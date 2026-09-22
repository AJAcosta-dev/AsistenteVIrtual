from datetime import datetime, timedelta, timezone
import json
import os
import secrets

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from orchestrator import process_command
from agents.financial import (
    get_financial_summary,
    get_available_budget,
    get_credit_cards_status,
    get_savings_goals,
    get_savings_goals_list,
    create_savings_goal,
    deposit_to_goal,
    delete_savings_goal,
    create_transaction,
    delete_transaction,
)
from agents.banking import extract_bank_transaction, is_income_notification
from agents.secretary import (
    get_pending_tasks,
    add_task,
    complete_task,
    check_emails,
    draft_email,
)
from agents.agenda import create_event, get_upcoming_events, delete_event
from supabase_client import supabase


app = FastAPI(
    title="GUTI Backend",
    description="Asistente Personal Inteligente Multi-Agente con Control por Voz (Secretaría, Finanzas, Agenda)",
    version="2.0.0",
)

# ============================================================
# CORS (Permitir conexiones desde Tailscale y app móvil)
# ============================================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================
# MODELOS PYDANTIC
# ============================================================

class CommandRequest(BaseModel):
    text: str


class TransactionCreateRequest(BaseModel):
    amount: float
    merchant: str
    category: str
    is_income: bool = False


class EventCreateRequest(BaseModel):
    title: str
    start_date: datetime
    description: str | None = None
    end_date: datetime | None = None


class TaskCreateRequest(BaseModel):
    title: str
    description: str | None = None
    due_date: str | None = None


class DraftEmailRequest(BaseModel):
    recipient: str
    subject: str
    body: str


class SavingsGoalCreateRequest(BaseModel):
    name: str
    target_amount: float
    category: str = "general"
    emoji: str = "🎯"
    target_date: str | None = None  # formato YYYY-MM-DD


class SavingsGoalDepositRequest(BaseModel):
    amount: float


# ============================================================
# HEALTH CHECK
# ============================================================

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "GUTI Backend",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ============================================================
# ORQUESTADOR CENTRAL / COMANDOS POR VOZ
# ============================================================

@app.post("/api/command")
async def command(request: CommandRequest):
    """
    Endpoint principal consumido por la aplicación móvil (VoiceService / Chat).
    Enruta la petición al agente correspondiente con Function Calling.
    """
    try:
        result = process_command(request.text)
        return result
    except Exception as error:
        print(f"Error procesando comando: {error}")
        raise HTTPException(
            status_code=500,
            detail="Error procesando la instrucción en el orquestador.",
        )


# ============================================================
# AGENTE FINANCIERO (TRANSACCIONES Y ANALÍTICA)
# ============================================================

@app.get("/api/financial/transactions")
def get_transactions():
    try:
        result = (
            supabase.table("transactions")
            .select("*")
            .order("date", desc=True)
            .execute()
        )
        return {"transactions": result.data or []}
    except Exception as error:
        print(f"Error obteniendo transacciones: {error}")
        raise HTTPException(status_code=500, detail="No se pudieron obtener las transacciones.")


@app.post("/api/financial/transactions")
def add_financial_transaction(request: TransactionCreateRequest):
    try:
        transaction = create_transaction(
            amount=request.amount,
            merchant=request.merchant,
            category=request.category,
            is_income=request.is_income,
        )
        return {"transaction": transaction}
    except Exception as error:
        print(f"Error creando transacción: {error}")
        raise HTTPException(status_code=500, detail="No se pudo crear la transacción.")


