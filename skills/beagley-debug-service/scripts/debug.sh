#!/bin/bash
set -u  # remove -e so it doesn't stop on failure

HOST="root@beagley-ai.local"

echo "[DEBUG] Step 1: Service status..."
echo "----------------------------------------"
ssh $HOST "systemctl status beagley_cluster --no-pager" || true

echo ""
echo "[DEBUG] Step 2: Recent logs (last 50 lines)..."
echo "----------------------------------------"
ssh $HOST "journalctl -u beagley_cluster -n 50 --no-pager" || true

echo ""
echo "[DEBUG] Step 3: Error-level logs..."
echo "----------------------------------------"
ssh $HOST "journalctl -u beagley_cluster -p err -n 20 --no-pager" || true

echo ""
echo "[DEBUG] Step 4: Restart count..."
echo "----------------------------------------"
ssh $HOST "systemctl show beagley_cluster -p NRestarts" || true

echo ""
echo "[DEBUG] Complete"
