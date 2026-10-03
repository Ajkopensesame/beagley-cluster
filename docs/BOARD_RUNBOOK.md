# Board Runbook (BeagleY + BBB)

Practical, documentation-only runbook for the two boards in the car/bench rig:
the **BeagleY-AI** (cluster display, Yocto appliance) and the **BeagleBone
Black (BBB)** (vehicle_state hub). Nothing in this document was executed on
hardware while writing it.

**Evidence tags used below**

| Tag | Meaning |
| --- | --- |
| **VERIFIED (HW 2026-10-03)** | Checked read-only on the live boards by Hardware Integration on 2026-10-03. Boards change; re-check before relying on it. |
| **REPO** | Read from files in this repository (may differ from what is deployed). |
| **TO CONFIRM** | Not verified. Do not act on it without checking with the owner. |
| **UNKNOWN** | Nobody has looked yet. |

Related docs: [live_cluster_workflow.md](live_cluster_workflow.md),
[beagley_ui_dev_workflow.md](beagley_ui_dev_workflow.md),
[beagley_wifi_architecture.md](beagley_wifi_architecture.md),
[../yocto/README.md](../yocto/README.md), [ENVIRONMENT.md](ENVIRONMENT.md),
hub protocol [../tools/schema/vehicle_state_v1.md](../tools/schema/vehicle_state_v1.md).
Added by PR #19 (not on this branch until it merges; links resolve after that):
`docs/bbb_deploy_rollback.md`, `docs/bbb_deploy_plan_2026-10-03.md`,
`docs/bbb_hardware_wiring.md`.

---

## 1. Purpose and safety rules

This runbook tells you how to reach the boards, do the routine things (QML
sync, app restart, hub restart), deploy, and recover. It is a map, not an
automation.

Hard rules:

1. **No board deploy, restart of a live service, overlay/boot change, image
   flash or Wi-Fi change without ThatGuy's explicit approval.** Read-only
   inspection is fine. Say which board and which command before you run it.
2. **Builds happen on CI or the Elitebook**, never on the Mac (keep Mac use
   light) and never on the boards.
3. **Wi-Fi is owned by Chief of Staff.** Do not touch
   `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`,
   `/usr/local/libexec/beagley-wifi-apply.sh`, networkd units or the hotspot
   watchdog without them.
4. **Never put passwords, keys or Wi-Fi PSKs** in docs, commits, PR text or
   chat. Reference key file names only.
5. **Use your own git worktree** (`git worktree add /workspace/wt-<topic> ...`).
   Shared checkouts get branch-switched under you.
6. **Never run broad `pkill -f <pattern>`.** The pattern can match your own
   shell command line. Target a unit (`systemctl ...`) or an exact PID.
7. Deploy only from the canonical branch `codex/maplibre-native-yocto-build`
   at a clean, published commit (REPO: `skills/beagley-deploy`,
   `skills/cluster-source-truth`).
8. Do not deploy anything that was not built from CI/Elitebook output of a
   pushed commit. A dirty Mac checkout is a dev queue, not a source of truth.

---

## 2. Topology and access

```text
 hardware GPS -> UART1 \
 UNO inputs  -> UART2  >-> BBB hub (10.24.0.7:8765, WebSocket, vehicle_state)
 (no can0)            /        |  eth0 direct LAN (hub LAN only)
                               v
                       BeagleY eth0 10.24.0.46 --- BeagleY wlan0 (DHCP, Wi-Fi) --- Mac
                       cluster app on the display
```

