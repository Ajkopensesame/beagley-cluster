#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-}"
MIN_FPS=58
MAX_P95=17
MAX_P99=25

fail() {
  echo "[perf-check] FAIL: $*" >&2
  exit 1
}

[[ -n "$LOG_FILE" ]] || fail "usage: $0 <log-file> [--min-fps N] [--max-p95 N] [--max-p99 N]"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-fps)
      MIN_FPS="${2:-}"
      shift 2
      ;;
    --max-p95)
      MAX_P95="${2:-}"
      shift 2
      ;;
    --max-p99)
      MAX_P99="${2:-}"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -f "$LOG_FILE" ]] || fail "log file not found: $LOG_FILE"

SUMMARY="$(
  awk '
    /\[Perf\]/ {
      fps = p95 = p99 = ""
      for (i = 1; i <= NF; ++i) {
        if ($i ~ /^fps=/) {
          split($i, a, "="); fps = a[2]
        } else if ($i ~ /^frame_p95_ms=/) {
          split($i, a, "="); p95 = a[2]
        } else if ($i ~ /^frame_p99_ms=/) {
          split($i, a, "="); p99 = a[2]
        }
      }
      if (fps != "") {
        if (minFps == "" || fps + 0 < minFps + 0) minFps = fps
      }
      if (p95 != "") {
        if (maxP95 == "" || p95 + 0 > maxP95 + 0) maxP95 = p95
      }
      if (p99 != "") {
        if (maxP99 == "" || p99 + 0 > maxP99 + 0) maxP99 = p99
      }
      count++
    }
    END {
      if (count == 0) {
        exit 2
      }
      printf "%s %s %s %s\n", count, minFps, maxP95, maxP99
    }
  ' "$LOG_FILE"
)" || fail "no [Perf] lines found in $LOG_FILE"

set -- $SUMMARY
COUNT="$1"
OBS_MIN_FPS="$2"
OBS_MAX_P95="$3"
OBS_MAX_P99="$4"

echo "[perf-check] samples=$COUNT min_fps=$OBS_MIN_FPS max_p95_ms=$OBS_MAX_P95 max_p99_ms=$OBS_MAX_P99"

awk -v observed="$OBS_MIN_FPS" -v required="$MIN_FPS" 'BEGIN { exit !(observed + 0 < required + 0) }' \
  && fail "minimum fps below target: $OBS_MIN_FPS < $MIN_FPS" || true
awk -v observed="$OBS_MAX_P95" -v required="$MAX_P95" 'BEGIN { exit !(observed + 0 > required + 0) }' \
  && fail "p95 frame time above target: $OBS_MAX_P95 > $MAX_P95" || true
awk -v observed="$OBS_MAX_P99" -v required="$MAX_P99" 'BEGIN { exit !(observed + 0 > required + 0) }' \
  && fail "p99 frame time above target: $OBS_MAX_P99 > $MAX_P99" || true

echo "[perf-check] PASS"
