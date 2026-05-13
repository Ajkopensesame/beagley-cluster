# Beagley Appliance Build

This directory contains the embedded appliance path for the Beagley cluster.

The production target is a Yocto image built on top of TI Processor SDK Linux
11.00 for J722S/AM67A. The layer in
`yocto/meta-beagley-cluster` adds the cluster application, the staged GPU-probe
and app systemd services, and the image recipe used for release images.

For boot-failure diagnosis there is also a dedicated image target:

- `beagley-cluster-image-diag`

That image keeps the same BeagleY boot payload as production, but switches the
kernel args and service behavior into a verbose diagnostic mode.

## Expected workflow

1. Bootstrap a TI Processor SDK Linux 11.00 workspace on a Linux host or VM.
2. Build the appliance on the BeagleY BSP path:
   - `MACHINE_POLICY=board-bsp`
   - `MACHINE=beagley-ai`
3. Let `yocto/build-appliance-image.sh` validate the deploy artifacts before packaging.
4. Run `yocto/build-appliance-image.sh`.
5. Flash the packaged release image from `build-*/release/...` to the production boot media.

## Quick start

```bash
./yocto/run-builder-container.sh

# inside the container
cd /workspace/beagley-cluster
./yocto/bootstrap-ti-sdk.sh /work/ti-sdk-11.00

MACHINE_POLICY=board-bsp MACHINE=beagley-ai \
  ./yocto/build-appliance-image.sh /work/ti-sdk-11.00/yocto-build build-beagley
```

If the TI SDK checkout already contains `meta-ti/meta-beagle/conf/machine/beagley-ai.conf`,
both build helpers default to `MACHINE=beagley-ai` and `MACHINE_POLICY=board-bsp`
automatically.

The Docker helper creates a repeatable Ubuntu 22.04 builder image and mounts:

- the repo at `/workspace/beagley-cluster`
- TI workspace state on a Docker-managed Linux volume at `/work/ti-sdk-11.00`
- shared `downloads` and `sstate-cache` under `.yocto-work`

The TI workspace and build tree are kept on a Docker volume, not the macOS
filesystem, because BitBake's Unix socket handling is not reliable on a bind
mount backed by Docker Desktop's host file sharing.

## macOS builder path

For the supported Mac-specific path, keep the repo on the internal SSD but move
Docker Desktop's disk image plus Yocto caches onto a dedicated external APFS
SSD. The expected layout is:

- Docker Desktop `DataFolder`: `/Volumes/BeagleyBuilder/DockerDesktop`
- downloads cache: `/Volumes/BeagleyBuilder/beagley-cache/downloads`
- sstate cache: `/Volumes/BeagleyBuilder/beagley-cache/sstate-cache`
- TI workspace: Docker volume `beagley-ti-sdk-11-workspace`

Use the Mac-specific helper instead of `run-builder-container.sh`:

```bash
./yocto/run-mac-docker-build.sh
```

This path:

- validates the external APFS volume with `diskutil verifyVolume`
- requires a dedicated SSD with at least `900 GiB` total capacity
- checks free space and Docker Desktop settings
- requires at least `500 GiB` free before launching the build
- can run a write/read SSD smoke test before the build
- locks Docker Desktop to the repo's Mac build defaults
- launches the Yocto build with `YOCTO_RESOURCE_PROFILE=moderate-memory`
- starts a watchdog that stops the build on Docker storage I/O errors
- keeps the Mac awake with `caffeinate` while the build runs

Environment overrides:

- `MACHINE`
- `MACHINE_POLICY`
- `IMAGE`
- `BEAGLEY_CLUSTER_GIT_BRANCH`
- `YOCTO_RESOURCE_PROFILE`
- `YOCTO_BITBAKE_RETRIES`
- `YOCTO_GIT_FETCH_RETRIES`
- `YOCTO_DL_DIR`
- `YOCTO_SSTATE_DIR`
- `BEAGLEY_SOURCE_REMOTE`
- `BEAGLEY_REQUIRE_REMOTE_REF`
- `BEAGLEY_ALLOW_DIRTY_SOURCE`

## Source provenance guard

Production Yocto builds are gated before `bitbake` starts. The helper verifies
that the Yocto layer resolves to the expected repo, `local.conf` builds the
expected `BEAGLEY_CLUSTER_GIT_BRANCH`, the build repo is clean, and the branch
tip in `BEAGLEY_SOURCE_REMOTE` matches the exact local commit.

If `BEAGLEY_CLUSTER_GIT_BRANCH` is not set, the appliance helper uses the
current checkout branch and only falls back to `main` when Git cannot report a
branch.

