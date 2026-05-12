#!/bin/bash

BEAGLEY_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEAGLEY_PROJECT_ROOT="$(cd "$BEAGLEY_COMMON_DIR/../../.." && pwd)"
BEAGLEY_TARGET_ENV="${BEAGLEY_TARGET_ENV:-$BEAGLEY_PROJECT_ROOT/config/beagley-target.env}"
BEAGLEY_ENV_HOST="${BEAGLEY_HOST:-}"
BEAGLEY_ENV_TARGETS="${BEAGLEY_TARGETS:-}"
BEAGLEY_ENV_HOST_NAME="${BEAGLEY_HOST_NAME:-}"
BEAGLEY_ENV_HOST_USER="${BEAGLEY_HOST_USER:-}"

if [[ -f "$BEAGLEY_TARGET_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$BEAGLEY_TARGET_ENV"
fi

if [[ -n "$BEAGLEY_ENV_HOST" ]]; then
  BEAGLEY_HOST="$BEAGLEY_ENV_HOST"
fi
if [[ -n "$BEAGLEY_ENV_TARGETS" ]]; then
  BEAGLEY_TARGETS="$BEAGLEY_ENV_TARGETS"
fi
if [[ -n "$BEAGLEY_ENV_HOST_NAME" ]]; then
  BEAGLEY_HOST_NAME="$BEAGLEY_ENV_HOST_NAME"
fi
if [[ -n "$BEAGLEY_ENV_HOST_USER" ]]; then
  BEAGLEY_HOST_USER="$BEAGLEY_ENV_HOST_USER"
fi

: "${BEAGLEY_HOST_NAME:=beagley-ai.local}"
: "${BEAGLEY_HOST_USER:=root}"

BEAGLEY_SSH_TARGET=""
BEAGLEY_SSH_HOST=""
BEAGLEY_SELECTED_HOST_USER=""
BEAGLEY_SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ConnectionAttempts=1
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=1
  -o StrictHostKeyChecking=accept-new
)
BEAGLEY_SCP_OPTS=("${BEAGLEY_SSH_OPTS[@]}")
BEAGLEY_CONFIGURED_TARGETS=()

beagley_add_targets() {
  local raw="${1:-}"
  local target

  raw="${raw//,/ }"
  for target in $raw; do
    [[ -n "$target" ]] || continue
    BEAGLEY_CONFIGURED_TARGETS+=("$target")
  done
}

if [[ -n "${BEAGLEY_HOST:-}" ]]; then
  # BEAGLEY_HOST remains a one-off override for direct debugging.
  beagley_add_targets "$BEAGLEY_HOST"
elif [[ -n "${BEAGLEY_TARGETS:-}" ]]; then
  beagley_add_targets "$BEAGLEY_TARGETS"
fi

if [[ "${#BEAGLEY_CONFIGURED_TARGETS[@]}" -eq 0 ]]; then
  beagley_add_targets "$BEAGLEY_HOST_NAME"
fi

beagley_is_ipv4() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
}

beagley_nc_22_reachable() {
  local target="$1"
  beagley_is_ipv4 "$target" || return 1
  command -v nc >/dev/null 2>&1 || return 0
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
    printf '%s\n' "${BEAGLEY_CONFIGURED_TARGETS[@]}"
    beagley_resolve_ipv4_candidates
    printf '%s\n' ${BEAGLEY_EXTRA_HOSTS:-}
    if [[ "${BEAGLEY_ALLOW_HOSTNAME_FALLBACK:-0}" == "1" ]]; then
      printf '%s\n' "$BEAGLEY_HOST_NAME"
      printf '%s\n' beagley-ai.modem beagley.local beagley.modem
    fi
  } | awk 'NF && !seen[$0]++'
}

beagley_split_target() {
  local raw="$1"

  BEAGLEY_CANDIDATE_USER="$BEAGLEY_HOST_USER"
  BEAGLEY_CANDIDATE_TARGET="$raw"
  if [[ "$raw" == *@* ]]; then
    BEAGLEY_CANDIDATE_USER="${raw%@*}"
    BEAGLEY_CANDIDATE_TARGET="${raw#*@}"
  fi
}

beagley_ssh_target_reachable() {
  local user="$1"
  local target="$2"

  ssh "${BEAGLEY_SSH_OPTS[@]}" "${user}@${target}" true >/dev/null 2>&1
}

beagley_pick_reachable_target() {
  local candidate
  local user
  local target

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    beagley_split_target "$candidate"
    user="$BEAGLEY_CANDIDATE_USER"
    target="$BEAGLEY_CANDIDATE_TARGET"

    if beagley_is_ipv4 "$target" && ! beagley_nc_22_reachable "$target"; then
      continue
    fi

    if beagley_ssh_target_reachable "$user" "$target"; then
      BEAGLEY_SELECTED_HOST_USER="$user"
      printf '%s' "$target"
      return 0
    fi
  done < <(beagley_candidate_targets)
  return 1
}

beagley_require_ssh_target() {
  BEAGLEY_SSH_TARGET="$(beagley_pick_reachable_target || true)"
  if [[ -z "$BEAGLEY_SSH_TARGET" ]]; then
    return 1
  fi
  BEAGLEY_HOST_USER="${BEAGLEY_SELECTED_HOST_USER:-$BEAGLEY_HOST_USER}"
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
