#!/usr/bin/env bash
set -euo pipefail

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
export QT_QPA_EGLFS_INTEGRATION="${QT_QPA_EGLFS_INTEGRATION:-eglfs_kms}"
export QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-basic}"
# MapLibre Native is the production map path and expects the basic render loop.
# The appliance defaults to the embedded UI, but explicit systemd/default-file
# overrides must win. The BeagleY development display workflow relies on
# /etc/default/beagley-cluster.local being able to select the V3 shell.
export BEAGLEY_UI_VARIANT="${BEAGLEY_UI_VARIANT:-embedded}"
export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-maplibre-native}"
export BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL="${BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL:-https://tiles.openfreemap.org/styles/positron}"
export BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES="${BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES:-$BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL}"
export BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES="${BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES:-0}"
export BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY="${BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY:-0}"
export BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM="${BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM:-14.0}"
export BEAGLEY_MAP_BOOT_MODE="${BEAGLEY_MAP_BOOT_MODE:-staged}"
export BEAGLEY_MAP_STYLE_MODE="${BEAGLEY_MAP_STYLE_MODE:-embedded}"
export BEAGLEY_REQUIRE_GPU_GATE="${BEAGLEY_REQUIRE_GPU_GATE:-1}"
export BEAGLEY_GPU_GATE_FILE="${BEAGLEY_GPU_GATE_FILE:-/run/beagley_gpu_gate.ok}"
export BEAGLEY_REQUIRE_TOUCH_GATE="${BEAGLEY_REQUIRE_TOUCH_GATE:-0}"
export BEAGLEY_TOUCH_GATE_FILE="${BEAGLEY_TOUCH_GATE_FILE:-/run/beagley_touch_gate.ok}"
export BEAGLEY_TOUCH_GATE_TIMEOUT="${BEAGLEY_TOUCH_GATE_TIMEOUT:-60}"

gpu_gate_enabled() {
  local value="${BEAGLEY_REQUIRE_GPU_GATE,,}"
  [[ "$value" != "0" && "$value" != "false" && "$value" != "off" && "$value" != "no" ]]
}

touch_gate_enabled() {
  local value="${BEAGLEY_REQUIRE_TOUCH_GATE,,}"
  [[ "$value" != "0" && "$value" != "false" && "$value" != "off" && "$value" != "no" ]]
}

wait_for_vehicle_hub() {
  local url="${VEHICLE_HUB_WS_URL:-}"
  local wait_secs="${BEAGLEY_VEHICLE_HUB_WAIT_SECS:-20}"
  local hostport host port i

  [[ -n "$url" ]] || return 0
  hostport="${url#*://}"
  hostport="${hostport%%/*}"
  host="${hostport%%:*}"
  port="${hostport##*:}"
  if [[ -z "$host" || -z "$port" || "$host" == "$hostport" ]]; then
    echo "[BOOT] vehicle hub wait skipped: could not parse VEHICLE_HUB_WS_URL=${url}" >&2
    return 0
  fi

  i=0
  while [ "$i" -lt "$wait_secs" ]; do
    if timeout 1 sh -c "nc '$host' '$port' </dev/null >/dev/null 2>&1"; then
      echo "[BOOT] vehicle hub reachable ${host}:${port}"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done

  echo "[BOOT] vehicle hub not reachable after ${wait_secs}s: ${host}:${port}" >&2
  return 0
}

if gpu_gate_enabled; then
  /usr/bin/beagley-gpu-gate --strict --mode appliance --write-ok "${BEAGLEY_GPU_GATE_FILE}"
fi

if touch_gate_enabled; then
  /usr/libexec/beagley-cluster/beagley-touch-gate.sh \
    --write-ok "${BEAGLEY_TOUCH_GATE_FILE}" \
    --timeout "${BEAGLEY_TOUCH_GATE_TIMEOUT}"
fi

wait_for_vehicle_hub

exec /usr/bin/beagley_cluster
