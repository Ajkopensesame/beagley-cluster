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
hub protocol [../tools/schema/vehicle_state_v1.md](../tools/schema/vehicle_state_v1.md),
UNO bench checklist [bench_test_checklist.md](bench_test_checklist.md),
UNO firmware [../firmware/uno_vehicle_input/](../firmware/uno_vehicle_input/README.md).
Added by PR #19 (merged):
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
 UNO inputs  -> UART4  >-> BBB hub (10.24.0.7:8765, WebSocket, vehicle_state)
 (no can0)            /        |  eth0 direct LAN (hub LAN only)
                               v
                       BeagleY eth0 10.24.0.46 --- BeagleY wlan0 (DHCP, Wi-Fi) --- Mac
                       cluster app on the display
```

| Device | Address | How to reach | Owner | Status |
| --- | --- | --- | --- | --- |
| BeagleY (`beagley-ai`) Wi-Fi | DHCP. `192.168.1.111` on 2026-10-03; was `192.168.1.100` on 2026-09-20 (that address now times out on port 22). **Changes: re-discover it every time.** | From the **Mac only**: find the IP with `dns-sd -G v4 beagley-ai.local`, then `ssh -o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/beagley_bbb root@<ip>` | Cluster Lead (app); Chief of Staff (Wi-Fi) | **VERIFIED (HW 2026-10-03)** |
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
  matches that shape (REPO) and adds `Restart=always`, `RestartSec=2`. The repo unit (since PR #19, merged) also has `Type=notify`, `WatchdogSec=15` and log rate limits; the board's unit state is under "Deployed board state" (`Type=notify` since the 2026-10-03 deploy).
* BBB deployed dir `/home/debian/projects/beagley-cluster` is **not a git
  checkout** and is **older than the repo**. **VERIFIED (HW 2026-10-03)**.
  Do not assume repo behaviour equals deployed behaviour.
* BBB serial: GPS on `/dev/ttyS1`; UNO input was configured on `/dev/ttyS2` but the
  RX pin is damaged (0 frames); since ~15:23 AEST it is on `/dev/ttyS4` (UART4),
  nothing wired yet. No `can0`. **VERIFIED (HW 2026-10-03)**; see "Deployed board
  state" below for the as-deployed facts, which supersede older "pre-deploy"
  bullets in this section.
* BeagleY time: it is a Yocto image with **no `chrony` or `ntpd`**; time comes
  from `systemd-timesyncd` only. **VERIFIED (HW 2026-10-03)**. So the BeagleY
  cannot serve time to the BBB (the "chrony from BeagleY" option in the
  PR #19 plan, Stage 3, option A, does not apply without adding a package).
* BBB clock: wrong on 2026-10-03 (shows Apr 2026, RTC reads 2000-01-01, no
  internet on the `10.24.0.x` link). **VERIFIED (HW 2026-10-03)**. The fix in
  progress is to set the time from GPS (Hardware Integration's follow-up
  GPS-time PR). Staged deploy scripts for it (hub update, clock fix, UART4)
  were in PR #29 ("staged BBB deploy scripts"), since merged (included in #32) and
  **deployed 2026-10-03**; the GPS clock service now sets the time (see "Deployed
  board state"). Records from before the first clock step carry the wrong date.
* Hub speed source (REPO, **PR #30, merged**): the hub now prefers GPS speed
  and falls back to pulse speed. Env `VEHICLE_SPEED_SOURCE` =
  `gps_first` | `pulse_only` | `gps_only`; the active choice is reported in
  the additive `_health.speedSource` field. **The hub deployed on the BBB is
  still the OLD code** and has none of this until ThatGuy approves a deploy.
  Bench steps: [bench_test_checklist.md](bench_test_checklist.md). UNO
  firmware (pulse/input sketch): [../firmware/uno_vehicle_input/](../firmware/uno_vehicle_input/README.md).
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

> **WARNING: the repo scripts target the wrong tree on the current board.**
> `tools/ui/beagley_sync_qml.sh`, `beagley_enable_qml_dev.sh` and
> `beagley_watch_qml.sh` default to `/opt/beagley-cluster/qml-dev` (also when
> `BEAGLEY_QML_DEV_ROOT` is set in your shell). **That is not what the glass
> shows** (see "What the display actually runs" below). Pointing
> `--remote-root` (or `BEAGLEY_QML_DEV_ROOT`) at the live source directory
> under `/data` passes the script's path validation and then **`rm -rf`s the
> live Pearl UI** (about 24 MB: PearlControlCenter, weather, radar, skin-v2,
> `tools/ui/audit` probes, fonts) and replaces it with the much smaller repo
> `src/ui`. Do not do that. Use the capture-once method below to try a
> different QML root.

**What the display actually runs (VERIFIED (HW 2026-10-03), read-only).**

* Unit `beagley_cluster.service`. Many numbered drop-ins (`90-` to `99-z-`)
  exist and the last one wins. The effective `ExecStart` comes from
  `/etc/systemd/system/beagley_cluster.service.d/99-z-hotspot-wifi.conf`:
  `/data/beagley-cluster/runtime-hotspot-wifi-20260919/launch.sh`
  (`User=root`). All `ui-dev.conf` drop-ins are renamed `*.disabled.*`.
* `launch.sh` (not `/opt`) exports `BEAGLEY_UI_VARIANT=v3`,
  `BEAGLEY_QML_DEV_ROOT=<runtime>/source` (same runtime dir, under `/data`),
  `BEAGLEY_QML_DEV_FILE=<root>/src/ui/MainV3.qml` (or
  `tools/ui/audit/start_plaza_sim.qml` while `/run/beagley-retrigger-plaza-sim`
  exists) and `BEAGLEY_MAP_RENDERER=maplibre-native` with `file://` dark/light
  vector styles from that source tree. `/etc/default/beagley-cluster.local`
  sets the same root/file (do not paste that file anywhere: it holds Spotify
  tokens).
