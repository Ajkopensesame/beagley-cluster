# `vehicle_health_verdict` v1

Purpose: define the structured evidence contract an AI or report layer may use
to judge whether a vehicle capture appears healthy, limited, inconclusive, or
anomalous.

This schema does not replace deterministic source health, signal health, CAN
diagnostics, or learned baseline findings. It sits above them and records:

- the evidence inputs considered
- coverage of the observed operating conditions
- confidence in the judgment
- abstain rules
- the language the AI is allowed to use

Owner: `tools/bbb_hub` and future AI/reporting layers.

## Boundary

- `_diagnostic` in `vehicle_state` remains the short, deterministic, display-safe
  runtime status.
- `vehicle_health_verdict` is a richer judgment contract for AI assistants,
  replay reports, customer summaries, and guided workflows.
- AI may issue a health judgment only from this structured evidence model or an
  equivalent future versioned contract.

## Example

```json
{
  "version": 1,
  "kind": "vehicle_health_verdict",
  "generatedAt": "2026-05-03T08:15:00+00:00",
  "mode": "replay",
  "vehicleProfile": "make model year engine trim ecu-calibration",
  "captureRef": {
    "sessionId": "capture-001",
    "source": "diagnostic_replay",
    "decoderVersion": "can_signals_v1",
    "durationSec": 1240.5
  },
  "verdict": {
    "label": "probably_healthy",
    "summary": "No strong anomalies were observed in the captured conditions",
    "ok": true
  },
  "coverage": {
    "score": 0.87,
    "confidence": 0.91,
    "observedContexts": [
      "startup",
      "idle_stationary",
      "road_speed_drive",
      "highway_speed_drive"
    ],
    "missingContexts": [
      "cold_start",
      "heavy_load"
    ],
    "sourceCoverage": {
      "can": "good",
      "gps": "good",
      "serial": "not_used",
      "obd": "partial"
    },
    "sampleCounts": {
      "frames": 12405,
      "signalSamples": 6120,
      "baselineComparisons": 84
    }
  },
  "confidenceModel": {
    "score": 0.91,
    "evidenceConsistency": 0.94,
    "sourceTrust": 0.96,
    "modelApplicability": 0.83,
    "penalties": [
      {
        "code": "missing_cold_start",
        "weight": 0.08,
        "message": "No cold-start evidence was captured"
      }
    ]
  },
  "evidenceInputs": {
    "captureQuality": {
      "gpsOk": true,
      "canOk": true,
      "serialOk": null,
      "linkStale": false
    },
    "findingSummary": {
      "worstSeverity": "ok",
      "activeFindingCount": 0,
      "codes": []
    },
    "sourceHealth": {
      "busSilenceSeen": false,
      "canIdDropouts": 0,
      "payloadStuckEvents": 0,
      "decodedSignalStuckEvents": 0
    },
    "signalHealth": {
      "outOfRangeEvents": 0,
      "impossibleJumpEvents": 0,
      "sourceDisagreementEvents": 0
    },
    "baselineHealth": {
      "enabled": true,
      "readyModels": [
        "intake_airflow",
        "map_pressure"
      ],
      "anomalyCount": 0
    },
    "transitionHealth": {
      "enabled": true,
      "readyModels": [
        "startup_maf_response"
      ],
      "anomalyCount": 0,
      "windowsScored": 12,
      "windowsLearned": 10
    },
    "anchors": {
      "direct": [
        "rpm",
        "speedKph",
        "mafGps",
        "mapKpa",
        "coolantC"
      ],
      "derived": [
        {
          "name": "gearRatioProxy",
          "confidenceTier": "medium"
        },
        {
          "name": "accelLongitudinalMps2",
          "confidenceTier": "high"
        }
      ]
    }
  },
  "abstain": {
    "required": false,
    "reasons": [],
    "recommendedLabel": null
  },
  "allowedLanguage": {
    "maySay": [
      "appears healthy",
      "probably healthy",
      "no strong anomalies were observed",
      "capture limited",
      "insufficient evidence",
      "anomaly likely"
    ],
    "mustAvoid": [
      "guaranteed healthy",
      "fault free",
      "no problems exist",
      "definitely broken",
      "replace part X",
      "safe to operate"
    ],
    "mustIncludeLimitationsWhenPresent": true
  },
  "limitations": [
    "Observed conditions did not include a cold start",
    "This verdict applies only to the captured bus segment and operating states"
  ]
}
```

## Top-Level Fields

- `version`: currently `1`
- `kind`: `vehicle_health_verdict`
- `generatedAt`: UTC timestamp
- `mode`: `normal`, `replay`, `report`, or future mode labels
- `vehicleProfile`: exact make/model/year/engine/trim/decoder context when known
- `captureRef`: references the capture session, replay source, and decoder
- `verdict`: AI-usable judgment label and short summary
- `coverage`: how much of the relevant operating space was observed
- `confidenceModel`: why the confidence is what it is
- `evidenceInputs`: structured deterministic evidence the AI is allowed to use
- `abstain`: whether the AI must refuse a positive/negative judgment
- `allowedLanguage`: policy for wording
- `limitations`: concise missing-evidence or scope limits

