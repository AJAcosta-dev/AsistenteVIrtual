#!/usr/bin/env bash
# Simula la notificación bancaria que enviaría el Atajo de iOS.
# Uso: ./scripts/simulate_bank_webhook.sh [host] ["texto de la notificación"]
#   host por defecto: 127.0.0.1 (usa la IP 100.x.x.x de Tailscale para probar desde otro equipo)
set -euo pipefail

HOST="${1:-127.0.0.1}"
TEXT="${2:-Bancolombia le informa Compra por \$38.900 en CREPES Y WAFFLES $(date +%d/%m/%Y) T.Cred *4521}"
TOKEN="${WEBHOOK_TOKEN:-}"

curl -sS "http://${HOST}:8000/api/banking/webhook" \
  -H "Content-Type: application/json" \
  ${TOKEN:+-H "X-GUTI-Token: ${TOKEN}"} \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$TEXT")"
echo
