#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./setup_wifi.sh --ssid <SSID> --psk <PASSWORD> [options]
  sudo ./setup_wifi.sh --profiles-file <tsv> [options]

Options:
  --ssid <ssid>           Single-profile mode SSID
  --psk <password>        Single-profile mode PSK
  --profile-id <id>       Single-profile saved-hotspot ID (default: derived from SSID)
  --priority <n>          Single-profile priority (default: 100)
  --profiles-file <tsv>   Multi-profile TSV with columns:
                          id<TAB>ssid<TAB>psk<TAB>priority<TAB>fallback_address
  --iface <name>          Wireless interface (default: wlan0)
  --country <code>        2-letter regulatory country code (default: AU)
  --host-name <name>      mDNS/SSH host name to publish (default: beagley)
  --fallback-address <cidr>
                          Single-profile fallback hotspot SSH address
  --route-metric <n>      DHCP route metric for wlan (default: 200)
  --wifi-power-save <on|off>
                          Wi-Fi power-save policy (default: off)
  --gateway-watchdog-enable
                          Enable hotspot gateway watchdog (default)
  --gateway-watchdog-disable
                          Disable hotspot gateway watchdog
  --gateway-watchdog-interval-sec <n>
                          Watchdog poll interval in seconds (default: 15)
  --gateway-watchdog-failures <n>
                          Consecutive failures before restart (default: 3)
  --gateway-watchdog-cooldown-sec <n>
                          Minimum seconds between recovery restarts (default: 45)
  --gateway-watchdog-target <ip|auto>
                          Health probe target (default: auto => wlan default gateway)
  --eth-iface <name>      Ethernet interface to keep on DHCP (default: eth0)
  --eth-route-metric <n>
                          DHCP route metric for ethernet (default: 100)
  --bbb-gateway-enable    Configure Beagley as the BBB hotspot gateway
  --bbb-gateway-address <cidr>
                          Static Beagley address on the BBB link (default: 10.24.0.46/24)
  --bbb-host <host>       BBB host/IP for reachability check (default: 10.24.0.7)
  --help                  Show this help

What this script does:
  1) Creates an ordered saved-hotspot set in /etc/wpa_supplicant/wpa_supplicant-<iface>.conf
  2) Creates /etc/systemd/network/<iface>.network for Wi-Fi (DHCPv4 + route metric)
  3) Installs an OS-side reconcile service/timer for hotspot-specific SSH fallback IPs
  4) Enforces persistent Wi-Fi power-save policy and gateway watchdog recovery
  5) Optionally enables BBB gateway mode on ethernet with persistent IPv4 forwarding
  6) Sets a stable host name, keeps /etc/hosts in sync, and advertises SSH over mDNS
  7) Enables and restarts wpa_supplicant@<iface> without dropping the current SSH path
  8) Prints link, route, and hotspot-profile diagnostics
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

has_unit_file() {
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q "^$1"
}

timestamp() {
  date +"%Y%m%d_%H%M%S"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

sanitize_profile_id() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
  printf '%s' "$value"
}

derive_profile_id() {
  local ssid="$1"
  local fallback_id
  fallback_id="$(sanitize_profile_id "$ssid")"
  if [[ -z "$fallback_id" ]]; then
    fallback_id="hotspot-$(( ${#PROFILE_IDS[@]} + 1 ))"
  fi
  printf '%s' "$fallback_id"
}

render_wpa_network_block() {
  local profile_id="$1"
  local ssid="$2"
  local psk="$3"
  local priority="$4"
  local fallback="$5"
  local fallback_label="-"

  if [[ -n "$fallback" ]]; then
    fallback_label="$fallback"
  fi

  printf '# BEAGLEY_PROFILE id=%s fallback=%s\n' "$profile_id" "$fallback_label"
  wpa_passphrase "$ssid" "$psk" | awk -v priority="$priority" -v profile_id="$profile_id" '
    /^[[:space:]]*#psk=/ { next }
    /^\}/ {
      print "\tpriority=" priority
      print "\tid_str=\"" profile_id "\""
      print "\tscan_ssid=1"
      print
      next
    }
    { print }
  '
  printf '\n'
}

write_wlan_network_file() {
  local net_file="$1"
  local iface="$2"
  local route_metric="$3"
  local fallback_address="$4"

  cat >"$net_file" <<EOF
[Match]
Name=${iface}
Type=wlan

[Link]
RequiredForOnline=no

[Network]
ConfigureWithoutCarrier=yes
DHCP=ipv4
EOF

  if [[ -n "$fallback_address" ]]; then
    cat >>"$net_file" <<EOF
Address=${fallback_address}
EOF
  fi

  cat >>"$net_file" <<EOF

[DHCPv4]
ClientIdentifier=mac
RouteMetric=${route_metric}
UseDNS=yes
EOF
}

cidr_network() {
  local cidr="$1"
  local ip prefix o1 o2 o3 o4 ip_int mask net_int

  IFS=/ read -r ip prefix <<<"$cidr"
  IFS=. read -r o1 o2 o3 o4 <<<"$ip"

  if [[ -z "$prefix" || -z "$o1" || -z "$o2" || -z "$o3" || -z "$o4" ]]; then
    echo "Invalid IPv4 CIDR: $cidr" >&2
    exit 1
  fi

  ip_int=$(( (o1 << 24) | (o2 << 16) | (o3 << 8) | o4 ))
  if (( prefix == 0 )); then
    mask=0
  else
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  fi
  net_int=$(( ip_int & mask ))

  printf '%d.%d.%d.%d/%d' \
    $(( (net_int >> 24) & 255 )) \
    $(( (net_int >> 16) & 255 )) \
    $(( (net_int >> 8) & 255 )) \
    $(( net_int & 255 )) \
    "$prefix"
}

