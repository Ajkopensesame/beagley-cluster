# obd_raw_can_capture_session v1

Storage: SQLite

Owner: `tools/can_reverse_workbench/capture_session.py`

Purpose: keep OBD/GPS anchor data and raw CAN frames from the same capture in
one durable artifact. This is the source used to teach the workbench which raw
CAN fields likely match standard OBD signals.

## Tables

### sessions

- `id`: stable capture id
- `schema_version`: capture schema version
- `vehicle_profile`: make/model/year/engine/trim/ECU calibration label when known
- `purpose`: owner-authorized diagnostic or discovery purpose
- `notes`: operator notes
- `source`: capture source, for example `log_import`
- `created_at`: ISO timestamp when the session record was created
- `started_at`: earliest raw CAN or anchor timestamp
- `ended_at`: latest raw CAN or anchor timestamp
- `thermal_start_class`: `cold`, `warm`, or `hot` when known
- `off_time_sec`: engine-off soak time before the capture when known
- `session_labels`: JSON list of operator/context labels
- `decoder_version`: decoder/profile version used for the capture when known

### raw_can_frames

- `session_id`: owning session
- `timestamp`: frame timestamp in seconds
- `interface`: CAN interface name
- `arbitration_id`: numeric CAN ID
- `can_id_hex`: display CAN ID
- `extended`: whether the ID is extended
- `dlc`: data length
- `data_hex`: payload bytes
- `source_line`: source log line when imported

### anchor_samples

- `session_id`: owning session
- `timestamp`: anchor timestamp in seconds
- `source`: `obd_mode_01`, `gps`, or `manual_anchor`
- `signal`: logical signal name, for example `rpm`, `speedKph`, or `gpsSpeedKph`
- `value`: decoded value
- `unit`: decoded unit when known
- `mode`: OBD mode when sourced from OBD
- `pid`: OBD PID when sourced from OBD
- `raw_payload`: original JSONL row when imported
- `source_line`: source log line when imported

### obd_pids_seen

- `session_id`: owning session
- `pid`: OBD PID seen in the capture
- `source_line`: source log line when first seen

### obd_supported_pids

- `session_id`: owning session
- `pid`: supported OBD PID reported by the vehicle
- `source_line`: source log line when first reported

### import_warnings

- `session_id`: owning session
- `source`: import source, for example `can_log` or `obd_log`
- `source_line`: source log line when known
- `message`: parse warning

## Export Contract

`capture-session --out` writes analyzer-ready files:

- `raw_can.candump`: raw CAN frames for `analyze --log`
- `guided_session.json`: OBD/GPS anchors for `analyze --labels`
- `obd_anchors.jsonl`: normalized anchor rows
- `capture_manifest.json`: paths and counts

The exported `guided_session.json` and `capture_manifest.json` include the
session metadata above so transition baselines can avoid comparing unlike
captures, such as a cold start against a hot restart.
