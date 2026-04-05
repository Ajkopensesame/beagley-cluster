#!/usr/bin/env bash
set -euo pipefail

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
export QT_QPA_EGLFS_INTEGRATION="${QT_QPA_EGLFS_INTEGRATION:-eglfs_kms}"
export QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-threaded}"
# The appliance launcher should always land on the embedded UI. Local override
# files are still useful for bench toggles like font paths, but letting them
# switch the entrypoint back to the desktop V3 shell strands the map on the
# snapshot path instead of the production native renderer.
export BEAGLEY_UI_VARIANT="embedded"
export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native-online}"
export BEAGLEY_MAP_BOOT_MODE="${BEAGLEY_MAP_BOOT_MODE:-staged}"
export BEAGLEY_MAP_STYLE_MODE="${BEAGLEY_MAP_STYLE_MODE:-embedded}"
export BEAGLEY_REQUIRE_GPU_GATE="${BEAGLEY_REQUIRE_GPU_GATE:-1}"
export BEAGLEY_GPU_GATE_FILE="${BEAGLEY_GPU_GATE_FILE:-/run/beagley_gpu_gate.ok}"

gpu_gate_enabled() {
  local value="${BEAGLEY_REQUIRE_GPU_GATE,,}"
  [[ "$value" != "0" && "$value" != "false" && "$value" != "off" && "$value" != "no" ]]
}

if gpu_gate_enabled; then
  /usr/bin/beagley-gpu-gate --strict --mode appliance --write-ok "${BEAGLEY_GPU_GATE_FILE}"
fi

exec /usr/bin/beagley_cluster
