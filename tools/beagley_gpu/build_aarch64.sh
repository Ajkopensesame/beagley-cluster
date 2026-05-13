#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BEAGLEY_AARCH64_BUILD_DIR:-$ROOT/build-beagley-aarch64}"
BUILD_TYPE="${BEAGLEY_AARCH64_BUILD_TYPE:-RelWithDebInfo}"
JOBS="${BEAGLEY_AARCH64_BUILD_JOBS:-}"
MAPLIBRE_NATIVE="${BEAGLEY_WITH_MAPLIBRE_NATIVE:-ON}"

fail() {
  echo "[build-aarch64] FAIL: $*" >&2
  exit 1
}

cmake_args=(
  -S "$ROOT"
  -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
  -DBEAGLEY_APPLIANCE_PRODUCTION=ON
  -DWITH_WEBENGINE=OFF
  -DWITH_MAPLIBRE_NATIVE="$MAPLIBRE_NATIVE"
)

if [[ "$(uname -s)" == "Linux" && "$(uname -m)" == "aarch64" ]]; then
  echo "[build-aarch64] native Linux aarch64 build"
elif [[ -n "${BEAGLEY_AARCH64_TOOLCHAIN_FILE:-}" ]]; then
  [[ -f "$BEAGLEY_AARCH64_TOOLCHAIN_FILE" ]] || fail "toolchain file not found: $BEAGLEY_AARCH64_TOOLCHAIN_FILE"
  cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$BEAGLEY_AARCH64_TOOLCHAIN_FILE")
  echo "[build-aarch64] cross build using $BEAGLEY_AARCH64_TOOLCHAIN_FILE"
elif [[ -n "${OECORE_TARGET_SYSROOT:-}" ]]; then
  [[ -d "$OECORE_TARGET_SYSROOT" ]] || fail "OECORE_TARGET_SYSROOT does not exist: $OECORE_TARGET_SYSROOT"
  cmake_args+=(-DCMAKE_SYSROOT="$OECORE_TARGET_SYSROOT")
  echo "[build-aarch64] Yocto SDK environment detected"
else
  fail "no Linux aarch64 build context found. Source the Yocto SDK environment or set BEAGLEY_AARCH64_TOOLCHAIN_FILE."
fi

cmake "${cmake_args[@]}"
if [[ -n "$JOBS" ]]; then
  cmake --build "$BUILD_DIR" -j "$JOBS"
else
  cmake --build "$BUILD_DIR" -j
fi

BIN="$(find "$BUILD_DIR" -type f -name beagley_cluster | head -n 1)"
[[ -n "$BIN" ]] || fail "built binary not found under $BUILD_DIR"

BIN_DESC="$(file "$BIN")"
echo "[build-aarch64] Built binary: $BIN_DESC"

if [[ "$BIN_DESC" != *"ELF 64-bit"* || "$BIN_DESC" != *"aarch64"* ]]; then
  fail "built binary is not Linux aarch64 ELF: $BIN_DESC"
fi

echo "[build-aarch64] PASS binary=$BIN"
