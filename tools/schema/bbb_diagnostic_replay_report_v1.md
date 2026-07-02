# bbb_diagnostic_replay_report v1

Owner: `tools/bbb_hub/diagnostic_replay.py`

Purpose: define the report produced when recorded or synthetic `vehicle_state`
JSONL is replayed through the deterministic BBB diagnostic stack.

This report is a deterministic replay artifact. It summarizes observed
diagnostic states, known-good coverage, generated fault evidence, transition
findings, and the separate `vehicle_health_verdict` judgment. It is not a
repair directive.

## Boundary

- Runtime detection truth stays in signal health, CAN diagnostics, learned
  baselines, transition monitors, and `_diagnostic`.
- `bbb_diagnostic_replay_report` records what the replay stack observed.
- `vehicle_health_verdict` remains the AI/report judgment contract.
- Report consumers should prefer `faultEventSummaries` over raw
  `faultEventPaths`.

## Top-Level Shape

```json
{
  "version": 1,
  "kind": "bbb_diagnostic_replay_report",
  "summary": {
    "frames": 2,
    "anomalyFrames": 2,
    "limitedFrames": 0,
    "staleFrames": 0,
    "worstSeverity": "warning",
    "findingCounts": {
      "source_disagreement": 2
    },
    "faultEvents": 1
  },
  "diagnosticStatusCounts": {
    "anomaly_detected": 2
  },
  "severityCounts": {
    "warning": 2
  },
  "firstAnomaly": {
    "frame": 0,
    "timestamp": 1700000100.0,
    "diagnostic": {
      "version": 1,
      "mode": "replay",
      "ok": false,
      "severity": "warning",
      "status": "anomaly_detected",
      "summary": "CAN/TOP-LEVEL SPEED DISAGREES WITH GPS SPEED",
      "findingCount": 1,
      "activeFindings": [
        {
          "source": "signalMonitor",
          "subject": "speedKph",
          "code": "source_disagreement",
          "severity": "warning",
          "message": "CAN/top-level speed disagrees with GPS speed.",
          "confidence": 0.9,
          "details": {
            "gpsSpeedKph": 55.0,
            "deltaKph": 55.0
          }
        }
      ],
      "captureQuality": {
        "gpsOk": true,
        "canOk": true,
        "serialOk": true,
        "linkStale": false
      }
    }
  },
  "lastDiagnostic": {
    "version": 1,
    "mode": "replay",
    "ok": false,
    "severity": "warning",
    "status": "anomaly_detected",
    "summary": "CAN/TOP-LEVEL SPEED DISAGREES WITH GPS SPEED",
    "findingCount": 1,
    "activeFindings": [],
    "captureQuality": {
      "gpsOk": true,
      "canOk": true,
      "serialOk": true,
      "linkStale": false
    }
  },
  "faultEventPaths": [
    "/tmp/beagley-diagnostic-replay-faults/1700000100000-0001_speedKph-source_disagreement-warning.json"
  ],
  "faultEventSummaries": [
    {
      "version": 1,
      "kind": "bbb_fault_event_summary",
      "status": "anomaly_recorded",
      "severity": "warning",
      "customerSummary": "A warning-level anomaly was recorded for speedKph. Evidence: CAN/top-level speed disagrees with GPS speed."
    }
  ],
  "healthVerdict": {
    "kind": "vehicle_health_verdict"
  },
  "signalMonitor": {
    "enabled": true,
    "ok": false,
    "watching": ["coolantC", "fuelPct", "rpm", "speedKph"],
    "faultCount": 1
  },
  "sensorCoverage": {
    "version": 1,
    "kind": "bbb_sensor_coverage_report",
    "summary": {
      "observedSensors": 4,
      "coveredSensors": 2,
      "lowTrustSensors": 1,
      "unsupportedSensors": 1,
      "lowTrustShapeFindings": 0,
      "coverageRatio": 0.5,
      "gapRatio": 0.5
    },
    "surfaceSummary": {
      "statusSensors": {
        "covered": ["rpm", "speedKph"],
        "low_trust": ["autoWheelSpeedKph"],
        "unsupported": ["mysteryVoltage"]
      },
      "surfaceSensors": {
        "signal_health": ["rpm", "speedKph"],
        "source_agreement_anchor": [],
        "learned_baseline_target": [],
        "learned_baseline_context": [],
        "transition_target": [],
        "transition_reference": [],
        "transition_event_input": []
      },
      "surfaceCounts": {
        "signal_health": 2,
        "source_agreement_anchor": 0,
        "learned_baseline_target": 0,
        "learned_baseline_context": 0,
        "transition_target": 0,
        "transition_reference": 0,
        "transition_event_input": 0
      },
      "gapSensors": ["autoWheelSpeedKph", "mysteryVoltage"]
    },
    "sensors": [],
    "shapeFindings": []
  },
  "baselineCoverage": {
    "kind": "baseline_coverage_report"
  },
  "vehicleBaseline": {},
  "transitionMonitor": {},
  "transitionCoverage": {},
  "transitionFindings": [],
  "transitionBaselineReady": false,
  "faultRecorder": {}
}
```

## Summary Count Invariants

Replay reports carry redundant summary fields to make CLI and report consumers
simple. These fields must remain internally consistent:

- `diagnosticStatusCounts` is a map of `_diagnostic.status` to non-negative
  integer frame counts.
- `summary.frames` equals the sum of all `diagnosticStatusCounts` values.
- `summary.anomalyFrames` equals
  `diagnosticStatusCounts.anomaly_detected`, or `0` when absent.
- `summary.limitedFrames` equals `diagnosticStatusCounts.limited`, or `0` when
  absent.
- `summary.staleFrames` equals `diagnosticStatusCounts.data_stale`, or `0` when
  absent.
