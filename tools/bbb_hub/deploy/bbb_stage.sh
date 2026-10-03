#!/usr/bin/env bash
# Runs on the MAC. Usage:  bash bbb_stage.sh <stage1|stage2|stage3|rollback1|rollback2|rollback3> [beagley-ip]
# Does every read-only check and dry run itself, then asks you to type "yes" and runs the one
# privileged step with ssh -t, so YOU type the BBB `debian` sudo password. Nothing bypasses sudo.
# Keep this script, bbb_apply.sh and release-<sha>.tgz in the same folder.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KEY="$HOME/.ssh/beagley_bbb"
STAGE="${1:-}"; IP="${2:-}"
TGZ="$(ls "$HERE"/release-*.tgz 2>/dev/null | head -1)"; SHA="$(basename "${TGZ:-release-none.tgz}" .tgz | sed 's/^release-//')"
REL=/home/debian/releases

find_ip() {
  [ -n "$IP" ] && return 0
  dns-sd -G v4 beagley-ai.local > /tmp/dnssd.$$ 2>&1 & local p=$!; sleep 4; kill $p 2>/dev/null; wait $p 2>/dev/null
  IP="$(awk '/ Add /{print $6}' /tmp/dnssd.$$ | head -1)"; rm -f /tmp/dnssd.$$
  [ -n "$IP" ] || { echo "Cannot find the BeagleY (dns-sd). Pass its IP: bash bbb_stage.sh $STAGE <ip>"; exit 1; }
}
SSHO=(-o BatchMode=yes -o ConnectTimeout=8 -i "$KEY")
bssh()  { ssh "${SSHO[@]}" -J "root@$IP" debian@10.24.0.7 "$@"; }          # no password needed
bsshT() { ssh -t "${SSHO[@]}" -J "root@$IP" debian@10.24.0.7 "$@"; }        # interactive: sudo asks YOU
ysh()   { ssh "${SSHO[@]}" "root@$IP" "$@"; }                               # BeagleY
confirm() { read -r -p "$1 Type yes to continue: " a; [ "$a" = yes ] || { echo "Stopped. Nothing changed."; exit 0; }; }

[ -n "$STAGE" ] || { sed -n 2,5p "$0"; exit 1; }
find_ip
echo "BeagleY at $IP"
bssh 'echo "BBB reachable: $(hostname), hub=$(systemctl is-active bbb-hardware-gps)"' || { echo "Cannot reach the BBB through the BeagleY. Nothing changed."; exit 1; }

upload_release() {
  [ -f "$TGZ" ] || { echo "release-*.tgz not found next to this script"; exit 1; }
  bssh "mkdir -p $REL" && scp "${SSHO[@]}" -J "root@$IP" "$TGZ" "$HERE/bbb_apply.sh" "debian@10.24.0.7:$REL/" >/dev/null || { echo "upload failed"; exit 1; }
  LOCAL_SUM="$(shasum -a 256 "$TGZ" | cut -d' ' -f1)"
  bssh "cd $REL && echo '$LOCAL_SUM  release-$SHA.tgz' | sha256sum -c - && { [ -d $SHA ] || tar xzf release-$SHA.tgz; } && ls $SHA/tools/bbb_hub | wc -l" || { echo "checksum/extract failed"; exit 1; }
}

case "$STAGE" in
stage1)
  echo "== Stage 1: hub update to $SHA (read-only checks + dry run first) =="
  upload_release
  echo "-- dry run: new hub on spare port 8799, no GPS/serial devices, temp dirs (live hub untouched)"
  bssh "cd $REL/$SHA/tools/bbb_hub && D=\$(mktemp -d) && \
    ( BBB_HUB_PORT=8799 BBB_HUB_HOST=127.0.0.1 BBB_GPS_DEVICE=/dev/nonexistent VEHICLE_INPUT_SERIAL_DEVICE= \
      FAULT_RECORDER_DIR=\$D/f VEHICLE_BASELINE_PATH=\$D/b.json VEHICLE_TRANSITION_BASELINE_PATH=\$D/t.json \
      PYTHONDONTWRITEBYTECODE=1 python3 vehicle_hub_prod.py > \$D/log 2>&1 & echo \$! > \$D/pid ); \
    sleep 8; python3 check_hub_health.py ws://127.0.0.1:8799; rc=\$?; kill \$(cat \$D/pid) 2>/dev/null; sleep 1; \
    tail -5 \$D/log; rm -rf \$D; exit \$rc" || { echo "DRY RUN FAILED. Nothing live was changed. Send the output above to Cluster Lead."; exit 1; }
  echo "Dry run passed. Live hub is still the old one."
  confirm "Next: switch the live hub to the new code (gauges blank a few seconds; auto-rollback if unhealthy)."
  bsshT "sudo bash $REL/bbb_apply.sh stage1 $SHA"
  echo "-- post check"; bssh "python3 $REL/current/tools/bbb_hub/check_hub_health.py ws://127.0.0.1:8765 --require-gps"
  ;;
