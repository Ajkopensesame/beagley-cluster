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

## Toggle drive vs show (no binary rebuild)

On a **qml-dev** appliance, a marker file forces **show** (matrix depth):

```bash
# SHOW — write a valid 1x1 PNG marker, then restart
ssh beagley-ai "python3 -c \"import pathlib; pathlib.Path(\"/opt/beagley-cluster/qml-dev/.skin-show.png\").write_bytes(bytes.fromhex(\"89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082\"))\" && systemctl restart beagley_cluster"

# DRIVE — remove marker (embedded default)
ssh beagley-ai "rm -f /opt/beagley-cluster/qml-dev/.skin-show.png && systemctl restart beagley_cluster"
```

With a binary that exposes `BEAGLEY_SKIN_PROFILE` (already in `main.cpp`), set it in
`/etc/default/beagley-cluster.local` instead of using the marker:

```text
BEAGLEY_SKIN_PROFILE=show   # or drive
```

**Drive never enables MatrixRain** (dual rain hard-off). Embedded show uses cheap
`GaugeMatrixDepth` Text columns, not Canvas rain. Embedded magma is SG
`GaugeArcItem` only (no Canvas crust).