install_bbb_gateway_nat_stack() {
  local nft_file="$1"
  local service_file="$2"
  local lan_cidr="$3"
  local lan_iface="$4"
  local wan_iface="$5"

  mkdir -p "$(dirname "$nft_file")" "$(dirname "$service_file")"

  cat >"$nft_file" <<EOF
table inet beagley_bbb_gateway {
  chain forward {
    type filter hook forward priority filter; policy accept;
    iifname "${lan_iface}" oifname "${wan_iface}" accept
    iifname "${wan_iface}" oifname "${lan_iface}" ct state established,related accept
  }
}

table ip beagley_bbb_gateway_nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr ${lan_cidr} oifname "${wan_iface}" masquerade
  }
}
EOF

  cat >"$service_file" <<EOF
[Unit]
Description=Apply Beagley BBB gateway nftables rules
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f ${nft_file}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

install_reconcile_stack() {
  local default_file="$1"
  local service_file="$2"
  local timer_file="$3"
  local script_file="$4"
  local iface="$5"
  local wpa_file="$6"
  local wifi_power_save="$7"

  mkdir -p "$(dirname "$default_file")" "$(dirname "$service_file")" "$(dirname "$script_file")"

  cat >"$default_file" <<EOF
IFACE=${iface}
WPA_FILE=${wpa_file}
WIFI_POWER_SAVE=${wifi_power_save}
EOF

  cat >"$script_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

: "${IFACE:=wlan0}"
: "${WPA_FILE:=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf}"
: "${FALLBACK_LABEL:=${IFACE}:bf}"
: "${WIFI_POWER_SAVE:=off}"

  if [[ "$WIFI_POWER_SAVE" == "off" ]]; then
    if command -v iw >/dev/null 2>&1; then
      iw dev "$IFACE" set power_save off >/dev/null 2>&1 || true
    elif command -v iwconfig >/dev/null 2>&1; then
      iwconfig "$IFACE" power off >/dev/null 2>&1 || true
    fi
  fi

  current_ssid=""
  if command -v iw >/dev/null 2>&1; then
    current_ssid="$(
      iw dev "$IFACE" link 2>/dev/null | awk '
        /^[[:space:]]*SSID:/ {
          sub(/^[[:space:]]*SSID:[[:space:]]*/, "", $0)
          print
          exit
        }
      '
    )"
  elif command -v wpa_cli >/dev/null 2>&1; then
    current_ssid="$(
      wpa_cli -i "$IFACE" status 2>/dev/null | awk -F= '
        $1 == "ssid" {
          print $2
          exit
        }
      '
    )"
  fi

desired_fallback="$(
  awk -v target="$current_ssid" '
    BEGIN {
      marker_fallback = ""
      in_block = 0
    }
    /^# BEAGLEY_PROFILE / {
      marker_fallback = ""
      count = split($0, parts, /[[:space:]]+/)
      for (i = 1; i <= count; ++i) {
        if (parts[i] ~ /^fallback=/) {
          marker_fallback = substr(parts[i], 10)
          break
        }
      }
      next
    }
    /^[[:space:]]*network=\{/ {
      in_block = 1
      next
    }
    in_block && /^[[:space:]]*ssid="/ {
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/".*$/, "", line)
      if (line == target) {
        print marker_fallback
        exit
      }
      next
    }
    in_block && /^[[:space:]]*\}/ {
      in_block = 0
      marker_fallback = ""
    }
  ' "$WPA_FILE"
)"

if [[ "$desired_fallback" == "-" || "$desired_fallback" == "none" ]]; then
  desired_fallback=""
fi

current_fallbacks="$(
  ip -o -4 addr show dev "$IFACE" label "$FALLBACK_LABEL" 2>/dev/null | awk '{ print $4 }'
)"

while IFS= read -r existing_fallback; do
  [[ -n "$existing_fallback" ]] || continue
  if [[ "$existing_fallback" != "$desired_fallback" ]]; then
    ip addr del "$existing_fallback" dev "$IFACE" label "$FALLBACK_LABEL" >/dev/null 2>&1 || true
  fi
done <<<"$current_fallbacks"

if [[ -n "$desired_fallback" ]]; then
  if ! ip -o -4 addr show dev "$IFACE" label "$FALLBACK_LABEL" 2>/dev/null | awk '{ print $4 }' | grep -Fxq "$desired_fallback"; then
    ip addr add "$desired_fallback" dev "$IFACE" label "$FALLBACK_LABEL" >/dev/null 2>&1 || true
  fi
fi
EOF

  chmod 755 "$script_file"

  cat >"$service_file" <<EOF
[Unit]
Description=Reconcile Beagley hotspot fallback address
After=wpa_supplicant@${iface}.service
Wants=wpa_supplicant@${iface}.service

[Service]
Type=oneshot
EnvironmentFile=-${default_file}
ExecStart=${script_file}
EOF

  cat >"$timer_file" <<EOF