- `summary.findingCounts` is a map of non-empty normalized deterministic
  finding codes to non-negative integer observation counts. Replay increments
  counts from the full normalized finding set collected from `_health` on each
  frame (the same source used to build `_diagnostic.findingCount`). This may
  include findings not present in capped `_diagnostic.activeFindings` when a
  frame carries more findings than the active display cap.
- When `summary.anomalyFrames` is greater than `0`, the sum of all
  `summary.findingCounts` values is at least `summary.anomalyFrames`; every
  anomaly frame must be backed by at least one deterministic finding code.
- Finding counts must stay aligned with replay diagnostics. Every code present
  in `firstAnomaly.diagnostic.activeFindings` or
  `lastDiagnostic.activeFindings` is present in `summary.findingCounts` with a
  positive count.
- When the CLI writes enriched JSONL, aggregating normalized finding codes from
  each emitted row's `_health` monitor surfaces via the same collector used for
  `_diagnostic` must exactly match `summary.findingCounts`.
- `severityCounts` is a map of normalized deterministic severity to
  non-negative integer frame counts.
- `summary.frames` equals the sum of all `severityCounts` values.
- `summary.worstSeverity` is the highest severity present in `severityCounts`
  using the deterministic order `ok < info < warning < error`.
- For zero-frame reports, `severityCounts` is empty and
  `summary.worstSeverity` is `ok`.
- `summary.faultEvents` equals the number of entries in `faultEventPaths`.
- `summary.faultEvents` also equals the number of entries in
  `faultEventSummaries`, including summary-error entries.
- When the fault recorder is disabled, or when no frames were replayed, all
  three values are `0` / empty arrays.

## Diagnostic Snapshot Contract

`lastDiagnostic` is the final normalized `_diagnostic` snapshot produced during
replay. It is `null` only when no frames were replayed. `firstAnomaly` is `null`
until an anomaly is observed; after that it contains:

- `frame`: zero-based replay frame index.
- `timestamp`: replay wall timestamp for that frame.
- `diagnostic`: the normalized `_diagnostic` snapshot from that frame.

Replay snapshot invariants:

- When `summary.frames` is `0`, `lastDiagnostic` and `firstAnomaly` are both
  `null`, and `summary.anomalyFrames` is `0`.
- When `summary.frames` is greater than `0`, `lastDiagnostic` is a normalized
  `_diagnostic` object whose `status` is represented in
  `diagnosticStatusCounts`.
- When enriched JSONL is written, `lastDiagnostic` must match the final emitted
  row's `_diagnostic` object.
- When `summary.anomalyFrames` is `0`, `firstAnomaly` is `null`.
- When `summary.anomalyFrames` is greater than `0`, `firstAnomaly.frame` is an
  integer in `[0, summary.frames)`, and cannot be later than
  `summary.frames - summary.anomalyFrames`.
- When enriched JSONL is written and `firstAnomaly` is not `null`,
  `firstAnomaly.frame` and `firstAnomaly.diagnostic` must match the first emitted
  row whose `_diagnostic.status` is `anomaly_detected`.
- `firstAnomaly.diagnostic.status` is always `anomaly_detected`.
- `firstAnomaly.diagnostic.ok` is `false`, its severity is `warning` or
  `error`, and its `findingCount` is greater than `0`.

The `diagnostic` object in both locations uses the same deterministic shape as
the `_diagnostic` field in `vehicle_state`:

- `version`: `1`.
- `mode`: replay mode label such as `replay`.
- `ok`: boolean status flag.
- `severity`: one of `ok`, `info`, `warning`, or `error`.
- `status`: one of `nominal`, `limited`, `data_stale`, or
  `anomaly_detected`.
- `summary`: short display-ready status text.
- `findingCount`: total normalized current finding count.
- `activeFindings`: array of normalized current findings. The list may be
  capped for display, so it can be shorter than `findingCount`.
- `captureQuality.gpsOk`: boolean.
- `captureQuality.canOk`: boolean, or `null` when CAN is not configured.
- `captureQuality.serialOk`: boolean, or `null` when serial input is not
  configured.
- `captureQuality.linkStale`: boolean.

Each `activeFindings` item is deterministic evidence, not an AI judgment:

- `source`, `subject`, `code`, `severity`, and `message` are required
  non-empty strings.
- `severity` uses the same allowed values as the diagnostic snapshot.
- `confidence` is optional and, when present, is a number from `0.0` to `1.0`.
- `details` is optional and should contain only public, report-safe evidence
  fields such as observed deltas, limits, event type, or GPS comparison values.

Replay consumers should use `lastDiagnostic` and `firstAnomaly.diagnostic` for
deterministic detection truth. `healthVerdict` remains the separate
`vehicle_health_verdict` judgment contract.

## Health Verdict Contract

`healthVerdict` follows `tools/schema/vehicle_health_verdict_v1.md` and is the
AI/report judgment surface for the replay. Replay reports must include:

- `version: 1` and `kind: "vehicle_health_verdict"`.
- A non-empty `generatedAt` timestamp and replay/report `mode`.
- `captureRef` for the replay source and duration when available.
- `verdict.label`, `verdict.summary`, and `verdict.ok`, with `ok` set to
  `true` for healthy labels, `false` for anomaly labels, and `null` for
  abstaining labels such as `capture_limited` or `insufficient_evidence`.
- `coverage.score`, `coverage.confidence`, observed/missing contexts, source
  coverage, and non-negative sample counts.
- `confidenceModel.score`, component scores, and explicit penalty records.
- `evidenceInputs` containing capture quality, finding summary, source health,
  signal health, baseline health, transition health, and anchor availability.
- `abstain.required`, `abstain.reasons`, and `abstain.recommendedLabel`; when
  abstaining, `verdict.label` must match the recommended label.
- `allowedLanguage` and `limitations` so report wording remains cautious.

