from __future__ import annotations

import asyncio
import contextlib
import json
import math
import os
import time

import websockets

from gps_nmea import NmeaSerialGpsSource, build_hardware_gps_payload


WS_HOST = os.getenv("BBB_HUB_HOST", "0.0.0.0")
WS_PORT = int(os.getenv("BBB_HUB_PORT", "8765"))
GPS_DEVICE = os.getenv("BBB_GPS_DEVICE", "/dev/ttyS4")
GPS_BAUD = int(os.getenv("BBB_GPS_BAUD", "9600"))
GPS_READ_TIMEOUT_MS = int(os.getenv("BBB_GPS_READ_TIMEOUT_MS", "200"))
GPS_STALE_MS = int(os.getenv("BBB_GPS_STALE_MS", "2000"))
GPS_MIN_HEADING_SPEED_KPH = float(os.getenv("BBB_GPS_MIN_HEADING_SPEED_KPH", "7.0"))
GPS_SOURCE_POLICY = os.getenv("GPS_SOURCE_POLICY", "hardware_only").strip().lower()

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
FRAME_PERIOD_SEC = 0.1


class VehicleHub:
    def __init__(self) -> None:
        self.clients: set[websockets.WebSocketServerProtocol] = set()
        self._started_at = time.time()
        self._gps = NmeaSerialGpsSource(
            device=GPS_DEVICE,
            baud=GPS_BAUD,
            read_timeout_ms=GPS_READ_TIMEOUT_MS,
            stale_ms=GPS_STALE_MS,
            min_heading_speed_kph=GPS_MIN_HEADING_SPEED_KPH,
        )

    async def add_client(self, ws: websockets.WebSocketServerProtocol) -> None:
        self.clients.add(ws)
        print(f"[bbb_hub] client connected ({len(self.clients)} total)")

    async def remove_client(self, ws: websockets.WebSocketServerProtocol) -> None:
        self.clients.discard(ws)
        print(f"[bbb_hub] client disconnected ({len(self.clients)} total)")

    async def gps_loop(self) -> None:
        await self._gps.run()

    def _build_base_state(self, t: float) -> dict:
        speed = max(0.0, min(130.0, 65.0 + 65.0 * math.sin(t * 0.22)))
        left = (t % 2.0) < 1.0
        right = ((t + 1.0) % 2.0) < 1.0
        high_beam = (t % 6.0) < 0.5
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

        return {
            "type": "vehicle_state",
            "version": 1,
            "speedKph": float(speed),
            "rpm": float(rpm),
            "fuelPct": fuel_pct,
            "coolantC": float(coolant_c),
            "gear": gear,
            "overdrive": bool(overdrive),
            "drivetrain": {
                "mode": drivetrain_mode,
                "transfer_lock": bool(transfer_lock),
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

    async def next_state(self) -> dict:
        t = time.time() - self._started_at
        state = self._build_base_state(t)
        sample, health = self._gps.snapshot()
        state["gps"] = build_hardware_gps_payload(sample, stale=health.stale)
        state["gpsSource"] = "hardware"
        state["_health"]["gpsSourcePolicy"] = "hardware_only"
        state["_health"]["gpsStale"] = health.stale
        state["_health"]["gpsSerialOk"] = health.serial_ok
        state["_health"]["gpsAgeMs"] = health.age_ms
        state["_health"]["gpsParseErrors"] = health.parse_errors
        state["_health"]["gpsDevice"] = health.device
        if health.last_error:
            state["_health"]["gpsLastError"] = health.last_error
        return state

    async def broadcast_loop(self) -> None:
        while True:
            if self.clients:
                frame = json.dumps(await self.next_state())
                disconnected = []
                for ws in self.clients:
                    try:
                        await ws.send(frame)
                    except Exception:
                        disconnected.append(ws)
                for ws in disconnected:
                    await self.remove_client(ws)
            await asyncio.sleep(FRAME_PERIOD_SEC)


async def ws_handler(ws: websockets.WebSocketServerProtocol, hub: VehicleHub) -> None:
    await hub.add_client(ws)
    try:
        await ws.wait_closed()
    finally:
        await hub.remove_client(ws)


async def main() -> None:
    if GPS_SOURCE_POLICY != "hardware_only":
        print(f"[bbb_hub] forcing GPS_SOURCE_POLICY=hardware_only (got {GPS_SOURCE_POLICY})")

    hub = VehicleHub()
    ws_server = await websockets.serve(lambda ws: ws_handler(ws, hub), WS_HOST, WS_PORT)

    print(f"[bbb_hub] vehicle_state ws://{WS_HOST}:{WS_PORT}")
    print(f"[bbb_hub] gps source policy: hardware_only")
    print(f"[bbb_hub] GPS device: {GPS_DEVICE} @ {GPS_BAUD}")
    print(f"[bbb_hub] GPS read timeout: {GPS_READ_TIMEOUT_MS} ms | stale: {GPS_STALE_MS} ms")

    gps_task = asyncio.create_task(hub.gps_loop())
    broadcaster = asyncio.create_task(hub.broadcast_loop())
    try:
        await asyncio.gather(ws_server.wait_closed(), broadcaster, gps_task)
    finally:
        broadcaster.cancel()
        gps_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await broadcaster
        with contextlib.suppress(asyncio.CancelledError):
            await gps_task


if __name__ == "__main__":
    asyncio.run(main())