[Unit]
Description=Periodic Beagley hotspot fallback reconcile

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=1s
Unit=$(basename "$service_file")

[Install]
WantedBy=timers.target
EOF
}

install_gateway_watchdog_stack() {
  local default_file="$1"
  local service_file="$2"
  local timer_file="$3"
  local script_file="$4"
  local iface="$5"
  local interval_sec="$6"
  local fail_threshold="$7"
  local cooldown_sec="$8"
  local probe_target="$9"

  mkdir -p "$(dirname "$default_file")" "$(dirname "$service_file")" "$(dirname "$script_file")"

  cat >"$default_file" <<EOF
IFACE=${iface}
FAIL_THRESHOLD=${fail_threshold}
COOLDOWN_SEC=${cooldown_sec}
PROBE_TARGET=${probe_target}
STATE_FILE=/run/beagley-hotspot-watchdog.state
DRIVER_RESET_ENABLE=1
DRIVER_MODULES="cc33xx_sdio cc33xx"
REQUIRE_INTERNET=0
RESET_WHILE_SCANNING=0
SCANNING_FAIL_THRESHOLD=8
FLUSH_STALE_ADDRESS_WHILE_SCANNING=1
EOF

  cat >"$script_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

: "${IFACE:=wlan0}"
: "${FAIL_THRESHOLD:=3}"
: "${COOLDOWN_SEC:=45}"
: "${PROBE_TARGET:=auto}"
: "${STATE_FILE:=/run/beagley-hotspot-watchdog.state}"
: "${DRIVER_RESET_ENABLE:=1}"
: "${DRIVER_MODULES:=cc33xx_sdio cc33xx}"
: "${REQUIRE_INTERNET:=0}"
: "${RESET_WHILE_SCANNING:=0}"
: "${SCANNING_FAIL_THRESHOLD:=8}"
: "${FLUSH_STALE_ADDRESS_WHILE_SCANNING:=1}"

log() {
  logger -t beagley-hotspot-watchdog "$*"
}

is_enabled() {
  case "$1" in
    1|true|True|TRUE|yes|Yes|YES|on|On|ON) return 0 ;;
    *) return 1 ;;
  esac
}

has_ipv4() {
  ip -o -4 addr show dev "$IFACE" scope global 2>/dev/null | grep -q 'inet '
}

has_default_route() {
  ip route show default dev "$IFACE" 2>/dev/null | grep -q '^default '
}

try_dhcp_refresh() {
  networkctl renew "$IFACE" >/dev/null 2>&1 || true
  networkctl reconfigure "$IFACE" >/dev/null 2>&1 || true
  sleep 3
}

flush_stale_wifi_address() {
  ip addr flush dev "$IFACE" scope global >/dev/null 2>&1 || true
  ip route flush dev "$IFACE" proto dhcp >/dev/null 2>&1 || true
  networkctl reconfigure "$IFACE" >/dev/null 2>&1 || true
}

full_radio_reset() {
  local first_module=""

  ip neigh flush dev "$IFACE" >/dev/null 2>&1 || true
  ip addr flush dev "$IFACE" scope global >/dev/null 2>&1 || true
  systemctl stop "wpa_supplicant@${IFACE}.service" >/dev/null 2>&1 || true
  ip link set "$IFACE" down >/dev/null 2>&1 || true

  if [[ "$DRIVER_RESET_ENABLE" != "0" && "$DRIVER_RESET_ENABLE" != "false" && "$DRIVER_RESET_ENABLE" != "off" && "$DRIVER_RESET_ENABLE" != "no" ]]; then
    # The TI CC33xx driver can recover enough for wlan0 to exist while still
    # returning EBUSY to wpa_supplicant. A module cycle is the validated
    # recovery path for that state.
    set -- $DRIVER_MODULES
    first_module="${1:-}"
    if [[ -n "$first_module" ]]; then
      modprobe -r "$@" >/dev/null 2>&1 || true
      sleep 2
      modprobe "$first_module" >/dev/null 2>&1 || true
    fi
  fi

  sleep 2
  systemctl restart systemd-networkd.service >/dev/null 2>&1 || true
  systemctl reset-failed "wpa_supplicant@${IFACE}.service" >/dev/null 2>&1 || true
  systemctl start "wpa_supplicant@${IFACE}.service" >/dev/null 2>&1 || true
  networkctl reconfigure "$IFACE" >/dev/null 2>&1 || true
}

supplicant_unhealthy() {
  local active sub result

  active="$(systemctl show "wpa_supplicant@${IFACE}.service" -p ActiveState --value 2>/dev/null || true)"
  sub="$(systemctl show "wpa_supplicant@${IFACE}.service" -p SubState --value 2>/dev/null || true)"
  result="$(systemctl show "wpa_supplicant@${IFACE}.service" -p Result --value 2>/dev/null || true)"

  if [[ "$active" != "active" || "$sub" != "running" ]]; then
    reason="supplicant-${active:-unknown}-${sub:-unknown}-${result:-unknown}"
    return 0
  fi
  return 1
}

wpa_state=""
if command -v wpa_cli >/dev/null 2>&1; then
  wpa_state="$(
    wpa_cli -i "$IFACE" status 2>/dev/null | awk -F= '
      $1 == "wpa_state" {
        print $2
        exit
      }
    '
  )"
fi

