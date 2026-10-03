# Bench test checklist: Arduino UNO + BBB hub, no vehicle inputs connected

Scope: UNO on the bench, fed only by a pot / voltage divider and a function generator (or the UNO's own
test pulses), talking to the BBB hub. **No real vehicle wiring, no 12 V.** Expected values below are
derived from the code (`tools/bbb_hub/sensor_calibration.py`, `input_adapters.py`, `speed_source.py`,
`vehicle_hub_prod.py`, `check_hub_health.py`, `sample_sensor_raw.py`) unless marked **TO CONFIRM**.
The fuel/coolant sender mapping is **not decided** (it will be worked out on the real vehicle), so nothing
here is a sender calibration; the bench calibration in section 5 is an arbitrary linear scale to prove the
conversion path only.

Hub address used below: `ws://10.24.0.7:8765`. All hub-side checks are read-only WebSocket clients and
can run from any machine with Python and `websockets` (`pip install websockets`).

## 0. Safety (read first)

- [ ] The UNO is **bench-only** here. It is never connected to the vehicle in this checklist.
- [ ] UNO TX is 5 V; BBB pins are 3.3 V and **not 5 V tolerant**. UNO TX (D1) -> **1 kOhm** -> node -> BBB
      **UART4 RX = P9_11**; node -> **2 kOhm** -> GND (about 3.3 V at the node). Nothing else from the UNO goes to the BBB.
- [ ] UNO GND and BBB GND (P9_1 or P9_2) are connected (common ground).
- [ ] **Never** connect the UNO 5 V pin (or any 5 V) to a BBB pin. Power the UNO from its own USB cable/supply.
      Leave BBB TX (P9_13) unconnected (the hub only reads).
- [ ] A0/A1/D2/D3 only ever see 0..5 V (no negative voltages, no >5 V). Function generator: 0..5 V square wave,
      DC offset set so the low level is 0 V, unloaded amplitude checked on a scope/meter **before** connecting.
- [ ] While uploading firmware, **disconnect the D1 wire** (D1 is shared with the USB serial used for upload).
- [ ] Wiring per `docs/bbb_hardware_wiring.md`. The UART4 overlay is enabled and `/dev/ttyS4` exists on the board (2026-10-03).
      The GPS-vs-UNO device question is **resolved**: GPS = `/dev/ttyS1` (UART1), UNO input = `/dev/ttyS4` (UART4).
      Still **TO CONFIRM on the bench**: the UART4 pin-mux (`config-pin -q P9_11`, not yet queried) and the UNO wiring
      (nothing is wired to UART4 yet, so the hub currently reads 0 serial frames).
- [ ] Changing the hub env file and restarting the hub is a board change and needs approval
      (`docs/bbb_deploy_rollback.md`). The hub on the board runs release `305b982` (2026-10-03), which
      contains `speed_source.py` (GPS-first speed).

## 1. Prerequisites

- [ ] UNO flashed with `firmware/uno_vehicle_input` (see its README), real-input mode (no `BENCH_SIM`), or with
      `BENCH_SIM=1` for the self-stepping variant in section 6. **TO CONFIRM**: the sketch has been compiled but not yet run on hardware.
- [ ] Hub env (`/etc/default/bbb-hardware-gps`): `VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4`
      (set on the deployed board; see section 0), `VEHICLE_INPUT_SERIAL_BAUD=115200`, `VEHICLE_INPUT_STALE_MS=1000` (default).
      `BBB_VEHICLE_BENCH_SIM` must be **unset or 0** (otherwise the hub shows synthetic values).
- [ ] `VEHICLE_SENSOR_CALIBRATION` unset for sections 2-4 (shipped file `tools/bbb_hub/config/sensor_calibration.json` is empty).

Commands used throughout (run from a repo checkout):

```bash
python3 tools/bbb_hub/check_hub_health.py ws://10.24.0.7:8765 --require-gps            # add --require-serial for the UNO
python3 tools/bbb_hub/sample_sensor_raw.py ws://10.24.0.7:8765 10                      # 10 s of raw/fuel/coolant/speed lines + min/mean/max
```

