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

section expected-home-ap-topology
cat <<'EOF'
telstra_gateway=192.168.0.1
tplink_ap_management=192.168.0.2
tplink_ap_mode=LAN-to-LAN yellow ports, DHCP disabled on TP-Link
tplink_2g_ssid=VX220-9869
expected_beagley_eth=192.168.0.46
expected_beagley_wifi=192.168.0.92
expected_elitebook=192.168.0.149
macbook_should_stay_on_telstra_wifi=1
EOF

section wifi-service
systemctl show wpa_supplicant@wlan0.service \
  -p ActiveState -p SubState -p NRestarts -p ExecMainStatus --no-pager 2>/dev/null || true

section wifi-status
wpa_cli -i wlan0 status 2>/dev/null || true
iw dev wlan0 link 2>/dev/null || true

section visible-wifi-networks
if command -v wpa_cli >/dev/null 2>&1; then
  wpa_cli -i wlan0 scan >/dev/null 2>&1 || true
  sleep 3
  wpa_cli -i wlan0 scan_results 2>/dev/null || true
fi

section cc33xx-radio
for param in /sys/module/cc33xx/parameters/ht_mode /sys/module/cc33xx/parameters/no_recovery; do
  if [ -f "$param" ]; then
    printf '%s=%s\n' "$(basename "$param")" "$(cat "$param")"
  fi
done
journalctl -k -b --no-pager 2>/dev/null \
  | grep -E 'Wireless (driver|firmware|PHY) version|cc33xx.*nvs|cc33xx-conf.bin' \
  | tail -n 12 || true

section saved-wifi-networks
wpa_cli -i wlan0 list_networks 2>/dev/null || true
grep -n 'BEAGLEY_PROFILE\|ssid=\|id_str=\|priority=' \
  /etc/wpa_supplicant/wpa_supplicant-wlan0.conf 2>/dev/null \
  | sed -E 's/(psk=).*/\1<redacted>/' || true

section wifi-watchdog
systemctl show beagley-hotspot-watchdog.timer \
  -p ActiveState -p SubState --no-pager 2>/dev/null || true
grep -n 'RESET_WHILE_SCANNING\|DRIVER_RESET_ENABLE\|FAIL_THRESHOLD\|EMPTY_SCAN\|SCAN_SETTLE\|COOLDOWN_SEC' \
  /etc/default/beagley-hotspot-watchdog 2>/dev/null || true

section bbb-link
ping -c 1 -W 1 10.24.0.7 >/dev/null 2>&1 && echo "bbb_ping=ok" || echo "bbb_ping=fail"
if command -v nc >/dev/null 2>&1; then
  nc -z -w 1 10.24.0.7 8765 >/dev/null 2>&1 && echo "bbb_vehicle_hub_8765=open" || echo "bbb_vehicle_hub_8765=closed"
fi

section home-ap-wifi-check
if grep -R 'ssid="VX220-9869"' /etc/wpa_supplicant >/dev/null 2>&1; then
  echo "tplink_2g_saved=yes"
else
  echo "tplink_2g_saved=no"
fi
if grep -R 'id_str="tplink-vx220-2g"' /etc/wpa_supplicant >/dev/null 2>&1; then
  echo "tplink_profile_id=ok"
else
  echo "tplink_profile_id=missing"
fi
if wpa_cli -i wlan0 status 2>/dev/null | grep -q '^ssid=VX220-9869$'; then
  echo "tplink_2g_connected=yes"
else
  echo "tplink_2g_connected=no"
fi

section home-ap-reachability
for target in 192.168.0.1 192.168.0.2; do
  ping -I wlan0 -c 1 -W 2 "$target" >/dev/null 2>&1 \
    && echo "wlan0_ping_$target=ok" \
    || echo "wlan0_ping_$target=fail"
done
if command -v arping >/dev/null 2>&1; then
  for target in 192.168.0.1 192.168.0.2; do
    arping -I wlan0 -c 1 "$target" >/dev/null 2>&1 \
      && echo "wlan0_arping_$target=ok" \
      || echo "wlan0_arping_$target=fail"
  done
fi
REMOTE
