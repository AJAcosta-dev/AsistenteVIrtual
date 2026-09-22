from datetime import datetime, timezone
import json
import os
from uuid import uuid4

from supabase_client import insert_with_fallback, supabase


# ============================================================
# DATOS FINANCIEROS COMPLEMENTARIOS (Persistencia local/Supabase)
# ============================================================

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
FINANCIAL_PROFILE_PATH = os.path.join(DATA_DIR, "financial_profile.json")


def _get_financial_profile() -> dict:
    """
    Carga el perfil financiero (tarjetas, presupuesto proyectado).
    Si no existe, crea un perfil inicial con valores representativos.
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    if os.path.exists(FINANCIAL_PROFILE_PATH):
        try:
            with open(FINANCIAL_PROFILE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass

    default_profile = {
        "monthly_budget": 1500000.0,
        "fixed_obligations": 600000.0,
        "credit_cards": [
            {
                "bank": "Bancolombia",
                "card_name": "Mastercard Joven",
                "total_limit": 2000000.0,
                "used_amount": 450000.0,
                "cutoff_date": "15 de cada mes",
                "due_date": "05 del próximo mes",
                "interest_rate": "24.5% E.A.",
            },
            {
                "bank": "Nu Colombia",
                "card_name": "Nu Moradita",
                "total_limit": 1200000.0,
                "used_amount": 180000.0,
                "cutoff_date": "22 de cada mes",
                "due_date": "02 del próximo mes",
                "interest_rate": "23.9% E.A.",
            },
        ],
    }

    try:
        with open(FINANCIAL_PROFILE_PATH, "w", encoding="utf-8") as f:
            json.dump(default_profile, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Advertencia guardando perfil financiero: {e}")

    return default_profile


def get_financial_summary() -> str:
    """
    Obtiene el resumen financiero consolidado del mes actual desde Supabase.
    """
    now = datetime.now(timezone.utc)
    current_month = now.month
    current_year = now.year

    try:
        result = (
            supabase.table("transactions")
            .select("*")
            .eq("month", current_month)
            .eq("year", current_year)
            .execute()
        )
        transactions = result.data or []
    except Exception as e:
        print(f"Error consultando transacciones en Supabase: {e}")
        transactions = []

    total_expenses = sum(
        t["amount"] for t in transactions if not t.get("is_income", False)
    )
    total_income = sum(
        t["amount"] for t in transactions if t.get("is_income", False)
    )
    balance = total_income - total_expenses

    category_totals = {}
    for transaction in transactions:
        if transaction.get("is_income", False):
            continue
        category = transaction.get("category", "otros")
        amount = transaction["amount"]
        category_totals[category] = category_totals.get(category, 0) + amount

    summary = (
        "RESUMEN FINANCIERO DEL MES:\n"
        f"• Ingresos registrados: ${total_income:,.0f} COP\n"
        f"• Gastos totales: ${total_expenses:,.0f} COP\n"
        f"• Balance neto: ${balance:,.0f} COP\n"
    )

    if category_totals:
        summary += "\nGastos por categoría:\n"
        for category, amount in sorted(
            category_totals.items(), key=lambda item: item[1], reverse=True
        ):
            summary += f"  - {category.capitalize()}: ${amount:,.0f} COP\n"

    return summary.strip()


def get_available_budget(timeframe: str = "este fin de semana") -> str:
    """
    Calcula el flujo de caja dinámico y la liquidez disponible para un periodo
    específico (ej. 'este fin de semana', 'semana actual' o 'fin de mes').
    """
    now = datetime.now(timezone.utc)
    profile = _get_financial_profile()

    try:
        result = (
            supabase.table("transactions")
            .select("*")
            .eq("month", now.month)
            .eq("year", now.year)
            .execute()
        )
        transactions = result.data or []
    except Exception:
        transactions = []

    total_expenses = sum(
        t["amount"] for t in transactions if not t.get("is_income", False)
    )
    total_income = sum(
        t["amount"] for t in transactions if t.get("is_income", False)
    )

    effective_income = total_income if total_income > 0 else profile.get("monthly_budget", 1500000.0)
    fixed_obligations = profile.get("fixed_obligations", 600000.0)

    discretionary_budget = effective_income - fixed_obligations - total_expenses
    if discretionary_budget < 0:
        discretionary_budget = 0.0

    weekend_budget = round(discretionary_budget * 0.25, -3)

    response = (
        f"ANÁLISIS DE FLUJO DE CAJA ({timeframe.upper()}):\n"
        f"• Ingresos/Presupuesto base: ${effective_income:,.0f} COP\n"
        f"• Obligaciones fijas proyectadas: ${fixed_obligations:,.0f} COP\n"
        f"• Gastos acumulados en el mes: ${total_expenses:,.0f} COP\n"
        f"• Liquidez libre restante para el mes: ${discretionary_budget:,.0f} COP\n"
        f"• Presupuesto sugerido disponible para {timeframe}: ${weekend_budget:,.0f} COP."
    )
    return response


def _get_credit_cards() -> list[dict]:
    """
    Tarjetas desde Supabase (tabla credit_cards). Si la tabla aún no existe,
    usa el perfil local data/financial_profile.json.
    """
    try:
        result = supabase.table("credit_cards").select("*").order("bank").execute()
        if result.data:
            return [
                {
                    "bank": c["bank"],
                    "card_name": c["card_name"],
                    "total_limit": float(c["total_limit"]),
                    "used_amount": float(c["used_amount"]),
                    "cutoff_date": f"{c['cutoff_day']} de cada mes",
                    "due_date": f"{c['due_day']:02d} del próximo mes",
                    "interest_rate": f"{float(c['interest_rate_ea'])}% E.A.",
                }
                for c in result.data
            ]
    except Exception as e:
        print(f"Aviso: credit_cards no disponible en Supabase, usando perfil local ({e})")
    return _get_financial_profile().get("credit_cards", [])


def _monthly_interest(used_amount: float, rate_label: str) -> float:
    """Interés estimado de un mes: tasa E.A. convertida a mensual vencida."""
    try:
        ea = float(rate_label.split("%")[0].replace(",", ".")) / 100
    except (ValueError, IndexError):
        return 0.0
    monthly_rate = (1 + ea) ** (1 / 12) - 1
    return used_amount * monthly_rate


def get_credit_cards_status() -> str:
    """
    Obtiene el estado de las tarjetas de crédito, incluyendo el interés
    estimado si se difiere el saldo utilizado.
    """
    cards = _get_credit_cards()

    if not cards:
        return "No tienes tarjetas de crédito registradas."

    summary = "ESTADO DE TARJETAS DE CRÉDITO:\n"
    for card in cards:
        available = card["total_limit"] - card["used_amount"]
        usage_pct = (card["used_amount"] / card["total_limit"]) * 100
        interest = _monthly_interest(card["used_amount"], card["interest_rate"])
        summary += (
            f"• {card['bank']} ({card['card_name']}):\n"
            f"  - Cupo utilizado: ${card['used_amount']:,.0f} COP ({usage_pct:.1f}%)\n"
            f"  - Cupo disponible: ${available:,.0f} COP de ${card['total_limit']:,.0f} COP\n"
            f"  - Fecha de corte: {card['cutoff_date']}\n"
            f"  - Fecha límite de pago: {card['due_date']}\n"
            f"  - Tasa: {card['interest_rate']} (interés estimado si difieres: ${interest:,.0f} COP/mes)\n"
        )
    return summary.strip()


# ============================================================
# METAS DE AHORRO — CRUD EN SUPABASE
# ============================================================

def get_savings_goals_list() -> list[dict]:
    """Retorna todas las metas de ahorro como lista de dicts."""
    try:
        result = (
            supabase.table("savings_goals")
            .select("*")
            .order("created_at", desc=False)
            .execute()
        )
        return result.data or []
    except Exception as e:
        print(f"Error leyendo savings_goals: {e}")
        return []


def get_savings_goals() -> str:
    """
    Obtiene el progreso porcentual y montos de las metas de ahorro (para el agente).
    """
    goals = get_savings_goals_list()

    if not goals:
        return "No tienes metas de ahorro registradas."

    summary = "PLANES Y METAS DE AHORRO:\n"
    for goal in goals:
        target = float(goal["target_amount"])
        current = float(goal["current_amount"])
        progress_pct = (current / target * 100) if target > 0 else 0.0
        remaining = target - current
        emoji = goal.get("emoji", "🎯")
        summary += (
            f"• {emoji} {goal['name']} ({goal['category']}):\n"
            f"  - Ahorrado: ${current:,.0f} COP de ${target:,.0f} COP ({progress_pct:.1f}%)\n"
            f"  - Faltante: ${remaining:,.0f} COP\n"
        )
    return summary.strip()


def create_savings_goal(
    name: str,
    target_amount: float,
    category: str = "general",
    emoji: str = "🎯",
    target_date: str | None = None,
) -> dict:
    """Crea una nueva meta de ahorro en Supabase."""
    record = {
        "id": str(uuid4()),
        "name": name,
        "target_amount": target_amount,
        "current_amount": 0.0,
        "category": category,
        "emoji": emoji,
    }
    if target_date:
        record["target_date"] = target_date

    result = supabase.table("savings_goals").insert(record).execute()
    if not result.data:
        raise RuntimeError("No se pudo crear la meta de ahorro en Supabase.")
    return result.data[0]


def deposit_to_goal(goal_id: str, amount: float) -> dict:
    """
    Agrega un depósito a una meta de ahorro existente.
    Suma el monto al current_amount sin exceder target_amount.
    """
    # Leer el estado actual
    res = supabase.table("savings_goals").select("*").eq("id", goal_id).execute()
    if not res.data:
        raise ValueError(f"Meta con id={goal_id} no encontrada.")

    goal = res.data[0]
    new_amount = min(
        float(goal["current_amount"]) + amount,
        float(goal["target_amount"]),
    )

    update_res = (
        supabase.table("savings_goals")
        .update({"current_amount": new_amount})
        .eq("id", goal_id)
        .execute()
    )
    if not update_res.data:
        raise RuntimeError("No se pudo actualizar la meta de ahorro.")

    # Historial de abonos (tabla goal_deposits); no bloquea si aún no existe.
    try:
        supabase.table("goal_deposits").insert({"goal_id": goal_id, "amount": amount}).execute()
    except Exception as e:
        print(f"Aviso: no se registró el abono en goal_deposits ({e})")

    return update_res.data[0]


def delete_savings_goal(goal_id: str) -> bool:
    """Elimina una meta de ahorro de Supabase."""
    result = (
        supabase.table("savings_goals")
        .delete()
        .eq("id", goal_id)
        .execute()
    )
    return bool(result.data)


# ============================================================
# TRANSACCIONES
# ============================================================

def create_transaction(
    amount: float,
    merchant: str,
    category: str,
    is_income: bool = False,
    transaction_date: datetime | None = None,
    source: str = "manual",
    payment_method: str | None = None,
    currency: str = "COP",
):
    """Crea una transacción en Supabase."""
    if amount <= 0:
        raise ValueError("El monto de la transacción debe ser mayor a cero.")

    if transaction_date is None:
        transaction_date = datetime.now(timezone.utc)
    elif transaction_date.tzinfo is None:
        transaction_date = transaction_date.replace(tzinfo=timezone.utc)

    transaction = {
        "id": str(uuid4()),
        "amount": amount,
        "merchant": merchant,
        "category": category,
        "date": transaction_date.isoformat(),
        "month": transaction_date.month,
        "year": transaction_date.year,
        "is_income": is_income,
        "source": source,
        "payment_method": payment_method,
        "currency": currency,
    }

    return insert_with_fallback(
        "transactions",
        transaction,
        optional_keys={"source", "payment_method", "currency"},
    )


def add_transaction(
    amount: float,
    merchant: str,
    category: str,
    is_income: bool = False,
) -> str:
    """Registro por voz: devuelve una confirmación legible para TTS."""
    create_transaction(
        amount=amount,
        merchant=merchant,
        category=category,
        is_income=is_income,
        source="voz",
    )
    kind = "Ingreso" if is_income else "Gasto"
    return f"{kind} registrado: ${amount:,.0f} COP en {merchant} ({category})."


def delete_transaction(transaction_id: str):
    clean_id = transaction_id.strip().lower()
    result = (
        supabase.table("transactions")
        .delete()
        .eq("id", clean_id)
        .execute()
    )
    if result.data:
        return True

    result_upper = (
        supabase.table("transactions")
        .delete()
        .eq("id", transaction_id.strip())
        .execute()
    )
    return bool(result_upper.data)