The default `BEAGLEY_SOURCE_REMOTE` is
`https://github.com/Ajkopensesame/beagley-cluster.git`. Set
`BEAGLEY_ALLOW_DIRTY_SOURCE=1` only for explicit local experiments; dirty source
is refused by default because BitBake fetches committed Git refs, not
worktree-only edits. Set `BEAGLEY_REQUIRE_REMOTE_REF=0` only for an intentional
offline build.

For a preflight check from the Mac against the EliteBook builder, run:

```bash
skills/beagley-build-source-guard/scripts/check.sh
```

Resource profiles:

- `balanced`: 4-way build parallelism for roomy Linux builders
- `moderate-memory`: 2-way build parallelism for constrained builders that
  cannot safely sustain full balanced mode
- `low-memory`: 1-way build parallelism for the most constrained fallback path

For a final Mac-based attempt on an 8 GB machine, prefer `moderate-memory`
instead of `low-memory`. It is still conservative, but materially faster than
serial compilation without jumping straight to the 4-way `balanced` profile.

Mac-specific entrypoints:

- `yocto/check-mac-builder.sh`
- `yocto/watch-mac-build.sh`
- `yocto/run-mac-docker-build.sh`

When the BeagleY BSP is present, `MACHINE_POLICY=board-bsp` and
`MACHINE=beagley-ai` are the supported production defaults. The helper only
falls back to `MACHINE_POLICY=ti-sdk` and `MACHINE=j722s-evm` when that BSP is
absent.

The build helper also installs a retrying `FETCHCMD_git` wrapper so large
upstream git repos can recover from transient network failures without changing
the resulting image contents. BitBake retries are limited to recent fetch
failures so deterministic compile or configuration errors still fail fast.

After `bitbake` completes, `yocto/build-appliance-image.sh` now validates the
flash bundle before packaging. The validation fails the build if the deploy
directory is missing BeagleY boot artifacts, if the `beagley-cluster` package is
missing `/usr/bin/beagley_cluster` or its systemd units, or if the image lacks
SSH or a GPU probe prerequisite such as `kmscube`.

For `MACHINE=beagley-ai`, the boot contract is now a dual-path BeagleY image.
The build emits:

- `extlinux/extlinux.conf` with an explicit `ti/k3-am67a-beagley-ai.dtb`
- `EFI/BOOT/bootaa64.efi` and `EFI/BOOT/grub.cfg`
- `uEnv.txt` that also sets `fdtfile=ti/k3-am67a-beagley-ai.dtb`
- a boot payload contract that includes `Image` and the BeagleY DTB on the
  boot partition

The diagnostic image also validates that both boot paths carry the verbose
console args, including `console=tty1` and `beagley.diag=1`.

## Release output

After a successful `bitbake`, the helper packages a flashable release under:

- `build-*/release/<image>-<machine>-<timestamp>/`

Each release directory includes:

- the `wic` image
- the `wic.bmap` file
- the Yocto rootfs manifest
- the build validation report
- `image-manifest.txt`
- `SHA256SUMS`
- `flash-instructions.md`

## First-boot provisioning

Optional boot-partition overrides:

- `beagley-cluster.env`
- `beagley-cluster.hostname`

These are copied into the appliance on boot by `beagley-cluster-provision.service`
before the GPU probe and app services start.

## Runtime bring-up

The appliance now brings the board up in two stages:

1. `beagley-cluster-gpu-probe.service` runs `beagley-gpu-gate` during boot,
   records pass/fail details under `/run/beagley_gpu_gate.status`, and keeps the
   OS reachable even when the renderer is wrong.
2. `beagley_cluster.service` starts only if the probe produced
   `/run/beagley_gpu_gate.ok`, then re-runs the strict gate before launching the
   full-screen app.

This keeps SSH and logs available for diagnosis while still preventing the UI
from running on `llvmpipe`, `swrast`, or any other software renderer.

In `beagley-cluster-image-diag`, the appliance and GPU-probe services are
explicitly suppressed, while `beagley-diagnostic-*` services leave stage
markers and snapshots under `/var/lib/beagley-cluster/diagnostic` and, when
possible, on the FAT boot partition under `beagley-diag/`.

## macOS flashing

If you package a release on a Linux builder and want to flash it from macOS:

```bash
./yocto/flash-appliance-image-macos.sh \
  build-beagley/release/<image>-<machine>-<timestamp> \
  /dev/diskN
```

## Linux flashing

If you are flashing directly from a Linux builder such as the EliteBook:

```bash
./yocto/flash-appliance-image-linux.sh \
  build-beagley/release/<image>-<machine>-<timestamp> \
  /dev/sdX
```
