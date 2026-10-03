# Serial vehicle input protocol (UNO / Arduino module -> BBB hub)

The BBB hub (`tools/bbb_hub/vehicle_hub_prod.py`) reads one text line per sample from the serial device
set by `VEHICLE_INPUT_SERIAL_DEVICE` (production board: `/dev/ttyS2`, BBB UART2) at
`VEHICLE_INPUT_SERIAL_BAUD` (default **115200**, 8N1, no flow control). Parsing lives in
`tools/bbb_hub/input_adapters.py`; calibration in `tools/bbb_hub/sensor_calibration.py`.
The `vehicle_state` wire format is **unchanged**.

## Line format the firmware must send

One line per sample, `\n` terminated, **10-20 lines per second**, comma-separated `key=value`
(or one JSON object per line with the same keys). **Send every field on every line**: each line
replaces the previous snapshot, so a field that is missing on a line reverts to the hub default.
The link goes stale (`_health.serialVehicleInputs.stale`) after `VEHICLE_INPUT_STALE_MS` (1000 ms) with no
valid line, so keep sending even when nothing changed.

```
left=0,right=0,high_beam=0,brake=0,oil=0,charge=0,door=0,a0=512,a1=430,speed_hz=48.2,rpm_hz=37.5
```

| Key | Meaning |
|---|---|
| `left`, `right`, `high_beam` | indicators, `0`/`1` (also `true/false/on/off`) |
| `brake`, `oil`, `charge`, `door` | warning lamps, `0`/`1` (`check`, `at`, `fuel_low` also accepted) |
| `a0` | **raw ADC counts 0-1023** of the fuel sender (alias `fuel_raw`) |
| `a1` | **raw ADC counts 0-1023** of the coolant sender (alias `coolant_raw`) |
| `speed_hz` | vehicle-speed pulse frequency in Hz (not km/h) |
| `rpm_hz` | tach pulse frequency in Hz (not rpm) |

Send **raw** values for these four and let the hub convert them; do not convert on the UNO. If the
firmware already knows final values it may instead send `fuel_pct`, `coolant_c`, `speed` (km/h), `rpm`;
a value sent pre-converted always wins over a calibrated raw value.
Unknown keys are ignored. Malformed lines count as `parseErrors` and are dropped.

Pin map used by the existing UNO sketch layout (from the vehicle-hub pin map): D2 left, D3 right,
D4 high beam, D5 brake, D6 oil, D7 charge, D8 door, A0 fuel sender, A1 coolant sender.
Note: on an UNO only D2/D3 are true external-interrupt pins, and they currently carry the indicators.
Counting speed/tach pulses needs interrupt pins, so either move the indicators or use pin-change
interrupts for the pulse inputs. Condition both pulse signals to 5 V logic (optocoupler/divider) and
the senders with a pull-up/divider so the ADC reads inside 6..1017 counts over the sender range
(counts <= 5 or >= 1018 are treated as open/shorted sender and produce no value).

## Calibration

`tools/bbb_hub/config/sensor_calibration.json` (path override `VEHICLE_SENSOR_CALIBRATION`), shipped empty:
a signal with no table is not produced and stays at the hub default `0.0`.

```json
{
  "fuel":    { "points": [[120, 0], [300, 25], [520, 50], [700, 75], [880, 100]], "low_pct": 10 },
  "coolant": { "points": [[900, 20], [500, 60], [250, 95]] },
  "speed":   { "kph_per_hz": 0.5, "max": 300 },
  "rpm":     { "rpm_per_hz": 30.0, "max": 9000 }
}
```

* `points` are `[raw_adc_counts, value]`, at least two, any order; values between points are interpolated
  linearly and clamped outside the range. Fuel is clamped to 0-100, coolant to -40..150 C.
* Capture the points with `tools/bbb_hub/sample_sensor_raw.py` (reads the live hub, read-only):
  `python3 tools/bbb_hub/sample_sensor_raw.py ws://10.24.0.7:8765 10` while the tank/engine is at a known level/temp.
* `speed.kph_per_hz` = km/h per Hz of the speed pulse (e.g. pulses-per-km / 3600 inverted); `rpm.rpm_per_hz`
  = 60 / pulses-per-revolution.
