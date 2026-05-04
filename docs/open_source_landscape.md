# Open Source Landscape

This file is the project filter for outside CAN, OBD, logging, decoding, and
telematics tools. Use it before adding a new dependency or building a feature
that may already exist elsewhere.

`md` just means Markdown: a plain text notes file that GitHub, editors, and
documentation tools render with headings, lists, tables, and links.

It answers three questions:

- Should we reuse this tool directly?
- Should we study it and borrow the workflow?
- Is our build doing something different enough to keep custom?

The goal is not to prove this project is unique in every part. It is to avoid
rebuilding commodity CAN tooling while keeping the BeagleY/BBB product flow
coherent.

## How To Use This

When a new idea appears, check the table below first.

1. If an existing project already owns the low-level job well, integrate or
   export to it instead of rewriting that layer.
2. If an existing project proves a product pattern, study it and document the
   part we want to copy.
3. If the idea belongs to our product flow, put it in the owning module listed
   in `docs/project_coordination.md`.
4. If a dependency changes a legal, safety, control, or licensing boundary,
   record that in this file before code is added.

Decision labels:

- **Reuse**: make this a dependency, CLI tool, file format, or test fixture.
- **Study**: learn from the design, but do not depend on it yet.
- **Compare**: use as a benchmark for positioning and product tradeoffs.
- **Custom**: keep this in our codebase because it is part of our specific
  BeagleY/BBB flow.

## Current Position

This project is not trying to beat every CAN tool at its own job. The stronger
position is:

- BeagleY appliance cluster for live, read-only vehicle display.
- BBB vehicle hub for CAN, GPS, OBD anchors, signal health, baseline comparison,
  and normalized `vehicle_state` output.
- Offline reverse workbench for signal discovery, dictionary export, consented
  known-good baselines, and cautious fault comparison.
- Local diagnostic summary that explains evidence without claiming a guaranteed
  repair.

That means CSS Electronics, OVMS, SavvyCAN, opendbc, can-utils, python-can, and
cantools are not all direct enemies. Some are tools we should use. Some are
benchmarks. Some cover adjacent product shapes.

## Landscape Table

