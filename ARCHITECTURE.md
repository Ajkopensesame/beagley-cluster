# Architecture

Thin ground truth for the BeagleY cluster (`codex/maplibre-native-yocto-build` line). For build/run details see [README.md](README.md).

## Product intent

DIY **1920×720** Qt Quick instrument cluster for a BeagleY display fed by a BeagleBone Black vehicle hub: speedo, tach, fuel, VIC warnings, map/navigation center. The cluster is display-only (see [docs/project_coordination.md](docs/project_coordination.md)). Development is typically on macOS/Linux; the BeagleY appliance image (Yocto) is the target runtime.

## Stack

| Layer | Choice |
| --- | --- |
| Language | C++17 |
| UI | Qt 6 Quick / QML (`BeagleY` QML module) |
| Graphics extras | Qt Svg |
| Hub transport | Raw-TCP WebSocket client in `VehicleStateClient` (Qt Network; Qt WebSockets is also a required component) |
| Map | `web` (Qt WebEngine, optional), `native` / `native-online`, `maplibre-native` (optional, `WITH_MAPLIBRE_NATIVE`) |
| Build | CMake ≥ 3.21, Ninja recommended |

## Layout and seams

```
src/
  main.cpp          # app entry, env/profile handling, backend selection, context props
  data/             # vehicle_state: VehicleStateSource, VehicleStateClient, MockVehicleStateClient
  navigation/       # NavigationService (consumes vehicle GPS), OpenNavigationProvider
  render/           # ClusterRenderModel and native render items
  system/           # Wi-Fi setup, now playing, radar image
  ui/               # QML: MainV3 (default), MainV2, Main, MainEmbedded, theme, widgets, web/map
tools/bbb_hub/      # Python BBB hub + diagnostics (producer side)
yocto/              # appliance image build
```

**Intended seams**

- **UI** binds to one context property, `vehicleState`, typed `VehicleStateSource*`. QML gauges gate on `connected && !linkStale && !bbbStale` before showing live values/warnings.
- **Data** (`src/data`) owns hub I/O and mock generation behind that interface. `NavigationService` and `ClusterRenderModel` depend on `VehicleStateSource`, not on a concrete client.
- **Map** (`MapCenter.qml`) picks a renderer; the web map is a `Loader`-loaded `MapCenterWeb.qml`.

## Data path

```
QML (gauges / VIC / map)      NavigationService, ClusterRenderModel
    ↑ context property "vehicleState"
VehicleStateSource          (QML-facing properties + shared setters)
    ├── MockVehicleStateClient   (BEAGLEY_VEHICLE_BACKEND=mock)
    └── VehicleStateClient       (live; default; or JSONL replay)
            ↑ WebSocket JSON text frames
        vehicle-hub  (PROTOCOL.md; tools/bbb_hub in this repo is a compatible producer)
```

### vehicle_state contract (Phase 1)

- Flat camelCase `speedKph`, `rpm`, `fuelPct`, `coolantC`, `gear` (P/R/N/D/2/1), `overdrive`; nested `indicators` (`left`, `right`, `high_beam`), `warnings` (`brake`, `oil`, `charge`, `door`, `check`, `at`, `fuel_low`) and `_health.stale`. Optional `ts_ms`, `seq`, `source` are ignored.
- **Good frame**: only a frame that has the four gauge keys **and** the `indicators`, `warnings` and `_health` objects refreshes `lastGoodRx`. Other frames are still applied but do not keep the link alive. Replayed frames (`BEAGLEY_REPLAY_FILE`) are always treated as good.
- **Stale**: the watchdog sets `linkStale` when no good frame arrived for >1000 ms (hub sends ~10 Hz). `_health.stale` is exposed separately as `bbbStale`.
- The hub owns fuel/coolant conversion; the client reads the top-level fields, never `analog.*`.
- The client additionally understands extras used on this line: GPS (nested `gps` or top-level), `_diagnostic`, `drivetrain`/`transmission`, `gpsSource`. Changes to the wire format belong in [vehicle-hub](https://github.com/Ajkopensesame/vehicle-hub) first.

## Run / backends

| Mode | How |
| --- | --- |
| Mock | `BEAGLEY_VEHICLE_BACKEND=mock` |
| Live | `BEAGLEY_VEHICLE_BACKEND=live` (default) + hub reachable at `VEHICLE_HUB_WS_URL` |
| Replay | `BEAGLEY_REPLAY_FILE=<jsonl>` (live client) |
| Map off | `BEAGLEY_NO_MAP=1` (forced when built with `WITH_WEBENGINE=OFF`) |

## Optional web map

- `WITH_WEBENGINE` gates linking `Qt6::WebEngineQuick`, compiling `MapCenterWeb.qml` into the BeagleY module, and packaging `src/ui/web/map/` as Qt resources.
- `main.cpp` only initialises WebEngine when built ON and the map is enabled.
- The required CI build gate compiles with `WITH_WEBENGINE=OFF`; the ON path is **not** built in CI.

## Known debt

1. **Dual assets** — `assets/` vs `src/assets/`; unclear single source of truth.
2. **Legacy QRC** — `src/qml.qrc` is not used by the current `qt_add_*` path.
3. **web/test scratch** — `src/ui/web/test/` is gitignored and not referenced by CMake.
4. **Committed `.bak` files** under `src/ui`.

## Out of scope (pointers)

- Collapsing dual assets or deleting legacy QRC without a dedicated PR.
- Hub protocol changes (own them in [vehicle-hub](https://github.com/Ajkopensesame/vehicle-hub)).
- Inventing fake vehicle metrics beyond the existing mock client.
