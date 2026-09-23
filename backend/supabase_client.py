import os
import re

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

def _missing_column(error: Exception) -> str | None:
    """Extrae el nombre de columna de errores PostgREST tipo PGRST204."""
    match = re.search(r"Could not find the '([^']+)' column", str(error))
    return match.group(1) if match else None


def execute_with_fallback(build_query, record: dict, optional_keys: set[str]):
    """
    Ejecuta `build_query(record)`. Si Supabase responde que falta una columna
    opcional (p. ej. porque aún no se re-ejecutó schema.sql), la quita y reintenta,
    conservando el resto de campos.
    """
    record = dict(record)
    while True:
        try:
            return build_query(record).execute()
        except Exception as error:
            column = _missing_column(error)
            if column not in optional_keys or column not in record:
                raise
            print(f"Aviso: falta la columna '{column}'. Ejecuta schema.sql para habilitarla.")
            record.pop(column)


def insert_with_fallback(table: str, record: dict, optional_keys: set[str]) -> dict:
    """Inserta `record` en `table` tolerando columnas opcionales ausentes."""
    result = execute_with_fallback(
        lambda data: supabase.table(table).insert(data), record, optional_keys
    )
    if not result.data:
        raise RuntimeError(f"No se pudo insertar en '{table}'.")
    return result.data[0]