This object is not deterministic detection truth. Consumers must not decide
whether an anomaly was detected from `healthVerdict` alone; use `_diagnostic`,
`summary.anomalyFrames`, `summary.findingCounts`, and the deterministic evidence
surfaces for that.

## Signal Monitor Contract

`signalMonitor` is the final signal-health monitor snapshot for the replay. It
lets report consumers distinguish intentionally disabled signal monitoring from
observed clean signal health:

- `enabled` is a boolean.
- `ok` is a boolean final health flag from the monitor.
- `watching` is an array of signal names monitored on the final frame.
- `faultCount` is the number of final-frame signal-health faults.

The replay CLI summary should include a `signal_health` status line derived from
`signalMonitor.enabled`, `signalMonitor.ok`, `signalMonitor.faultCount`, and
`signalMonitor.watching`. When `signalMonitor.enabled` is `false`, CLI guidance
should say the signal-health monitor was disabled for that replay and must not
imply stale, bad, or disagreeing sensor evidence was checked and found clean.
When `signalMonitor.enabled` is `true` and `signalMonitor.ok` is `false`,
`faultCount` describes final-frame signal-health evidence; replay-level
recurrence and persisted evidence remain represented by `_diagnostic`,
`summary.findingCounts`, and `faultEventSummaries`.
Deterministic detection truth still comes from `_diagnostic`,
`summary.anomalyFrames`, and `summary.findingCounts`.

## Sensor Coverage Contract

`sensorCoverage` is the replay-wide inventory of sensor-like fields observed in
the input states. It exists so all-sensor scope does not silently collapse to
the few signals with built-in rules today.

The object must include:

- `version: 1`
- `kind: "bbb_sensor_coverage_report"`
- `summary.observedSensors`: number of observed sensor entries.
- `summary.coveredSensors`: sensors covered by deterministic signal health,
  source agreement, learned baseline target/context use, transition target/
  reference use, or transition event input use.
- `summary.lowTrustSensors`: low-trust auto-detected candidate sensors that may
  support coverage, availability, stuck/noisy shape evidence, and capture
  guidance, but must not drive strong repair conclusions.
- `summary.unsupportedSensors`: observed sensors with no deterministic rule,
  learned model, transition profile, or explicit low-trust policy yet.
- `summary.lowTrustShapeFindings`: report-only shape findings emitted for
  low-trust candidate sensors.
- `summary.coverageRatio`: deterministic `coveredSensors / observedSensors`,
  rounded to six decimal places. Use `0.0` when no sensors were observed.
- `summary.gapRatio`: deterministic `(lowTrustSensors + unsupportedSensors) /
  observedSensors`, rounded to six decimal places. Use `0.0` when no sensors
  were observed.
- `surfaceSummary`: deterministic, replay-wide sensor-name indexes that make
  coverage and gaps scannable without walking every `sensors[]` entry.
- `sensors[]`: one object per observed sensor path with `name`, `sampleCount`,
  `trustTier`, `status`, `surfaces`, `shapeFindings`, and `reason`.
- `shapeFindings[]`: flattened report-only shape findings copied from the
  relevant `sensors[].shapeFindings` entries. This list must exactly equal the
  concatenated per-sensor `shapeFindings[]` entries in `sensors[]` order.

Nested observed values must use stable dotted sensor names in this inventory.
For example, `gps.speedKph` is a direct anchor sensor with
`source_agreement_anchor` coverage. Other numeric GPS fields, such as
`gps.hdop`, are observed as direct anchors but remain `unsupported` until a
deterministic surface covers them. `drivetrain.gear` / `transmission.gear`
string values are transition event inputs with `transition_event_input`
coverage.
Boolean-like nested fields, such as `gps.fix`, are state flags rather than
numeric/string sensor observations and must stay out of `sensorCoverage`.
The only string-valued fields treated as observable sensors in report v1 are
`gear`, `drivetrain.gear`, and `transmission.gear`; other strings such as
`driveMode` or `gps.fixType` are metadata/state labels and must stay out of
`sensorCoverage` until a deterministic sensor policy covers them.
List- or dict-valued fields, such as raw CAN byte arrays, raw CAN frame
objects, satellite lists, or raw GPS report objects, are containers or metadata
rather than scalar sensor observations. They must stay out of `sensorCoverage`
unless the normalizer flattens them into explicit observable numeric or
allowlisted string sensor paths.

Allowed `status` values are `covered`, `low_trust`, and `unsupported`.
Allowed `trustTier` values are `verified_decoded`, `direct_anchor`,
`low_trust_candidate`, and `unknown`.
Allowed `surfaces[]` values are `signal_health`, `source_agreement_anchor`,
`learned_baseline_target`, `learned_baseline_context`, `transition_target`,
`transition_reference`, and `transition_event_input`.
Status, trust, surface, and reason fields must remain internally consistent:

- `covered` sensors must have at least one `surfaces[]` entry, must not use
  `trustTier: "low_trust_candidate"`, and must use reason
  `Observed with deterministic signal-health, baseline, transition, or source-agreement coverage.`
- `low_trust` sensors must use `trustTier: "low_trust_candidate"` and must use
  reason
  `Observed as low-trust diagnostic evidence only; needs promotion, rules, or known-good baseline support.`
- `unsupported` sensors must have empty `surfaces[]` and `shapeFindings[]`,
  must not use `trustTier: "low_trust_candidate"`, and must use reason
  `Observed but no deterministic rule, learned model, transition profile, or low-trust policy covers it yet.`

Verified decoded sensors are not automatically covered. If a verified sensor has
no deterministic signal-health rule, source agreement check, learned baseline
use, transition profile use, or other explicit surface, its status remains
`unsupported` until one is added.

