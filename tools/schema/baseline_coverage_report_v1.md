# baseline_coverage_report v1

Owner: `tools/vehicle_analysis/baseline_coverage.py`

Purpose: summarize whether a vehicle has enough known-good coverage to make
context-aware anomaly claims. This report does not diagnose faults. It tells the
operator which normal scenarios are strong, weak, or missing.

## Top-Level Shape

```json
{
  "version": 1,
  "kind": "baseline_coverage_report",
  "summary": {
    "score": 0.42,
    "statusCounts": {
      "strong": 3,
      "weak": 4,
      "missing": 4
    },
    "ready": false
  },
  "scenarios": [],
  "operatingContexts": {
    "observed": ["startup", "road_speed_drive"],
    "missing": ["cold_start", "heavy_load"]
  },
  "steadyState": {
    "readyModels": ["intake_airflow"],
    "models": []
  },
  "transitions": {
    "eventsSeen": {"first_fire": 6},
    "readyModels": ["startup_maf_response"],
    "models": []
  }
}
```

## Scenario Status

- `strong`: the matching model or event/context coverage is ready enough to use
  as known-good evidence.
- `weak`: some relevant data exists, but the system should avoid strong claims.
- `missing`: no useful known-good evidence has been captured for that scenario.

## Initial Scenarios

- startup response
- cold start
- hot restart
- warm idle
- intake airflow baseline
- MAP pressure baseline
- road cruise
- heavy load
- throttle tip-in
- shift response
- decel behavior

The report should be used to guide new known-good captures and active learning
prompts. It should not be shown as a repair recommendation.
