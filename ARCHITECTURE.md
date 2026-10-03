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

### Link-lost behaviour

Policy is owned in one place: `VehicleStateSource` (C++, shared by the live client and the mock). QML only binds to it.

**`linkLost`** (new `bool` property on `vehicleState`; also mirrored as `clusterRenderModel.linkLost`) is true when **any** of:

- the socket is not `connected`, or
- `linkStale` (no *good* frame for >1 s, see client), or
- `bbbStale` (hub says `_health.stale=true`, i.e. its serial/CAN source is silent; the hub publishes zeroed values in that state), or
- no `vehicle_state` frame has been seen yet (boot).

It is derived inside the setters of those four properties, so it needs no client changes and adds no timers or clocks of its own. The `_health.stale` flag is the only per-vehicle staleness flag the protocol defines for the gauges (`gpsStale` / per-source diagnostics are hub passthrough and are not consumed here), so there is no per-gauge "SENSOR" case: loss is all-or-nothing.

**While `linkLost` (MainV3 and MainEmbedded):**

| Item | Behaviour |
|------|-----------|
| speed, rpm | `--` (grey), arc/needle empty and greyed, never a real `0` |
| fuel, coolant | `--` (grey), fill arcs/bars hidden, pods greyed |
| gear | `-` (unchanged), drive-mode/overdrive/odometer placeholders unchanged |
| turn signals, high beam | off (transient) |
| warnings: brake, oil, charge, check engine, A/T, low fuel, door | **latched**: a warning that was active in the last healthy state stays on; warnings that were off stay off (no invented "unknown" state) |
| LINK LOST telltale | persistent amber-on-red pill + `!` icon (`widgets/LinkLostTelltale.qml`), window-level child at `z: 20000` (above the WiFi overlay's 9500), no timeout, shown for as long as `linkLost` |
| existing status text (`LINK DOWN` / `LINK STALE` / `BBB STALE`, embedded ribbon + warning summary) | unchanged; the embedded warning summary additionally appends `LINK LOST` and never reads `SYSTEMS NOMINAL` while lost |

Dev-only simulation / stress / gauge-review scenes in MainV3 (and the stress scene in MainEmbedded) bypass the dashes and telltale because they fake the data on purpose.

**Warning latch.** `VehicleStateSource` exposes `warnBrakeLatched`, `warnOilLatched`, `warnChargeLatched`, `warnDoorLatched`, `warnCheckEngineLatched`, `warnATLatched`, `warnFuelLowLatched` (existing `warn*` properties are unchanged). While the link is healthy the latched value tracks the live value; the moment `linkLost` becomes true it is frozen. QML shows `linkLost ? warnXLatched : warnX`. The sync runs one event-loop turn after a change (queued) because the client applies a frame's warnings *before* its `_health.stale` flag: a hub-stale frame carries zeroed warnings, and syncing immediately would latch those zeros. When the link recovers the latch is released and warnings follow live values again. Limits: a warning that *turns on* while the link is lost cannot be known; that is why the LINK LOST telltale is prominent. A warning that cleared in the same event-loop turn as the loss is latched at its previous (on) value. A partial (non-good) frame is still applied by the client and, while the link is otherwise healthy, can legitimately clear a warning; that is existing client behaviour and not changed here.

**Not covered:** the legacy `Main.qml` / `MainV2.qml` variants (`BEAGLEY_UI_VARIANT=legacy|v1|v2`) only get the warning latch (via `TachGauge.qml`); they still show `0` and have no LINK LOST telltale.

**Verifying on a vehicle/bench:** stop the hub (or unplug the UNO so it reports `_health.stale`) and expect dashes + LINK LOST within about 1 s, active warnings still lit; restart it and expect live values and no telltale. C++ coverage: `tests/vehicle_state_link_lost_test.cpp` (ctest `vehicle_state_link_lost_test`). The QML side is not covered by automated tests.

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
