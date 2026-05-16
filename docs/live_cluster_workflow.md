# Live Cluster Workflow

Use this path when the physical BeagleY display must match the final runtime.
The BeagleY app should not fake vehicle data in this mode. It should render the
same `vehicle_state` stream that production will receive from the BBB.

## Runtime Shape

Source of truth:

```text
UNO/CAN/bench sim -> BBB vehicle_state hub -> BeagleY cluster UI
hardware GPS ----^                         -> live MapLibre Native maps
```

The BeagleY production-like profile is:

```text
BEAGLEY_UI_VARIANT=v3
BEAGLEY_RENDER_PROFILE=embedded
BEAGLEY_EFFECT_LEVEL=low|high
BEAGLEY_GAUGE_DETAIL=safe|rich
BEAGLEY_GAUGE_DEMO=0|1
BEAGLEY_MAP_RENDERER=maplibre-native
BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL=https://tiles.openfreemap.org/styles/positron
BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES=https://tiles.openfreemap.org/styles/positron
BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=0
BEAGLEY_REPLAY_LOOP=0
BEAGLEY_STRESS_SCENE=0
VEHICLE_HUB_WS_URL=ws://10.24.0.7:8765
```

`BEAGLEY_EFFECT_LEVEL` controls global effect budget and map/compositor safety.
`BEAGLEY_GAUGE_DETAIL` controls gauge richness separately:

- `safe`: gauges follow the global effect budget.
- `rich`: gauges show the full ticks, lens, arcs, chevrons, and gauge detail
  while the map can stay on a conservative profile.

`BEAGLEY_GAUGE_DEMO=1` is only for visual review of telltales and gauge
readouts. It does not enable app replay or change the BBB vehicle-state source.

Do not set `BEAGLEY_REPLAY_FILE` for live-cluster UI work. App-side replay and
`BEAGLEY_STRESS_SCENE=1` are useful for demos, but they do not exercise the
production data path.

## BeagleY: Enter Live Cluster Profile

```bash
cd /Users/joshkomant/projects/beagley-cluster
tools/ui/beagley_live_cluster_profile.sh
```

The default is global `BEAGLEY_EFFECT_LEVEL=low` plus
`BEAGLEY_GAUGE_DETAIL=rich`: the map/compositor stays conservative while the
gauges show the full design.
Use `--gauge-detail safe` when checking the conservative production gauge
default. Use `--gauge-demo` only while visually reviewing telltales.
Use `--metrics` only while measuring FPS.

## Check What The Display Is Actually Running

Run this before trusting a screenshot or comparing the display to GitHub:

```bash
tools/ui/beagley_display_status.sh
```

The display source is the combination of:

- deployed binary build commit from the BeagleY journal `[BUILD]` line
- process environment from the running `beagley_cluster` process
- QML-dev manifest when `BEAGLEY_QML_DEV_ROOT` is set
- BBB live/sim source feeding `vehicle_state`

GitHub is the source of intent after commit/push. The actual display is the
source of truth for what is rendered right now.

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
