#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE="/etc/beagley-gpu-cohort.lock"
PVR_BRIDGE_PACKAGE="beagley-pvr-bridge"
PVR_BRIDGE_CACHE_DIR="/usr/local/share/beagley/packages"

usage() {
  cat <<'EOF'
Usage: generate_cohort_lock.sh [--output <path>]

Captures a deterministic graphics package cohort for Beagley.
EOF
}

fail() {
  echo "[gpu-lock] FAIL: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="${2:-}"
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

command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v eglinfo >/dev/null 2>&1 || fail "eglinfo is required"

EGLINFO_OUTPUT="$(eglinfo -B 2>&1 || true)"
RENDERER="$(
  printf '%s\n' "$EGLINFO_OUTPUT" \
    | awk -F': ' 'tolower($0) ~ /opengl renderer string/ { print $2; exit }'
)"
if [[ -z "$RENDERER" ]]; then
  RENDERER="$(
    printf '%s\n' "$EGLINFO_OUTPUT" \
      | awk -F': ' 'tolower($0) ~ /egl driver name/ { print $2; exit }'
  )"
fi
VENDOR="$(
  printf '%s\n' "$EGLINFO_OUTPUT" \
    | awk -F': ' 'tolower($0) ~ /opengl vendor string/ { print $2; exit }'
)"

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

BRIDGE_VERSION="$(dpkg-query -W -f='${Version}' "$PVR_BRIDGE_PACKAGE" 2>/dev/null || true)"
BRIDGE_DEB=""
if [[ -n "$BRIDGE_VERSION" ]]; then
  BRIDGE_DEB="$(
    find "$PVR_BRIDGE_CACHE_DIR" -maxdepth 1 -type f \
      -name "${PVR_BRIDGE_PACKAGE}_${BRIDGE_VERSION}_*.deb" \
      | sort \
      | tail -n 1
  )"
  [[ -n "$BRIDGE_DEB" ]] || fail "missing cached .deb for ${PVR_BRIDGE_PACKAGE} ${BRIDGE_VERSION} in ${PVR_BRIDGE_CACHE_DIR}"
fi

{
  echo "# Beagley GPU Cohort Lock v1"
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "hostname=$(hostname)"
  echo "kernel_release=$(uname -r)"
  echo "kernel_arch=$(uname -m)"
  echo "eglinfo_renderer=${RENDERER}"
  echo "eglinfo_vendor=${VENDOR}"
  if [[ -n "$BRIDGE_VERSION" ]]; then
    echo "bridge_package=${PVR_BRIDGE_PACKAGE}"
    echo "local_pkg:${PVR_BRIDGE_PACKAGE}=${BRIDGE_DEB}"
  fi
  if lsmod | grep -q '^pvrsrvkm'; then
    echo "pvrsrvkm_loaded=1"
  else
    echo "pvrsrvkm_loaded=0"
  fi
  if modinfo -n pvrsrvkm >/dev/null 2>&1; then
    echo "pvrsrvkm_module_path=$(modinfo -n pvrsrvkm)"
  fi
  echo
  echo "# Pinned package versions"
  dpkg-query -W -f='${binary:Package}=${Version}\n' \
    | grep -E "^(beagley-pvr-bridge|ti-sgx|libegl|libgles|libgl1-mesa-dri|mesa-|libgbm|libdrm|qt6-base|qt6-declarative|qt6-webengine)" \
    | sort -u \
    | sed 's/^/pkg:/'
  echo
  echo "# Key userspace library hashes"
  for lib in \
    /usr/lib/aarch64-linux-gnu/libEGL.so.1 \
    /usr/lib/aarch64-linux-gnu/libGLESv2.so.2 \
    /usr/lib/aarch64-linux-gnu/libgbm.so.1
  do
    if [[ -f "$lib" ]]; then
      echo "sha256:${lib}=$(sha256sum "$lib" | awk '{print $1}')"
    fi
  done
  if [[ -d /usr/lib/aarch64-linux-gnu/dri ]]; then
    while IFS= read -r dri_lib; do
      echo "sha256:${dri_lib}=$(sha256sum "$dri_lib" | awk '{print $1}')"
    done < <(find /usr/lib/aarch64-linux-gnu/dri -maxdepth 1 -type f | sort)
  fi
  if [[ -n "$BRIDGE_DEB" ]]; then
    echo "sha256:${BRIDGE_DEB}=$(sha256sum "$BRIDGE_DEB" | awk '{print $1}')"
  fi
} >"$TMP_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"
cp "$TMP_FILE" "$OUTPUT_FILE"

echo "[gpu-lock] wrote $OUTPUT_FILE"
