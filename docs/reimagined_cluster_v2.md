# Reimagined Cluster V2

## What the project is trying to be

This codebase is not a generic dashboard. It is a digital instrument cluster for a 1994 Mitsubishi Pajero that is trying to preserve analog drama while adding modern GPS/navigation and richer vehicle-state feedback.

The intent visible in the current build:

- left dial as speed-first driver focus,
- right dial as tach plus VIC/warnings,
- center panel reserved for navigation/video,
- OEM-ish warning truth sourced from the BBB over WebSocket,
- a stylized cyber / pearl / glass visual language rather than a stock OEM clone.

## What is working well in the current direction

- The data model is pragmatic: one `vehicle_state` feed, stale handling, clear analog bindings.
- The gauge widgets already have a physical feel with smoothing and arc tapering.
- Warning state is separated from signal health, which is the right architecture for a real vehicle.
- GPS is already in the state model, so the center panel can become genuinely useful.

## What is hurting the current design

- The layout is visually split into thirds, but the center map path is still unstable.
- The current screen has too many competing motifs: pearl gauges, matrix rain, VIC halos, snapshot/web fallbacks.
- Font usage is inconsistent and some configured fonts are missing or invalid.
- There are too many legacy and backup files inside the active widget tree.
- The map strategy depends on network paths that may fail at runtime, leaving the center panel visually dead.

## V2 concept

The V2 recode treats the cluster as a cockpit, not a screensaver.

Design goals:

- make the center panel feel like a real nav pod,
- keep speed and tach physically dominant,
- move system state into a crisp top ribbon,
- compress warnings into a bottom rail so faults read instantly,
- reduce visual noise behind the gauges.

## V2 layout

- `Top ribbon`: link health, gear, O/D, high beam, live GPS coordinates.
- `Left pod`: speed as the primary driving instrument.
- `Center pod`: live GPS-driven map inside a hard-framed nav shell.
- `Right pod`: tach with VIC and warning hierarchy.
- `Bottom ribbon`: fault summary and live numeric speed/RPM readout.

## Runtime model

- Default entrypoint is now `MainV2`.
- Legacy screen remains available with `BEAGLEY_UI_VARIANT=legacy`.
- The run script defaults to V2 unless you override it.

## Next architectural cleanup I would do

1. Move all live widget files out of directories containing `.bak` variants.
2. Replace network-dependent map snapshots with a local/offline tile path or BBB-served raster feed.
3. Consolidate fonts into one real bundled family and one system fallback.
4. Split the monolithic gauges into reusable primitives: dial face, arc band, center readout, indicator overlays.
5. Add a dedicated drivetrain/4WD state path if the Pajero transfer case data is available.
