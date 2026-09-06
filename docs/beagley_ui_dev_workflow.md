# BeagleY UI Dev Workflow

Use this workflow when the Mac preview does not match the real display closely
enough. The BeagleY stays the renderer, and local QML edits are copied to the
device.

## One-Time Setup

The installed BeagleY binary must support filesystem QML loading. After that
binary is deployed, enable QML dev mode:

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/beagley_enable_qml_dev.sh
```

This copies `src/ui` QML files to:

```text
/opt/beagley-cluster/qml-dev
```

It also installs a systemd drop-in that sets:

```text
BEAGLEY_QML_DEV_ROOT=/opt/beagley-cluster/qml-dev
```

## Edit On The Real Display

Run the watcher from a Mac terminal:

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/beagley_watch_qml.sh
```

When a QML file under `src/ui` changes, the watcher copies the QML tree to the
BeagleY, restarts `beagley_cluster`, then runs the health check. If the service
fails, it collects debug output.

For a single manual sync:

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/beagley_sync_qml.sh
```

Each sync writes `/opt/beagley-cluster/qml-dev/.beagley-qml-manifest` with the
local branch, commit, dirty count, and sync time. Check the live display source
with:

```bash
./tools/ui/beagley_display_status.sh
```

If `qml_source=qml-dev`, the BeagleY is showing synced filesystem QML, not the
compiled QML inside the deployed binary. That is the right mode for UI
iteration, but final validation should disable QML-dev and use the Yocto-built
binary.

## Main Files

- `src/ui/MainV3.qml`: current display layout.
- `src/ui/widgets/`: gauges, map, warnings, status, and supporting UI.
- `src/main.cpp`: selects compiled QML normally, or filesystem QML when
  `BEAGLEY_QML_DEV_ROOT` is set.

## Return To Production Mode

```bash
cd /Users/joshkomant/projects/beagley-cluster
./tools/ui/beagley_disable_qml_dev.sh
```

This removes the systemd drop-in and returns the BeagleY to compiled QML from
the deployed binary.

## Product-night lava / matrix

Product-night dial lava and subtle in-face matrix rain only run when the process has:

```text
BEAGLEY_EFFECT_LEVEL=high
BEAGLEY_RENDER_PROFILE=embedded
```

Confirm on device with `tools/ui/beagley_display_status.sh`. Lab appliance
`/etc/default/beagley-cluster.local` should keep `high` for night review (backup
`.local.bak-slice6-20260906` captured the pre-change profile).

Matrix rain is drawn **above** the opaque `NativeGaugeInstrument` face and
**below** lava + numerals (z 122 vs face 120 / lava 125). Earlier z 118 under an
opaque face made rain invisible on-glass. For review without hub values, set
`BEAGLEY_GAUGE_DEMO=1` (turn off with `=0` + restart).

