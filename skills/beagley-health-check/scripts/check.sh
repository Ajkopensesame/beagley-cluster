#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../beagley-common/scripts/ssh.sh"

ssh_run() {
  beagley_ssh "$@"
}

echo "[CHECK] Step 1: Network..."

if ! beagley_require_ssh_target; then
  echo "[FAIL] No reachable SSH endpoint resolved from $BEAGLEY_HOST_NAME"
  exit 2
fi
echo "[OK] Network reachable via $BEAGLEY_SSH_TARGET"

echo "[CHECK] Step 2: SSH..."

ssh_run "true"
echo "[OK] SSH available"

echo "[CHECK] Step 3: Service state..."

STATE=$(ssh_run "systemctl is-active beagley_cluster" 2>/dev/null || echo "unknown")
RESTARTS=$(ssh_run "systemctl show beagley_cluster -p NRestarts --value" 2>/dev/null || echo "0")

echo "[INFO] state=$STATE restarts=$RESTARTS"

# Restart loops are failures even while systemd reports the service active.
if [ "$RESTARTS" -gt 5 ]; then
  echo "[FAIL] Service is restarting repeatedly (restart loop)"
  ssh_run "systemctl status beagley_cluster --no-pager"
  exit 1
fi

if [ "$STATE" != "active" ]; then
  echo "[FAIL] Service is not active"
  ssh_run "systemctl status beagley_cluster --no-pager"
  exit 1
fi

echo "[CHECK] Step 4: Process..."

if ssh_run "pgrep beagley_cluster" >/dev/null; then
  echo "[OK] Process exists"
else
  echo "[FAIL] Process missing"
  exit 1
fi

echo "[CHECK] Step 5: Logs..."

ssh_run "journalctl -u beagley_cluster -n 10 --no-pager"

echo "[SUCCESS] System healthy"