`check_hub_health.py` exit codes: 0 healthy, 1 hub up but a required source is stale, 2 hub unreachable/malformed.
Note `--require-gps` checks that GPS **sentences are arriving** (`_health.gpsStale` false), **not** that there is a fix.
`sample_sensor_raw.py` prints one line per frame:
`raw={...} stale=... faults=[...] fuelPct=... coolantC=... speedKph=... rpm=... speedSource=gps|pulse|none`
then `a0:/a1:/speed_hz:/rpm_hz: n= mean= min= max=`.

## 2. Link / health (UNO talking, GPS module connected, fix not required)

- [ ] `check_hub_health.py ws://10.24.0.7:8765 --require-gps --require-serial` prints `OK source=serial stale=False gpsStale=False`, exit 0.
- [ ] Unplug the UNO TX wire: within about 1 s (`VEHICLE_INPUT_STALE_MS`) `--require-serial` returns exit 1 with
      `serial stale/disabled`; `speedKph`, `rpm`, indicators fall back to `0.0`/false (fail-safe, no frozen values). Re-plug: recovers, exit 0.
- [ ] `_health.serialVehicleInputs`: `enabled: true`, `stale: false`, `frames` increasing, `parseErrors: 0`, `baud: 115200`.

## 3. A0 (fuel) and A1 (coolant): voltage steps, **empty calibration**

Set each input with a pot (ends on UNO 5 V and GND, wiper to the pin) and **verify the wiper voltage with a
multimeter**. Drive A0 and A1 together or one at a time. UNO ADC: 10 bit, 5 V reference, `raw = V / 5 * 1023`,
plus or minus about 1-2 counts (floating-point result is truncated by the ADC, noise, the actual 5 V rail).

| Step | Volts | Nominal raw | Expect raw in range | Pass |
|---|---|---|---|---|
| 1 | 0 V | 0 | 0..3 | [ ] |
| 2 | 1.25 V | 255.75 | 254..258 | [ ] |
| 3 | 2.5 V | 511.5 | 509..514 | [ ] |
| 4 | 3.75 V | 767.25 | 765..770 | [ ] |
| 5 | 5 V | 1023 | 1021..1023 | [ ] |

(The tolerance bands are estimates, not measured: TO CONFIRM. If the UNO rail is e.g. 4.8 V instead of 5.0 V the counts scale accordingly: TO CONFIRM against the multimeter reading.)

What the hub shows at **every** step with the shipped empty calibration (derived from the code):

- [ ] `_health.serialVehicleInputs.raw.a0` / `.a1` = the counts above (as floats, e.g. `512.0`); visible with `sample_sensor_raw.py`.
- [ ] `_health.serialVehicleInputs.calibration` = `{fuel:false, coolant:false, speed:false, rpm:false}`.
- [ ] `fuelPct = 0.0` and `coolantC = 0.0` (no calibration means the hub default stays; nothing is invented).
- [ ] `sensorFaults = []` even at 0 V and 5 V (fault detection only runs for a calibrated signal).
- [ ] `lastError` is `null`. `stale: false` while the UNO streams.

## 4. speed_hz and rpm_hz pulse steps, **empty calibration**

Apply a 0..5 V square wave (about 50 % duty) to **D2 = speed** and **D3 = rpm** (common ground with the generator).
The sketch counts one edge per pulse, over a 200 ms window, so the resolution is 5 Hz (one pulse per window);
`speed_hz` therefore jitters by +-5 Hz at low frequency. The sketch ignores edges closer than 100 us (about 10 kHz max).

| Step | Generator | Expect `raw.speed_hz` / `raw.rpm_hz` | Pass |
|---|---|---|---|
| 1 | 10 Hz | 10 (range 5..15) | [ ] |
| 2 | 50 Hz | 50 (range 45..55) | [ ] |
| 3 | 100 Hz | 100 (range 95..105) | [ ] |
| 4 | 200 Hz | 200 (range 195..205) | [ ] |
| 5 | generator off | 0 within one window (about 0.2 s) | [ ] |

