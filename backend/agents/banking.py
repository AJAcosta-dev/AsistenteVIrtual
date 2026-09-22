from datetime import datetime, timezone
import json
import os
import re
import requests


OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434/api/generate")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2")


def _extract_amount_regex(text: str) -> float | None:
    """
    Intenta extraer montos colombianos con regex tolerante:
    - $42.500 COP
    - $ 150.000
    - 42.500 COP
    - 1.250.000 pesos
    - 85000
    """
    # 1. Con símbolo $
    m = re.search(r"\$\s*([0-9]{1,3}(?:\.[0-9]{3})*(?:,[0-9]+)?)", text)
    if not m:
        # 2. Con palabra COP o pesos
        m = re.search(r"([0-9]{1,3}(?:\.[0-9]{3})*(?:,[0-9]+)?)\s*(?:COP|pesos)", text, re.IGNORECASE)
    if not m:
        # 3. Número de al menos 4 dígitos con punto de miles (ej: 45.000)
        m = re.search(r"\b([0-9]{1,3}\.[0-9]{3}(?:\.[0-9]{3})*)\b", text)

    if m:
        val_str = m.group(1).replace(".", "")
        if "," in val_str:
            val_str = val_str.replace(",", ".")
        try:
            val = float(val_str)
            if val > 0:
                return val
        except ValueError:
            pass

    return None


INCOME_PATTERNS = [
    r"\brecibiste\b", r"\bte (?:enviaron|consignaron|transfirieron|abonaron)\b",
    r"\babono\b", r"\bconsignaci[oó]n\b", r"\bpago de n[oó]mina\b",
    r"\bdep[oó]sito recibido\b", r"\bingreso\b",
]


def is_income_notification(text: str) -> bool:
    """Detecta si la notificación bancaria corresponde a dinero recibido."""
    low = text.lower()
    return any(re.search(pattern, low) for pattern in INCOME_PATTERNS)


def extract_bank_transaction(text: str) -> dict:
    """
    Extrae la información estructurada de una notificación o extracto bancario
    utilizando el LLM con Structured Output (JSON) y validación complementaria.
    """
    today_str = datetime.now().strftime("%Y-%m-%d")

    # Intentar extracción rápida de monto por regex
    amount_from_regex = _extract_amount_regex(text)

    prompt = f"""Eres un motor especializado en extraer y clasificar transacciones bancarias colombianas.
Analiza la siguiente notificación bancaria y responde EXCLUSIVAMENTE con un objeto JSON válido con los datos de la compra.

Texto recibido:
"{text}"

Fecha de hoy de referencia: {today_str}

Formato obligatorio de respuesta:
{{
    "amount": 0.0,
    "currency": "COP",
    "merchant": "nombre limpio del comercio",
    "date": "YYYY-MM-DD",
    "payment_method": "tarjeta / debito / credito / transferencia / desconocido",
    "category": "alimentación / transporte / entretenimiento / salud / educación / hogar / tecnología / compras / servicios / viajes / otros"
}}

Reglas estrictas:
1. "amount": número flotante del valor total sin puntos de miles (ej. 42500.0).
2. "merchant": nombre del establecimiento (ej. "Exito", "Crepes & Waffles", "Uber", "Starbucks").
3. "category": debe ser una de las categorías válidas. Si es comida o supermercado usa "alimentación" o "comida".
4. "date": formato YYYY-MM-DD. Si no tiene año, usa {today_str}.
5. Responde ÚNICAMENTE el JSON sin explicaciones ni markdown.
"""

    extracted = None

    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
                "format": "json",
            },
            timeout=30,
        )
        if response.status_code == 200:
            raw_response = response.json().get("response", "").strip()
            # Intentar decodificar JSON
            try:
                extracted = json.loads(raw_response)
            except json.JSONDecodeError:
                m = re.search(r"\{.*\}", raw_response, re.DOTALL)
                if m:
                    extracted = json.loads(m.group(0))
    except Exception as e:
        print(f"Aviso: Ollama no respondió o falló la extracción LLM: {e}")

    # Fallback o complementación si Ollama no devolvió JSON completo
    if not isinstance(extracted, dict):
        extracted = {}

    # Determinar monto final
    final_amount = amount_from_regex
    if final_amount is None:
        try:
            candidate = float(extracted.get("amount", 0))
            if candidate > 0:
                final_amount = candidate
        except (ValueError, TypeError):
            pass

    if final_amount is None or final_amount <= 0:
        raise ValueError(f"No se pudo determinar el monto de la transacción en: {text}")

    # Determinar comercio
    merchant = str(extracted.get("merchant", "")).strip()
    if not merchant or merchant.lower() in ["comercio", "desconocido", "none", "null"]:
        # Heurística de respaldo para comercios comunes
        common_merchants = [
            "Crepes & Waffles", "Exito", "Éxito", "Carulla", "Jumbo", "D1", "Ara",
            "Uber", "Didi", "Rappi", "Starbucks", "McDonald", "Farmatodo", "Netflix", "Spotify"
        ]
        merchant = "Comercio"
        for cm in common_merchants:
            if cm.lower() in text.lower():
                merchant = cm
                break

    # Categoría
    allowed_categories = {
        "alimentación", "comida", "transporte", "entretenimiento",
        "salud", "educación", "hogar", "tecnología", "compras", "servicios", "viajes", "otros"
    }
    category = str(extracted.get("category", "otros")).strip().lower()
    if category not in allowed_categories:
        category = "otros"

    # Fecha
    date_str = str(extracted.get("date", today_str)).strip()
    try:
        t_date = datetime.strptime(date_str[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except Exception:
        t_date = datetime.now(timezone.utc)

    # Método de pago
    payment_method = str(extracted.get("payment_method", "tarjeta")).strip()

    return {
        "amount": float(final_amount),
        "currency": "COP",
        "merchant": merchant,
        "date": t_date.isoformat(),
        "payment_method": payment_method,
        "category": category,
    }