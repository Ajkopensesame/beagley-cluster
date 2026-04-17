#!/bin/bash
set -euo pipefail

HOST="root@beagley-ai.local"

echo "[CHECK] Step 1: Network..."

ping -c 2 beagley-ai.local >/dev/null
echo "[OK] Network reachable"

echo "[CHECK] Step 2: SSH..."

nc -z beagley-ai.local 22
echo "[OK] SSH available"

echo "[CHECK] Step 3: Service state..."

STATE=$(ssh $HOST "systemctl is-active beagley_cluster" 2>/dev/null || echo "unknown")
RESTARTS=$(ssh $HOST "systemctl show beagley_cluster -p NRestarts --value" 2>/dev/null || echo "0")

echo "[INFO] state=$STATE restarts=$RESTARTS"

# 🚨 Detect restart loop
if [ "$RESTARTS" -gt 5 ]; then
  echo "[FAIL] Service is restarting repeatedly (restart loop)"
  ssh $HOST "systemctl status beagley_cluster --no-pager"
  exit 1
fi

# Normal active check
if [ "$STATE" != "active" ]; then
  echo "[FAIL] Service is not active"
  ssh $HOST "systemctl status beagley_cluster --no-pager"
  exit 1
fi

echo "[CHECK] Step 4: Process..."

if ssh $HOST "pgrep beagley_cluster" >/dev/null; then
  echo "[OK] Process exists"
else
  echo "[FAIL] Process missing"
  exit 1
fi

echo "[CHECK] Step 5: Logs..."

ssh $HOST "journalctl -u beagley_cluster -n 10 --no-pager"

echo "[SUCCESS] System healthy"
