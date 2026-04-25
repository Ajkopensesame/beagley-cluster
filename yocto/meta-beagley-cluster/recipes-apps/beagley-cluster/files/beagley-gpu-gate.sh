#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/etc/beagley-gpu-cohort.lock"
STRICT=0
WRITE_OK_FILE=""
PVR_BRIDGE_PACKAGE="beagley-pvr-bridge"
GATE_MODE="bridge"

usage() {
  cat <<'EOF'
Usage: gpu_gate.sh [--lock <path>] [--strict] [--mode <bridge|appliance>] [--write-ok <path>]

Checks that the running graphics stack is hardware accelerated and matches
the pinned cohort lock (if present).
EOF
}

fail() {
  echo "[gpu-gate] FAIL: $*" >&2
  exit 1
}

warn() {
  echo "[gpu-gate] WARN: $*" >&2
}

find_connected_drm_card() {
  local status_path connector_name card_name

  for status_path in /sys/class/drm/card*-*/status; do
    [[ -e "$status_path" ]] || continue
    [[ "$(cat "$status_path" 2>/dev/null || true)" == "connected" ]] || continue

    connector_name="$(basename "$(dirname "$status_path")")"
    card_name="${connector_name%%-*}"
    [[ -e "/dev/dri/${card_name}" ]] || continue

    printf '%s\n' "/dev/dri/${card_name}"
    return 0
  done

  return 1
}

probe_renderer_output() {
  local kmscube_args=()
  local drm_card="${BEAGLEY_GPU_PROBE_DRM_CARD:-}"

  if command -v eglinfo >/dev/null 2>&1; then
    eglinfo -B 2>&1 || true
    return
  fi

  command -v kmscube >/dev/null 2>&1 || fail "eglinfo is required but not installed, and kmscube is unavailable"
  if [[ -z "$drm_card" ]]; then
    drm_card="$(find_connected_drm_card || true)"
  fi
  if [[ -z "$drm_card" && -e /dev/dri/card0 ]]; then
    drm_card="/dev/dri/card0"
  fi
  if [[ -n "$drm_card" ]]; then
    kmscube_args+=(-D "$drm_card")
  fi
  timeout 8 kmscube -c 1 "${kmscube_args[@]}" 2>&1 || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock)
      LOCK_FILE="${2:-}"
      shift 2
      ;;
    --mode)
      GATE_MODE="${2:-}"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --write-ok)
      WRITE_OK_FILE="${2:-}"
      shift 2
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

case "$GATE_MODE" in
  bridge|appliance)
    ;;
  *)
    fail "unknown gate mode: $GATE_MODE"
    ;;
esac

command -v lsmod >/dev/null 2>&1 || fail "lsmod is required but not installed"

DPKG_QUERY_AVAILABLE=0
if command -v dpkg-query >/dev/null 2>&1; then
  DPKG_QUERY_AVAILABLE=1
elif [[ "$GATE_MODE" == "bridge" ]]; then
  fail "dpkg-query is required but not installed"
fi

RENDER_PROBE_OUTPUT="$(probe_renderer_output)"
[[ -n "$RENDER_PROBE_OUTPUT" ]] || fail "renderer probe returned no output"
PVR_GBM_SO="/usr/lib/aarch64-linux-gnu/gbm/pvr_gbm.so"
SGX_DRI_SO="/usr/lib/aarch64-linux-gnu/dri/sgx_dri.so"
PVR_DRI_SO="/usr/lib/aarch64-linux-gnu/dri/pvr_dri.so"
TIDSS_DRI_SO="/usr/lib/aarch64-linux-gnu/dri/tidss_dri.so"
INSTALLED_MESA_VERSION=""
INSTALLED_SGX_PACKAGE=""
if [[ $DPKG_QUERY_AVAILABLE -eq 1 ]]; then
  INSTALLED_MESA_VERSION="$(dpkg-query -W -f='${Version}' mesa-libgallium 2>/dev/null || true)"
  INSTALLED_SGX_PACKAGE="$(
    dpkg-query -W -f='${binary:Package}\n' 2>/dev/null \
      | grep -E '^ti-sgx-.*-ddx-um$' \
      | sort -V \
      | tail -n 1
  )"
fi

package_owner() {
  local path="$1"
  [[ $DPKG_QUERY_AVAILABLE -eq 1 ]] || fail "dpkg-query is required in bridge mode"
  dpkg-query -S "$path" 2>/dev/null | awk -F': ' 'NR == 1 { print $1 }'
}

require_managed_bridge() {
  local path owner
  for path in "$SGX_DRI_SO" "$PVR_DRI_SO" "$TIDSS_DRI_SO" "$PVR_GBM_SO"; do
    [[ -e "$path" || -L "$path" ]] || fail "managed bridge file missing: $path"
    owner="$(package_owner "$path")"
    if [[ "$owner" != "$PVR_BRIDGE_PACKAGE" ]]; then
      fail "expected $path to be owned by $PVR_BRIDGE_PACKAGE, got ${owner:-unowned}"
    fi
  done

  if [[ "$(basename "$(readlink -f "$PVR_DRI_SO")")" != "sgx_dri.so" ]]; then
    fail "pvr_dri.so does not resolve to sgx_dri.so"
  fi
  if [[ "$(basename "$(readlink -f "$TIDSS_DRI_SO")")" != "sgx_dri.so" ]]; then
    fail "tidss_dri.so does not resolve to sgx_dri.so"
  fi
}

