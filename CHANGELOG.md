# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/) (see [docs/RELEASING.md](docs/RELEASING.md)).

## [Unreleased]

### Added
- `THIRD_PARTY_NOTICES.md` inventory of bundled/third-party components and open licence questions.
- `CHANGELOG.md`, `docs/RELEASING.md` and a CMake project version (`0.2.0`).

### Notes
- Repository hygiene, CI checks and community files are tracked in their own PRs and will be listed here
  once merged.

## History before this changelog (reconstructed, informal)

This section was reconstructed from `git log` and merged PRs #1–#10 on the default branch
`codex/maplibre-native-yocto-build`; it is a summary, not an exact release record. No versioned release has
been cut yet.

### 2026-10 (PRs #6–#10)
- #10 Phase 1 vehicle-state port: `VehicleStateSource` base class, C++ mock, `BEAGLEY_VEHICLE_BACKEND`
  switch, good-frame rule, VIC warnings, project docs; follow-up fix so `VehicleStateClient` reads
  base-class state via getters.
- #9 CI: required `Configure + build (WITH_WEBENGINE=OFF)` gate; qmldir and `toLower` build fixes.
- #8 Sync script: guard `REMOTE_ROOT` before remote `rm -rf`; corrected sync docs.
- #7 CI/Yocto: package skin-v2 atlas PNGs as Qt resources.
- #6 Appliance HMI polish (slices 1–6): map hierarchy, quiet chrome, Spotify UX, corners, motion, product
  night theme, skin v2 atlas/lava work (2026-09).

### 2026-09 (PRs #2–#5, on the earlier `main` line)
- #5 Phase 3 product skin (demo flair opt-in).
- #4 Optional WebEngine via `Loader` so OFF builds load the UI.
- #3 Phase 2 repo hygiene: README, LICENSE, CI.
- #2 Phase 1 `vehicle_state` contract on `VehicleStateClient` + C++ mock.

### 2026-07
- #1 Diagnostic replay contract v1 with CI fixtures and runtime guardrails.

### 2026-04 – 2026-06 (Yocto/appliance line)
- Snapshot of the app for Yocto builds (2026-04-04); BeagleY-AI appliance image, Wi-Fi/Ethernet target
  support and Wi-Fi hotspot/touch-gated appliance behaviour.
- Embedded MapLibre native map, frame pacing, map search and ranking, map menu.
- Radar/weather corner widgets and MapLibre radar underlay (gated behind explicit enable).
- Spotify pairing and passive cluster chrome, now-playing ticker.
- Live GPS from BBB hardware independent of vehicle staleness; BBB hub/simulator tooling.

### Existing git tags (not reachable from the current default branch)
These four tags (two annotated, two lightweight) point at commits from earlier, separate history and are **not** releases of the
current line:
- `v0.1-gauges-working` (2026-01-03) – speed and tach gauges with smooth theme transitions.
- `speedo-labels-working` (2026-01-03) – speed tick labels rendered correctly above the arc.
- `maplibre-v1` (2026-01-04) – MapLibre map layer wired into the cluster layout.
- `live-gps-source-of-truth-20260426` (2026-04-26) – known-good live GPS + BBB bench simulation baseline
  (also on branch `codex/live-gps-source-of-truth-20260426`).

[Unreleased]: https://github.com/Ajkopensesame/beagley-cluster/commits/codex/maplibre-native-yocto-build
