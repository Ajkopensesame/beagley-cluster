# BBB hardware: UART/pin map, wiring safety, CAN bring-up

Status: **UART4 overlay enabled and deployed on the BBB (2026-10-03, ~15:23 AEST); nothing is wired to UART4 yet.**
Pin numbers below are the standard BeagleBone Black header functions; the pin-mux (`config-pin -q P9_11`) has **not**
been queried on the board, so confirm it on the bench before wiring. See `docs/BOARD_RUNBOOK.md`, section
"Deployed board state (verified 2026-10-03 15:55 AEST)".

## Serial port / pin map

| UART | Linux device | RX pin | TX pin | Current/planned use |
|---|---|---|---|---|
| UART1 | `/dev/ttyS1` | P9_26 | P9_24 | **GPS** (live hub reported GPS on `/dev/ttyS1`) |
| UART2 | `/dev/ttyS2` | P9_22 | P9_21 | overlay enabled, **unused**; the original UNO input, **RX pin P9_22 is damaged, do not use** |
| UART4 | `/dev/ttyS4` | P9_11 | P9_13 | **UNO serial input**: overlay enabled and `/dev/ttyS4` present; hub reads it (`VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4` @115200). UNO TX -> P9_11 **not wired yet** (0 frames); pin-mux not queried |
| UART5 | `/dev/ttyS5` | P8_38 | P8_37 | spare (may clash with HDMI pins on some images) |
| DCAN0 | `can0` | P9_19 (RX) | P9_20 (TX) | planned CAN (shares pins with I2C2) |
| DCAN1 | `can1` | P9_26 | P9_24 | **not usable while UART1 carries the GPS** |

**Resolved (2026-10-03):** the GPS is on UART1 (`/dev/ttyS1`) and the UNO input is on UART4 (`/dev/ttyS4`). Older
text (`docs/beagley_wifi_architecture.md`, `tools/bbb_hub/bbb-hardware-gps.env.example`) that set
`BBB_GPS_DEVICE=/dev/ttyS4` was wrong and has been corrected. Note the hub code default in
`tools/bbb_hub/vehicle_hub_prod.py` is still `/dev/ttyS4` if `BBB_GPS_DEVICE` is unset; the deployed env file sets it
explicitly to `/dev/ttyS1`, so always keep `BBB_GPS_DEVICE` set.

Deployed UART4 change (done by `bbb_stage.sh stage3`, with `/boot/uEnv.txt` backups on the board): overlay
`BB-UART4` (`addr6`; `addr4`=BB-UART1, `addr5`=BB-UART2) added to `/boot/uEnv.txt`, BBB rebooted, then
`VEHICLE_INPUT_SERIAL_DEVICE=/dev/ttyS4` set in `/etc/default/bbb-hardware-gps` and the hub restarted. Rollback:
`bbb_stage.sh rollback3` (see `docs/BOARD_RUNBOOK.md`). Serial line format: `docs/serial_vehicle_input_protocol.md`.

## GPS time (system clock)

The BBB has no battery RTC and no internet on its only link, so after every boot its clock is wrong until
something sets it. The GPS is the only time source, and `/dev/ttyS1` cannot be shared with gpsd, so the hub
publishes the time and a small helper applies it:

* Hub (`gps_nmea.py`): `gps.utcMs` / `gps.utcValid` in every `vehicle_state` frame. They come **only** from an
  RMC sentence with status `A`, a valid `hhmmss` time and a valid `ddmmyy` date (year >= 2026), advanced by
  monotonic time since receipt. `utcValid` is false for GGA-only data, status `V`, bad dates, stale or held
  fixes and when the RMC UTC is older than 5 s. The existing `gps.timestampMs` is unchanged (for GGA it still
  takes the date from the wall clock, so it can be wrong while the clock is wrong).
* Helper (`tools/bbb_hub/gps_clock.py`, service `bbb-gps-clock`, runs as `debian` with only `CAP_SYS_TIME`):
  needs 5 consecutive valid frames with >= 4 satellites, then steps the clock if it is off by more than 1 s,
  re-checking at most every 10 minutes. Dates outside 2026-01-01..2040-01-01 are rejected. Expect accuracy
  within roughly a second (serial and WebSocket latency), which is plenty for logs and timestamps.
* The clock stays wrong until the first fix after power-up (cold start can take minutes; indoors there is none).
  A coin-cell RTC module would be a hardware add-on if time must survive power-off.

Check on the BBB: `date; journalctl -u bbb-gps-clock -n 20 --no-pager` (look for `stepped clock by ...`), and
without changing anything: `python3 /home/debian/releases/current/tools/bbb_hub/gps_clock.py --once --dry-run`
(exit 0 clock right, 10 clock off, 2 no usable GPS time, 3 hub unreachable). Overrides (optional, in
`/etc/default/bbb-gps-clock`): `GPS_CLOCK_HUB_URL`, `GPS_CLOCK_STEP_THRESHOLD_S`, `GPS_CLOCK_RECHECK_S`,
`GPS_CLOCK_DRY_RUN=1`. Deploy: `tools/bbb_hub/deploy/` (`bbb_stage.sh stage2`).

