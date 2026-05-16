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
: "${SCANNING_FAIL_THRESHOLD:=0}"
: "${EMPTY_SCAN_RESET_THRESHOLD:=4}"
: "${EMPTY_SCAN_RESET_COOLDOWN_SEC:=300}"
: "${SCAN_SETTLE_SEC:=8}"
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

count_visible_bss() {
  if ! command -v wpa_cli >/dev/null 2>&1; then
    echo unknown
    return
  fi

  wpa_cli -i "$IFACE" scan >/dev/null 2>&1 || true
  sleep "$SCAN_SETTLE_SEC"
  wpa_cli -i "$IFACE" scan_results 2>/dev/null | awk '
    NR > 1 && $1 ~ /^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$/ { count++ }
    END { print count + 0 }
  '
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

  if is_enabled "$DRIVER_RESET_ENABLE"; then
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
      $1 == "wpa_state" { print $2; exit }
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
    printf '0 %s healthy\n' "$last_restart" >"$STATE_FILE"
    exit 0
  fi
  healthy=0
  reason="probe-failed:${target}"
fi

if [[ "$healthy" == "1" ]]; then
  printf '0 %s healthy\n' "$last_restart" >"$STATE_FILE"
  exit 0
fi

if [[ "$last_reason" != "$reason" ]]; then
  count=0
fi

if [[ "$reason" == "not-associated" ]] && ! is_enabled "$RESET_WHILE_SCANNING"; then
  visible_bss="$(count_visible_bss)"
  count=$((count + 1))
  if is_enabled "$FLUSH_STALE_ADDRESS_WHILE_SCANNING"; then
    flush_stale_wifi_address
  fi
  if [[ "$visible_bss" =~ ^[0-9]+$ && "$visible_bss" == "0" && "$EMPTY_SCAN_RESET_THRESHOLD" =~ ^[0-9]+$ && "$EMPTY_SCAN_RESET_THRESHOLD" -gt 0 ]]; then
    if (( count >= EMPTY_SCAN_RESET_THRESHOLD )); then
      empty_scan_cooldown="$EMPTY_SCAN_RESET_COOLDOWN_SEC"
      if [[ ! "$empty_scan_cooldown" =~ ^[0-9]+$ ]]; then
        empty_scan_cooldown="$COOLDOWN_SEC"
      fi
      if (( now - last_restart >= empty_scan_cooldown )); then
        log "recover iface=${IFACE} reason=${reason} count=${count}/${EMPTY_SCAN_RESET_THRESHOLD} visible_bss=0 wpa_state=${wpa_state:-unknown}; empty scans, resetting radio"
        full_radio_reset
        printf '0 %s reset-empty-scan\n' "$now" >"$STATE_FILE"
        exit 0
      fi
      printf '%s %s %s\n' "$count" "$last_restart" "$reason" >"$STATE_FILE"
      log "cooldown iface=${IFACE} reason=${reason} count=${count}/${EMPTY_SCAN_RESET_THRESHOLD} visible_bss=0 wpa_state=${wpa_state:-unknown}; empty-scan reset deferred"
      exit 0
    fi
    printf '%s %s %s\n' "$count" "$last_restart" "$reason" >"$STATE_FILE"
    log "waiting iface=${IFACE} reason=${reason} count=${count}/${EMPTY_SCAN_RESET_THRESHOLD} visible_bss=0 wpa_state=${wpa_state:-unknown}; empty scans below reset threshold"
    exit 0
  fi
  if (( SCANNING_FAIL_THRESHOLD <= 0 || count < SCANNING_FAIL_THRESHOLD )); then
    printf '%s %s %s\n' "$count" "$last_restart" "$reason" >"$STATE_FILE"
    log "waiting iface=${IFACE} reason=${reason} count=${count} visible_bss=${visible_bss} wpa_state=${wpa_state:-unknown}; leaving supplicant scanning"
    exit 0
  fi
  if (( now - last_restart < COOLDOWN_SEC )); then
    printf '%s %s %s\n' "$count" "$last_restart" "$reason" >"$STATE_FILE"
    log "cooldown iface=${IFACE} reason=${reason} count=${count}/${SCANNING_FAIL_THRESHOLD} visible_bss=${visible_bss}; reset deferred"
    exit 0
  fi
  log "recover iface=${IFACE} reason=${reason} count=${count}/${SCANNING_FAIL_THRESHOLD} visible_bss=${visible_bss}; sustained scanning, resetting radio"
  full_radio_reset
  printf '0 %s reset-scanning\n' "$now" >"$STATE_FILE"
  exit 0
fi

count=$((count + 1))
if (( count >= FAIL_THRESHOLD )); then
  if (( now - last_restart >= COOLDOWN_SEC )); then
    if [[ "$reason" == "no-ipv4-lease" || "$reason" == "no-default-gateway" || "$reason" == probe-failed:* ]]; then
      log "refresh iface=${IFACE} reason=${reason} count=${count}; renewing dhcp"
      try_dhcp_refresh
      if has_ipv4 && has_default_route; then
        printf '0 %s recovered-dhcp\n' "$last_restart" >"$STATE_FILE"
        exit 0
      fi
    fi

    log "recover iface=${IFACE} reason=${reason} count=${count}; resetting radio"
    full_radio_reset
    printf '0 %s %s\n' "$now" "$reason" >"$STATE_FILE"
    exit 0
  fi
fi

printf '%s %s %s\n' "$count" "$last_restart" "$reason" >"$STATE_FILE"
log "unhealthy iface=${IFACE} reason=${reason} count=${count}"
