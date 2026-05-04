#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${YOCTO_BUILD_DIR:-/home/pneumaion/ti-sdk-11.00/yocto-build/build}"
TARGET="beagley-cluster"
CLEAN=1
FAIL_DIRTY=1

usage() {
  cat <<'EOF'
Usage:
  tools/yocto/build_beagley_cluster_app.sh [options]

Builds the BeagleY app through the Yocto tree after verifying the exact source
repo, branch, and commit that BitBake will fetch. Use this instead of raw
`bitbake beagley-cluster`.

Options:
  --build-dir DIR      Yocto build dir. Default: YOCTO_BUILD_DIR or
                       /home/pneumaion/ti-sdk-11.00/yocto-build/build
  --no-clean           Skip `bitbake beagley-cluster -c clean`.
  --allow-dirty        Allow a dirty source checkout. Avoid this for production
                       deploys because Yocto builds committed HEAD only.
  --fail-dirty         Kept for compatibility; dirty source is already fatal by
                       default.
EOF
}

fail() {
  echo "[yocto-app-build] FAIL: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      BUILD_DIR="${2:-}"
      shift 2
      ;;
    --no-clean)
      CLEAN=0
      shift
      ;;
    --allow-dirty)
      FAIL_DIRTY=0
      shift
      ;;
    --fail-dirty)
      FAIL_DIRTY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -f "$BUILD_DIR/conf/setenv" ]] || fail "missing Yocto setenv: $BUILD_DIR/conf/setenv"

MANIFEST_DIR="$ROOT/build/yocto"
MANIFEST_PATH="$MANIFEST_DIR/beagley-cluster-source-manifest.env"
VERIFY_ARGS=(--build-dir "$BUILD_DIR" --expected-repo "$ROOT" --write-manifest "$MANIFEST_PATH")
if [[ "$FAIL_DIRTY" == 1 ]]; then
  VERIFY_ARGS+=(--fail-dirty)
fi

"$ROOT/tools/yocto/verify_beagley_build_source.sh" "${VERIFY_ARGS[@]}"

echo "[yocto-app-build] Source manifest: $MANIFEST_PATH"
echo "[yocto-app-build] Building $TARGET in $BUILD_DIR"
cd "$BUILD_DIR"
. conf/setenv

if [[ "$CLEAN" == 1 ]]; then
  bitbake "$TARGET" -c clean
fi
bitbake "$TARGET"

BIN_PATH="$(find "$BUILD_DIR" -path "*/work/aarch64-oe-linux/$TARGET/1.0/build/beagley_cluster" -type f -print | sort | tail -n 1)"
[[ -n "$BIN_PATH" ]] || fail "built binary not found under $BUILD_DIR"
file "$BIN_PATH"
echo "[yocto-app-build] PASS binary=$BIN_PATH"
