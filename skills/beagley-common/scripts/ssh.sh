#!/bin/bash

BEAGLEY_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEAGLEY_PROJECT_ROOT="$(cd "$BEAGLEY_COMMON_DIR/../../.." && pwd)"
BEAGLEY_TARGET_ENV="${BEAGLEY_TARGET_ENV:-$BEAGLEY_PROJECT_ROOT/config/beagley-target.env}"
BEAGLEY_ENV_HOST="${BEAGLEY_HOST:-}"
BEAGLEY_ENV_HOST_NAME="${BEAGLEY_HOST_NAME:-}"
BEAGLEY_ENV_HOST_USER="${BEAGLEY_HOST_USER:-}"

if [[ -f "$BEAGLEY_TARGET_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$BEAGLEY_TARGET_ENV"
fi

if [[ -n "$BEAGLEY_ENV_HOST" ]]; then
  BEAGLEY_HOST="$BEAGLEY_ENV_HOST"
fi
if [[ -n "$BEAGLEY_ENV_HOST_NAME" ]]; then
  BEAGLEY_HOST_NAME="$BEAGLEY_ENV_HOST_NAME"
fi
if [[ -n "$BEAGLEY_ENV_HOST_USER" ]]; then
  BEAGLEY_HOST_USER="$BEAGLEY_ENV_HOST_USER"
fi

: "${BEAGLEY_HOST_NAME:=beagley-ai.local}"
: "${BEAGLEY_HOST_USER:=root}"

BEAGLEY_CONFIGURED_TARGET="${BEAGLEY_HOST:-}"
if [[ -n "$BEAGLEY_CONFIGURED_TARGET" && "$BEAGLEY_CONFIGURED_TARGET" == *@* ]]; then
  BEAGLEY_HOST_USER="${BEAGLEY_CONFIGURED_TARGET%@*}"
  BEAGLEY_CONFIGURED_TARGET="${BEAGLEY_CONFIGURED_TARGET#*@}"
fi

BEAGLEY_SSH_TARGET=""
BEAGLEY_SSH_HOST=""
BEAGLEY_SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ConnectionAttempts=1
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=1
  -o StrictHostKeyChecking=accept-new
)
BEAGLEY_SCP_OPTS=("${BEAGLEY_SSH_OPTS[@]}")

beagley_is_ipv4() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
}

beagley_nc_22_reachable() {
  local target="$1"
  beagley_is_ipv4 "$target" || return 1
  if [[ "$(uname -s)" == "Darwin" ]] || nc -h 2>&1 | grep -q -- "-G"; then
    nc -z -G 2 "$target" 22 >/dev/null 2>&1
  else
    nc -z -w 2 "$target" 22 >/dev/null 2>&1
  fi
}

beagley_resolve_mdns_ipv4() {
  command -v dns-sd >/dev/null 2>&1 || return 0

  local tmp pid
  tmp="$(mktemp "${TMPDIR:-/tmp}/beagley-mdns.XXXXXX")"
  (
    dns-sd -G v4 "$BEAGLEY_HOST_NAME" >"$tmp" 2>/dev/null &
    pid=$!
    sleep 2
    kill "$pid" >/dev/null 2>&1 || true
    sleep 0.1
    kill -KILL "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  ) 2>/dev/null
  awk '/ Add / && $NF ~ /^[0-9]+(\.[0-9]+){3}$/ { print $NF }' "$tmp"
  rm -f "$tmp"
}

beagley_resolve_system_ipv4() {
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$BEAGLEY_HOST_NAME" 2>/dev/null | awk '{print $1}'
    return 0
  fi

  command -v dscacheutil >/dev/null 2>&1 || return 0

  local tmp pid
  tmp="$(mktemp "${TMPDIR:-/tmp}/beagley-dns.XXXXXX")"
  (
    dscacheutil -q host -a name "$BEAGLEY_HOST_NAME" >"$tmp" 2>/dev/null &
    pid=$!
    sleep 2
    kill "$pid" >/dev/null 2>&1 || true
    sleep 0.1
    kill -KILL "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  ) 2>/dev/null
  awk '/^ip_address:/{print $2}' "$tmp"
  rm -f "$tmp"
}

beagley_resolve_ipv4_candidates() {
  {
    beagley_resolve_mdns_ipv4
    beagley_resolve_system_ipv4
  } | awk 'NF && !seen[$0]++'
}

beagley_candidate_targets() {
  {
    printf '%s\n' "$BEAGLEY_CONFIGURED_TARGET"
    beagley_resolve_ipv4_candidates
    printf '%s\n' ${BEAGLEY_EXTRA_HOSTS:-}
    if [[ "${BEAGLEY_ALLOW_HOSTNAME_FALLBACK:-0}" == "1" ]]; then
      printf '%s\n' "$BEAGLEY_HOST_NAME"
      printf '%s\n' beagley-ai.modem beagley.local beagley.modem
    fi
  } | awk 'NF && !seen[$0]++'
}

beagley_ssh_target_reachable() {
  local target="$1"
  ssh "${BEAGLEY_SSH_OPTS[@]}" "${BEAGLEY_HOST_USER}@${target}" true >/dev/null 2>&1
}

beagley_pick_reachable_target() {
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if beagley_is_ipv4 "$candidate"; then
      if beagley_nc_22_reachable "$candidate"; then
        printf '%s' "$candidate"
        return 0
      fi
    else
      if beagley_ssh_target_reachable "$candidate"; then
        printf '%s' "$candidate"
        return 0
      fi
    fi
  done < <(beagley_candidate_targets)
  return 1
}

beagley_require_ssh_target() {
  BEAGLEY_SSH_TARGET="$(beagley_pick_reachable_target || true)"
  if [[ -z "$BEAGLEY_SSH_TARGET" ]]; then
    return 1
  fi
  BEAGLEY_SSH_HOST="${BEAGLEY_HOST_USER}@${BEAGLEY_SSH_TARGET}"
  return 0
}

beagley_ssh() {
  ssh "${BEAGLEY_SSH_OPTS[@]}" "$BEAGLEY_SSH_HOST" "$@"
}

beagley_scp_to() {
  local local_path="$1"
  local remote_path="$2"
  scp "${BEAGLEY_SCP_OPTS[@]}" "$local_path" "${BEAGLEY_SSH_HOST}:${remote_path}"
}
