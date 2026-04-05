#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="/etc/beagley-gpu-cohort.lock"
WRITE_OK_FILE="/tmp/beagley_gpu_gate.ok"
APPLY_HOLD=0

usage() {
  cat <<'EOF'
Usage: reinstall_and_gate.sh [--lock <path>] [--write-ok <path>] [--apply-hold]

Runs deterministic GPU stack reinstall from lock, then validates the gate.
Must run as root.
EOF
}

fail() {
  echo "[gpu-reinstall+gate] FAIL: $*" >&2
  exit 1
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
[[ -f "$LOCK_FILE" ]] || fail "lock file not found: $LOCK_FILE"

if lock_contains_software_renderer "$LOCK_FILE"; then
  fail "lock file records a software renderer; regenerate it with repair_in_place.sh after hardware EGL is restored"
fi

REINSTALL_ARGS=(--lock "$LOCK_FILE")
if [[ $APPLY_HOLD -eq 1 ]]; then
  REINSTALL_ARGS+=(--apply-hold)
fi

"$SCRIPT_DIR/reinstall_from_cohort_lock.sh" "${REINSTALL_ARGS[@]}"
"$SCRIPT_DIR/gpu_gate.sh" --strict --lock "$LOCK_FILE" --write-ok "$WRITE_OK_FILE"

echo "[gpu-reinstall+gate] PASS lock=$LOCK_FILE ok_file=$WRITE_OK_FILE"
