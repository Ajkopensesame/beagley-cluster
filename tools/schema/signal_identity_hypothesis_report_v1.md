# `signal_identity_hypothesis_report.json` v1

`signal_identity_hypothesis_report.json` is an offline CAN workbench report for
unknown raw CAN candidates. It suggests likely signal classes and names, shows
the evidence behind those guesses, and can optionally export probable candidates
as low-trust diagnostic experiment inputs.

It is not a decoder dictionary. Verified decoder mappings continue to live only
in `can_signals.json`.

## Inputs

- Raw CAN log: candump or CSV frames.
- Optional guided OBD/GPS anchors.
- Optional decoded `vehicle_state` JSONL.
- Optional external AI command that receives compact evidence JSON and returns
  naming suggestions.

## Top-Level Shape

```json
{
  "version": 1,
  "schema": "signal_identity_hypothesis_report_v1",
  "generatedAt": "2026-05-03T00:00:00+00:00",
  "source": {
    "log": "/path/to/raw_can.candump",
    "labels": "/path/to/guided_session.json",
    "decoded": "/path/to/vehicle_state.jsonl"
  },
  "inputs": {
    "rawCan": true,
    "guidedAnchors": true,
    "guidedWindows": true,
    "decodedVehicleState": false
  },
  "policy": {},
  "frameStats": {},
  "anchorSummary": {},
  "decodedSignalSummary": {},
  "ai": {},
  "summary": {},
  "hypotheses": []
}
```

## Hypothesis Shape

```json
{
  "candidateId": "0x221:b16:l16:little:u",
  "canId": "0x221",
  "canIdInt": 545,
  "startBit": 16,
  "byteIndex": 2,
  "length": 16,
  "endian": "little",
  "signed": false,
  "suggested": {
    "name": "speed_like_candidate",
    "class": "speed_like",
    "source": "deterministic",
    "confidence": 0.86,
    "rationale": "tracks speedKph with lagged correlation"
  },
  "evidence": {
    "frameCount": 220,
    "sampleHz": 10.0,
    "range": 7200.0,
    "uniqueCount": 90,
    "correlations": [],
    "eventResponses": [],
    "counterScore": 0.02,
    "checksumScore": 0.01
  },
  "safety": {
    "promotionStatus": "probable",
    "safeToUse": true,
    "trust": "low",
    "allowedUses": ["diagnostic_low_trust"],
    "blockedUses": ["cluster_display", "authoritative_health_verdict"],
    "reason": "strong deterministic evidence; low-trust diagnostic export allowed"
  }
}
```

## Classes

`suggested.class` is one of:

- `switch`
- `state_enum`
- `continuous_sensor`
- `speed_like`
- `rpm_like`
- `pressure_like`
- `temperature_like`
- `percentage_like`
- `voltage_like`
- `airflow_like`
- `gear_or_ratio`
- `warning_lamp`
- `counter`
- `checksum_or_crc`
- `unknown`

## Promotion Status

- `unknown`: not usable.
- `candidate`: interesting, report-only.
- `probable`: auto-exportable to `diagnostic_candidate_signals.json` as
  low-trust diagnostic evidence.
- `verified`: reserved for the existing deterministic `can_signals.json` export
  path. The identity report must not create verified mappings.
- `rejected`: counter, checksum, noise, or wrong behavior.

## AI Boundary

AI is optional. The default path is deterministic.

When `--ai-command` or `SIGNAL_IDENTITY_AI_COMMAND` is set, the workbench sends a
compact evidence payload to that command on stdin. The command may return:

```json
{
  "suggestions": [
    {
      "candidateId": "0x221:b16:l16:little:u",
      "name": "front_left_wheel_speed",
      "class": "speed_like",
      "confidence": 0.84,
      "rationale": "tracks road speed and changes during decel"
    }
  ]
}
```

AI suggestions may change the suggested name/class for non-rejected candidates,
but they cannot promote a candidate and cannot override deterministic rejection.

## Low-Trust Export

`diagnostic_candidate_signals.json` contains only hypotheses whose safety block
has `promotionStatus: "probable"` and `safeToUse: true`.

Those exported candidates:

- are allowed only for `diagnostic_low_trust`
- must not be merged into `can_signals.json`
- must not drive cluster display fields
- must not be sole evidence for a health verdict
