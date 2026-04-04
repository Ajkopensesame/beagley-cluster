#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/etc/beagley-gpu-cohort.lock"
APPLY_HOLD=0

usage() {
  cat <<'EOF'
Usage: reinstall_from_cohort_lock.sh [--lock <path>] [--apply-hold]

Reinstalls the exact package versions listed in the cohort lock.
Must run as root.
EOF
}

fail() {
  echo "[gpu-reinstall] FAIL: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock)
      LOCK_FILE="${2:-}"
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
command -v apt-get >/dev/null 2>&1 || fail "apt-get is required"

declare -a PACKAGE_PINS=()
declare -a PACKAGE_NAMES=()
declare -a LOCAL_PACKAGE_NAMES=()
declare -a LOCAL_PACKAGE_PATHS=()
declare -a LOCAL_PACKAGE_SHAS=()

local_package_index_by_name() {
  local name="$1"
  local i
  for ((i = 0; i < ${#LOCAL_PACKAGE_NAMES[@]}; ++i)); do
    if [[ "${LOCAL_PACKAGE_NAMES[$i]}" == "$name" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

local_package_index_by_path() {
  local path="$1"
  local i
  for ((i = 0; i < ${#LOCAL_PACKAGE_PATHS[@]}; ++i)); do
    if [[ "${LOCAL_PACKAGE_PATHS[$i]}" == "$path" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

while IFS= read -r line; do
  [[ "$line" == local_pkg:* ]] || continue
  entry="${line#local_pkg:}"
  name="${entry%%=*}"
  path="${entry#*=}"
  [[ -n "$name" && -n "$path" ]] || continue
  LOCAL_PACKAGE_NAMES+=("$name")
  LOCAL_PACKAGE_PATHS+=("$path")
  LOCAL_PACKAGE_SHAS+=("")
done <"$LOCK_FILE"

while IFS= read -r line; do
  [[ "$line" == sha256:* ]] || continue
  entry="${line#sha256:}"
  path="${entry%%=*}"
  sha="${entry#*=}"
  [[ -n "$path" && -n "$sha" ]] || continue
  if index="$(local_package_index_by_path "$path" 2>/dev/null)"; then
    LOCAL_PACKAGE_SHAS[$index]="$sha"
  fi
done <"$LOCK_FILE"

while IFS= read -r line; do
  [[ "$line" == pkg:* ]] || continue
  entry="${line#pkg:}"
  name="${entry%%=*}"
  version="${entry#*=}"
  [[ -n "$name" && -n "$version" ]] || continue
  if local_package_index_by_name "$name" >/dev/null 2>&1; then
    PACKAGE_NAMES+=("$name")
    continue
  fi
  PACKAGE_PINS+=("${name}=${version}")
  PACKAGE_NAMES+=("${name}")
done <"$LOCK_FILE"

if [[ ${#PACKAGE_PINS[@]} -eq 0 && ${#LOCAL_PACKAGE_NAMES[@]} -eq 0 ]]; then
  fail "no packages found in lock file"
fi

echo "[gpu-reinstall] apt-get update"
DEBIAN_FRONTEND=noninteractive apt-get update

if [[ ${#PACKAGE_PINS[@]} -gt 0 ]]; then
  echo "[gpu-reinstall] reinstalling ${#PACKAGE_PINS[@]} pinned packages"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall --allow-downgrades "${PACKAGE_PINS[@]}"
fi

if [[ ${#LOCAL_PACKAGE_NAMES[@]} -gt 0 ]]; then
  for ((i = 0; i < ${#LOCAL_PACKAGE_NAMES[@]}; ++i)); do
    local_name="${LOCAL_PACKAGE_NAMES[$i]}"
    local_path="${LOCAL_PACKAGE_PATHS[$i]}"
    local_sha="${LOCAL_PACKAGE_SHAS[$i]}"
    [[ -f "$local_path" ]] || fail "local package missing from lock: $local_path"
    if [[ -n "$local_sha" ]]; then
      actual_sha="$(sha256sum "$local_path" | awk '{print $1}')"
      [[ "$actual_sha" == "$local_sha" ]] || fail "sha256 mismatch for $local_path"
    fi
    echo "[gpu-reinstall] reinstalling local package ${local_name} from ${local_path}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall "$local_path"
  done
fi

if [[ $APPLY_HOLD -eq 1 ]]; then
  echo "[gpu-reinstall] applying apt holds"
  apt-mark hold "${PACKAGE_NAMES[@]}"
fi

echo "[gpu-reinstall] done"
