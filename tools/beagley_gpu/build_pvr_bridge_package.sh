#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SRC_DIR="${HOME}/srcbuild/mesa-powervr-24.0.1"
DEFAULT_BUILD_DIR="${DEFAULT_SRC_DIR}/build-pvr-release"
OUT_DIR="${SCRIPT_DIR}/../../dist"
SRC_DIR="${DEFAULT_SRC_DIR}"
BUILD_DIR="${DEFAULT_BUILD_DIR}"
PACKAGE_NAME="beagley-pvr-bridge"
PACKAGE_VERSION="$(date -u +%Y%m%d.%H%M%S)"
CACHE_DIR="/usr/local/share/beagley/packages"
INSTALL_PACKAGE=0
SGX_USERSPACE_PACKAGE=""

usage() {
  cat <<'EOF'
Usage: build_pvr_bridge_package.sh [options]

Packages the built TI SGX/PowerVR bridge artifacts into a Debian package and
can optionally install/cache that package on the Beagley.

Options:
  --src-dir <path>         Mesa source directory (default: ~/srcbuild/mesa-powervr-24.0.1)
  --build-dir <path>       Mesa build directory (default: <src-dir>/build-pvr-release)
  --out-dir <path>         Output directory for the generated .deb
  --package-name <name>    Debian package name (default: beagley-pvr-bridge)
  --version <version>      Debian package version (default: UTC timestamp)
  --cache-dir <path>       Local cache directory for installed .debs
  --install                Cache and install the generated package
  --sgx-package <name>     Override the SGX userspace package dependency
  -h, --help               Show help
EOF
}

fail() {
  echo "[pvr-bridge-pkg] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[pvr-bridge-pkg] $*"
}

detect_sgx_userspace_package() {
  dpkg-query -W -f='${binary:Package}\n' 2>/dev/null \
    | grep -E '^ti-sgx-.*-ddx-um$' \
    | sort -V \
    | tail -n 1
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
    --src-dir)
      SRC_DIR="${2:-}"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --package-name)
      PACKAGE_NAME="${2:-}"
      shift 2
      ;;
    --version)
      PACKAGE_VERSION="${2:-}"
      shift 2
      ;;
    --cache-dir)
      CACHE_DIR="${2:-}"
      shift 2
      ;;
    --install)
      INSTALL_PACKAGE=1
      shift
      ;;
    --sgx-package)
      SGX_USERSPACE_PACKAGE="${2:-}"
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

command -v dpkg-deb >/dev/null 2>&1 || fail "dpkg-deb is required"
command -v dpkg >/dev/null 2>&1 || fail "dpkg is required"
command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

ARCH="$(dpkg --print-architecture)"
BUILD_DIR="${BUILD_DIR/#\~/$HOME}"
OUT_DIR="${OUT_DIR/#\~/$HOME}"
CACHE_DIR="${CACHE_DIR/#\~/$HOME}"

if [[ -z "$SGX_USERSPACE_PACKAGE" ]]; then
  SGX_USERSPACE_PACKAGE="$(detect_sgx_userspace_package)"
fi
[[ -n "$SGX_USERSPACE_PACKAGE" ]] || fail "unable to detect installed ti-sgx userspace package; pass --sgx-package explicitly"

SGX_DRI_SRC="${BUILD_DIR}/src/gallium/targets/dri/sgx_dri.so"
PVR_DRI_SRC="${BUILD_DIR}/src/gallium/targets/dri/pvr_dri.so"
TIDSS_DRI_SRC="${BUILD_DIR}/src/gallium/targets/dri/tidss_dri.so"

[[ -f "$SGX_DRI_SRC" ]] || fail "missing build artifact: $SGX_DRI_SRC"
[[ -f "$PVR_DRI_SRC" ]] || fail "missing build artifact: $PVR_DRI_SRC"
[[ -f "$TIDSS_DRI_SRC" ]] || fail "missing build artifact: $TIDSS_DRI_SRC"

mkdir -p "$OUT_DIR"
PACKAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$PACKAGE_ROOT"' EXIT

mkdir -p \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/usr/lib/aarch64-linux-gnu/dri" \
  "$PACKAGE_ROOT/usr/lib/aarch64-linux-gnu/gbm"

install -m 0644 "$SGX_DRI_SRC" \
  "$PACKAGE_ROOT/usr/lib/aarch64-linux-gnu/dri/sgx_dri.so"
ln -s sgx_dri.so \
  "$PACKAGE_ROOT/usr/lib/aarch64-linux-gnu/dri/pvr_dri.so"
ln -s sgx_dri.so \
  "$PACKAGE_ROOT/usr/lib/aarch64-linux-gnu/dri/tidss_dri.so"
ln -s dri_gbm.so \
  "$PACKAGE_ROOT/usr/lib/aarch64-linux-gnu/gbm/pvr_gbm.so"

cat >"$PACKAGE_ROOT/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${PACKAGE_VERSION}
Section: libs
Priority: optional
Architecture: ${ARCH}
Maintainer: Beagley Cluster <beagley@beagley.local>
Depends: libgl1-mesa-dri, libgbm1, mesa-libgallium, ${SGX_USERSPACE_PACKAGE}
Description: TI SGX DRI/GBM bridge for the Beagley cluster display
 This package installs the SGX DRI bridge artifacts required for the Beagley
 cluster to use the hardware GPU path under eglfs.
EOF

cat >"$PACKAGE_ROOT/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ldconfig
EOF
chmod 0755 "$PACKAGE_ROOT/DEBIAN/postinst"

cat >"$PACKAGE_ROOT/DEBIAN/postrm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ldconfig
EOF
chmod 0755 "$PACKAGE_ROOT/DEBIAN/postrm"

PACKAGE_FILE="${OUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"
SHA_FILE="${PACKAGE_FILE}.sha256"
dpkg-deb --root-owner-group --build "$PACKAGE_ROOT" "$PACKAGE_FILE" >/dev/null
sha256sum "$PACKAGE_FILE" >"$SHA_FILE"

log "built package: $PACKAGE_FILE"
log "sha256 file: $SHA_FILE"

if [[ $INSTALL_PACKAGE -eq 1 ]]; then
  run_as_root mkdir -p "$CACHE_DIR"
  CACHED_PACKAGE="${CACHE_DIR}/$(basename "$PACKAGE_FILE")"
  CACHED_SHA="${CACHED_PACKAGE}.sha256"
  run_as_root install -m 0644 "$PACKAGE_FILE" "$CACHED_PACKAGE"
  run_as_root install -m 0644 "$SHA_FILE" "$CACHED_SHA"
  log "cached package: $CACHED_PACKAGE"
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall "$CACHED_PACKAGE"
fi
