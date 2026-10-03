#!/usr/bin/env bash
# Runs ON THE BBB as root (via: sudo bash bbb_apply.sh <step> <release-sha>).
# Written by Hardware Integration. Read it before you type the sudo password.
# Every step: backs up what it changes, verifies, and rolls itself back on failure.
#   stage1   switch hub to the release dir, install repo unit (Type=notify), restart hub, health check
#   stage2   install + enable bbb-gps-clock.service (GPS-disciplined clock, runs as debian with CAP_SYS_TIME only)
#            optional 2nd arg: the Mac's UTC epoch, printed as a sanity comparison
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
CLK_UNIT=/etc/systemd/system/bbb-gps-clock.service
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
  MAC_EPOCH="${SHA:-}"   # for stage2 the 2nd argument is the Mac's UTC epoch (optional, sanity print only)
  case "$MAC_EPOCH" in ''|*[!0-9]*) MAC_EPOCH="" ;; esac
  [ -f "$CUR/tools/bbb_hub/gps_clock.py" ] && [ -f "$CUR/tools/bbb_hub/bbb-gps-clock.service" ] \
    || die "$CUR does not contain gps_clock.py / bbb-gps-clock.service: apply stage1 with a release that includes them first"
  B=/home/debian/rollback/stage2-$TS; mkdir -p "$B"
  { echo "clock_before: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "unit_file_present: $([ -f "$CLK_UNIT" ] && echo yes || echo no)"
    echo "enabled_before: $(systemctl is-enabled bbb-gps-clock 2>&1)"
    echo "active_before: $(systemctl is-active bbb-gps-clock 2>&1)"
    echo "timesyncd: $(systemctl is-enabled systemd-timesyncd 2>&1) / $(systemctl is-active systemd-timesyncd 2>&1)"
  } > "$B/state.txt"
  [ -f "$CLK_UNIT" ] && cp -a "$CLK_UNIT" "$B/bbb-gps-clock.service"
  say "state recorded in $B/state.txt"
  [ -n "$MAC_EPOCH" ] && say "Mac UTC epoch at launch: $MAC_EPOCH; BBB now: $(date -u +%s) (difference includes the time you took to type the password)"
  sed "s#/home/debian/projects/beagley-cluster/tools/bbb_hub#$CUR/tools/bbb_hub#g" \
      "$CUR/tools/bbb_hub/bbb-gps-clock.service" > "$CLK_UNIT.new" || die "unit render failed"
  mv "$CLK_UNIT.new" "$CLK_UNIT"
  systemctl daemon-reload
  STEPS_BEFORE="$(journalctl -u bbb-gps-clock -b --no-pager -o cat 2>/dev/null | grep -c 'stepped clock')"
  OKS_BEFORE="$(journalctl -u bbb-gps-clock -b --no-pager -o cat 2>/dev/null | grep -c 'no step')"
  systemctl enable --now bbb-gps-clock || { systemctl disable --now bbb-gps-clock >/dev/null 2>&1; rm -f "$CLK_UNIT"; systemctl daemon-reload; die "could not enable bbb-gps-clock; unit removed again"; }
  say "bbb-gps-clock enabled and started; waiting up to 120 s for a GPS time fix (journalctl -u bbb-gps-clock)"
  RESULT=""
  for _ in $(seq 1 120); do
    if [ "$(systemctl is-active bbb-gps-clock)" = failed ]; then RESULT=failed; break; fi
    LOG="$(journalctl -u bbb-gps-clock -b --no-pager -o cat 2>/dev/null)"
    if [ "$(printf '%s\n' "$LOG" | grep -c 'stepped clock')" -gt "$STEPS_BEFORE" ]; then RESULT=stepped; break; fi
    if [ "$(printf '%s\n' "$LOG" | grep -c 'no step')" -gt "$OKS_BEFORE" ]; then RESULT=correct; break; fi
    sleep 1
  done
  say "recent bbb-gps-clock log:"; journalctl -u bbb-gps-clock -n 8 --no-pager -o cat 2>&1 | sed 's/^/    /'
  say "BBB clock now: $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
  [ -n "$MAC_EPOCH" ] && say "Mac UTC epoch at launch was $MAC_EPOCH; BBB epoch now $(date -u +%s)"
  case "$RESULT" in
  stepped) say "STAGE 2 OK: the clock was set from GPS time. The hub keeps running; restart it (or reboot) later if you want its baseline files stamped with the corrected date." ;;
  correct) say "STAGE 2 OK: the clock already matches GPS time (no step needed)." ;;
  failed)
    systemctl disable --now bbb-gps-clock >/dev/null 2>&1; rm -f "$CLK_UNIT"; systemctl daemon-reload
    die "bbb-gps-clock entered the failed state; unit removed again (see journalctl -u bbb-gps-clock -n 30 --no-pager)" ;;
  *)
    say "STAGE 2 INSTALLED. No GPS time yet (no fix, e.g. indoors, or the hub is not up). This is not an error:"
    say "the service keeps running and sets the clock as soon as a fix arrives. Check later with:"
    say "    date; journalctl -u bbb-gps-clock -n 20 --no-pager"
    systemctl is-active bbb-gps-clock >/dev/null || die "bbb-gps-clock is not active; see journalctl -u bbb-gps-clock -n 30 --no-pager" ;;
  esac
  ;;
rollback2)
  systemctl disable --now bbb-gps-clock 2>&1 | sed 's/^/    /'
  rm -f "$CLK_UNIT"
  systemctl daemon-reload
  say "bbb-gps-clock disabled and removed (the clock keeps whatever time it has; it is not reverted)"
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