@app.delete("/api/financial/transactions/{transaction_id}")
def remove_financial_transaction(transaction_id: str):
    try:
        deleted = delete_transaction(transaction_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Transacción no encontrada.")
        return {"message": "Transacción eliminada correctamente.", "id": transaction_id}
    except HTTPException:
        raise
    except Exception as error:
        print(f"Error eliminando transacción: {error}")
        raise HTTPException(status_code=500, detail="No se pudo eliminar la transacción.")


@app.get("/api/financial/summary")
def get_summary():
    """Resumen consolidado de ingresos, gastos y balance mensual."""
    return {"summary": get_financial_summary()}


@app.get("/api/financial/cashflow")
def get_cashflow(timeframe: str = "este fin de semana"):
    """Cálculo dinámico de liquidez y presupuesto disponible."""
    return {"cashflow": get_available_budget(timeframe)}


@app.get("/api/financial/cards")
def get_cards():
    """Estado de tarjetas de crédito y fechas de corte."""
    return {"cards": get_credit_cards_status()}


@app.get("/api/financial/goals")
def get_goals():
    """Lista estructurada de metas de ahorro desde Supabase."""
    goals = get_savings_goals_list()
    return {"goals": goals}


@app.post("/api/financial/goals")
def create_goal(request: SavingsGoalCreateRequest):
    """Crea una nueva meta de ahorro en Supabase."""
    try:
        goal = create_savings_goal(
            name=request.name,
            target_amount=request.target_amount,
            category=request.category,
            emoji=request.emoji,
            target_date=request.target_date,
        )
        return {"goal": goal, "message": f"Meta '{request.name}' creada exitosamente."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.patch("/api/financial/goals/{goal_id}/deposit")
def deposit_goal(goal_id: str, request: SavingsGoalDepositRequest):
    """Deposita un monto a una meta de ahorro existente."""
    try:
        updated = deposit_to_goal(goal_id=goal_id, amount=request.amount)
        return {"goal": updated, "message": f"Depósito de ${request.amount:,.0f} COP registrado."}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/financial/goals/{goal_id}")
def remove_goal(goal_id: str):
    """Elimina una meta de ahorro de Supabase."""
    deleted = delete_savings_goal(goal_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Meta no encontrada.")
    return {"message": "Meta de ahorro eliminada."}


# ============================================================
# AGENTE DE SECRETARÍA (TAREAS, PENDIENTES Y CORREOS)
# ============================================================

@app.get("/api/secretary/tasks")
@app.get("/api/tasks")
def get_all_tasks():
    try:
        result = (
            supabase.table("tasks")
            .select("*")
            .order("created_at", desc=False)
            .execute()
        )
        return {"tasks": result.data or []}
    except Exception as error:
        print(f"Error obteniendo tareas: {error}")
        raise HTTPException(status_code=500, detail="No se pudieron obtener las tareas.")


@app.post("/api/secretary/tasks")
@app.post("/api/tasks")
def create_new_task(request: TaskCreateRequest):
    msg = add_task(
        title=request.title,
        description=request.description,
        due_date=request.due_date,
    )
    return {"message": msg}


@app.patch("/api/secretary/tasks/{task_id}/toggle")
@app.patch("/api/tasks/{task_id}/toggle")
def toggle_task_status(task_id: str):
    try:
        current = supabase.table("tasks").select("*").eq("id", task_id).execute()
        if not current.data:
            raise HTTPException(status_code=404, detail="Tarea no encontrada.")
        new_val = not current.data[0].get("completed", False)
        updated = supabase.table("tasks").update({"completed": new_val}).eq("id", task_id).execute()
        return {"task": updated.data[0]}
    except HTTPException:
        raise
    except Exception as error:
        print(f"Error actualizando tarea: {error}")
        raise HTTPException(status_code=500, detail="No se pudo actualizar la tarea.")


@app.delete("/api/secretary/tasks/{task_id}")
@app.delete("/api/tasks/{task_id}")
def delete_task_item(task_id: str):
    try:
        result = supabase.table("tasks").delete().eq("id", task_id).execute()
        return {"message": "Tarea eliminada correctamente.", "id": task_id}
    except Exception as error:
        print(f"Error eliminando tarea: {error}")
        raise HTTPException(status_code=500, detail="No se pudo eliminar la tarea.")


@app.get("/api/secretary/emails")
def list_emails(query: str | None = None, unread_only: bool = False):
    """Consulta la bandeja de correos electrónicos."""
    return {"emails": check_emails(query=query, unread_only=unread_only)}


@app.post("/api/secretary/drafts")
def create_draft(request: DraftEmailRequest):
    """Crea un borrador de correo electrónico."""
    res = draft_email(
        recipient=request.recipient,
        subject=request.subject,
        body=request.body,
    )
    return {"message": res}


# ============================================================
# AGENTE DE AGENDA (CITAS Y EVENTOS)
# ============================================================

@app.get("/api/agenda/events")
def get_agenda_events():
    try:
        events = get_upcoming_events()
        return {"events": events}
    except Exception as error:
        print(f"Error obteniendo eventos: {error}")
        raise HTTPException(status_code=500, detail="No se pudieron obtener los eventos.")


@app.post("/api/agenda/events")
def add_agenda_event(request: EventCreateRequest):
    try:
        event = create_event(
            title=request.title,
            start_date=request.start_date,
            description=request.description,
            end_date=request.end_date,
        )
        return {"event": event}
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))
    except Exception as error:
        print(f"Error creando evento: {error}")
        raise HTTPException(status_code=500, detail="No se pudo crear el evento.")


@app.delete("/api/agenda/events/{event_id}")
def remove_agenda_event(event_id: str):
    try:
        deleted = delete_event(event_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Evento no encontrado.")
        return {"message": "Evento eliminado correctamente.", "id": event_id}
    except HTTPException:
        raise
    except Exception as error:
        print(f"Error eliminando evento: {error}")
        raise HTTPException(status_code=500, detail="No se pudo eliminar el evento.")


# ============================================================
# BANKING WEBHOOK (ZERO-FRICTION INGESTION)
# ============================================================

WEBHOOK_TOKEN = os.getenv("WEBHOOK_TOKEN", "")


def _log_bank_notification(raw_text: str, transaction_id: str | None, error: str | None = None):
    """Bitácora de ingesta (tabla bank_notifications). No interrumpe el flujo si falla."""
    try:
        supabase.table("bank_notifications").insert({
            "raw_text": raw_text,
            "transaction_id": transaction_id,
            "status": "error" if error else "procesada",
            "error": error,
        }).execute()
    except Exception as log_error:
        print(f"Aviso: no se registró en bank_notifications ({log_error})")


def _sanitize_transaction_date(iso_date: str) -> datetime:
    """
    El LLM a veces inventa el año o la fecha. Si queda en el futuro o con más de
    45 días de antigüedad, se usa el momento de recepción de la notificación.
    """
    now = datetime.now(timezone.utc)
    try:
        parsed = datetime.fromisoformat(iso_date)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return now
    if parsed > now + timedelta(days=1) or parsed < now - timedelta(days=45):
        return now
    # Si la notificación es de hoy, conservar la hora real de recepción.
    return now if parsed.date() == now.date() else parsed


@app.post("/api/banking/webhook")
async def banking_webhook(
    request: Request,
    x_guti_token: str | None = Header(default=None),
):
    """
    Webhook para ingesta de transacciones en segundo plano vía Apple Shortcuts o Android listeners.
    Acepta formato JSON estándar {"text": "..."}, o dicts {"Clave": "...", "Valor": "..."},
    o texto plano.
    Extrae la información mediante LLM Structured Output e inserta en Supabase sin intervención humana.
    """
    # Si WEBHOOK_TOKEN está definido en .env, se exige el header X-GUTI-Token.
    if WEBHOOK_TOKEN and not secrets.compare_digest(x_guti_token or "", WEBHOOK_TOKEN):
        raise HTTPException(status_code=401, detail="Token de webhook inválido.")

    text = ""
    try:
        # 1. Leer cuerpo
        content_type = request.headers.get("content-type", "")
        if "application/json" in content_type:
            body = await request.json()
        else:
            raw_body = (await request.body()).decode("utf-8")
            try:
                body = json.loads(raw_body)
            except Exception:
                body = raw_body

        print(f"\n💳 WEBHOOK BANCARIO RECIBIDO: {body}")

        # Si llegó como string directo
        if isinstance(body, str):
            text = body
        elif isinstance(body, dict):
            # Compatibilidad con Apple Shortcuts ("Valor") o payload directo ("text")
            if "Valor" in body:
                text = str(body["Valor"])
            elif "text" in body:
                text = str(body["text"])
            elif "message" in body:
                text = str(body["message"])
            elif "body" in body:
                text = str(body["body"])
            else:
                # Tomar el primer valor de tipo string
                str_vals = [str(v) for v in body.values() if isinstance(v, str)]
                text = str_vals[0] if str_vals else ""
        else:
            text = str(body)

        text = text.strip()
        if not text:
            raise HTTPException(
                status_code=400,
                detail="No se encontró contenido de texto en la solicitud bancaria.",
            )

        print(f"🔍 TEXTO A PROCESAR: {text}")

        # 2. Extracción estructurada mediante LLM
        extracted = extract_bank_transaction(text)
        print(f"✅ DATOS EXTRAÍDOS: {extracted}")

        # 3. Fecha validada e ingreso vs. gasto
        transaction_date = _sanitize_transaction_date(extracted["date"])
        is_income = is_income_notification(text)

        # 4. Inserción directa en la base de datos Supabase
        transaction = create_transaction(
            amount=extracted["amount"],
            merchant=extracted["merchant"],
            category="ingresos" if is_income else extracted["category"],
            is_income=is_income,
            transaction_date=transaction_date,
            source="webhook",
            payment_method=extracted.get("payment_method"),
            currency=extracted.get("currency", "COP"),
        )
        _log_bank_notification(text, transaction.get("id"))

        return {
            "message": "Transacción bancaria procesada e insertada correctamente.",
            "extracted": extracted,
            "transaction": transaction,
        }

    except HTTPException:
        raise
    except Exception as error:
        print(f"❌ Error procesando webhook bancario: {error}")
        if text:
            _log_bank_notification(text, None, error=str(error))
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo procesar la transacción bancaria: {error}",
        )