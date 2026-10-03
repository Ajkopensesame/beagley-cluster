# beagley-cluster

DIY **Qt 6 Quick** instrument cluster (**1920×720**) for a **BeagleY** display with a **BeagleBone Black** vehicle hub: gauges, VIC warnings, navigation/map center, and an appliance (Yocto) build path.

See [ARCHITECTURE.md](ARCHITECTURE.md) for seams and data flow, and [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR. License: [MIT](LICENSE).

> This is the `codex/maplibre-native-yocto-build` line. It is a superset of `main` (MapLibre Native map path, Yocto appliance image, BBB hub tooling, skin v2); its history is unrelated to `main`, so changes are ported by hand, not merged.

## Stack

- **C++17**, CMake ≥ 3.21 (Ninja recommended)
- **Qt 6**: Core, Network, Quick, Qml, Svg, WebSockets (required)
- Optional **Qt WebEngine** (`WITH_WEBENGINE`, default **ON**) for the web map
- Optional **MapLibre Native** / Qt Location (`WITH_MAPLIBRE_NATIVE`, default **OFF**)
- `BEAGLEY_APPLIANCE_PRODUCTION=ON` selects the embedded appliance profile and forces `WITH_WEBENGINE=OFF`

## Layout

| Path | Role |
| --- | --- |
| `src/main.cpp` | App entry: env/profile handling, backend selection, QML context properties |
| `src/data/` | `VehicleStateSource` (shared QML surface), live `VehicleStateClient`, `MockVehicleStateClient` |
| `src/navigation/` | `NavigationService`, `OpenNavigationProvider` |
| `src/render/` | C++ render items and `ClusterRenderModel` |
| `src/system/` | Wi‑Fi setup, now-playing, radar image services |
| `src/ui/` | QML: `MainV3` (default), `MainV2`, `Main` (legacy), `MainEmbedded`, theme, widgets, `web/map` |
| `tools/bbb_hub/` | Python BBB hub (prod/sim), diagnostics, replay |
| `yocto/` | Appliance image build (`meta-beagley-cluster`) |
| `docs/` | Design notes and workflows |
| `assets/`, `src/assets/` | VIC SVGs / fonts (dual tree — see Known debt) |

## Build

```bash
cmake -S . -B build -G Ninja -DWITH_WEBENGINE=OFF   # or ON
cmake --build build
```

Binary: `build/beagley_cluster`. Install Qt 6 with Quick, Svg and WebSockets (and WebEngine only for `-DWITH_WEBENGINE=ON`). On Linux you can use [aqt / install-qt-action](https://github.com/jurplel/install-qt-action) as CI does.

The QML list in `CMakeLists.txt` (`BEAGLEY_QML_FILES`) is checked against `src/ui/widgets/qmldir` at configure time: every qmldir entry must also be in the CMake list, or configure fails with a "QML dev/prod mismatch" error.

For the appliance image see [yocto/README.md](yocto/README.md).

## Run

`run_1920x720.sh` sets the usual development environment (UI variant, render profile, map renderer, default hub URL `ws://10.24.0.7:8765`) and launches `build/beagley_cluster`.

### Mock backend (no hub)

```bash
BEAGLEY_VEHICLE_BACKEND=mock ./build/beagley_cluster
```

The mock simulates speed, RPM, fuel, coolant, gear/overdrive, indicators and warnings only. It does not simulate GPS or drivetrain, so navigation sees no GPS fix.

### Live hub

```bash
BEAGLEY_VEHICLE_BACKEND=live \
  VEHICLE_HUB_WS_URL=ws://HOST:8765 \
  ./build/beagley_cluster
```

`BEAGLEY_VEHICLE_BACKEND` defaults to **`live`**; unknown values fall back to live with a warning. If `VEHICLE_HUB_WS_URL` is unset, the live client uses `ws://10.24.0.7:8765` (see `VehicleStateClient`).

### Replay

`BEAGLEY_REPLAY_FILE=<file.jsonl>` makes the live client replay recorded `vehicle_state` frames instead of connecting (`BEAGLEY_REPLAY_LOOP=0` to play once).

## Map

Map rendering is chosen by `BEAGLEY_MAP_RENDERER` (`web`, `native`, `native-online`, `maplibre-native`; default `web` on the desktop profile and `native-online` on the `embedded` profile).

- `MapCenter.qml` is the map host. The web map (`MapCenterWeb.qml`, Qt WebEngine + MapLibre GL JS) is loaded through a `Loader` with a string URL, so no unconditional `import QtWebEngine` exists in the UI.
- With `WITH_WEBENGINE=OFF`, `MapCenterWeb.qml` and the web resources are not built, and `main.cpp` forces `BEAGLEY_NO_MAP` true.
- `maplibre-native` needs a build with `-DWITH_MAPLIBRE_NATIVE=ON` (QMapLibre + Qt Location); otherwise it falls back.

## Environment / flags

| Name | Kind | Meaning |
| --- | --- | --- |
| `BEAGLEY_VEHICLE_BACKEND` | env | `mock` or `live` (default **`live`**) |
| `VEHICLE_HUB_WS_URL` | env | Hub WebSocket URL (default `ws://10.24.0.7:8765`) |
| `BEAGLEY_REPLAY_FILE` / `BEAGLEY_REPLAY_LOOP` | env | Replay JSONL frames through the live client |
| `BEAGLEY_UI_VARIANT` | env | `v3` (default), `v2`, `legacy`/`v1`, `embedded`/`appliance` |
| `BEAGLEY_RENDER_PROFILE` | env | `embedded` or desktop profile |
| `BEAGLEY_MAP_RENDERER` | env | See Map |
| `BEAGLEY_NO_MAP` | env | Non-zero → skip WebEngine map |
| `WITH_WEBENGINE` | CMake | `ON`/`OFF` — link WebEngine, ship web map QML/resources |
| `WITH_MAPLIBRE_NATIVE` | CMake | `ON`/`OFF` — experimental MapLibre Native path |
| `BEAGLEY_APPLIANCE_PRODUCTION` | CMake | Appliance profile (forces `WITH_WEBENGINE=OFF`) |

More `BEAGLEY_*` switches are read in `src/main.cpp`.

## Vehicle hub

Wire protocol (Phase 1 `vehicle_state` contract):

- https://github.com/Ajkopensesame/vehicle-hub
- [PROTOCOL.md](https://github.com/Ajkopensesame/vehicle-hub/blob/main/PROTOCOL.md)

The cluster also ships its own BBB hub tooling in `tools/bbb_hub/` (see [docs/vehicle_hub_scope.md](docs/vehicle_hub_scope.md)); `VehicleStateClient` accepts both and tolerates extra fields (GPS, `_diagnostic`, drivetrain).

## Local target configuration

Helper scripts under `skills/` read BeagleY SSH targets from `config/beagley-target.env` (gitignored; never commit real IPs/MACs). Create it from the example:

```bash
cp config/beagley-target.env.example config/beagley-target.env
# then edit BEAGLEY_TARGETS / BEAGLEY_HOST_NAME for your network
```

You can also override with the `BEAGLEY_TARGETS`, `BEAGLEY_HOST`, `BEAGLEY_HOST_NAME` environment variables.

## Known debt

1. **Dual assets** — both `assets/` and `src/assets/` exist; packaging/source-of-truth is unclear.
2. **Legacy QRC** — `src/qml.qrc` is not wired into the current `qt_add_*` build path.
3. **web/test scratch** — `src/ui/web/test/` is gitignored for local experiments and is not part of the build.
4. ~~**`.bak` files**~~ — untracked and gitignored (`*.bak`, `*.bak.*`).

Do not drive-by refactor these in unrelated PRs — see [CONTRIBUTING.md](CONTRIBUTING.md).

## CI

GitHub Actions `.github/workflows/ci.yml` runs on every pull request and on push to `main`, `ui/slice1-map-hierarchy-quiet-chrome` and `codex/maplibre-native-yocto-build`:

- **Build job** (ubuntu-22.04, Qt **6.6.3** via `jurplel/install-qt-action`, module `qtwebsockets` only, **no** WebEngine): **configure** (`-DWITH_WEBENGINE=OFF`) and **build** are both required steps (hard gate, no `continue-on-error`).

Other workflows cover the diagnostic replay contracts (`tools/bbb_hub`, `tests`) and the fleet-atlas Pages deploy.

## License

[MIT](LICENSE) © 2026 Ajkopensesame.
