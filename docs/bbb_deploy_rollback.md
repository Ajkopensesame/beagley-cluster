# BBB / BeagleY deploy and rollback runbook (DRAFT for review)

Owner of process: Platform DevOps. Contributed by Hardware Integration from the repo review; items marked
**TO CONFIRM** depend on the live boards, which have not been audited yet.

**Rules.** No deploy, restart, overlay, boot-image or Wi-Fi change without explicit approval from Cluster Lead
(who gets ThatGuy's approval). Read-only inspection is always allowed. The BeagleY Wi-Fi config is owned by Chief of Staff.

## Current state (as found in the repo)

* BBB runs the hub from a git checkout `/home/debian/projects/beagley-cluster` via `tools/bbb_hub/bbb-hardware-gps.service`
  (`run_prod.sh` -> `vehicle_hub_prod.py`), env from `/etc/default/bbb-hardware-gps`. **TO CONFIRM** the unit is installed and enabled.
* No versioning of what is running, no post-deploy check, no documented rollback.

## Proposed BBB hub procedure

**0. Preconditions.** CI green on the commit (required check `Configure + build (WITH_WEBENGINE=OFF)` plus Python tests).
Approval recorded. Car/bench in a state where a ~10 s gauge blackout is acceptable.

**1. Record current state (read-only).**
`cd /home/debian/projects/beagley-cluster && git rev-parse HEAD`, `systemctl cat bbb-hardware-gps`,
`cat /etc/default/bbb-hardware-gps`, `journalctl -u bbb-hardware-gps -n 50`, and
`python3 tools/bbb_hub/check_hub_health.py ws://10.24.0.7:8765 --require-gps`. Save the output as the rollback reference.

**2. Stage, do not switch.** Put the new revision in `/home/debian/releases/<git-sha>/` (`git worktree add` or `git archive`),
create its venv or reuse the existing one (`websockets` must match the board: 10.4). Run
`python3 -m pytest tests -q` there. Nothing is running from it yet.

**3. Deploy order matters.** Hub code that speaks `sd_notify` must be in place **before** the unit that says
`Type=notify`/`WatchdogSec` is installed, otherwise systemd kills the old code after the start/watchdog timeout.
Order: code, then env changes, then unit, then `systemctl daemon-reload`, then `systemctl restart bbb-hardware-gps`.

**4. Switch.** Point `/home/debian/current` at the new release (`ln -sfn`) once the unit paths use `current`
(one-time migration from the git checkout path), then restart the hub only. Do not touch the BeagleY, Wi-Fi or other services.

**5. Verify (within 60 s).**
`python3 tools/bbb_hub/check_hub_health.py ws://10.24.0.7:8765 --require-gps [--require-serial]` must print `OK`;
`systemctl status bbb-hardware-gps` active; `journalctl -u bbb-hardware-gps -n 30` has no tracebacks; the cluster on the
BeagleY reconnects and shows live data.

**6. Roll back (if verify fails or anything looks wrong).**
`ln -sfn <previous release> /home/debian/current` (or restore the previous unit and `/etc/default/bbb-hardware-gps` copies saved in step 1),
`systemctl daemon-reload && systemctl restart bbb-hardware-gps`, re-run the health check. Rollback uses only files saved in step 1,
so it works without network access.

**Config-only rollbacks** (no code change): set `VEHICLE_SENSOR_CALIBRATION=/nonexistent.json`, unset `VEHICLE_INPUT_SERIAL_DEVICE`,
unset `CAN_LIVE_INTERFACE`, then restart the hub.

**Journal limits.** Install `tools/bbb_hub/journald-beagley.conf` as `/etc/systemd/journald.conf.d/10-beagley-limits.conf`
and restart `systemd-journald` (also an approved deploy step).

**UART/overlay changes** (UART4, CAN0) need a reboot of the BBB: copy `/boot/uEnv.txt` first, change one overlay at a time,
reboot, health-check; roll back by restoring the copy and rebooting.

## BeagleY (cluster app) **TO CONFIRM**

Not yet audited. Needed from Platform DevOps / Yocto owners: how the cluster app and image are updated (Yocto image vs. file copy),
whether the image has an A/B or fallback slot, how to reach the board (it is reachable from the Mac only, address changes;
discover via `dns-sd -G v4 beagley-ai.local`), the `beagley_cluster.service` rollback path, and the GPU/touch gate behaviour
on failure. Do not alter boot images or Wi-Fi without approval.

## Open items

1. Read-only audit of the live BBB (blocked: no key/route to the BBB).
2. Migrate the unit to a release-dir layout (`/home/debian/releases/<sha>`, `current` symlink).
3. Decide who runs deploys and how approval is recorded.