| Device | Address | How to reach | Owner | Status |
| --- | --- | --- | --- | --- |
| BeagleY (`beagley-ai`) Wi-Fi | DHCP. Was `192.168.1.111`, earlier `192.168.1.100`. **Changes.** | From the **Mac only**: find the IP with `dns-sd -G v4 beagley-ai.local`, then `ssh -o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/beagley_bbb root@<ip>` | Cluster Lead (app); Chief of Staff (Wi-Fi) | **VERIFIED (HW 2026-10-03)** |
| BeagleY from the Elitebook | none | Cannot reach it. Cause **TO CONFIRM** (Wi-Fi client isolation or a different network). Use the Mac. | n/a | Unreachable: **VERIFIED (HW 2026-10-03)**; cause **TO CONFIRM** |
| BeagleY `eth0` | `10.24.0.46/24` | Direct hub LAN to the BBB only; not a general uplink | Cluster Lead | **VERIFIED (HW 2026-10-03)**; REPO `05-beagley-eth-debug.network` |
| BBB hub | `10.24.0.7:8765` (WebSocket) | From the Mac, jump through the BeagleY: `ssh -o BatchMode=yes -i ~/.ssh/beagley_bbb -J root@<beagley-ip> debian@10.24.0.7`. User `debian`; root login refused. | Hardware Integration | **VERIFIED (HW 2026-10-03)** |
| BBB `sudo` | n/a | `debian` has `sudo` with a password (`(ALL:ALL) ALL`). The only passwordless (NOPASSWD) rule is for exactly `/usr/local/sbin/bbb-bench-sim enable\|disable\|status\|parked\|cruise`. So in general there is no passwordless sudo: hub restart, overlay, clock and any other change need ThatGuy's password. | ThatGuy | **VERIFIED (HW 2026-10-03)** |
| BBB USB gadget (fallback) | `192.168.7.2` | Over the USB cable to the BBB. BBB `/etc/systemd/network/usb0.network` is static `192.168.7.2/24` with `DHCPServer=on`, so a laptop on that cable gets a lease. `usb0`/`usb1` were down (no cable) on 2026-10-03. | n/a | Config **VERIFIED (HW 2026-10-03)**; path itself **untested** (TO CONFIRM) |
| BeagleY USB recovery `usb0` (fallback) | `192.168.7.2/24` | REPO: `55-beagley-usb-recovery.network`, `beagley_wifi_architecture.md` recovery path. Same address as the BBB gadget; that is fine as long as only one board is cabled at a time. | Cluster Lead | REPO; untested on hardware (TO CONFIRM) |
| BeagleY wired path | `10.24.0.x` | Hub LAN between the boards; the BBB jump hop uses it | n/a | Working path **VERIFIED (HW 2026-10-03)**. As a *recovery* path it needs the BeagleY up, so it does not help when the BeagleY is the dead one: recovery use **TO CONFIRM** |
| Elitebook (Yocto builder) | see `tools/source_truth/build_canonical_yocto_app.sh` | Builds the Yocto aarch64 app/image | Platform DevOps | REPO; current address **TO CONFIRM** |
| Mac | n/a | Only machine that can reach the BeagleY; hosts the SSH key and snapshots | ThatGuy | **VERIFIED (HW 2026-10-03)** |

Other facts

* BeagleY Wi-Fi: `wlan0`, DHCP. wpa file
  `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`, apply script
  `/usr/local/libexec/beagley-wifi-apply.sh`. wpa priorities: VX network `250`,
  iPhone hotspot `50`. **VERIFIED (HW 2026-10-03)**. The saved-network list and
  the watchdog contract are described in `beagley_wifi_architecture.md` (REPO).
* BBB live service: `bbb-hardware-gps.service` (currently `Type=simple`)
  running `tools/bbb_hub/run_prod.sh` -> `vehicle_hub_prod.py`, env
  `/etc/default/bbb-hardware-gps`. Legacy `vehicle-hub.service` is disabled.
  **VERIFIED (HW 2026-10-03)**. The repo unit (`tools/bbb_hub/bbb-hardware-gps.service`)
  matches that shape (REPO) and adds `Restart=always`, `RestartSec=2`. The repo unit after PR #19 also adds `Type=notify`, `WatchdogSec=15` and log rate limits; the unit on the board is the pre-#19 version.