* `fuel.low_pct` drives `warnings.fuel_low` when calibrated fuel is at or below it.
* Raw ADC is smoothed with an exponential average (`smoothing_alpha`, default 0.25) before conversion.

## Speed source: GPS first, pulse fallback (`VEHICLE_SPEED_SOURCE`)

Top-level `speedKph` has two possible sources: the GPS receiver and the UNO speed pulse
(`speed_hz` x `speed.kph_per_hz`, or a pre-converted `speed` key). Implemented in
`tools/bbb_hub/speed_source.py`, wired in `vehicle_hub_prod.py`. **RPM is not affected**: the rpm source is
still undecided and keeps the previous behaviour (serial/CAN only).

| `VEHICLE_SPEED_SOURCE` | Behaviour |
|---|---|
| `gps_first` (default) | GPS speed while there is a live fix; otherwise pulse speed; otherwise `0.0` |
| `pulse_only` | previous behaviour: UNO/serial speed only, GPS never overrides it |
| `gps_only` | GPS speed only, `0.0` without a live fix |

* "Live fix" = the GPS receiver reports a valid fix **now**: GPS sentences fresh (`BBB_GPS_STALE_MS`, 2 s) and
  the fix is not the hub's 15 s fix-hold (`gps_nmea.py` keeps `fixValid` true for up to 15 s after the receiver
  loses its fix; that held speed is old, so it is not used for speed selection. `gps.fixValid` itself is unchanged).
* "Pulse available" = the UNO link is not stale and its line produced a `speedKph` (needs `speed.kph_per_hz` > 0
  in the calibration, or a pre-converted `speed`). An uncalibrated pulse is not available, so the result is `0.0`.
* **Hysteresis** (`gps_first`): fall back to the pulse only after the fix has been lost for
  `VEHICLE_SPEED_GPS_LOST_S` (default 2.0 s; the last GPS speed is held for at most that long, then replaced);
  return to GPS only after the fix has been continuously valid for `VEHICLE_SPEED_GPS_REGAIN_S` (default 2.0 s).
  If no pulse speed exists there is nothing to flap against, so GPS is used immediately.
* **Fail-safe is unchanged**: with neither source valid the speed is `0.0` (never a frozen value), reported as
  `active: "none"`. A stale UNO still contributes nothing.
* CAN-supplied speed (when the serial line has no speed) and the bench simulator are left untouched
  (`active: "other"`). If both CAN and serial supply speed, serial already overwrites CAN, so the policy applies.
* Additive health field `_health.speedSource`: `{policy, active: "gps"|"pulse"|"none"|"other", reason, gpsFix, ageS}`.
  `gpsFix` is the live-fix flag used above; `ageS` is the age of the active source (GPS sentence age or UNO line age),
  `null` for `none`. Reasons: `gps_fix`, `gps_lost_holding`, `gps_lost_pulse_fallback`, `gps_lost_no_pulse`,
  `no_gps_fix_pulse`, `gps_regain_wait`, `gps_regained`, `pulse_unavailable`, `no_valid_source`, `pulse_only`,
  `gps_only`, `gps_only_no_fix`, `bench_sim`, `can_speed`.

## Health fields (additive, under `_health.serialVehicleInputs`)

* `calibration`: `{fuel,coolant,speed,rpm}` booleans, which signals are calibrated.
* `raw`: last raw `a0`, `a1`, `speed_hz`, `rpm_hz` seen (for calibration and debugging).
* `sensorFaults`: from the most recent line, `fuel_sender_fault` / `coolant_sender_fault` for an open/shorted sender.
* `lastError` reports a missing/unusable calibration file (the hub keeps running with no calibration).

## Testing without a UNO

`tools/bbb_hub/fake_uno.py` writes lines in this format to a new pty (`--link /tmp/fake_uno`), a file/FIFO/tty (`--out`)
or stdout, with `--sweep fixed|ramp|steps|fault` (`--help`). `tests/test_fake_uno_calibration_e2e.py` runs the real hub
against it and checks raw -> calibrated values, sender faults, no-calibration and stale behaviour. Local only.

## Rollback / safety

Setting `VEHICLE_SENSOR_CALIBRATION=/nonexistent.json` (or emptying the tables) returns to pre-calibration
behaviour. Changing the file or env needs a hub process restart on the BBB; that is a deploy step and
needs approval.
