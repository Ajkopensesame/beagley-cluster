#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPLAY_FILE="${1:-}"
LOG_FILE="${2:-/tmp/beagley_embedded_replay.log}"

fail() {
  echo "[perf-replay] FAIL: $*" >&2
  exit 1
}

[[ -n "$REPLAY_FILE" ]] || fail "usage: $0 <replay.jsonl> [log-file]"
[[ -f "$REPLAY_FILE" ]] || fail "replay file not found: $REPLAY_FILE"
[[ -x "$ROOT/build/beagley_cluster" ]] || fail "missing build/beagley_cluster"

export BEAGLEY_UI_VARIANT="${BEAGLEY_UI_VARIANT:-embedded}"
export BEAGLEY_RENDER_PROFILE="${BEAGLEY_RENDER_PROFILE:-embedded}"
export BEAGLEY_EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
export BEAGLEY_MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-native-online}"
export BEAGLEY_PROFILE_METRICS="${BEAGLEY_PROFILE_METRICS:-1}"
export BEAGLEY_REPLAY_FILE="$REPLAY_FILE"
export BEAGLEY_REPLAY_LOOP="${BEAGLEY_REPLAY_LOOP:-0}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-cocoa}"
else
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
fi

"$ROOT/build/beagley_cluster" >"$LOG_FILE" 2>&1