* BBB deployed dir `/home/debian/projects/beagley-cluster` is **not a git
  checkout** and is **older than the repo**. **VERIFIED (HW 2026-10-03)**.
  Do not assume repo behaviour equals deployed behaviour.
* BBB serial: GPS on `/dev/ttyS1`; UNO input configured on `/dev/ttyS2` but the
  RX pin is damaged (0 frames). No `can0`. **VERIFIED (HW 2026-10-03)**.
* Canonical hub address is `10.24.0.7`. Any `192.168.0.x` hub value in older
  docs is a stale hotspot-era value. Canonical hub protocol doc is
  `tools/schema/vehicle_state_v1.md` (the vehicle-hub repo `PROTOCOL.md` is
  legacy).
* Repo helper scripts default to `root@beagley-ai.local`
  (`skills/beagley-common/scripts/ssh.sh` also tries mDNS and
  `config/beagley-target.env`, which is gitignored). They use
  `BatchMode=yes`, `ConnectTimeout=8`. mDNS may fail; pass the discovered IP
  with `BEAGLEY_HOST=root@<ip>`.
* Several repo docs/skills still show `192.168.0.92`, `192.168.0.x` and
  `/Users/joshkomant/...` paths. Treat them as stale examples.

---

## 3. Daily flows

All of these run on the **Mac** (the only machine that reaches the BeagleY).
Each one changes a live board: get approval first (rule 1).

### 3.1 QML hot-sync (UI iteration, no Yocto build)

REPO: `docs/beagley_ui_dev_workflow.md`, `tools/ui/*`.

Prerequisite: the deployed binary supports `BEAGLEY_QML_DEV_ROOT`
(**TO CONFIRM** for the binary currently on the board).

1. Find the IP (`dns-sd -G v4 beagley-ai.local`), then export
   `BEAGLEY_HOST=root@<ip>`.
2. Confirm what the display really runs: `tools/ui/beagley_display_status.sh`
   (`qml_source=compiled-binary` or `qml-dev`).
3. One-time enable: `tools/ui/beagley_enable_qml_dev.sh`. It syncs `src/ui` to
   `/opt/beagley-cluster/qml-dev`, installs
   `/etc/systemd/system/beagley_cluster.service.d/ui-dev.conf`
   (`BEAGLEY_QML_DEV_ROOT=...`), runs `daemon-reload` and restarts the app.
4. Edit, then sync: `tools/ui/beagley_sync_qml.sh` (restart + health check) or
   `tools/ui/beagley_watch_qml.sh` (polls `src/ui`, re-syncs and restarts on
   every change). Flags: `--no-restart`, `--no-health`, `--remote-root PATH`.
5. Each sync writes `.beagley-qml-manifest` (branch, commit, dirty count) in
   the remote root. A dirty tree means the display is **not** reproducible
   from GitHub.
6. Finish: `tools/ui/beagley_disable_qml_dev.sh` removes the drop-in and
   restarts into the compiled QML. Final validation must be on a Yocto-built
   binary with `qml_source=compiled-binary`.

**Wipe gotcha.** `beagley_sync_qml.sh` is a *replace*, not a merge: it runs
`rm -rf` on the remote root (and `<root>.tmp`) and re-creates it from a tar of
`src/ui`. **Anything else in `/opt/beagley-cluster/qml-dev` is deleted on every
sync, including a hand-made `SkinShowOverride.qml`.** The watcher does this on
every save. Keep such files in the repo (or a copy outside the sync root) and
re-create them after each sync. Where the master copy of
`SkinShowOverride.qml` lives is **TO CONFIRM**.

PR #8 added `validate_remote_root`: the sync refuses an empty or relative path,
characters outside `A-Za-z0-9._/-`, `//`, a trailing `/`, `.`/`..` segments,
fewer than three components, and roots under `/bin /boot /dev /etc /lib* /proc
/root /run /sbin /sys /usr`. Do not work around it. (`beagley_enable_qml_dev.sh`
only checks for single quotes itself but calls the sync script, which
validates.)