`surfaceSummary.statusSensors` must contain sorted sensor-name lists for
`covered`, `low_trust`, and `unsupported`, exactly matching `sensors[].status`.
`surfaceSummary.surfaceSensors` must contain sorted sensor-name lists for every
allowed `surfaces[]` value, exactly matching the per-sensor surface assignments.
`surfaceSummary.surfaceCounts` must contain the corresponding list lengths.
`surfaceSummary.gapSensors` must be the sorted union of low-trust and
unsupported sensor names. Report generation must treat any mismatch between
`statusSensors`, `surfaceSensors`, `surfaceCounts`, or `gapSensors` and the
backing `sensors[]` entries as a contract error. These fields plus
`summary.coverageRatio` and `summary.gapRatio` are report navigation aids only;
they must not change `_diagnostic`,
`summary.findingCounts`, or `healthVerdict`.
Replay report contract tests should assert that `coverageRatio`, `gapRatio`,
`surfaceSummary`, `statusSensors`, `surfaceSensors`, `surfaceCounts`, and
`gapSensors` do not appear in diagnostic snapshots, finding-count keys, or
`healthVerdict`.

The zero-observed-sensor case is a valid replay result, not a missing report. In
that case `summary.observedSensors`, `coveredSensors`, `lowTrustSensors`,
`unsupportedSensors`, and `lowTrustShapeFindings` must all be `0`;
`coverageRatio` and `gapRatio` must both be `0.0`; `sensors[]` and
`shapeFindings[]` must be empty; `surfaceSummary.statusSensors` must still
contain `covered`, `low_trust`, and `unsupported` keys with empty lists;
`surfaceSummary.surfaceSensors` must contain every allowed surface key with an
empty list; `surfaceSummary.surfaceCounts` must contain every allowed surface
key with value `0`; and `surfaceSummary.gapSensors` must be empty. This edge
case must not create `_diagnostic` findings or finding-count entries.

The replay CLI summary should include a `sensor_coverage` status line derived
from `sensorCoverage.summary` and a `sensor_surfaces` status line derived from
`sensorCoverage.surfaceSummary.surfaceCounts`. The `sensor_coverage` line
should include `coverage_ratio` and `gap_ratio` alongside the exact observed,
covered, low-trust, unsupported, and shape-finding counts. When low-trust or
unsupported sensors are present, or when low-trust shape findings are present, guidance
should direct users to promote the sensor, add deterministic rules, or add
learned replay fixtures before treating the sensor as strong diagnostic truth.
For zero-observed-sensor replays, the CLI `sensor_coverage` line must report all
counts and ratios as zero, and the `sensor_surfaces` line must report every
surface count as `0` with `gaps=0`.

Low-trust shape findings use the same normalized finding fields as diagnostic
findings (`source`, `subject`, `code`, `severity`, `message`, optional
`confidence`, and optional `details`), but they live under `sensorCoverage`
only. They must not be copied into `_diagnostic.activeFindings`, must not
increment `summary.findingCounts`, and must not by themselves change
`healthVerdict.verdict.label`. They are capture and promotion guidance until the
sensor is verified or backed by enough known-good baseline evidence.

Initial low-trust shape codes are:

- `low_trust_candidate_stuck_flat`: a candidate stayed effectively flat across
  enough replay samples.
- `low_trust_candidate_noisy_or_flapping`: a candidate oscillated across enough
  replay samples with repeated direction changes.

No other low-trust shape code is valid in report version 1 unless this schema
and the replay contract tests are updated together. The allowlisted low-trust
shape codes must remain absent from `summary.findingCounts` and every
`_diagnostic.activeFindings[].code`; active diagnostic findings must not use
`source: "sensorCoverage"`.

Every low-trust shape finding must include report-safe `details` that preserve
capture provenance: non-empty `candidateId`, `trustTier:
"low_trust_candidate"`, `trustMetadataSource`, positive `sampleCount`,
non-negative `durationSec`, and non-negative `valueRange`. Allowed
`trustMetadataSource` values are `diagnostic_candidate_signals_sidecar`,
`sensorTrust`, `_health.sensorTrust`, `diagnosticCandidateSignals`, and
`_health.diagnosticCandidateSignals`. `low_trust_candidate_stuck_flat` findings
must also include `shape: "stuck_flat"` and non-negative `flatLimit`.
`low_trust_candidate_noisy_or_flapping` findings must include `shape:
"noisy_or_flapping"`, positive `directionChanges`, positive
`significantSteps`, and non-negative `stepEpsilon` and `noisyRangeLimit`.
If a low-trust sensor has enough replay samples for shape analysis but its trust
metadata does not include a stable non-empty `candidateId`, the replay must
suppress `shapeFindings[]` for that sensor and may add
`shapeFindingSuppressedReason` with the message `Low-trust shape evidence
suppressed because trust metadata lacks stable candidateId provenance.` on the
`sensorCoverage.sensors[]` entry. This keeps ambiguous future-sensor shape
evidence in coverage guidance and out of diagnostic truth until provenance
exists.

The replay CLI may receive low-trust candidate metadata from
`--diagnostic-candidate-signals /path/to/diagnostic_candidate_signals.json`.
That file must follow `tools/schema/signal_identity_hypothesis_report_v1.md`'s
candidate export shape (`kind: "diagnostic_candidate_signals"` with a
`candidates` object). Candidate names observed in `vehicle_state` should appear
in `sensorCoverage.sensors[]` with `trustTier: "low_trust_candidate"` and
`status: "low_trust"` unless they are later promoted to verified decoded
sensors with deterministic rules or learned baseline support.
Candidate names present only in the sidecar export and not observed in replay
rows are metadata, not sensor observations; they must not appear in
`sensorCoverage.sensors[]`.
If a sidecar candidate has missing or blank `candidateId`, it may still
contribute low-trust coverage, but it must use the same
`shapeFindingSuppressedReason` behavior above and must not emit report-only
shape findings until stable candidate provenance exists.

