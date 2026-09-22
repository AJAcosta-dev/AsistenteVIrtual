# GUTI — Documento Técnico de Arquitectura

## 1. Topología

```mermaid
flowchart TD
    subgraph iPhone["iPhone (SwiftUI)"]
        Voice["VoiceService<br/>SpeechAnalyzer (STT) + AVSpeechSynthesizer (TTS)"]
        UI["Dashboard · Finanzas · Agenda · Tareas · Chat GUTI"]
        Shortcut["Atajo iOS<br/>'Cuando recibo un correo de Bancolombia'"]
    end

    VPN["Tailscale Mesh VPN<br/>(WireGuard, IP 100.x.x.x)"]

    subgraph Mac["Servidor local (FastAPI :8000)"]
        Orch["orchestrator.py<br/>Function Calling + enrutador semántico"]
        Sec["agents/secretary.py<br/>correos, borradores, tareas"]
        Agenda["agents/agenda.py<br/>eventos"]
        Fin["agents/financial.py<br/>transacciones, flujo de caja, tarjetas, metas"]
        Bank["agents/banking.py<br/>extracción Structured Output (JSON)"]
        Ollama["Ollama · llama3.2"]
    end

    DB[("Supabase (PostgreSQL)<br/>RLS activo, solo clave secreta del backend")]

    Voice --> VPN
    UI --> VPN
    Shortcut -->|POST /api/banking/webhook| VPN
    VPN --> Orch
    VPN --> Bank
    Orch --> Sec & Agenda & Fin
    Orch <--> Ollama
    Bank <--> Ollama
    Sec & Agenda & Fin & Bank --> DB
```

**Seguridad de red:** el backend no se expone a internet. El iPhone lo alcanza por la IP privada de Tailscale
(`100.x.x.x:8000`) incluso con datos móviles, sin abrir puertos del router ni túneles públicos (ngrok, etc.).
Supabase solo recibe tráfico del backend usando la clave secreta; la app nunca tiene credenciales de base de datos.
El webhook bancario acepta opcionalmente un secreto compartido en el header `X-GUTI-Token`.

## 2. Diagrama de secuencia — comando por voz

```mermaid
sequenceDiagram
    actor U as Usuario
    participant App as App iOS (VoiceService)
    participant API as FastAPI /api/command
    participant O as Orquestador
    participant L as Ollama (llama3.2)
    participant A as Agentes (Financiero / Secretaría)
    participant DB as Supabase

    U->>App: Mantiene el botón y habla
    App->>App: STT on-device (SpeechAnalyzer, es-CO / es-US)
    App->>API: POST {"text": "¿Cuánto me queda para el fin de semana?"} vía Tailscale
    API->>O: process_command(text)
    O->>L: /api/chat con tools (Function Calling)
    L-->>O: tool_calls: get_available_budget(timeframe)
    O->>O: Enrutador semántico agrega consultas omitidas (p. ej. get_pending_tasks)
    O->>A: Ejecuta cada herramienta
    A->>DB: select transactions / tasks / emails ...
    DB-->>A: filas
    A-->>O: resultados en texto
    O->>L: Síntesis (datos reales + pregunta)
    L-->>O: respuesta en lenguaje natural
    O-->>API: {"response": "...", "agent": "financial | secretary | multi-agent"}
    API-->>App: JSON
    App->>U: Muestra la respuesta y la lee en voz alta (TTS)
```

## 3. Diagrama de secuencia — ingesta cero-fricción

