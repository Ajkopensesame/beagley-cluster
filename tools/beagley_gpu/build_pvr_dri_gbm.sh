#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MESA_REPO="https://gitlab.freedesktop.org/StaticRocket/mesa.git"
MESA_BRANCH="powervr/24.0.1"
SRC_ROOT="${HOME}/srcbuild"
SRC_DIR="${SRC_ROOT}/mesa-powervr-24.0.1"
BUILD_DIR="${SRC_DIR}/build-pvr-release"
DRI_DIR="/usr/lib/aarch64-linux-gnu/dri"
GBM_DIR="/usr/lib/aarch64-linux-gnu/gbm"
JOBS="$(nproc)"
INSTALL=0
SETUP_DEPS=1
RUN_GATE=1
WIPE_BUILD=1
ALLOW_VERSION_MISMATCH=0

usage() {
  cat <<'EOF'
Usage: build_pvr_dri_gbm.sh [options]

Builds the TI SGX/PowerVR Mesa DRI bridge targets and optionally installs them.

Options:
  --repo <url>           Mesa git URL (default: StaticRocket mesa)
  --branch <name>        Mesa branch/tag (default: powervr/24.0.1)
  --src-dir <path>       Source directory (default: ~/srcbuild/mesa-powervr-24.0.1)
  --build-dir <path>     Build directory (default: <src-dir>/build-pvr-release)
  --jobs <n>             Parallel build jobs (default: nproc)
  --no-deps              Skip apt build dependency setup
  --no-gate              Skip gpu_gate.sh after install
  --no-wipe              Reuse existing Meson build directory
  --install              Install built sgx_dri/pvr_dri/tidss_dri + pvr_gbm alias
  --allow-version-mismatch
                         Allow building against a Mesa/PVR bridge branch that
                         does not match the installed Mesa major.minor series
  -h, --help             Show help

Notes:
  - --install writes into /usr/lib and uses sudo when not root.
  - This script follows TI's SGX DRI bridge layout: sgx_dri.so is the primary
    DRI target and pvr_dri.so/tidss_dri.so resolve back to it.
EOF
}

log() {
  echo "[pvr-build] $*"
}

fail() {
  echo "[pvr-build] FAIL: $*" >&2
  exit 1
}

installed_mesa_version() {
  dpkg-query -W -f='${Version}' mesa-libgallium 2>/dev/null || true
}

version_series() {
  local version="$1"
  if [[ "$version" =~ ^([0-9]+)\.([0-9]+) ]]; then
    printf '%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  fi
}

run_as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      MESA_REPO="${2:-}"
      shift 2
      ;;
    --branch)
      MESA_BRANCH="${2:-}"
      shift 2
      ;;
    --src-dir)
      SRC_DIR="${2:-}"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="${2:-}"
      shift 2
      ;;
    --jobs)
      JOBS="${2:-}"
      shift 2
      ;;
    --no-deps)
      SETUP_DEPS=0
      shift
      ;;
    --no-gate)
      RUN_GATE=0
      shift
      ;;
    --no-wipe)
      WIPE_BUILD=0
      shift
      ;;
    --install)
      INSTALL=1
      shift
      ;;
    --allow-version-mismatch)
      ALLOW_VERSION_MISMATCH=1
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

command -v git >/dev/null 2>&1 || fail "git is required"
command -v meson >/dev/null 2>&1 || fail "meson is required"
command -v ninja >/dev/null 2>&1 || fail "ninja is required"
command -v eglinfo >/dev/null 2>&1 || fail "eglinfo is required"
command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required"

