# Vehicle Hub CAN Reverse Workbench

This is a Mac-first offline workbench for reverse-engineering raw CAN logs into
named vehicle signals. The cluster display should continue consuming stable
human fields such as `rpm` and `speedKph`; this tool works upstream and exports
a decoder dictionary.

Milestone one targets `rpm` and `speedKph` from guided log sessions. Discovery is
deterministic and mathematical. No cloud AI is used as the source of truth.

## Pipeline Contract

Every analysis run follows the same verification pipeline:

1. Bit analysis: enumerate plausible common 4-32 bit numeric fields, endian variants, and signedness.
2. Correlation: compare candidate behavior against guided windows and lagged trusted anchors.
3. Scaling: calibrate raw values to units using least-squares anchors with deterministic holdout checks where enough anchors exist.
4. Validation: check physical plausibility, smoothness, refresh rate, fitted scale resolution, and counter/noise telltales.
5. Decision: output confidence and either mark the mapping `verified` or leave it `unknown`.

The tool must not assume that a packet is `rpm`, `speedKph`, or any other human
signal just because it looks interesting. Candidates are always reported with
confidence, but `can_signals.json` only exports verified mappings.

## OBD + Raw CAN Capture Sessions

The preferred source artifact is a single SQLite capture session that contains:

- timestamped raw CAN frames
- timestamped OBD Mode 01 anchor samples
- optional GPS anchor samples
- vehicle profile, purpose, and import warnings

Build one from synchronized raw CAN and OBD/GPS logs:

```bash
python3 -m tools.can_reverse_workbench capture-session \
  --db /tmp/can_workbench/capture.sqlite \
  --can-log /path/to/candump.log \
  --obd-log /path/to/obd_mode01.jsonl \
  --out /tmp/can_workbench/session_001 \
  --vehicle-profile "make model year engine trim ecu-calibration" \
  --purpose "owner-authorized raw CAN discovery" \
  --thermal-start-class cold \
  --session-label known_good \
  --decoder-version can_signals_v1
```

The export directory contains:

- `raw_can.candump`: analyzer-ready raw CAN log
- `guided_session.json`: analyzer-ready OBD/GPS anchors
- `obd_anchors.jsonl`: normalized anchor samples
- `capture_manifest.json`: counts and file paths

Capture metadata can include `thermalStartClass`, `offTimeSec`,
`sessionLabels`, and `decoderVersion`. Transition baselines use this metadata to
avoid treating unlike captures as the same truth source.

Then decode/name raw CAN candidates from the same capture:

```bash
python3 -m tools.can_reverse_workbench analyze \
  --log /tmp/can_workbench/session_001/raw_can.candump \
  --labels /tmp/can_workbench/session_001/guided_session.json \
  --target rpm \
  --target speedKph \
  --target mafGps \
  --target throttlePct \
  --target mapKpa \
  --out /tmp/can_workbench/session_001/analysis
```

This is the "OBD teaches raw CAN" path. OBD/GPS anchors help name and scale raw
signals; the exported raw CAN dictionary is what the BBB can use later for fast
live monitoring.

## Inputs

Supported raw log formats:

```text
(1710000000.100000) can0 123#AABBCCDD
```

```csv
timestamp,interface,id,data
1710000000.100000,can0,0x123,AABBCCDD
```

Guided session JSON:

```json
{
  "windows": [
    {"label": "idle", "start": 0.0, "end": 4.0},
    {"label": "stationary_rev", "start": 5.0, "end": 12.0},
    {"label": "accelerate", "start": 13.0, "end": 25.0},
    {"label": "decelerate", "start": 26.0, "end": 34.0}
  ],
  "anchors": {
    "rpm": [
      {"timestamp": 1.0, "value": 820},
      {"timestamp": 8.0, "value": 3200}
    ],
    "speedKph": [
      {"timestamp": 14.0, "value": 0},
      {"timestamp": 22.0, "value": 80}
    ]
  }
}
```

Anchors are optional, but they materially improve scale/offset calibration.
When a signal has at least six anchor points, discovery searches small positive
and negative timestamp lags before fitting. This handles common GPS/OBD/logger
delay without treating raw cross-correlation magnitude as a confidence value.

## OBD Mode 01 Anchors

The workbench can convert standard OBD Mode 01 PID responses into guided
session anchors. This is the first step toward the strategy of using legally /
standards-exposed emissions data as trusted anchors before naming raw CAN
signals.

Accepted JSONL examples:

```json
{"timestamp": 1.0, "response": "04 41 0C 1A F8 00 00 00"}
{"timestamp": 1.1, "pid": "0x0D", "data": "58"}
{"timestamp": 1.2, "signal": "gpsSpeedKph", "value": 88.2}
```

Convert the OBD log into a guided session:

