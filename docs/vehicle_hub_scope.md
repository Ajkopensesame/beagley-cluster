# Vehicle Hub Scope

The cluster should be built as one codebase with clear runtime roles:

- BeagleY is the display/application brain. It renders the V3 cluster, gauges,
  maps, navigation, and visual behavior.
- BBB is the vehicle I/O hub. It receives messy vehicle inputs and emits clean
  `vehicle_state` JSON over WebSocket.
- Arduino Uno is optional. It can be a low-cost input module for protected 12V
  discrete signals, but it is not the main cluster brain.

## Signal Path

```text
vehicle CAN / protected 12V / GPS / sensors
  -> BBB input adapters
  -> decoder + normalizer
  -> vehicle_state
  -> BeagleY cluster UI
  -> display
```

The BeagleY UI should not care whether `rpm` came from CAN, replay, Arduino, or
simulation. It consumes stable fields such as `rpm`, `speedKph`,
`warnings.brake`, `warnings.oil`, `indicators.left`, and `drivetrain.mode`.

## CAN

Live CAN uses Linux SocketCAN on the BBB:

```bash
CAN_SIGNAL_DICTIONARY=/home/debian/can_signals.json
CAN_LIVE_INTERFACE=can0
CAN_STALE_MS=1000
```

The dictionary comes from the Mac workbench in `tools/can_reverse_workbench`.
The first proven targets are `rpm` and `speedKph`.

The BBB also runs an expert CAN diagnostics engine on live/replay CAN frames.
It learns per-ID timing and records telltales:

- `bus_silence`: the CAN source is enabled but no frames arrive.
- `can_id_dropout`: one CAN ID was arriving at a learned cadence, then stopped.
- `frame_rate_jitter`: one ID's timing became irregular.
- `dlc_changed`: one ID changed payload length.
- `payload_stuck`: a decoded dynamic packet repeats the same payload for too long.
- `decoded_signal_stuck`: a decoded dynamic signal such as `rpm` or `speedKph`
  stays flat long enough to be suspicious.

Each finding includes confidence and suspected causes. Warning/error findings are
bridged into `_health.signalFaults`, so the fault recorder saves them.

## OBD-Derived Virtual Anchors

Standard OBD data should do more than provide direct display values. When RPM,
vehicle speed, coolant temperature, MAF, and vehicle displacement are known, the
BBB/workbench can compute extra "virtual sensors" from physics and use them as
additional anchors for raw CAN discovery.

These values are not directly measured sensors. They are derived evidence with
quality metadata. The discovery engine should weight them by confidence and
never treat them as standalone repair proof.

Useful derived anchors:

- `accelLongitudinalMps2`: derivative of vehicle speed after filtering. Useful
  for finding throttle, brake, wheel-speed, and drivetrain load signals.
- `coldStartState` / `hotStartState`: inferred from coolant temperature, intake
  air temperature, ambient temperature when available, and time since last run.
  Useful for condition-aware baselines.
- `airflowLoadProxy`: MAF normalized by RPM and displacement. Useful when MAP or
  throttle is missing.
- `volumetricEfficiencyPct`: estimated from MAF, RPM, displacement, intake air
  temperature, and MAP/barometric pressure when available. Stronger during
  stable high-load regions than during transients.
- `fuelFlowLph`: estimated from MAF, AFR/lambda/equivalence ratio, fuel density,
  and trims when available. For diesel engines, prefer direct fuel-rate,
  injector quantity, or calibrated BSFC data; gasoline stoichiometric assumptions
  are not valid enough on their own.
- `fuelEconomyLPer100Km`: derived from fuel flow and speed, only when speed is
  high enough to avoid divide-by-near-zero noise.
- `gearRatioProxy`: RPM divided by speed after filtering. Stable clusters reveal
  likely gear states, especially after tire size/final-drive calibration.
- `powerKwEstimate` / `torqueNmEstimate`: low-confidence estimates from airflow,
  fuel model, efficiency, and BSFC assumptions. Useful as correlation anchors for
  driver-demand or transmission-torque frames, not as measured dyno values.
- `coolantWarmupRate`: derivative of coolant temperature, compared with airflow
  and speed. Useful for fan, thermostat, and warmup behavior discovery.

The intended workbench flow is:

```text
OBD anchors + vehicle constants
  -> derived anchor generator
  -> correlation/ranking against raw CAN candidates
  -> multi-anchor consistency checks
  -> confirmed signal dictionary
  -> BBB live decode
```

Derived anchor records should carry:

- source inputs used, such as `rpm`, `mafGps`, `speedKph`, `coolantC`,
  `intakeAirTempC`, `mapKpa`, `baroKpa`, and displacement