| Project | What It Does Well | Decision | How We Use It | Boundary |
| --- | --- | --- | --- | --- |
| [can-utils](https://github.com/linux-can/can-utils) | SocketCAN command line tools such as `candump`, `canplayer`, `cansend`, `cangen`, `cansequence`, and `cansniffer`. | Reuse | Use for capture, replay, smoke tests, and live bus sanity checks on Linux targets. | Do not build a custom replacement for basic SocketCAN capture/replay unless a product workflow needs extra metadata. |
| [python-can](https://python-can.readthedocs.io/en/stable/) | Python CAN abstraction across hardware, including SocketCAN and low-power Linux devices. | Reuse | Prefer it for BBB/dev-machine CAN readers and test harnesses when raw sockets are not needed. | It is an I/O layer, not our signal discovery or diagnostic reasoning layer. |
| [cantools](https://github.com/cantools/cantools) | DBC/KCD/SYM/ARXML/CDD parsing, CAN message encode/decode, diagnostics, `candump` decoding, plotting, and code generation. | Reuse | Use for DBC import/export validation and compatibility tests around our signal dictionaries. | Our deployed `can_signals_v1` stays simple for the BBB, but should interoperate with DBC-style tooling. |
| [SavvyCAN](https://github.com/collin80/SavvyCAN) | Cross-platform desktop CAN analysis, reverse-engineering, DBC workflows, replay, filtering, and visual exploration. | Study and use manually | Use during reverse-engineering sessions to inspect logs and validate candidate signals. | It is a desktop analyst tool, not the BeagleY cluster runtime or BBB hub. |
| [opendbc](https://github.com/commaai/opendbc) | Large open vehicle CAN knowledge base and Python API, with examples that can read vehicle state and also support control-focused ADAS work. | Study and selectively reuse | Check for vehicle/platform overlap, learn DBC conventions, and use compatible definitions where license and vehicle fit. | Our product remains read-only. Do not import control assumptions or actuator workflows into the cluster/hub path. |
| [OVMS](https://github.com/openvehicles/Open-Vehicle-Monitoring-System-3) | Open-source vehicle monitoring module with CAN logging, OBD2 translation, DBC decoding, reverse-engineering tools, WebSocket streaming, plugins, GPS/cellular, and vehicle modules. | Study as closest cousin | Study module boundaries, logging formats, plugin patterns, OBD/DBC translation, and user-facing telemetry flows. | Not a drop-in for our hardware/product shape: our split is BeagleY display plus BBB vehicle hub, with a display-first local cluster and known-good baseline comparison. |
| [python-OBD](https://github.com/brendan-w/python-OBD) | ELM327-style OBD-II serial access for reading engine data. | Optional fallback | We now have a small stdlib ELM327 Mode 01 capture path for anchor JSONL; evaluate python-OBD later only if adapter compatibility becomes a problem. | It does not replace SocketCAN ISO-TP, proprietary CAN discovery, or the baseline/anomaly workflow. |
| [CSS Electronics CANedge/CANcloud](https://www.csselectronics.com/products/can-bus-data-logger-wifi-canedge2) | Commercial CAN/LIN logger hardware, raw data capture, SD/WiFi/LTE upload paths, open file/API tooling, DBC workflows, dashboards, and S3-style data pipelines. | Compare | Benchmark logging reliability, deployment simplicity, data handling, and customer-facing docs. | Do not compete as a generic logger first. Our stronger angle is live in-vehicle cluster flow, BBB hub control over local inputs, OBD-anchored discovery, and known-good fault comparison. |

## What We Should Not Rebuild

- Generic CAN frame capture and replay.
- Basic DBC parsing.
- Desktop log browsing and one-off reverse-engineering UI.
- Generic cloud object storage or fleet file management.
- Broader ELM327 scanner features beyond read-only Mode 01 anchor capture.

## What Remains Custom

- `vehicle_state` as the stable BBB to BeagleY display contract.
- Read-only cluster display behavior and diagnostic status presentation.
- CAN signal discovery that starts with legal OBD/known-good anchors and exports
  a BBB-friendly dictionary.
- Known-good Car A vs suspect Car B comparison using matched vehicle metadata.
- Local fault evidence packets and cautious customer summaries.
- The project coordination rules that keep UI, hub, workbench, and reports from
  owning the same logic.

## Next Integration Decisions

- Test the live ELM327 Mode 01 capture path across cheap clone adapters and
  document adapter-specific baud/protocol quirks.
- Add a DBC compatibility test using `cantools` so exported signals can be
  validated against common CAN workflows.
- Add a small "import from opendbc" research task only after a target vehicle
  profile is chosen.
- Keep CSS Electronics as a benchmark for logger reliability and data workflow,
  not as proof that the BeagleY/BBB cluster idea is already solved.

## Source Notes

- can-utils describes itself as SocketCAN userspace utilities and lists basic
  tools for displaying, recording, generating, and replaying CAN traffic.
- python-can documents CAN support for Python across hardware interfaces,
  including SocketCAN and low-power Linux devices such as BeagleBone and
  Raspberry Pi.
- cantools documents CAN database parsing, message encode/decode, diagnostic
  DID encode/decode, `candump` output decoding, plotting, and code generation.
- SavvyCAN describes itself as a Qt cross-platform CAN bus tool and includes
  reverse-engineering and DBC-related project areas.
- opendbc describes itself as a Python API for cars that can read vehicle state
  and, in its own project scope, support control of gas, brake, steering, and
  more.
- OVMS documents CAN logging, DBC-based vehicle support, OBD2 translation, and
  reverse-engineering tooling around its own vehicle-monitoring module.
- CSS Electronics documents CANedge2 as a 2x CAN/LIN logger with WiFi and
  positions CANedge/CANcloud around raw CAN logging, open file/API tooling, DBC
  workflows, and S3-style data handling.