require_appliance_renderer() {
  if [[ "$RENDERER_LOWER" != *powervr* && "$RENDERER_LOWER" != *rogue* && "$RENDERER_LOWER" != *imagination* && "$RENDERER_LOWER" != *pvr* ]]; then
    fail "appliance mode expected a PowerVR renderer, got: $RENDERER"
  fi
}

RENDERER="$(
  printf '%s\n' "$RENDER_PROBE_OUTPUT" \
    | awk -F': ' 'tolower($0) ~ /opengl renderer string/ { print $2; exit }'
)"
if [[ -z "$RENDERER" ]]; then
  RENDERER="$(
    printf '%s\n' "$RENDER_PROBE_OUTPUT" \
      | awk -F': ' 'tolower($0) ~ /^device:/ { print $2; exit }'
  )"
fi
if [[ -z "$RENDERER" ]]; then
  RENDERER="$(
    printf '%s\n' "$RENDER_PROBE_OUTPUT" \
      | awk -F': ' 'tolower($0) ~ /egl driver name/ { print $2; exit }'
  )"
fi
if [[ -z "$RENDERER" ]]; then
  RENDERER="$(
    printf '%s\n' "$RENDER_PROBE_OUTPUT" \
      | awk -F'"' 'tolower($0) ~ /renderer:/ { print $2; exit }'
  )"
fi
[[ -n "$RENDERER" ]] || fail "unable to detect renderer from eglinfo -B or kmscube"

RENDERER_LOWER="$(printf '%s' "$RENDERER" | tr '[:upper:]' '[:lower:]')"
if [[ "$RENDERER_LOWER" == *llvmpipe* || "$RENDERER_LOWER" == *swrast* || "$RENDERER_LOWER" == *kms_swrast* || "$RENDERER_LOWER" == *software* ]]; then
  HINTS=()
  if lsmod | grep -q '^pvrsrvkm'; then
    HINTS+=("pvrsrvkm=loaded")
    if [[ ! -e "$SGX_DRI_SO" ]]; then
      HINTS+=("missing:$SGX_DRI_SO")
    fi
    if [[ ! -e "$PVR_GBM_SO" ]]; then
      HINTS+=("missing:$PVR_GBM_SO")
    fi
    if [[ ! -e "$PVR_DRI_SO" ]]; then
      HINTS+=("missing:$PVR_DRI_SO")
    fi
    if printf '%s\n' "$RENDER_PROBE_OUTPUT" | grep -q 'DRI2: failed to load driver'; then
      [[ -n "$INSTALLED_MESA_VERSION" ]] && HINTS+=("mesa=${INSTALLED_MESA_VERSION}")
      [[ -n "$INSTALLED_SGX_PACKAGE" ]] && HINTS+=("sgx=${INSTALLED_SGX_PACKAGE}")
      HINTS+=("pvr_dri_load_failed")
    fi
  else
    HINTS+=("pvrsrvkm=not_loaded")
  fi
  if [[ ${#HINTS[@]} -gt 0 ]]; then
    fail "software renderer detected: $RENDERER ($(IFS=', '; echo "${HINTS[*]}"))"
  fi
  fail "software renderer detected: $RENDERER"
fi

if [[ $STRICT -eq 1 ]]; then
  if [[ "$GATE_MODE" == "bridge" ]]; then
    require_managed_bridge
    require_appliance_renderer
  else
    require_appliance_renderer
  fi
fi

lsmod | grep -q '^pvrsrvkm' || fail "pvrsrvkm kernel module is not loaded"

if dmesg >/dev/null 2>&1; then
  if dmesg | grep -qi 'KM and FW version mismatch'; then
    fail "kernel/firmware mismatch reported in dmesg"
  fi
fi

if [[ "$GATE_MODE" == "bridge" && -f "$LOCK_FILE" ]]; then
  while IFS= read -r line; do
    [[ "$line" == pkg:* ]] || continue
    package_entry="${line#pkg:}"
    package_name="${package_entry%%=*}"
    expected_version="${package_entry#*=}"
    [[ -n "$package_name" && -n "$expected_version" ]] || continue
    installed_version="$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)"
    [[ -n "$installed_version" ]] || fail "package from lock missing: $package_name"
    if [[ "$installed_version" != "$expected_version" ]]; then
      fail "package version mismatch for $package_name: expected $expected_version got $installed_version"
    fi
  done <"$LOCK_FILE"
elif [[ "$GATE_MODE" == "bridge" && $STRICT -eq 1 ]]; then
  fail "strict mode requires lock file: $LOCK_FILE"
elif [[ "$GATE_MODE" == "bridge" ]]; then
  warn "lock file not found: $LOCK_FILE (continuing)"
fi

if [[ -n "$WRITE_OK_FILE" ]]; then
  mkdir -p "$(dirname "$WRITE_OK_FILE")"
  {
    echo "status=pass"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "mode=$GATE_MODE"
    echo "renderer=$RENDERER"
    echo "lock_file=$LOCK_FILE"
  } >"$WRITE_OK_FILE"
fi

echo "[gpu-gate] PASS mode=${GATE_MODE} renderer=$RENDERER lock=${LOCK_FILE}"
