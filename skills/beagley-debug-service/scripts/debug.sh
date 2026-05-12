#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../beagley-common/scripts/ssh.sh"

ssh_run() {
  if [[ -z "$BEAGLEY_SSH_HOST" ]]; then
    echo "[WARN] No reachable SSH endpoint resolved from $BEAGLEY_HOST_NAME"
    return 0
  fi
  beagley_ssh "$@" || true
}

if beagley_require_ssh_target; then
  echo "[DEBUG] SSH target: $BEAGLEY_SSH_TARGET"
else
  echo "[DEBUG] SSH target: unavailable"
fi

echo "[DEBUG] Step 1: Service status..."
echo "----------------------------------------"
ssh_run "systemctl status beagley_cluster --no-pager"

echo ""
echo "[DEBUG] Step 2: Recent logs (last 50 lines)..."
echo "----------------------------------------"
ssh_run "journalctl -u beagley_cluster -n 50 --no-pager"

echo ""
echo "[DEBUG] Step 3: Error-level logs..."
echo "----------------------------------------"
ssh_run "journalctl -u beagley_cluster -p err -n 20 --no-pager"

echo ""
echo "[DEBUG] Step 4: Restart count..."
echo "----------------------------------------"
ssh_run "systemctl show beagley_cluster -p NRestarts"

echo ""
echo "[DEBUG] Complete"
