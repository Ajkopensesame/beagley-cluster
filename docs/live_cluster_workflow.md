# Live Cluster Workflow

Use this path when the physical BeagleY display must match the final runtime.
The BeagleY app should not fake vehicle data in this mode. It should render the
same `vehicle_state` stream that production will receive from the BBB.

## Runtime Shape

Source of truth:

```text
UNO/CAN/bench sim -> BBB vehicle_state hub -> BeagleY cluster UI
hardware GPS ----^                         -> live native-online maps
```

The BeagleY production-like profile is:

```text
BEAGLEY_UI_VARIANT=v3
BEAGLEY_RENDER_PROFILE=embedded
BEAGLEY_MAP_RENDERER=native-online
BEAGLEY_REPLAY_LOOP=0
BEAGLEY_STRESS_SCENE=0
VEHICLE_HUB_WS_URL=ws://10.24.0.7:8765
```

Do not set `BEAGLEY_REPLAY_FILE` for live-cluster UI work. App-side replay and
`BEAGLEY_STRESS_SCENE=1` are useful for demos, but they do not exercise the
production data path.

## BeagleY: Enter Live Cluster Profile

```bash
cd /Users/joshkomant/projects/beagley-cluster
tools/ui/beagley_live_cluster_profile.sh --effect-level high
```

Use `--effect-level low` when checking the current performance-safe profile.
Use `--metrics` only while measuring FPS.

## BBB: Bench Vehicle Inputs With Real GPS

Install the BBB toggle once:

```bash
cd /home/debian/projects/beagley-cluster
tools/bbb_hub/install_bbb_bench_sim_toggle.sh
```

After that, the source-of-truth switch is the BBB service mode:

```bash
sudo bbb-bench-sim status
sudo bbb-bench-sim enable
sudo bbb-bench-sim disable
```

From the Mac, the same commands can be run through the stable SSH alias:

```bash
ssh bbb 'sudo bbb-bench-sim status'
ssh bbb 'sudo bbb-bench-sim enable'
ssh bbb 'sudo bbb-bench-sim disable'
```

The direct repo script is also available on the BBB:

```bash
cd /home/debian/projects/beagley-cluster
tools/bbb_hub/bbb_bench_vehicle_sim.sh enable
```

This keeps the BBB hardware GPS path active, but synthesizes vehicle-like
fields upstream of the BeagleY:

- speed
- rpm
- fuel
- coolant
- gear and overdrive
- turn indicators and high beam
- VIC warnings
- drivetrain mode and transfer lock

Disable it when real UNO/CAN/serial inputs are ready:

```bash
sudo bbb-bench-sim disable
```

## UI Iteration

For current QML work, keep `BEAGLEY_QML_DEV_ROOT=/opt/beagley-cluster/qml-dev`
enabled on the BeagleY and sync QML after edits:

```bash
tools/ui/beagley_sync_qml.sh
```

That keeps rendering on the physical BeagleY display while avoiding a full
Yocto build for every UI tweak. When the UI is accepted, package the same QML
through the EliteBook/Yocto aarch64 build and disable QML-dev for final release
validation.
