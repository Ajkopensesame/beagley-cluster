# QML smoke tests and static QML checks

All of these are CTest tests, so the required `ctest` step in `.github/workflows/ci.yml`
(job "Configure + build (WITH_WEBENGINE=OFF)") runs them. No workflow change was needed.

## `qml_smoke_*` - offscreen load of the real app

Runs the **real `beagley_cluster` binary** with `BEAGLEY_SMOKE_TEST=1`. `main.cpp`'s genuine
bootstrap (all `qmlRegisterType` calls, all ~35 context properties, backend and entry-point
selection) runs unchanged; `src/test_support/SmokeProbe.{h,cpp}` only observes the result. This
was chosen over a separate harness because a harness has to re-implement the bootstrap and
drifts from it. The probe is inert unless `BEAGLEY_SMOKE_TEST=1`.

| ctest name | `BEAGLEY_UI_VARIANT` | backend | expectation |
| --- | --- | --- | --- |
| `qml_smoke_v3_mock` | `v3` (MainV3) | `mock` | data flowing |
| `qml_smoke_embedded_mock` | `embedded` (MainEmbedded) | `mock` | data flowing |
| `qml_smoke_v3_linklost` | `v3` | `live`, `VEHICLE_HUB_WS_URL=ws://127.0.0.1:1` (refused, never connects) | link lost |
| `qml_smoke_embedded_linklost` | `embedded` | same | link lost |

Environment set by CTest: `QT_QPA_PLATFORM=offscreen`, `QT_QUICK_BACKEND=software` (no GL/EGL
needed on the runner), `BEAGLEY_WIFI_ONBOARDING=0` (otherwise the Wi-Fi dialog covers the
screen), hermetic `XDG_*` dirs under the build tree, and `BEAGLEY_MAP_TILE_URL=file:///nonexistent-tiles/...` so the
embedded map pod / radar never contact a real tile server (a live OSM response once failed CI with
HTTP/2 "stream N finished with error" warnings). Works with `WITH_WEBENGINE=OFF` and
`WITH_MAPLIBRE_NATIVE=OFF` (the CI configuration).

Assertions: root object created and is a `QQuickWindow`; window and content item are 1920x720;
>= 5 frames swapped (and >= 1.5 s elapsed) without a crash; **zero** unexpected `qWarning` /
`qCritical` (QML load errors, binding errors, TypeErrors) captured by a message handler from
process start until the verdict - allow-list with justifications is `kAllowList` in
`SmokeProbe.cpp`; `vehicleState.linkLost` matches the scenario; the `linkLostTelltale` item
(`objectName`) is visible iff link lost; every gauge readout (`speedValueText`,
`rpmValueText` in MainV3; `gaugeReadout` x2 in MainEmbedded) is a number with mock data and
exactly `--` when link is lost.

Teardown: a `SmokeProbe::TeardownGuard` (first local in `main()`, so destroyed last) collects every
warning logged after the verdict until the process is fully torn down; any non-allow-listed one (in
practice `TypeError: Cannot read property ... of null`) prints `[SMOKE] TEARDOWN FAIL` and exits 1
(`FAIL_REGULAR_EXPRESSION` makes ctest fail).

Because a failed QML load makes `main()` return -1 before any verdict, the tests also require
the `[SMOKE] RESULT PASS` line (`PASS_REGULAR_EXPRESSION`).

Run locally: `ctest --test-dir build -R qml_smoke --output-on-failure`.

## `qml_static_guards` and `qmllint_errors`

Both are `check_qml.py`. File set: every tracked `src/ui/**/*.qml` except `*.bak*` (see
`EXCLUDED` in the script; the legacy `Main`/`MainV2` screens and dead `SpeedoPearl` are deleted).

* `qml_static_guards`: import allow-list (unversioned `QtQuick.Shapes` only - a versioned import
  hides `Shape.preferredRendererType`/`CurveRenderer` on Qt >= 6.6 and the component fails to
  load; no Qt5-only modules such as `QtGraphicalEffects`), and no dead Carto raster tile URLs.
  Also `qrc` references: every literal relative resource path in a QML file (`"Foo.qml"`, `"../assets/x.png"`, ...)
  must exist and be listed in `CMakeLists.txt` (`QML_FILES`/`RESOURCES`), otherwise it is missing from the
  compiled qrc (`qrc:/BeagleY/...: No such file or directory`). Intentionally absent files go in
  `OPTIONAL_QRC_REFS` with a justification and a required guard expression (currently only the qml-dev-only
  `SkinShowOverride.qml`, probed only when MainV3 was loaded from a `file:` URL). The runtime counterpart is the
  smoke probe: a missing Loader/Image source is a `qWarning`, which fails every `qml_smoke_*` test.
  Also the MapLibre-native style init guard (`map_style_init_failures`): the wrapper must pass `styleUrl` to the
  Impl as an initial property via `setSource(...)`, and the Impl must never default to `demotiles` or an empty style.
* `qmllint_errors`: qmllint from the same Qt install, `-I <build dir>` so `import BeagleY` resolves.
  Fails on syntax errors and on every category except those listed below. Levels are passed
  as flags (not a `.qmllint.ini`) because qmllint applies a repo-level `.qmllint.ini` to *every*
  qmllint run including Platform DevOps' informational job in `checks.yml`, which would hide
  its output.

  Baseline with Qt 6.6.3 (before disabling): `unresolved-type` 553, `unqualified` 515,
  `missing-property` 466 -> **disabled** (context properties come from `main.cpp`; C++ types are
  registered at runtime with `qmlRegisterType`, so qmllint cannot see them);
  `import` ~45 ("X was not found", same cause), `duplicate-property-binding` 6 (benign
  `foo: x` + `NumberAnimation on foo`), `incompatible-type` 1 (`WeatherCorners.qml`, false
  positive) -> **info** (printed, never fatal). Everything else is at default level and
  currently 0.
