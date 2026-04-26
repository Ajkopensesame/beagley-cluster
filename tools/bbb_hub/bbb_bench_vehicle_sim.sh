#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${BBB_HARDWARE_GPS_ENV_FILE:-/etc/default/bbb-hardware-gps}"
SERVICE="${BBB_HARDWARE_GPS_SERVICE:-bbb-hardware-gps}"
MODE="${1:-enable}"
RESTART=1

usage() {
  cat <<'EOF'
Usage:
  tools/bbb_hub/bbb_bench_vehicle_sim.sh [enable|disable|status] [--no-restart]

Run this on the BBB. It toggles BBB_VEHICLE_BENCH_SIM for the production
vehicle_state hub. Bench sim keeps hardware GPS/live maps but synthesizes
vehicle/CAN-like gauge, warning, indicator, and drivetrain fields upstream of
the BeagleY app.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    enable|disable|status)
      MODE="$1"
      shift
      ;;
    --no-restart)
      RESTART=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[bbb-bench-sim] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ "$MODE" == "status" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    grep -E '^(BBB_VEHICLE_BENCH_SIM|GPS_SOURCE_POLICY)=' "$ENV_FILE" || true
  else
    echo "[bbb-bench-sim] env file missing: $ENV_FILE"
  fi
  systemctl is-active "$SERVICE" 2>/dev/null || true
  exit 0
fi

VALUE=1
if [[ "$MODE" == "disable" ]]; then
  VALUE=0
elif [[ "$MODE" != "enable" ]]; then
  echo "[bbb-bench-sim] unknown mode: $MODE" >&2
  usage >&2
  exit 2
fi

TMP="$(mktemp)"
if [[ -f "$ENV_FILE" ]]; then
  awk -F= '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
    {
      key=$1
      sub(/^[[:space:]]*/, "", key)
      sub(/[[:space:]]*$/, "", key)
      if (key != "BBB_VEHICLE_BENCH_SIM" && key != "GPS_SOURCE_POLICY") print
    }
  ' "$ENV_FILE" >"$TMP"
fi

cat >>"$TMP" <<EOF

# Bench sim toggled by tools/bbb_hub/bbb_bench_vehicle_sim.sh
GPS_SOURCE_POLICY=hardware_only
BBB_VEHICLE_BENCH_SIM=$VALUE
EOF

run_root mkdir -p "$(dirname "$ENV_FILE")"
run_root cp "$TMP" "$ENV_FILE"
run_root chmod 0644 "$ENV_FILE"
rm -f "$TMP"

echo "[bbb-bench-sim] BBB_VEHICLE_BENCH_SIM=$VALUE in $ENV_FILE"

if [[ "$RESTART" == "1" ]]; then
  run_root systemctl daemon-reload
  run_root systemctl restart "$SERVICE"
  systemctl status "$SERVICE" --no-pager -n 20
else
  echo "[bbb-bench-sim] restart skipped"
fi
