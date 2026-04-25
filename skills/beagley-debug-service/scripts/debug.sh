#!/bin/bash
set -u  # remove -e so it doesn't stop on failure

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
  if [[ -z "$HOST" ]]; then
    echo "[WARN] No reachable SSH endpoint resolved from $HOST_NAME"
    return 0
  fi
  ssh -o BatchMode=yes \
    -o ConnectTimeout=8 \
    -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=accept-new \
    "$HOST" "$@" || true
}

TARGET="$(pick_reachable_target || true)"
if [[ -n "$TARGET" ]]; then
  HOST="${HOST_USER}@${TARGET}"
  echo "[DEBUG] SSH target: $TARGET"
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