```bash
python3 -m tools.can_reverse_workbench obd-anchors \
  --log /path/to/obd_mode01.jsonl \
  --out /tmp/can_workbench/obd_guided_session.json \
  --vehicle-profile "make model year engine trim ecu-calibration"
```

Then use the generated guided session as the `--labels` input to `analyze`.
By default `analyze` ranks `rpm` and `speedKph`. Use repeated `--target`
arguments to rank additional OBD-anchored signals:

```bash
python3 -m tools.can_reverse_workbench analyze \
  --log /path/to/candump.log \
  --labels /tmp/can_workbench/obd_guided_session.json \
  --target rpm \
  --target speedKph \
  --target mafGps \
  --target throttlePct \
  --target mapKpa \
  --out /tmp/can_workbench
```

Implemented standard anchors include common emissions/diagnostic values such as
`rpm`, `speedKph`, `coolantC`, `engineLoadPct`, `mapKpa`, `mafGps`,
`throttlePct`, `intakeAirTempC`, fuel trims, module voltage, oil temperature,
and fuel rate when the vehicle reports those PIDs.

This is not a live OBD scanner yet. The durable capture artifact is now the
SQLite capture session; the current command imports synchronized logs into that
session and exports the same anchor contract as manually guided sessions.

## Live ELM327 Capture

For a live vehicle with an ELM327-compatible USB or Bluetooth serial adapter,
capture read-only standard OBD Mode 01 anchors directly:

```bash
python3 -m tools.can_reverse_workbench elm327-capture \
  --device /dev/ttyUSB0 \
  --out /tmp/can_workbench/elm327_obd.jsonl \
  --guided-out /tmp/can_workbench/elm327_guided_session.json \
  --duration-sec 60 \
  --pid rpm \
  --pid speed \
  --pid maf \
  --pid throttle \
  --purpose "owner-authorized live OBD anchor capture" \
  --owner-consent
```

Common device paths:

- Linux USB: `/dev/ttyUSB0`
- Linux Bluetooth RFCOMM: `/dev/rfcomm0`
- macOS USB/Bluetooth serial: `/dev/tty.*`

Default polling is conservative and read-only. The command initializes the
adapter with standard `AT` setup commands, asks for supported PIDs, then polls
Mode 01 requests such as RPM, speed, load, coolant, MAP, IAT, MAF, throttle, and
module voltage. It writes the same JSONL accepted by `obd-anchors` and
`capture-session`.

If a clone adapter behaves poorly, useful fallback flags are:

```bash
--baud 9600
--no-supported-filter
--timeout-sec 4
--sample-interval-sec 0.5
```

This path is for OBD anchor capture, not proprietary CAN control. It does not
clear codes, write ECU settings, or transmit control commands.

## Analyze

```bash
python3 -m tools.can_reverse_workbench analyze \
  --log /path/to/candump.log \
  --labels /path/to/guided_session.json \
  --out /tmp/can_workbench
```

Outputs:

- `/tmp/can_workbench/analysis.json`: ranked candidates, evidence, previews, ID activity.
- `/tmp/can_workbench/can_signals.json`: exported decoder dictionary containing only verified mappings.

If a candidate is not verified, the export keeps it under `rejectedSignals` with
its confidence and reason instead of attaching it to a human signal name.

## Signal Identity Hypothesis Report

Use `identity-report` when you want to rank unknown CAN candidates without
turning them into verified decoder fields:

```bash
python3 -m tools.can_reverse_workbench identity-report \
  --log /tmp/can_workbench/session_001/raw_can.candump \
  --labels /tmp/can_workbench/session_001/guided_session.json \
  --decoded /tmp/can_workbench/session_001/vehicle_state_overlay.jsonl \
  --out /tmp/can_workbench/session_001/signal_identity_hypothesis_report.json \
  --candidate-export /tmp/can_workbench/session_001/diagnostic_candidate_signals.json
```

The report classifies candidates as `switch`, `state_enum`,
`continuous_sensor`, `speed_like`, `rpm_like`, `pressure_like`,
`temperature_like`, `percentage_like`, `voltage_like`, `airflow_like`,
`gear_or_ratio`, `warning_lamp`, `counter`, `checksum_or_crc`, or `unknown`.

Promotion policy is separate from `can_signals.json`:

- `candidate`: useful for human review only.
- `probable`: can be exported as low-trust diagnostic evidence.
- `rejected`: counter/checksum/noise/wrong behavior.
- `verified`: reserved for the normal `analyze` -> `can_signals.json` path.

`diagnostic_candidate_signals.json` is intentionally low-trust. It can support
diagnostic experiments and anomaly investigation, but it must not drive cluster
display fields and must not be sole evidence for a health verdict.

Optional AI naming is command-based, not tied to a cloud SDK:

```bash
python3 -m tools.can_reverse_workbench identity-report \
  --log /path/to/candump.log \
  --labels /path/to/guided_session.json \
  --out /tmp/signal_identity_hypothesis_report.json \
  --ai-command "/path/to/ai_namer"
```