assoc_known=0
connected=0
if command -v iw >/dev/null 2>&1; then
  assoc_known=1
  if iw dev "$IFACE" link 2>/dev/null | grep -q '^Connected to '; then
    connected=1
  fi
elif command -v wpa_cli >/dev/null 2>&1; then
  assoc_known=1
  if [[ "$wpa_state" == "COMPLETED" ]]; then
    connected=1
  fi
fi

ip_ok=0
if ip -o -4 addr show dev "$IFACE" scope global 2>/dev/null | grep -q 'inet '; then
  ip_ok=1
fi

gateway="$(
  ip route show default dev "$IFACE" 2>/dev/null | awk '
    /default/ {
      for (i = 1; i <= NF; ++i) {
        if ($i == "via" && (i + 1) <= NF) {
          print $(i + 1)
          exit
        }
      }
    }
  '
)"

target="$PROBE_TARGET"
if [[ "$target" == "auto" ]]; then
  target="$gateway"
fi

now="$(date +%s)"
count=0
last_restart=0
last_reason=""
if [[ -f "$STATE_FILE" ]]; then
  read -r count last_restart last_reason < "$STATE_FILE" || true
fi

healthy=1
reason=""
if supplicant_unhealthy; then
  healthy=0
elif [[ "$assoc_known" == "1" && "$connected" != "1" ]]; then
  healthy=0
  reason="not-associated"
elif [[ "$ip_ok" != "1" ]]; then
  healthy=0
  reason="no-ipv4-lease"
elif [[ -z "$gateway" ]]; then
  healthy=0
  reason="no-default-gateway"
elif [[ -z "$target" ]]; then
  healthy=0
  reason="no-probe-target"
elif ! ping -I "$IFACE" -c 1 -W 1 "$target" >/dev/null 2>&1; then
  if [[ "$REQUIRE_INTERNET" != "1" && "$REQUIRE_INTERNET" != "true" && "$REQUIRE_INTERNET" != "yes" ]]; then
    log "internet probe failed iface=${IFACE} target=${target}; link is associated with ipv4/default route, leaving radio up"
    printf '0 %s\n' "$last_restart" > "$STATE_FILE"
    exit 0
  fi
  healthy=0
  reason="probe-failed:${target}"
fi

if [[ "$healthy" == "1" ]]; then
  printf '0 %s healthy\n' "$last_restart" > "$STATE_FILE"
  exit 0
fi

if [[ "$last_reason" != "$reason" ]]; then
  count=0
fi

if [[ "$reason" == "not-associated" ]] && ! is_enabled "$RESET_WHILE_SCANNING"; then
  count=$((count + 1))
  if is_enabled "$FLUSH_STALE_ADDRESS_WHILE_SCANNING"; then
    flush_stale_wifi_address
  fi
  if command -v wpa_cli >/dev/null 2>&1; then
    wpa_cli -i "$IFACE" scan >/dev/null 2>&1 || true
    wpa_cli -i "$IFACE" reassociate >/dev/null 2>&1 || true
  fi
  if (( count < SCANNING_FAIL_THRESHOLD )); then
    printf '%s %s %s\n' "$count" "$last_restart" "$reason" > "$STATE_FILE"
    log "waiting iface=${IFACE} reason=${reason} count=${count}/${SCANNING_FAIL_THRESHOLD} wpa_state=${wpa_state:-unknown}; leaving supplicant scanning"
    exit 0
  fi
  if (( now - last_restart < COOLDOWN_SEC )); then
    printf '%s %s %s\n' "$count" "$last_restart" "$reason" > "$STATE_FILE"
    log "cooldown iface=${IFACE} reason=${reason} count=${count}/${SCANNING_FAIL_THRESHOLD} wpa_state=${wpa_state:-unknown}; reset deferred"
    exit 0
  fi
  log "recover iface=${IFACE} reason=${reason} count=${count}/${SCANNING_FAIL_THRESHOLD}; sustained scanning, resetting radio+supplicant+networkd"
  full_radio_reset
  printf '0 %s reset-scanning\n' "$now" > "$STATE_FILE"
  exit 0
fi

count=$((count + 1))
if (( count >= FAIL_THRESHOLD )); then
  if (( now - last_restart >= COOLDOWN_SEC )); then
    if [[ "$reason" == "no-ipv4-lease" || "$reason" == "no-default-gateway" || "$reason" == probe-failed:* ]]; then
      log "refresh iface=${IFACE} reason=${reason} count=${count}; renewing dhcp"
      try_dhcp_refresh
      if has_ipv4 && has_default_route; then
        printf '0 %s recovered-dhcp\n' "$last_restart" > "$STATE_FILE"
        exit 0
      fi
    fi

    log "recover iface=${IFACE} reason=${reason} count=${count}; resetting radio+supplicant+networkd"
    full_radio_reset
    printf '0 %s %s\n' "$now" "$reason" > "$STATE_FILE"
    exit 0
  fi
fi

printf '%s %s %s\n' "$count" "$last_restart" "$reason" > "$STATE_FILE"
log "unhealthy iface=${IFACE} reason=${reason} count=${count}"
EOF

  chmod 755 "$script_file"

  cat >"$service_file" <<EOF
[Unit]
Description=Beagley hotspot gateway watchdog
After=wpa_supplicant@${iface}.service systemd-networkd.service
Wants=wpa_supplicant@${iface}.service systemd-networkd.service

