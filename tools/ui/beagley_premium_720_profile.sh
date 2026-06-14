#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"
HUB_URL="${VEHICLE_HUB_WS_URL:-ws://10.24.0.7:8765}"
EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
GAUGE_DETAIL="${BEAGLEY_GAUGE_DETAIL:-rich}"
RENDER_LOOP="${QSG_RENDER_LOOP:-basic}"
METRICS=0
RESTART=1
HEALTH=1

usage() {
  cat <<'EOF'
Usage:
  tools/ui/beagley_premium_720_profile.sh [options]

Installs the named premium-720 live display profile on the real BeagleY:
- 1920x720-oriented V3 shell
- embedded EGLFS/OpenGL path
- MapLibre Native full underlay
- rich gauges with controlled effects
- explicit Qt scenegraph render loop

Options:
  --host HOST             SSH target. Default: root@beagley-ai.local
  --hub-url URL           Vehicle hub URL. Default: ws://10.24.0.7:8765
  --effect-level LEVEL    off, low, or high. Default: low.
  --gauge-detail MODE     safe or rich. Default: rich.
  --render-loop LOOP      basic or threaded. Default: basic.
  --metrics               Enable BeagleY perf metrics.
  --no-restart            Write env without restarting.
  --no-health             Skip post-restart health check.
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
    --effect-level)
      EFFECT_LEVEL="${2:-}"
      shift 2
      ;;
    --gauge-detail)
      GAUGE_DETAIL="${2:-}"
      shift 2
      ;;
    --render-loop)
      RENDER_LOOP="${2:-}"
      shift 2
      ;;
    --metrics)
      METRICS=1
      shift
      ;;
    --no-restart)
      RESTART=0
      shift
      ;;
    --no-health)
      HEALTH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[premium-720] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$(printf '%s' "$EFFECT_LEVEL" | tr '[:upper:]' '[:lower:]')" in
  off|low|high)
    EFFECT_LEVEL="$(printf '%s' "$EFFECT_LEVEL" | tr '[:upper:]' '[:lower:]')"
    ;;
  *)
    echo "[premium-720] --effect-level must be off, low, or high: $EFFECT_LEVEL" >&2
    exit 2
    ;;
esac

case "$(printf '%s' "$RENDER_LOOP" | tr '[:upper:]' '[:lower:]')" in
  basic|threaded)
    RENDER_LOOP="$(printf '%s' "$RENDER_LOOP" | tr '[:upper:]' '[:lower:]')"
    ;;
  *)
    echo "[premium-720] --render-loop must be basic or threaded: $RENDER_LOOP" >&2
    exit 2
    ;;
esac

for value in "$HOST" "$HUB_URL" "$EFFECT_LEVEL" "$GAUGE_DETAIL" "$RENDER_LOOP"; do
  if [[ "$value" == *"'"* ]]; then
    echo "[premium-720] values may not contain single quotes: $value" >&2
    exit 2
  fi
done

LIVE_ARGS=(
  --host "$HOST"
  --hub-url "$HUB_URL"
  --effect-level "$EFFECT_LEVEL"
  --gauge-detail "$GAUGE_DETAIL"
  --no-gauge-demo
  --no-simulation
  --map-renderer maplibre-native
  --maplibre-full-underlay
  --maplibre-max-zoom 14.0
  --render-loop "$RENDER_LOOP"
  --no-restart
  --no-health
)

if [[ "$METRICS" == "1" ]]; then
  LIVE_ARGS+=(--metrics)
fi

echo "[premium-720] Step 1: Install base live profile..."
"$ROOT/tools/ui/beagley_live_cluster_profile.sh" "${LIVE_ARGS[@]}"

echo "[premium-720] Step 2: Mark profile identity..."
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$HOST" "set -e
  env_file=/etc/default/beagley-cluster.local
  tmp=\$(mktemp)
  if [ -f \"\$env_file\" ]; then
    awk -F= '\$1 != \"BEAGLEY_DISPLAY_PROFILE\" { print }' \"\$env_file\" >\"\$tmp\"
  fi
  printf 'BEAGLEY_DISPLAY_PROFILE=premium-720\n' >>\"\$tmp\"
  cp \"\$tmp\" \"\$env_file\"
  chmod 0644 \"\$env_file\"
  rm -f \"\$tmp\""

if [[ "$RESTART" != "1" ]]; then
  echo "[premium-720] Restart skipped"
  exit 0
fi

echo "[premium-720] Step 3: Restart beagley_cluster..."
ssh "$HOST" "systemctl daemon-reload && systemctl reset-failed beagley_cluster && systemctl restart beagley_cluster"

if [[ "$HEALTH" != "1" ]]; then
  echo "[premium-720] Health check skipped"
  exit 0
fi

echo "[premium-720] Step 4: Health check..."
BEAGLEY_HOST="$HOST" "$ROOT/skills/beagley-health-check/scripts/check.sh"

echo "[premium-720] Complete"
