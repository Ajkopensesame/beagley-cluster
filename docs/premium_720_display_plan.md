# Premium 720 Display Plan

This is the long-term path for getting the most out of the BeagleY display
without turning the cluster into an unstable desktop-style scene.

## Goal

Deliver a premium 1920x720 cluster on the real BeagleY display:

- hardware PowerVR renderer
- Qt Quick scenegraph over OpenGL
- `eglfs_kms` full-screen display path
- MapLibre Native map underlay
- rich but controlled gauges and overlays
- repeatable perf, source-truth, and screenshot evidence before deploys

The BeagleY can support a polished 720p automotive HMI. It should not be treated
like a desktop GPU that can absorb arbitrary blur, shadow, layer, Canvas, and
full-screen transparency changes.

## Current Known-Good Base

The production source-truth branch is:

```text
codex/maplibre-native-yocto-build
```

The current supported display stack is:

```text
QT_QPA_PLATFORM=eglfs
QT_QPA_EGLFS_INTEGRATION=eglfs_kms
BEAGLEY_RENDER_PROFILE=embedded
BEAGLEY_MAP_RENDERER=maplibre-native
BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=1
BEAGLEY_REQUIRE_GPU_GATE=1
```

The board must report a hardware renderer, for example:

```text
PowerVR B-Series BXS-4-64
```

Software renderers such as `llvmpipe`, `swrast`, or `kms_swrast` are failures
for this profile.

## Named Runtime Profile

Install the premium 720 profile:

```bash
tools/ui/beagley_premium_720_profile.sh \
  --host root@beagley-ai.local \
  --render-loop basic \
  --effect-level low
```

The profile intentionally sets:

- `BEAGLEY_DISPLAY_PROFILE=premium-720`
- `BEAGLEY_UI_VARIANT=v3`
- `BEAGLEY_GAUGE_DETAIL=rich`
- `BEAGLEY_MAP_RENDERER=maplibre-native`
- `BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=1`
- explicit `QSG_RENDER_LOOP`

Use `--metrics` when measuring frame time.

## Baseline Matrix

Run the hardware acceptance matrix:

```bash
tools/perf/run_premium_720_matrix.sh \
  --host root@beagley-ai.local \
  --duration 45 \
  --warmup 15
```

Default cases:

```text
basic + effects off
basic + effects low
threaded + effects off
threaded + effects low
```

Each run writes an artifact directory under:

```text
build/perf/premium-720-<timestamp>/
```

Expected artifacts include:

- `source-truth.txt`
- `qml-risk.txt`
- `results.tsv`
- per-case `runtime.log`
- per-case `perf.log`
- per-case `perf-check.txt`
- per-case `display-status-before.txt`
- per-case `display-status-after.txt`
- per-case `screenshot.png`
- per-case screenshot analysis JSON when available

Default temporary thresholds are:

```text
min_fps >= 45
p95 <= 35 ms
p99 <= 60 ms
```

The long-term target is:

```text
min_fps >= 58
p95 <= 17 ms
p99 <= 25 ms
```

Do not raise the visual budget until the matrix is repeatably passing.

## Render Loop Decision

`basic` is the conservative production default.

`threaded` is a candidate for smoother animation, but it must win on the real
matrix before becoming the default. Do not switch production to `threaded` based
only on a Mac preview, a single screenshot, or one clean boot.

Decision rule:

1. Same commit.
2. Same map style.
3. Same GPS/vehicle state source.
4. Same Spotify/banner state.
5. Same effect level.
6. Compare `basic` and `threaded` with matrix artifacts.
7. Pick the loop with better frame-time stability and no corruption.

## QML Risk Budget

Run the static risk scan:

```bash
tools/perf/qml_render_risk_scan.sh
```

Use strict mode once the current known risks are paid down:

```bash
tools/perf/qml_render_risk_scan.sh --strict
```

Patterns that require review before production:

- unconditional `layer.enabled`
- graphical effects such as `DropShadow`, `FastBlur`, `ShaderEffect`
- large animated `clip: true` surfaces
- large live `Canvas` repaint loops
- full-screen translucent overlays
- new timers that repaint or animate every frame

Prefer:

- static assets for decorative chrome
- native C++ scenegraph items for repeated gauge geometry
- transform and opacity animations
- bounded, localized clipping
- named effect profiles instead of ad hoc visual switches

## Build And Deploy Discipline

Production visual work must use the source-truth flow:

```bash
skills/cluster-source-truth/scripts/check.sh --strict
tools/source_truth/build_canonical_yocto_app.sh
```

After deploying a built binary:

```bash
skills/cluster-source-truth/scripts/check.sh --strict
tools/perf/run_premium_720_matrix.sh --host root@beagley-ai.local
```

For long Yocto builds, start the build, report the log path/PID, then wait for
explicit instructions before polling again.

## Design Direction

Premium does not mean maximum effects. On this hardware it means:

- clear hierarchy
- precise geometry
- high-quality iconography
- restrained animation
- stable map/gauge layering
- crisp contrast
- predictable frame times

The BeagleY remains a good tool if the cluster is treated as an embedded HMI.
If the target becomes full cinematic 3D, heavy shader effects, or dense
multi-layer animation, the hardware target should be revisited.
