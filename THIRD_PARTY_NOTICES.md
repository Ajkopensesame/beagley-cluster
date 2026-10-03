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
| MapLibre GL JS **4.7.1** (vendored) | `src/ui/web/map/vendor/maplibre/maplibre-gl.js`, `maplibre-gl.css` | BSD-3-Clause | **VERIFIED.** Both files are byte-identical (sha256 checked) to the `maplibre-gl@4.7.1` npm `dist/` files; `.js` carries the upstream header `@license 3-Clause BSD` pointing to the v4.7.1 `LICENSE.txt`. Upstream licence text (Copyright (c) 2023, MapLibre contributors) is copied to [`licenses/MapLibre-GL-JS-4.7.1-BSD-3-Clause.txt`](licenses/MapLibre-GL-JS-4.7.1-BSD-3-Clause.txt). Upstream's bundle also inlines small helper libraries (e.g. `pbf`, `supercluster`, `kdbush`); upstream ships them under this single header and we leave it unmodified. |
| Oxanium Regular | `src/assets/fonts/Oxanium-Regular.ttf` | SIL OFL 1.1 | **VERIFIED.** Name table: "Copyright 2019 The Oxanium Project Authors (https://github.com/sevmeyer/oxanium)", licence URL `scripts.sil.org/OFL`, version 2.000 (designer: Severin Meyer). 369 of 374 glyph outlines are identical to upstream `fonts/ttf/Oxanium-Regular.ttf` (upstream commit `a8f39e0`), but the file is **not byte-identical** (different build: has a `STAT` table, no `DSIG`), so the exact download source (likely a Google Fonts-derived static instance) is not known. No Reserved Font Name is declared in the upstream OFL. Upstream `OFL.txt` copied to [`licenses/OFL-Oxanium.txt`](licenses/OFL-Oxanium.txt). |
| Orbitron Medium / Bold | `src/assets/fonts/Orbitron-Medium.ttf`, `Orbitron-Bold.ttf` | SIL OFL 1.1, Reserved Font Name "Orbitron" | **VERIFIED.** PR #16 replaced the previous fake (saved-HTML) files. Both TTFs are **byte-identical** (sha256) to `Orbitron Medium.ttf` / `Orbitron Bold.ttf` at <https://github.com/theleagueof/orbitron> commit `13e6a5222aa6818d81c9acd27edd701a2d744152` (Matt McInerney, (c) 2009). Name table: designer "Matt McInerney", vendor URL theleagueofmoveabletype.com (the upstream files carry no copyright/licence strings of their own). Licence text is in [`src/assets/fonts/OFL-Orbitron.txt`](src/assets/fonts/OFL-Orbitron.txt) (sha256 identical to upstream `Open Font License.markdown`) with provenance in `src/assets/fonts/README-Orbitron.md`. Files are unmodified, so the Reserved Font Name clause is respected. |
| svgrepo icons (+ `door-open.svg`) | `assets/vic/svg/` | **Per-icon**, see table below | **PARTLY VERIFIED** – see "SVG Repo icons" below |
| Skin art ("skin v2": atlas, lava, glass rim, concept/captures) | `src/ui/assets/skin-v2/**`, `src/ui/skin-show-marker.png`, `docs/vision/**` | Unknown / owner's own work | **TO CONFIRM with ThatGuy.** Repo evidence is summarised under "Skin art provenance" below; it cannot establish authorship or licence. Do not redistribute outside this repo until confirmed. |
| Fleet Atlas demo (`projects/fleet-atlas/`) | loads Leaflet 1.9.4 (BSD-2-Clause, TO VERIFY) from unpkg, and Space Grotesk / IBM Plex Mono (OFL, TO VERIFY) from Google Fonts at run time | see left | TO VERIFY; nothing vendored |

### SVG Repo icons

