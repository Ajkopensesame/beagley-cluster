# uno_vehicle_input (Arduino UNO vehicle-input module)

No Arduino firmware for this project was found anywhere (repos `beagley-cluster` and `vehicle-hub`, their git
history, the box, GitHub), so this sketch was written from `docs/serial_vehicle_input_protocol.md`.
**Status: compiles for `arduino:avr:uno` (arduino-cli, both normal and `BENCH_SIM=1`); NOT run on hardware.**
The line it prints is checked against the hub's real parser by `tests/test_uno_firmware_line.py` (no hardware).

## What it sends

115200 baud, 8N1, one line every ~100 ms, every field on every line:

```
left=0,right=0,high_beam=0,brake=0,oil=0,charge=0,door=0,a0=512,a1=430,speed_hz=48.2,rpm_hz=37.5
```

- `a0`, `a1`: raw `analogRead` counts (0-1023, 5 V reference) of the fuel / coolant senders. No conversion on the UNO.
- `speed_hz`, `rpm_hz`: pulse frequency in Hz from `attachInterrupt` on **D2 (speed, INT0)** and **D3 (rpm, INT1)**, counted over a
  200 ms window (resolution 5 Hz) and printed with one decimal. Edges closer than 100 us are ignored (glitch filter).
- Lamp lines are `0`/`1`. **Proposed pin map** (the legacy map had indicators on D2/D3, which are the only interrupt pins, so the
  indicators moved): D4 high_beam, D5 brake, D6 oil, D7 charge, D8 door, D9 left, D10 right.
  By default inputs are `INPUT_PULLUP` and **active low** (optocoupler output pulls the pin low). Use `-DINPUT_ACTIVE_LOW=0` for active-high. **TO CONFIRM** against the real input module.
- Pulses count `FALLING` edges (`-DPULSE_EDGE=RISING` to change). **TO CONFIRM** against the real conditioning circuit.

The hub turns counts / Hz into fuel %, coolant C, km/h and rpm with `tools/bbb_hub/config/sensor_calibration.json`.

## BENCH_SIM mode

`-DBENCH_SIM=1` ignores A0/A1/D2/D3 and cycles through five steps (5 s each), for bench use only:

| Step | a0 | a1 | speed_hz | rpm_hz |
|---|---|---|---|---|
| 0 | 0 | 1023 | 0.0 | 200.0 |
| 1 | 256 | 767 | 10.0 | 100.0 |
| 2 | 512 | 512 | 50.0 | 50.0 |
| 3 | 767 | 256 | 100.0 | 10.0 |
| 4 | 1023 | 0 | 200.0 | 0.0 |

(a0 = round(V/5*1023) for 0, 1.25, 2.5, 3.75, 5 V.) Lamp fields still read the real pins.

## Wiring (bench)

```
UNO D1 (TX) --[1 kOhm]--+--> BBB P9_11 (UART4 RX, /dev/ttyS4: TO CONFIRM)
                        |
                      [2 kOhm]
                        |
UNO GND ----------------+--> BBB GND (P9_1 / P9_2)   (common ground)
```

- UNO TX is 5 V; BBB pins are 3.3 V and not 5 V tolerant: the 1k/2k divider is mandatory. Never connect 5 V to any BBB pin.
- Leave BBB TX unconnected. Power the UNO from USB or its own supply, not from the BBB.
- Disconnect the D1 wire while uploading (D1 is shared with the USB serial).
- A0/A1/D2/D3 must stay within 0-5 V. Vehicle 12 V signals need optocouplers/dividers first (`docs/bbb_hardware_wiring.md`, `docs/vehicle_hub_scope.md`). The UNO is bench-only until that is built and verified.
- Using USB to the BBB instead shows up as `/dev/ttyACM0` (no divider needed): TO CONFIRM.

## Build and upload (arduino-cli)

```bash
arduino-cli core update-index && arduino-cli core install arduino:avr
cd firmware
arduino-cli compile --fqbn arduino:avr:uno uno_vehicle_input
arduino-cli compile --fqbn arduino:avr:uno --build-property "build.extra_flags=-DBENCH_SIM=1" uno_vehicle_input   # bench-sim variant
arduino-cli board list                                                      # find the port, e.g. /dev/ttyACM0
arduino-cli upload -p /dev/ttyACM0 --fqbn arduino:avr:uno uno_vehicle_input
arduino-cli monitor -p /dev/ttyACM0 -c baudrate=115200                      # eyeball the lines (D1 wire disconnected from the BBB)
```

Compile result (arduino-cli 1.5.2-rc.1, core arduino:avr 1.8.8): normal build 5140 bytes flash (15 %), 232 bytes RAM; `BENCH_SIM=1` 5076 bytes flash, 284 bytes RAM.

Bench procedure and expected hub readings: `docs/bench_test_checklist.md`.
