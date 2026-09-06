# BeagleY Skin v2 — vision target

Locked concept still (success criteria for live 1920×720):

- [`skin-v2-concept-1920x720.png`](./skin-v2-concept-1920x720.png)

Pixel-close visual match to this still beats incremental Pearl polish.

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

## Related env

```text
BEAGLEY_EFFECT_LEVEL=high
BEAGLEY_RENDER_PROFILE=embedded   # appliance
BEAGLEY_SKIN_PROFILE=drive|show
BEAGLEY_GAUGE_DEMO=1              # review needles without hub
```

## Toggle drive vs show (no binary rebuild)

On a **qml-dev** appliance, drop a tiny QML override next to MainV3:

```bash
# SHOW
ssh beagley-ai "printf '%s\n' 'import QtQuick 2.15; QtObject {}' > /opt/beagley-cluster/qml-dev/src/ui/SkinShowOverride.qml && systemctl restart beagley_cluster"

# DRIVE (embedded default)
ssh beagley-ai "rm -f /opt/beagley-cluster/qml-dev/src/ui/SkinShowOverride.qml /opt/beagley-cluster/qml-dev/src/ui/skin-show.on && systemctl restart beagley_cluster"
```

With a rebuilt binary that exposes `BEAGLEY_SKIN_PROFILE` (already in `main.cpp` on this branch), set it in `/etc/default/beagley-cluster.local` instead:

```text
BEAGLEY_SKIN_PROFILE=show   # or drive
```

**Drive never enables MatrixRain** (dual rain hard-off). Embedded show uses cheap
`GaugeMatrixDepth` Text columns, not Canvas rain. Embedded magma is SG
`GaugeArcItem` only (no Canvas crust).
