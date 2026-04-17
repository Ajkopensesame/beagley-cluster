#!/bin/bash
set -euo pipefail

HOST="root@beagley-ai.local"

echo "[RESTART] Step 1: Reset failed state..."
ssh $HOST "systemctl reset-failed beagley_cluster"

echo "[RESTART] Step 2: Attempt start..."
ssh $HOST "systemctl start beagley_cluster"

echo "[RESTART] Step 3: Check status..."
ssh $HOST "systemctl status beagley_cluster --no-pager"

echo "[RESTART] Complete"
