#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
export QT_QPA_EGLFS_INTEGRATION="${QT_QPA_EGLFS_INTEGRATION:-eglfs_kms}"
export BEAGLEY_UI_VARIANT="${BEAGLEY_UI_VARIANT:-embedded}"
export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native-online}"
export BEAGLEY_MAP_BOOT_MODE="${BEAGLEY_MAP_BOOT_MODE:-staged}"
export BEAGLEY_MAP_STYLE_MODE="${BEAGLEY_MAP_STYLE_MODE:-embedded}"
export BEAGLEY_REQUIRE_GPU_GATE="${BEAGLEY_REQUIRE_GPU_GATE:-1}"
export BEAGLEY_GPU_GATE_FILE="${BEAGLEY_GPU_GATE_FILE:-/tmp/beagley_gpu_gate.ok}"

"$ROOT/tools/beagley_gpu/gpu_gate.sh" --strict --write-ok "$BEAGLEY_GPU_GATE_FILE"

exec "$ROOT/build/beagley_cluster"
