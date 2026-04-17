#!/bin/bash
set -euo pipefail

HOST="root@beagley-ai.local"

echo "[CONNECT] Testing reachability..."

if ping -c 2 beagley-ai.local >/dev/null 2>&1; then
  echo "[OK] BeagleY reachable via mDNS"
else
  echo "[FAIL] Cannot resolve beagley-ai.local"
  echo "Check WiFi / network"
  exit 1
fi

echo "[CONNECT] Opening SSH session..."
echo "----------------------------------------"

ssh $HOST