### 3.2 App restart (`beagley_cluster`)

REPO: `skills/beagley-restart-safe/scripts/restart.sh`, unit
`yocto/.../files/beagley_cluster.service`, launcher
`beagley-cluster-launch.sh`.

What the unit does (REPO): `Restart=always`, `RestartSec=2`; env from
`/etc/default/beagley-cluster` then `/etc/default/beagley-cluster.local` (local
overrides win; secrets go in `.local`); a GPU gate (`/run/beagley_gpu_gate.ok`,
waits up to 30 s) before start; `ExecCondition` skips start in diagnostic mode
(`beagley.diag=1` on the kernel cmdline or `/run/beagley-diagnostic.mode`); the
launcher re-runs the strict GPU gate, waits up to 20 s for the hub
(`VEHICLE_HUB_WS_URL`, never fatal) and `exec`s `/usr/bin/beagley_cluster`.

Safe restart procedure:

1. Get approval; note the car/bench state. The display blanks for several
   seconds.
2. Record state first (read-only): `systemctl is-active beagley_cluster`,
   `systemctl show beagley_cluster -p NRestarts`,
   `journalctl -u beagley_cluster -n 30 --no-pager` (the `[BUILD]` line gives
   the deployed commit).
3. Run `skills/beagley-restart-safe/scripts/restart.sh` (SSH target resolved by
   the common helper). It does `systemctl reset-failed beagley_cluster`,
   `systemctl start beagley_cluster`, then `systemctl status`. Note it uses
   **`start`**, not `restart`, so it does not bounce an already-running app.
   For a running app use `systemctl restart beagley_cluster` (this is what the
   sync and deploy scripts do).
4. Verify with `skills/beagley-health-check/scripts/check.sh`: unit `active`,
   `NRestarts <= 5`, process exists, last 10 journal lines. A restart loop
   fails the check.
5. If it fails: `skills/beagley-debug-service/scripts/debug.sh` for
   diagnostics. Do not keep restarting in a loop.

**Hung app (VERIFIED incident, HW 2026-09-19).** The app sat at about 86% CPU
on eglfs after a MainV3/GirlGlass load and an Arago login prompt showed on the
glass. Recovery: SIGKILL of the app process, then rolling back the GirlGlass
change. Use an exact PID or `systemctl kill -s KILL beagley_cluster`
(**TO CONFIRM**: not exercised, shown as the unit-scoped equivalent). Never use
a broad `pkill -f`.

### 3.3 Hub restart (BBB)

Restarting the hub needs `sudo` with a password on the BBB (the only NOPASSWD
rule is for `bbb-bench-sim`), so **ThatGuy must run it or approve a narrow
sudoers rule**. The same applies to overlay and clock changes.

1. Reach the BBB through the BeagleY jump (section 2). Read-only first:
   `systemctl is-active bbb-hardware-gps`,
   `journalctl -u bbb-hardware-gps -n 50 --no-pager`,
   `cat /etc/default/bbb-hardware-gps`. Log timestamps are unreliable
   (section 6).
2. A restart blanks the gauges for roughly 5-10 s (**estimated** in the PR #19 plan, not measured).
3. ThatGuy runs: `sudo systemctl restart bbb-hardware-gps`.
4. Verify within 60 s: service `active`, no traceback in the journal, and the
   cluster on the BeagleY reconnects (`journalctl -u beagley_cluster` shows
   `VehicleStateClient connecting to ws://10.24.0.7:8765`).
   `tools/bbb_hub/check_hub_health.py ... --require-gps` is added by PR #19.
   Gauge behaviour while the hub is down or its sources are stale goes with two
   PRs: PR #19 (stale sources publish 0.0 / fail-safe) and PR #23 (UI link-lost
   dashes and LINK LOST telltale). Read them together; the glass was not
   checked on hardware (**TO CONFIRM**, owner Cluster HMI/Engineer).
