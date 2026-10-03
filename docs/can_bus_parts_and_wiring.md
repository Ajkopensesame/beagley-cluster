# CAN bus: parts list and wiring (BBB DCAN0, receive-only first)

Status: **planning note. Nothing here is wired, applied or bench-verified.** Items marked **(UNVERIFIED)** come from
general BeagleBone knowledge or datasheet memory, not from this repo or the board: check them before wiring. Fuller
bring-up steps: `docs/bbb_hardware_wiring.md` ("CAN bring-up"). The BBB has no `can0` today (`docs/BOARD_RUNBOOK.md`).

## Parts

| Part | Notes |
|---|---|
| 3.3 V CAN transceiver breakout | **SN65HVD230** (3.3 V, up to 1 Mbit/s) is the usual choice. A 5 V supply with 3.3 V logic I/O also works, e.g. **MCP2562** (VIO pin) or **TJA1051T/3** (VIO pin) **(UNVERIFIED: check the exact part's datasheet)**. |
| Do **not** use | A 5 V-only transceiver (MCP2551, TJA1050, most "MCP2515 + TJA1050" boards) wired straight to BBB pins. BBB I/O is 3.3 V and not 5 V tolerant. |
| OBD-II male plug / breakout | Pigtail or breakout so nothing is cut into the car loom. |
| Wire, fuse | Twisted pair for CAN-H/CAN-L, short run. If anything is powered from the car, a fuse near the tap. |
| Optional | 120 ohm resistor for a **two-node bench** setup only (see termination). |

Many cheap SN65HVD230 boards have a 120 ohm resistor soldered on (or a jumper). **Remove or open it** before connecting
to a car.

## DCAN0 pins on the BBB (P9 header)

| Signal | BBB pin | Transceiver pin | Note |
|---|---|---|---|
| CAN RX (DCAN0_RX) | **P9_19** | RXD (R) | Also I2C2 SCL **(UNVERIFIED mux names; same as `docs/bbb_hardware_wiring.md`)** |
| CAN TX (DCAN0_TX) | **P9_20** | TXD (D) | Also I2C2 SDA |
| 3.3 V | P9_3 or P9_4 | VCC | Only if the transceiver is a 3.3 V part |
| GND | P9_1 or P9_2 | GND | Common ground with the transceiver (and the car's signal ground via OBD-II pin 4/5 if used) |

* Use **DCAN0**. DCAN1 uses P9_24/P9_26, which are UART1 = the **GPS** (`/dev/ttyS1`). (Pin direction for DCAN1 is
  P9_24 = RX, P9_26 = TX **(UNVERIFIED)**; `docs/bbb_hardware_wiring.md` lists it the other way round. It does not matter
  while DCAN1 is unused.)
* DCAN0 shares P9_19/P9_20 with I2C2. Do not enable the I2C2 overlay at the same time, and note that a future DS3231 RTC
  on I2C2 would clash (`docs/bbb_deploy_plan_2026-10-03.md`).
* Confirm on the board before wiring: `config-pin -q P9_19`, `config-pin -q P9_20` and `dmesg | grep -i can` after the
  overlay is loaded. The overlay is expected to set the pin mux itself **(UNVERIFIED)**; if not, `config-pin P9_19 can` /
  `config-pin P9_20 can`.

## OBD-II connector (J1962), CAN on pins 6/14

| Pin | Use |
|---|---|
| 6 | CAN-H (ISO 15765-4 high-speed CAN) |
| 14 | CAN-L |
| 4 / 5 | Chassis ground / signal ground |
| 16 | Battery +12 V (always live). Do not connect it to the BBB or the transceiver. Power the BBB the way it is powered today. |

Some vehicles route OBD-II pins 6/14 through a gateway, or use a different bus on them: confirm for this vehicle.
Typical bitrate is **500 kbit/s**, but it is **UNVERIFIED for this car** (some use 250 kbit/s or 125 kbit/s).

## Termination

* The bus already has 120 ohm at each of its two ends (inside the ECUs). **Do not add a 120 ohm resistor when tapping
  a vehicle bus**, in the car or at the OBD port. Extra termination loads the bus and can cause errors.
* Only a two-device bench setup (BBB + transceiver talking to one other CAN device on a table) needs 120 ohm at each end.
  With a bare cable and one other node: 120 ohm across CAN-H/CAN-L at the far end and at the transceiver.

## Software (when the hardware is ready; these are board changes and need approval)

1. `/boot/uEnv.txt` (back it up first, one overlay at a time): `uboot_overlay_addr7=BB-CAN0-00A0.dtbo` (the file exists in
   `/lib/firmware`; slot number must be free, check the existing `uboot_overlay_addr*` lines; a path form such as
   `/lib/firmware/BB-CAN0-00A0.dtbo` is also seen, **UNVERIFIED which one this image wants**). Reboot.
2. **First capture is listen-only**, so the BBB cannot ACK, transmit or disturb the car:
   `sudo ip link set can0 type can bitrate 500000 listen-only on && sudo ip link set can0 up`
3. `candump -L can0 > candump.log` (package `can-utils`) while doing known actions (ignition on, idle, rev, drive).
   If the log is empty, suspect bitrate, a gateway, or swapped CAN-H/CAN-L before anything else.
4. Build a real `can_signals.json` from the capture: `tools/bbb_hub/config/README.md`.
5. Live: `CAN_LIVE_INTERFACE=can0`, `CAN_SIGNAL_DICTIONARY=...`, restart the hub (deploy step).

## Warnings

* The hub never transmits. A passive listener sees OBD-II **responses** (0x7E8) only while some other tool is polling;
  normal ECU broadcast frames are what the workbench is for. The OBD-II starter dictionary is a plumbing example.
* Never exceed 3.3 V on any BBB pin. Never connect pin 16 (12 V). Do not leave listen-only for normal (ACKing / transmitting)
  mode until the bitrate is proven. Do not probe or transmit on a safety bus (airbag, brakes) and only work on a vehicle you own.
* Test without hardware: `python3 -m pytest tests/test_can_prep.py` (pure-Python fake CAN, plus a real `vcan0` test when one exists).
