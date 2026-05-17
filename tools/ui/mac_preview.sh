#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
APP="$BUILD_DIR/beagley_cluster"
POLL_INTERVAL="${POLL_INTERVAL:-1}"

WATCH=0
BUILD=1
STRESS=1
HUB_URL="${VEHICLE_HUB_WS_URL:-ws://10.24.0.7:8765}"

usage() {
  cat <<'EOF'
Usage:
  ./tools/ui/mac_preview.sh [options]

Options:
  --watch             Rebuild and relaunch when UI/source files change.
  --no-build          Launch the existing build without running cmake --build.
  --live              Use the vehicle hub feed instead of simulated visual motion.
  --stress            Use simulated visual motion for local UI design. Default.
  --hub URL           Vehicle hub WebSocket URL for --live mode.
  -h, --help          Show this help.

Examples:
  ./tools/ui/mac_preview.sh
  ./tools/ui/mac_preview.sh --watch
  ./tools/ui/mac_preview.sh --live --hub ws://10.24.0.7:8765
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      WATCH=1
      shift
      ;;
    --no-build)
      BUILD=0
      shift
      ;;
    --live)
      STRESS=0
      shift
      ;;
    --stress)
      STRESS=1
      shift
      ;;
    --hub)
      if [[ $# -lt 2 ]]; then
        echo "[mac-preview] --hub requires a WebSocket URL" >&2
        exit 2
      fi
      HUB_URL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[mac-preview] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[mac-preview] this script is intended for macOS. Use ./run_1920x720.sh directly on Linux." >&2
  exit 2
fi

configure_if_needed() {
  if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "[mac-preview] configuring build directory: $BUILD_DIR"
    cmake -S "$ROOT" -B "$BUILD_DIR"
  fi
}

build_app() {
  if [[ "$BUILD" == "0" ]]; then
    return
  fi
  configure_if_needed
  echo "[mac-preview] building local preview"
  cmake --build "$BUILD_DIR" -j
}

launch_app() {
  if [[ ! -x "$APP" ]]; then
    echo "[mac-preview] missing app binary: $APP" >&2
    echo "[mac-preview] run without --no-build first, or check the CMake build output." >&2
    exit 1
  fi

  export BEAGLEY_UI_VARIANT="${BEAGLEY_UI_VARIANT:-v3}"
  export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
  export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
  export BEAGLEY_GAUGE_DETAIL="${BEAGLEY_GAUGE_DETAIL:-rich}"
  export BEAGLEY_GAUGE_DEMO="${BEAGLEY_GAUGE_DEMO:-0}"
  export BEAGLEY_CLUSTER_SIMULATION="${BEAGLEY_CLUSTER_SIMULATION:-0}"
  export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native}"
  export BEAGLEY_MAP_BOOT_MODE="${BEAGLEY_MAP_BOOT_MODE:-staged}"
  export BEAGLEY_MAP_STYLE_MODE="${BEAGLEY_MAP_STYLE_MODE:-embedded}"
  export BEAGLEY_WEBENGINE_MODE="${BEAGLEY_WEBENGINE_MODE:-swiftshader_driver}"
  export BEAGLEY_REQUIRE_GPU_GATE=0
  export VEHICLE_HUB_WS_URL="$HUB_URL"

  if [[ "$STRESS" == "1" ]]; then
    export BEAGLEY_STRESS_SCENE=1
  else
    unset BEAGLEY_STRESS_SCENE
  fi

  echo "[mac-preview] launching UI=$BEAGLEY_UI_VARIANT map=$BEAGLEY_MAP_RENDERER stress=$STRESS hub=$VEHICLE_HUB_WS_URL"
  "$ROOT/run_1920x720.sh" &
  APP_PID=$!
}

stop_app() {
  if [[ "${APP_PID:-}" != "" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    echo "[mac-preview] stopping preview pid=$APP_PID"
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
}

on_error() {
  local line_no="$1"
  echo "[mac-preview] failed at line $line_no" >&2
  stop_app
}

source_fingerprint() {
  (
    cd "$ROOT"
    {
      printf '%s\n' CMakeLists.txt run_1920x720.sh
      find src -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.qml' -o -name '*.qrc' \)
    } | sort | while IFS= read -r path; do
      [[ -f "$path" ]] && shasum "$path"
    done
  ) | shasum | awk '{print $1}'
}

run_once() {
  build_app
  launch_app
  wait "$APP_PID"
}

run_watch() {
  trap stop_app EXIT
  trap 'stop_app; exit 0' INT TERM
  trap 'on_error "$LINENO"' ERR

  build_app
  launch_app
  local last_fp
  last_fp="$(source_fingerprint)"

  echo "[mac-preview] watching src/*.qml, src/*.cpp, src/*.h, CMakeLists.txt"
  echo "[mac-preview] press Ctrl-C to stop"

  while true; do
    sleep "$POLL_INTERVAL"
    if [[ "${APP_PID:-}" != "" ]] && ! kill -0 "$APP_PID" 2>/dev/null; then
      wait "$APP_PID" 2>/dev/null || true
      APP_PID=""
      echo "[mac-preview] preview exited; relaunching while watch mode is active"
      if build_app; then
        launch_app
      else
        echo "[mac-preview] build failed; fix the error and save again"
      fi
    fi

    local next_fp
    next_fp="$(source_fingerprint)"
    if [[ "$next_fp" != "$last_fp" ]]; then
      last_fp="$next_fp"
      stop_app
      if build_app; then
        launch_app
      else
        echo "[mac-preview] build failed; fix the error and save again"
      fi
    fi
  done
}

if [[ "$WATCH" == "1" ]]; then
  run_watch
else
  run_once
fi
