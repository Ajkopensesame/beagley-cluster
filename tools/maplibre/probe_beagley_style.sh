#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="root@beagley-ai.local"
STYLE_URL=""
LABEL=""
PROMOTE=0
KEEP_RUNNING=0
DELAY_MS=14000
MAX_ZOOM=""
RENDER_LOOP=""
REMOTE_ENV="/etc/default/beagley-cluster.local"
OUT_DIR="$BASE/build/maplibre-probes"
USER_AGENT="BeagleyCluster/1.0 (MapLibre probe)"

usage() {
  cat <<EOF
Usage: $0 --style-url URL [--label NAME] [--host HOST] [--promote] [--keep-running]

Probes a MapLibre Native style on the real BeagleY display. The previous
BeagleY environment is restored unless --promote or --keep-running is used.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --style-url)
      STYLE_URL="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --delay-ms)
      DELAY_MS="${2:-}"
      shift 2
      ;;
    --max-zoom)
      MAX_ZOOM="${2:-}"
      shift 2
      ;;
    --render-loop)
      RENDER_LOOP="${2:-}"
      shift 2
      ;;
    --promote)
      PROMOTE=1
      shift
      ;;
    --keep-running)
      KEEP_RUNNING=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[PROBE] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$STYLE_URL" ]]; then
  echo "[PROBE] --style-url is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$LABEL" ]]; then
  LABEL="$(printf '%s' "$STYLE_URL" | sed -E 's#^https?://##; s#[^A-Za-z0-9_.-]+#-#g; s#^-+|-+$##g')"
fi
LABEL="$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9_.-' '-')"
TS="$(date +%Y%m%d-%H%M%S)"
RUN_LABEL="$TS-$LABEL"
RUN_DIR="$OUT_DIR/$RUN_LABEL"
REMOTE_SCREENSHOT="/tmp/beagley-maplibre-$RUN_LABEL.png"
REMOTE_PROMOTE_SCREENSHOT="/tmp/beagley-maplibre-$RUN_LABEL-promoted.png"
REMOTE_BACKUP="/var/volatile/beagley-cluster.local.maplibre.$RUN_LABEL.bak"
RESTORE_ON_EXIT=1

mkdir -p "$RUN_DIR"

remote_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

run_health_or_debug() {
  if "$BASE/skills/beagley-health-check/scripts/check.sh"; then
    return 0
  fi
  echo "[PROBE] Health check failed; collecting diagnostics" >&2
  "$BASE/skills/beagley-debug-service/scripts/debug.sh" || true
  return 1
}

restore_remote_env() {
  set +e
  if [[ "$RESTORE_ON_EXIT" -eq 1 ]]; then
    echo "[PROBE] Restoring previous BeagleY environment"
    ssh "$HOST" "if [ -s $(remote_quote "$REMOTE_BACKUP") ]; then cp $(remote_quote "$REMOTE_BACKUP") $(remote_quote "$REMOTE_ENV"); systemctl reset-failed beagley_cluster; systemctl restart beagley_cluster; fi" >/dev/null 2>&1
  fi
}

trap restore_remote_env EXIT

write_remote_env() {
  local allow_untested="$1"
  local trusted_styles="$2"
  local screenshot_path="$3"
  local screenshot_exit="$4"

  ssh "$HOST" \
    "STYLE_URL=$(remote_quote "$STYLE_URL") TRUSTED_STYLES=$(remote_quote "$trusted_styles") ALLOW_UNTESTED=$(remote_quote "$allow_untested") MAX_ZOOM=$(remote_quote "$MAX_ZOOM") RENDER_LOOP=$(remote_quote "$RENDER_LOOP") SCREENSHOT_PATH=$(remote_quote "$screenshot_path") SCREENSHOT_DELAY_MS=$(remote_quote "$DELAY_MS") SCREENSHOT_EXIT=$(remote_quote "$screenshot_exit") REMOTE_ENV=$(remote_quote "$REMOTE_ENV") bash -s" <<'REMOTE'
set -euo pipefail
touch "$REMOTE_ENV"
tmp="$(mktemp)"
awk -F= '
BEGIN {
  split("BEAGLEY_MAP_RENDERER BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM BEAGLEY_SCREENSHOT_PATH BEAGLEY_SCREENSHOT_DELAY_MS BEAGLEY_SCREENSHOT_EXIT QSG_RENDER_LOOP", keys, " ")
  for (i in keys) drop[keys[i]] = 1
}
($1 in drop) { next }
{ print }
' "$REMOTE_ENV" > "$tmp"
{
  printf 'BEAGLEY_MAP_RENDERER=maplibre-native\n'
  printf 'BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL=%s\n' "$STYLE_URL"
  printf 'BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES=%s\n' "$TRUSTED_STYLES"
  printf 'BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=%s\n' "$ALLOW_UNTESTED"
  printf 'BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=0\n'
  printf 'BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM=%s\n' "$MAX_ZOOM"
  if [ -n "$RENDER_LOOP" ]; then
    printf 'QSG_RENDER_LOOP=%s\n' "$RENDER_LOOP"
  fi
  if [ -n "$SCREENSHOT_PATH" ]; then
    printf 'BEAGLEY_SCREENSHOT_PATH=%s\n' "$SCREENSHOT_PATH"
    printf 'BEAGLEY_SCREENSHOT_DELAY_MS=%s\n' "$SCREENSHOT_DELAY_MS"
    printf 'BEAGLEY_SCREENSHOT_EXIT=%s\n' "$SCREENSHOT_EXIT"
  fi
} >> "$tmp"
cp "$tmp" "$REMOTE_ENV"
rm -f "$tmp"
REMOTE
}

