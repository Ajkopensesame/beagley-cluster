# bbb_fault_event v1

Owner: `tools/bbb_hub/fault_recorder.py`

Purpose: define the persisted fault evidence packet written by the BBB fault
recorder when deterministic health checks emit actionable faults from
`_health.signalFaults`, enabled `_health.vehicleBaseline.findings`, or enabled
`_health.transitionMonitor.findings`.

This schema is an evidence packet, not a repair report. It captures the trigger
state, current source health, rolling context, and supporting evidence so later
reporting code can explain what was observed without re-running the live system.

## Boundary

- Detection truth comes from deterministic signal health, CAN diagnostics,
  learned baselines, and transition monitors.
- `bbb_fault_event` preserves evidence for later replay/report workflows.
- AI/report layers may summarize this packet, but must not turn it into repair
  instructions without additional evidence and the `vehicle_health_verdict`
  contract.

## Top-Level Shape

```json
{
  "version": 1,
  "kind": "bbb_fault_event",
  "eventId": "1700000100000-0001",
  "generatedAt": "2023-11-14T22:15:00+00:00",
  "faultFingerprint": "speedKph:source_disagreement:warning",
  "faults": [
    {
      "signal": "speedKph",
      "code": "source_disagreement",
      "severity": "warning",
      "message": "CAN/top-level speed disagrees with GPS speed",
      "details": {
        "deltaKph": 55.0
      }
    }
  ],
  "sourceHealth": {},
  "triggerState": {},
  "rollingBuffer": {
    "seconds": 20.0,
    "frames": []
  },
  "evidence": {},
  "recorder": {
    "outputDir": "/var/log/beagley-cluster/faults",
    "minIntervalSeconds": 10.0,
    "wallTimestamp": 1700000100.0,
    "monotonicTimestamp": 100.0
  }
}
```

## Required Fields

- `version`: integer schema version. Current value is `1`.
- `kind`: literal `bbb_fault_event`.
- `eventId`: stable event id made from trigger wall-clock milliseconds and a
  recorder-local sequence number.
- `generatedAt`: ISO-8601 UTC timestamp for the trigger.
- `faultFingerprint`: deterministic summary of fault signal, code, and severity.
- `faults`: normalized fault entries that triggered the event. Signal faults are
  copied from `_health.signalFaults`. Baseline and transition findings are
  converted into the same fault shape when their parent monitor is enabled and
  severity is `warning` or `error`.
- `sourceHealth`: copied `_health` object from the trigger state.
- `triggerState`: full `vehicle_state` after diagnostic enrichment at the
  trigger. Its `_diagnostic.activeFindings` are the deterministic source for
  public fault-event summaries; the event must not embed `vehicle_health_verdict`.
- `rollingBuffer.seconds`: configured pre-trigger buffer window.
- `rollingBuffer.frames`: recent safe JSON state snapshots. Each frame includes
  `wallTime`, `wallTimestamp`, `monotonicTimestamp`, and `state`.
- `evidence`: additional safe JSON evidence such as recent CAN frames, baseline
  snapshots, transition snapshots, or serial input state.
- `recorder`: recorder metadata, including output directory, suppress interval,
  trigger wall timestamp, and trigger monotonic timestamp.

## Fault Semantics

Fault entries should use normalized deterministic finding language:

- `signal`: affected signal or subject.
- `code`: machine-readable fault code, such as `source_disagreement`,
  `out_of_range`, `impossible_jump`, `source_stale`, or CAN diagnostic codes.
- `severity`: `info`, `warning`, or `error`.
- `message`: human-readable evidence summary.
- `details`: optional safe JSON details. Do not include raw secrets or private
  customer information here.

## Use

The event file can feed diagnostic replay, customer-facing summaries, and guided
workflows. It should be linked to `vehicle_health_verdict` when an AI/report
layer needs to make a cautious health judgment.