[Service]
Type=oneshot
EnvironmentFile=-${default_file}
ExecStart=${script_file}
EOF

  cat >"$timer_file" <<EOF
[Unit]
Description=Periodic Beagley hotspot gateway watchdog

[Timer]
OnBootSec=35s
OnUnitActiveSec=${interval_sec}s
AccuracySec=1s
Unit=$(basename "$service_file")

[Install]
WantedBy=timers.target
EOF
}

install_arp_flux_sysctl() {
  local sysctl_file="$1"
  local eth_iface="$2"
  local wifi_iface="$3"

  cat >"$sysctl_file" <<EOF
# Keep the BeagleY Ethernet and Wi-Fi modem leases from answering for each
# other. Without this, eth0 can answer ARP for wlan0's reserved IP after a
# carrier loss, which makes the router and deploy tools think Wi-Fi is alive.
net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.default.arp_ignore=1
net.ipv4.conf.${eth_iface}.arp_ignore=1
net.ipv4.conf.${wifi_iface}.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.default.arp_announce=2
net.ipv4.conf.${eth_iface}.arp_announce=2
net.ipv4.conf.${wifi_iface}.arp_announce=2
net.ipv4.conf.all.arp_filter=1
net.ipv4.conf.default.arp_filter=1
net.ipv4.conf.${eth_iface}.arp_filter=1
net.ipv4.conf.${wifi_iface}.arp_filter=1
EOF

  sysctl -p "$sysctl_file" >/dev/null || true
}

add_profile() {
  local raw_id="$1"
  local ssid="$2"
  local psk="$3"
  local priority="$4"
  local fallback="$5"

  ssid="$(trim "$ssid")"
  psk="$(trim "$psk")"
  priority="$(trim "$priority")"
  fallback="$(trim "$fallback")"

  if [[ -z "$ssid" || -z "$psk" ]]; then
    echo "Each hotspot profile requires non-empty SSID and PSK." >&2
    exit 1
  fi
  if [[ ${#psk} -lt 8 ]]; then
    echo "PSK for hotspot '$ssid' must be at least 8 characters." >&2
    exit 1
  fi
  if [[ -z "$priority" ]]; then
    priority="100"
  fi
  if [[ ! "$priority" =~ ^[0-9]+$ ]]; then
    echo "Priority for hotspot '$ssid' must be numeric." >&2
    exit 1
  fi

  local profile_id
  if [[ -n "$raw_id" ]]; then
    profile_id="$(sanitize_profile_id "$raw_id")"
  else
    profile_id="$(derive_profile_id "$ssid")"
  fi
  if [[ -z "$profile_id" ]]; then
    echo "Unable to derive a stable profile id for hotspot '$ssid'." >&2
    exit 1
  fi

  PROFILE_IDS+=("$profile_id")
  PROFILE_SSIDS+=("$ssid")
  PROFILE_PSKS+=("$psk")
  PROFILE_PRIORITIES+=("$priority")
  PROFILE_FALLBACKS+=("$fallback")
}

load_profiles_from_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Profiles file '$path' was not found." >&2
    exit 1
  fi

  local line_no=0
  while IFS=$'\t' read -r raw_id raw_ssid raw_psk raw_priority raw_fallback extra || [[ -n "${raw_id}${raw_ssid}${raw_psk}${raw_priority}${raw_fallback}${extra}" ]]; do
    line_no=$((line_no + 1))

    if [[ -z "${raw_id}${raw_ssid}${raw_psk}${raw_priority}${raw_fallback}${extra}" ]]; then
      continue
    fi

    if [[ "$(trim "$raw_id")" == \#* ]]; then
      continue
    fi

    if [[ "$(trim "$raw_id")" == "id" && "$(trim "$raw_ssid")" == "ssid" ]]; then
      continue
    fi

    if [[ -n "$extra" ]]; then
      echo "Profiles file '$path' has too many columns on line $line_no." >&2
      exit 1
    fi

    add_profile "$raw_id" "$raw_ssid" "$raw_psk" "$raw_priority" "$raw_fallback"
  done < "$path"
}

SSID=""
PSK=""
PROFILE_ID=""
PROFILE_PRIORITY="100"
PROFILES_FILE=""
IFACE="wlan0"
COUNTRY="AU"
HOST_NAME="beagley"
FALLBACK_ADDRESS=""
ROUTE_METRIC="200"
ETH_IFACE="eth0"
ETH_ROUTE_METRIC="100"
BBB_GATEWAY_ENABLE="0"
BBB_GATEWAY_ADDRESS="10.24.0.46/24"
BBB_HOST="10.24.0.7"
WIFI_POWER_SAVE="off"
GATEWAY_WATCHDOG_ENABLE="1"
GATEWAY_WATCHDOG_INTERVAL_SEC="15"
GATEWAY_WATCHDOG_FAILURES="3"
GATEWAY_WATCHDOG_COOLDOWN_SEC="45"
GATEWAY_WATCHDOG_TARGET="auto"

PROFILE_IDS=()
PROFILE_SSIDS=()
PROFILE_PSKS=()
PROFILE_PRIORITIES=()
PROFILE_FALLBACKS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssid)
      SSID="${2:-}"; shift 2 ;;
    --psk)
      PSK="${2:-}"; shift 2 ;;
    --profile-id)
      PROFILE_ID="${2:-}"; shift 2 ;;
    --priority)
      PROFILE_PRIORITY="${2:-}"; shift 2 ;;
    --profiles-file)
      PROFILES_FILE="${2:-}"; shift 2 ;;
    --iface)
      IFACE="${2:-}"; shift 2 ;;
    --country)
      COUNTRY="${2:-}"; shift 2 ;;
    --host-name)
      HOST_NAME="${2:-}"; shift 2 ;;
    --fallback-address)
      FALLBACK_ADDRESS="${2:-}"; shift 2 ;;
    --route-metric)
      ROUTE_METRIC="${2:-}"; shift 2 ;;
    --wifi-power-save)
      WIFI_POWER_SAVE="${2:-}"; shift 2 ;;
    --gateway-watchdog-enable)
      GATEWAY_WATCHDOG_ENABLE="1"; shift ;;
    --gateway-watchdog-disable)
      GATEWAY_WATCHDOG_ENABLE="0"; shift ;;
    --gateway-watchdog-interval-sec)
      GATEWAY_WATCHDOG_INTERVAL_SEC="${2:-}"; shift 2 ;;
    --gateway-watchdog-failures)
      GATEWAY_WATCHDOG_FAILURES="${2:-}"; shift 2 ;;
    --gateway-watchdog-cooldown-sec)
      GATEWAY_WATCHDOG_COOLDOWN_SEC="${2:-}"; shift 2 ;;
    --gateway-watchdog-target)
      GATEWAY_WATCHDOG_TARGET="${2:-}"; shift 2 ;;
    --eth-iface)
      ETH_IFACE="${2:-}"; shift 2 ;;
    --eth-route-metric)
      ETH_ROUTE_METRIC="${2:-}"; shift 2 ;;
    --bbb-gateway-enable)
      BBB_GATEWAY_ENABLE="1"; shift ;;
    --bbb-gateway-address)
      BBB_GATEWAY_ADDRESS="${2:-}"; shift 2 ;;
    --bbb-host)
      BBB_HOST="${2:-}"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -n "$PROFILES_FILE" && ( -n "$SSID" || -n "$PSK" ) ]]; then
  echo "Choose either single-profile mode (--ssid/--psk) or --profiles-file, not both." >&2
  exit 1
