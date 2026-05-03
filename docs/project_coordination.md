# Project Coordination Map

This file is the working map for the project. Update it when a new idea becomes
part of the build, when a module takes ownership of a responsibility, or when a
schema changes. The goal is to keep the BeagleY UI, BBB hub, CAN workbench,
diagnostics, and hardware path from solving the same problem in different ways.

## Product Direction

Build a read-only vehicle display and diagnostic companion:

- BeagleY runs the cluster UI, maps, guided display flows, and appliance runtime.
- BBB runs vehicle I/O, CAN decode, GPS ingest, signal health, anomaly detection,
  baseline comparison, and fault evidence capture.
- The CAN reverse workbench runs offline on development machines to discover and
  validate signal dictionaries before they are deployed to the BBB.
- Optional Arduino modules handle protected 12V discrete inputs when direct BBB
  GPIO would be unsafe.

The product should feel like a plug-in cluster/display add-on first, not an ECU
tuner or control module. Diagnostics should be evidence-backed and clearly
separate from repair claims.

Before adding an external CAN/OBD/logging dependency or rebuilding a tool that
may already exist, check `docs/open_source_landscape.md`.

## Non-Negotiable Boundaries

- The cluster is display-only. It must not command brakes, throttle, steering,
  transmission, immobilizer, or safety systems.
- Raw CAN frames do not go directly into QML. BBB normalizes them into
  `vehicle_state`; BeagleY consumes that contract.
- AI can explain, summarize, rank, and guide based on evidence. AI should not be
  the source of truth for detecting abnormal data.
- AI health judgments must use the `vehicle_health_verdict` evidence contract or
  a future equivalent, including coverage, confidence, abstain rules, and
  wording limits.
- Legal use requires owner consent, purpose-limited data capture, and clear
  separation between trusted known-good data and customer fault captures.
- Runtime health diagnosis for the BeagleY service follows the local skill
  workflow in the repo instructions. Do not guess around systemd failures.

## Core Data Contracts

- `tools/schema/vehicle_state_v1.md`: live BBB to BeagleY state contract.
- `tools/schema/can_signals_v1.md`: deployed CAN signal dictionary contract.
- `tools/schema/can_health_baseline_v1.md`: offline known-good health baseline.
- `tools/schema/obd_raw_can_capture_session_v1.md`: synchronized OBD/GPS anchor
  plus raw CAN capture database.
- `tools/schema/vehicle_health_verdict_v1.md`: structured evidence contract for
  AI-issued health judgments, confidence, abstain rules, and wording limits.
- `tools/schema/vehicle_transition_baseline_v1.md`: per-vehicle learned
  transition templates for startup, throttle, shift, decel, and similar event
  response checks.
- `tools/schema/baseline_coverage_report_v1.md`: report that marks known-good
  scenarios as strong, weak, or missing for a vehicle.
- Fault recorder event JSON: rolling evidence packet produced by BBB when signal
  faults appear.

Schema changes should be made before UI or runtime consumers depend on new
fields.

## Ownership Map

| Area | Owner Path | Owns | Must Not Own |
| --- | --- | --- | --- |
| BeagleY cluster UI | `src/ui`, `src/render`, `src/data` | Read-only display, smoothing, map/nav presentation, link state, diagnostic summary display | Raw CAN parsing, fault detection truth, repair inference |
| BBB vehicle hub | `tools/bbb_hub` | Live inputs, GPS, CAN replay/live overlays, signal health, learned baselines, fault evidence, normalized diagnostic status | Gauge layout, map rendering, user interface animation |
| CAN reverse workbench | `tools/can_reverse_workbench` | Offline CAN parsing, signal discovery, DBC/dictionary export, known-good baseline comparison, consent records, customer reports | Embedded UI behavior, live service control |
| Schemas | `tools/schema` | Versioned contracts for state, signal dictionaries, baselines | Runtime logic |
| Runtime deployment/debug | `skills`, service scripts, Yocto docs | Safe device connection, health checks, deployment, appliance build rules | Feature semantics |
| Product docs | `docs` | Direction, system boundaries, architecture decisions, roadmap | Code execution |

## Active Build Streams

### 1. Reliable Appliance Cluster

Goal: make the BeagleY cluster boot, render, and stay stable on target hardware.

Current pieces:

- Embedded UI path: `MainEmbedded.qml`
- Desktop/V3 UI path: `MainV3.qml`
- Render model bridge: `ClusterRenderModel`
- Appliance documentation: `docs/beagley_appliance.md`
- GPU/runtime contracts: `docs/beagley_gpu_contract.md`

Rules:

- UI consumes `VehicleStateClient` / `ClusterRenderModel` only.
- Appliance work should not reintroduce optional desktop-only WebEngine paths.

### 2. Vehicle Hub and Normalized State

Goal: BBB emits one clean `vehicle_state` stream regardless of whether values
come from CAN, replay, serial, GPS, or future sensors.

Current pieces:

