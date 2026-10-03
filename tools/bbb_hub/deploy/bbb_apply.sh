#!/usr/bin/env bash
# Runs ON THE BBB as root (via: sudo bash bbb_apply.sh <step> <release-sha>).
# Written by Hardware Integration. Read it before you type the sudo password.
# Every step: backs up what it changes, verifies, and rolls itself back on failure.
#   stage1   switch hub to the release dir, install repo unit (Type=notify), restart hub, health check
#   stage2   point systemd-timesyncd at the BeagleY (10.24.0.46), wait for sync, restart hub, health check
#   stage3a  add BB-UART4 overlay to /boot/uEnv.txt and reboot
#   stage3b  after reboot: check /dev/ttyS4, set VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4, restart hub, health check
#   rollback1|rollback2|rollback3   undo that stage from the newest backup (3 reboots the board)
set -u
STEP="${1:-}"; SHA="${2:-}"
UNIT=/etc/systemd/system/bbb-hardware-gps.service
ENVF=/etc/default/bbb-hardware-gps
UENV=/boot/uEnv.txt
REL=/home/debian/releases
CUR=$REL/current
TIMESYNCD_DROPIN=/etc/systemd/timesyncd.conf.d/beagley.conf
BEAGLEY_NTP=10.24.0.46
WS=ws://127.0.0.1:8765
TS="$(date +%Y%m%d-%H%M%S)"   # board clock is wrong; only used to make names unique

say() { echo "[bbb_apply] $*"; }
die() { echo "[bbb_apply] FAIL: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run with sudo"

health() {  # $1 = extra flags
  sudo -u debian python3 "$CUR/tools/bbb_hub/check_hub_health.py" "$WS" $1
}
wait_active() {  # up to 45 s for the hub to be active (Type=notify -> READY=1)
  for _ in $(seq 1 45); do
    [ "$(systemctl is-active bbb-hardware-gps)" = active ] && return 0
    sleep 1
  done
  return 1
}
latest_backup() { ls -1d /home/debian/rollback/"$1"-* 2>/dev/null | tail -1; }

restore_unit_env() {  # $1 = backup dir
  [ -f "$1/bbb-hardware-gps.service" ] && cp -a "$1/bbb-hardware-gps.service" "$UNIT"
  [ -f "$1/bbb-hardware-gps" ] && cp -a "$1/bbb-hardware-gps" "$ENVF"
  systemctl daemon-reload
  systemctl restart bbb-hardware-gps
}

case "$STEP" in
stage1)
  [ -n "$SHA" ] && [ -d "$REL/$SHA/tools/bbb_hub" ] || die "release $REL/$SHA not found"
  B=/home/debian/rollback/stage1-$TS; mkdir -p "$B"
  cp -a "$UNIT" "$ENVF" "$B"/ || die "backup failed"
  readlink "$CUR" > "$B/previous_current_link" 2>/dev/null || true
  say "backup in $B (old code stays untouched at /home/debian/projects/beagley-cluster)"
  mkdir -p /var/lib/beagley-cluster/baselines /var/log/beagley-cluster/faults
  chown -R debian:debian /var/lib/beagley-cluster /var/log/beagley-cluster
  ln -sfn "$REL/$SHA" "$CUR"
  # code is in place first; only now install the Type=notify unit, pointed at the release dir
  sed "s#/home/debian/projects/beagley-cluster/tools/bbb_hub#$CUR/tools/bbb_hub#g" \
      "$REL/$SHA/tools/bbb_hub/bbb-hardware-gps.service" > "$UNIT.new" || die "unit render failed"
  mv "$UNIT.new" "$UNIT"
  systemctl daemon-reload
  say "restarting bbb-hardware-gps (gauges blank for a few seconds)"
  systemctl restart bbb-hardware-gps
  if wait_active && sleep 5 && health --require-gps; then
    say "STAGE 1 OK. Rollback later with: sudo bash $REL/bbb_apply.sh rollback1"
  else
    say "health check failed -> rolling back automatically"
    restore_unit_env "$B"
    if wait_active; then say "ROLLED BACK: old unit restored, hub active. Check: journalctl -u bbb-hardware-gps -n 50 --no-pager"
    else say "ROLLBACK ALSO FAILED. Hub not active. Backup is in $B and the Mac snapshot has the originals."; fi
    exit 1
  fi
  ;;
rollback1)
  B="$(latest_backup stage1)"; [ -n "$B" ] || die "no stage1 backup found"
  say "restoring unit and env from $B"
  restore_unit_env "$B"; wait_active && say "old unit restored, hub active" || die "hub not active after rollback"
  ;;
