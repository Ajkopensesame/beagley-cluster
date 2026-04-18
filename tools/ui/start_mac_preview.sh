#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PID_FILE="${PID_FILE:-/tmp/beagley-mac-preview-watch.pid}"
LOG_FILE="${LOG_FILE:-/tmp/beagley-mac-preview.log}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[mac-preview] this starter is intended for macOS." >&2
  exit 2
fi

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[mac-preview] stopping existing watcher pid=$OLD_PID"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi
fi

pkill -f "$ROOT/run_1920x720.sh" 2>/dev/null || true
pkill -f "$ROOT/build/beagley_cluster" 2>/dev/null || true

rm -f "$LOG_FILE"
nohup "$ROOT/tools/ui/mac_preview.sh" --watch "$@" > "$LOG_FILE" 2>&1 &
WATCH_PID=$!
echo "$WATCH_PID" > "$PID_FILE"

echo "[mac-preview] watcher started pid=$WATCH_PID"
echo "[mac-preview] log: $LOG_FILE"
echo "[mac-preview] stop with: $ROOT/tools/ui/stop_mac_preview.sh"
