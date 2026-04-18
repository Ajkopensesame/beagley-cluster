# UI Preview Workflow

Use the Mac preview loop for visual design. This keeps the BeagleY stable while
the display layout is changing.

## Start The Local Display

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/mac_preview.sh
```

The default mode runs the `v3` UI, uses the embedded render profile, and enables
`BEAGLEY_STRESS_SCENE=1` so the gauges and map have visual motion without
depending on the vehicle hub.

## Watch While Editing

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/mac_preview.sh --watch
```

Watch mode rebuilds and relaunches the Mac preview when QML or C++ source files
change. It is not true in-process QML hot reload; it is an automated
build-and-restart loop for local visual iteration.

## Use Live Vehicle Data

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/mac_preview.sh --watch --live --hub ws://10.24.0.7:8765
```

Use live mode when the BBB/vehicle hub is reachable and the display should
reflect real vehicle state.

## Main UI Files

- `src/ui/MainV3.qml`: active desktop/V3 cluster display.
- `src/ui/widgets/`: reusable QML widgets for gauges, map, warnings, and status.
- `run_1920x720.sh`: lower-level launcher used by the preview script.

## Target Validation

Do not deploy every visual tweak to the BeagleY. Iterate on the Mac first, then
use the BeagleY build/deploy path only when a UI change is ready for hardware
validation.
