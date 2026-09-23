"""
Carga datos de demostración del mes actual en Supabase (para el video / sustentación).

    cd backend
    .venv/bin/python scripts/seed_demo_data.py          # crea o actualiza los datos demo
    .venv/bin/python scripts/seed_demo_data.py --clean  # elimina solo los datos demo

Todos los registros usan IDs con prefijo "demo-", así que volver a ejecutarlo no
duplica nada y --clean nunca toca datos reales.
"""

from datetime import datetime, timedelta, timezone
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from supabase_client import supabase  # noqa: E402


COLOMBIA_TZ = timezone(timedelta(hours=-5))
now = datetime.now(COLOMBIA_TZ)
month_key = now.strftime("%Y%m")


def day(n: int, hour: int = 12) -> datetime:
    """Día n del mes actual (sin pasar de hoy), a la hora indicada en Colombia."""
    return now.replace(day=min(n, now.day), hour=hour, minute=0, second=0, microsecond=0)


# Arriendo y servicios no se incluyen: ya están en "fixed_obligations" del perfil financiero.
# (día, comercio, categoría, monto, es_ingreso, origen, medio de pago, banco de la tarjeta)
TRANSACTIONS = [
    (1,  "Mesada mensual",        "ingresos",       1_200_000, True,  "manual",  "transferencia", None),
    (5,  "Monitoría académica",   "ingresos",         350_000, True,  "manual",  "transferencia", None),
    (3,  "Éxito",                 "alimentación",      86_400, False, "webhook", "debito",        None),
    (6,  "Uber",                  "transporte",        18_900, False, "webhook", "credito",       "Nu Colombia"),
    (8,  "Crepes & Waffles",      "alimentación",      42_500, False, "webhook", "credito",       "Bancolombia"),
    (10, "Librería Panamericana", "educación",         64_000, False, "manual",  "debito",        None),
    (12, "Spotify",               "entretenimiento",   16_900, False, "webhook", "credito",       "Nu Colombia"),
    (14, "Farmatodo",             "salud",             23_700, False, "webhook", "debito",        None),
    (16, "Cine Colombia",         "entretenimiento",   38_000, False, "voz",     "credito",       "Bancolombia"),
    (18, "D1",                    "alimentación",      31_250, False, "webhook", "debito",        None),
    (20, "Recarga TransMilenio",  "transporte",        30_000, False, "voz",     "debito",        None),
]

TASKS = [
    ("demo-task-1", "Estudiar para el parcial de Bases de Datos", "alta", "universidad", 2),
    ("demo-task-2", "Pagar tarjeta Nu antes del día 2", "alta", "personal", 8),
    ("demo-task-3", "Preparar video del taller de Móviles", "media", "universidad", 4),
]

EVENTS = [
    ("demo-event-1", "Asesoría con el profesor Gómez", 1, 10),
    ("demo-event-2", "Sustentación proyecto GUTI", 3, 14),
]


def _table_columns(table: str) -> set[str]:
    try:
        rows = supabase.table(table).select("*").limit(1).execute().data
        return set(rows[0].keys()) if rows else set()
    except Exception:
        return set()


def seed():
    cards = {c["bank"]: c["id"] for c in supabase.table("credit_cards").select("id, bank").execute().data or []}

    transactions = []
    for index, (d, merchant, category, amount, is_income, source, method, bank) in enumerate(TRANSACTIONS, 1):
        date = day(d, hour=9 + index % 10).astimezone(timezone.utc)
        transactions.append({
            "id": f"demo-{month_key}-{index:02d}",
            "amount": amount,
            "merchant": merchant,
            "category": category,
            "date": date.isoformat(),
            "month": date.month,
            "year": date.year,
            "is_income": is_income,
            "currency": "COP",
            "source": source,
            "payment_method": method,
            "card_id": cards.get(bank) if bank else None,
        })
    supabase.table("transactions").upsert(transactions).execute()

    # Cada compra "webhook" deja su notificación cruda enlazada (FK transaction_id).
    notifications = [
        {
            "id": f"demo-notif-{t['id']}",
            "raw_text": f"Compra por ${t['amount']:,.0f} en {t['merchant'].upper()} con {t['payment_method']}".replace(",", "."),
            "received_at": t["date"],
            "status": "procesada",
            "transaction_id": t["id"],
        }
        for t in transactions if t["source"] == "webhook"
    ]
    supabase.table("bank_notifications").upsert(notifications).execute()

    has_category = "category" in _table_columns("tasks") or not _table_columns("tasks")
    tasks = []
    for task_id, title, priority, category, due_in in TASKS:
        row = {
            "id": task_id,
            "title": title,
            "priority": priority,
            "status": "pendiente",
            "completed": False,
            "due_date": (now + timedelta(days=due_in)).replace(hour=23, minute=59).isoformat(),
        }
        if has_category:
            row["category"] = category
        tasks.append(row)
    try:
        supabase.table("tasks").upsert(tasks).execute()
    except Exception:
        # Columna category aún no creada: volver a ejecutar schema.sql la agrega.
        for row in tasks:
            row.pop("category", None)
        supabase.table("tasks").upsert(tasks).execute()

    events = [
        {
            "id": event_id,
            "title": title,
            "start_date": (now + timedelta(days=days_ahead)).replace(hour=hour, minute=0, second=0, microsecond=0).isoformat(),
            "end_date": (now + timedelta(days=days_ahead)).replace(hour=hour + 1, minute=0, second=0, microsecond=0).isoformat(),
        }
        for event_id, title, days_ahead, hour in EVENTS
    ]
    supabase.table("events").upsert(events).execute()

    income = sum(t["amount"] for t in transactions if t["is_income"])
    expenses = sum(t["amount"] for t in transactions if not t["is_income"])
    print(f"✅ {len(transactions)} transacciones ({len(notifications)} vía webhook), {len(tasks)} tareas, {len(events)} eventos.")
    print(f"   Ingresos ${income:,.0f} · Gastos ${expenses:,.0f} · Balance ${income - expenses:,.0f} COP")


def clean():
    for table, column in [
        ("bank_notifications", "id"),
        ("transactions", "id"),
        ("tasks", "id"),
        ("events", "id"),
    ]:
        deleted = supabase.table(table).delete().like(column, "demo-%").execute().data or []
        print(f"🧹 {table}: {len(deleted)} registros demo eliminados")


if __name__ == "__main__":
    clean() if "--clean" in sys.argv else seed()
