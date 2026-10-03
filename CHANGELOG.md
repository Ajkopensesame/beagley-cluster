# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims to
follow [Semantic Versioning](https://semver.org/) (see [docs/RELEASING.md](docs/RELEASING.md)).

## [Unreleased]

### Removed
- Cleanup (no behaviour change; every file was unreferenced by code, CMake, tests, scripts and docs): duplicate `docs/vision/atlas/*.png` (identical copies live in `src/ui/assets/skin-v2/`; `atlas-meta.txt` kept, README pointer added), `src/resources/web.qrc`, `src/ui/widgets/VehicleStateCoreAnimated.qml`, `src/ui/mock/`, the orphan old VIC icon/warning widgets (`vic/ATIcon`, `vic/VicWarningIcon`, `vic/VicWarningHalo`, `vic/icons/*` except `DriveStateIcon`, `vic/warnings/*`) and the unused `FuelGauge`, `FuelPumpIcon`, `SpeedoPearl`, `MapLibreGaugeBackplate` widgets (CMake `BEAGLEY_QML_FILES` and `widgets/qmldir` entries removed together).

### Changed
- Board runbook: section 3.1 now describes the live QML root (`<runtime>/source` under `/data`, launched by `launch.sh`), warns that `tools/ui` sync/enable scripts default to `/opt/beagley-cluster/qml-dev` and that pointing `--remote-root` at the live source deletes it, documents the `capture-once.env` one-shot method, answers open question 6, and adds known issues (root fs 95% full, deployed binary is the 2026-09-13 build, BeagleY IP drift). Docs only.

## [0.2.0] - 2026-10-03

### Added
- Hub: CAN prep without a car: OBD-II starter dictionary (`tools/bbb_hub/config/can_signals.obd2_example.json`, example only, unverified), additive optional `when` multiplexer in `can_signals.json` (needed for OBD-II PIDs sharing `0x7E8`), pure-Python fake SocketCAN (`tools/bbb_hub/fake_can.py`, `SocketCanSignalSource(socket_factory=...)`), `vcan0` test when available, `docs/can_bus_parts_and_wiring.md`. Fix: CAN log replay (`CAN_RAW_LOG`) was always treated as stale by the hub and never applied.
- Hub: fake UNO tool (`tools/bbb_hub/fake_uno.py`), fake-UNO calibration end-to-end tests against the real hub, `docs/uno_bench_setup.md`.
- Hub: GPS-disciplined clock. New additive `gps.utcMs`/`gps.utcValid` (RMC-only UTC) and `tools/bbb_hub/gps_clock.py` + `bbb-gps-clock.service` (runs as `debian` with `CAP_SYS_TIME` only) that steps the BBB clock from GPS time via the hub WebSocket; staged deploy scripts under `tools/bbb_hub/deploy/` (supersedes #29). Hub bench waveform and the baseline/transition monitors no longer depend on wall-clock continuity.
- Hub: GPS-first speed with pulse fallback (`VEHICLE_SPEED_SOURCE`, `_health.speedSource`); UNO bench-test checklist; `firmware/uno_vehicle_input` sketch.
- Board runbook: recorded BBB access path, missing BeagleY NTP daemon, BBB clock status and GPS-first speed links (`docs/BOARD_RUNBOOK.md`).
- `THIRD_PARTY_NOTICES.md` inventory of bundled/third-party components and open licence questions.
- `CHANGELOG.md`, `docs/RELEASING.md` and a CMake project version (`0.2.0`).
- Third-party provenance review: verified MapLibre GL JS 4.7.1 / Orbitron / Oxanium sources, added `licenses/` (MapLibre BSD-3, Oxanium OFL), per-icon SVG Repo licence table, OpenFreeMap/OSM attribution requirements and gaps in `THIRD_PARTY_NOTICES.md`.
- Docs: deployed BBB state (release `305b982`, verified 2026-10-03 15:55 AEST) added to `docs/BOARD_RUNBOOK.md`; UART4 (`/dev/ttyS4`) is now the enabled UNO serial input and the GPS is on `/dev/ttyS1`; corrected stale `ttyS4`-as-GPS values in `tools/bbb_hub/bbb-hardware-gps.env.example` (comments/example values only) and in the wiring, bench-checklist, Wi-Fi architecture, serial-protocol, deploy-plan (now marked executed) and UNO README docs.

### Notes
- Repository hygiene, CI checks and community files are tracked in their own PRs and will be listed here
  once merged.

## History before this changelog (reconstructed, informal)

This section was reconstructed from `git log` and merged PRs #1–#10 on the default branch
`codex/maplibre-native-yocto-build`; it is a summary, not an exact release record. The first versioned release is 0.2.0 (above).

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