Replay rows may also carry trust metadata directly in `vehicle_state` using
top-level or `_health.sensorTrust` entries, or top-level or
`_health.diagnosticCandidateSignals` entries with the same
`diagnostic_candidate_signals` candidate shape. Inline row metadata should be
honored without requiring the CLI sidecar export. Inline metadata does not need
to carry `trustMetadataSource`; when a low-trust shape finding is emitted, the
replay must preserve the row-provided `candidateId` in `details.candidateId`
and normalize `details.trustMetadataSource` from the metadata path that supplied
the trust decision.
Inline metadata names that are not observed as sensor values in replay rows are
metadata, not sensor observations; they must not appear in
`sensorCoverage.sensors[]` until a value is present in `vehicle_state`.

## Baseline Coverage Contract

`baselineCoverage` follows `tools/schema/baseline_coverage_report_v1.md` and
describes known-good capture coverage for replay guidance. Replay reports must
include:

- `version: 1` and `kind: "baseline_coverage_report"`.
- `summary.score` as the rounded average of scenario scores, normalized from
  `0.0` to `1.0`.
- `summary.statusCounts` with exactly `strong`, `weak`, and `missing`
  non-negative integer counts.
- `summary.strongScenarios`, `summary.weakScenarios`, and
  `summary.missingScenarios` matching `summary.statusCounts`.
- `summary.ready` as a boolean readiness signal for stronger known-good
  coverage claims.
- `summary.nextSteps` as prioritized guidance entries. Each entry must point to
  an existing non-strong scenario and include the scenario key, label, status,
  score, next-step text, and missing evidence.
- `scenarios` with non-empty `key`, `label`, and `category`, status of
  `strong`, `weak`, or `missing`, normalized score, evidence, missing evidence,
  and `nextStep`.
- `operatingContexts`, `steadyState`, and `transitions` surfaces that describe
  observed contexts, ready steady-state models, ready transition models, and
  transition event counts.

This object guides capture planning and active learning. It does not diagnose a
fault and must not be treated as repair guidance.

Replay CLI summaries should keep baseline coverage guidance separate from
learned steady-state baseline availability. The CLI should print a
`vehicle_baseline` status line derived from `vehicleBaseline.enabled` and
`baselineCoverage.steadyState.readyModels`. When `vehicleBaseline.enabled` is
`false`, CLI guidance should say the vehicle baseline monitor was disabled for
that replay and should not print learned-baseline capture steps as though model
readiness were merely missing. Report consumers should still preserve
`baselineCoverage` for deterministic capture planning, but must inspect
`vehicleBaseline.enabled` before treating missing steady-state ready models as a
coverage gap.

If both `vehicleBaseline.enabled` and `transitionMonitor.enabled` are `false`,
the CLI should show both disabled states independently. `healthVerdict` may
still abstain with `insufficient_evidence`, but that judgment must remain
separate from the monitor-disabled truth in the report.

## Vehicle Baseline Contract

`vehicleBaseline` is the final learned steady-state baseline snapshot from
replay. It describes model readiness and persistence health:

- `enabled` is a boolean.
- `storagePath` and `lastError` are `null` or non-empty strings.
- `writes` is a non-negative integer persistence count.
- `models` is a non-empty list of learned baseline model snapshots.
- Each model includes non-empty `name`, `target`, `unit`, and `status`; optional
  `reason`; normalized `confidence`; boolean `ready`; non-negative
  `bucketCount`, `totalSamples`, and `activeAnomalies`; and `lastBucket` as
  `null` or a non-empty string.
- When a model is `ready`, it must have observed at least one bucket and at
  least one sample.

Learned-baseline anomaly evidence is exposed through normalized `_diagnostic`
findings with `source: "vehicleBaseline"` and may also appear in
`summary.findingCounts`. Those findings are deterministic evidence, not AI
judgments. Public fields must include normalized severity, non-empty code and
message, confidence, and report-safe details such as the model name, value, or
suspected causes when available.

## Transition Surface Contract

Replay reports expose transition-monitor state separately from replay finding
history:

- `transitionMonitor` is the final transition monitor snapshot.
- `transitionCoverage` equals `transitionMonitor.coverage`.
- `transitionFindings` is the accumulated replay evidence list, capped at the
  first 50 historical transition findings for report size.
- `transitionBaselineReady` is `true` when any
  `transitionMonitor.models[].ready` value is `true`.

`transitionMonitor` contains:

- `enabled` and `ok` booleans.
- `storagePath` and `lastError` as `null` or non-empty strings.
- `activeEvent` as `null` or an event object with name, timestamp, index, and
  evidence.
- `coverage.eventsSeen`, `coverage.windowsScored`,
  `coverage.windowsLearned`, `coverage.pendingWindows`, and
  `coverage.readyModels`.
- `models`, where each model includes name, event type, target, unit, signal
  tier, readiness, window count, first/last seen timestamps, event counts, and
  metric snapshots.
- `findings`, the current monitor findings at the final snapshot.

Each transition finding in `transitionMonitor.findings` or
`transitionFindings` is deterministic evidence from `source:
"transitionMonitor"`. It must use a normalized finding shape and include
transition details such as `eventType`, `anomalyClass`, baseline window count,
signal tier, observed/expected deltas, observed/expected ranges, and optional
suspected causes.

Transition findings are evidence objects, not verdict objects. They must not
embed `healthVerdict`, `verdict`, `abstain`, `allowedLanguage`, or
`limitations` fields. `healthVerdict` remains the separate
`vehicle_health_verdict` judgment surface.

Because `transitionMonitor` is the final snapshot and `transitionFindings` is
the replay history, `transitionMonitor.ok` can be true while
`transitionFindings` is non-empty. Consumers should use `transitionFindings`
for historical replay evidence and `_diagnostic` / summary counts for
deterministic detection truth.

