# Orbitron (bundled)

| File | Family (name ID 1) | Style | usWeightClass |
| --- | --- | --- | --- |
| `Orbitron-Medium.ttf` | `Orbitron` | Medium | 500 |
| `Orbitron-Bold.ttf` | `Orbitron` | Bold | 700 |

- Designer: Matt McInerney. Copyright (c) 2009, Matt McInerney, with Reserved Font Name "Orbitron".
- License: SIL Open Font License 1.1 — full text in `OFL-Orbitron.txt` (copied verbatim from the upstream repo).
- Source: https://github.com/theleagueof/orbitron (commit `13e6a5222aa6818d81c9acd27edd701a2d744152`),
  files `Orbitron Medium.ttf` and `Orbitron Bold.ttf`, bundled **unmodified**.
- Why these and not the Google Fonts variable `Orbitron[wght].ttf`: Qt only registers the default
  (Regular) instance of a variable font added via `QFontDatabase::addApplicationFont` on this stack,
  so `font.weight: Font.Bold` would not change the glyphs. Static files are also unmodified, which keeps
  the OFL Reserved Font Name clause satisfied (no re-instancing/renaming).
- Medium (500) is the lightest weight the upstream static release ships that serves as the "regular"
  weight; Qt picks it for the default `Font.Normal` request.

Loaded at startup in `src/main.cpp` via `QFontDatabase::addApplicationFont(":/assets/fonts/...")`
(resources declared in `CMakeLists.txt` under `app_font_resources`). QML requests `font.family: "Orbitron"`.
