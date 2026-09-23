# GUTI — Asistente Personal Multi-Agente con Control por Voz

App iOS (SwiftUI) + backend FastAPI local con orquestador multi-agente (Secretaría y Finanzas),
LLM local con Ollama, persistencia en Supabase y conexión privada por Tailscale.

```
GUTI/                 App iOS (SwiftUI)
  Services/           APIService (REST), VoiceService (STT/TTS), AppStore (estado)
  Views/              Dashboard, Finanzas, Agenda, Tareas, Chat GUTI
backend/              Servidor FastAPI
  main.py             Endpoints REST + webhook bancario
  orchestrator.py     Function Calling con Ollama + enrutador semántico
  agents/             secretary, financial, agenda, banking
  schema.sql          Esquema relacional de Supabase
  scripts/            Simulador del webhook bancario
docs/ARQUITECTURA.md  Diagramas de secuencia y modelo entidad-relación
```

Arquitectura, diagramas de secuencia y esquema relacional: [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md).

## 1. Requisitos

- macOS con Xcode 26+ (la app usa `SpeechAnalyzer`, iOS 26.5+)
- Python 3.13
- [Ollama](https://ollama.com) con `llama3.2`
- Proyecto en [Supabase](https://supabase.com)
- [Tailscale](https://tailscale.com) en el Mac y en el iPhone, con la misma cuenta

## 2. Base de datos (Supabase)

1. En el panel de Supabase abre **SQL Editor**.
2. Pega el contenido de [`backend/schema.sql`](backend/schema.sql) y ejecútalo.
   Es idempotente: crea las tablas que falten, agrega columnas nuevas, activa RLS y carga datos semilla.
   Vuelve a ejecutarlo cada vez que el archivo cambie (no borra datos).
3. Opcional, para la demo: carga gastos, ingresos, tareas y eventos del mes actual.

```bash
cd backend
.venv/bin/python scripts/seed_demo_data.py          # crear datos demo
.venv/bin/python scripts/seed_demo_data.py --clean  # borrar solo los datos demo
```

## 3. Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env    # completar SUPABASE_URL y SUPABASE_SECRET_KEY
ollama pull llama3.2
./run.sh                # escucha en 0.0.0.0:8000
```

Prueba rápida: `curl http://127.0.0.1:8000/health`. Documentación interactiva: `http://127.0.0.1:8000/docs`.

### Correo real (Agente de Secretaría)

Sin configuración, GUTI usa un buzón de ejemplo. Para leer tu Gmail real y guardar borradores en él:

1. Activa la verificación en 2 pasos en tu cuenta de Google.
2. Crea una contraseña de aplicación en https://myaccount.google.com/apppasswords.
3. Agrégala a `backend/.env`:

```
MAIL_ADDRESS=tu_correo@gmail.com
MAIL_APP_PASSWORD=abcd efgh ijkl mnop
```

GUTI lee los últimos 25 correos de la bandeja de entrada sin marcarlos como leídos, prioriza los
urgentes y guarda los borradores en tu carpeta **Borradores** (nunca envía correos por su cuenta).

## 4. Tailscale

1. Instala Tailscale en el Mac y en el iPhone e inicia sesión con la misma cuenta.
2. Obtén la IP del Mac: `tailscale ip -4` (algo como `100.83.82.72`).
3. En el iPhone desactiva Wi-Fi (solo datos móviles) y abre `http://100.x.x.x:8000/health` en Safari.

No se abren puertos del router ni se usan túneles públicos: todo el tráfico va cifrado por WireGuard dentro de la tailnet.

## 5. App iOS

1. Abre `GUTI.xcodeproj` en Xcode.
2. En [`GUTI/Services/APIService.swift`](GUTI/Services/APIService.swift) ajusta `baseURL` con la IP de Tailscale del Mac.
3. Ejecuta en el iPhone y concede permisos de micrófono y reconocimiento de voz.

## 6. Ingesta automática de pagos (Atajo de iOS)

1. App **Atajos → Automatización → Nueva automatización → Correo**.
2. Remitente: el correo de alertas de tu banco (ej. `alertasynotificaciones@bancolombia.com.co`). Marca **Ejecutar inmediatamente**.
3. Acciones:
   - **Obtener contenido de URL**
     - URL: `http://100.x.x.x:8000/api/banking/webhook`
     - Método: `POST`, Cuerpo: `JSON`, campo `text` = *Mensaje del correo* (variable de la automatización)
     - Header `X-GUTI-Token` con el valor de `WEBHOOK_TOKEN` de `backend/.env` (sin él, el backend responde 401)
4. Guarda. Cada alerta bancaria queda registrada como transacción con `source = 'webhook'`.

Simular una alerta sin esperar al banco:

```bash
WEBHOOK_TOKEN=$(grep ^WEBHOOK_TOKEN backend/.env | cut -d= -f2-) ./backend/scripts/simulate_bank_webhook.sh 100.x.x.x
```

## 7. Comandos de voz para la demo

| Comando | Agente |
| --- | --- |
| "¿Cuánto dinero me queda disponible para salir este fin de semana?" | Financiero |
| "Revisa si el decano me respondió el correo" | Secretaría |
| "¿Cuánto me queda para el fin de semana y qué tareas tengo pendientes?" | Multi-agente |
| "¿Cómo están mis tarjetas de crédito?" | Financiero |
| "Redacta una excusa formal para el profesor Gómez indicando incapacidad médica" | Secretaría |
| "Agrega una tarea urgente de estudiar cálculo para la universidad" | Secretaría |
| "¿Tengo correos no leídos?" | Secretaría |