(These ranges describe the sketch's counting window; the sketch has **not** been run on hardware: TO CONFIRM.)

Hub with empty calibration (`speed.kph_per_hz = 0`, `rpm.rpm_per_hz = 0`, derived from the code):

- [ ] `raw.speed_hz` and `raw.rpm_hz` show the measured Hz.
- [ ] `speedKph = 0.0`, `rpm = 0.0` (an uncalibrated pulse produces no value; the hub does not guess a scale).
- [ ] `_health.speedSource.active = "none"`, `reason = "no_valid_source"` while there is no GPS fix (pulse speed is not available without a `kph_per_hz`).

## 5. Temporary **bench** calibration (shows percent / degrees / km/h / rpm)

This is an arbitrary linear scale for the bench, **not** a sender calibration. Do not leave it on the board.

Save as e.g. `/tmp/bench_cal.json` on the BBB (`smoothing_alpha: 1.0` removes the 0.25 smoothing so numbers are exact):

```json
{
  "fuel":    { "points": [[6, 0], [1017, 100]], "low_pct": 10, "smoothing_alpha": 1.0 },
  "coolant": { "points": [[6, 0], [1017, 120]], "smoothing_alpha": 1.0 },
  "speed":   { "kph_per_hz": 0.5, "max": 300 },
  "rpm":     { "rpm_per_hz": 30.0, "max": 9000 }
}
```

- [ ] Set `VEHICLE_SENSOR_CALIBRATION=/tmp/bench_cal.json` in the hub env and restart **the hub only** (approval needed, section 0).
- [ ] `_health.serialVehicleInputs.calibration` = all four `true`. `lastError` is `null` (a typo in the path shows `calibration file not found`).

Expected (computed with the real conversion code; raw within the ranges of section 3):

| A0=A1 raw | about V | `fuelPct` | `coolantC` | `sensorFaults` | Pass |
|---|---|---|---|---|---|
| 0 | 0 V | stays `0.0` (no value) | stays `0.0` | `fuel_sender_fault`, `coolant_sender_fault` | [ ] |
| 256 | 1.25 V | 24.7 (255 gives 24.6) | 29.7 (255 gives 29.6) | `[]` | [ ] |
| 512 | 2.5 V | 50.0 | 60.1 (511 gives 59.9) | `[]` | [ ] |
| 767 | 3.75 V | 75.3 | 90.3 | `[]` | [ ] |
| 1023 | 5 V | stays `0.0` (no value) | stays `0.0` | `fuel_sender_fault`, `coolant_sender_fault` | [ ] |

Raw at or below 5 or at or above 1018 counts is treated as an open/shorted sender and produces no value, never a fake one.
Rule: `fuelPct = (raw - 6) / 1011 * 100`, `coolantC = (raw - 6) / 1011 * 120`, rounded to 0.1.
- [ ] `warnings.fuel_low` becomes true when `fuelPct <= 10` (raw about 107 or lower, above the fault limit of 5).
      Check with a divider at about 0.52 V (raw about 107 gives about 10 %): **TO CONFIRM** with a multimeter.

Pulses with the bench calibration (`speedKph = speed_hz * 0.5`, `rpm = rpm_hz * 30`). These only reach `speedKph` when the
pulse is the active source: **no GPS fix** (or `VEHICLE_SPEED_SOURCE=pulse_only`).

| Generator | `speedKph` | `rpm` | Pass |
|---|---|---|---|
| 10 Hz | 5.0 | 300 | [ ] |
| 50 Hz | 25.0 | 1500 | [ ] |
| 100 Hz | 50.0 | 3000 | [ ] |
| 200 Hz | 100.0 | 6000 | [ ] |

(+-5 Hz sketch resolution gives +-2.5 km/h and +-150 rpm at the bench scale.) With the generator off, both go to 0.
`rpm` is **not** subject to the GPS-first rule: the rpm source is still undecided and rpm always comes from the serial/CAN path.

## 6. Optional: BENCH_SIM firmware (no pot, no generator)

Compile with `-DBENCH_SIM=1` (firmware README). The sketch ignores A0/A1/D2/D3 and cycles through five steps, each held 5 s:

| Step | a0 | a1 | speed_hz | rpm_hz |
|---|---|---|---|---|
| 0 | 0 | 1023 | 0.0 | 200.0 |
| 1 | 256 | 767 | 10.0 | 100.0 |
| 2 | 512 | 512 | 50.0 | 50.0 |
| 3 | 767 | 256 | 100.0 | 10.0 |
| 4 | 1023 | 0 | 200.0 | 0.0 |

- [ ] `sample_sensor_raw.py ... 30` shows `raw` stepping through exactly these values every 5 s (a0 and a1 are exact in this mode).
- [ ] With the section 5 calibration, `speedKph`/`rpm`/`fuelPct`/`coolantC` follow the tables above (speed and rpm only while the pulse is the active speed source; fuel/coolant at 0 and 1023 show the fault behaviour).

## 7. GPS-first speed check (`VEHICLE_SPEED_SOURCE=gps_first`, the default)

Needs the section 5 calibration (otherwise there is no pulse speed to fall back to) and the GPS antenna.
Feed a steady **100 Hz** on D2 (pulse speed = 50.0 km/h). Defaults: `VEHICLE_SPEED_GPS_LOST_S=2.0`, `VEHICLE_SPEED_GPS_REGAIN_S=2.0`, `BBB_GPS_STALE_MS=2000`.
Watch `speedKph` and `_health.speedSource` (`sample_sensor_raw.py` prints `speedKph` and `speedSource=`).

A bench GPS is stationary, so the GPS speed is near 0 (receiver noise, typically under 1-2 km/h; **TO CONFIRM**) while the pulse says 50.0. That makes the source visible.

- [ ] **7a. Antenna with sky view, fix acquired** (`gps.fixValid: true`, `gps.satellites >= 4`): `speedSource.active = "gps"`,
      `reason = "gps_fix"`, `gpsFix = true`, and `speedKph` equals the GPS speed (`gps.speedKph` rounded to 0.1, near 0), **not** 50.0.
- [ ] **7b. Disconnect the antenna or the GPS TX** (fix lost): `speedKph` follows the GPS value (`reason = "gps_lost_holding"`) for
      at most 2 s after the fix is judged lost, then `active = "pulse"`, `reason = "gps_lost_pulse_fallback"`, `speedKph = 50.0`, `gpsFix = false`.
      Timing from the code: if the module keeps sending sentences without a fix, the loss is seen at once (the hub's 15 s `fixValid` hold
      is not used for speed), so the switch is about 2 s later; if the sentences stop, add `BBB_GPS_STALE_MS` (2 s), so about 4 s.
- [ ] **7c. Reconnect / fix returns**: `speedKph` stays 50.0 with `reason = "gps_regain_wait"` for 2 s of continuous valid fix, then
      `active = "gps"`, `reason = "gps_regained"`. A fix that drops again inside those 2 s restarts the wait (no flapping). Time to re-acquire a fix: **TO CONFIRM**.
- [ ] **7d. No GPS at all from the start** (GPS TX unplugged before hub start): pulse is used immediately, `active = "pulse"`, `reason = "no_gps_fix_pulse"`, `speedKph = 50.0`.
- [ ] **7e. Both lost**: (i) GPS fix lost with the UNO unplugged: `speedKph = 0.0` about 2 s after the fix is judged lost (the GPS grace);
      (ii) already on the pulse fallback and the UNO then goes silent: `speedKph = 0.0` as soon as the UNO link is stale (about 1 s).
      Either way `active = "none"`, `ageS = null`, `gpsFix = false`; the last value is never held.
- [ ] **7f. `VEHICLE_SPEED_SOURCE=pulse_only`** (hub restart, approval needed): with a GPS fix `speedKph` stays 50.0 (pulse). **`gps_only`**: without a fix `speedKph = 0.0`, `active = "none"`.

Result:  Pass [ ]   Fail [ ]   Date/operator: ______________   Hub build/commit: ______________   Notes: ______________

## 8. Tear-down

- [ ] Remove `VEHICLE_SENSOR_CALIBRATION=/tmp/bench_cal.json` from the hub env (or point it back to the shipped empty file) and restart the hub (approval needed).
- [ ] Disconnect the function generator and pot before any vehicle connection. Vehicle-side conditioning (optocouplers, fuse, TVS, divider) is covered in `docs/bbb_hardware_wiring.md`, not here.
