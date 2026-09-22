import os

from dotenv import load_dotenv
from supabase import Client, create_client


load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")


if not SUPABASE_URL:
    raise RuntimeError(
        "Falta SUPABASE_URL en el archivo .env"
    )

if not SUPABASE_SECRET_KEY:
    raise RuntimeError(
        "Falta SUPABASE_SECRET_KEY en el archivo .env"
    )


supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_SECRET_KEY,
)

def insert_with_fallback(table: str, record: dict, optional_keys: set[str]) -> dict:
    """
    Inserta `record` en `table`. Si falla (p. ej. porque aún no se ejecutó
    schema.sql y faltan columnas nuevas), reintenta sin `optional_keys`.
    """
    try:
        result = supabase.table(table).insert(record).execute()
    except Exception as error:
        base = {k: v for k, v in record.items() if k not in optional_keys}
        if base == record:
            raise
        print(f"Aviso: insert en '{table}' sin columnas opcionales ({error}). ¿Ejecutaste schema.sql?")
        result = supabase.table(table).insert(base).execute()

    if not result.data:
        raise RuntimeError(f"No se pudo insertar en '{table}'.")
    return result.data[0]
