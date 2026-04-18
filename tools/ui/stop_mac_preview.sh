#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PID_FILE="${PID_FILE:-/tmp/beagley-mac-preview-watch.pid}"

if [[ -f "$PID_FILE" ]]; then
  WATCH_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$WATCH_PID" ]] && kill -0 "$WATCH_PID" 2>/dev/null; then
    echo "[mac-preview] stopping watcher pid=$WATCH_PID"
    kill "$WATCH_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

pkill -f "$ROOT/run_1920x720.sh" 2>/dev/null || true
pkill -f "$ROOT/build/beagley_cluster" 2>/dev/null || true

echo "[mac-preview] stopped"