## Verdict Labels

Allowed `verdict.label` values:

- `healthy`
- `probably_healthy`
- `capture_limited`
- `insufficient_evidence`
- `anomaly_likely`
- `anomaly_detected`

Recommended meaning:

- `healthy`: only for high-confidence, broad-coverage, internally consistent
  evidence with no material warning/error findings.
- `probably_healthy`: no strong anomalies observed, but some coverage or model
  limits remain.
- `capture_limited`: capture quality was degraded enough that conclusions should
  be cautious.
- `insufficient_evidence`: too little valid data to make a judgment.
- `anomaly_likely`: multiple supporting findings suggest abnormal behavior, but
  the evidence does not support a strong claim of root cause.
- `anomaly_detected`: strong warning/error evidence exists in well-covered
  operating conditions.

`verdict.ok` should be:

- `true` for `healthy` and `probably_healthy`
- `false` for `anomaly_likely` and `anomaly_detected`
- `null` or omitted for `capture_limited` and `insufficient_evidence`

## Evidence Inputs

The AI may rely on:

- source/capture quality
- deterministic signal findings
- CAN timing/findings
- learned baseline findings
- learned transition findings
- direct anchor availability
- derived/virtual anchor availability and confidence tier
- observed operating contexts
- sample counts and replay duration

The AI must not infer a health verdict from raw CAN bytes alone unless those
bytes have already been converted into deterministic evidence or verified signal
relationships.

### Minimum Evidence Shape

`evidenceInputs` should include at least:

- `captureQuality`
- `findingSummary`
- `sourceHealth`
- `signalHealth`
- `baselineHealth`
- `transitionHealth`
- `anchors`

## Coverage Score

`coverage.score` is a normalized `[0, 1]` measure of how much useful operating
space was observed.

Coverage should consider:

- capture duration
- number of valid samples
- source availability and freshness
- observed operating contexts
- whether relevant conditions were exercised, for example startup, idle, cruise,
  acceleration, deceleration, cold start, hot restart, heavy load

Suggested interpretation:

- `>= 0.90`: broad coverage
- `0.70 - 0.89`: good coverage
- `0.45 - 0.69`: partial coverage
- `< 0.45`: limited coverage

`coverage.confidence` is separate from coverage breadth. A short but very clean
capture may have high confidence in a narrow conclusion and still have partial
coverage.

## Confidence Score

`confidenceModel.score` is a normalized `[0, 1]` confidence in the verdict.

It should reflect:

- `evidenceConsistency`: whether the evidence agrees with itself
- `sourceTrust`: whether the inputs were fresh and stable
- `modelApplicability`: whether the learned models and vehicle profile match the
  captured conditions
- `penalties`: explicit downward adjustments for missing contexts, conflicting
  signals, stale sources, low replay duration, missing decoder coverage, or weak
  baseline readiness

Suggested interpretation:

- `>= 0.90`: high confidence
- `0.75 - 0.89`: good confidence
- `0.55 - 0.74`: moderate confidence
- `< 0.55`: low confidence

## Abstain Rules

The AI must set `abstain.required = true` when one or more of these apply:

- `health_stale`: `_health.stale` or equivalent link-stale evidence is true
- `capture_degraded`: capture quality is materially degraded
- `coverage_too_low`: `coverage.score < 0.45`
- `confidence_too_low`: `confidenceModel.score < 0.55`
- `conflicting_evidence`: strong signals disagree in ways the system cannot
  reconcile
- `vehicle_profile_unknown`: the decoder/profile/model applicability is too weak
- `baseline_not_ready`: a verdict depends on learned baseline behavior but the
  relevant models are not ready
- `conditions_not_exercised`: the target condition was not observed, for example
  no startup data for a startup health claim

When abstaining, `verdict.label` should usually be one of:

- `capture_limited`
- `insufficient_evidence`

The AI may still summarize what was and was not observed, but must not issue a
positive health claim or a strong fault claim.

## Allowed Language Policy

### Allowed Phrases

The AI may say:

- "appears healthy"
- "probably healthy"
- "no strong anomalies were observed"
- "capture limited"
- "insufficient evidence"
- "anomaly likely"
- "anomaly detected in the captured conditions"

### Restricted / Forbidden Phrases

The AI must avoid:

- "guaranteed healthy"
- "fault free"
- "no problems exist"
- "definitely broken"
- "safe to operate"
- "replace [component]" unless a separate repair workflow explicitly authorizes
  that language with supporting service data

### Required Qualifiers

When any limitation exists, the AI must mention it, such as:

- missing cold-start coverage
- missing heavy-load coverage
- degraded source quality
- only one bus segment observed
- learned baseline not fully ready

## Contract Rule

This schema is the gate between deterministic evidence and AI judgment.

The AI may be the component that says "this bus appears healthy" or "anomaly is
likely", but only when:

1. the evidence inputs are structured,
2. coverage is recorded,
3. confidence is recorded,
4. abstain rules are checked, and
5. wording follows the language policy above.
