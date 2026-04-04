# Beagley 60 FPS Appliance Path

This repo now contains the production pivot away from the drifting Debian
desktop workflow.

## Production shape

- OS: Yocto appliance image built from TI Processor SDK Linux 11.00
- Graphics: `eglfs` + `eglfs_kms`
- UI entrypoint: `MainEmbedded.qml`
- Map path: native online raster map via `NativeRasterMapItem`
- Perf source: `PerformanceMetrics`
- Replay harness: `BEAGLEY_REPLAY_FILE`

## Build contracts

- Embedded appliance builds should use:
  - `-DBEAGLEY_APPLIANCE_PRODUCTION=ON`
  - `-DWITH_WEBENGINE=OFF`
- Embedded runtime defaults should use:
  - `BEAGLEY_UI_VARIANT=embedded`
  - `BEAGLEY_RENDER_PROFILE=embedded`
  - `BEAGLEY_EFFECT_LEVEL=low`
  - `BEAGLEY_MAP_RENDERER=native-online`
  - `QT_QPA_PLATFORM=eglfs`
  - `QT_QPA_EGLFS_INTEGRATION=eglfs_kms`

## Repo entrypoints

- Yocto layer: [yocto/meta-beagley-cluster](/Users/joshkomant/projects/beagley-cluster/yocto/meta-beagley-cluster)
- Yocto helper: [yocto/build-appliance-image.sh](/Users/joshkomant/projects/beagley-cluster/yocto/build-appliance-image.sh)
- Mac preflight: [yocto/check-mac-builder.sh](/Users/joshkomant/projects/beagley-cluster/yocto/check-mac-builder.sh)
- Mac watchdog: [yocto/watch-mac-build.sh](/Users/joshkomant/projects/beagley-cluster/yocto/watch-mac-build.sh)
- Mac launcher: [yocto/run-mac-docker-build.sh](/Users/joshkomant/projects/beagley-cluster/yocto/run-mac-docker-build.sh)
- Embedded launcher: [tools/beagley_gpu/run_embedded_with_gate.sh](/Users/joshkomant/projects/beagley-cluster/tools/beagley_gpu/run_embedded_with_gate.sh)
- Perf replay docs: [tools/perf/README.md](/Users/joshkomant/projects/beagley-cluster/tools/perf/README.md)
- Release packager: [yocto/package-appliance-release.sh](/Users/joshkomant/projects/beagley-cluster/yocto/package-appliance-release.sh)

## Mac builder contract

- Dedicated external APFS SSD mounted as `BeagleyBuilder`
- Preflight requires at least `900 GiB` total SSD capacity and `500 GiB` free
- Docker Desktop `DataFolder` on that SSD
- Yocto `downloads` and `sstate-cache` on that SSD
- TI workspace inside Docker volume `beagley-ti-sdk-11-workspace`
- Mac build profile uses `YOCTO_RESOURCE_PROFILE=moderate-memory`
- `watch-mac-build.sh` stops the build on Docker storage I/O errors

## Validation targets

- hardware EGL active on first boot
- no production `Canvas` paint loops
- replay-driven perf checks emit `[Perf]` with fps, p95, p99, and map counters
- production image reaches Linux/network/SSH even when the GPU probe fails
- `beagley-cluster.service` starts only after a passing GPU probe

## Appliance contract

- Production build defaults to the BeagleY BSP path with `MACHINE=beagley-ai`
- Build helpers fall back to `MACHINE_POLICY=ti-sdk` only if the BeagleY BSP is absent
- BeagleY boot media uses U-Boot distro boot with `extlinux`, not the generic EFI/GRUB path
- The boot partition carries an explicit `k3-am67a-beagley-ai.dtb` selection in both `extlinux.conf` and `uEnv.txt`
- `beagley-cluster-gpu-probe.service` records the first-boot renderer result under `/run`
- `beagley-cluster.service` starts only when `/run/beagley_gpu_gate.ok` exists
- `beagley-cluster-launch.sh` re-enforces `gpu_gate.sh --strict --mode appliance`
- `beagley-cluster-provision.service` applies optional boot-media overrides
- Release output is a flashable `wic` bundle with checksum, manifest, and validation report
- The tracked flash helpers are `yocto/flash-appliance-image-linux.sh` and `yocto/flash-appliance-image-macos.sh`
