#!/bin/bash
set -euo pipefail

HOST="${ELITEBOOK_HOST:-pneumaion@172.20.10.9}"
KEY="$HOME/.ssh/pneumaion_elitebook"
HOST_ADDR="${HOST#*@}"

echo "[ELITEBOOK-CONNECT] Step 1: Check network..."

if ping -c 2 "$HOST_ADDR" >/dev/null 2>&1; then
  echo "[OK] EliteBook reachable"
else
  echo "[FAIL] Cannot reach EliteBook at $HOST_ADDR"
  exit 1
fi

echo "[ELITEBOOK-CONNECT] Step 2: Open SSH session..."
echo "----------------------------------------"

ssh -i "$KEY" "$HOST"
