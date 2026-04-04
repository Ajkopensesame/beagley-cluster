#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="/etc/beagley-gpu-cohort.lock"
WRITE_OK_FILE="/tmp/beagley_gpu_gate.ok"
BRIDGE_DEB=""
APPLY_HOLD=0

usage() {
  cat <<'EOF'
Usage: repair_in_place.sh [--bridge-deb <path>] [--lock <path>] [--write-ok <path>] [--apply-hold]

Bootstraps a deterministic Beagley GPU cohort on a drifted image.

- If the lock already exists, this script defers to reinstall_and_gate.sh.
- If no lock exists, it reinstalls the current graphics cohort packages, installs
  the local PowerVR bridge .deb, generates the cohort lock, and re-runs the
  strict gate against that lock.
EOF
}

fail() {
  echo "[gpu-repair] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[gpu-repair] $*"
}

lock_contains_software_renderer() {
  local renderer
  [[ -f "$1" ]] || return 1
  renderer="$(
    awk -F= '
      $1 == "eglinfo_renderer" || $1 == "renderer" { print tolower($2); exit }
    ' "$1"
  )"
  [[ "$renderer" == *llvmpipe* || "$renderer" == *swrast* || "$renderer" == *kms_swrast* || "$renderer" == *software* ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bridge-deb)
      BRIDGE_DEB="${2:-}"
      shift 2
      ;;
    --lock)
      LOCK_FILE="${2:-}"
      shift 2
      ;;
    --write-ok)
      WRITE_OK_FILE="${2:-}"
      shift 2
      ;;
    --apply-hold)
      APPLY_HOLD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ $EUID -eq 0 ]] || fail "must run as root"
command -v apt-get >/dev/null 2>&1 || fail "apt-get is required"
command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required"

if [[ -f "$LOCK_FILE" ]]; then
  if lock_contains_software_renderer "$LOCK_FILE"; then
    BAD_LOCK_BACKUP="${LOCK_FILE}.bad.$(date -u +%Y%m%dT%H%M%SZ)"
    log "existing lock records a software renderer; moving it to $BAD_LOCK_BACKUP"
    mv "$LOCK_FILE" "$BAD_LOCK_BACKUP"
  else
  ARGS=(--lock "$LOCK_FILE" --write-ok "$WRITE_OK_FILE")
  if [[ $APPLY_HOLD -eq 1 ]]; then
    ARGS+=(--apply-hold)
  fi
  exec "$SCRIPT_DIR/reinstall_and_gate.sh" "${ARGS[@]}"
  fi
fi

[[ -n "$BRIDGE_DEB" ]] || fail "--bridge-deb is required when lock file does not exist"
[[ -f "$BRIDGE_DEB" ]] || fail "bridge package not found: $BRIDGE_DEB"

declare -a PACKAGE_NAMES=()
while IFS= read -r package_name; do
  [[ -n "$package_name" ]] || continue
  PACKAGE_NAMES+=("$package_name")
done < <(
  dpkg-query -W -f='${binary:Package}\n' \
    | grep -E '^(ti-sgx|libegl|libgles|libgl1-mesa-dri|mesa-|libgbm|libdrm|qt6-base|qt6-declarative|qt6-webengine)' \
    | sort -u
)

[[ ${#PACKAGE_NAMES[@]} -gt 0 ]] || fail "no installed GPU cohort packages detected"

log "apt-get update"
DEBIAN_FRONTEND=noninteractive apt-get update

log "reinstalling ${#PACKAGE_NAMES[@]} current graphics packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall "${PACKAGE_NAMES[@]}"

log "installing bridge package $BRIDGE_DEB"
DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall "$BRIDGE_DEB"

log "validating hardware renderer before lock generation"
"$SCRIPT_DIR/gpu_gate.sh" --write-ok "$WRITE_OK_FILE"

log "writing new cohort lock to $LOCK_FILE"
"$SCRIPT_DIR/generate_cohort_lock.sh" --output "$LOCK_FILE"

log "re-running strict gate against the new lock"
"$SCRIPT_DIR/gpu_gate.sh" --strict --lock "$LOCK_FILE" --write-ok "$WRITE_OK_FILE"

if [[ $APPLY_HOLD -eq 1 ]]; then
  BRIDGE_PACKAGE_NAME="$(dpkg-deb -f "$BRIDGE_DEB" Package 2>/dev/null || true)"
  if [[ -n "$BRIDGE_PACKAGE_NAME" ]]; then
    PACKAGE_NAMES+=("$BRIDGE_PACKAGE_NAME")
  fi
  log "applying apt holds"
  apt-mark hold "${PACKAGE_NAMES[@]}"
fi

log "PASS lock=$LOCK_FILE ok_file=$WRITE_OK_FILE"
