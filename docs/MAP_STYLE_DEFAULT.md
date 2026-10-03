# Map style default (maplibre-native build)

## Intended default

The embedded / `BEAGLEY_MAP_RENDERER=maplibre-native` build starts with the **dark OpenFreeMap
style, online**: `https://tiles.openfreemap.org/styles/dark`.

* Compiled-in default: `ClusterConfig::defaultMapLibreNativeStyleUrl()` (`src/config/ClusterConfig.h`),
  exposed to QML as the context property `BEAGLEY_MAPLIBRE_NATIVE_DEFAULT_STYLE_URL`.
* `MainV3.qml` `activeMapStyleUrl` returns it whenever MapLibre native is requested and the user has
  not picked a map theme this session.
* The style, its glyphs (`/fonts/{fontstack}/{range}.pbf`), sprite (`/sprites/ofm_f384/ofm`) and vector
  source (`https://tiles.openfreemap.org/planet`) all resolve over HTTPS (checked with curl, HTTP 200).
* Startup logs the choice: `[MAP] MapLibre native: requested=... builtIn=... startupStyle=... envStyleOverride=...`
  and `[MapCenterMapLibreNative] creating native map with style <url>`.

## Why demotiles ended up on the display

`MapCenterMapLibreNativeImpl.qml` fell back to `https://demotiles.maplibre.org/style.json` when its
`styleUrl` was empty, and the Qt Location plugin reads `maplibre.map.styles` **once, when the Map is
created**. PR #36 turned the wrapper into a `Loader` whose properties were bound in `onLoaded`, i.e.
*after* the Map (and plugin) already existed with the empty `styleUrl`. The later binding never reached
the plugin, so demotiles (light `#D8F2FF` background, almost no tiles at city zoom) was used.
Fix: the wrapper now passes `styleUrl` through `Loader.setSource(...)` initial properties before the
item is created, and the Impl falls back to the dark OpenFreeMap default instead of demotiles.

## Environment override (read this)

`BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL` is honoured only **after the user picks a map theme**
(`mapLibreNativeStyleOverrideActive`). The Yocto unit and the stock launcher export a *positron*
(light) default for it, so honouring it at start-up would give a light map. At start-up the dark
OpenFreeMap default always wins.

## Board launcher copy: the old file:// style variables must be unset

The board's real `launch.sh` (runtime `runtime-hotspot-wifi-20260919`) exports:

| Variable | Value on the board |
|---|---|
| `BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL` | `file://$RUNTIME/source/src/ui/web/map/styles/pearl-vector-dark.json` |
| `BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES` | `file://…/pearl-vector-dark.json,file://…/pearl-vector-light.json` |
| `BEAGLEY_QML_DEV_ROOT`, `BEAGLEY_QML_DEV_FILE` | `$RUNTIME/source`, `$RUNTIME/source/src/ui/MainV3.qml` (load QML from disk, which also hides compiled-in fixes) |

(`BEAGLEY_MAP_BOOT_MODE`, `BEAGLEY_MAP_STYLE_MODE` only affect the web map.) The unit additionally sets
the same two style variables to positron. For the compiled-in default to apply, the launcher *copy* for
a new runtime must add, immediately before the final `exec "$RUNTIME/bin/beagley_cluster" ...` line:

```sh
unset BEAGLEY_QML_DEV_ROOT BEAGLEY_QML_DEV_FILE BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES
```

Do not edit the live launcher; make the change in a copy inside a new runtime dir.

## Offline

If the style cannot be fetched, MapLibre native cannot render vector tiles and the existing
raster/offline fallback in `MapCenterMapLibreNative.qml` remains the degrade path; there is no new
crash path (the style URL is a plain string passed to the plugin). Not runtime-tested off-board.
