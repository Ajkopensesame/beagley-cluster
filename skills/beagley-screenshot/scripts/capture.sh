#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MODE="current"
HOST_OVERRIDE=""
REMOTE_ROOT="${BEAGLEY_QML_DEV_ROOT:-/opt/beagley-cluster/qml-dev}"
REMOTE_ENV="/etc/default/beagley-cluster.local"
OUT_PATH=""
OUT_DIR="$ROOT/build"
DELAY_MS=4500
RESTORE=1
HEALTH=1
ANALYZE=1
SYNC_QML="auto"

usage() {
  cat <<'EOF'
Usage:
  skills/beagley-screenshot/scripts/capture.sh [options]

Options:
  --wifi-signup          Open and capture the Wi-Fi setup overlay.
  --wifi-networks        Open and capture the Wi-Fi setup overlay with networks visible.
  --wifi-password        Open Wi-Fi setup with a selected network and keyboard visible.
  --current              Capture the normal cluster UI after restart. Default.
  --host HOST            BeagleY SSH target, for example root@192.168.0.92.
  --remote-root PATH     QML dev root. Default: /opt/beagley-cluster/qml-dev.
  --out PATH             Local output PNG path. Default: build/beagley-<mode>-<timestamp>.png.
  --out-dir DIR          Local output directory when --out is not set. Default: build.
  --delay-ms MS          Delay before the app captures the window. Default: 4500.
  --sync-qml             Sync local QML before capture.
  --no-sync-qml          Do not sync QML before capture.
  --no-restore           Leave temporary screenshot env in place. For debugging only.
  --no-health            Skip post-restore health check.
  --no-analyze           Skip screenshot analysis JSON.
  -h, --help             Show this help.

The script restarts beagley_cluster to use the app's built-in screenshot hook,
then restores the normal service environment unless --no-restore is used.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wifi-signup|--wifi-setup)
      MODE="wifi-signup"
      shift
      ;;
    --wifi-networks|--wifi-network-list)
      MODE="wifi-networks"
      shift
      ;;
    --wifi-password|--wifi-password-flow)
      MODE="wifi-password"
      shift
      ;;
    --current)
      MODE="current"
      shift
      ;;
    --host)
      HOST_OVERRIDE="${2:-}"
      if [[ -z "$HOST_OVERRIDE" ]]; then
        echo "[beagley-screenshot] --host requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="${2:-}"
      if [[ -z "$REMOTE_ROOT" ]]; then
        echo "[beagley-screenshot] --remote-root requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --out)
      OUT_PATH="${2:-}"
      if [[ -z "$OUT_PATH" ]]; then
        echo "[beagley-screenshot] --out requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      if [[ -z "$OUT_DIR" ]]; then
        echo "[beagley-screenshot] --out-dir requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --delay-ms)
      DELAY_MS="${2:-}"
      if ! [[ "$DELAY_MS" =~ ^[0-9]+$ ]]; then
        echo "[beagley-screenshot] --delay-ms must be an integer" >&2
        exit 2
      fi
      shift 2
      ;;
    --sync-qml)
      SYNC_QML=1
      shift
      ;;
    --no-sync-qml)
      SYNC_QML=0
      shift
      ;;
    --no-restore)
      RESTORE=0
      shift
      ;;
    --no-health)
      HEALTH=0
      shift
      ;;
    --no-analyze)
      ANALYZE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[beagley-screenshot] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$MODE" in
  current|wifi-signup|wifi-networks|wifi-password) ;;
  *)
    echo "[beagley-screenshot] unsupported mode: $MODE" >&2
    exit 2
    ;;
esac

if [[ -n "$HOST_OVERRIDE" ]]; then
  export BEAGLEY_HOST="$HOST_OVERRIDE"
fi

# shellcheck source=/dev/null
source "$ROOT/skills/beagley-common/scripts/ssh.sh"