```mermaid
sequenceDiagram
    participant Bank as Banco
    participant Mail as Mail (iPhone)
    participant SC as Atajo iOS (automatización personal)
    participant W as FastAPI /api/banking/webhook
    participant X as banking.py
    participant L as Ollama (format: json)
    participant DB as Supabase

    Bank->>Mail: "Compra por $38.900 en CREPES Y WAFFLES"
    Mail->>SC: Disparador: correo de remitente bancario
    SC->>W: POST {"text": cuerpo del correo} vía Tailscale (+ X-GUTI-Token)
    W->>X: extract_bank_transaction(text)
    X->>X: Regex de montos colombianos ($42.500, 1.250.000 COP)
    X->>L: Prompt de Structured Output
    L-->>X: {amount, currency, merchant, date, payment_method, category}
    X-->>W: datos validados (categoría permitida, fecha saneada, ingreso/gasto)
    W->>DB: insert transactions (source = 'webhook')
    W->>DB: insert bank_notifications (raw_text, transaction_id)
    W-->>SC: 200 {"transaction": ...}
```

## 4. Esquema relacional

Definido en [`backend/schema.sql`](../backend/schema.sql).

```mermaid
erDiagram
    emails ||--o{ email_drafts : "reply_to_email_id"
    emails ||--o{ tasks : "source_email_id"
    credit_cards ||--o{ transactions : "card_id"
    transactions ||--o{ bank_notifications : "transaction_id"
    savings_goals ||--o{ goal_deposits : "goal_id"

    emails {
        text id PK
        text sender
        text sender_name
        text subject
        text body
        timestamptz date
        boolean is_read
        boolean is_urgent
    }
    email_drafts {
        text id PK
        text reply_to_email_id FK
        text recipient
        text subject
        text body
        text status "borrador | enviado"
    }
    tasks {
        text id PK
        text title
        text description
        timestamptz due_date
        boolean completed
        text priority "alta | media | baja"
        text status "pendiente | en_progreso | completado"
        text source_email_id FK
    }
    events {
        text id PK
        text title
        timestamptz start_date
        timestamptz end_date
    }
    credit_cards {
        text id PK
        text bank
        text card_name
        numeric total_limit
        numeric used_amount
        smallint cutoff_day
        smallint due_day
        numeric interest_rate_ea
    }
    transactions {
        text id PK
        numeric amount "CHECK > 0"
        text merchant
        text category
        timestamptz date
        int month
        int year
        boolean is_income
        text currency
        text payment_method
        text source "manual | voz | webhook"
        text card_id FK
    }
    bank_notifications {
        text id PK
        text raw_text
        timestamptz received_at
        text status "procesada | error"
        text transaction_id FK
    }
    savings_goals {
        text id PK
        text name
        numeric target_amount
        numeric current_amount
        text emoji
        date target_date
    }
    goal_deposits {
        text id PK
        text goal_id FK
        numeric amount
    }
```

Reglas de integridad:
- `ON DELETE CASCADE` en `goal_deposits` (sin meta no hay abonos).
- `ON DELETE SET NULL` en el resto de FKs: borrar un correo o tarjeta no borra tareas ni transacciones históricas.
- `CHECK` en montos positivos, días de corte 1–31 y estados enumerados.

## 5. Herramientas del orquestador (Function Calling)

| Agente | Herramienta | Acción |
| --- | --- | --- |
| Financiero | `get_financial_summary` | Ingresos, gastos y gasto por categoría del mes |
| Financiero | `get_available_budget` | Liquidez libre y presupuesto sugerido para el periodo |
| Financiero | `get_credit_cards_status` | Cupos, fechas de corte/pago e interés mensual estimado |
| Financiero | `get_savings_goals` | Avance porcentual de metas de ahorro |
| Financiero | `add_transaction` | Registro de gasto/ingreso por voz |
| Secretaría | `check_emails` | Búsqueda de correos (p. ej. respuesta del decano) |
| Secretaría | `draft_email` | Borrador formal, queda pendiente de confirmación |
| Secretaría | `get_pending_tasks` / `add_task` / `complete_task` | Gestión de pendientes |
| Secretaría (agenda) | `get_upcoming_events` / `schedule_event` | Citas y reuniones |

Si el LLM no emite `tool_calls` o deja por fuera parte de una pregunta mixta, un enrutador semántico
determinista (palabras clave normalizadas sin tildes) completa las consultas, y la respuesta se marca
como `multi-agent` cuando intervienen ambos agentes.
