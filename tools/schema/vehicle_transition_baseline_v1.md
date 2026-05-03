# vehicle_transition_baseline v1

Owner: `tools/bbb_hub/transition_monitor.py`

Purpose: store per-vehicle known-good event-response templates. This is the
transition sibling of the steady-state `vehicleBaseline` model.

## Top-Level Shape

```json
{
  "version": 1,
  "kind": "vehicle_transition_baseline",
  "generatedAt": 1700000000.0,
  "models": {
    "startup_maf_response": {
      "profile": "startup_maf_response",
      "count": 8,
      "metrics": {},
      "correlations": {},
      "eventCounts": {"first_fire": 8},
      "firstSeen": 1700000000.0,
      "lastSeen": 1700000100.0
    }
  },
  "lineage": {
    "truthSource": "per_vehicle_known_good",
    "eventsSeen": {"first_fire": 8},
    "vehicleProfile": "vehicle profile",
    "sessionIds": ["capture-001"],
    "thermalStartClasses": ["cold"],
    "observedContexts": ["startup"],
    "decoderVersions": ["can_signals_v1"]
  }
}
```

## Model Meaning

Each model records one target signal during one event type. The runtime aligns
samples around the event and learns metrics such as:

- before/after mean
- signed and absolute delta
- value range
- response lag
- slope
- noise score
- cross-signal correlation against reference signals

The stored template is statistical and interpretable. It is not a repair
instruction and it is not an AI-originated verdict.

## Event Types

Supported shared event names:

- `key_on`
- `crank_start`
- `first_fire`
- `idle_settle`
- `stall`
- `throttle_tip_in`
- `shift`
- `decel`
- `fan_on`

## Anomaly Classes

Transition findings use reusable anomaly classes:

- `no_response`
- `delayed_response`
- `too_small_delta`
- `too_large_delta`
- `stuck_flat`
- `wrong_sequence`
- `wrong_correlation`
- `unexpected_noise`
- `persistent_offset`
- `cross_signal_inconsistency`

Runtime verdicts may promote only Tier 0-2 evidence by default:

- Tier 0: trusted anchors
- Tier 1: verified decoded signals
- Tier 2: derived virtual anchors
- Tier 3: raw CAN candidates, exploratory unless manually approved
