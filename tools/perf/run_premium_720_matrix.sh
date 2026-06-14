#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"
HUB_URL="${VEHICLE_HUB_WS_URL:-ws://10.24.0.7:8765}"
RENDER_LOOPS="${PREMIUM_720_RENDER_LOOPS:-basic threaded}"
EFFECT_LEVELS="${PREMIUM_720_EFFECT_LEVELS:-off low}"
DURATION_SECONDS=45
WARMUP_SECONDS=15
MIN_FPS=45
MAX_P95=35
MAX_P99=60
SCREENSHOT_DELAY_MS=7000
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$ROOT/build/perf/premium-720-$STAMP"
RESTORE=1
CAPTURE_SCREENSHOTS=1
STRICT_QML=0
SOURCE_TRUTH=1

usage() {
  cat <<'EOF'
Usage:
  tools/perf/run_premium_720_matrix.sh [options]

Runs the premium-720 hardware acceptance matrix on the real BeagleY. Each case
installs the premium-720 profile, measures `[Perf]` output, captures journal
evidence, and optionally captures a real display screenshot.

Default matrix:
  render loops: basic threaded
  effect levels: off low

Options:
  --host HOST             SSH target. Default: root@beagley-ai.local
  --hub-url URL           Vehicle hub URL. Default: ws://10.24.0.7:8765
  --render-loops LIST     Space-separated list. Default: "basic threaded"
  --effect-levels LIST    Space-separated list. Default: "off low"
  --duration SECONDS      Measured sample duration. Default: 45
  --warmup SECONDS        Warmup before measurement. Default: 15
  --min-fps N             Perf check minimum FPS. Default: 45
  --max-p95 MS            Perf check maximum p95. Default: 35
  --max-p99 MS            Perf check maximum p99. Default: 60
  --out-dir DIR           Artifact directory. Default: build/perf/premium-720-<stamp>
  --screenshot-delay-ms N Screenshot capture delay. Default: 7000
  --no-screenshots        Skip screenshot capture.
  --no-restore            Leave the last matrix profile installed.
  --strict-qml            Fail if the static QML risk scan finds hard risks.
  --skip-source-truth     Do not run strict source-truth before the matrix.
  -h, --help              Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --hub-url)
      HUB_URL="${2:-}"
      shift 2
      ;;
    --render-loops)
      RENDER_LOOPS="${2:-}"
      shift 2
      ;;
    --effect-levels)
      EFFECT_LEVELS="${2:-}"
      shift 2
      ;;
    --duration)
      DURATION_SECONDS="${2:-}"
      shift 2
      ;;
    --warmup)
      WARMUP_SECONDS="${2:-}"
      shift 2
      ;;
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
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --screenshot-delay-ms)
      SCREENSHOT_DELAY_MS="${2:-}"
      shift 2
      ;;
    --no-screenshots)
      CAPTURE_SCREENSHOTS=0
      shift
      ;;
    --no-restore)
      RESTORE=0
      shift
      ;;
    --strict-qml)
      STRICT_QML=1
      shift
      ;;
    --skip-source-truth)
      SOURCE_TRUTH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[premium-720-matrix] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_uint() {
  local label="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "[premium-720-matrix] $label must be an integer: $value" >&2
    exit 2
  fi
}

require_uint "--duration" "$DURATION_SECONDS"
require_uint "--warmup" "$WARMUP_SECONDS"
require_uint "--screenshot-delay-ms" "$SCREENSHOT_DELAY_MS"

for value in "$HOST" "$HUB_URL" "$RENDER_LOOPS" "$EFFECT_LEVELS" "$OUT_DIR"; do
  if [[ "$value" == *"'"* ]]; then
    echo "[premium-720-matrix] values may not contain single quotes: $value" >&2
    exit 2
  fi
done

mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.md"
RESULTS_TSV="$OUT_DIR/results.tsv"
REMOTE_BACKUP=""

restore_remote_env() {
  if [[ "$RESTORE" != "1" || -z "$REMOTE_BACKUP" ]]; then
    return
  fi
  echo "[premium-720-matrix] Restoring previous BeagleY local env..."
  ssh "$HOST" "set -e
    if [ -f '$REMOTE_BACKUP' ]; then
      cp '$REMOTE_BACKUP' /etc/default/beagley-cluster.local
      chmod 0644 /etc/default/beagley-cluster.local
      systemctl daemon-reload
      systemctl reset-failed beagley_cluster
      systemctl restart beagley_cluster
    fi" || true
}
trap restore_remote_env EXIT

{
  echo "# Premium 720 Matrix"
  echo
  printf 'stamp: `%s`\n' "$STAMP"
  printf 'host: `%s`\n' "$HOST"
  printf 'commit: `%s`\n' "$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
  printf 'render_loops: `%s`\n' "$RENDER_LOOPS"
  printf 'effect_levels: `%s`\n' "$EFFECT_LEVELS"
  printf 'duration_seconds: `%s`\n' "$DURATION_SECONDS"
  printf 'warmup_seconds: `%s`\n' "$WARMUP_SECONDS"
  echo
} >"$SUMMARY"
printf 'case\trender_loop\teffect_level\tstatus\tperf_summary\tlog\tscreenshot\n' >"$RESULTS_TSV"

echo "[premium-720-matrix] Artifacts: $OUT_DIR"
echo "[premium-720-matrix] Step 1: Verify SSH and back up local env..."
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$HOST" true
REMOTE_BACKUP="$(
  ssh "$HOST" "set -e
    backup_dir=/var/lib/beagley-cluster/perf
    mkdir -p \"\$backup_dir\"
    backup=\$backup_dir/beagley-cluster.local.before-premium-720-matrix.$STAMP
    if [ -f /etc/default/beagley-cluster.local ]; then
      cp /etc/default/beagley-cluster.local \"\$backup\"
    else
      : >\"\$backup\"
    fi
    echo \"\$backup\""
)"
echo "[premium-720-matrix] Remote env backup: $REMOTE_BACKUP" | tee -a "$SUMMARY"