remote_quote() {
  local value="$1"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

if ! beagley_require_ssh_target; then
  echo "[beagley-screenshot] BeagleY SSH target not reachable" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_MODE="${MODE//[^A-Za-z0-9_-]/-}"
if [[ -z "$OUT_PATH" ]]; then
  OUT_PATH="$OUT_DIR/beagley-${SAFE_MODE}-${STAMP}.png"
fi
mkdir -p "$(dirname "$OUT_PATH")"

REMOTE_PNG="/tmp/beagley-${SAFE_MODE}-${STAMP}.png"
REMOTE_BACKUP="/tmp/beagley-cluster.local.screenshot-${STAMP}.bak"
REMOTE_TEMP_QML="$REMOTE_ROOT/src/ui/MainV3ScreenshotRequest.qml"
REMOTE_CAPTURE_EXIT=0
SETUP_DONE=0

restore_remote() {
  if [[ "$RESTORE" != "1" || "$SETUP_DONE" != "1" ]]; then
    return
  fi

  echo "[beagley-screenshot] Restoring BeagleY service environment..."
  beagley_ssh "set -e;
    if [ -f $(remote_quote "$REMOTE_BACKUP") ]; then
      current_token_file=\$(mktemp);
      if [ -f $(remote_quote "$REMOTE_ENV") ]; then
        awk -F= '\$1 == \"BEAGLEY_SPOTIFY_REFRESH_TOKEN\" || \$1 == \"BEAGLEY_SPOTIFY_ACCESS_TOKEN\" { print }' $(remote_quote "$REMOTE_ENV") > \"\$current_token_file\" || true;
      else
        : > \"\$current_token_file\";
      fi;
      if [ -s \"\$current_token_file\" ]; then
        tmp_env=\$(mktemp);
        awk -F= '\$1 == \"BEAGLEY_SPOTIFY_REFRESH_TOKEN\" || \$1 == \"BEAGLEY_SPOTIFY_ACCESS_TOKEN\" { next } { print }' $(remote_quote "$REMOTE_BACKUP") > \"\$tmp_env\";
        cat \"\$current_token_file\" >> \"\$tmp_env\";
        cp \"\$tmp_env\" $(remote_quote "$REMOTE_ENV");
        rm -f \"\$tmp_env\";
      else
        cp $(remote_quote "$REMOTE_BACKUP") $(remote_quote "$REMOTE_ENV");
      fi;
      rm -f \"\$current_token_file\";
      chmod 0600 $(remote_quote "$REMOTE_ENV") 2>/dev/null || true;
      rm -f $(remote_quote "$REMOTE_BACKUP");
    fi;
    rm -f $(remote_quote "$REMOTE_TEMP_QML");
    systemctl daemon-reload;
    systemctl reset-failed beagley_cluster;
    systemctl restart beagley_cluster" >/dev/null 2>&1 || true
}
trap restore_remote EXIT

if [[ "$SYNC_QML" == "auto" ]]; then
  if [[ "$MODE" == "wifi-signup" || "$MODE" == "wifi-networks" || "$MODE" == "wifi-password" ]]; then
    SYNC_QML=1
  else
    SYNC_QML=0
  fi
fi

echo "[beagley-screenshot] target=$BEAGLEY_SSH_HOST"
echo "[beagley-screenshot] mode=$MODE"
echo "[beagley-screenshot] remote_png=$REMOTE_PNG"

if [[ "$SYNC_QML" == "1" ]]; then
  echo "[beagley-screenshot] Syncing QML to $REMOTE_ROOT..."
  "$ROOT/tools/ui/beagley_sync_qml.sh" \
    --host "$BEAGLEY_SSH_HOST" \
    --remote-root "$REMOTE_ROOT" \
    --no-restart \
    --no-health
fi

echo "[beagley-screenshot] Preparing temporary screenshot env..."
SETUP_DONE=1
beagley_ssh "bash -s -- \
  $(remote_quote "$MODE") \
  $(remote_quote "$REMOTE_PNG") \
  $(remote_quote "$REMOTE_ROOT") \
  $(remote_quote "$REMOTE_ENV") \
  $(remote_quote "$REMOTE_BACKUP") \
  $(remote_quote "$REMOTE_TEMP_QML") \
  $(remote_quote "$DELAY_MS") \
  $(remote_quote "$REMOTE_CAPTURE_EXIT") \
  $(remote_quote "$SYNC_QML")" <<'REMOTE'
set -euo pipefail

mode="$1"
remote_png="$2"
remote_root="$3"
remote_env="$4"
remote_backup="$5"
remote_temp_qml="$6"
delay_ms="$7"
screenshot_exit="$8"
sync_qml="$9"

qml_escape_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g'
}

fallback_ssid=""
fallback_signal=""
fallback_security="Secure"
if [ "$mode" = "wifi-networks" ] || [ "$mode" = "wifi-password" ]; then
  wpa_cli -i wlan0 scan >/dev/null 2>&1 || true
  sleep 3
  scan_line="$(wpa_cli -i wlan0 scan_results 2>/dev/null \
    | awk -F '\t' 'NF >= 5 && $1 !~ /^bssid/ && $1 !~ /^Selected interface/ { print; exit }' || true)"
  if [ -n "$scan_line" ]; then
    fallback_signal="$(printf '%s\n' "$scan_line" | awk -F '\t' '{ if ($3 != "") print int($3) " dBm" }')"
    fallback_flags="$(printf '%s\n' "$scan_line" | awk -F '\t' '{ print $4 }')"
    fallback_ssid="$(printf '%s\n' "$scan_line" | awk -F '\t' '{ ssid=$5; for (i = 6; i <= NF; ++i) ssid = ssid "\t" $i; print ssid }')"
    case "$fallback_flags" in
      *WPA*|*WEP*) fallback_security="Secure" ;;
      *) fallback_security="Open" ;;
    esac
  fi
  if [ -z "$fallback_ssid" ]; then
    fallback_ssid="$(wpa_cli -i wlan0 status 2>/dev/null | awk -F= '$1 == "ssid" { print $2; exit }' || true)"
  fi
