import asyncio
import json
import math
import time
import websockets

HOST = "0.0.0.0"
PORT = 8765
VIC_SEQUENCE = [
    {"warning": "brake"},
    {"warning": "charge"},
    {"warning": "check_engine"},
    {"warning": "at"},
    {"warning": "fuel_low"},
    {"warning": "oil"},
    {"warning": "door"},
    {"drivetrain_mode": "2wd", "transfer_lock": False},
    {"drivetrain_mode": "4wd", "transfer_lock": False},
    {"drivetrain_mode": "4wd", "transfer_lock": True},
]
VIC_HOLD_S = 2.0

async def handler(ws):
    print("[bbb_sim] client connected")

    t0 = time.time()
    try:
        while True:
            t = time.time() - t0

            speed = max(0.0, min(130.0, 65.0 + 65.0 * math.sin(t * 0.22)))
            left  = int((t % 2.0) < 1.0)
            right = int(((t + 1.0) % 2.0) < 1.0)
            high_beam = (t % 7.0) < 0.6
            lat = -27.4698 + 0.0030 * math.sin(t * 0.03)
            lng = 153.0251 + 0.0030 * math.cos(t * 0.03)
            bearing = (t * 18.0) % 360.0
            gear_cycle = ["P", "R", "N", "D", "2", "1"]
            gear = gear_cycle[int(t / 5.0) % len(gear_cycle)]
            overdrive = gear == "D" and speed > 45.0 and ((t % 8.0) < 4.0)
            rpm_phase = 0.5 + 0.5 * math.sin(t * 0.62 - 1.0)
            rpm = 850.0 + (rpm_phase ** 1.18) * 6650.0 + 180.0 * math.sin(t * 2.4)
            rpm = max(0.0, min(7800.0, rpm))
            vic_state = VIC_SEQUENCE[int(t / VIC_HOLD_S) % len(VIC_SEQUENCE)]
            warning_key = vic_state.get("warning")
            fuel_phase = 0.5 + 0.5 * math.sin(t * 0.12 + math.pi / 2.0)
            fuel_pct = max(0.0, min(100.0, fuel_phase * 100.0))
            coolant_phase = 0.5 + 0.5 * math.sin(t * 0.10 - math.pi / 2.0)
            coolant_c = 40.0 + coolant_phase * 80.0
            drivetrain_mode = vic_state.get("drivetrain_mode", "2wd")
            transfer_lock = bool(vic_state.get("transfer_lock", False))

            msg = {
                "type": "vehicle_state",

                "speedKph": float(speed),
                "rpm": int(rpm),
                "fuelPct": fuel_pct,
                "coolantC": float(coolant_c),
                "gear": gear,
                "overdrive": bool(overdrive),
                "drivetrain": {
                    "mode": drivetrain_mode,
                    "transfer_lock": bool(transfer_lock),
                },
                "gps": {
                    "lat": float(lat),
                    "lng": float(lng),
                    "bearing": float(bearing),
                },

                "indicators": {
                    "left": bool(left),
                    "right": bool(right),
                    "high_beam": bool(high_beam),
                },

                "warnings": {
                    "brake": warning_key == "brake",
                    "oil": warning_key == "oil",
                    "charge": warning_key == "charge",
                    "door": warning_key == "door",
                    "check_engine": warning_key == "check_engine",
                    "at": warning_key == "at",
                    "fuel_low": warning_key == "fuel_low",
                },

                "_health": {
                    "stale": False,
                },
            }

            await ws.send(json.dumps(msg))
            await asyncio.sleep(0.1)

    except websockets.exceptions.ConnectionClosed as e:
        print(f"[bbb_sim] client disconnected ({e.code} {e.reason})")
    except Exception as e:
        print(f"[bbb_sim] handler error: {e!r}")

async def main():
    async with websockets.serve(handler, HOST, PORT):
        print(f"[bbb_sim] ws://{HOST}:{PORT}")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
