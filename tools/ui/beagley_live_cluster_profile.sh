#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"
HUB_URL="${VEHICLE_HUB_WS_URL:-ws://10.24.0.7:8765}"
EFFECT_LEVEL="${BEAGLEY_EFFECT_LEVEL:-low}"
GAUGE_DETAIL="${BEAGLEY_GAUGE_DETAIL:-rich}"
GAUGE_DEMO="${BEAGLEY_GAUGE_DEMO:-0}"
MAP_RENDERER="${BEAGLEY_MAP_RENDERER:-maplibre-native}"
MAPLIBRE_STYLE_URL="${BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL:-https://tiles.openfreemap.org/styles/positron}"
MAPLIBRE_TRUSTED_STYLES="${BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES:-$MAPLIBRE_STYLE_URL}"
MAPLIBRE_FULL_UNDERLAY="${BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY:-0}"
MAPLIBRE_MAX_ZOOM="${BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM:-14.0}"
METRICS=0
RESTART=1
HEALTH=1

usage() {
  cat <<'EOF'
Usage:
  tools/ui/beagley_live_cluster_profile.sh [options]

Puts the BeagleY into the live production-like UI path:
- V3 shell on the real BeagleY display
- MapLibre Native maps in the safe compositor path
- live BBB vehicle_state hub
- no BeagleY app replay file
- no BeagleY stress scene

This is the source-of-truth profile for UI work that should match the final
runtime path. Use BBB bench vehicle sim upstream when you need animated gauge
inputs without a road test.

Options:
  --host HOST             SSH target. Default: root@beagley-ai.local
  --hub-url URL           Vehicle hub URL. Default: ws://10.24.0.7:8765
  --effect-level LEVEL    off, low, or high. Default: low
  --gauge-detail MODE     safe or rich. Default: rich
  --gauge-demo            Show telltales/gear review state without BeagleY replay.
  --no-gauge-demo         Disable gauge visual-review telltales. Default.
  --map-renderer MODE     maplibre-native or native-online. Default: maplibre-native
  --maplibre-style-url URL
                          Trusted MapLibre style. Default: OpenFreeMap Positron
  --maplibre-full-underlay
                          Let MapLibre draw under the full cluster shell.
                          Experimental; unsafe on the BeagleY EGLFS display.
  --maplibre-max-zoom Z   Max MapLibre zoom. Default: 14.0
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
    --gauge-demo)
      GAUGE_DEMO=1
      shift
      ;;
    --no-gauge-demo)
      GAUGE_DEMO=0
      shift
      ;;
    --map-renderer)
      MAP_RENDERER="${2:-}"
      shift 2
      ;;
    --maplibre-style-url)
      MAPLIBRE_STYLE_URL="${2:-}"
      MAPLIBRE_TRUSTED_STYLES="$MAPLIBRE_STYLE_URL"
      shift 2
      ;;
    --maplibre-full-underlay)
      MAPLIBRE_FULL_UNDERLAY=1
      shift
      ;;
    --maplibre-max-zoom)
      MAPLIBRE_MAX_ZOOM="${2:-}"
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
      echo "[beagley-live] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

GAUGE_DETAIL_NORMALIZED="$(printf '%s' "$GAUGE_DETAIL" | tr '[:upper:]' '[:lower:]')"
case "$GAUGE_DETAIL_NORMALIZED" in
  rich|full|high)
    GAUGE_DETAIL=rich
    ;;
  safe|simple|low)
    GAUGE_DETAIL=safe
    ;;
  *)
    echo "[beagley-live] --gauge-detail must be safe or rich: $GAUGE_DETAIL" >&2
    exit 2
    ;;
esac