The replay CLI summary should include a transition status line derived from
these same report fields: `transitionMonitor.enabled`,
`transitionBaselineReady`, the number of `transitionFindings`, and
`transitionCoverage.readyModels`. When `transitionMonitor.enabled` is `false`,
CLI guidance should say the transition monitor was disabled for that replay and
must not ask for known-good transition captures or imply missing learned
baseline readiness. When transition findings are present, CLI guidance should
direct users to deterministic `transitionFindings` evidence and must not imply
that `faultEventSummaries` should exist for transition-only anomalies. When no
transition baseline is ready and no transition findings are present with the
monitor enabled, CLI guidance should ask for repeated known-good transition
captures.

## Zero-Frame Replay Semantics

An empty JSONL input is a valid replay input. It means the replay stack received
no vehicle frames, not that the vehicle was observed to be healthy.

For a zero-frame replay:

- `summary.frames`, `summary.anomalyFrames`, `summary.limitedFrames`,
  `summary.staleFrames`, and `summary.faultEvents` are `0`.
- `summary.worstSeverity` is `ok` because no deterministic severity was
  observed.
- `summary.findingCounts`, `diagnosticStatusCounts`, and `severityCounts` are
  empty objects.
- `firstAnomaly` is `null`.
- `lastDiagnostic` is `null`.
- `faultEventPaths` is `[]`.
- `faultEventSummaries` is `[]`.
- The enriched JSONL output, when requested, is empty.
- No fault-event directory or file is required to exist.
- `healthVerdict` still follows the separate `vehicle_health_verdict` contract
  and must abstain. The current replay contract reports
  `abstain.required: true`, `abstain.recommendedLabel: "capture_limited"`, and
  `verdict.label: "capture_limited"` because no capture evidence was present.

Report consumers must treat this as insufficient captured evidence. Empty
diagnostic counts or fault-event summaries in a zero-frame replay must not be
presented as a nominal or healthy vehicle result.

## JSONL Input Formatting

Replay input is newline-delimited JSON. Each non-empty row must parse to one
JSON object that represents a `vehicle_state`-like frame.

Input formatting rules:

- Blank lines and whitespace-only lines are ignored.
- Valid object rows are replayed in file order after blank-line filtering.
- Input loading is all-or-nothing: every non-empty row must parse and validate
  before replay starts.
- A file containing only blank or whitespace-only lines is a valid zero-frame
  replay and follows the zero-frame semantics above.
- A malformed JSON row fails the command before replay starts.
- A row that parses successfully but is not a JSON object also fails the command
  before replay starts.
- The same failure rule applies when earlier rows were valid; valid rows before
  a later malformed or non-object row are not partially replayed.
- On those failures, no report, enriched JSONL, or fault-event output should be
  produced.

## CLI Input Failure Semantics

Malformed input is different from a valid zero-frame replay. If the replay CLI
cannot load `--state-jsonl`, if the supplied path does not exist, or if any
non-empty row is not a JSON object, it does not produce a
`bbb_diagnostic_replay_report`.

For input-load failures:

- The process returns exit code `2`.
- A single guidance line is written to stderr with the prefix
  `[diagnostic-replay] failed:`.
- The guidance includes the underlying path. For a missing `--state-jsonl` path,
  this includes the missing filename and file-not-found error.
- For malformed or invalid JSONL rows, the guidance includes the line number,
  JSON parse error, or validation error when available.
- No replay report JSON is written, even if `--report` was supplied.
- No enriched JSONL is written, even if `--enriched-jsonl` was supplied.
- No fault-event directory or evidence file is required to exist, even if
  `--fault-dir` was supplied.
- No `healthVerdict`, `_diagnostic`, `faultEventSummaries`, or baseline coverage
  object exists because replay did not start.

Automation and report consumers should treat exit code `2` as a command/input
failure that needs capture or fixture repair. It must not be summarized as a
vehicle anomaly, nominal replay, zero-frame replay, or AI health verdict.

## Preferred Fault Evidence Surface

`faultEventSummaries` is the stable report-consumer surface. It contains safe,
report-ready summaries derived from persisted `bbb_fault_event` files:

- `kind`: `bbb_fault_event_summary`.
- `eventRef`: event id, generated timestamp, fingerprint, source kind, and raw
  event path when available.
- `status`: `anomaly_recorded` or `evidence_recorded`.
- `severity`: worst normalized deterministic severity.
- `customerSummary`: cautious evidence wording with no repair instruction.
- `primaryFinding` and `findings`: normalized public findings.
- `triggerContext`: operating state, `_diagnostic` status/summary, capture
  quality, and selected safe trigger signals.
- `evidenceSummary`: rolling-frame count, buffer window, evidence keys, and
  source-health keys.
- `responsibleUse`: explicit flags that the summary is not a repair directive
  and requires corroboration.

For normal `bbb_fault_event_summary` entries, `primaryFinding` is traceable to
the persisted event's deterministic trigger state. When `primaryFinding` is not
`null`, the same normalized `source`, `subject`, `code`, `severity`, and
`message` must be present in
`bbb_fault_event.triggerState._diagnostic.activeFindings`. The summary must not
embed `healthVerdict`, `verdict`, `abstain`, or `allowedLanguage`; those remain
separate report-judgment surfaces.

`faultEventPaths` remains in the report for traceability and debugging. New
report-generation code should not require reopening those paths unless it needs
the full raw evidence packet.

`faultEventSummaries` is positionally aligned with `faultEventPaths`: for every
index `i`, `faultEventSummaries[i].eventRef.path` equals `faultEventPaths[i]`.
This applies to normal `bbb_fault_event_summary` entries and to
`bbb_fault_event_summary_error` entries.

