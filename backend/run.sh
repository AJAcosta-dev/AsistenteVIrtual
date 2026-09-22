#!/usr/bin/env bash
# ============================================================
# Script de inicio para GUTI Backend
# Evita consumo excesivo de CPU excluyendo .venv del file watcher
# Escucha en 0.0.0.0:8000 para acceso local y mediante Tailscale
# ============================================================

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ -f "$DIR/.venv/bin/activate" ]; then
    source "$DIR/.venv/bin/activate"
fi

echo "🚀 Iniciando GUTI Backend en http://0.0.0.0:8000 ..."
echo "🌐 Conexión disponible vía Tailscale y local."

exec uvicorn main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --reload \
    --reload-dir "$DIR" \
    --reload-exclude ".venv" \
    --reload-exclude "data" \
    --reload-exclude "__pycache__"