GAUGE_DEMO_NORMALIZED="$(printf '%s' "$GAUGE_DEMO" | tr '[:upper:]' '[:lower:]')"
case "$GAUGE_DEMO_NORMALIZED" in
  1|true|yes|on)
    GAUGE_DEMO=1
    ;;
  0|false|no|off)
    GAUGE_DEMO=0
    ;;
  *)
    echo "[beagley-live] BEAGLEY_GAUGE_DEMO must be 0 or 1: $GAUGE_DEMO" >&2
    exit 2
    ;;
esac

for value in "$HOST" "$HUB_URL" "$EFFECT_LEVEL" "$GAUGE_DETAIL" "$GAUGE_DEMO" "$MAP_RENDERER" "$MAPLIBRE_STYLE_URL" "$MAPLIBRE_TRUSTED_STYLES" "$MAPLIBRE_FULL_UNDERLAY" "$MAPLIBRE_MAX_ZOOM"; do
  if [[ "$value" == *"'"* ]]; then
    echo "[beagley-live] values may not contain single quotes: $value" >&2
    exit 2
  fi
done

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
echo "[beagley-live] Step 1: Verify SSH..."
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$HOST" true

echo "[beagley-live] Step 2: Install live cluster profile..."
BACKUP_PATH="$(
  ssh "$HOST" "set -e
    backup_dir=/var/lib/beagley-cluster/profile-backups
    mkdir -p \"\$backup_dir\"
    backup=\$backup_dir/beagley-cluster.local.before-live-profile.$STAMP
    if [ -f /etc/default/beagley-cluster.local ]; then
      cp /etc/default/beagley-cluster.local \"\$backup\"
    else
      : >\"\$backup\"
    fi
    cat > /etc/default/beagley-cluster.local <<'REMOTE_ENV'
BEAGLEY_TOUCH_USB_RECOVERY=1
BEAGLEY_TOUCH_GATE_TIMEOUT=20
BEAGLEY_REQUIRE_GPU_GATE=1
BEAGLEY_REQUIRE_TOUCH_GATE=0

# Live production-like cluster profile generated by tools/ui/beagley_live_cluster_profile.sh
BEAGLEY_UI_VARIANT=v3
BEAGLEY_RENDER_PROFILE=embedded
BEAGLEY_EFFECT_LEVEL=$EFFECT_LEVEL
BEAGLEY_GAUGE_DETAIL=$GAUGE_DETAIL
BEAGLEY_GAUGE_DEMO=$GAUGE_DEMO
BEAGLEY_MAP_RENDERER=$MAP_RENDERER
BEAGLEY_MAP_BOOT_MODE=staged
BEAGLEY_MAP_STYLE_MODE=embedded
BEAGLEY_PROFILE_METRICS=$METRICS
BEAGLEY_REPLAY_LOOP=0
BEAGLEY_STRESS_SCENE=0
VEHICLE_HUB_WS_URL=$HUB_URL
BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL=$MAPLIBRE_STYLE_URL
BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES=$MAPLIBRE_TRUSTED_STYLES
BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=0
BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=$MAPLIBRE_FULL_UNDERLAY
BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM=$MAPLIBRE_MAX_ZOOM
REMOTE_ENV
    chmod 0644 /etc/default/beagley-cluster.local
    rm -rf /root/.cache/Beagley/BeagleyCluster/qmlcache
    echo \"\$backup\""
)"
echo "[beagley-live] Remote env backup: $BACKUP_PATH"

if [[ "$RESTART" != "1" ]]; then
  echo "[beagley-live] Restart skipped"
  exit 0
fi

echo "[beagley-live] Step 3: Restart beagley_cluster..."
ssh "$HOST" "systemctl daemon-reload && systemctl reset-failed beagley_cluster && systemctl restart beagley_cluster"

if [[ "$HEALTH" != "1" ]]; then
  echo "[beagley-live] Health check skipped"
  exit 0
fi

echo "[beagley-live] Step 4: Health check..."
if ! "$ROOT/skills/beagley-health-check/scripts/check.sh"; then
  echo "[beagley-live] Health check failed; collecting debug output..."
  "$ROOT/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[beagley-live] Complete"