If a fault-event file cannot be read, the corresponding summary uses
`kind: "bbb_fault_event_summary_error"` with `eventRef.path` and `error`.

## Fault Recorder Health Contract

`faultRecorder` is the replay-local health surface for persisted evidence
capture. It reports recorder state, not vehicle health:

- `enabled` is a boolean.
- `outputDir` is a non-empty string.
- `bufferSeconds` is a non-negative number.
- `bufferFrames`, `maxEventFiles`, `maxTotalBytes`, and `writes` are
  non-negative integers.
- `lastEventPath` is `null` or a non-empty string.
- `lastError` is `null` or a non-empty string.
- In replay reports, `faultRecorder.writes` equals the number of entries in
  `faultEventPaths`.
- When `faultEventPaths` is non-empty, `faultRecorder.lastEventPath` equals the
  last path in `faultEventPaths`; otherwise it is `null`.

This surface must not be interpreted as deterministic detection truth. Use
`_diagnostic`, summary counts, and finding counts for detection truth; use
`faultRecorder` only to explain whether evidence files were persisted.

The replay CLI summary should include a `fault_recorder` status line derived
from `faultRecorder.enabled`, `faultRecorder.writes`, and
`faultRecorder.lastEventPath`. When `faultRecorder.enabled` is `false`, CLI
guidance should say evidence persistence was disabled and that deterministic
findings may still be present.
When the recorder is enabled and writes an event, the CLI should report
`last_event=present`, and `faultRecorder.writes`, `summary.faultEvents`,
`faultEventPaths`, `faultEventSummaries`, and the persisted event's
`triggerState._diagnostic` must remain traceable to the same deterministic
finding.

## Suppressed Duplicate Fault Semantics

The fault recorder may suppress duplicate fault-event writes inside its
configured fingerprint interval. Suppression affects evidence persistence only;
it does not suppress deterministic detection.

When repeated frames carry the same deterministic fault:

- `_diagnostic`, `diagnosticStatusCounts`, `severityCounts`,
  `summary.anomalyFrames`, and `summary.findingCounts` still count every replay
  frame where the condition is detected.
- `summary.faultEvents`, `faultEventPaths`, and `faultEventSummaries` only count
  persisted `bbb_fault_event` files.
- Enriched JSONL rows may show `_health.faultRecorder.suppressed: true` and a
  `suppressedFingerprint` for duplicate frames.
- After the recorder's suppression interval expires, the same deterministic
  fault fingerprint may produce another persisted `bbb_fault_event`; finding
  counts still represent all detected frames, not just persisted events.
- Report consumers must not compare `summary.findingCounts` directly to
  `summary.faultEvents`; they represent detection observations and persisted
  evidence events respectively.

Replay CLI coverage should include duplicate suppression cases where
`summary.findingCounts` and `diagnosticStatusCounts` continue to count every
deterministic finding, while the `fault_recorder` status line,
`summary.faultEvents`, `faultEventPaths`, and `faultEventSummaries` reflect only
persisted event files.
It should also cover suppression-expiry cases where a later repeat of the same
fault fingerprint writes another event after the recorder interval expires; in
that case `fault_recorder` should show the updated write count and each
`faultEventSummaries[]` entry should remain traceable to its matching
`faultEventPaths[]` event and trigger `_diagnostic`.

## Disabled Fault Recorder Semantics

The replay CLI can run with `--disable-fault-recorder`. This disables evidence
file persistence only; it does not disable deterministic anomaly detection.

When the fault recorder is disabled:

- `_diagnostic`, `summary.anomalyFrames`, `summary.findingCounts`,
  `diagnosticStatusCounts`, `severityCounts`, `firstAnomaly`, and
  `lastDiagnostic` still report replay detection truth.
- `healthVerdict` still follows the separate `vehicle_health_verdict` contract
  and must not be treated as the source of deterministic detection truth.
- `faultRecorder.enabled` is `false` and `faultRecorder.writes` is `0`.
- `summary.faultEvents` is `0` because it counts persisted evidence events.
- `faultEventPaths` is `[]`.
- `faultEventSummaries` is `[]` because there are no persisted
  `bbb_fault_event` files to summarize.
- No fault-event directory or file is required to exist.

Report consumers must not interpret empty `faultEventSummaries` as nominal
vehicle health. Use the diagnostic fields above to decide whether anomalies were
detected, and use `faultEventSummaries` only as the safe surface for persisted
fault evidence when event recording is enabled.

## Replay Fixture Index

Replay fixtures are indexed in
`tests/fixtures/diagnostic_replay_fixture_index.json`. The index records what
each JSONL fixture proves and the expected headline report counts:
`summary.frames`, `summary.anomalyFrames`, `summary.faultEvents`,
`diagnosticStatusCounts`, `severityCounts`, `summary.findingCounts`,
`healthVerdict.verdict.label`, and `transitionBaselineReady`.
Entries may include `diagnosticCandidateSignals`, a path to a
`diagnostic_candidate_signals.json` fixture that must be supplied to the replay
runner alongside the state JSONL.
Entries may include `baselineProfiles`, a list of fixture-scoped learned
baseline profile definitions appended to the default profiles. Use this only for
synthetic replay fixtures that prove newly verified or auto-detected sensors can
gain `learned_baseline_target` or `learned_baseline_context` coverage without
adding a hard-coded signal-health rule. Each profile includes `name`, `target`,
`unit`, and `features[]` entries with `signal` and `bucketSize`.
Paired fixtures may combine `baselineProfiles` with
`replayOptions.vehicleBaselineEnabled: false` to prove those learned-baseline
surfaces disappear and verified sensors fall back to `unsupported` when no other
deterministic surface covers them.
Entries may include `transitionProfiles`, a list of fixture-scoped transition
profile definitions appended to the default profiles. Use this for synthetic
replay fixtures that prove newly verified or auto-detected sensors can gain
`transition_target` or `transition_reference` coverage without adding a
hard-coded signal-health rule or learned baseline. Each profile includes `name`,
`eventType`, `target`, `unit`, and `referenceSignals[]`.
Paired fixtures may combine `transitionProfiles` with
`replayOptions.transitionMonitorEnabled: false` to prove those transition
surfaces disappear and verified sensors fall back to `unsupported` when no other
deterministic surface covers them.
Entries may also include `replayOptions.signalHealthEnabled: false` when a
fixture intentionally proves behavior with deterministic signal health disabled.
Use `replayOptions.vehicleBaselineEnabled: false` when a fixture intentionally
proves behavior with learned vehicle baselines disabled.
Use `replayOptions.transitionMonitorEnabled: false` when a fixture intentionally
proves behavior with transition monitoring disabled.
Use `replayOptions.faultRecorderEnabled: false` when a fixture intentionally
proves deterministic detection truth with persisted fault-event evidence
disabled.