- formula/model version
- confidence tier
- vehicle fuel type and assumptions
- whether the value is display-safe, discovery-only, or diagnostic-only

Suggested confidence tiers:

- High: acceleration from speed, warm/cold state, filtered speed/load trends.
- Medium: VE, gear-ratio clusters, fuel flow when lambda or fuel-rate data is
  available.
- Low: torque/power estimates and fuel flow built from broad assumptions.

The main rule is that virtual anchors expand discovery coverage, but confirmed
raw signals and direct OBD PIDs remain stronger evidence. After a raw CAN signal
is confirmed, it can become a pseudo-anchor for discovering related chassis and
body signals.

## 12V Inputs

Raw vehicle 12V must not connect directly to BBB GPIO or Arduino pins. Use
proper input conditioning first: optocouplers, current limiting, clamping, and
automotive protection.

The first supported path is:

```text
vehicle 12V signal -> optocoupler/protection -> Arduino Uno -> USB serial -> BBB
```

Serial protocol examples:

```text
brake=1,oil=0,left=on,rpm=1200,speed=35.5
```

```json
{"brake": true, "left": true, "speed": 42.5}
```

Enable it on the BBB with:

```bash
VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyACM0
VEHICLE_INPUT_SERIAL_BAUD=115200
VEHICLE_INPUT_STALE_MS=1000
```

## Rule

New vehicle hardware integrations should add an input adapter and normalize into
`vehicle_state`. They should not force a rewrite of the BeagleY gauges, maps, or
navigation.

## Fault Detection

The BBB hub also runs a deterministic signal monitor. It is not AI-driven. It
flags machine-checkable failure reasons such as:

- `out_of_range`: decoded value is outside expected physical limits.
- `impossible_jump`: decoded value changes faster than a real vehicle should.
- `noisy_or_flapping`: decoded value oscillates rapidly.
- `source_stale`: live CAN, replay, or serial input has stopped updating.
- `source_disagreement`: top-level/CAN speed disagrees with valid GPS speed.

These reasons are emitted in `_health.signalFaults`. A later AI layer can
summarize those reasons, but it should not be the source of truth for detecting
the fault.

When `_health.signalFaults` appears, the BBB fault recorder writes a JSON
evidence packet to `/var/log/beagley-cluster/faults/` by default. Each event
includes:

- the trigger fault list
- the trigger `vehicle_state`
- a rolling pre-trigger state buffer
- CAN replay/live recent raw frames when available
- serial input latest values when available
- source health at the trigger moment

This makes intermittent failures diagnosable after the fact instead of relying
on someone watching a screen at exactly the right moment.

## Learned Vehicle Baselines

Not every useful diagnostic is a raw CAN fault. Some faults are slow component
drift, where each individual reading is plausible but the relationship is no
longer normal for this vehicle.

The baseline monitor handles that by learning target-vs-context relationships:

```text
target signal + comparable operating conditions -> learned normal range
```

The first built-in profile is `intake_airflow`. It learns `mafGps` against
similar `rpm`, `throttlePct`, `intakeAirTempC`, and optional `engineLoadPct` /
`mapKpa` while `coolantC` says the engine is warm. If MAF is repeatedly below
the learned normal range across trusted buckets, it emits `intake_airflow_low`
with confidence and evidence.

This does not require hand-writing every possible scenario. It does require a
model definition that says which signals should be compared. The system learns
normal values inside those operating buckets, but it should not invent fault
meaning from raw sensor names alone.

Enable / persist baselines on the BBB with:

```bash
VEHICLE_BASELINE_ENABLED=1
VEHICLE_BASELINE_PATH=/var/lib/beagley-cluster/baselines/vehicle_baseline.json
VEHICLE_BASELINE_SAVE_EVERY_SAMPLES=25
VEHICLE_BASELINE_MIN_SAVE_INTERVAL_SECONDS=30.0
```

## Startup What-Changed Check

For no-start or start-then-stall faults, route baseline is the wrong truth
source. The useful truth source is a set of known-good startup captures.

The first offline check is:

```bash
python3 tools/can_reverse_workbench/startup_diff.py \
  --good good_start_1.log \
  --good good_start_2.log \
  --bad failed_start.log \
  --window-sec 8 \
  --out startup_diff.json
```

This compares raw CAN byte behavior during successful starts against the failed
start and ranks what changed most. It can catch cases where a raw field normally
moves during startup but stays flat during the failed start, even before that
field has a human label such as IAC, intake throttle, fuel pressure, or relay
state.

This is the intended pattern for the broader product:

```text
learned truth database -> cheap deviation math -> evidence packet -> optional LLM explanation
```

The LLM should not decide whether data is abnormal. The math decides that. The
LLM can later summarize likely causes from the evidence packet and clearly label
missing evidence.
