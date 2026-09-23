from datetime import datetime, timezone
import json
import os
from uuid import uuid4

from supabase_client import execute_with_fallback, insert_with_fallback, supabase
from agents import mailbox


# ============================================================
# PERSISTENCIA LOCAL DE CORREOS / BUZÓN INTELIGENTE
# ============================================================

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
EMAILS_FILE_PATH = os.path.join(DATA_DIR, "emails.json")


def _get_emails_store() -> dict:
    """
    Carga el buzón de correos electrónicos. Si no existe, inicializa
    con correos realistas requeridos para el taller (Decano, Profesores, etc.).
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    if os.path.exists(EMAILS_FILE_PATH):
        try:
            with open(EMAILS_FILE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass

    now_iso = datetime.now(timezone.utc).isoformat()
    default_store = {
        "inbox": [
            {
                "id": "email-decano-001",
                "sender": "Decanatura de Ingeniería <decanatura.ingenieria@universidad.edu.co>",
                "sender_name": "Decano Roberto Mendoza",
                "recipient": "estudiante@universidad.edu.co",
                "subject": "Respuesta: Aprobación de prórroga para entrega de Proyecto GUTI",
                "snippet": "Estimado estudiante, he revisado su solicitud. Se autoriza la sustentación técnica del asistente multi-agente...",
                "body": (
                    "Estimado estudiante,\n\n"
                    "He revisado detenidamente su comunicación respecto al desarrollo del Asistente Personal GUTI con "
                    "control por voz y conectividad Tailscale. Le confirmo que la fecha de sustentación del segundo corte "
                    "ha quedado ratificada y su avance técnico cumple con los requerimientos esperados para la evaluación.\n\n"
                    "Por favor asegúrese de tener configurado el webhook bancario y la demostración de los agentes en vivo.\n\n"
                    "Atentamente,\n"
                    "Dr. Roberto Mendoza\n"
                    "Decano de la Facultad de Ingeniería"
                ),
                "date": now_iso,
                "is_read": False,
                "is_urgent": True,
            },
            {
                "id": "email-prof-moviles-002",
                "sender": "Profesor Carlos Gómez <carlos.gomez@universidad.edu.co>",
                "sender_name": "Profesor Carlos Gómez",
                "recipient": "estudiante@universidad.edu.co",
                "subject": "Rúbrica y Lineamientos Taller Segundo Corte - Aplicaciones Móviles",
                "snippet": "Recordatorio sobre los criterios de evaluación: App nativa, orquestador multi-agente, VPN Mesh Tailscale...",
                "body": (
                    "Apreciados estudiantes,\n\n"
                    "Recuerden que para la entrega de este segundo corte se evaluará rigurosamente el funcionamiento "
                    "del orquestador backend con Function Calling, la persistencia en Supabase y la ingesta cero fricción "
                    "mediante Apple Shortcuts o Android listeners a través de la IP de Tailscale.\n\n"
                    "Muchos éxitos en la entrega."
                ),
                "date": now_iso,
                "is_read": True,
                "is_urgent": False,
            },
        ],
        "drafts": [],
        "sent": [],
    }

    try:
        with open(EMAILS_FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(default_store, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Advertencia guardando emails: {e}")

    return default_store


def _cache_emails(emails: list[dict]):
    """Guarda en Supabase los correos leídos por IMAP (para borradores/tareas con FK)."""
    try:
        rows = [{k: v for k, v in e.items() if k != "body" or v} for e in emails if e.get("date")]
        if rows:
            supabase.table("emails").upsert(rows).execute()
    except Exception as e:
        print(f"Aviso: no se pudieron cachear correos en Supabase ({e})")


def _get_inbox(unread_only: bool = False) -> list[dict]:
    """
    Orden de fuentes:
      1. Buzón real por IMAP (si MAIL_ADDRESS y MAIL_APP_PASSWORD están en .env).
      2. Tabla emails de Supabase.
      3. Buzón local data/emails.json (demo sin conexión).
    """
    if mailbox.is_configured():
        try:
            emails = mailbox.fetch_inbox(unread_only=unread_only)
            _cache_emails(emails)
            return emails
        except Exception as e:
            print(f"Aviso: IMAP no disponible, usando respaldo ({e})")

    try:
        result = supabase.table("emails").select("*").order("date", desc=True).execute()
        if result.data:
            return result.data
    except Exception as e:
        print(f"Aviso: tabla emails no disponible, usando buzón local ({e})")
    return _get_emails_store().get("inbox", [])


def _save_emails_store(store: dict):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(EMAILS_FILE_PATH, "w", encoding="utf-8") as f:
        json.dump(store, f, indent=2, ensure_ascii=False)


# ============================================================
# FUNCIONES DE CORREO ELECTRÓNICO (SECRETARY AGENT)
# ============================================================

def check_emails(query: str | None = None, unread_only: bool = False) -> str:
    """
    Inspecciona la bandeja de entrada para listar o buscar correos.
    Permite filtrar por remitente o tema (ej. 'decano', 'profesor', 'taller').
    """
    inbox = _get_inbox(unread_only=unread_only)

    if unread_only:
        inbox = [m for m in inbox if not m.get("is_read", False)]

    if query:
        q = query.lower()
        matched = [
            m for m in inbox
            if q in (m.get("sender") or "").lower()
            or q in (m.get("sender_name") or "").lower()
            or q in (m.get("subject") or "").lower()
            or q in (m.get("body") or "").lower()
        ]
    else:
        matched = inbox[:10]

    # Prioriza remitentes urgentes y no leídos.
    matched.sort(key=lambda m: (not m.get("is_urgent"), bool(m.get("is_read"))))

    if not matched:
        if query:
            return f"No se encontraron correos relacionados con '{query}'."
        return "No tienes correos nuevos en la bandeja de entrada."

    # Con pocos resultados se incluye el cuerpo completo para que GUTI pueda resumir el hilo.
    include_body = len(matched) <= 3

    response = f"Encontré {len(matched)} correo(s):\n"
    for email in matched:
        estado = "No leído (Urgente)" if not email.get("is_read") and email.get("is_urgent") else (
            "No leído" if not email.get("is_read") else "Leído"
        )
        response += (
            f"\n📨 De: {email.get('sender_name', email.get('sender'))}\n"
            f"   Asunto: {email.get('subject')}\n"
            f"   Estado: {estado}\n"
            f"   Fecha: {(email.get('date') or '')[:10]}\n"
        )
        if include_body and email.get("body"):
            response += f"   Cuerpo: {email['body'][:1500]}\n"
        else:
            response += f"   Contenido: {email.get('snippet') or (email.get('body') or '')[:140]}\n"

    return response.strip()


def draft_email(recipient: str, subject: str, body: str) -> str:
    """
    Crea y almacena un borrador de correo electrónico basado en las instrucciones del usuario
    (ej. redacción de excusa médica o respuesta formal a un profesor).
    """
    draft = {
        "id": f"draft-{uuid4()}",
        "recipient": recipient,
        "subject": subject,
        "body": body,
        "status": "borrador",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    saved_in_gmail = False
    if mailbox.is_configured():
        try:
            mailbox.save_draft(recipient, subject, body)
            saved_in_gmail = True
        except Exception as e:
            print(f"Aviso: no se pudo guardar el borrador en el buzón real ({e})")

    try:
        supabase.table("email_drafts").insert(draft).execute()
    except Exception as e:
        print(f"Aviso: tabla email_drafts no disponible, guardando en local ({e})")
        store = _get_emails_store()
        store.setdefault("drafts", []).append(draft)
        _save_emails_store(store)

    return (
        f"Borrador creado exitosamente:\n"
        f"• Para: {recipient}\n"
        f"• Asunto: {subject}\n"
        f"• Cuerpo:\n\"{body}\"\n\n"
        + ("Quedó en la carpeta Borradores de tu correo, listo para que lo revises y lo envíes."
           if saved_in_gmail
           else "Quedó guardado en borradores, listo para tu confirmación.")
    )


def summarize_email(subject: str, content: str) -> str:
    """
    Genera un resumen ejecutivo de un correo largo.
    """
    return (
        f"Resumen ejecutivo de '{subject}':\n"
        f"{content.strip()}"
    )


# ============================================================
# FUNCIONES DE TAREAS Y RECORDATORIOS (SUPABASE)
# ============================================================

PRIORITIES = ("alta", "media", "baja")
CATEGORIES = ("universidad", "trabajo", "personal", "proyecto")


def _normalize_choice(value: str | None, allowed: tuple[str, ...], default: str) -> str:
    value = (value or "").strip().lower()
    return value if value in allowed else default


def get_pending_tasks() -> str:
    """
    Obtiene las tareas pendientes desde Supabase, ordenadas por prioridad.
    """
    try:
        result = (
            supabase.table("tasks")
            .select("*")
            .eq("completed", False)
            .order("created_at", desc=False)
            .execute()
        )
        tasks = result.data or []
    except Exception as e:
        print(f"Error consultando tareas en Supabase: {e}")
        return "No pude consultar las tareas en la base de datos."

    if not tasks:
        return "No tienes tareas pendientes."

    rank = {"alta": 0, "media": 1, "baja": 2}
    tasks.sort(key=lambda t: rank.get(t.get("priority") or "media", 1))

    response = f"Tienes {len(tasks)} tarea(s) pendiente(s):\n"
    for index, task in enumerate(tasks, start=1):
        details = []
        if task.get("priority") == "alta":
            details.append("prioridad alta")
        if task.get("status") == "en_progreso":
            details.append("en progreso")
        if task.get("due_date"):
            details.append(f"vence {task['due_date'][:10]}")
        if task.get("description"):
            details.append(task["description"])
        suffix = f" ({', '.join(details)})" if details else ""
        response += f"{index}. {task['title']}{suffix}\n"

    return response.strip()


def add_task(
    title: str,
    description: str | None = None,
    due_date: str | None = None,
    priority: str | None = None,
    category: str | None = None,
    task_id: str | None = None,
) -> str:
    """
    Agrega una nueva tarea en Supabase con prioridad (alta/media/baja) y
    categoría (universidad/trabajo/personal/proyecto).
    """
    title = title.strip()
    if not title:
        return "No se puede crear una tarea vacía."

    new_task = {
        "id": (task_id or str(uuid4())).strip().lower(),
        "title": title,
        "description": description,
        "due_date": due_date,
        "completed": False,
        "status": "pendiente",
        "priority": _normalize_choice(priority, PRIORITIES, "media"),
        "category": _normalize_choice(category, CATEGORIES, "personal"),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        insert_with_fallback("tasks", new_task, optional_keys={"status", "priority", "category"})
        return f"Tarea agregada exitosamente: '{title}'."
    except Exception as e:
        print(f"Error creando tarea en Supabase: {e}")
        return f"Error al guardar la tarea: {e}"


def set_task_completed(task_id: str, completed: bool) -> dict | None:
    """Actualiza completed y status de forma consistente."""
    fields = {"completed": completed, "status": "completado" if completed else "pendiente"}
    try:
        result = supabase.table("tasks").update(fields).eq("id", task_id).execute()
    except Exception:
        # Esquema antiguo sin columna status.
        result = supabase.table("tasks").update({"completed": completed}).eq("id", task_id).execute()
    return result.data[0] if result.data else None


def update_task(
    task_id: str,
    title: str | None = None,
    priority: str | None = None,
    category: str | None = None,
    due_date: str | None = None,
    clear_due_date: bool = False,
) -> dict | None:
    """Edita campos de una tarea existente (solo los enviados)."""
    fields: dict = {}
    if title and title.strip():
        fields["title"] = title.strip()
    if priority:
        fields["priority"] = _normalize_choice(priority, PRIORITIES, "media")
    if category:
        fields["category"] = _normalize_choice(category, CATEGORIES, "personal")
    if due_date or clear_due_date:
        fields["due_date"] = None if clear_due_date else due_date
    if not fields:
        return None

    result = execute_with_fallback(
        lambda data: supabase.table("tasks").update(data).eq("id", task_id),
        fields,
        optional_keys={"priority", "category"},
    )
    return result.data[0] if result.data else None


def complete_task(title: str) -> str:
    """
    Marca una tarea como completada en Supabase buscando por coincidencia de texto.
    """
    search_title = title.strip().lower()

    try:
        result = (
            supabase.table("tasks")
            .select("*")
            .eq("completed", False)
            .execute()
        )
        tasks = result.data or []
    except Exception as e:
        print(f"Error consultando tareas: {e}")
        return "No pude verificar tus tareas en la base de datos."

    for task in tasks:
        task_title = task.get("title", "").strip().lower()
        if search_title and (search_title in task_title or task_title in search_title):
            if set_task_completed(task["id"], True):
                return f"Tarea '{task['title']}' marcada como completada."

    return f"No encontré ninguna tarea pendiente que coincida con '{title}'."
