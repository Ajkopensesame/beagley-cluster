# UNO bench setup: flash, wire, test

Ready-to-use notes for putting `firmware/uno_vehicle_input/uno_vehicle_input.ino` on an Arduino UNO and proving the
UNO -> BBB hub path on the bench. Bench only: **no vehicle wiring, no 12 V**. Statements I could not check from the
repo or hardware are marked **(UNVERIFIED)**. Protocol: `docs/serial_vehicle_input_protocol.md`. Longer checklist with
expected numbers: `docs/bench_test_checklist.md`. Nothing here has been run on the board; the sketch is compile-checked only.

## 0. No UNO at hand? Simulate it locally first

`tools/bbb_hub/fake_uno.py` writes the same lines to a pty, so the real hub can be exercised on a laptop (no BBB, no BeagleY):

```bash
python3 tools/bbb_hub/fake_uno.py --link /tmp/fake_uno --sweep ramp --period 20 &     # or --sweep steps | fault | fixed
VEHICLE_INPUT_SERIAL_DEVICE=/tmp/fake_uno BBB_HUB_HOST=127.0.0.1 BBB_HUB_PORT=8765 \
  VEHICLE_SENSOR_CALIBRATION=/tmp/bench_cal.json python3 tools/bbb_hub/vehicle_hub_prod.py
python3 tools/bbb_hub/sample_sensor_raw.py ws://127.0.0.1:8765 10
```

## 1. Compile and upload (arduino-cli)

```bash
arduino-cli core update-index && arduino-cli core install arduino:avr
cd firmware
arduino-cli compile --fqbn arduino:avr:uno uno_vehicle_input
arduino-cli board list                      # port column: /dev/ttyACM0 (genuine UNO) or /dev/ttyUSB0 (CH340/FTDI clones)
arduino-cli upload -p /dev/ttyACM0 --fqbn arduino:avr:uno uno_vehicle_input
arduino-cli monitor -p /dev/ttyACM0 -c baudrate=115200      # expect ~10 lines/s; Ctrl-C to quit
```

* Clones often show as "Unknown" in `board list`; the `--fqbn arduino:avr:uno` flag is what matters. Pick the port that
  appears when the UNO is plugged in (`ls /dev/ttyACM* /dev/ttyUSB*` before/after).
* Linux: if upload says permission denied, add your user to `dialout` and log in again.
* Optional self-stepping variant, no inputs needed (bench only):
  `arduino-cli compile --fqbn arduino:avr:uno --build-property "build.extra_flags=-DBENCH_SIM=1" uno_vehicle_input` then upload.
  Other options: `-DINPUT_ACTIVE_LOW=0`, `-DPULSE_EDGE=RISING` (see the sketch header).
* **Unplug the D1 (TX) wire to the BBB while uploading and while the serial monitor is open**: D1 is shared with USB serial.
* Expected output line: `left=0,right=0,high_beam=0,brake=0,oil=0,charge=0,door=0,a0=512,a1=430,speed_hz=48.2,rpm_hz=37.5`.

## 2. Pin table (read from the sketch)

| UNO pin | Signal | Notes |
|---|---|---|
| D2 | speed pulse (INT0) | falling edges counted; keep within 0-5 V |
| D3 | rpm pulse (INT1) | same |
| D4 / D5 / D6 / D7 | high_beam / brake / oil / charge | lamp inputs, `INPUT_PULLUP`, **active low** by default |
| D8 / D9 / D10 | door / left / right | same |
| A0 | fuel sender, raw 0-1023 | `a0` |
| A1 | coolant sender, raw 0-1023 | `a1` |
| D1 (TX) | serial to BBB, 115200 8N1 | through the divider below |

The sketch's own comment calls this pin map a "proposal" (the legacy map had indicators on D2/D3). **(UNVERIFIED against the real input module.)**

## 3. UNO TX -> BBB wiring (5 V to 3.3 V)

```
UNO D1 (TX) --[1 kOhm]--+--> BBB P9_11 (UART4_RXD)
                        |
                      [2 kOhm]
                        |
UNO GND ----------------+--> BBB P9_1 or P9_2 (GND)
```

* Node voltage = 5 V x 2/3 = about 3.3 V. BBB pins are **not 5 V tolerant**. Never connect the UNO 5 V pin to the BBB.
* Common ground is required. Leave BBB TX (P9_13) unconnected. Power the UNO from its own USB cable/supply.
* BBB side: per the project notes the `BB-UART4` overlay is enabled and the hub reads **`/dev/ttyS4` @ 115200**. The repo's
  docs still call UART4 a proposal (`docs/bbb_hardware_wiring.md`, `docs/BOARD_RUNBOOK.md`), so before trusting it,
  read-only: `dmesg | grep -i ttyS`, `config-pin -q P9_11`, and the `device` field in the hub health (below). **(UNVERIFIED here.)**

## 4. Bench inputs