restart_and_capture() {
  local phase="$1"
  local remote_screenshot="$2"
  local since
  local timeout_seconds
  local local_screenshot="$RUN_DIR/$phase.png"
  local local_log="$RUN_DIR/$phase.journal.log"
  local local_analysis="$RUN_DIR/$phase.analysis.json"

  since="$(ssh "$HOST" "date '+%Y-%m-%d %H:%M:%S'")"
  ssh "$HOST" "rm -f $(remote_quote "$remote_screenshot"); systemctl reset-failed beagley_cluster; systemctl restart beagley_cluster"
  timeout_seconds=$((DELAY_MS / 1000 + 24))
  echo "[PROBE] Waiting for $phase screenshot: $remote_screenshot"
  for _ in $(seq 1 "$timeout_seconds"); do
    if ssh "$HOST" "[ -s $(remote_quote "$remote_screenshot") ]"; then
      break
    fi
    sleep 1
  done
  if ! ssh "$HOST" "[ -s $(remote_quote "$remote_screenshot") ]"; then
    echo "[PROBE] Screenshot was not created for $phase" >&2
    return 1
  fi

  scp "$HOST:$remote_screenshot" "$local_screenshot" >/dev/null
  ssh "$HOST" "journalctl -u beagley_cluster --since $(remote_quote "$since") --no-pager" > "$local_log" || true
  if ! python3 "$BASE/tools/maplibre/analyze_screenshot.py" "$local_screenshot" --json > "$local_analysis"; then
    echo "[PROBE] Screenshot analysis failed for $phase:" >&2
    cat "$local_analysis" >&2 || true
    return 1
  fi

  if grep -Eiq 'MapChangeDidFailLoadingMap|ParseStyle|Failed to load|HTTP status code [45]|Error transferring|SSL|style is not allowlisted|native implementation failed' "$local_log"; then
    echo "[PROBE] MapLibre-related errors were found in $local_log" >&2
    grep -Ein 'MapChangeDidFailLoadingMap|ParseStyle|Failed to load|HTTP status code [45]|Error transferring|SSL|style is not allowlisted|native implementation failed' "$local_log" >&2 || true
    return 1
  fi

  echo "[PROBE] Screenshot analysis for $phase:"
  cat "$local_analysis"
}

echo "[PROBE] Baseline health check"
run_health_or_debug

echo "[PROBE] Inspecting style dependencies"
python3 "$BASE/tools/maplibre/inspect_style.py" "$STYLE_URL" --user-agent "$USER_AGENT" --json > "$RUN_DIR/style-inspection.json"
cat "$RUN_DIR/style-inspection.json"
if [[ -z "$MAX_ZOOM" ]]; then
  MAX_ZOOM="$(python3 - "$RUN_DIR/style-inspection.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
zooms = []
for source in data.get("checks", {}).get("sources", []):
    tilejson = source.get("tilejson") or {}
    value = tilejson.get("maxzoom")
    if isinstance(value, (int, float)):
        zooms.append(float(value))
if zooms:
    print(max(zooms))
else:
    print("14")
PY
)"
fi
echo "[PROBE] Using MapLibre max zoom: $MAX_ZOOM"

echo "[PROBE] Verifying BeagleY can fetch the style URL"
ssh "$HOST" "curl -fsSL --max-time 20 -A $(remote_quote "$USER_AGENT") $(remote_quote "$STYLE_URL") >/tmp/beagley-maplibre-style-probe.json"

echo "[PROBE] Backing up $REMOTE_ENV to $REMOTE_BACKUP"
ssh "$HOST" "touch $(remote_quote "$REMOTE_ENV"); cp $(remote_quote "$REMOTE_ENV") $(remote_quote "$REMOTE_BACKUP")"

echo "[PROBE] Running untrusted-style probe with temporary guard bypass"
write_remote_env 1 "$STYLE_URL" "$REMOTE_SCREENSHOT" 0
restart_and_capture "probe" "$REMOTE_SCREENSHOT"

if [[ "$PROMOTE" -eq 1 ]]; then
  echo "[PROBE] Verifying promoted allowlist path"
  write_remote_env 0 "$STYLE_URL" "$REMOTE_PROMOTE_SCREENSHOT" 0
  restart_and_capture "promoted" "$REMOTE_PROMOTE_SCREENSHOT"

  echo "[PROBE] Promoting MapLibre Native style"
  write_remote_env 0 "$STYLE_URL" "" 0
  RESTORE_ON_EXIT=0
  ssh "$HOST" "systemctl reset-failed beagley_cluster; systemctl restart beagley_cluster"
  run_health_or_debug
  echo "[PROBE] Promoted style: $STYLE_URL"
elif [[ "$KEEP_RUNNING" -eq 1 ]]; then
  echo "[PROBE] Leaving BeagleY in temporary MapLibre test mode"
  write_remote_env 1 "$STYLE_URL" "" 0
  RESTORE_ON_EXIT=0
  ssh "$HOST" "systemctl reset-failed beagley_cluster; systemctl restart beagley_cluster"
else
  echo "[PROBE] Probe complete. Restoring previous environment."
fi

echo "[PROBE] Artifacts: $RUN_DIR"