INSTALLED_MESA_VERSION="$(installed_mesa_version)"
if [[ -n "$INSTALLED_MESA_VERSION" ]]; then
  INSTALLED_MESA_SERIES="$(version_series "$INSTALLED_MESA_VERSION")"
  BRANCH_SERIES="$(version_series "${MESA_BRANCH##*/}")"
  if [[ -n "$INSTALLED_MESA_SERIES" && -n "$BRANCH_SERIES" && "$INSTALLED_MESA_SERIES" != "$BRANCH_SERIES" && $ALLOW_VERSION_MISMATCH -ne 1 ]]; then
    fail "installed mesa-libgallium is ${INSTALLED_MESA_VERSION} (series ${INSTALLED_MESA_SERIES}) but bridge branch ${MESA_BRANCH} targets ${BRANCH_SERIES}; this combination is known to fall back to kms_swrast with DRI2 driver load failures"
  fi
fi

if [[ $SETUP_DEPS -eq 1 ]]; then
  log "installing mesa build dependencies"
  run_as_root apt-get update
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get build-dep -y mesa
fi

mkdir -p "$(dirname "$SRC_DIR")"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  log "cloning ${MESA_REPO} (${MESA_BRANCH}) into ${SRC_DIR}"
  git clone --depth 1 --branch "$MESA_BRANCH" "$MESA_REPO" "$SRC_DIR"
else
  log "using existing source tree: ${SRC_DIR}"
fi

cd "$SRC_DIR"

if [[ $WIPE_BUILD -eq 1 ]]; then
  MESA_SETUP_FLAGS=(--wipe)
else
  MESA_SETUP_FLAGS=()
fi

log "configuring meson build: ${BUILD_DIR}"
meson setup "$BUILD_DIR" "${MESA_SETUP_FLAGS[@]}" \
  -Dbuildtype=release \
  -Dprefix=/usr \
  -Dlibdir=lib/aarch64-linux-gnu \
  -Dplatforms=auto \
  -Degl=enabled \
  -Dgbm=enabled \
  -Dglx=disabled \
  -Dgallium-drivers=sgx,swrast,kmsro \
  -Dvulkan-drivers= \
  -Dllvm=enabled

log "building sgx_dri/pvr_dri/tidss_dri targets (jobs=${JOBS})"
ninja -C "$BUILD_DIR" -j"$JOBS" \
  src/gallium/targets/dri/sgx_dri.so \
  src/gallium/targets/dri/pvr_dri.so \
  src/gallium/targets/dri/tidss_dri.so

SGX_DRI_SRC="${BUILD_DIR}/src/gallium/targets/dri/sgx_dri.so"
PVR_DRI_SRC="${BUILD_DIR}/src/gallium/targets/dri/pvr_dri.so"
TIDSS_DRI_SRC="${BUILD_DIR}/src/gallium/targets/dri/tidss_dri.so"

[[ -e "$SGX_DRI_SRC" ]] || fail "missing build artifact: $SGX_DRI_SRC"
[[ -e "$PVR_DRI_SRC" ]] || fail "missing build artifact: $PVR_DRI_SRC"
[[ -e "$TIDSS_DRI_SRC" ]] || fail "missing build artifact: $TIDSS_DRI_SRC"

log "build artifacts ready"
log "  sgx_dri: $(readlink -f "$SGX_DRI_SRC")"
log "  pvr_dri: $(readlink -f "$PVR_DRI_SRC")"
log "  tidss_dri: $(readlink -f "$TIDSS_DRI_SRC")"

if [[ $INSTALL -eq 1 ]]; then
  TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  BACKUP_DIR="/usr/local/share/beagley-pvr-backup-${TIMESTAMP}"
  log "installing artifacts with backup dir: ${BACKUP_DIR}"

  run_as_root mkdir -p "$DRI_DIR" "$GBM_DIR" "$BACKUP_DIR"
  for f in sgx_dri.so pvr_dri.so tidss_dri.so; do
    if [[ -e "${DRI_DIR}/${f}" || -L "${DRI_DIR}/${f}" ]]; then
      run_as_root cp -a "${DRI_DIR}/${f}" "$BACKUP_DIR/"
    fi
  done
  if [[ -e "${GBM_DIR}/pvr_gbm.so" || -L "${GBM_DIR}/pvr_gbm.so" ]]; then
    run_as_root cp -a "${GBM_DIR}/pvr_gbm.so" "$BACKUP_DIR/"
  fi

  run_as_root install -m 0644 "$SGX_DRI_SRC" "${DRI_DIR}/sgx_dri.so"
  run_as_root ln -sfn sgx_dri.so "${DRI_DIR}/pvr_dri.so"
  run_as_root ln -sfn sgx_dri.so "${DRI_DIR}/tidss_dri.so"
  run_as_root ln -sfn dri_gbm.so "${GBM_DIR}/pvr_gbm.so"
  run_as_root ldconfig

  log "install complete"
  log "renderer probe:"
  eglinfo -B | sed -n '1,120p'

  if [[ $RUN_GATE -eq 1 ]]; then
    "${SCRIPT_DIR}/gpu_gate.sh" || fail "gpu gate failed after install"
  fi
fi

log "done"