stage2)
  command -v timedatectl >/dev/null && systemctl list-unit-files | grep -q '^systemd-timesyncd' || die "systemd-timesyncd not available on the BBB"
  B=/home/debian/rollback/stage2-$TS; mkdir -p "$B"
  [ -f "$TIMESYNCD_DROPIN" ] && cp -a "$TIMESYNCD_DROPIN" "$B"/
  date > "$B/clock_before.txt"
  mkdir -p "$(dirname "$TIMESYNCD_DROPIN")"
  printf '[Time]\nNTP=%s\nFallbackNTP=\n' "$BEAGLEY_NTP" > "$TIMESYNCD_DROPIN"
  systemctl enable --now systemd-timesyncd >/dev/null 2>&1
  systemctl restart systemd-timesyncd
  say "waiting up to 90 s for time from $BEAGLEY_NTP"
  OK=0
  for _ in $(seq 1 90); do
    [ "$(timedatectl show -p NTPSynchronized --value)" = yes ] && { OK=1; break; }
    sleep 1
  done
  timedatectl timesync-status 2>&1 | head -12
  if [ "$OK" = 1 ]; then
    say "clock synchronized: $(date). Restarting hub so it starts from the corrected clock."
    systemctl restart bbb-hardware-gps
    if wait_active && sleep 5 && health --require-gps; then say "STAGE 2 OK"; else die "hub unhealthy after clock step; run: sudo bash $REL/bbb_apply.sh rollback2 (and check the hub)"; fi
  else
    say "no sync from $BEAGLEY_NTP (BeagleY NTP server not running, or the BeagleY has no good time). Rolling back the drop-in."
    rm -f "$TIMESYNCD_DROPIN"; [ -f "$B/beagley.conf" ] && cp -a "$B/beagley.conf" "$TIMESYNCD_DROPIN"
    systemctl restart systemd-timesyncd
    exit 1
  fi
  ;;
rollback2)
  B="$(latest_backup stage2)"; rm -f "$TIMESYNCD_DROPIN"
  [ -n "$B" ] && [ -f "$B/beagley.conf" ] && cp -a "$B/beagley.conf" "$TIMESYNCD_DROPIN"
  systemctl restart systemd-timesyncd; say "timesyncd drop-in removed"
  ;;
stage3a)
  [ -f /lib/firmware/BB-UART4-00A0.dtbo ] || ls /boot/dtbs/*/overlays/BB-UART4-00A0.dtbo >/dev/null 2>&1 || die "BB-UART4-00A0.dtbo not found"
  grep -q '^uboot_overlay_addr6=' "$UENV" && die "uboot_overlay_addr6 already set in $UENV; not touching it"
  grep -q '^enable_uboot_overlays=1' "$UENV" || die "enable_uboot_overlays=1 missing in $UENV"
  B=/home/debian/rollback/stage3-$TS; mkdir -p "$B"
  cp -a "$UENV" "$B/uEnv.txt" && cp -a "$ENVF" "$B/bbb-hardware-gps" || die "backup failed"
  cp -a "$UENV" "$UENV.bak-before-uart4" 2>/dev/null
  printf '\n# Hardware Integration: UART4 (P9_11 RX, P9_13 TX) for the UNO serial input, replaces damaged UART2 RX\nuboot_overlay_addr6=BB-UART4-00A0.dtbo\n' >> "$UENV"
  say "uEnv.txt now:"; grep '^uboot_overlay' "$UENV"
  say "rebooting in 5 s. After it is back, run stage 3 part B."
  sleep 5; systemctl reboot
  ;;
stage3b)
  [ -e /dev/ttyS4 ] || { dmesg | grep -i 'ttyS\|uart' | tail -15; die "/dev/ttyS4 missing after reboot. Roll back with: sudo bash $REL/bbb_apply.sh rollback3"; }
  say "dmesg:"; dmesg | grep -i ttyS | tail -6
  B=/home/debian/rollback/stage3b-$TS; mkdir -p "$B"; cp -a "$ENVF" "$B/bbb-hardware-gps" || die "backup failed"
  if grep -q '^VEHICLE_INPUT_SERIAL_DEVICE=' "$ENVF"; then sed -i 's#^VEHICLE_INPUT_SERIAL_DEVICE=.*#VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4#' "$ENVF"; else echo 'VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4' >> "$ENVF"; fi
  systemctl restart bbb-hardware-gps
  # UNO is bench-only/disconnected, so serial is NOT required to be live; GPS must be.
  if wait_active && sleep 5 && health --require-gps; then say "STAGE 3 OK: hub reads /dev/ttyS4 (no frames until the UNO is wired to P9_11)"
  else say "unhealthy -> restoring env"; cp -a "$B/bbb-hardware-gps" "$ENVF"; systemctl restart bbb-hardware-gps; wait_active && say "env restored, hub active"; exit 1; fi
  ;;
rollback3)
  B="$(latest_backup stage3)"; [ -n "$B" ] && [ -f "$B/uEnv.txt" ] || die "no stage3 backup"
  cp -a "$B/uEnv.txt" "$UENV"; cp -a "$B/bbb-hardware-gps" "$ENVF"
  say "uEnv.txt and env restored from $B. Rebooting in 5 s."; sleep 5; systemctl reboot
  ;;
*) die "usage: sudo bash bbb_apply.sh stage1|stage2|stage3a|stage3b|rollback1|rollback2|rollback3 [release-sha]" ;;
esac
