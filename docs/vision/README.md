# BeagleY Skin v2 — vision target

Locked concept still (success criteria for live 1920×720):

- [`skin-v2-concept-1920x720.png`](./skin-v2-concept-1920x720.png)

Pixel-close visual match to this still beats incremental Pearl polish.

## Atlas assets (from concept PNG)

Baked under [`atlas/`](./atlas/) and shipped as `src/ui/assets/skin-v2/`:

- `lava-annulus.png` — annular magma (OpacityMask progress on DialChrome)
- `lava-strip.png` — polar unwrap (reference / future shader map)
- `glass-rim.png` — specular glass ring overlay
- `gauge-face-matrix.png` — show-profile face plate

Drive composites the annulus via `GaugeAtlasMagma` (GPU OpacityMask). Show can enable the face plate + richer tip.

## What “done” looks like

- Deep glass gauge lenses on a near-black face
- Thick **molten lava** progress arcs (orange → hot yellow tip), not thin Pearl purple
- Subtle cyan **matrix depth** inside the glass (show profile)
- Speedo left / tach right with calm center readouts (KM/H + gear/odo; RPM×1000)
- Twin micro fuel% + coolant°C arcs in the tach
- Dark map chrome with purple frame accents and gold route/pose
- TL weather / TR radar corners; bottom swipe-up caret

## Profiles

| Profile | Env | Intent |
| --- | --- | --- |
| **drive** (appliance default) | `BEAGLEY_SKIN_PROFILE=drive` or embedded default | Glass + SG magma + map; matrix hard-off |
| **show** | `BEAGLEY_SKIN_PROFILE=show` or qml-dev override | Concept still match: matrix depth + richer lava |

Score captures against the concept PNG with the profile named in the filename.

Latest appliance stills live in [`captures/`](./captures/) (`skin-v2-drive-*.png` / `skin-v2-show-*.png`). `beagley_sync_qml.sh` uses rsync delete — re-create `SkinShowOverride.qml` after sync.

## Related env

```text
BEAGLEY_EFFECT_LEVEL=high
BEAGLEY_RENDER_PROFILE=embedded   # appliance
BEAGLEY_SKIN_PROFILE=drive|show
BEAGLEY_GAUGE_DEMO=1              # review needles without hub
```

## Toggle drive vs show (no binary rebuild)

On a **qml-dev** appliance, drop a tiny QML override next to MainV3
(`Loader` → `SkinShowOverride.qml`). No binary rebuild required for show/drive
toggle (running appliance binary may predate `BEAGLEY_SKIN_PROFILE`):

```bash
# SHOW
ssh beagley-ai "printf '%s\n' 'import QtQuick 2.15; QtObject { objectName: "skinShow" }' > /opt/beagley-cluster/qml-dev/src/ui/SkinShowOverride.qml && systemctl restart beagley_cluster"

# DRIVE (embedded default)
ssh beagley-ai "rm -f /opt/beagley-cluster/qml-dev/src/ui/SkinShowOverride.qml && systemctl restart beagley_cluster"
```

With a rebuilt binary that exposes `BEAGLEY_SKIN_PROFILE` (already in `main.cpp` on this branch), set it in `/etc/default/beagley-cluster.local` instead:

```text
BEAGLEY_SKIN_PROFILE=show   # or drive
```

**Drive never enables MatrixRain** (dual rain hard-off). Embedded show uses cheap
`GaugeMatrixDepth` Text columns, not Canvas rain. Embedded magma is SG
`GaugeArcItem` only (no Canvas crust).
