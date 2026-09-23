from datetime import datetime, timedelta, timezone
import json
import os
import re
import unicodedata
import requests

from agents.financial import (
    get_financial_summary,
    get_available_budget,
    get_credit_cards_status,
    get_savings_goals,
    add_transaction,
)

from agents.secretary import (
    get_pending_tasks,
    add_task,
    complete_task,
    check_emails,
    draft_email,
    summarize_email,
)

from agents.agenda import (
    create_event,
    get_upcoming_events,
    delete_event,
)


# ============================================================
# CONFIGURACIÓN
# ============================================================

OLLAMA_URL = os.getenv("OLLAMA_CHAT_URL", "http://127.0.0.1:11434/api/chat")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:latest")

COLOMBIA_TZ = timezone(timedelta(hours=-5))


def get_colombia_now() -> datetime:
    return datetime.now(COLOMBIA_TZ)


# ============================================================
# DEFINICIÓN FORMAL DE HERRAMIENTAS (FUNCTION CALLING)
# ============================================================

TOOL_DEFINITIONS = [
    # --- FINANCIAL AGENT ---
    {
        "type": "function",
        "function": {
            "name": "get_financial_summary",
            "description": "Obtiene el balance general, gastos totales, ingresos y gastos por categoría del mes actual.",
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_available_budget",
            "description": "Calcula el dinero y presupuesto disponible libre para salir este fin de semana, semana o fin de mes, evaluando flujo de caja.",
            "parameters": {
                "type": "object",
                "properties": {
                    "timeframe": {
                        "type": "string",
                        "description": "Periodo consultado (ej. 'este fin de semana', 'hoy', 'fin de mes')",
                    }
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_credit_cards_status",
            "description": "Consulta el estado de tarjetas de crédito: cupo disponible, cupo utilizado, fecha de corte y pago.",
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_savings_goals",
            "description": "Consulta el avance y estado de metas y planes de ahorro del usuario (ej: fondo de emergencia, viaje académico).",
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "add_transaction",
            "description": "Registra una transacción manual de gasto o ingreso.",
            "parameters": {
                "type": "object",
                "properties": {
                    "amount": {"type": "number", "description": "Monto de la transacción"},
                    "merchant": {"type": "string", "description": "Comercio o concepto"},
                    "category": {"type": "string", "description": "Categoría del gasto"},
                    "is_income": {"type": "boolean", "description": "True si es ingreso, False si es gasto"},
                },
                "required": ["amount", "merchant"],
            },
        },
    },

    # --- SECRETARY AGENT ---
    {
        "type": "function",
        "function": {
            "name": "check_emails",
            "description": "Inspecciona y busca correos electrónicos del usuario. Úsalo para saber si alguien respondió (ej. 'Revisa si el decano me respondió el correo') o para listar correos no leídos.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Palabra clave, remitente o tema a buscar (ej: 'decano', 'profesor', 'taller')",
                    },
                    "unread_only": {
                        "type": "boolean",
                        "description": "True para mostrar solo no leídos",
                    },
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "draft_email",
            "description": "Redacta un borrador formal de correo electrónico (ej. excusa médica al profesor, solicitud formal, etc.).",
            "parameters": {
                "type": "object",
                "properties": {
                    "recipient": {"type": "string", "description": "Destinatario del correo"},
                    "subject": {"type": "string", "description": "Asunto del correo"},
                    "body": {"type": "string", "description": "Cuerpo o texto redactado de forma formal"},
                },
                "required": ["recipient", "subject", "body"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_pending_tasks",
            "description": "Obtiene la lista de tareas y pendientes del usuario desde la base de datos.",
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "add_task",
            "description": "Agrega una nueva tarea a la lista de pendientes del usuario en la base de datos.",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Título o descripción de la tarea"},
                    "description": {"type": "string", "description": "Detalles adicionales opcionales"},
                    "priority": {
                        "type": "string",
                        "enum": ["alta", "media", "baja"],
                        "description": "Prioridad; 'alta' si el usuario dice urgente o importante",
                    },
                    "category": {
                        "type": "string",
                        "enum": ["universidad", "trabajo", "personal", "proyecto"],
                        "description": "Área de la tarea (ej. un taller o parcial es 'universidad')",
                    },
                },
                "required": ["title"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "complete_task",
            "description": "Marca una tarea existente como completada en la base de datos.",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Título de la tarea a completar"},
                },
                "required": ["title"],
            },
        },
    },

    # --- AGENDA AGENT ---
    {
        "type": "function",
        "function": {
            "name": "get_upcoming_events",
            "description": "Consulta los eventos, citas y reuniones programadas en la agenda.",
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "schedule_event",
            "description": "Agenda un nuevo evento, reunión o cita indicando título, fecha y hora.",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "Título del evento o reunión"},
                    "date_description": {"type": "string", "description": "Fecha y hora (ej: 'mañana a las 3 pm', 'hoy a las 4 pm')"},
                },
                "required": ["title"],
            },
        },
    },
]

