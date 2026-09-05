# beagley-cluster

DIY **Qt 6 Quick** instrument cluster (**1920×720**) for a **BeagleY / BeagleBone Black** vehicle hub: gauges, VIC warnings, and an optional WebEngine map.

See [ARCHITECTURE.md](ARCHITECTURE.md) for seams and data flow. License: [MIT](LICENSE).

## Stack

- **C++17**, CMake ≥ 3.21 (Ninja recommended)
- **Qt 6**: Quick / QML, Svg, WebSockets
- Optional **Qt WebEngine** map via CMake `WITH_WEBENGINE` (default **ON**)

## Layout

| Path | Role |
| --- | --- |
| `src/ui/` | QML UI (`Main.qml`, theme, widgets, optional `web/map`) |
| `src/data/` | `VehicleStateSource`, live `VehicleStateClient`, `MockVehicleStateClient` |
| `assets/` | VIC SVGs and related static art |
| `src/assets/` | Fonts (also present; dual-tree debt — see below) |

## Build

### macOS (primary day-to-day)

Install Qt 6 (Homebrew or Qt Online Installer) with **Quick, Svg, WebSockets**, and optionally **WebEngine**. Ensure `cmake` ≥ 3.21 and prefer Ninja.

```bash
cmake -S . -B build -G Ninja -DWITH_WEBENGINE=ON   # or OFF
cmake --build build
```

Binary: `build/beagley_cluster`.

### Linux notes

Same CMake invocation. Install distro Qt 6 packages (or use [aqt / install-qt-action](https://github.com/jurplel/install-qt-action) as CI does):

- Required: `qt6-base`, Quick/QML, Svg, WebSockets (names vary by distro)
- Optional: WebEngine packages only if `-DWITH_WEBENGINE=ON`
- Tools: `cmake` ≥ 3.21, `ninja-build`, C++17 toolchain

On BeagleY / BBB target images, prefer matching the Qt version you validated on the desktop when possible.

## Run

### Mock backend (no hub)

```bash
BEAGLEY_VEHICLE_BACKEND=mock ./build/beagley_cluster
```

Or with the macOS geometry helper (env is inherited):

```bash
BEAGLEY_VEHICLE_BACKEND=mock ./run_1920x720.sh
```

### Live hub

```bash
BEAGLEY_VEHICLE_BACKEND=live \
  VEHICLE_HUB_WS_URL=ws://HOST:8765 \
  ./build/beagley_cluster
```

`BEAGLEY_VEHICLE_BACKEND` defaults to **`live`**. If `VEHICLE_HUB_WS_URL` is unset, the live client falls back to `ws://192.168.0.7:8765` (see `VehicleStateClient`).

### macOS window geometry

`./run_1920x720.sh` forces cocoa geometry `1920×720` so macOS does not restore an off-screen position.

### Disable map

```bash
BEAGLEY_NO_MAP=1 ./build/beagley_cluster
```

When built with `WITH_WEBENGINE=OFF`, map init is skipped in C++ (`BEAGLEY_NO_MAP` is forced true in `main.cpp`).

## Vehicle hub

Companion hub and wire protocol:

- https://github.com/Ajkopensesame/vehicle-hub
- [PROTOCOL.md](https://github.com/Ajkopensesame/vehicle-hub/blob/main/PROTOCOL.md)

## Environment / flags

| Name | Kind | Meaning |
| --- | --- | --- |
| `BEAGLEY_VEHICLE_BACKEND` | env | `mock` or `live` (default **`live`**) |
| `VEHICLE_HUB_WS_URL` | env | WebSocket URL for live hub (e.g. `ws://HOST:8765`) |
| `BEAGLEY_NO_MAP` | env | Non-zero → skip WebEngine map init |
| `WITH_WEBENGINE` | CMake | `ON`/`OFF` — link WebEngine, ship map QML/resources |

## Known debt

Honest current gaps (not rubber-stamped as fine):

1. **Dual assets** — both `assets/` and `src/assets/` exist; packaging/source-of-truth is unclear.
2. **Legacy QRC** — `src/qml.qrc` and `src/resources/web.qrc` are not wired into the current `qt_add_*` build path.
3. **WebEngine hard-import** — `Main.qml` always `import QtWebEngine`, even when `WITH_WEBENGINE=OFF`. A separate follow-up should use a Loader / conditional module so OFF builds work end-to-end.
4. **web/test vs CMake** — with WebEngine ON, CMake still references `src/ui/web/test/index.html`, but `src/ui/web/test/` is **gitignored** (local scratch). Clean clones may miss that file.

Do not drive-by refactor these in unrelated PRs — see [CONTRIBUTING.md](CONTRIBUTING.md).

## CI

GitHub Actions (`.github/workflows/ci.yml`) on `push` / `pull_request` to `main`:

1. **Hygiene job** — asserts `README.md`, `LICENSE`, and `CMakeLists.txt` exist.
2. **Build job** (ubuntu-22.04, Qt **6.6.3** via `jurplel/install-qt-action`, modules `qtwebsockets` + `qtsvg`, **no** WebEngine):
   - **Configure** (`-DWITH_WEBENGINE=OFF`) is a **required** success step.
   - **Build** runs with **`continue-on-error: true`** because the `Main.qml` QtWebEngine hard-import commonly fails OFF builds until the Loader fix lands. Configure remains the hard gate.

## License

[MIT](LICENSE) © 2026 Ajkopensesame.
