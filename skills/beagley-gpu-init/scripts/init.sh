#!/bin/bash
set -euo pipefail

HOST="root@beagley-ai.local"

echo "[GPU-INIT] Step 1: Detect PrivateTmp setting..."

PRIV=$(ssh $HOST "systemctl show beagley_cluster -p PrivateTmp --value")

echo "[INFO] PrivateTmp=$PRIV"

echo "[GPU-INIT] Step 2: Handle gate file..."

if [ "$PRIV" = "yes" ]; then
  echo "[FIX] Service uses private /tmp → creating gate file inside service namespace"

  ssh $HOST "PID=\$(pgrep beagley_cluster || true); \
  if [ -n \"\$PID\" ]; then \
    nsenter -t \$PID -m touch /tmp/beagley_gpu_gate.ok; \
  else \
    echo '[WARN] Service not running, using fallback approach'; \
    mkdir -p /tmp/systemd-gpu-gate && touch /tmp/systemd-gpu-gate/beagley_gpu_gate.ok; \
  fi"

else
  echo "[FIX] Standard /tmp → creating gate file normally"
  ssh $HOST "touch /tmp/beagley_gpu_gate.ok && chmod 644 /tmp/beagley_gpu_gate.ok"
fi

echo "[GPU-INIT] Step 3: Restart service cleanly..."
ssh $HOST "systemctl reset-failed beagley_cluster"
ssh $HOST "systemctl restart beagley_cluster"

echo "[GPU-INIT] Step 4: Verify status..."
ssh $HOST "systemctl status beagley_cluster --no-pager"

echo "[GPU-INIT] Complete"