5. A restart reloads `/etc/default/bbb-hardware-gps`. Env or unit edits also
   need `sudo systemctl daemon-reload`. Keep a dated backup of anything you
   edit.

**Bench vehicle simulation toggle (`bbb-bench-sim`)**

> **WARNING: `sudo bbb-bench-sim enable` makes the hub send FAKE vehicle data**
> (speed, rpm, fuel, coolant, gear, indicators, warnings, drivetrain). Run
> `sudo bbb-bench-sim status` and make sure the state is `disable` before any
> real-vehicle test or any test whose results depend on real inputs.

Installed on the BBB (**VERIFIED (HW 2026-10-03)**):

* binary `/usr/local/sbin/bbb-bench-sim` (not `/usr/local/bin`)
* sudoers rule `/etc/sudoers.d/bbb-bench-sim`: NOPASSWD for exactly
  `enable|disable|status|parked|cruise`
* scripts `/home/debian/projects/beagley-cluster/tools/bbb_hub/bbb_bench_vehicle_sim.sh`
  and `install_bbb_bench_sim_toggle.sh`
* env `BBB_VEHICLE_BENCH_SIM=0`, profile `busy-demo` (read 2026-10-03)

Usage and what it synthesizes: `live_cluster_workflow.md` (REPO).

---

## 4. Deploy checklist

Applies to the app/image (BeagleY) and the hub (BBB). Hub specifics are in the
PR #19 docs (`bbb_deploy_rollback.md`, `bbb_deploy_plan_2026-10-03.md`,
**not yet on the default branch**).

