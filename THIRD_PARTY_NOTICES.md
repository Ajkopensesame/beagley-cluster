# Third-party notices

This file lists third-party software, data, fonts and artwork that this repository bundles, links against,
or fetches at run time. It is a **best-effort inventory, not legal advice**. Status key:

- **VERIFIED** – licence text/header found in this repo or a recipe checksum that pins it.
- **TO VERIFY** – believed licence stated, but not confirmed against the upstream source in this review.
- **TO CONFIRM** – provenance/licence unknown; the owner (ThatGuy) must confirm.

The project's own code is MIT-licensed, see [LICENSE](LICENSE).

## 1. Bundled in this repository

| Component | Where | Licence | Status |
|---|---|---|---|
| MapLibre GL JS **4.7.1** (vendored, minified) | `src/ui/web/map/vendor/maplibre/maplibre-gl.js`, `maplibre-gl.css` | BSD-3-Clause | VERIFIED (file header: `@license 3-Clause BSD`, links to v4.7.1 LICENSE). The upstream LICENSE text is not yet copied into the repo; add it when convenient. |
| Oxanium Regular | `src/assets/fonts/Oxanium-Regular.ttf` | SIL OFL 1.1 | VERIFIED from font metadata ("Copyright 2019 The Oxanium Project Authors", OFL URL). OFL text not yet included in the repo. |
| Orbitron Regular / Bold | `src/assets/fonts/Orbitron-*.ttf` | SIL OFL 1.1 (upstream) | **TO VERIFY.** Upstream Orbitron (The League of Moveable Type) is OFL 1.1, but the files *currently committed are broken* and are being **replaced by the Cluster HMI work**; they carry no licence/copyright strings in their name table. Re-check the replacement files' provenance and add the OFL text and copyright line with that change. |
| svgrepo icons | `assets/vic/svg/` (see list below) | **Per-icon** (SVG Repo hosts CC0, MIT, Apache-2.0, CC-BY and others) | **TO VERIFY** – see below |
| Skin art ("skin v2": atlas, lava, glass rim, concept/captures) | `src/ui/assets/skin-v2/**`, `src/ui/skin-show-marker.png`, `docs/vision/**` | Unknown | **TO CONFIRM with ThatGuy** – provenance unknown (hand-made, AI-generated, derived from third-party art?). Do not redistribute outside this repo until confirmed. |
| `door-open.svg` | `assets/vic/svg/door-open.svg` | Unknown | TO CONFIRM (no svgrepo marker in filename) |
| Fleet Atlas demo (`projects/fleet-atlas/`) | loads Leaflet 1.9.4 (BSD-2-Clause, TO VERIFY) from unpkg, and Space Grotesk / IBM Plex Mono (OFL, TO VERIFY) from Google Fonts at run time | see left | TO VERIFY; nothing vendored |

### svgrepo icons (TO VERIFY – licence is per icon)

Files whose name ends in `-svgrepo-com` (plus colour variants):

- `assets/vic/svg/brake-system-warning-svgrepo-com.svg`
- `assets/vic/svg/car-door-4-svgrepo-com.svg`
- `assets/vic/svg/car-lights-car-svgrepo-com.svg`
- `assets/vic/svg/engine-svgrepo-com.svg`
- `assets/vic/svg/fuel-svgrepo-com-yellow.svg` (variant of `fuel-svgrepo-com`)
- `assets/vic/svg/gearshift-shift-svgrepo-com.svg`
- `assets/vic/svg/oil-can-solid-svgrepo-com-red.svg` (variant of `oil-can-solid-svgrepo-com`)

Action for the owner: look each icon up on svgrepo.com, record its licence and author here, and add
attribution where the licence (e.g. CC-BY) requires it. The recoloured variants are modifications.

## 2. Linked / built with (not vendored)

| Component | Use | Licence | Status |
|---|---|---|---|
| Qt 6 (Core, Network, Quick, Qml, Svg, WebSockets; optional WebEngine, Location, Positioning) | UI toolkit; CI uses 6.6.3 | LGPL-3.0 / GPL-2.0/3.0 / commercial. Most modules are usable under LGPL-3.0; **WebEngine and parts of Qt Location are LGPL/GPL with additional third-party (Chromium) terms.** | TO VERIFY per module. When shipping a device image, LGPL obligations apply (provide the licence text, allow relinking/replacing the Qt libraries, offer corresponding Qt source). Avoid static linking of Qt unless the implications are understood. |
| maplibre-native-qt 3.0.0 | native map (`find_package(QMapLibre 3.0.0)`), built by a Yocto recipe | Recipe declares `BSD-2-Clause & (LGPL-3.0-only \| GPL-2.0-only \| GPL-3.0-only) & MIT` with pinned licence checksums | Recipe-declared; TO VERIFY upstream |
| Yocto / OpenEmbedded layers, TI SDK, BeagleY-AI kernel/U-Boot | `yocto/` (only recipes/config in this repo, no upstream sources) | Various; each recipe carries its own `LICENSE` | Not reviewed |
| Python dependencies of `tools/` | stdlib plus whatever the individual tools import | Various | Not reviewed; no requirements file exists yet |

## 3. Map data and online services (run-time, attribution required)

- **OpenStreetMap data** – © OpenStreetMap contributors, licensed under the
  [Open Database Licence (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/). Any display of OSM-derived
  maps must show the attribution **"© OpenStreetMap contributors"** with a link/notice to
  <https://www.openstreetmap.org/copyright>.
- **OpenFreeMap** (`https://tiles.openfreemap.org`) – vector tiles and glyphs used by the MapLibre styles
  (`src/ui/web/map/styles/embedded-liberty.*`, `config/maplibre/production-styles.json`). OpenFreeMap asks
  for attribution of OpenFreeMap, OpenMapTiles and OpenStreetMap
  (published form: **"OpenFreeMap © OpenMapTiles Data from OpenStreetMap"**). **TO VERIFY** against
  <https://openfreemap.org/> terms. **Gap noted:** the embedded style currently declares only
  `© OpenStreetMap contributors` as source attribution, and it is not confirmed that the cluster UI shows any
  attribution on screen. Decide where attribution is displayed on the in-vehicle HMI (e.g. map corner or an
  About/Settings screen).
- Other endpoints referenced in `src/` and `config/` (usage policies/attribution **TO VERIFY**; several are
  free community services with fair-use limits that are not suitable for production traffic):
  `tile.openstreetmap.org` (OSM tile usage policy), `nominatim.openstreetmap.org` (geocoding, ≤1 req/s,
  identifying User-Agent), `photon.komoot.io`, `router.project-osrm.org` (public demo server),
  `a.basemaps.cartocdn.com` (CARTO basemap terms/attribution), `tilecache.rainviewer.com` (RainViewer terms,
  attribution), `demotiles.maplibre.org` (MapLibre demo tiles only).
- Spotify integration (`tools/spotify*`) uses the Spotify Web API; Spotify Developer Terms and branding
  guidelines apply (TO VERIFY, not reviewed).

## 4. Open items for the owner

1. Skin art provenance (section 1) – **TO CONFIRM**.
2. svgrepo per-icon licences – **TO VERIFY** and attribute as required.
3. Orbitron replacement files: confirm source and add the OFL text.
4. Add upstream licence texts (MapLibre GL JS BSD-3, OFL 1.1) under a `LICENSES/` directory.
5. Decide on and implement on-screen map attribution for OpenFreeMap/OSM.
