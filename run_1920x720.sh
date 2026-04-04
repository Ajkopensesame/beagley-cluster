#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Scaling: keep 1:1 for predictable layout while developing
export QT_SCALE_FACTOR=1
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCREEN_SCALE_FACTORS=1
export BEAGLEY_UI_VARIANT="${BEAGLEY_UI_VARIANT:-v3}"
export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native}"
export BEAGLEY_MAP_BOOT_MODE="${BEAGLEY_MAP_BOOT_MODE:-staged}"
export BEAGLEY_MAP_STYLE_MODE="${BEAGLEY_MAP_STYLE_MODE:-embedded}"
export BEAGLEY_WEBENGINE_MODE="${BEAGLEY_WEBENGINE_MODE:-swiftshader_driver}"
export BEAGLEY_GPU_GATE_FILE="${BEAGLEY_GPU_GATE_FILE:-/tmp/beagley_gpu_gate.ok}"
export BEAGLEY_REQUIRE_GPU_GATE="${BEAGLEY_REQUIRE_GPU_GATE:-0}"
# Default BBB vehicle-state endpoint (override as needed per network)
export VEHICLE_HUB_WS_URL="${VEHICLE_HUB_WS_URL:-ws://192.168.0.7:8765}"

# Platform selection:
# - macOS: cocoa (does NOT support geometry option)
# - Linux desktop: xcb (geometry supported)
UNAME="$(uname -s)"

if [[ "$UNAME" == "Darwin" ]]; then
  export QT_QPA_PLATFORM=cocoa
  exec "$ROOT/build/beagley_cluster" -platform cocoa
else
  export QT_QPA_PLATFORM=xcb
  export QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-basic}"
  if [[ "$BEAGLEY_REQUIRE_GPU_GATE" == "1" ]]; then
    "$ROOT/tools/beagley_gpu/gpu_gate.sh" --strict --write-ok "$BEAGLEY_GPU_GATE_FILE"
  fi
  exec "$ROOT/build/beagley_cluster" -platform "xcb:geometry=1920x720+0+0"
fi
