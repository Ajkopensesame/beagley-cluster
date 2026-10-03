# Environment variables: vehicle state / hub

Only the vehicle-state link is covered here. Many more `BEAGLEY_*` switches (UI variant, render profile, map renderer, GPU gate, ...) are read in `src/main.cpp`; see [README.md](../README.md).

| Variable | Default | Read by | Meaning |
| --- | --- | --- | --- |
| `VEHICLE_HUB_WS_URL` | `ws://10.24.0.7:8765` (`ClusterConfig::defaultHubUrl()`) | `VehicleStateClient` via `ClusterConfig::hubUrl()` | Hub WebSocket endpoint. Empty/unset → default. |
| `BEAGLEY_VEHICLE_BACKEND` | `live` | `main.cpp` via `ClusterConfig::resolveVehicleBackend()` | `live` or `mock`. Unknown values warn and use live. `mock` is **refused** (warn + live) in builds with `BEAGLEY_APPLIANCE_PRODUCTION=ON`. |
| `BEAGLEY_REPLAY_FILE` | unset | `VehicleStateClient` | JSONL file of `vehicle_state` frames to replay instead of connecting. Replay frames always count as "good" (never stale); see ARCHITECTURE.md. |
| `BEAGLEY_REPLAY_LOOP` | `1` | `VehicleStateClient` | `0` plays the replay once. |

## Screenshots, tests and map tiles

| Variable | Default | Read by | Meaning |
| --- | --- | --- | --- |
| `BEAGLEY_WIFI_ONBOARDING` | enabled | `WiFiSetupService` | `0` disables the Wi-Fi onboarding dialog. **Set `0` for screenshots, offscreen renders and tests**: otherwise the dialog is shown on first run and covers the whole 1920x720 screen. The CTest smoke tests set it. |
| `BEAGLEY_MAP_TILE_URL` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` (`ClusterConfig::defaultMapTileUrl()`) | `main.cpp` -> `MainV3.qml` map themes, `RadarImageService` base layer | `{z}/{x}/{y}` raster tile template for the keyless fallback map. OSM's tile usage policy applies (identifying User-Agent, no heavy use): use your own tile server for fleets. Carto `light_all`/`dark_all`/`voyager` tiles are dead (they return an "API KEY REQUIRED" watermark) and are rejected by a CI guard. |
| `BEAGLEY_MAP_TILE_DARKEN` | `1` | `main.cpp` -> `NativeRasterMapItem` | The "Dark" map theme darkens the fallback tiles locally (invert + hue-rotate 180, `src/render/TileTint.h`). `0` if `BEAGLEY_MAP_TILE_URL` already serves a dark style. |
| `BEAGLEY_SMOKE_TEST` | unset | `src/test_support/SmokeProbe` | `1` makes the real binary self-check (message capture, 1920x720, frames, link-lost UI) and exit 0/1. Used by `qml_smoke_*` CTest tests; see `tests/qml_smoke/README.md`. Also `BEAGLEY_SMOKE_EXPECT` (`live`/`linklost`), `BEAGLEY_SMOKE_FRAMES`, `BEAGLEY_SMOKE_MIN_MS`, `BEAGLEY_SMOKE_TIMEOUT_MS`. |
| `BEAGLEY_SCREENSHOT_PATH` / `_DELAY_MS` / `_EXIT` | unset / 3000 / 0 | `main.cpp` | Grab the window to a PNG after the delay; `_EXIT=1` quits afterwards. Combine with `QT_QPA_PLATFORM=offscreen BEAGLEY_VEHICLE_BACKEND=mock BEAGLEY_WIFI_ONBOARDING=0`. |

## Single source of the default hub URL

- C++: `src/config/ClusterConfig.h` (`ClusterConfig::defaultHubUrl()`).
- Not generated from C++, so these must be edited together when the BBB address changes: `run_1920x720.sh`, `tools/ui/*.sh`, `tools/perf/*.sh`, `tools/beagley_wifi/setup_wifi.sh` (`--bbb-host`), `tools/beagley_gpu/beagley-cluster.env.example`, `yocto/.../beagley-cluster.default`, and the docs under `docs/`. They all pass the value through `VEHICLE_HUB_WS_URL`; there is no other hub env var.

The vehicle-hub repo's `PROTOCOL.md` mentions `ws://192.168.0.7:8765` as the cluster fallback; that is the older `main`-line value and does not apply to this line.
