# `can_signals.json` v1

`can_signals.json` is the exported decoder dictionary produced by
`tools/can_reverse_workbench`. It maps raw CAN fields to stable named vehicle
signals consumed upstream of the cluster UI.

Example:

```json
{
  "version": 1,
  "generatedAt": "2026-04-11T00:00:00+00:00",
  "source": {
    "log": "/path/to/candump.log",
    "labels": "/path/to/guided_session.json",
    "analysisGeneratedAt": "2026-04-11T00:00:00+00:00"
  },
  "exportPolicy": {
    "minConfidence": 0.7,
    "requiresVerified": true,
    "unknownPolicy": "unverified candidates are not attached to human signal names"
  },
  "signals": {
    "rpm": {
      "canId": "0x100",
      "startBit": 0,
      "length": 16,
      "endian": "big",
      "signed": false,
      "scale": 0.25,
      "offset": 0.0,
      "unit": "rpm",
      "confidence": 0.93,
      "verified": true,
      "pipeline": {},
      "evidence": {}
    },
    "speedKph": {
      "canId": "0x101",
      "startBit": 16,
      "length": 16,
      "endian": "little",
      "signed": false,
      "scale": 0.01,
      "offset": 0.0,
      "unit": "kph",
      "confidence": 0.91,
      "verified": true,
      "pipeline": {},
      "evidence": {}
    }
  },
  "rejectedSignals": {}
}
```

## Required Signal Fields

- `canId`: hexadecimal CAN arbitration ID string.
- `startBit`: zero-based start bit. Byte-aligned fields preserve the original
  workbench semantics. Non-byte-aligned big-endian fields use MSB-first bit
  numbering; non-byte-aligned little-endian fields use LSB-first bit numbering.
- `length`: integer bit length in `[1, 32]`.
- `endian`: `big` or `little`.
- `signed`: boolean signedness.
- `scale`: multiplier applied to the raw integer value.
- `offset`: offset applied after scaling.
- `unit`: display/semantic unit such as `rpm` or `kph`.
- `confidence`: deterministic confidence in `[0, 1]`.
- `verified`: true for exported mappings. Unverified candidates must not appear
  under `signals`.
- `pipeline`: bit analysis, correlation, scaling, validation, and final decision
  evidence.
- `evidence`: scoring and calibration metadata used to justify the result.

Decoded value:

```text
value = raw_integer * scale + offset
```

## Contract

The dictionary is not a UI contract. The BBB decoder converts these raw CAN
fields into existing `vehicle_state` fields such as `rpm` and `speedKph`, so the
cluster gauges, maps, and navigation do not need rewrites.

The export policy is intentionally conservative: if scaling is not anchored, the
candidate stays in `rejectedSignals`/`analysis.json` as an unknown candidate with
confidence instead of being attached to a human signal name.