* So the **live QML root is `<runtime>/source` under `/data`**, a Pearl UI
  snapshot that is a different, larger tree than this repo's `src/ui`.
  `/opt/beagley-cluster/qml-dev` is a **stale copy** (manifest synced
  2026-09-06, branch `ui/slice1-map-hierarchy-quiet-chrome`, commit
  `458d02d46782`, 18 dirty files). The `ui-dev.conf` that
  `beagley_enable_qml_dev.sh` installs would be overridden by `launch.sh`'s
  own exports anyway.
* Find the real root on the day, do not assume it:
  `systemctl show beagley_cluster -p ExecStart`, then `cat` the `launch.sh`
  it names (read-only).

Prerequisite: `BEAGLEY_QML_DEV_ROOT` **is supported** by the deployed binary
(VERIFIED (HW 2026-10-03): the live display uses it), but only with the C++
and fonts from the same build. Fonts are registered in C++ from the Qt
resources (`src/main.cpp`: Oxanium-Regular, Orbitron-Medium, Orbitron-Bold) and
the `linkLost` state (REPO: `src/data/VehicleStateSource.*`, `src/render/ClusterRenderModel.*`) is also C++, so a QML-only sync cannot deliver
new fonts or new C++-backed properties (see section 6).

1. Find the IP (`dns-sd -G v4 beagley-ai.local`), then export
   `BEAGLEY_HOST=root@<ip>`.
2. Confirm what the display really runs: `tools/ui/beagley_display_status.sh`
   (`qml_source=compiled-binary` or `qml-dev`) **and** the `ExecStart` /
   `launch.sh` check above. The status script reports on the drop-in it knows
   about, not on a `launch.sh` that sets its own root.
3. One-time enable (**only on a board that really runs from
   `/opt/beagley-cluster/qml-dev`; not the current board**):
   `tools/ui/beagley_enable_qml_dev.sh`. It syncs `src/ui` to
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
`src/ui`. **Anything else in the remote root (default `/opt/beagley-cluster/qml-dev`)
is deleted on every sync, including a hand-made `SkinShowOverride.qml`.** The watcher does this on
every save. Keep such files in the repo (or a copy outside the sync root) and
re-create them after each sync. Where the master copy of
`SkinShowOverride.qml` lives is **TO CONFIRM**.

