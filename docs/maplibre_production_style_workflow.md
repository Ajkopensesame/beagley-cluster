# MapLibre Native Production Style Workflow

The BeagleY cluster defaults to the verified MapLibre Native production style.
A style is not trusted just because it downloads on a laptop. It must pass these
checks before replacing the default:

1. The app is healthy before the probe starts.
2. The style JSON, sources, glyphs, and sprites fetch successfully.
3. The BeagleY can fetch the style URL over its own network path.
4. The real cluster process renders a nonblank screenshot on the display.
5. The style is promoted into `/etc/default/beagley-cluster.local` with
   `BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=0`.

Run this from the repo root:

```sh
./tools/maplibre/probe_beagley_style.sh \
  --style-url https://tiles.openfreemap.org/styles/positron \
  --label openfreemap-positron \
  --promote
```

The script writes screenshots, logs, and JSON analysis to
`build/maplibre-probes/`. If a probe fails, it restores the previous BeagleY
environment and restarts the service.

The current known-good default is OpenFreeMap Positron, verified on the real
BeagleY display by this workflow:

```sh
BEAGLEY_MAP_RENDERER=maplibre-native
BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL=https://tiles.openfreemap.org/styles/positron
BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES=https://tiles.openfreemap.org/styles/positron
BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=0
BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=0
BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM=14.0
```

Promotion writes these keys on the BeagleY:

```sh
BEAGLEY_MAP_RENDERER=maplibre-native
BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL=<verified style URL>
BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES=<verified style URL>
BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES=0
BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY=0
BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM=<verified source maxzoom>
```

The QML runtime also has a guard. If MapLibre Native is requested with a style
that is not in `BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES`, it falls back to the
native raster map instead of showing a blank center.

The probe reads source TileJSON and caps the native renderer zoom to the
provider's published `maxzoom`. That prevents the embedded renderer from asking
for unavailable high-zoom vector tiles during parking or low-speed camera modes.
