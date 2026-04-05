#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${1:-$ROOT/build}"
OUT_DIR="${2:-$ROOT/dist}"

fail() {
  echo "[release-bundle] FAIL: $*" >&2
  exit 1
}

BIN_PATH="$BUILD_DIR/beagley_cluster"
CACHE_PATH="$BUILD_DIR/CMakeCache.txt"
[[ -x "$BIN_PATH" ]] || fail "missing binary: $BIN_PATH"
[[ -f "$CACHE_PATH" ]] || fail "missing cache: $CACHE_PATH"

BUILD_TYPE="$(awk -F= '/^CMAKE_BUILD_TYPE:/{print $2}' "$CACHE_PATH" | tail -n 1)"
if [[ "$BUILD_TYPE" != "RelWithDebInfo" && "$BUILD_TYPE" != "Release" ]]; then
  fail "build type must be RelWithDebInfo or Release (got: $BUILD_TYPE)"
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
STAGE_DIR="$OUT_DIR/beagley-release-$STAMP"
mkdir -p "$STAGE_DIR"

cp "$BIN_PATH" "$STAGE_DIR/"
cp "$ROOT/run_1920x720.sh" "$STAGE_DIR/"
mkdir -p "$STAGE_DIR/tools/beagley_gpu" "$STAGE_DIR/docs"
cp "$ROOT"/tools/beagley_gpu/*.sh "$STAGE_DIR/tools/beagley_gpu/"
cp "$ROOT"/tools/beagley_gpu/*.service.in "$STAGE_DIR/tools/beagley_gpu/" 2>/dev/null || true
cp "$ROOT"/tools/beagley_gpu/*.example "$STAGE_DIR/tools/beagley_gpu/" 2>/dev/null || true
cp "$ROOT/docs/beagley_gpu_contract.md" "$STAGE_DIR/docs/"
cp "$ROOT/src/ui/web/map/styles/embedded-liberty.json" "$STAGE_DIR/"
cp "$ROOT/src/ui/web/map/styles/embedded-liberty.js" "$STAGE_DIR/"

cat >"$STAGE_DIR/manifest.txt" <<EOF
generated_at_utc=$STAMP
build_type=$BUILD_TYPE
binary=beagley_cluster
default_render_profile=embedded
default_map_renderer=native
default_effect_level=low
gpu_gate_required_with_embedded_platform=1
EOF

ARCHIVE="$OUT_DIR/beagley-release-$STAMP.tar.gz"
tar -C "$OUT_DIR" -czf "$ARCHIVE" "beagley-release-$STAMP"
sha256sum "$ARCHIVE" >"$ARCHIVE.sha256"

echo "[release-bundle] created $ARCHIVE"
echo "[release-bundle] checksum $ARCHIVE.sha256"