if [[ "$SOURCE_TRUTH" == "1" ]]; then
  echo "[premium-720-matrix] Step 2: Source-truth check..."
  BEAGLEY_HOST="$HOST" "$ROOT/skills/cluster-source-truth/scripts/check.sh" --strict >"$OUT_DIR/source-truth.txt"
fi

echo "[premium-720-matrix] Step 3: Static QML risk scan..."
if [[ "$STRICT_QML" == "1" ]]; then
  "$ROOT/tools/perf/qml_render_risk_scan.sh" --strict >"$OUT_DIR/qml-risk.txt"
else
  "$ROOT/tools/perf/qml_render_risk_scan.sh" >"$OUT_DIR/qml-risk.txt"
fi

failures=0
case_index=0
for render_loop in $RENDER_LOOPS; do
  case "$render_loop" in
    basic|threaded) ;;
    *)
      echo "[premium-720-matrix] invalid render loop in matrix: $render_loop" >&2
      failures=$((failures + 1))
      continue
      ;;
  esac
  for effect_level in $EFFECT_LEVELS; do
    case "$effect_level" in
      off|low|high) ;;
      *)
        echo "[premium-720-matrix] invalid effect level in matrix: $effect_level" >&2
        failures=$((failures + 1))
        continue
        ;;
    esac

    case_index=$((case_index + 1))
    case_name="$(printf '%02d-%s-%s' "$case_index" "$render_loop" "$effect_level")"
    case_dir="$OUT_DIR/$case_name"
    mkdir -p "$case_dir"

    echo "[premium-720-matrix] Case $case_name: install profile..."
    if ! "$ROOT/tools/ui/beagley_premium_720_profile.sh" \
      --host "$HOST" \
      --hub-url "$HUB_URL" \
      --render-loop "$render_loop" \
      --effect-level "$effect_level" \
      --gauge-detail rich \
      --metrics >"$case_dir/profile.txt" 2>&1; then
      echo "[premium-720-matrix] Case $case_name failed during profile install" >&2
      printf '%s\t%s\t%s\tprofile-failed\t%s\t%s\t%s\n' "$case_name" "$render_loop" "$effect_level" "" "$case_dir/profile.txt" "" >>"$RESULTS_TSV"
      failures=$((failures + 1))
      continue
    fi

    "$ROOT/tools/ui/beagley_display_status.sh" --host "$HOST" >"$case_dir/display-status-before.txt" 2>&1 || true

    echo "[premium-720-matrix] Case $case_name: warmup ${WARMUP_SECONDS}s..."
    restart_epoch="$(ssh "$HOST" "date +%s")"
    sleep "$WARMUP_SECONDS"
    measure_epoch="$(ssh "$HOST" "date +%s")"
    echo "[premium-720-matrix] Case $case_name: measure ${DURATION_SECONDS}s..."
    sleep "$DURATION_SECONDS"

    ssh "$HOST" "journalctl -u beagley_cluster --since '@$restart_epoch' --no-pager" >"$case_dir/runtime.log" || true
    ssh "$HOST" "journalctl -u beagley_cluster --since '@$measure_epoch' --no-pager" >"$case_dir/perf.log" || true

    set +e
    "$ROOT/tools/perf/check_perf_log.sh" "$case_dir/perf.log" \
      --min-fps "$MIN_FPS" \
      --max-p95 "$MAX_P95" \
      --max-p99 "$MAX_P99" >"$case_dir/perf-check.txt" 2>&1
    perf_status=$?
    set -e

    screenshot_path=""
    if [[ "$CAPTURE_SCREENSHOTS" == "1" ]]; then
      screenshot_path="$case_dir/screenshot.png"
      echo "[premium-720-matrix] Case $case_name: screenshot..."
      "$ROOT/skills/beagley-screenshot/scripts/capture.sh" \
        --host "$HOST" \
        --current \
        --delay-ms "$SCREENSHOT_DELAY_MS" \
        --out "$screenshot_path" >"$case_dir/screenshot-capture.txt" 2>&1 || {
          echo "[premium-720-matrix] Case $case_name screenshot failed" >&2
          failures=$((failures + 1))
        }
    fi

    "$ROOT/tools/ui/beagley_display_status.sh" --host "$HOST" >"$case_dir/display-status-after.txt" 2>&1 || true

    if [[ "$perf_status" -eq 0 ]]; then
      status="pass"
    else
      status="perf-failed"
      failures=$((failures + 1))
    fi
    perf_summary="$(tr '\n' ' ' <"$case_dir/perf-check.txt" | sed 's/[[:space:]]\+/ /g; s/[[:space:]]$//')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$case_name" "$render_loop" "$effect_level" "$status" "$perf_summary" "$case_dir/perf.log" "$screenshot_path" >>"$RESULTS_TSV"
  done
done

{
  echo
  echo "## Results"
  echo
  echo '```tsv'
  cat "$RESULTS_TSV"
  echo '```'
  echo
  echo "## Artifacts"
  echo
  printf -- '- source truth: `%s`\n' "$OUT_DIR/source-truth.txt"
  printf -- '- qml risk scan: `%s`\n' "$OUT_DIR/qml-risk.txt"
  printf -- '- result table: `%s`\n' "$RESULTS_TSV"
} >>"$SUMMARY"

if [[ "$failures" -gt 0 ]]; then
  echo "[premium-720-matrix] FAIL failures=$failures summary=$SUMMARY" >&2
  exit 1
fi

echo "[premium-720-matrix] PASS summary=$SUMMARY"
