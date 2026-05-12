#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../beagley-common/scripts/ssh.sh"

if ! beagley_require_ssh_target; then
  echo "[RESTART] No reachable SSH endpoint resolved from $BEAGLEY_HOST_NAME" >&2
  exit 2
fi
echo "[RESTART] Using SSH target: $BEAGLEY_SSH_TARGET"

echo "[RESTART] Step 1: Reset failed state..."
beagley_ssh "systemctl reset-failed beagley_cluster"

echo "[RESTART] Step 2: Attempt start..."
beagley_ssh "systemctl start beagley_cluster"

echo "[RESTART] Step 3: Check status..."
beagley_ssh "systemctl status beagley_cluster --no-pager"

echo "[RESTART] Complete"