- [ ] **CI green** on the exact commit. Required check:
      `Configure + build (WITH_WEBENGINE=OFF)`. For hub changes also run
      `python3 -m pytest tests -q` (Python CI arrives with PR #19/#20).
- [ ] **Source of truth clean**: commit is on `codex/maplibre-native-yocto-build`
      and pushed; `skills/cluster-source-truth/scripts/check.sh --strict` is
      clean.
- [ ] **Artifact built** on CI or the Elitebook, not the Mac:
      `tools/source_truth/build_canonical_yocto_app.sh` (fast-forward only from
      GitHub, remote-ref enforced) or `yocto/build-appliance-image.sh` for a
      full image. SRCREV is pinned to the commit (`yocto/README.md`). Record
      the SHA and file checksums. Confirm the binary is Linux aarch64
      (`file <bin>`).
- [ ] **Approval** from ThatGuy, naming board, artifact SHA and time window.
      Record where it was given (PR comment or chat link).
- [ ] **Snapshot / rollback reference** (read-only copies). BeagleY: current
      `/usr/bin/beagley_cluster`, `/usr/bin/beagley-cluster-launch.sh`,
      `/etc/default/beagley-cluster.local`, `[BUILD]` line, active drop-ins.
      BBB: `tools/bbb_hub`, `/etc/default/bbb-hardware-gps`, the unit and
      `/boot/uEnv.txt`. A BBB snapshot from 2026-10-03 exists on the Mac at
      `~/bbb-snapshots/2026-10-03-pre-deploy/` (**VERIFIED (HW 2026-10-03)**);
      take a fresh one if the board changed since.
- [ ] **Deploy**, one board at a time.
      * BeagleY app: `BEAGLEY_HOST=root@<ip> BEAGLEY_DEPLOY_BIN=<aarch64 binary>
        skills/beagley-deploy/scripts/deploy.sh`. REPO behaviour: refuses a
        non-aarch64 binary; stops the app, copies the current binary and
        launcher to `/var/volatile/*.rollback`, installs the new ones, resets
        failed state, restarts, runs the health check, and on a failed install
        restores the rollback copies. `/var/volatile` is RAM, so those
        rollback copies **do not survive a reboot**.
      * BBB hub: stage beside the running code, never over it; deploy order
        code -> env -> unit -> `daemon-reload` -> restart (a `Type=notify`
        unit needs `sd_notify`-capable code first). Needs ThatGuy for `sudo`.
      * Full image: flashing the media is a separate approval and a
        hands-on step (see 5.3).
- [ ] **Health check**: BeagleY `check.sh` OK and
      `skills/cluster-source-truth/scripts/check.sh --strict` shows the new
      `[BUILD]` commit and `qml_source=compiled-binary` (and
      `BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=1` with the MapLibre renderer).
      If `qml-dev`, remove the `ui-dev.conf` drop-in and restart. BBB: service
      active, hub health check OK, live data on the glass.
- [ ] **Record**: SHA, artifact checksum, board, who approved, time (note that
      the BBB clock is wrong; use the Mac clock), snapshot location, result.
      Put it in the PR or issue that drove the change.

---

## 5. Rollback and recovery

### 5.1 App and QML rollback (BeagleY)

* **QML-dev experiment went wrong** (REPO): run
  `tools/ui/beagley_disable_qml_dev.sh`. It removes the drop-in and restarts
  the compiled-in QML.
* **Bad binary just deployed**: `deploy.sh` already restores
  `/var/volatile/beagley_cluster.rollback` and the launcher rollback if the
  *install* step fails. For a later rollback, copy the saved previous binary
  back to `/usr/bin/beagley_cluster` (mode 0755), `systemctl reset-failed
  beagley_cluster`, `systemctl restart beagley_cluster`, run the health check.
  Whether the `/var/volatile` copy is still there depends on whether the board
  rebooted; keep your own copy of the previous artifact on the Mac/Elitebook.
* **Config change** (`/etc/default/beagley-cluster.local`): restore the dated
  backup, `systemctl restart beagley_cluster`. Example from the repo docs: a
  `.local.bak-slice6-20260906` backup of the pre-change profile (existence now
  **TO CONFIRM**).
* **Hung or glass shows a login prompt**: see 3.2 (SIGKILL the app process,
  revert the visual change). Precedent: incident 2026-09-19.

### 5.2 Hub rollback (BBB)

Summary of PR #19 `bbb_deploy_rollback.md` / `bbb_deploy_plan_2026-10-03.md`
(read those for the full text):

* Rollback uses only files saved before the change, so it works without
  network access: restore the saved unit and env copies (or repoint a
  `current` symlink to the previous release), then
  `sudo systemctl daemon-reload && sudo systemctl restart bbb-hardware-gps`,
  then re-run the health check.
* The old code stays untouched at
  `/home/debian/projects/beagley-cluster/tools/bbb_hub` while a new release is
  staged beside it.
* Full restore from the Mac snapshot: `bbb-snapshot.tgz` in
  `~/bbb-snapshots/2026-10-03-pre-deploy/` (checksums in `MANIFEST.sha256`);
  extraction as root, ThatGuy only.
* Config-only fallbacks (no code change): unset `VEHICLE_INPUT_SERIAL_DEVICE`,
  unset `CAN_LIVE_INTERFACE`, restart the hub. Both variables exist in the
  hub deployed on the BBB today (**VERIFIED (HW 2026-10-03)**).
  `VEHICLE_SENSOR_CALIBRATION` exists only in repo code from PR #11 (merged);
  the deployed BBB hub is older code and does not read it at all, so changing
  it does nothing until the hub is updated.
* Overlay/UART changes need a BBB reboot: back up `/boot/uEnv.txt`, change one
  overlay at a time, roll back by restoring the copy and rebooting.
* Ordering trap: a unit with `Type=notify`/`WatchdogSec` installed before
  `sd_notify`-capable code makes systemd kill the hub.
* The app launcher only waits up to 20 s for the hub and then starts anyway.
  REPO: `VehicleStateClient.cpp` auto-reconnects with backoff and has a stale
  watchdog, so the app keeps running and reconnects. What the glass shows with
  no hub is **not confirmed on hardware** (**TO CONFIRM**); owned by Cluster
  HMI/Engineer (PR #23: link-lost dashes + LINK LOST telltale, merging).

### 5.3 Image / Yocto rollback (BeagleY)

* How the image is updated in the field: flash the `wic` image from
  `build-*/release/<image>-<machine>-<timestamp>/` with
  `yocto/flash-appliance-image-linux.sh` (Elitebook) or
  `yocto/flash-appliance-image-macos.sh` (Mac) (REPO `yocto/README.md`).
  Each release dir has `SHA256SUMS` and `image-manifest.txt`.
* Rollback = re-flash the previous release image. **TO CONFIRM**: whether the
  previous release directories/artifacts are retained anywhere, who flashes,
  and how long it takes.
* **TO CONFIRM**: whether there is an A/B or fallback boot slot (nothing in the
  repo suggests one).
* **TO CONFIRM**: whether `/etc/default/beagley-cluster.local` and other state
  survive a re-flash (assume no; back it up).
* A diagnostic image exists: `beagley-cluster-image-diag` (REPO). It
  suppresses the app and GPU-probe services and writes stage markers under
  `/var/lib/beagley-cluster/diagnostic`. Using it on the car board is
  **TO CONFIRM**.
* If the GPU gate fails, the app does not start but the OS and SSH stay up
  (REPO `yocto/README.md`), so SSH-based recovery should still work.

### 5.4 Cannot boot / Wi-Fi lost / BeagleY not reachable

Order of least to most invasive. Wi-Fi config is **not** yours to edit.

1. **Re-discover the IP.** DHCP changes it. From the Mac run
   `dns-sd -G v4 beagley-ai.local` (stop it with Ctrl-C; do not `pkill -f`).
   Retry with `ConnectTimeout >= 8`. Check the Mac is on the same Wi-Fi and
   that the router does not isolate clients.
2. **Wrong network in range?** Priorities are VX network `250`, iPhone hotspot
   `50` (**VERIFIED (HW 2026-10-03)**). If the board sits on the hotspot or
   nothing is in range, the fix belongs to Chief of Staff.
3. **Wired hub LAN**: the BeagleY `eth0` is `10.24.0.46` and the BBB `10.24.0.7`.
   If the BBB is reachable by another path, the BeagleY can be reached from it
   at `10.24.0.46`. This is a working path, but it needs the BeagleY up, so it
   does not help if the BeagleY is the dead board. Recovery use **TO CONFIRM**.
4. **USB gadget** `192.168.7.2`. The BBB gadget address is documented but
   untested (**TO CONFIRM**). The BBB side is a static `192.168.7.2/24` with a
   DHCP server, so a laptop on the cable gets a lease. The BeagleY image also
   defines `usb0` as `192.168.7.2/24` (REPO), also untested (**TO CONFIRM**);
   that is fine as long as only one board is cabled. Confirm which one
   answers before doing anything.
5. **Wi-Fi watchdog**: the BeagleY has a hotspot watchdog that handles
   CC33xx driver stuck states (REPO `beagley_wifi_architecture.md`). Do not
   disable or tune it without Chief of Staff.
6. **Display shows a login prompt or frozen UI but SSH works**: section 3.2.
7. **No SSH at all and no display**: needs physical access (serial console,
   re-flash). Console/UART debug procedure and the boot media layout are
   **UNKNOWN**; ask the Yocto owners.

---

## 6. Known issues (as of 2026-10-03)

| Issue | Detail | Source |
| --- | --- | --- |
| BBB clock wrong | Shows Apr 2026, RTC reads 2000-01-01, not synchronized, and the BBB link has no internet. Journal and fault-recorder timestamps are unreliable. Fix options (chrony from BeagleY, GPS time, RTC) are in the PR #19 plan, Stage 3; none applied. | **VERIFIED (HW 2026-10-03)** |
| journald unbounded on BBB | 558 MB used. A limits drop-in (`tools/bbb_hub/journald-beagley.conf`) is added by PR #19; not installed. | **VERIFIED (HW 2026-10-03)** |
| ttyS mismatch | Live: GPS on `/dev/ttyS1`, UNO configured on `/dev/ttyS2` (RX pin damaged, 0 frames). Docs and `bbb-hardware-gps.env.example` that say `ttyS4` are stale; UART4 on P9_11 is a *proposal* (PR #19 plan, Stage 2). | **VERIFIED (HW 2026-10-03)** |
| No CAN | No `can0`, no `can_signals.json` on the BBB. | **VERIFIED (HW 2026-10-03)** |
| BBB deployed code is old | Not a git checkout, older than the repo. Repo behaviour and tests do not describe what runs. | **VERIFIED (HW 2026-10-03)** |
| BeagleY unreachable from Elitebook | Likely Wi-Fi client isolation. Builds can still be done on the Elitebook, but pushing to the board goes via the Mac. | **VERIFIED (HW 2026-10-03)** |
| BeagleY IP changes | DHCP. Hard-coded IPs in docs and skills (`192.168.0.92` etc.) are stale. | **VERIFIED (HW 2026-10-03)** |
| Stale hub address | `192.168.0.x` hub values are hotspot-era. Canonical is `10.24.0.7`. The vehicle-hub repo `PROTOCOL.md` is legacy. | REPO (`docs/ENVIRONMENT.md`) |
| `main` is unrelated history | Port changes by hand; do not merge across. `legacy-main-2026-10-03` branch exists. | REPO (`README.md`) |

---

## 7. Open questions (for ThatGuy and owners)

**ThatGuy**

1. Standing rule for approvals: is a PR comment enough, or do you want chat
   sign-off per deploy? `sudo` on the BBB needs your password (except
   `bbb-bench-sim`): will you run hub restarts yourself, or approve a narrow
   sudoers rule for `systemctl restart bbb-hardware-gps`?
2. Should the BBB clock fix (PR #19 plan Stage 3, option A first) go ahead, and
   when?
3. `bbb-bench-sim` is installed (state `disable`). Who is allowed to enable it, and how is the state checked before a real-vehicle test?

**Chief of Staff (Wi-Fi)**

4. Can the BeagleY get a DHCP reservation (or a stable name) so the IP stops
   moving? Is Wi-Fi client isolation on the VX network intended, and can the
   Elitebook be allowed through?

**Platform DevOps / Yocto owners**

5. Image rollback: are previous release images retained, is there an A/B slot,
   what state survives a re-flash, who flashes? (5.3)
6. Does the board's deployed binary support `BEAGLEY_QML_DEV_ROOT`? Where is
   the master copy of `SkinShowOverride.qml`?
7. Is `systemctl kill -s KILL beagley_cluster` the agreed way to clear a hung
   app? What caused the 2026-09-19 eglfs hang (MainV3/GirlGlass)?
8. Current Elitebook address/name for the canonical build, and whether the
   previous app binary is archived per release.
9. Serial console / physical recovery procedure for a BeagleY that does not
    boot (UNKNOWN).

**Hardware Integration**

10. Is the USB gadget fallback (`192.168.7.2`) tested on the BBB and on the
    BeagleY? (Only one board should be cabled at a time.)
11. Wired `10.24.0.x` as a recovery path: it needs the BeagleY up; is there any use case when the BeagleY is the dead board?
12. What does the glass show when the hub is down or sources are stale (PR #19 + PR #23 together)? Owner: Cluster HMI/Engineer.
13. After PR #19 merges: update section 3.3/5.2 to point at the merged docs
    and the hub health-check tool, and update the unit state (`Type=notify`).

---

*Maintenance:* update the evidence tags when someone verifies an item.
Re-verify **VERIFIED (HW 2026-10-03)** facts after any hardware, network or
image change.
