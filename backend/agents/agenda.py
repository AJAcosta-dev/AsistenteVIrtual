from datetime import datetime, timezone
from uuid import uuid4

from supabase_client import supabase


def create_event(
    title: str,
    start_date: datetime,
    description: str | None = None,
    end_date: datetime | None = None,
):
    """
    Crea un evento real en Supabase.
    """

    if not title.strip():
        raise ValueError("El título del evento no puede estar vacío.")

    if start_date.tzinfo is None:
        start_date = start_date.replace(tzinfo=timezone.utc)

    if end_date is not None and end_date.tzinfo is None:
        end_date = end_date.replace(tzinfo=timezone.utc)

    event = {
        "id": str(uuid4()),
        "title": title.strip(),
        "description": description,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat() if end_date else None,
    }

    result = (
        supabase
        .table("events")
        .insert(event)
        .execute()
    )

    if not result.data:
        raise RuntimeError(
            "No se pudo crear el evento en Supabase."
        )

    return result.data[0]


def get_upcoming_events():
    """
    Obtiene todos los eventos futuros.
    """

    now = datetime.now(timezone.utc).isoformat()

    result = (
        supabase
        .table("events")
        .select("*")
        .gte("start_date", now)
        .order("start_date", desc=False)
        .execute()
    )

    return result.data or []


def delete_event(event_id: str):
    """
    Elimina un evento por ID (soporta UUIDs en mayúsculas o minúsculas de iOS).
    """
    clean_id = event_id.strip().lower()

    # 1. Intentar con ID en minúsculas
    result = (
        supabase
        .table("events")
        .delete()
        .eq("id", clean_id)
        .execute()
    )

    if result.data:
        return True

    # 2. Respaldo por si se guardó en mayúsculas
    result_upper = (
        supabase
        .table("events")
        .delete()
        .eq("id", event_id.strip())
        .execute()
    )

    return bool(result_upper.data)