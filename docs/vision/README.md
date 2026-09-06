# BeagleY Skin v2 — vision target

Locked concept still (success criteria for live 1920×720):

- [`skin-v2-concept-1920x720.png`](./skin-v2-concept-1920x720.png)

Pixel-close visual match to this still beats incremental Pearl polish.

## What “done” looks like

- Deep glass gauge lenses on a near-black face
- Thick **molten lava** progress arcs (orange → magenta), not thin Pearl purple
- Subtle cyan **matrix depth** inside the glass (show profile)
- Speedo left / tach right with calm center readouts (KM/H + gear/odo; RPM×1000)
- Twin micro fuel% + coolant°C arcs in the tach
- Dark map chrome with purple frame accents and gold route/pose
- TL weather / TR radar corners; bottom swipe-up caret

## Profiles

| Profile | Env | Intent |
| --- | --- | --- |
| **drive** (appliance default) | `BEAGLEY_SKIN_PROFILE=drive` or embedded default | Glass + visible lava-lite + map; matrix off |
| **show** | `BEAGLEY_SKIN_PROFILE=show` | Concept still match: matrix depth + richer lava |

Score captures against the concept PNG with the profile named in the filename.

## Related env

```text
BEAGLEY_EFFECT_LEVEL=high
BEAGLEY_RENDER_PROFILE=embedded   # appliance
BEAGLEY_SKIN_PROFILE=drive|show
BEAGLEY_GAUGE_DEMO=1              # review needles without hub
```
