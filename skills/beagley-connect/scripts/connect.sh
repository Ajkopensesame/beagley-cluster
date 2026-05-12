#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../beagley-common/scripts/ssh.sh"

echo "[CONNECT] Testing reachability..."

if ! beagley_require_ssh_target; then
  echo "[FAIL] No reachable SSH endpoint resolved from $BEAGLEY_HOST_NAME"
  echo "Check WiFi / network"
  exit 1
fi
echo "[OK] BeagleY reachable on $BEAGLEY_SSH_TARGET:22"

echo "[CONNECT] Opening SSH session..."
echo "----------------------------------------"

ssh "${BEAGLEY_SSH_OPTS[@]}" "$BEAGLEY_SSH_HOST"
