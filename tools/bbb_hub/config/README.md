# tools/bbb_hub/config

* `sensor_calibration.json`: the UNO sensor calibration (ships empty). See `docs/serial_vehicle_input_protocol.md`.
* `can_signals.obd2_example.json`: **STARTER / EXAMPLE ONLY for CAN, not a verified vehicle mapping.** It is not loaded by
  default. Generic ISO 15765-4 (11-bit, 500 kbit/s) OBD-II Mode 01 *responses* from ECU #1 (`0x7E8`) with the public
  SAE J1979 formulas:

  | Signal | PID | Bytes (`0x7E8` payload `[len, 0x41, PID, A, B, ...]`) | Formula |
  |---|---|---|---|
  | `speedKph` | 0x0D | A | A km/h |
  | `rpm` | 0x0C | A, B | (256A + B) / 4 |
  | `coolantC` | 0x05 | A | A - 40 |
  | `fuelPct` | 0x2F | A | A x 100 / 255 |

  Because one CAN ID carries every PID, each signal has an optional `when` list (additive schema field, see
  `tools/schema/can_signals_v1.md`) that requires byte 1 = `0x41` and byte 2 = the PID. Dictionaries without `when`
  behave as before. All entries have `verified: false` and `confidence: 0.0` on purpose.

  Caveats: the hub never sends requests, so these frames only appear if another tool on the bus is polling; the ECU may
  not answer PID 0x2F; manufacturers may use other IDs or 29-bit addressing; check the bitrate. Try it offline:

  ```bash
  python3 -m pytest tests/test_can_prep.py -q           # decode + fake SocketCAN + hub overlay
  CAN_SIGNAL_DICTIONARY=tools/bbb_hub/config/can_signals.obd2_example.json CAN_RAW_LOG=some_candump.log \
      python3 tools/bbb_hub/vehicle_hub_prod.py          # offline replay overlay (local only)
  ```

## Generating a real `can_signals.json`

1. Capture a listen-only candump on the car (`docs/can_bus_parts_and_wiring.md`), ideally together with OBD-II Mode 01
   anchors and/or GPS speed for the same period (`tools/can_reverse_workbench/README.md`, `capture-session`).
2. Run the workbench `analyze` with `--target rpm --target speedKph ...`; it exports only verified, anchored mappings to
   `can_signals.json` (schema: `tools/schema/can_signals_v1.md`).
3. Validate by replay (`CAN_SIGNAL_DICTIONARY` + `CAN_RAW_LOG`) before live use, then set `CAN_LIVE_INTERFACE=can0`.
