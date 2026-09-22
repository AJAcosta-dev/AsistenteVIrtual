from datetime import datetime, timezone
import json
import os
from uuid import uuid4

from supabase_client import supabase


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


def _get_inbox() -> list[dict]:
    """
    Bandeja de entrada desde Supabase (tabla emails). Si la tabla no existe
    o está vacía, usa el buzón local data/emails.json.
    """
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
    inbox = _get_inbox()

    if unread_only:
        inbox = [m for m in inbox if not m.get("is_read", False)]

    if query:
        q = query.lower()
        matched = [
            m for m in inbox
            if q in m.get("sender", "").lower()
            or q in m.get("sender_name", "").lower()
            or q in m.get("subject", "").lower()
            or q in m.get("body", "").lower()
        ]
    else:
        matched = inbox

    if not matched:
        if query:
            return f"No se encontraron correos relacionados con '{query}'."
        return "No tienes correos nuevos en la bandeja de entrada."

    response = f"Encontré {len(matched)} correo(s):\n"
    for email in matched:
        estado = "No leído (Urgente)" if not email.get("is_read") and email.get("is_urgent") else (
            "No leído" if not email.get("is_read") else "Leído"
        )
        response += (
            f"\n📨 De: {email.get('sender_name', email.get('sender'))}\n"
            f"   Asunto: {email.get('subject')}\n"
            f"   Estado: {estado}\n"
            f"   Contenido: {email.get('snippet') or (email.get('body') or '')[:140]}\n"
        )

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
        f"Quedó guardado en la carpeta de borradores listo para tu confirmación."
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

def get_pending_tasks() -> str:
    """
    Obtiene las tareas pendientes desde Supabase.
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

    response = f"Tienes {len(tasks)} tarea(s) pendiente(s):\n"
    for index, task in enumerate(tasks, start=1):
        desc = f" ({task['description']})" if task.get("description") else ""
        response += f"{index}. {task['title']}{desc}\n"

    return response.strip()


def add_task(
    title: str,
    description: str | None = None,
    due_date: str | None = None,
) -> str:
    """
    Agrega una nueva tarea en Supabase.
    """
    title = title.strip()
    if not title:
        return "No se puede crear una tarea vacía."

    new_task = {
        "id": str(uuid4()),
        "title": title,
        "description": description,
        "due_date": due_date,
        "completed": False,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        result = supabase.table("tasks").insert(new_task).execute()
        if not result.data:
            return "No se pudo crear la tarea en la base de datos."
        return f"Tarea agregada exitosamente: '{title}'."
    except Exception as e:
        print(f"Error creando tarea en Supabase: {e}")
        return f"Error al guardar la tarea: {e}"


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
        if search_title in task_title or task_title in search_title:
            update_result = (
                supabase.table("tasks")
                .update({"completed": True})
                .eq("id", task["id"])
                .execute()
            )
            if update_result.data:
                return f"Tarea '{task['title']}' marcada como completada."

    return f"No encontré ninguna tarea pendiente que coincida con '{title}'."