fi

if [[ -z "$PROFILES_FILE" && ( -z "$SSID" || -z "$PSK" ) ]]; then
  echo "Provide either --profiles-file or both --ssid and --psk." >&2
  usage
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root (use sudo)." >&2
  exit 1
fi

WIFI_POWER_SAVE="$(printf '%s' "$WIFI_POWER_SAVE" | tr '[:upper:]' '[:lower:]')"
if [[ "$WIFI_POWER_SAVE" != "on" && "$WIFI_POWER_SAVE" != "off" ]]; then
  echo "--wifi-power-save must be 'on' or 'off'." >&2
  exit 1
fi
if [[ ! "$GATEWAY_WATCHDOG_INTERVAL_SEC" =~ ^[0-9]+$ || "$GATEWAY_WATCHDOG_INTERVAL_SEC" -lt 5 ]]; then
  echo "--gateway-watchdog-interval-sec must be >= 5." >&2
  exit 1
fi
if [[ ! "$GATEWAY_WATCHDOG_FAILURES" =~ ^[0-9]+$ || "$GATEWAY_WATCHDOG_FAILURES" -lt 1 ]]; then
  echo "--gateway-watchdog-failures must be >= 1." >&2
  exit 1
fi
if [[ ! "$GATEWAY_WATCHDOG_COOLDOWN_SEC" =~ ^[0-9]+$ || "$GATEWAY_WATCHDOG_COOLDOWN_SEC" -lt 10 ]]; then
  echo "--gateway-watchdog-cooldown-sec must be >= 10." >&2
  exit 1
fi

require_cmd wpa_passphrase
require_cmd systemctl
require_cmd ip
require_cmd ping
require_cmd hostnamectl
require_cmd networkctl
require_cmd install
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "Interface '$IFACE' not found." >&2
  exit 1
fi

if [[ -n "$PROFILES_FILE" ]]; then
  load_profiles_from_file "$PROFILES_FILE"
else
  add_profile "$PROFILE_ID" "$SSID" "$PSK" "$PROFILE_PRIORITY" "$FALLBACK_ADDRESS"
fi