## UNO <-> BBB wiring safety

* **Levels.** BBB GPIO is 3.3 V and **not 5 V tolerant**; the UNO drives 5 V. UNO TX -> BBB RX needs level shifting.
  * Minimum: resistor divider on that one wire, 1 kOhm in series from UNO TX, then 2 kOhm from the BBB RX
    node to ground (about 3.3 V at the tap). Fine at 115200 baud.
  * Better: a small bidirectional MOSFET level-shifter board (BSS138 type) or a 74LVC buffer powered from 3.3 V.
  * BBB TX -> UNO RX can go direct (3.3 V is above the UNO's logic-high threshold), but a shifter keeps margin.
* **Ground.** UNO GND and BBB GND (P9_1/P9_2) must be common, or serial is unreliable and a floating ground can
  push current through the signal pins.
* **Series resistor and power order.** Keep at least 1 kOhm in series on every signal line between boards so a
  powered UNO cannot push current into an unpowered BBB pin. Power both from the same switched supply so
  they come up and go down together.
* **Never** connect a 12 V vehicle signal to a BBB or UNO pin directly.

## Vehicle-side input protection (UNO module)

* Supply: fuse on the 12 V feed close to the tap (size to the load, typically 1-2 A), reverse-polarity
  protection (series Schottky or P-MOSFET), a TVS diode rated for 12 V automotive systems, and a buck regulator
  rated for load dump (input >= 36-40 V) to make 5 V.
* Indicator/warning lines (12 V): optocoupler per line, input resistor sized for the lamp-line current,
  UNO pin with pull-up. Gives isolation and protects from transients.
* Fuel/coolant senders (resistive, to chassis ground): ADC input from a divider against a known 5 V reference
  resistor, with series resistor (about 1 kOhm) + small capacitor (about 100 nF) at the ADC pin and a clamp to 5 V.
  The divider should keep the ADC between about 6 and 1017 counts across the sender range (outside that the hub flags
  a sender fault).
* Speed (VSS) / tach pulses: condition to 5 V logic with an optocoupler or comparator; UNO external interrupts
  exist only on D2/D3, which currently carry the indicators (see `docs/serial_vehicle_input_protocol.md`).

## CAN bring-up (DCAN0, receive-only first)

The hub's SocketCAN source only reads frames (`SocketCanSignalSource`); it never transmits. Keep it that way
until the signal dictionary is verified.

1. **Hardware.** 3.3 V CAN transceiver (e.g. SN65HVD230 class) between DCAN0 (P9_19 RX, P9_20 TX) and the bus.
   Do **not** use a 5 V transceiver on the 3.3 V pins without level shifting. Common ground. Check nothing else uses I2C2.
2. **Bus access.** At the OBD-II port, high-speed CAN is normally pin 6 (CAN-H) and 14 (CAN-L); some vehicles
   differ. Confirm for the vehicle. The bus is already terminated at its two ends; do not add 120 Ohm on an in-car
   tap. Add termination only on a two-node bench setup.
3. **Overlay.** Enable the `BB-CAN0` overlay in `/boot/uEnv.txt` and reboot (board change, needs approval).
4. **Bring up listen-only first** (cannot disturb the car):
   `sudo ip link set can0 type can bitrate 500000 listen-only on && sudo ip link set can0 up`
   (500 kbit/s is typical; confirm the vehicle's rate).
5. **Capture:** `candump -L can0 > candump.log` (package `can-utils`) with known actions (ignition, brake, indicators, wheel spin).
6. **Dictionary:** feed the capture through `tools/can_reverse_workbench` to produce `can_signals.json`
   (`tools/schema/can_signals_v1.md`); validate by replay (`CAN_SIGNAL_DICTIONARY` + `CAN_RAW_LOG`) before live use.
7. **Live:** `CAN_LIVE_INTERFACE=can0`, `CAN_SIGNAL_DICTIONARY=/home/debian/can_signals.json`,
   `CAN_STALE_MS=1000`; hub restart is a deploy step. Without a dictionary live CAN decodes nothing.
8. **Both builds side by side:** inputs (UART4 + UNO) and CAN are independent overlays that can coexist.
   When both feed the same signal, CAN overlay is applied first and the serial overlay merges after it,
   so for any key the serial line provides, the serial value overwrites the CAN value; decide per signal which source is authoritative before enabling both.
9. **Test without hardware:** `vcan0` (`sudo modprobe vcan; sudo ip link add vcan0 type vcan; sudo ip link set vcan0 up`)
   with `cansend`/`canplayer` exercises the live path on a laptop. `tests/test_can_prep.py` does this automatically when a `vcan0`
   already exists (skipped otherwise) and always runs the same checks through a pure-Python fake CAN socket
   (`tools/bbb_hub/fake_can.py`). Parts and wiring list: `docs/can_bus_parts_and_wiring.md`.
