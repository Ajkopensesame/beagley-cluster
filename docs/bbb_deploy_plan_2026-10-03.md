# BBB deploy plan (DRAFT, NOT EXECUTED): hub update, UART4 overlay, GPS clock fix

Written by Hardware Integration from the read-only audit of 2026-10-03. **Nothing here has been run.** Each stage
needs separate approval from Cluster Lead / ThatGuy. Companion docs: `docs/bbb_deploy_rollback.md` (generic procedure),
`docs/bbb_hardware_wiring.md` (pins), `docs/serial_vehicle_input_protocol.md` (UNO line format, PR #11).

## Board facts (VERIFIED read-only, 2026-10-03)

* Access (from the Mac): `ssh -i ~/.ssh/beagley_bbb -J root@<beagley-ip> debian@10.24.0.7`. BeagleY IP is DHCP
  (192.168.1.111 today; `dns-sd -G v4 beagley-ai.local`). `debian` has no passwordless sudo: **every step marked `sudo`
  needs ThatGuy to type the password, or a sudoers rule he approves.**
* Debian 12, kernel 6.12.57-bone42, Python 3.11.2, websockets 10.4, 11 GB free.
* Hub: `bbb-hardware-gps.service` (Type=simple), code in `/home/debian/projects/beagley-cluster/tools/bbb_hub`, **not a git
  checkout and older than the repo** (`vehicle_hub_prod.py` Apr 8, `input_adapters.py` Apr 22).
  Env `/etc/default/bbb-hardware-gps`: GPS `/dev/ttyS1`@115200, UNO `/dev/ttyS2`@115200.
* `/boot/uEnv.txt` overlays enabled: `BB-UART1` (addr4), `BB-UART2` (addr5), PRU. `BB-UART4-00A0.dtbo` and
  `BB-CAN0-00A0.dtbo` exist in `/lib/firmware`. No `can0`, no `can_signals.json`.
* Clock wrong (shows Apr 2026, RTC 2000-01-01, not synchronized).
* **Pre-deploy snapshot taken** (copy only): `~/bbb-snapshots/2026-10-03-pre-deploy/` on the Mac (and a copy in
  `/workspace/bbb-snapshots/2026-10-03-pre-deploy/` on the agent box): `bbb-snapshot.tgz` (tools/bbb_hub,
  `/etc/default/bbb-hardware-gps`, the unit, `/boot/uEnv.txt`), `MANIFEST.sha256`, `board-notes.txt`.

## Stage 0: preconditions (no board change)

1. PR #19 (watchdog/fail-safe/tests) and PR #11 (calibration) merged to the default branch, CI green.
2. Pick the commit `<SHA>`; run `python3 -m pytest tests -q` on it (144+ tests, includes hub integration test).
3. Record baseline health: `python3 tools/bbb_hub/check_hub_health.py ws://10.24.0.7:8765 --require-gps` (from a machine that can reach the BBB,
   e.g. over an `ssh -L` tunnel through the BeagleY).
4. Decide the time of day / car state: hub restart blanks the gauges for about 5-10 s; the BBB reboot in stage 2 for about 1 min.

## Stage 1: hub code update (restart hub only; no reboot)

Approval needed: (b). Rollback unit: the snapshot.

1. On the Mac, build a release tree from the repo at `<SHA>`: `git archive <SHA> tools/bbb_hub tools/schema | tar -x -C /tmp/rel`.
2. Copy to the board **beside** the running code, not over it:
   `scp -r -i ~/.ssh/beagley_bbb -J root@<beagley-ip> /tmp/rel/tools/bbb_hub debian@10.24.0.7:/home/debian/releases/<SHA>/tools/bbb_hub`
   (creates a new dir; the live dir is untouched). Verify checksums against the repo.
3. Dry run, nothing live affected: on the BBB run the new hub on a spare port with the same env but no serial devices that are already open:
   `cd /home/debian/releases/<SHA>/tools/bbb_hub && BBB_HUB_PORT=8799 BBB_GPS_DEVICE=/dev/null VEHICLE_INPUT_SERIAL_DEVICE= python3 vehicle_hub_prod.py`
   then `check_hub_health.py ws://127.0.0.1:8799`, then stop it. (Check the port is free and that /dev/null is accepted as GPS; if not, skip to step 4.)
4. Switch: `sudo ln -sfn /home/debian/releases/<SHA> /home/debian/current`; edit the unit once (`sudo`) so `WorkingDirectory`/`ExecStart` use
   `/home/debian/current/tools/bbb_hub`, install the repo unit (Type=notify, WatchdogSec=15) **after** the code is in place,
   `sudo systemctl daemon-reload && sudo systemctl restart bbb-hardware-gps`.
5. Verify within 60 s: `systemctl is-active bbb-hardware-gps`, `journalctl -u bbb-hardware-gps -n 30 --no-pager` (no traceback; shows `serial vehicle inputs enabled`),
   `check_hub_health.py ... --require-gps`, cluster on BeagleY reconnects.
6. **Rollback (any failure):** restore the saved unit and symlink to the old directory, e.g.
   `sudo cp /home/debian/rollback/bbb-hardware-gps.service /etc/systemd/system/` (put the snapshot copies there in step 0),
   old code stays at `/home/debian/projects/beagley-cluster/tools/bbb_hub` untouched, `sudo systemctl daemon-reload && sudo systemctl restart bbb-hardware-gps`,
   re-run health check. Full restore from the tarball if ever needed: `tar xzf bbb-snapshot.tgz -C /` (as root).

## Stage 2: UART4 for the UNO (needs BBB reboot)

Approval needed: (c). Hardware first: UNO TX -> 1k/2k divider -> **P9_11**, common ground (see wiring doc). P9_22/ttyS2 RX is damaged.

1. Before: `sudo cp -a /boot/uEnv.txt /boot/uEnv.txt.bak-2026-10-03` (the snapshot also has it).
2. Add one line to `/boot/uEnv.txt`: `uboot_overlay_addr6=BB-UART4-00A0.dtbo` (addr4/addr5 are used; check addr6 is free). Leave UART1 (GPS) and UART2 lines as they are.
3. `sudo reboot`. The hub restarts by itself (enabled unit). Gauges are blank for about a minute; GPS/UART1 unchanged.
4. After reboot: `dmesg | grep ttyS` should list a new UART at `48022000`-style address for UART4 (the audit saw only ttyS0/1/2 before), and `config-pin -q P9_11` (if available) shows uart. Loopback check without the UNO: briefly short P9_11 to P9_13 and echo through `/dev/ttyS4` (remove the jumper afterwards).
5. Point the hub at it: set `VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4` in `/etc/default/bbb-hardware-gps` (keep a backup), `sudo systemctl restart bbb-hardware-gps`.
6. Verify with the UNO sending: `check_hub_health.py ... --require-serial`; `python3 tools/bbb_hub/sample_sensor_raw.py` shows `raw` a0/a1; frames count rises in `_health.serialVehicleInputs`.
7. **Rollback:** restore `/boot/uEnv.txt` from the backup, restore env file, `sudo reboot`. (UART2 stays enabled in the original config so the old state returns exactly.)

## Clock fix from GPS time (this section's "Stage 3" is `bbb_stage.sh stage2`; script and doc numbering differ)

Approval needed: (d). Problem: the BBB has no battery-backed RTC (RTC reads 2000-01-01) and its link to the BeagleY has no internet, so it boots with a stale
clock and NTP cannot sync. Wrong time poisons journal, fault-recorder and baseline timestamps.

**Decision (ThatGuy / Cluster Lead): option B, fix the clock from GPS time. No chrony, no new service on the BeagleY.**

| Option | Verdict | Why |
|---|---|---|
| A. BeagleY serves time over eth0 (chrony) | **Impossible** | The BeagleY image has no chrony and no ntpd, no package manager, and only `systemd-timesyncd` (a client, not a server). Even with chrony it would only have true time when online. |
| **B. GPS time on the BBB** | **CHOSEN** | The hub already reads NMEA on `/dev/ttyS1` (gpsd cannot share that port), so the hub publishes RMC-derived UTC as `gps.utcMs`/`gps.utcValid` on its WebSocket and a small helper, `tools/bbb_hub/gps_clock.py` (service `bbb-gps-clock`), steps the clock from it. Correct time anywhere with sky view, no internet, nothing on the BeagleY. |
| A2 / A3 (other BeagleY- or network-sourced time variants) | Not chosen | Same dependency on the BeagleY having true time, which it only has when online. |
| C. Hardware RTC (DS3231 on I2C) with coin cell | Still a hardware add-on | Would let the time survive power-off (GPS needs a fix after every cold boot, indoors there is none). Not needed for B to work. I2C2 shares pins with DCAN0. |

How it works: `bbb-gps-clock.service` runs as `debian` (no root) with only `CAP_SYS_TIME` (`AmbientCapabilities`/`CapabilityBoundingSet`, `NoNewPrivileges=yes`),
connects to `ws://127.0.0.1:8765`, waits for 5 consecutive frames with `gps.utcValid` true and >= 4 satellites, and if the clock is off by more than 1 s calls
`clock_settime` once and logs `[gps_clock] stepped clock by +X s to <ISO UTC>`. It re-checks at most every 10 minutes. GPS dates before 2026-01-01 or after 2040-01-01 are
rejected. Held, stale or invalid fixes are never used. Until the first fix (cold start, indoors) the clock stays wrong; that is expected.

Steps (all via `bbb_stage.sh stage2`, which needs stage 1 done with a release that contains `gps_clock.py`):

1. Mac script checks (read-only) that `releases/current/tools/bbb_hub/gps_clock.py` exists, shows the existing units and runs `gps_clock.py --once --dry-run` on the BBB (no `sudo`, sets nothing).
2. You type `yes`; the script runs `sudo bash bbb_apply.sh stage2` (you type the `debian` sudo password). It records state in `/home/debian/rollback/stage2-*/state.txt`,
   renders the unit with the path `/home/debian/releases/current/tools/bbb_hub`, installs `/etc/systemd/system/bbb-gps-clock.service`, `daemon-reload`, `systemctl enable --now bbb-gps-clock`.
3. It waits up to 120 s for a `stepped clock` line (or the helper's `no step` line when the clock was already right). **No GPS fix yet is not a failure:** it prints that the service is installed and will set the clock when a fix arrives.
4. Check later: `date; journalctl -u bbb-gps-clock -n 20 --no-pager`.

**Rollback:** `bash bbb_stage.sh rollback2` (`systemctl disable --now bbb-gps-clock; rm` the unit; `daemon-reload`). The clock keeps whatever time it has.
The hub is not restarted by this stage; restart it (or reboot) later if you want the baseline/transition-monitor files stamped with the corrected date (see the `time.time()` audit in the PR).
Do not change the BeagleY Wi-Fi/networkd config; Chief of Staff owns it.

## Stage 4 (later): CAN0

`uboot_overlay_addr7=BB-CAN0-00A0.dtbo`, transceiver wiring, `ip link set can0 type can bitrate 500000 listen-only on`, capture, workbench,
`can_signals.json`, then `CAN_LIVE_INTERFACE=can0`. See `docs/bbb_hardware_wiring.md`. Separate approval.

## Suggested order and time

Stage 1 (45 min incl. dry run) -> clock fix (`bbb_stage.sh stage2`, ~5 min) -> UART4 (`bbb_stage.sh stage3`, 30 min) -> UNO wired (this doc's Stage 2) -> later CAN (Stage 4).
Each stage ends with `check_hub_health.py` and a note of the new baseline.