fi

qml_fallback_ssid="$(qml_escape_string "$fallback_ssid")"
qml_fallback_signal="$(qml_escape_string "$fallback_signal")"
qml_fallback_security="$(qml_escape_string "$fallback_security")"

if [ -f "$remote_env" ]; then
  cp "$remote_env" "$remote_backup"
else
  : > "$remote_backup"
  mkdir -p "$(dirname "$remote_env")"
  : > "$remote_env"
fi

append_qml_env=0
qml_dev_file="$remote_root/src/ui/MainV3.qml"
if [ "$mode" = "wifi-signup" ] || [ "$mode" = "wifi-networks" ] || [ "$mode" = "wifi-password" ]; then
  if [ ! -f "$qml_dev_file" ]; then
    echo "[beagley-screenshot] missing QML dev source: $qml_dev_file" >&2
    exit 1
  fi
  awk '
    { lines[NR] = $0 }
    END {
      for (i = 1; i < NR; ++i) print lines[i]
      print ""
      print "    Timer {"
      print "        interval: 900"
      print "        running: true"
      print "        repeat: false"
      print "        onTriggered: wifiOverlay.openPrompt()"
	      print "    }"
	      if ("'"$mode"'" == "wifi-networks") {
	        print ""
	        print "    Timer {"
	        print "        interval: 1800"
	        print "        running: true"
	        print "        repeat: false"
	        print "        onTriggered: wifiOverlay.showNetworkPickerWithFallback(\"'"$qml_fallback_ssid"'\", \"'"$qml_fallback_signal"'\", \"'"$qml_fallback_security"'\")"
	        print "    }"
	      } else if ("'"$mode"'" == "wifi-password") {
	        print ""
	        print "    Timer {"
	        print "        interval: 1800"
	        print "        running: true"
	        print "        repeat: false"
	        print "        onTriggered: {"
	        print "            wifiOverlay.showNetworkPickerWithFallback(\"'"$qml_fallback_ssid"'\", \"'"$qml_fallback_signal"'\", \"'"$qml_fallback_security"'\")"
	        print "            wifiOverlay.selectNetwork(\"'"$qml_fallback_ssid"'\")"
	        print "            wifiOverlay.applyKey(\"p\")"
	        print "            wifiOverlay.applyKey(\"a\")"
	        print "            wifiOverlay.applyKey(\"s\")"
	        print "            wifiOverlay.applyKey(\"s\")"
	        print "            wifiOverlay.applyKey(\"w\")"
	        print "            wifiOverlay.applyKey(\"o\")"
	        print "            wifiOverlay.applyKey(\"r\")"
	        print "            wifiOverlay.applyKey(\"d\")"
	        print "        }"
	        print "    }"
	      }
      print lines[NR]
    }
  ' "$qml_dev_file" > "$remote_temp_qml"
  chmod 0644 "$remote_temp_qml"
  qml_dev_file="$remote_temp_qml"
  append_qml_env=1
