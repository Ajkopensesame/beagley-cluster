#!/bin/bash
set -euo pipefail

HOST_NAME="beagley-ai.local"
HOST_USER="root"
HOST=""

nc_22_reachable() {
  local target="$1"
  if nc -h 2>&1 | grep -q -- "-G"; then
    nc -z -G 2 "$target" 22 >/dev/null 2>&1
  else
    nc -z -w 2 "$target" 22 >/dev/null 2>&1
  fi
}

resolve_ipv4_candidates() {
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$HOST_NAME" 2>/dev/null | awk '{print $1}'
  elif command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "$HOST_NAME" 2>/dev/null | awk '/^ip_address:/{print $2}'
  fi | awk 'NF && !seen[$0]++'
}

candidate_targets() {
  {
    printf '%s\n' "$HOST_NAME"
    printf '%s\n' ${BEAGLEY_EXTRA_HOSTS:-beagley-ai.modem beagley.local beagley.modem}
    resolve_ipv4_candidates
  } | awk 'NF && !seen[$0]++'
}

ssh_target_reachable() {
  local target="$1"
  ssh -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=accept-new \
    "${HOST_USER}@${target}" true >/dev/null 2>&1
}

pick_reachable_target() {
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if nc_22_reachable "$candidate" || ssh_target_reachable "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done < <(candidate_targets)
  return 1
}

ssh_run() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$HOST" "$@"
}

echo "[CHECK] Step 1: Network..."

TARGET="$(pick_reachable_target || true)"
if [[ -z "$TARGET" ]]; then
  echo "[FAIL] No reachable SSH endpoint resolved from $HOST_NAME"
  exit 2
fi
HOST="${HOST_USER}@${TARGET}"
echo "[OK] Network reachable via $TARGET"

echo "[CHECK] Step 2: SSH..."

ssh_run "true"
echo "[OK] SSH available"

echo "[CHECK] Step 3: Service state..."

STATE=$(ssh_run "systemctl is-active beagley_cluster" 2>/dev/null || echo "unknown")
RESTARTS=$(ssh_run "systemctl show beagley_cluster -p NRestarts --value" 2>/dev/null || echo "0")

echo "[INFO] state=$STATE restarts=$RESTARTS"

# 🚨 Detect restart loop
if [ "$RESTARTS" -gt 5 ]; then
  echo "[FAIL] Service is restarting repeatedly (restart loop)"
  ssh_run "systemctl status beagley_cluster --no-pager"
  exit 1
fi

# Normal active check
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
