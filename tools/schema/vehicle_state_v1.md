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
- Extra aliases accepted by BeagleY parser:
  `warnings.check|engine`, `warnings.trans|transmission`, `warnings.fuel`,
  plus `drivetrain.gear`, `transmission.gear`, `transmission.overdrive`,
  `drivetrain.mode|drivetrainMode|drive`, and
  `drivetrain.transfer_lock|transferLock|lock|locked`.