# Mapa de ejecución de funciones
TOOL_MAP = {
    "get_financial_summary": lambda **kwargs: get_financial_summary(),
    "get_available_budget": lambda **kwargs: get_available_budget(kwargs.get("timeframe", "este fin de semana")),
    "get_credit_cards_status": lambda **kwargs: get_credit_cards_status(),
    "get_savings_goals": lambda **kwargs: get_savings_goals(),
    "add_transaction": lambda **kwargs: add_transaction(
        amount=float(kwargs.get("amount", 0)),
        merchant=kwargs.get("merchant", "Gasto manual"),
        category=kwargs.get("category", "otros"),
        is_income=bool(kwargs.get("is_income", False)),
    ),
    "check_emails": lambda **kwargs: check_emails(
        query=kwargs.get("query"),
        unread_only=bool(kwargs.get("unread_only", False)),
    ),
    "draft_email": lambda **kwargs: draft_email(
        recipient=kwargs.get("recipient", "Destinatario"),
        subject=kwargs.get("subject", "Asunto"),
        body=kwargs.get("body", ""),
    ),
    "get_pending_tasks": lambda **kwargs: get_pending_tasks(),
    "add_task": lambda **kwargs: add_task(
        title=kwargs.get("title", ""),
        description=kwargs.get("description"),
        priority=kwargs.get("priority"),
        category=kwargs.get("category"),
    ),
    "complete_task": lambda **kwargs: complete_task(kwargs.get("title", "")),
    "get_upcoming_events": lambda **kwargs: _format_upcoming_events(),
    "schedule_event": lambda **kwargs: _schedule_event_helper(
        title=kwargs.get("title", "Reunión"),
        date_description=kwargs.get("date_description", "hoy"),
    ),
}

# Clasificación de herramientas por agente para reportar en la respuesta
AGENT_BY_TOOL = {
    "get_financial_summary": "financial",
    "get_available_budget": "financial",
    "get_credit_cards_status": "financial",
    "get_savings_goals": "financial",
    "add_transaction": "financial",
    "check_emails": "secretary",
    "draft_email": "secretary",
    "get_pending_tasks": "secretary",
    "add_task": "secretary",
    "complete_task": "secretary",
    "get_upcoming_events": "agenda",
    "schedule_event": "agenda",
}


# ============================================================
# AUXILIARES DE AGENDA
# ============================================================

def _format_upcoming_events() -> str:
    events = get_upcoming_events()
    if not events:
        return "No tienes eventos próximos agendados."

    lines = ["Tus próximos eventos son:"]
    for ev in events:
        try:
            st = datetime.fromisoformat(ev["start_date"].replace("Z", "+00:00"))
            st_col = st.astimezone(COLOMBIA_TZ)
            date_str = st_col.strftime("%d/%m a las %I:%M %p")
        except Exception:
            date_str = ev["start_date"]
        lines.append(f"• {ev['title']} — {date_str}")
    return "\n".join(lines)