if [[ ${#PROFILE_IDS[@]} -eq 0 ]]; then
  echo "No hotspot profiles were loaded." >&2
  exit 1
fi

WPA_DIR="/etc/wpa_supplicant"
NET_DIR="/etc/systemd/network"
AVAHI_DIR="/etc/avahi/services"
DEFAULT_DIR="/etc/default"
BEAGLEY_DIR="/etc/beagley"
SYSTEMD_DIR="/etc/systemd/system"
LIBEXEC_DIR="/usr/local/libexec"
SYSCTL_DIR="/etc/sysctl.d"
WPA_FILE="$WPA_DIR/wpa_supplicant-${IFACE}.conf"
NET_FILE="$NET_DIR/${IFACE}.network"
ETH_NET_FILE="$NET_DIR/${ETH_IFACE}.network"
AVAHI_SSH_FILE="$AVAHI_DIR/ssh.service"
RECONCILE_DEFAULT_FILE="$DEFAULT_DIR/beagley-hotspot-reconcile"
RECONCILE_SCRIPT_FILE="$LIBEXEC_DIR/beagley-hotspot-reconcile"
RECONCILE_SERVICE_FILE="$SYSTEMD_DIR/beagley-hotspot-reconcile.service"
RECONCILE_TIMER_FILE="$SYSTEMD_DIR/beagley-hotspot-reconcile.timer"
WATCHDOG_DEFAULT_FILE="$DEFAULT_DIR/beagley-hotspot-watchdog"
WATCHDOG_SCRIPT_FILE="$LIBEXEC_DIR/beagley-hotspot-watchdog"
WATCHDOG_SERVICE_FILE="$SYSTEMD_DIR/beagley-hotspot-watchdog.service"
WATCHDOG_TIMER_FILE="$SYSTEMD_DIR/beagley-hotspot-watchdog.timer"
BBB_GATEWAY_SYSCTL_FILE="$SYSCTL_DIR/90-beagley-bbb-gateway.conf"
BBB_GATEWAY_NFT_FILE="$BEAGLEY_DIR/bbb-gateway.nft"
BBB_GATEWAY_SERVICE_FILE="$SYSTEMD_DIR/beagley-bbb-gateway.service"
ARP_FLUX_SYSCTL_FILE="$SYSCTL_DIR/90-beagley-arp-flux.conf"

mkdir -p "$WPA_DIR" "$NET_DIR" "$DEFAULT_DIR" "$BEAGLEY_DIR" "$LIBEXEC_DIR" "$SYSCTL_DIR"
mkdir -p /var/volatile/tmp
chmod 1777 /var/volatile /var/volatile/tmp 2>/dev/null || true
install_arp_flux_sysctl "$ARP_FLUX_SYSCTL_FILE" "$ETH_IFACE" "$IFACE"

if [[ -f "$WPA_FILE" ]]; then
  cp "$WPA_FILE" "${WPA_FILE}.bak.$(timestamp)"
fi
if [[ -f "$NET_FILE" ]]; then
  cp "$NET_FILE" "${NET_FILE}.bak.$(timestamp)"
fi
if [[ -n "$ETH_IFACE" && -f "$ETH_NET_FILE" ]]; then
  cp "$ETH_NET_FILE" "${ETH_NET_FILE}.bak.$(timestamp)"
fi

{
  cat <<EOF
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=${COUNTRY}
ap_scan=1
fast_reauth=1
disable_scan_offload=1

EOF

  for index in "${!PROFILE_IDS[@]}"; do
    render_wpa_network_block \
      "${PROFILE_IDS[$index]}" \
      "${PROFILE_SSIDS[$index]}" \
      "${PROFILE_PSKS[$index]}" \
      "${PROFILE_PRIORITIES[$index]}" \
      "${PROFILE_FALLBACKS[$index]}"
  done
} >"$WPA_FILE"

chmod 600 "$WPA_FILE"

write_wlan_network_file "$NET_FILE" "$IFACE" "$ROUTE_METRIC" ""

if [[ -n "$ETH_IFACE" ]] && ip link show "$ETH_IFACE" >/dev/null 2>&1; then
if [[ "$BBB_GATEWAY_ENABLE" == "1" ]]; then
cat >"$ETH_NET_FILE" <<EOF
[Match]
Name=${ETH_IFACE}
Type=ether

[Link]
RequiredForOnline=no

[Network]
ConfigureWithoutCarrier=yes
Address=${BBB_GATEWAY_ADDRESS}
IPForward=ipv4
IPv6AcceptRA=no
EOF
else
cat >"$ETH_NET_FILE" <<EOF
[Match]
Name=${ETH_IFACE}
Type=ether

[Link]
RequiredForOnline=no

[Network]
DHCP=ipv4

[DHCPv4]
RouteMetric=${ETH_ROUTE_METRIC}
EOF
fi
fi

if [[ "$BBB_GATEWAY_ENABLE" == "1" ]]; then
  require_cmd nft
  BBB_LAN_CIDR="$(cidr_network "$BBB_GATEWAY_ADDRESS")"
  cat >"$BBB_GATEWAY_SYSCTL_FILE" <<EOF
net.ipv4.ip_forward=1
EOF
  sysctl -p "$BBB_GATEWAY_SYSCTL_FILE" >/dev/null || true
  install_bbb_gateway_nat_stack \
    "$BBB_GATEWAY_NFT_FILE" \
    "$BBB_GATEWAY_SERVICE_FILE" \
    "$BBB_LAN_CIDR" \
    "$ETH_IFACE" \
    "$IFACE"
else
  rm -f "$BBB_GATEWAY_SYSCTL_FILE"
  rm -f "$BBB_GATEWAY_NFT_FILE"
  rm -f "$BBB_GATEWAY_SERVICE_FILE"
fi

hostnamectl set-hostname "$HOST_NAME"
if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
  sed -i "s/^127\\.0\\.1\\.1[[:space:]].*/127.0.1.1 ${HOST_NAME}/" /etc/hosts
else
  printf '127.0.1.1 %s\n' "$HOST_NAME" >> /etc/hosts
fi

if has_unit_file avahi-daemon.service; then
  mkdir -p "$AVAHI_DIR"
  cat >"$AVAHI_SSH_FILE" <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_ssh._tcp</type>
    <port>22</port>
  </service>
</service-group>
EOF
fi

mkdir -p "/etc/systemd/system/wpa_supplicant@${IFACE}.service.d"
cat >"/etc/systemd/system/wpa_supplicant@${IFACE}.service.d/restart.conf" <<EOF
[Service]
Restart=always
RestartSec=3
EOF

install_reconcile_stack \
  "$RECONCILE_DEFAULT_FILE" \
  "$RECONCILE_SERVICE_FILE" \
  "$RECONCILE_TIMER_FILE" \
  "$RECONCILE_SCRIPT_FILE" \
  "$IFACE" \
  "$WPA_FILE" \
  "$WIFI_POWER_SAVE"

if [[ "$GATEWAY_WATCHDOG_ENABLE" == "1" ]]; then
  install_gateway_watchdog_stack \
    "$WATCHDOG_DEFAULT_FILE" \
    "$WATCHDOG_SERVICE_FILE" \
    "$WATCHDOG_TIMER_FILE" \
    "$WATCHDOG_SCRIPT_FILE" \
    "$IFACE" \
    "$GATEWAY_WATCHDOG_INTERVAL_SEC" \
    "$GATEWAY_WATCHDOG_FAILURES" \
    "$GATEWAY_WATCHDOG_COOLDOWN_SEC" \
    "$GATEWAY_WATCHDOG_TARGET"
else
  rm -f "$WATCHDOG_DEFAULT_FILE" "$WATCHDOG_SCRIPT_FILE" "$WATCHDOG_SERVICE_FILE" "$WATCHDOG_TIMER_FILE"
fi

systemctl daemon-reload
systemctl enable ssh
systemctl enable "wpa_supplicant@${IFACE}.service"
systemctl enable beagley-hotspot-reconcile.timer
if [[ "$GATEWAY_WATCHDOG_ENABLE" == "1" ]]; then
  systemctl enable beagley-hotspot-watchdog.timer
fi
if [[ "$BBB_GATEWAY_ENABLE" == "1" ]]; then
  systemctl enable beagley-bbb-gateway.service
fi
if has_unit_file avahi-daemon.service; then
  systemctl enable avahi-daemon
  systemctl restart avahi-daemon
fi
systemctl restart "wpa_supplicant@${IFACE}.service"
networkctl reload || true
networkctl reconfigure "$IFACE" || true
systemctl restart beagley-hotspot-reconcile.timer
if [[ "$GATEWAY_WATCHDOG_ENABLE" == "1" ]]; then
  systemctl restart beagley-hotspot-watchdog.timer
fi
if [[ "$BBB_GATEWAY_ENABLE" == "1" ]]; then
  systemctl restart beagley-bbb-gateway.service
fi

sleep 3

echo
echo "=== ${IFACE} link ==="
ip -br link show "$IFACE" || true
echo
echo "=== ${IFACE} addresses ==="
ip -br a show "$IFACE" || true
if [[ -n "$ETH_IFACE" ]] && ip link show "$ETH_IFACE" >/dev/null 2>&1; then
  echo
  echo "=== ${ETH_IFACE} addresses ==="
  ip -br a show "$ETH_IFACE" || true
fi
echo
echo "=== routes ==="
ip route || true
if [[ "$BBB_GATEWAY_ENABLE" == "1" ]]; then
echo
echo "=== BBB gateway mode ==="
printf 'BBB link iface: %s\n' "$ETH_IFACE"
printf 'Beagley BBB-side address: %s\n' "$BBB_GATEWAY_ADDRESS"
printf 'BBB expected address: %s\n' "$BBB_HOST"
sysctl net.ipv4.ip_forward || true
fi
echo
echo "=== saved hotspot profiles ==="
for index in "${!PROFILE_IDS[@]}"; do
  printf '%s\tpriority=%s\tssid=%s' \
    "${PROFILE_IDS[$index]}" \
    "${PROFILE_PRIORITIES[$index]}" \
    "${PROFILE_SSIDS[$index]}"
  if [[ -n "${PROFILE_FALLBACKS[$index]}" ]]; then
    printf '\tfallback=%s' "${PROFILE_FALLBACKS[$index]}"
  fi
  printf '\n'
done
echo
echo "=== systemd status ==="
systemctl --no-pager --full status "wpa_supplicant@${IFACE}.service" | sed -n '1,25p' || true
echo
echo "=== hotspot reconcile ==="
systemctl --no-pager --full status beagley-hotspot-reconcile.service | sed -n '1,20p' || true
if [[ "$GATEWAY_WATCHDOG_ENABLE" == "1" ]]; then
echo
echo "=== hotspot watchdog ==="
systemctl --no-pager --full status beagley-hotspot-watchdog.service | sed -n '1,20p' || true
fi
echo
echo "=== host discovery ==="
hostnamectl --static || true
grep '^127\.0\.1\.1[[:space:]]' /etc/hosts || true
if has_unit_file avahi-daemon.service; then
  systemctl is-active avahi-daemon || true
  echo "Try: ssh debian@${HOST_NAME}.local"
fi
echo
echo "=== reachability checks ==="
ping -c 2 -W 1 "$BBB_HOST" || true
ping -c 2 -W 1 8.8.8.8 || true

echo
echo "USB recovery path remains on 192.168.7.2 (usb0) if the hotspot or ethernet path is unavailable."
echo
echo "Wi-Fi setup complete for ${IFACE}."
