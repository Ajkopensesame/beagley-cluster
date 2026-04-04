#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GPU_GATE_FILE="${BEAGLEY_GPU_GATE_FILE:-/tmp/beagley_gpu_gate.ok}"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
export QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-basic}"
export BEAGLEY_UI_VARIANT="${BEAGLEY_UI_VARIANT:-v3}"
export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native}"
export BEAGLEY_MAP_BOOT_MODE="${BEAGLEY_MAP_BOOT_MODE:-staged}"
export BEAGLEY_MAP_STYLE_MODE="${BEAGLEY_MAP_STYLE_MODE:-embedded}"

if "$ROOT/tools/beagley_gpu/gpu_gate.sh" --strict --write-ok "$GPU_GATE_FILE"; then
  export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
  export BEAGLEY_REQUIRE_GPU_GATE=1
  export BEAGLEY_GPU_GATE_FILE="$GPU_GATE_FILE"
  echo "[run-embedded-auto] hardware EGL path ready"
else
  echo "[run-embedded-auto] hardware EGL unavailable, switching to safe embedded profile" >&2
  export BEAGLEY_REQUIRE_GPU_GATE=0
  export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-off}"
  export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native}"
  export BEAGLEY_WEBENGINE_MODE="${BEAGLEY_WEBENGINE_MODE:-software}"
fi

exec "$ROOT/build/beagley_cluster"