def _schedule_event_helper(title: str, date_description: str) -> str:
    now = get_colombia_now()
    desc_low = date_description.lower()

    if "pasado mañana" in desc_low:
        target_date = now + timedelta(days=2)
    elif "mañana" in desc_low:
        target_date = now + timedelta(days=1)
    else:
        target_date = now

    # Extraer hora
    hour = 12
    m = re.search(r"(\d{1,2})\s*(?:de la tarde|pm|p\.m\.)", desc_low)
    if m:
        h = int(m.group(1))
        hour = h + 12 if h < 12 else h
    else:
        m2 = re.search(r"(\d{1,2})\s*(?:de la mañana|am|a\.m\.)", desc_low)
        if m2:
            hour = int(m2.group(1))
        else:
            m3 = re.search(r"(\d{1,2}):(\d{2})", desc_low)
            if m3:
                hour = int(m3.group(1))

    event_dt = target_date.replace(hour=hour, minute=0, second=0, microsecond=0)
    utc_dt = event_dt.astimezone(timezone.utc)

    ev = create_event(title=title, start_date=utc_dt)
    formatted = event_dt.strftime("%d/%m/%Y a las %I:%M %p")
    return f"Evento agendado exitosamente: '{ev['title']}' para el {formatted}."


# ============================================================
# LLAMADA A OLLAMA
# ============================================================

def _call_ollama_chat(messages: list, tools: list | None = None) -> dict | None:
    payload = {
        "model": OLLAMA_MODEL,
        "messages": messages,
        "stream": False,
    }
    if tools:
        payload["tools"] = tools

    try:
        res = requests.post(OLLAMA_URL, json=payload, timeout=45)
        if res.status_code == 200:
            return res.json().get("message")
    except Exception as e:
        print(f"Error llamando a Ollama: {e}")
    return None


def _call_ollama_synthesis(system_prompt: str, user_prompt: str) -> str:
    try:
        res = requests.post(
            OLLAMA_URL,
            json={
                "model": OLLAMA_MODEL,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "stream": False,
            },
            timeout=40,
        )
        if res.status_code == 200:
            return res.json()["message"]["content"].strip()
    except Exception as e:
        print(f"Error en síntesis con Ollama: {e}")
    return ""


# ============================================================
# ENRUTAMIENTO SEMÁNTICO DE RESPALDO (SAFETY HEURISTICS)
# ============================================================

def _normalize(text: str) -> str:
    """Minúsculas y sin tildes/signos: 'Cuánto' → 'cuanto', '¿crédito?' → 'credito'."""
    decomposed = unicodedata.normalize("NFD", text.lower())
    without_accents = "".join(c for c in decomposed if unicodedata.category(c) != "Mn")
    return re.sub(r"[¿?¡!.,;:]", " ", without_accents).strip()


def _parse_tool_args(raw) -> dict:
    """
    Ollama puede entregar los argumentos como dict, como string JSON o (llama3.2)
    envueltos en {"type": ..., "function": ..., "parameters": {...}}.
    """
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return {}
    if not isinstance(raw, dict):
        return {}
    if isinstance(raw.get("parameters"), dict):
        return raw["parameters"]
    return raw


