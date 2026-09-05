# Architecture

Thin ground truth for the BeagleY cluster after Phase 1 (vehicle state contract). For product/build/run details see [README.md](README.md).

## Product intent

DIY **1920×720** Qt Quick instrument cluster aimed at a BeagleY / BeagleBone Black vehicle hub: speedo, tach, fuel, VIC warnings, optional WebEngine map. Development day-to-day is primarily on macOS; Linux/BeagleY is the target runtime.

## Stack

| Layer | Choice |
| --- | --- |
| Language | C++17 |
| UI | Qt 6 Quick / QML |
| Graphics extras | Qt Svg |
| Hub transport | Qt WebSockets |
| Optional map | Qt WebEngine (`WITH_WEBENGINE`, default ON) |
| Build | CMake ≥ 3.21, Ninja recommended |

## Layout and seams

```
assets/                 # VIC SVGs (and similar static art)
src/
  main.cpp              # app entry, backend selection, QML context props
  data/                 # vehicle_state C++ sources (hub + mock)
  ui/                   # QML: Main, theme, widgets, optional web map
  assets/               # fonts (Orbitron, Oxanium, …)
  qml.qrc               # LEGACY — not wired to current qt_add_* path
  resources/web.qrc     # LEGACY — not wired to current qt_add_* path
```

**Intended seams**

- **UI** (`src/ui`) binds to a single context property `vehicleState` (`VehicleStateSource` interface). Prefer not to talk to the hub from QML directly.
- **Data** (`src/data`) owns hub I/O and mock generation behind that interface.
- **Assets** should eventually converge on one tree; today both `assets/` and `src/assets/` exist (known debt).

## Data path

```
QML (gauges / VIC)
    ↑ context property "vehicleState"
VehicleStateSource          (abstract API)
    ├── MockVehicleStateClient   (BEAGLEY_VEHICLE_BACKEND=mock)
    └── VehicleStateClient       (live; default)
            ↑ WebSocket
        vehicle-hub  (PROTOCOL.md)
```

- Live client URL: `VEHICLE_HUB_WS_URL` (default in code: `ws://192.168.0.7:8765`).
- Wire format and message types: [vehicle-hub PROTOCOL.md](https://github.com/Ajkopensesame/vehicle-hub/blob/main/PROTOCOL.md).

## Run / backends

| Mode | How |
| --- | --- |
| Mock | `BEAGLEY_VEHICLE_BACKEND=mock` |
| Live | `BEAGLEY_VEHICLE_BACKEND=live` (default) + hub reachable at `VEHICLE_HUB_WS_URL` |
| Map off | `BEAGLEY_NO_MAP=1` (also forced when built with `WITH_WEBENGINE=OFF`) |
| macOS geometry | `./run_1920x720.sh` → cocoa `1920x720+0+0` |

## Known debt

1. **Dual assets** — `assets/` vs `src/assets/`; unclear single source of truth for packaging.
2. **Legacy QRC** — `src/qml.qrc` and `src/resources/web.qrc` remain but are not used by the current `qt_add_executable` / `qt_add_qml_module` / `qt_add_resources` path.
3. **WebEngine hard-import** — `src/ui/Main.qml` always `import QtWebEngine`, so `WITH_WEBENGINE=OFF` builds can fail at QML even though C++/`MapCenterWeb.qml` are gated. Follow-up: Loader / conditional import.
4. **web/test vs CMake** — CMake still lists `src/ui/web/test/index.html` under `WITH_WEBENGINE`, but `src/ui/web/test/` is gitignored (local scratch). ON builds may miss that file unless present locally.

## Out of scope (pointers)

- Fixing the WebEngine hard-import / Loader split (separate follow-up).
- Collapsing dual assets or deleting legacy QRC without a dedicated PR.
- Hub protocol changes (own them in [vehicle-hub](https://github.com/Ajkopensesame/vehicle-hub)).
- Inventing fake vehicle metrics beyond the existing mock client.