PR #8 added `validate_remote_root`: the sync refuses an empty or relative path,
characters outside `A-Za-z0-9._/-`, `//`, a trailing `/`, `.`/`..` segments,
fewer than three components, and roots under `/bin /boot /dev /etc /lib* /proc
/root /run /sbin /sys /usr`. Do not work around it. (`beagley_enable_qml_dev.sh`
only checks for single quotes itself but calls the sync script, which
validates.)

**Capture-once trial / one-shot screenshot (`capture-once.env`).** On the
current board `launch.sh` sources `$RUNTIME/capture-once.env` after its own
exports and then **deletes it**, so the next restart reverts to the normal
setup. It can override `BEAGLEY_QML_DEV_ROOT` / `BEAGLEY_QML_DEV_FILE` and set
`BEAGLEY_SCREENSHOT_PATH`, `BEAGLEY_SCREENSHOT_DELAY_MS` and
`BEAGLEY_SCREENSHOT_EXIT` (REPO: `src/main.cpp` implements the screenshot
variables). This is the supported way to try a different QML root or take a
screenshot (it is how the 2026-09-20 shots were taken), and it is much safer
than a sync. Put trial QML in a **new directory under `/data`**, never in
the live `source` directory, and write screenshots to `/data` too (root fs is
nearly full, see section 6). Needs approval like any restart (rule 1).
(VERIFIED (HW 2026-10-03), read-only; the hook is in the board's `launch.sh`,
not in this repo.)

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
   (section 6). `VEHICLE_SPEED_SOURCE` and `_health.speedSource` (PR #30) only
   exist after the hub is updated; the deployed hub is still the old code.
   After a deploy, run the speed-source cases in
   [bench_test_checklist.md](bench_test_checklist.md).
2. A restart blanks the gauges for roughly 5-10 s (**estimated** in the PR #19 plan, not measured).
3. ThatGuy runs: `sudo systemctl restart bbb-hardware-gps`.
4. Verify within 60 s: service `active`, no traceback in the journal, and the
   cluster on the BeagleY reconnects (`journalctl -u beagley_cluster` shows
   `VehicleStateClient connecting to ws://10.24.0.7:8765`).
   `tools/bbb_hub/check_hub_health.py ... --require-gps` exists (added by PR #19, merged).
   Gauge behaviour while the hub is down or its sources are stale goes with two
   PRs, both merged: PR #19 (stale sources publish 0.0 / fail-safe) and PR #23 (UI link-lost
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
now on the default branch).

- [ ] **CI green** on the exact commit. Required check:
      `Configure + build (WITH_WEBENGINE=OFF)`. For hub changes also run
      `python3 -m pytest tests -q` (Python CI is `contract-tests` in `diagnostic-replay-contracts.yml`, from PR #19/#20, merged).
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
        Staged deploy scripts (hub update, clock fix, UART4) were PR #29, now merged
        (included in #32) and used for the 2026-10-03 deploy:
        `tools/bbb_hub/deploy/bbb_stage.sh` (Mac) and `bbb_apply.sh` (BBB).
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
  HMI/Engineer (PR #23, merged: link-lost dashes + LINK LOST telltale; not in the binary currently on the board, see section 6).

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

## Deployed board state (verified 2026-10-03 15:55 AEST)

Evidence tag for everything in this section: **VERIFIED (HW 2026-10-03)** (Hardware Integration), unless marked
REPO / UNKNOWN. It describes the boards *after* the 2026-10-03 deploy and supersedes the "pre-deploy" statements
elsewhere in this runbook. No secrets are recorded here.

### BBB (BeagleBone Black)

* **Release `305b982`** (merge of #32, which includes #30 and #31) live since 2026-10-03 ~15:17 AEST. Deployed by an
  owner-authorised run of `bbb_stage.sh` stage1/2/3 from the Mac. Hub restarted 15:17, and again 15:24 after the reboot.
* **Layout:** `/home/debian/releases/<sha>/` (`305b982`; `5f01914` was only a dry-run copy); symlink
  `/home/debian/releases/current -> /home/debian/releases/305b982` (root-owned); `release-<sha>.tgz` and `bbb_apply.sh`
  in `/home/debian/releases/`. The old hub code at `/home/debian/projects/beagley-cluster` is not a git checkout and is
  no longer used.
* **Hub:** `bbb-hardware-gps.service` enabled, `User=debian`, `Type=notify`, runs
  `/bin/bash /home/debian/releases/current/tools/bbb_hub/run_prod.sh` -> `vehicle_hub_prod.py`, WebSocket
  `0.0.0.0:8765`. The hub log shows speed source `gps_first`. `/var/lib/beagley-cluster` and `/var/log/beagley-cluster`
  were created (owner `debian`).
* **Env `/etc/default/bbb-hardware-gps`:** `BBB_GPS_DEVICE=/dev/ttyS1`, `BBB_GPS_BAUD=115200`,
  `VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4` @115200, `GPS_SOURCE_POLICY=hardware_only`, `BBB_VEHICLE_BENCH_SIM=0`.
  (REPO note: the code default for `BBB_GPS_DEVICE` in `vehicle_hub_prod.py` is still `/dev/ttyS4`, so keep it set
  explicitly.)
* **Caveat, file times:** the BBB wall clock was wrong until stage 2, so mtimes of the stage1 dirs under
  `/home/debian/releases` and of `rollback/stage1-*`, `stage2-*` show Apr 27 2026. Do not use them as deploy times.

### UART

* `/boot/uEnv.txt` overlays: `addr4=BB-UART1`, `addr5=BB-UART2`, `addr6=BB-UART4` (UART4 added 15:23 AEST; BBB
  rebooted). `ttyS1`, `ttyS2`, `ttyS4` exist.
* UART4 pins: RX P9_11, TX P9_13 (REPO). Pin-mux **UNKNOWN** (not queried with `config-pin`).
* **Nothing is wired to UART4 yet** (UNO disconnected; 0 serial frames).
* GPS is on `/dev/ttyS1` (UART1) with a live fix, 12 satellites. UART2/`ttyS2` is enabled but unused (RX pin P9_22 is
  damaged).

### GPS clock (`bbb-gps-clock.service`)

* Enabled and active, `Type=simple`, `User=debian`, `AmbientCapabilities=CAP_SYS_TIME`, runs `gps_clock.py` from
  `releases/current`.
* Reads GPS UTC from the hub WebSocket (`gps.utcMs` / `gps.utcValid`). Steps the clock after 5 consecutive valid
  frames with >= 4 satellites when off by more than 1 s; rechecks every 600 s; rejects dates before 2026-01-01 or
  after 2040-01-01.
* First set: stepped +13759463.572 s at 15:22:43. After the reboot: re-stepped +36.9 s at 15:24:28. There is no
  battery-backed RTC, so the clock resets on every boot until the GPS fix (about 40-60 s after boot). Later offsets
  were under 0.5 s; drift is about 0.1 s per 10 min.
* `timedatectl` still says "System clock synchronized: no". This is cosmetic: it only tracks timesyncd/NTP.
* With no fix the service stays running and waits (REPO + stub test; **not tested live** with the antenna removed).

### BeagleY (unchanged by this deploy)

* Arago 2025.01; `beagley_cluster.service` active; `beagley-user-bg-upload.service` (:8787); app under
  `/opt/beagley-cluster`. Running commit: `1371e7f299fd` (2026-09-13 build, branch `development/drive-adaptive-feeds-20260913`, from the `[BUILD]` journal line), launched via `/data/beagley-cluster/runtime-hotspot-wifi-20260919/launch.sh`; see 3.1 and section 6.
* Wi-Fi DHCP currently `192.168.1.111` on `VX220-9869`. It dropped off the network twice on 2026-10-03 (13:40-14:50
  and ~15:52 AEST); cause **UNKNOWN** (Chief of Staff owns Wi-Fi).

### Rollback pointers

* BBB backups in `/home/debian/rollback/`: `stage1-20260427-091655` (old unit/env), `stage2-20260427-091758`,
  `stage3-20261003-152317` (`uEnv.txt` backup), `stage3b-20261003-152434`; plus `/boot/uEnv.txt.bak-before-uart4`.
  (The `20260427` in two names is the wrong BBB clock at the time, not a real date.)
* From the Mac, in `~/bbb-release`: `bash bbb_stage.sh rollback1|rollback2|rollback3`. On the BBB:
  `sudo bash /home/debian/releases/bbb_apply.sh rollbackN`. Mac files: `~/bbb-release/{bbb_stage.sh,bbb_apply.sh,release-305b982.tgz}`.
  Pre-deploy read-only snapshot: Mac `~/bbb-snapshots/2026-10-03-pre-deploy/`.
* Generic procedure: section 5.2 and `docs/bbb_deploy_rollback.md`.

### Known issues after the deploy

* BBB journal is 545 MB and unbounded (capping it needs approval).
* The clock helper has not been tested live with no GPS fix.
* BeagleY Wi-Fi dropouts (above).
* UNO TX is not wired, so serial inputs read 0 frames; fuel, coolant and rpm are uncalibrated; the UNO sketch pins are
  unverified on hardware.
* No `can0` and no `can_signals.json` on the BBB (the CAN prep work is merged in the repo, v0.2.0, but not deployed).

---

## 6. Known issues (as of 2026-10-03)

| Issue | Detail | Source |
| --- | --- | --- |
| BBB clock wrong | Shows Apr 2026, RTC reads 2000-01-01, not synchronized, and the BBB link has no internet. Journal and fault-recorder timestamps are unreliable until fixed. The BeagleY has no chrony/ntpd (systemd-timesyncd only), so it cannot serve time. **Fixed 2026-10-03 15:22 AEST** by the `bbb-gps-clock` service (GPS time; see "Deployed board state"); earlier journal and fault-recorder timestamps stay wrong. | **VERIFIED (HW 2026-10-03)** |
| BeagleY has no NTP daemon | Yocto image; `systemd-timesyncd` only, no `chrony`/`ntpd`. | **VERIFIED (HW 2026-10-03)** |
| New hub features deployed (was: not deployed) | PR #30 (GPS-first speed, `VEHICLE_SPEED_SOURCE`, `_health.speedSource`) is merged and **live on the BBB since 2026-10-03 ~15:17 AEST (release 305b982)**; the hub log shows speed source `gps_first`. Bench checklist: [bench_test_checklist.md](bench_test_checklist.md); UNO firmware: [../firmware/uno_vehicle_input/](../firmware/uno_vehicle_input/README.md). | REPO (deployed state **VERIFIED (HW 2026-10-03)**) |
| journald unbounded on BBB | 545 MB used (2026-10-03 15:55 AEST; was 558 MB). A limits drop-in (`tools/bbb_hub/journald-beagley.conf`) is in the repo; not installed (capping needs approval). | **VERIFIED (HW 2026-10-03)** |
| ttyS mismatch (resolved) | GPS on `/dev/ttyS1` (UART1). UART4 is now **enabled** (overlay added 15:23 AEST, BBB rebooted, `/dev/ttyS4` exists) and the hub reads `/dev/ttyS4` @115200 as the UNO input. UART2/`ttyS2` is enabled but unused (RX pin P9_22 damaged). The older docs and `bbb-hardware-gps.env.example` that said GPS = `ttyS4` were wrong and are corrected. Still open: nothing is wired to UART4 (0 frames) and the pin-mux (`config-pin -q P9_11`) was not queried. | **VERIFIED (HW 2026-10-03)** (enabled/present); wiring and pin-mux **UNKNOWN** |
| No CAN | No `can0`, no `can_signals.json` on the BBB. | **VERIFIED (HW 2026-10-03)** |
| BBB deployed code is old | Not a git checkout, older than the repo. Repo behaviour and tests do not describe what runs. | **VERIFIED (HW 2026-10-03)** |
| BeagleY unreachable from Elitebook | Likely Wi-Fi client isolation. Builds can still be done on the Elitebook, but pushing to the board goes via the Mac. | **VERIFIED (HW 2026-10-03)** |
| BeagleY IP changes | DHCP. Drifted `192.168.1.100` (2026-09-20) -> `192.168.1.111` (2026-10-03). Hard-coded IPs in docs and skills (`192.168.0.92` etc.) are stale. | **VERIFIED (HW 2026-10-03)** |
| Stale hub address | `192.168.0.x` hub values are hotspot-era. Canonical is `10.24.0.7`. The vehicle-hub repo `PROTOCOL.md` is legacy. | REPO (`docs/ENVIRONMENT.md`) |
| Root fs 95% full | BeagleY `/dev/root`: 847.8 MB, 751.6 MB used, **35.5 MB free** (read 2026-10-03). `/opt` and `/etc` live there, so anything that writes to `/` (e.g. `/usr/bin` in a binary deploy) has very little headroom. `/var/volatile` is RAM. `/data` (mmcblk1p3) has 27.5 GB, 1.7 GB used, **24.4 GB free**: put runtimes, backups and screenshots on `/data`. | **VERIFIED (HW 2026-10-03)** |
| Deployed binary is not the default branch | `$RUNTIME/bin/beagley_cluster` -> `/data/beagley-cluster/runtime-drive-adaptive-1371e7f299fd/bin/beagley_cluster`. Journal `[BUILD]`: branch `development/drive-adaptive-feeds-20260913`, commit `1371e7f299fd`, clean, built 2026-09-13T10:27:42Z. It is **not** built from `codex/maplibre-native-yocto-build`: `strings` finds no `linkLost` in it (PR #23's LINK LOST telltale and dashes cannot show with any QML) and it carries the older font set. Verifying fonts, link-lost or the dark map from the default branch needs a **new aarch64 binary** (Elitebook/CI) and a **binary deploy with a snapshot** (`skills/beagley-deploy/scripts/deploy.sh`, section 4), not a QML sync. | **VERIFIED (HW 2026-10-03)** |
| `main` is unrelated history | Port changes by hand; do not merge across. `legacy-main-2026-10-03` branch exists. | REPO (`README.md`) |

---

## 7. Open questions (for ThatGuy and owners)

**ThatGuy**

1. Standing rule for approvals: is a PR comment enough, or do you want chat
   sign-off per deploy? `sudo` on the BBB needs your password (except
   `bbb-bench-sim`): will you run hub restarts yourself, or approve a narrow
   sudoers rule for `systemctl restart bbb-hardware-gps`?
2. Should the BBB clock fix go ahead, and when? Option A (chrony from the
   BeagleY) is out because the BeagleY has no chrony; the GPS-time fix was
   deployed 2026-10-03 (done, see "Deployed board state").
3. `bbb-bench-sim` is installed (state `disable`). Who is allowed to enable it, and how is the state checked before a real-vehicle test?

**Chief of Staff (Wi-Fi)**

4. Can the BeagleY get a DHCP reservation (or a stable name) so the IP stops
   moving? Is Wi-Fi client isolation on the VX network intended, and can the
   Elitebook be allowed through?

**Platform DevOps / Yocto owners**

5. Image rollback: are previous release images retained, is there an A/B slot,
   what state survives a re-flash, who flashes? (5.3)
6. ~~Does the board's deployed binary support `BEAGLEY_QML_DEV_ROOT`?~~
   **Answered (VERIFIED (HW 2026-10-03)): yes**, the live display uses it, but
   only with C++/fonts from the same build (3.1). Still open: where is the
   master copy of `SkinShowOverride.qml`?
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
13. ~~After PR #19 merges: update 3.3/5.2~~ PR #19 is merged and the docs/tool exist; the unit is `Type=notify` on the board since the 2026-10-03 deploy. Remaining: re-read 3.3/5.2 against `docs/bbb_deploy_rollback.md` once more.

---

*Maintenance:* update the evidence tags when someone verifies an item.
Re-verify **VERIFIED (HW 2026-10-03)** facts after any hardware, network or
image change.
