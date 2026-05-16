# Beagley GPU Stack Contract

This project now treats embedded rendering as a gated contract.

For production, the supported path is now the Yocto appliance image. Debian-side
bridge repair remains a diagnostics workflow only.

- Beagley production defaults to `BEAGLEY_MAP_RENDERER=maplibre-native` with a
  probed, allowlisted style.
- WebEngine map is desktop/debug only.
- Embedded launch can require a hardware GPU gate pass file before app start.

## Runtime Defaults

- `BEAGLEY_RENDER_PROFILE=embedded`
- `BEAGLEY_EFFECT_LEVEL=low`
- `BEAGLEY_GAUGE_DETAIL=safe`
- `BEAGLEY_GAUGE_DEMO=0`
- `BEAGLEY_MAP_RENDERER=maplibre-native`
- `QSG_RENDER_LOOP=basic`
- `BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL=https://tiles.openfreemap.org/styles/positron`
- `BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES=https://tiles.openfreemap.org/styles/positron`
- `BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=0`
- `BEAGLEY_MAP_BOOT_MODE=staged`
- `BEAGLEY_MAP_STYLE_MODE=embedded`

## Debian Debug Workflow

These scripts remain available for debugging a drifted Debian image, but they are
not the production install path:

1. Build the TI SGX bridge package from the Mesa bridge artifacts:
```bash
/home/debian/projects/beagley-cluster/tools/beagley_gpu/build_pvr_dri_gbm.sh
/home/debian/projects/beagley-cluster/tools/beagley_gpu/build_pvr_bridge_package.sh \
  --install
```

2. Bootstrap a drifted image in place and generate the first pinned cohort lock:
```bash
sudo /home/debian/projects/beagley-cluster/tools/beagley_gpu/repair_in_place.sh \
  --bridge-deb /usr/local/share/beagley/packages/$(ls /usr/local/share/beagley/packages/beagley-pvr-bridge_*.deb | tail -n 1) \
  --lock /etc/beagley-gpu-cohort.lock \
  --write-ok /tmp/beagley_gpu_gate.ok \
  --apply-hold
```

3. Reinstall to the pinned cohort and gate it on subsequent repairs:
```bash
sudo /home/debian/projects/beagley-cluster/tools/beagley_gpu/reinstall_and_gate.sh \
  --lock /etc/beagley-gpu-cohort.lock \
  --write-ok /tmp/beagley_gpu_gate.ok \
  --apply-hold
```

4. Launch embedded UI with mandatory gate:
```bash
/home/debian/projects/beagley-cluster/tools/beagley_gpu/run_embedded_with_gate.sh
```

5. Install the production systemd unit so startup is fail-closed:
```bash
sudo /home/debian/projects/beagley-cluster/tools/beagley_gpu/install_production_service.sh \
  --project-root /home/debian/projects/beagley-cluster \
  --enable-now
```

6. Launch embedded UI with automatic fallback (field recovery only, not production):
```bash
/home/debian/projects/beagley-cluster/tools/beagley_gpu/run_embedded_auto.sh
```

## Bridge Compatibility

The SGX DRI bridge must match the Mesa userspace ABI on the image.

- Building the bridge from `powervr/24.0.1` against a board running
  `mesa-libgallium 25.0.5-*` is not a supported production combination.
- The observed failure mode on the Beagley is:
  - `eglinfo -B` falls back to `kms_swrast`
  - Mesa debug logs show `using driver pvr` followed by `DRI2: failed to load driver`
- `tools/beagley_gpu/build_pvr_dri_gbm.sh` now fails fast on a mismatched Mesa
  major.minor series unless `--allow-version-mismatch` is explicitly provided.

If the distro image carries a Mesa series newer than the available PowerVR bridge
branch, the long-term production answer is a matched appliance image, not a forced
mixed-stack install.

## Appliance Production Gate

The supported appliance base is the TI SDK Linux 11.00 Yocto flow with the
BeagleY BSP enabled through `MACHINE_POLICY=board-bsp` and `MACHINE=beagley-ai`.
If that BSP is missing from a given SDK checkout, the build helpers can still
fall back to `j722s-evm`, but that is no longer the preferred production path.

For BeagleY production images, the supported boot contract is the non-EFI
U-Boot distro-boot path with `extlinux` and an explicit
`ti/k3-am67a-beagley-ai.dtb`. The generic EFI/GRUB path is not the production
boot contract for this appliance because it can fall back to the default
`j722s-evm` runtime tree.

The appliance launch path uses:

```bash
/usr/bin/beagley-gpu-gate --strict --mode appliance
```

In appliance mode the gate requires:

- hardware EGL renderer
- `pvrsrvkm` loaded
- a PowerVR/PVR renderer string

It does not require the Debian bridge package or cohort lock.

## Gate Rules

`tools/beagley_gpu/gpu_gate.sh` fails if any of these conditions are true:

- `eglinfo -B` reports `llvmpipe`/`swrast`/software renderer.
- `pvrsrvkm` kernel module is not loaded.
- strict mode does not find the managed bridge package-owned files:
  - `/usr/lib/aarch64-linux-gnu/dri/sgx_dri.so`
  - `/usr/lib/aarch64-linux-gnu/dri/pvr_dri.so`
  - `/usr/lib/aarch64-linux-gnu/dri/tidss_dri.so`
  - `/usr/lib/aarch64-linux-gnu/gbm/pvr_gbm.so`
- strict mode lock-check finds a package version mismatch.
- strict mode lock file is missing.

When `--write-ok` is provided, it writes a pass marker consumed by app startup:

- `status=pass`
- renderer string
- timestamp

The Yocto appliance now runs this in two stages:

- `beagley-cluster-gpu-probe.service` runs the strict appliance gate during boot,
  writes `/run/beagley_gpu_gate.status`, and leaves the OS reachable on failure.
- `beagley_cluster.service` only starts when `/run/beagley_gpu_gate.ok` exists,
  then re-runs the strict gate before launching the app.

When software rendering is detected and `pvrsrvkm` is loaded, gate output now includes
missing SGX bridge files (for example `sgx_dri.so` / `pvr_gbm.so`) so mixed-stack
issues are explicit instead of silent.

## App-Level Enforcement

- Startup gate input file: `BEAGLEY_GPU_GATE_FILE` (default `/tmp/beagley_gpu_gate.ok`).
- Gate enable flag: `BEAGLEY_REQUIRE_GPU_GATE` (defaults to enabled when embedded platform is requested).
- On gate failure the app exits early with a non-zero code and logs `[GPU-GATE] failed`.

## Production Service Contract

- Systemd unit: `beagley_cluster.service`
- Yocto boot probe unit: `beagley-cluster-gpu-probe.service`
- Yocto launch wrapper: `/usr/bin/beagley-cluster-launch.sh`
- Production must not launch the cluster with `BEAGLEY_REQUIRE_GPU_GATE=0`