The index also records deterministic, operator-facing surfaces that should stay
stable for each fixture: `firstAnomaly.frame`, `firstAnomaly.diagnostic` status,
severity, finding count, and active finding codes; final
`lastDiagnostic.status`, `lastDiagnostic.severity`,
`lastDiagnostic.findingCount`, `lastDiagnostic.activeFindings[].code`,
`signalMonitor.enabled`, `signalMonitor.ok`, `signalMonitor.faultCount`,
`signalMonitor.watching`, `sensorCoverage.summary`, optional
`sensorCoverageSurfaceSummary` partial expectations for
`sensorCoverage.surfaceSummary`, optional `baselineCoverage.steadyState`
headline fields, optional `transitionCoverage` headline fields, optional
`cliSummaryIncludes` / `cliSummaryExcludes` snippets for operator guidance such
as `sensor_coverage`, `sensor_surfaces`, vehicle-baseline, and transition
guidance lines, `faultRecorder.enabled`, `faultRecorder.writes`, and whether
`faultRecorder.lastEventPath` is present.
Low-trust candidate fixtures should also assert whether report-only
`sensorCoverage.shapeFindings` are expected, and those findings must not change
diagnostic anomaly counts. Multi-candidate low-trust fixtures should include
per-sensor shape expectations for each subject so the flattened report evidence
stays ordered and traceable to `sensorCoverage.sensors[]`.
Representative, anomaly, and future-sensor fixtures should include
`sensorCoverageSensors` expectations for the named sensors that prove trust and
coverage behavior. Each entry may assert `sampleCount`, `status`, `trustTier`,
`surfaces`, `reason`, `shapeFindingCodes`, `shapeFindingCandidateIds`, and
`shapeFindingTrustMetadataSources` so broad replay tests catch per-sensor drift
that aggregate summary counts would miss. Entries may also assert
`sensorCoverageSurfaceSummary.gapSensors`, selected
`sensorCoverageSurfaceSummary.statusSensors`, selected
`sensorCoverageSurfaceSummary.surfaceSensors`, or
`sensorCoverageSurfaceSummary.surfaceCounts` values to prove the report-level
all-sensor gap and surface index remains aligned with representative covered,
low-trust, unsupported, learned-baseline, and transition fixtures.
Entries may also assert
`absentSensorCoverageSensors` for sidecar-only or inline-metadata-only
candidates that must stay absent from `sensorCoverage.sensors[]` until observed
in replay rows. Entries may assert `ignoredSensorCoverageSensors` for fields
present in replay rows but intentionally ignored because their value type is not
observable as a sensor, such as boolean flags, non-gear string labels, or
list/dict containers that must first be flattened into explicit sensor paths.
When a fixture uses `diagnosticCandidateSignals`, non-empty
`shapeFindingCandidateIds` should match the exported candidate ids for those
sensors. When a fixture uses row-level trust metadata without a sidecar export,
`shapeFindingCandidateIds` should match
the row-provided candidate ids and `shapeFindingTrustMetadataSources` should
name the top-level or `_health` metadata path. Fixtures proving that low-trust
shape evidence is suppressed for missing candidate provenance, from either a
sidecar export or inline row metadata, should assert an empty
`shapeFindingCodes` list and the expected
`shapeFindingSuppressedReason`. Fixtures proving that low-trust or unsupported
sensors do not drive strong health claims may assert
`healthVerdictAbstainRequired: true`.

When adding or changing a replay fixture, update that index in the same change.
`tests/test_diagnostic_replay.py` replays every indexed fixture, writes enriched
JSONL, and fails if the documented counts or monitor surfaces drift from the
generated report. Status and severity expectations are also aggregated from the
enriched `_diagnostic` rows, and snapshot expectations are checked against the
first anomalous and final enriched rows.

Fixture coverage should not collapse to a single target sensor. The anomaly
scope is all available sensors, including sensors that will be automatically
detected and promoted later. Keep non-MAF transition or learned-baseline
fixtures in the index so replay coverage proves deterministic anomaly detection
can surface other normalized sensors such as `mapKpa` or `rpm`, and add future
fixtures when newly discovered sensors gain signal-health rules, learned
baselines, transition profiles, or low-trust coverage behavior.

## Related Contracts

- `tools/schema/bbb_fault_event_v1.md`: persisted raw evidence packet.
- `tools/schema/baseline_coverage_report_v1.md`: known-good coverage guidance.
- `tools/schema/vehicle_health_verdict_v1.md`: cautious health judgment and
  allowed language policy.

## Use

Use this report for deterministic replay QA, customer/report workflows, and
guided capture planning. It may identify observed anomalies and missing coverage,
but it should not recommend repairs without additional workflow-specific
authorization and corroborating evidence.