The command receives compact evidence JSON on stdin and may return name/class
suggestions. AI can rename or explain a non-rejected hypothesis, but it cannot
promote a signal and cannot override deterministic rejection.

## Browser Workbench

```bash
python3 -m tools.can_reverse_workbench serve \
  --analysis /tmp/can_workbench/analysis.json
```

Open `http://127.0.0.1:8769`.

The browser view shows CAN ID activity, byte activity, guided labels, ranked
`rpm` and `speedKph` candidates, candidate overlays, and export preview. It is
for analysis only and is not intended to run on the BeagleY display.

## Decode Replay

```bash
python3 -m tools.can_reverse_workbench decode \
  --signals /tmp/can_workbench/can_signals.json \
  --log /path/to/candump.log \
  --out /tmp/can_workbench/vehicle_state_overlay.jsonl
```

The JSONL output contains decoded signal snapshots that can be replayed into the
existing vehicle state pipeline.

Run the shared transition anomaly monitor over decoded replay output:

```bash
python3 -m tools.can_reverse_workbench transition-replay \
  --decoded /tmp/can_workbench/vehicle_state_overlay.jsonl \
  --out /tmp/can_workbench/transition_replay_report.json
```

This uses the same event segmentation and transition scoring as the BBB runtime.
Raw-byte `startup_diff.py` remains the fallback when a signal has not been
decoded yet.

Replay reports include `baselineCoverage`, which marks known-good scenarios as
`strong`, `weak`, or `missing` so the next capture can target the gaps instead
of collecting random mileage.

## Known-Good Baseline Diagnostics

The workbench can build a consent-tagged healthy baseline from decoded signal
logs and compare a suspect vehicle against matched operating states. This is
evidence ranking for mechanic review, not an automated repair instruction.

Create a pseudonymous consent record first:

```bash
python3 -m tools.can_reverse_workbench consent \
  --out /tmp/can_workbench/car_b_consent.json \
  --owner-reference "work-order-1234" \
  --vehicle-profile "make model year engine trim ecu-calibration" \
  --purpose "owner-authorized engine fault triage" \
  --retention-days 30 \
  --owner-consent
```

```bash
python3 -m tools.can_reverse_workbench baseline \
  --decoded-good /tmp/can_workbench/car_a_vehicle_state_overlay.jsonl \
  --out /tmp/can_workbench/car_a_health_baseline.json \
  --vehicle-profile "make model year engine trim ecu-calibration" \
  --purpose "known-good baseline for owner-authorized diagnostics" \
  --retention-days 30 \
  --owner-consent
```

```bash
python3 -m tools.can_reverse_workbench diagnose \
  --baseline /tmp/can_workbench/car_a_health_baseline.json \
  --decoded-suspect /tmp/can_workbench/car_b_vehicle_state_overlay.jsonl \
  --out /tmp/can_workbench/car_b_diagnostic_report.json \
  --customer-report /tmp/can_workbench/car_b_customer_report.md \
  --vehicle-profile "make model year engine trim ecu-calibration" \
  --purpose "owner-authorized engine fault triage" \
  --consent-record /tmp/can_workbench/car_b_consent.json \
  --retention-days 30 \
  --owner-consent
```

The report compares decoded signals inside coarse operating states such as
stationary idle, stationary rev, low-speed drive, road-speed drive, and highway
drive. Findings include severity, confidence, baseline envelope evidence, and
next checks. Findings deliberately carry `notRepairDirective: true`; they must be
validated with DTCs, freeze-frame data, service information, and physical tests.

Responsible-use guardrails:

- Owner consent and a recorded purpose are required before baseline creation or
  suspect comparison.
- Consent records should use pseudonymous owner/work-order references rather
  than direct owner identifiers whenever possible.
- Generated baseline and diagnostic reports include retention metadata with a
  delete-after date.
- Capture must remain read-only; this tooling does not transmit CAN messages.
- VINs, locations, timestamps, and driving behavior should be treated as
  sensitive owner data and not reused outside the recorded purpose.
- Baselines should match exact make, model, year, engine, trim, ECU calibration,
  and guided test conditions.

## BBB Hub Integration

The existing `vehicle_state` WebSocket shape is preserved. The BBB hub only
overlays decoded CAN values when replay or live CAN is explicitly enabled.

```bash
CAN_SIGNAL_DICTIONARY=/home/debian/can_signals.json
CAN_RAW_LOG=/home/debian/candump.log
CAN_REPLAY_REPEAT=1
```

Live SocketCAN receive uses the same dictionary:

```bash
CAN_SIGNAL_DICTIONARY=/home/debian/can_signals.json
CAN_LIVE_INTERFACE=can0
CAN_STALE_MS=1000
```

This keeps CAN decoding behind the BBB hub, so the BeagleY display continues to
consume the same `vehicle_state` fields.