- Hub runtime: `tools/bbb_hub/vehicle_hub_prod.py`
- Input adapters: `tools/bbb_hub/input_adapters.py`
- Signal health: `tools/bbb_hub/signal_health.py`
- CAN diagnostics: `tools/bbb_hub/can_diagnostics.py`
- Fault recorder: `tools/bbb_hub/fault_recorder.py`
- Learned baseline monitor: `tools/bbb_hub/vehicle_baseline.py`
- Learned transition monitor: `tools/bbb_hub/transition_monitor.py`

Rules:

- New hardware inputs become adapters that merge into `vehicle_state`.
- Do not teach the UI where a value came from unless it is a display/status
  concern.

### 3. CAN Discovery and Signal Dictionary

Goal: discover candidate CAN signals using trusted anchors, then export a
dictionary that the BBB can decode live.

Current pieces:

- Workbench package: `tools/can_reverse_workbench`
- Shared bit extraction: `tools/can_reverse_workbench/bitfield.py`
- OBD anchor adapter: `tools/can_reverse_workbench/obd_anchors.py`
- OBD + raw CAN capture sessions: `tools/can_reverse_workbench/capture_session.py`
- Planned virtual anchor generator: derives acceleration, load proxies, VE,
  fuel-flow estimates, gear-ratio proxies, warmup rates, and confidence metadata
  from OBD anchors plus vehicle constants.
- Discovery/ranking: `tools/can_reverse_workbench/discovery.py`
- BBB decoder: `tools/can_reverse_workbench/bbb_decoder.py`
- Export: `tools/can_reverse_workbench/export.py`

Rules:

- Standards-exposed OBD data should be treated as anchor evidence, not as proof
  that every manufacturer/private CAN signal is known.
- Derived OBD virtual sensors are weighted anchors, not directly measured truth.
  Each derived value needs source inputs, assumptions, and a confidence tier.
- Candidate discovery happens offline first.
- Deployed dictionaries should be tested against replay before live vehicle use.

### 4. Known-Good Baselines and Fault Comparison

Goal: compare a faulting vehicle against known-good data from the same vehicle
configuration, then produce evidence and a cautious customer-facing summary.

Current pieces:

- Health baseline utilities: `tools/can_reverse_workbench/baseline.py`
- Startup diff: `tools/can_reverse_workbench/startup_diff.py`
- Runtime learned baseline: `tools/bbb_hub/vehicle_baseline.py`
- Runtime transition baseline: `tools/bbb_hub/transition_monitor.py`

Rules:

- "Car A vs Car B" comparisons should match make, model, year, engine, trim, and
  decoder version before being treated as strong evidence.
- V1 transition anomaly detection is per-vehicle. Fleet priors can be added
  later, but they are not the first source of truth.
- Reports should say "most likely based on captured evidence", not guaranteed
  repair instructions.

### 5. Normalized Diagnostic Status

Goal: give the display one compact diagnostic status without making the display
run diagnostics.

Current direction:

- BBB aggregates `_health.signalFaults`, CAN diagnostics, and learned baseline
  findings into `_diagnostic`.
- BeagleY parses `_diagnostic` and shows status such as nominal, data stale,
  capture limited, or anomaly detected.
- Fault recorder keeps the detailed evidence packet.

Rules:

- `_diagnostic` is a summary layer, not a replacement for `_health` evidence.
- UI text should be short and display-ready.
- Detailed repair reasoning belongs in reports or guided workflows, not the
  main gauge loop.
- AI verdicts such as "probably healthy" belong in `vehicle_health_verdict`,
  not directly in `_diagnostic`.

## Near-Term Priorities

1. Finish `_diagnostic` end-to-end:
   - BBB summary builder
   - schema update
   - `VehicleStateClient` properties
   - `ClusterRenderModel` status and warning summary integration
   - unit tests and a replay smoke test
2. Keep CAN reverse workbench focused on signal discovery and export quality.
3. Expand known-good baseline examples with clear consent and vehicle metadata.
4. Add derived OBD virtual anchors to expand signal discovery without claiming
   unsupported sensor certainty.
5. Add a guided diagnostic report flow that consumes evidence packets but keeps
   the cluster display read-only.
6. Keep appliance stability work separate from product feature work.

## Idea Inbox

- Plug-in aesthetic cluster powered by decoded vehicle data.
- Live anomaly detection using deterministic signal health plus learned vehicle
  baselines.
- Guided display functions that explain what data is missing or suspect.
- Known-good vehicle profile library for identical make/model/year/engine/trim
  comparisons.
- Customer report generation from consented captures and evidence packets.
- OBD-derived virtual anchors for acceleration, warm/cold state, airflow load,
  VE, fuel-flow estimates, gear-ratio proxies, torque/power estimates, and
  coolant warmup behavior.
- Accessory/plugin hardware model: cluster, BBB hub, optional Arduino/12V module,
  optional GPS/IMU module.
- Differentiation from generic CAN loggers: live display flow, embedded runtime,
  local evidence capture, and vehicle-specific baseline comparison.

## Change Checklist

Before adding a feature, answer these in this file or the feature doc:

- Which area owns it?
- What data contract does it read or write?
- Is it display, detection, evidence capture, or explanation?
- What should happen when the input is stale or missing?
- What test or replay proves it works?
- Does it touch legal/consent/customer data?

If the answers cross more than one area, add the schema or adapter first, then
update consumers.
