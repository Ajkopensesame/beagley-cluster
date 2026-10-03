# Staged BBB deploy scripts (hub update, clock fix, UART4)

Run from the Mac, one stage at a time; each stage ends with a health check and rolls itself back if unhealthy.
Everything read-only and every dry run happens before the one privileged step, which uses `ssh -t` so the
BBB `debian` sudo password is typed by a person.

    cd ~/bbb-release
    bash bbb_stage.sh stage1      # hub update (new release dir, dry run on port 8799, then switch)
    bash bbb_stage.sh stage2      # clock fix, BeagleY serves time over eth0 (stops if chrony is absent on the BeagleY)
    bash bbb_stage.sh stage3      # UART4 overlay + BBB reboot + VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4
    bash bbb_stage.sh rollbackN   # undo stage N from the newest backup (rollback3 reboots)

Files: `bbb_stage.sh` (Mac side), `bbb_apply.sh` (runs on the BBB as root; read it first),
`release-<sha>.tgz` (tools/ subset of the repo at that commit). Context: `docs/bbb_deploy_plan_2026-10-03.md`.
The stage scripts were dry-run tested locally (hub start + health check) but NOT yet run against the board.
