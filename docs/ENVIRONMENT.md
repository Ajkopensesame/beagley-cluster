# Environment variables: vehicle state / hub

Only the vehicle-state link is covered here. Many more `BEAGLEY_*` switches (UI variant, render profile, map renderer, GPU gate, ...) are read in `src/main.cpp`; see [README.md](../README.md).

| Variable | Default | Read by | Meaning |
| --- | --- | --- | --- |
| `VEHICLE_HUB_WS_URL` | `ws://10.24.0.7:8765` (`ClusterConfig::defaultHubUrl()`) | `VehicleStateClient` via `ClusterConfig::hubUrl()` | Hub WebSocket endpoint. Empty/unset → default. |
| `BEAGLEY_VEHICLE_BACKEND` | `live` | `main.cpp` via `ClusterConfig::resolveVehicleBackend()` | `live` or `mock`. Unknown values warn and use live. `mock` is **refused** (warn + live) in builds with `BEAGLEY_APPLIANCE_PRODUCTION=ON`. |
| `BEAGLEY_REPLAY_FILE` | unset | `VehicleStateClient` | JSONL file of `vehicle_state` frames to replay instead of connecting. Replay frames always count as "good" (never stale); see ARCHITECTURE.md. |
| `BEAGLEY_REPLAY_LOOP` | `1` | `VehicleStateClient` | `0` plays the replay once. |

## Single source of the default hub URL

- C++: `src/config/ClusterConfig.h` (`ClusterConfig::defaultHubUrl()`).
- Not generated from C++, so these must be edited together when the BBB address changes: `run_1920x720.sh`, `tools/ui/*.sh`, `tools/perf/*.sh`, `tools/beagley_wifi/setup_wifi.sh` (`--bbb-host`), `tools/beagley_gpu/beagley-cluster.env.example`, `yocto/.../beagley-cluster.default`, and the docs under `docs/`. They all pass the value through `VEHICLE_HUB_WS_URL`; there is no other hub env var.

The vehicle-hub repo's `PROTOCOL.md` mentions `ws://192.168.0.7:8765` as the cluster fallback; that is the older `main`-line value and does not apply to this line.
