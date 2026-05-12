#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../beagley-common/scripts/ssh.sh"

echo "[NET] Resolving BeagleY target..."
if ! beagley_require_ssh_target; then
  echo "[NET] No reachable SSH endpoint resolved from $BEAGLEY_HOST_NAME" >&2
  exit 2
fi
echo "[NET] Using SSH target: $BEAGLEY_SSH_HOST"

beagley_ssh "bash -s" <<'REMOTE'
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

section() {
  printf '\n=== %s ===\n' "$1"
}

section identity
hostname || true
date -Iseconds 2>/dev/null || date || true

section addresses
for iface in eth0 wlan0; do
  ip -br addr show dev "$iface" 2>/dev/null || ip addr show dev "$iface" 2>/dev/null || true
done

section default-routes
ip route show default 2>/dev/null || true

section interface-routes
ip route show dev eth0 2>/dev/null || true
ip route show dev wlan0 2>/dev/null || true

section wifi-service
systemctl show wpa_supplicant@wlan0.service \
  -p ActiveState -p SubState -p NRestarts -p ExecMainStatus --no-pager 2>/dev/null || true

section wifi-status
wpa_cli -i wlan0 status 2>/dev/null || true
iw dev wlan0 link 2>/dev/null || true

section saved-wifi-networks
wpa_cli -i wlan0 list_networks 2>/dev/null || true

section wifi-watchdog
systemctl show beagley-hotspot-watchdog.timer \
  -p ActiveState -p SubState --no-pager 2>/dev/null || true
grep -n 'RESET_WHILE_SCANNING\|DRIVER_RESET_ENABLE\|FAIL_THRESHOLD\|COOLDOWN_SEC' \
  /etc/default/beagley-hotspot-watchdog 2>/dev/null || true

section bbb-link
ping -c 1 -W 1 10.24.0.7 >/dev/null 2>&1 && echo "bbb_ping=ok" || echo "bbb_ping=fail"
if command -v nc >/dev/null 2>&1; then
  nc -z -w 1 10.24.0.7 8765 >/dev/null 2>&1 && echo "bbb_vehicle_hub_8765=open" || echo "bbb_vehicle_hub_8765=closed"
fi

section prohibited-ssid-check
if grep -R 'VX220-9869' /etc/wpa_supplicant /etc/systemd/network >/dev/null 2>&1; then
  echo "VX220-9869=CONFIGURED"
else
  echo "VX220-9869=not-configured"
fi
REMOTE
