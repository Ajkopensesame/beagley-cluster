# vehicle_state v1 (UNO → BBB → BeagleY)

Transport: WebSocket text frames (JSON)
Port: 8765
Top-level required fields:
- type: "vehicle_state"
- version: 1

## Example
{
  "type": "vehicle_state",
  "version": 1,

  "speedKph": 0.0,
  "rpm": 0.0,
  "fuelPct": 0.0,
  "coolantC": 0.0,
  "mafGps": 0.0,
  "throttlePct": 0.0,
  "engineLoadPct": 0.0,
  "intakeAirTempC": 0.0,
  "mapKpa": 0.0,
  "gear": "D",
  "overdrive": true,
  "drivetrain": {
    "mode": "4wd",
    "transfer_lock": false
  },
  "gps": {
    "lat": -27.4698,
    "lng": 153.0251,
    "bearing": 0.0,
    "accuracyM": 4.0,
    "timestampMs": 1735779600000,
    "fixValid": true,
    "satellites": 12,
    "speedKph": 61.5,
    "headingReliable": true
  },

  "indicators": {
    "left": false,
    "right": false,
    "high_beam": false
  },

  "warnings": {
    "brake": false,
    "oil": false,
    "charge": false,
    "door": false,
    "check_engine": false,
    "at": false,
    "fuel_low": false
  },

  "_health": {
    "stale": false
  },

  "_diagnostic": {
    "version": 1,
    "mode": "normal",
    "ok": true,
    "severity": "ok",
    "status": "nominal",
    "summary": "SYSTEMS NOMINAL",
    "findingCount": 0,
    "activeFindings": [],
    "captureQuality": {
      "gpsOk": true,
      "canOk": null,
      "serialOk": null,
      "linkStale": false
    }
  }
}

## Notes
- BeagleY treats "linkStale" separately (computed by watchdog timing).
- BBB may set _health.stale=true if its upstream UNO feed is stale.
- Optional source hint may be included at top level:
  - `gpsSource`: for example `hardware`, `sim`, `phone_web`.
- GPS can be sent as nested `gps` (`lat`,`lng|lon`,`bearing|heading|course`) or
  top-level aliases (`gpsLat`,`gpsLng`,`gpsBearing`) for backward compatibility.
- Optional GPS enrichments accepted by BeagleY:
  `gps.accuracyM|accuracy`, `gps.timestampMs|timestamp|ts`,
  `gps.fixValid|fix_valid|valid`, `gps.satellites|sats`,
  `gps.speedKph|speed|speed_kph`, `gps.headingReliable|heading_reliable`.
- Optional phone fallback diagnostics:
  - `_health.phoneGpsFresh` (bool)
  - `_health.phoneGpsAgeMs` (int)
  - `_health.gpsSourcePolicy` (string)
- Optional hardware GPS diagnostics:
  - `_health.gpsStale` (bool)
  - `_health.gpsSerialOk` (bool)
  - `_health.gpsAgeMs` (int)
  - `_health.gpsParseErrors` (int)
  - `_health.gpsDevice` (string)
  - `_health.gpsLastError` (string)
- Optional CAN decoder diagnostics:
  - `_health.canReplay.enabled` (bool)
  - `_health.canReplay.dictionary` (string)
  - `_health.canReplay.log` (string)
  - `_health.canLive.enabled` (bool)
  - `_health.canLive.interface` (string)
  - `_health.canLive.dictionary` (string)
  - `_health.canReplayDiagnostics.findings` (array of expert CAN findings)
  - `_health.canLiveDiagnostics.findings` (array of expert CAN findings)
  - `_health.canDecodedSignals` (array of decoded signal names)
- Optional Arduino/serial vehicle input diagnostics:
  - `_health.serialVehicleInputs.enabled` (bool)
  - `_health.serialVehicleInputs.device` (string)
  - `_health.serialVehicleInputs.baud` (int)
  - `_health.serialVehicleInputs.stale` (bool)
- Optional deterministic signal monitor diagnostics:
  - `_health.signalMonitor.enabled` (bool)
  - `_health.signalMonitor.ok` (bool)
  - `_health.signalMonitor.watching` (array of signal names)
  - `_health.signalFaults` (array of fault objects)
  - fault codes include `out_of_range`, `impossible_jump`,
    `noisy_or_flapping`, `source_stale`, and `source_disagreement`.
  - Expert CAN fault codes can include `bus_silence`, `can_id_dropout`,
    `frame_rate_jitter`, `payload_stuck`, `decoded_signal_stuck`, and
    `dlc_changed`.
- Optional learned vehicle baseline diagnostics:
  - `_health.vehicleBaseline.enabled` (bool)
  - `_health.vehicleBaseline.ok` (bool)
  - `_health.vehicleBaseline.storagePath` (string)
  - `_health.vehicleBaseline.models` (array of model snapshots)
  - `_health.vehicleBaseline.findings` (array of learned-baseline findings)
  - Baseline findings always include `confidence`, `model`, `signal`, `code`,
    `message`, and evidence details.
  - The first built-in profile is `intake_airflow`, which compares `mafGps`
    against learned normal behavior for similar `rpm`, `throttlePct`,
    `intakeAirTempC`, and optional `engineLoadPct` / `mapKpa` when the engine
    is warm.
- Optional fault recorder diagnostics:
  - `_health.faultRecorder.enabled` (bool)
  - `_health.faultRecorder.outputDir` (string)
  - `_health.faultRecorder.bufferFrames` (int)
  - `_health.faultRecorder.writes` (int)
  - `_health.faultRecorder.lastEventPath` (string)
  - `_health.faultRecorder.lastError` (string)
- Optional normalized diagnostic display surface:
  - `_diagnostic.version` (int)
  - `_diagnostic.mode` (string)
  - `_diagnostic.ok` (bool)
  - `_diagnostic.severity` (`ok`, `info`, `warning`, or `error`)
  - `_diagnostic.status` (`nominal`, `limited`, `data_stale`, or
    `anomaly_detected`)
  - `_diagnostic.summary` (short display-ready uppercase status)
  - `_diagnostic.findingCount` (int)
  - `_diagnostic.activeFindings` (array of normalized current findings)
  - `_diagnostic.captureQuality.gpsOk` (bool)
  - `_diagnostic.captureQuality.canOk` (bool or null when CAN is not configured)
  - `_diagnostic.captureQuality.serialOk` (bool or null when serial input is not configured)
  - `_diagnostic.captureQuality.linkStale` (bool)
- Raw CAN reverse engineering stays upstream of this schema. The BBB decoder may
  load `can_signals.json` and populate existing `rpm` and `speedKph` fields, but
  BeagleY gauges, maps, and navigation should not consume raw CAN fields.
- Extra aliases accepted by BeagleY parser:
  `warnings.check|engine`, `warnings.trans|transmission`, `warnings.fuel`,
  plus `drivetrain.gear`, `transmission.gear`, `transmission.overdrive`,
  `drivetrain.mode|drivetrainMode|drive`, and
  `drivetrain.transfer_lock|transferLock|lock|locked`.
