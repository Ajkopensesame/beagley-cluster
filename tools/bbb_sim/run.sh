#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$ROOT/.venv"

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "[bbb_sim] venv missing. Create it with:"
  echo "  python3 -m venv tools/bbb_sim/.venv"
  echo "  source tools/bbb_sim/.venv/bin/activate"
  echo "  python -m pip install --upgrade pip websockets"
  echo "  deactivate"
  exit 1
fi

exec "$VENV/bin/python" "$ROOT/sim.py"