elif [ "$sync_qml" = "1" ]; then
  if [ ! -f "$qml_dev_file" ]; then
    echo "[beagley-screenshot] missing QML dev source: $qml_dev_file" >&2
    exit 1
  fi
  append_qml_env=1
fi

drop_keys="BEAGLEY_SCREENSHOT_PATH BEAGLEY_SCREENSHOT_DELAY_MS BEAGLEY_SCREENSHOT_EXIT"
if [ "$append_qml_env" = "1" ]; then
  drop_keys="$drop_keys BEAGLEY_QML_DEV_ROOT BEAGLEY_QML_DEV_FILE"
fi

tmp="$(mktemp)"
DROP_KEYS="$drop_keys" awk -F= '
BEGIN {
  split(ENVIRON["DROP_KEYS"], keys, " ")
  for (i in keys) drop[keys[i]] = 1
}
($1 in drop) { next }
{ print }
' "$remote_env" > "$tmp"

{
  if [ "$append_qml_env" = "1" ]; then
    printf 'BEAGLEY_QML_DEV_ROOT=%s\n' "$remote_root"
    printf 'BEAGLEY_QML_DEV_FILE=%s\n' "$qml_dev_file"
  fi
  printf 'BEAGLEY_SCREENSHOT_PATH=%s\n' "$remote_png"
  printf 'BEAGLEY_SCREENSHOT_DELAY_MS=%s\n' "$delay_ms"
  printf 'BEAGLEY_SCREENSHOT_EXIT=%s\n' "$screenshot_exit"
} >> "$tmp"

cp "$tmp" "$remote_env"
chown root:root "$remote_env" 2>/dev/null || true
chmod 0600 "$remote_env" 2>/dev/null || true
rm -f "$tmp" "$remote_png"

systemctl daemon-reload
systemctl reset-failed beagley_cluster
systemctl restart beagley_cluster
REMOTE

timeout_seconds=$((DELAY_MS / 1000 + 25))
echo "[beagley-screenshot] Waiting up to ${timeout_seconds}s for screenshot..."
for _ in $(seq 1 "$timeout_seconds"); do
  if beagley_ssh "test -s $(remote_quote "$REMOTE_PNG")"; then
    break
  fi
  sleep 1
done

if ! beagley_ssh "test -s $(remote_quote "$REMOTE_PNG")"; then
  echo "[beagley-screenshot] screenshot was not created" >&2
  exit 1
fi

beagley_ssh "cat $(remote_quote "$REMOTE_PNG")" > "$OUT_PATH"
echo "[beagley-screenshot] output=$OUT_PATH"
file "$OUT_PATH" || true

if [[ "$ANALYZE" == "1" && -f "$ROOT/tools/maplibre/analyze_screenshot.py" ]]; then
  ANALYSIS_PATH="${OUT_PATH%.png}.analysis.json"
  if python3 "$ROOT/tools/maplibre/analyze_screenshot.py" "$OUT_PATH" --json > "$ANALYSIS_PATH"; then
    echo "[beagley-screenshot] analysis=$ANALYSIS_PATH"
  else
    echo "[beagley-screenshot] screenshot analysis failed: $ANALYSIS_PATH" >&2
    cat "$ANALYSIS_PATH" >&2 || true
    exit 1
  fi
fi

restore_remote
SETUP_DONE=0

if [[ "$HEALTH" == "1" ]]; then
  echo "[beagley-screenshot] Health check..."
  if ! "$ROOT/skills/beagley-health-check/scripts/check.sh"; then
    echo "[beagley-screenshot] health check failed; collecting debug output" >&2
    "$ROOT/skills/beagley-debug-service/scripts/debug.sh" || true
    exit 1
  fi
fi

echo "[beagley-screenshot] Complete"