stage2)
  echo "== Stage 2: clock fix, option A (BeagleY serves time over eth0) =="
  echo "-- checking the BeagleY for chrony (read-only)"
  ysh 'command -v chronyd chronyc; ls /etc/chrony.conf /etc/chrony/chrony.conf 2>&1; date; timedatectl 2>&1 | grep -i "synchronized\|NTP"; ss -lun 2>/dev/null | grep ":123 " || echo "nothing listening on UDP 123"'
  if ! ysh 'command -v chronyd >/dev/null'; then
    echo "chrony is NOT installed on the BeagleY, so option A cannot proceed as planned. Nothing changed. Tell Cluster Lead."; exit 2
  fi
  echo "-- BBB side (read-only)"; bssh 'date; timedatectl 2>&1 | head -6; systemctl list-unit-files | grep -i "timesyncd\|chrony"'
  confirm "Next: (1) on the BeagleY allow NTP for 10.24.0.0/24 in chrony and restart chronyd (backup kept), (2) on the BBB point timesyncd at 10.24.0.46 and restart the hub."
  CF="$(ysh 'ls /etc/chrony.conf /etc/chrony/chrony.conf 2>/dev/null | head -1')"
  ysh "cp -a $CF $CF.bak-hwint-\$(date +%s) && grep -q '^allow 10.24.0.0/24' $CF || echo 'allow 10.24.0.0/24' >> $CF; systemctl restart chronyd 2>/dev/null || systemctl restart chrony; sleep 2; chronyc tracking | head -5; chronyc sources 2>&1 | head -6"
  echo "NOTE: if 'Leap status' above is not Normal the BeagleY itself has no good time (offline); the BBB will then not sync."
  scp "${SSHO[@]}" -J "root@$IP" "$HERE/bbb_apply.sh" "debian@10.24.0.7:$REL/" >/dev/null
  bsshT "sudo bash $REL/bbb_apply.sh stage2"
  ;;
stage3)
  echo "== Stage 3: UART4 overlay + BBB reboot + /dev/ttyS4 =="
  echo "-- read-only: current overlays and devices"
  bssh 'grep "^uboot_overlay\|^enable_uboot" /boot/uEnv.txt; ls /lib/firmware/BB-UART4-00A0.dtbo; ls /dev/ttyS*; df -h / | tail -1'
  bssh "[ -d $REL/current/tools/bbb_hub ] || { echo 'Stage 1 has not been applied; do stage1 first.'; exit 1; }" || exit 1
  scp "${SSHO[@]}" -J "root@$IP" "$HERE/bbb_apply.sh" "debian@10.24.0.7:$REL/" >/dev/null
  confirm "Next: add BB-UART4 to /boot/uEnv.txt (backup kept) and REBOOT the BBB (about 1-2 minutes of no hub/GPS data)."
  bsshT "sudo bash $REL/bbb_apply.sh stage3a"
  echo "Waiting for the BBB to come back..."
  sleep 25
  for i in $(seq 1 24); do bssh 'true' 2>/dev/null && break; sleep 5; done
  bssh 'uptime; ls /dev/ttyS*' || { echo "BBB did not come back in about 2.5 minutes. See rollback notes; tell Cluster Lead."; exit 1; }
  echo "BBB is back. Second sudo prompt: finish by pointing the hub at /dev/ttyS4."
  bsshT "sudo bash $REL/bbb_apply.sh stage3b"
  ;;
rollback1|rollback2|rollback3)
  confirm "Rollback ${STAGE#rollback} restores the saved backups ($( [ "$STAGE" = rollback3 ] && echo 'this REBOOTS the BBB')."
  scp "${SSHO[@]}" -J "root@$IP" "$HERE/bbb_apply.sh" "debian@10.24.0.7:$REL/" >/dev/null
  bsshT "sudo bash $REL/bbb_apply.sh $STAGE"
  ;;
*) echo "unknown stage"; exit 1 ;;
esac