def _fallback_intent_detection(text: str) -> list[tuple[str, dict]]:
    """
    Si Ollama no emite tool_calls directamente, este enrutador
    identifica de forma determinista la intención para garantizar
    que las peticiones clave del taller se resuelvan al 100%.
    """
    text_low = _normalize(text)
    invocations = []

    # 1. ¿Revisa si el decano me respondió el correo? / Correos
    if any(k in text_low for k in ["decano", "correo", "email", "buzon", "mensaje"]):
        query = next((k for k in ("decano", "profesor", "banco") if k in text_low), None)
        invocations.append((
            "check_emails",
            {"query": query, "unread_only": "no leido" in text_low or "nuevos" in text_low},
        ))

    # 2. ¿Cuánto dinero me queda disponible para salir este fin de semana? / Presupuesto
    if any(k in text_low for k in ["disponible para salir", "fin de semana", "cuanto dinero me queda", "liquidez"]):
        invocations.append(("get_available_budget", {"timeframe": "este fin de semana"}))
    elif any(k in text_low for k in ["gaste", "gastos", "saldo", "balance", "cuanto dinero tengo", "finanzas"]):
        invocations.append(("get_financial_summary", {}))

    # 3. Tarjetas de crédito
    if any(k in text_low for k in ["tarjeta", "tarjetas", "cupo", "credito"]):
        invocations.append(("get_credit_cards_status", {}))

    # 4. Metas de ahorro
    if any(k in text_low for k in ["ahorro", "metas", "meta"]):
        invocations.append(("get_savings_goals", {}))

    # 5. Tareas: agregar
    if any(k in text_low for k in ["agrega una tarea", "crea una tarea", "agregar tarea", "anota que debo"]):
        m = re.search(r"(?:tarea llamada|tarea de|tarea|que debo)\s+(.+?)(?:\s+y\s+|\s+dime\s+|$)", text_low)
        title = m.group(1).strip() if m else "Nueva tarea"
        invocations.append(("add_task", {"title": title}))
    # Tareas: consultar
    elif any(k in text_low for k in ["tareas", "pendientes", "que tengo que hacer", "que debo hacer"]):
        invocations.append(("get_pending_tasks", {}))

    # 6. Agenda: agendar
    if any(k in text_low for k in ["agenda una", "agendar", "programa una", "crea una cita", "crear evento"]):
        invocations.append(("schedule_event", {"title": "Reunión", "date_description": text}))
    elif any(k in text_low for k in ["que tengo hoy", "que tengo manana", "ver mi agenda", "proximos eventos", "mis citas"]):
        invocations.append(("get_upcoming_events", {}))

    return invocations


SYNTHESIS_SYSTEM_PROMPT = (
    "Eres GUTI, el asistente personal por voz de un estudiante universitario en Colombia. "
    "Recibirás la pregunta del usuario y los datos reales ya consultados en su base de datos. "
    "Responde la pregunta usando esos datos, en español, hablándole de tú al usuario "
    "(por ejemplo: 'te quedan 225.000 pesos', 'el decano te respondió'). "
    "Reglas: máximo 4 oraciones; sin saludos, disculpas ni relleno; sin markdown, viñetas ni asteriscos; "
    "si los datos cubren varios temas (finanzas y tareas o correos), responde todos. "
    "Tienes acceso completo a los datos: nunca digas que no puedes acceder a ellos."
)

REFUSAL_PATTERNS = (
    "no tengo acceso", "no puedo acceder", "no puedo proporcionar",
    "no tengo informacion", "no tengo información", "como modelo de lenguaje",
)


def _looks_like_refusal(answer: str) -> bool:
    low = answer.lower()
    return any(p in low for p in REFUSAL_PATTERNS)


# ============================================================
# PROCESAR COMANDO (ORCHESTRATOR PRINCIPAL)
# ============================================================

