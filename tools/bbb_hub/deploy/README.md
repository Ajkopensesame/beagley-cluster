# Staged BBB deploy scripts (hub update, clock fix, UART4)

Run from the Mac, one stage at a time; each stage ends with a health check and rolls itself back if unhealthy.
Everything read-only and every dry run happens before the one privileged step, which uses `ssh -t` so the
BBB `debian` sudo password is typed by a person.

    cd ~/bbb-release
    bash bbb_stage.sh stage1      # hub update (new release dir, dry run on port 8799, then switch)
    bash bbb_stage.sh stage2      # clock fix from GPS time: installs bbb-gps-clock.service on the BBB (no BeagleY changes)
    bash bbb_stage.sh stage3      # UART4 overlay + BBB reboot + VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4
    bash bbb_stage.sh rollbackN   # undo stage N from the newest backup (rollback3 reboots)

Files: `bbb_stage.sh` (Mac side), `bbb_apply.sh` (runs on the BBB as root; read it first),
`release-<sha>.tgz` (tools/ subset of the repo at that commit). Context: `docs/bbb_deploy_plan_2026-10-03.md`.

Stage 2 (clock) needs stage 1 done with a release that contains `tools/bbb_hub/gps_clock.py` and
`bbb-gps-clock.service`. It runs `gps_clock.py --once --dry-run` read-only first, then installs and enables the service
(runs as `debian` with only `CAP_SYS_TIME`), waits up to 120 s for a `stepped clock` line, and does NOT fail if there is no GPS
fix yet (it sets the clock when a fix arrives). Check later on the BBB: `date; journalctl -u bbb-gps-clock -n 20 --no-pager`.
The old stage 2 (timesyncd against a BeagleY NTP server) is gone: the BeagleY has no chrony or ntpd.
The board-side `tar` uses `-m` because the BBB clock is in the past (no "time stamp is in the future" flood).

The stage scripts were dry-run tested locally (hub start + health check, stubbed `bbb_apply.sh stage2`) but stage 2 has NOT been run against the board.