* **A0 / A1**: a 10 kOhm potentiometer each, outer legs to UNO 5 V and GND, wiper to the pin. Check the wiper with a meter.
  `raw = V / 5 x 1023`: 0 V = 0, 2.5 V = about 512, 5 V = 1023. At the extremes (raw <= 5 or >= 1018) the hub treats it as an
  open/shorted sender (fault, no value). Stay inside 6..1017 for normal readings.
* **D2 / D3 pulses**: a function generator set to a 0-5 V square wave (low level at 0 V, checked on a meter/scope **before**
  connecting), or a second UNO running `void setup(){ tone(9, 100); } void loop(){}` with its pin 9 -> D2 and grounds joined.
  100 Hz should show `speed_hz` of about 100 (the sketch counts over 200 ms, so resolution is about 5 Hz). **(UNVERIFIED)**
* Lamps: ground a lamp pin (D4-D10) to light that flag (active low).

## 5. What to look for in the hub health

Read-only clients (any machine that can reach the hub, `pip install websockets`):

```bash
python3 tools/bbb_hub/check_hub_health.py ws://10.24.0.7:8765 --require-serial     # exit 0 = serial live
python3 tools/bbb_hub/sample_sensor_raw.py ws://10.24.0.7:8765 10                   # raw + converted values per frame
```

`_health.serialVehicleInputs` in each `vehicle_state` frame:

| Field | Meaning on the bench |
|---|---|
| `enabled` | `true` once `VEHICLE_INPUT_SERIAL_DEVICE` is set and the hub could build the source |
| `device`, `baud` | should be `/dev/ttyS4`, `115200` |
| `frames` | rises about 10/s while the UNO runs. Stuck at 0 = wiring/pin-mux/baud |
| `parseErrors` | stays 0. Rising = garbled line (level or ground problem, wrong baud) |
| `stale` / `ageMs` | `false` / under 1000 while lines arrive; `true` after `VEHICLE_INPUT_STALE_MS` (1000 ms) of silence (values then drop to 0 and `vehicleSource` becomes `none`) |
| `raw` | last `a0`, `a1`, `speed_hz`, `rpm_hz` as seen (works with no calibration; use these for calibration points) |
| `calibration` | `{fuel, coolant, speed, rpm}` booleans: which signals have a calibration table loaded |
| `sensorFaults` | `fuel_sender_fault` / `coolant_sender_fault` for raw <= 5 or >= 1018, only for a calibrated signal |
| `lastError` | may be cleared once the port opens, so check the `calibration` flags, not this, for a missing calibration file |

With **no calibration** the frame keeps `fuelPct`/`coolantC`/`speedKph`/`rpm` at the hub default `0.0` (the hub does not
invent values); only `raw` moves. Speed: with `VEHICLE_SPEED_SOURCE=gps_first` the pulse speed is only used when there is no GPS fix.

## 6. Setting calibration on the BBB (describe only; do not run without approval)

Config lives in `/etc/default/bbb-hardware-gps` (systemd `EnvironmentFile` of `bbb-hardware-gps.service`). Back it up first.

```
VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4
VEHICLE_INPUT_SERIAL_BAUD=115200
VEHICLE_INPUT_STALE_MS=1000
VEHICLE_SENSOR_CALIBRATION=/home/debian/sensor_calibration.json
```

1. Copy `tools/bbb_hub/config/sensor_calibration.json` to the path above and fill in the tables:
   `fuel.points` / `coolant.points` = `[[raw_counts, value], ...]` (at least 2), `speed.kph_per_hz`, `rpm.rpm_per_hz`.
   Bench-only example (proves the path, **not** a sender calibration): `{"fuel": {"points": [[6, 0], [1017, 100]]}, "coolant": {"points": [[6, 0], [1017, 100]]}}`.
2. Capture real points with the sender at a known level/temperature: `sample_sensor_raw.py ws://10.24.0.7:8765 10` and use the mean `a0`/`a1`.
3. Restart only the hub: `sudo systemctl restart bbb-hardware-gps` (a deploy step: gauges blank for a moment). Roll back by
   pointing `VEHICLE_SENSOR_CALIBRATION` at a nonexistent file or restoring the backed-up env file (`docs/bbb_deploy_rollback.md`).
4. Check `calibration` flags are `true` and `fuelPct`/`coolantC` follow the pots.

## 7. Bench test steps

1. Flash (section 1), wire (section 3), power the UNO, hub running. `check_hub_health.py ... --require-serial` -> exit 0.
2. Turn the pots: `raw.a0`/`raw.a1` follow `V/5 x 1023`.
3. Apply a pulse on D2/D3: `raw.speed_hz` / `raw.rpm_hz` follow the frequency.
4. Load a calibration (section 6): converted values appear; a pot at the extreme shows the sender fault, no value.
5. Unplug UNO TX: `stale` turns `true` within about 1 s and values fall back to 0; re-plug: recovers.