def process_command(text: str) -> dict:
    """
    Punto de entrada principal para el enrutamiento de intenciones y
    ejecución multi-agente con Function Calling.
    Devuelve: {"response": str, "agent": str}
    """
    text = text.strip()
    if not text:
        return {"response": "No recibí ningún comando.", "agent": "general"}

    print("\n" + "=" * 60)
    print("🤖 GUTI ORCHESTRATOR (Function Calling Mode)")
    print("=" * 60)
    print(f"📥 Comando recibido: '{text}'")

    system_instruction = (
        "Eres GUTI, un asistente personal inteligente para un estudiante universitario en Colombia. "
        "Cuentas con dos agentes especializados: Agente de Secretaría (correos, tareas y agenda) "
        "y Agente Financiero (finanzas, flujo de caja, tarjetas y ahorros). "
        "Usa las herramientas disponibles para consultar o modificar información real. "
        "Responde de forma concisa, cálida, natural y directa en español. "
        "Nunca menciones herramientas internas, JSON, ni aspectos técnicos."
    )

    messages = [
        {"role": "system", "content": system_instruction},
        {"role": "user", "content": text},
    ]

    # Paso 1: Intentar Function Calling nativo con Ollama
    assistant_msg = _call_ollama_chat(messages, tools=TOOL_DEFINITIONS)
    tool_calls = assistant_msg.get("tool_calls") if assistant_msg else None

    executed_tools = []
    tool_results = []
    agents_involved = set()

    if tool_calls:
        print(f"🧠 Ollama detectó {len(tool_calls)} Tool Call(s):")
        for tc in tool_calls:
            fn = tc.get("function", {})
            fn_name = fn.get("name")
            fn_args = _parse_tool_args(fn.get("arguments", {}))
            print(f"   ⚙️ Invocando herramienta: {fn_name} con {fn_args}")

            executor = TOOL_MAP.get(fn_name)
            if executor:
                try:
                    res = executor(**fn_args)
                    executed_tools.append(fn_name)
                    tool_results.append((fn_name, res))
                    agent_name = AGENT_BY_TOOL.get(fn_name, "general")
                    agents_involved.add(agent_name)
                except Exception as err:
                    print(f"   ❌ Error ejecutando {fn_name}: {err}")

    # Paso 2: Complementar con el enrutador semántico.
    # - Si Ollama no disparó nada, se usan todas las intenciones detectadas.
    # - Si ya disparó algo, solo se agregan consultas (no mutaciones) que el LLM
    #   haya omitido, para que preguntas mixtas (finanzas + tareas) cubran ambos agentes.
    mutation_tools = {"schedule_event", "add_task", "complete_task", "add_transaction", "draft_email"}
    fallback_invocations = [
        (fn_name, fn_args)
        for fn_name, fn_args in _fallback_intent_detection(text)
        if fn_name not in executed_tools
        and (not executed_tools or fn_name not in mutation_tools)
    ]
    if fallback_invocations:
        print(f"🔍 Enrutador semántico agregó: {fallback_invocations}")
        for fn_name, fn_args in fallback_invocations:
            executor = TOOL_MAP.get(fn_name)
            if executor:
                try:
                    res = executor(**fn_args)
                    executed_tools.append(fn_name)
                    tool_results.append((fn_name, res))
                    agents_involved.add(AGENT_BY_TOOL.get(fn_name, "general"))
                except Exception as err:
                    print(f"   ❌ Error en fallback {fn_name}: {err}")

    # Paso 3: Generar la respuesta final al usuario
    if executed_tools:
        # Determinar agente asignado
        if len(agents_involved) > 1:
            primary_agent = "multi-agent"
        elif len(agents_involved) == 1:
            primary_agent = list(agents_involved)[0]
        else:
            primary_agent = "general"

        # Si fue una sola acción directa de modificación, responder directamente con éxito garantizado
        if len(executed_tools) == 1 and executed_tools[0] in mutation_tools:
            direct_response = tool_results[0][1]
            print(f"📤 Respuesta directa de acción ({primary_agent}): {direct_response}\n")
            return {"response": str(direct_response), "agent": primary_agent}

        # Construir contexto con los resultados de las herramientas reales
        context_blocks = []
        for fn_name, result in tool_results:
            context_blocks.append(f"[{fn_name.upper()}]:\n{result}")
        joined_context = "\n\n".join(context_blocks)

        synthesis_prompt = (
            f"Pregunta del usuario: {text}\n\n"
            f"Datos reales de GUTI:\n{joined_context}"
        )
        final_answer = _call_ollama_synthesis(
            system_prompt=SYNTHESIS_SYSTEM_PROMPT,
            user_prompt=synthesis_prompt,
        )

        # Los modelos pequeños a veces niegan tener acceso aunque recibieron los datos.
        if final_answer and _looks_like_refusal(final_answer):
            print(f"⚠️ Síntesis descartada por negarse a responder: {final_answer}")
            final_answer = ""

        if not final_answer:
            final_answer = "\n\n".join(str(res) for _, res in tool_results)

        print(f"📤 Respuesta generada ({primary_agent}): {final_answer}\n")
        return {"response": final_answer, "agent": primary_agent}

    # Si es una conversación libre o general
    general_answer = assistant_msg.get("content", "") if assistant_msg else ""
    if not general_answer:
        general_answer = _call_ollama_synthesis(
            system_prompt="Eres GUTI, un asistente personal inteligente y amigable en español.",
            user_prompt=text,
        )

    if not general_answer:
        general_answer = "Hola, soy GUTI. ¿En qué te puedo ayudar hoy con tus finanzas, tareas o agenda?"

    return {"response": general_answer, "agent": "general"}