#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$ROOT/.venv"

exec "$VENV/bin/python" "$ROOT/vehicle_hub_prod.py"