Every file in `assets/vic/svg/` carries the header `<!-- Uploaded to: SVG Repo, www.svgrepo.com, Generator: SVG Repo Mixer Tools -->`
but **no licence or author metadata** (SVG Repo's "Mixer" export strips it), so the licence has to be looked up per
icon. Method: icons were matched to SVG Repo entries by geometry (colour-normalised rasterisation / identical path data),
not just by name. SVG Repo's own pages are behind a bot check, so for some icons the licence comes from the
public mirror of SVG Repo metadata (`huggingface.co/datasets/nyuuzyou/svgrepo`, crawled 2025-04, fields `license` and
`license_owner`) rather than the live page; this is marked below. Colour variants (`-yellow`, `-red`, the `#FF3B3B`
fills) are recolourings of the originals.

| File in repo | SVG Repo entry | Licence | Attribution required? | Status |
|---|---|---|---|---|
| `brake-system-warning-svgrepo-com.svg` | [Brake System Warning, id 136689](https://www.svgrepo.com/svg/136689/brake-system-warning) (uploader: SVG Repo) | CC0 (page: "LICENSE: CC0") | No | **VERIFIED** (path data identical to the file served by svgrepo.com) |
| `door-open.svg` | [Car Door Left 2, id 460630](https://www.svgrepo.com/svg/460630/car-door-left-2) (pack "variety duotone line", Mary Akveo; uploader: SVG Repo) | CC0 (page); mirror metadata says Public Domain | No | **VERIFIED** (identical geometry) |
| `car-door-4-svgrepo-com.svg` | Car Door 4, id 460629 (same pack as above) | Public Domain per mirror metadata; sibling entry 460630 is CC0 on its live page | No | **VERIFIED** geometry; licence from mirror + sibling page |
| `oil-can-solid-svgrepo-com-red.svg` | Oil can solid, id 314403 (pack `line-awesome`, owner Icons8) | MIT (mirror metadata) | **Yes, keep the MIT notice** | **VERIFIED** geometry; licence from mirror. Line Awesome (<https://github.com/icons8/line-awesome>) is offered under MIT or Icons8's "Good Boy" licence. Suggested credit: "Oil can icon: Line Awesome by Icons8, MIT licence (via SVG Repo)". The upstream repo has no copyright line to reproduce. |
| `fuel-svgrepo-com-yellow.svg` | Fuel, id 448006 (pack `mt-web-interface-icons`, owner moneytree) | Mirror metadata says Public Domain, **but** the upstream repo <https://github.com/moneytree/mt-web-icons> declares `"license": "ISC"` in `package.json` and has no LICENSE file | Unclear (ISC would require keeping its copyright notice, which upstream does not state) | **TO CONFIRM** (conflicting sources) |
| `car-lights-car-svgrepo-com.svg` | not identified | unknown | unknown | **UNRESOLVED** – SVG Repo's vector pages could not be fetched and the icon is absent from the public metadata mirror; the same-named page lives in the "Car Parts" collection |
| `engine-svgrepo-com.svg` | not identified | unknown | unknown | **UNRESOLVED** (as above; likely the "Car Dashboard Signals" collection) |
| `gearshift-shift-svgrepo-com.svg` | not identified (the SVG Repo page "Gearshift Shift", id 218869, is a *different* drawing) | unknown | unknown | **UNRESOLVED** |

Most SVG Repo entries uploaded by "SVG Repo" itself are CC0, which makes the three unresolved icons likely (not
confirmed) attribution-free. To close them the owner can open each icon in a browser, or replace the icon.

### Skin art provenance (evidence only; **TO CONFIRM**)

- Git history: `docs/vision/skin-v2-concept-1920x720.png` was first committed in `f80241d` ("Skin v2 Slice A ...
  Vision PNG locked under docs/vision/", 2026-09-06, author `joshkomant`). Every later change to `skin-v2/`,
  `docs/vision/` and `skin-show-marker.png` is by the same author (commits `92c6511`, `6156465`, `2a21364`, `458d02d`
  and the "Skin v2" series). No commit message or doc says where the concept still came from.
- Embedded metadata: the concept PNG has only `IHDR`, `pHYs` (aspect ratio) and `IDAT` chunks: **no** tEXt/iTXt/eXIf/C2PA
  generator, software, prompt or author fields. No file under these paths contains such metadata, so tool/AI use can
  neither be proved nor excluded from the files.
- The atlas PNGs (`lava-annulus`, `lava-strip`, `glass-rim`, `gauge-face-matrix`, `progress/lava-p00..20`) are derived from the
  concept still: `docs/vision/README.md` ("Atlas assets (from concept PNG)") and `docs/vision/atlas/atlas-meta.txt`
  (`source=skin-v2-concept-1920x720.png`, `bake=extract_skin_atlas4`). The bake script `extract_skin_atlas4` is not in the
  repository. Ownership of the atlases therefore follows the ownership of the concept still.
- `docs/vision/captures/*.png` are screenshots of the app itself (1920x720, 100 dpi); they are not third-party art.
  `skin-show-marker.png` is a 1x1 marker pixel.
- The concept still shows a map with place names and no map attribution; that is a mock-up and not evidence either way.
- Conclusion: no evidence of third-party sourcing, none of AI generation, none of hand-made origin. The owner has to say.

## 2. Linked / built with (not vendored)

| Component | Use | Licence | Status |
|---|---|---|---|
| Qt 6 (Core, Network, Quick, Qml, Svg, WebSockets; optional WebEngine, Location, Positioning) | UI toolkit; CI uses 6.6.3 | LGPL-3.0 / GPL-2.0/3.0 / commercial. Most modules are usable under LGPL-3.0; **WebEngine and parts of Qt Location are LGPL/GPL with additional third-party (Chromium) terms.** | TO VERIFY per module. When shipping a device image, LGPL obligations apply (provide the licence text, allow relinking/replacing the Qt libraries, offer corresponding Qt source). Avoid static linking of Qt unless the implications are understood. |
| maplibre-native-qt 3.0.0 | native map (`find_package(QMapLibre 3.0.0)`), built by a Yocto recipe | Recipe declares `BSD-2-Clause & (LGPL-3.0-only \| GPL-2.0-only \| GPL-3.0-only) & MIT` with pinned licence checksums | Recipe-declared; TO VERIFY upstream |
| Yocto / OpenEmbedded layers, TI SDK, BeagleY-AI kernel/U-Boot | `yocto/` (only recipes/config in this repo, no upstream sources) | Various; each recipe carries its own `LICENSE` | Not reviewed |
| Python dependencies of `tools/` | stdlib, plus `websockets` (BBB hub tools, BSD-3-Clause) and optional `Pillow` (`tools/maplibre/analyze_screenshot.py`, HPND); `sd_notify` and `gps_nmea` are in-repo modules (`tools/bbb_hub/`) | Not vendored; installed by the user/image | Identified by import scan; no requirements file exists yet, versions not pinned |
| Node dependencies of `tools/spotify_firebase/functions` | `firebase-admin` (Apache-2.0), `firebase-functions` (MIT) and their transitive packages (`package-lock.json`) | Not vendored (installed by `npm`) | Direct-dependency licences from general knowledge, not re-checked here |
| `firmware/uno_vehicle_input` | Arduino sketch, no `#include` of any third-party library (only core Arduino API) | Project's own code (MIT) | VERIFIED by source scan |

## 3. Map data and online services (run-time, attribution required)

- **OpenStreetMap data** – © OpenStreetMap contributors, licensed under the
  [Open Database Licence (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/). Any display of OSM-derived
  maps must show the attribution **"© OpenStreetMap contributors"** with a link/notice to
  <https://www.openstreetmap.org/copyright>.
- **OpenFreeMap** (`https://tiles.openfreemap.org`) – vector tiles and glyphs used by the MapLibre styles
  (`src/ui/web/map/styles/embedded-liberty.*`, `config/maplibre/production-styles.json`, `MainV3.qml` trusted styles).
  **Requirement (VERIFIED against <https://openfreemap.org/> "Attribution" section, 2026-10-03):** attribution is
  required; "If you are using MapLibre, they are automatically added"; for alternative clients, print or video you must add
  **"OpenFreeMap © OpenMapTiles Data from OpenStreetMap"** (the "OpenFreeMap" part may be omitted, but is appreciated).
  Commercial use is allowed. The hosted TileJSON (`https://tiles.openfreemap.org/planet`) supplies the attribution
  `OpenFreeMap © OpenMapTiles Data from OpenStreetMap` (with links to openfreemap.org, openmaptiles.org and
  openstreetmap.org/copyright). The underlying licences are ODbL (OSM data) and CC BY 4.0 (OpenMapTiles schema/design).
  **What the repo shows today (VERIFIED by code search, not on-device):**
  - Web map (`src/ui/web/map/index.html`, WebEngine path): MapLibre's compact `AttributionControl` is enabled bottom-left. With
    the hosted OpenFreeMap style URLs the full attribution appears automatically. **Gap:** the embedded style
    (`embedded-liberty.json/.js`) overrides the source attribution with only `&copy; OpenStreetMap contributors`, so OpenMapTiles
    (and OpenFreeMap) are not credited when that style is used.
  - Native MapLibre path (`MapCenterMapLibreNative.qml`, `MainV3.qml`): no attribution text anywhere in the QML, and the
    maplibre-native-qt widget is not known to draw one. **Gap:** nothing credits OpenFreeMap/OpenMapTiles/OSM on screen
    (to be confirmed on the board).
  - Raster OSM fallbacks: `MapCenterBootShell.qml` and `MapCenterSnapshot.qml` draw "© OpenStreetMap" (without
    "contributors" and without a link); `MapCenterNative.qml` (raster `tile.openstreetmap.org`) draws none.
  **Recommended text:** vector (OpenFreeMap) map, small but legible in a map corner at all times:
  `OpenFreeMap © OpenMapTiles Data from OpenStreetMap`; raster OSM fallback: `© OpenStreetMap contributors`; plus a
  Settings/About/Legal screen with the full notice and the links (<https://www.openstreetmap.org/copyright>,
  <https://openfreemap.org>, <https://www.openmaptiles.org/>). The embedded style's `attribution` field should be changed to the
  same string. This repo change is outside this docs PR (Cluster HMI owns the QML).
- Other endpoints referenced in `src/` and `config/` (usage policies/attribution **TO VERIFY**; several are
  free community services with fair-use limits that are not suitable for production traffic):
  `tile.openstreetmap.org` (OSM tile usage policy), `nominatim.openstreetmap.org` (geocoding, ≤1 req/s,
  identifying User-Agent), `photon.komoot.io`, `router.project-osrm.org` (public demo server),
  `a.basemaps.cartocdn.com` (CARTO basemap terms/attribution), `tilecache.rainviewer.com` (RainViewer terms,
  attribution), `demotiles.maplibre.org` (MapLibre demo tiles only).
- Spotify integration (`tools/spotify*`) uses the Spotify Web API; Spotify Developer Terms and branding
  guidelines apply (TO VERIFY, not reviewed).

## 4. Open items for the owner

Resolved in this review: MapLibre GL JS header and licence text, Orbitron and Oxanium provenance and OFL texts,
firmware/vendored-code scan, OpenFreeMap attribution requirement, 5 of 8 SVG icon licences.

Still needs the owner (ThatGuy):

1. **Skin art ownership** – state whether the concept still (`docs/vision/skin-v2-concept-1920x720.png`) and the atlases
   derived from it are your own work / generated with a tool whose terms allow this use / sourced from someone else.
   Record the answer here. Until then: **TO CONFIRM**.
2. **Icons**: confirm or replace `fuel-svgrepo-com-yellow.svg` (public-domain vs ISC conflict), and identify
   `car-lights-car`, `engine` and `gearshift-shift` on svgrepo.com; keep the Line Awesome (MIT) credit for the oil-can icon in an About/Legal screen.
3. **On-screen attribution** – approve the text in section 3 and ask Cluster HMI to implement it (map corner + About/Legal) and to fix the embedded style's `attribution`.
4. Ship a licences/About screen or file list on the device image (OFL fonts, MapLibre BSD-3, Qt LGPL, Line Awesome MIT) – licence texts live in `licenses/` and `src/assets/fonts/`.
