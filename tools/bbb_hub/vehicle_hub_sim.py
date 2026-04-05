from __future__ import annotations

import asyncio
import contextlib
import json
import math
import os
import time
from dataclasses import dataclass
from typing import Optional

import websockets


WS_HOST = os.getenv("BBB_HUB_HOST", "0.0.0.0")
WS_PORT = int(os.getenv("BBB_HUB_PORT", "8765"))
HTTP_HOST = os.getenv("PHONE_GPS_HTTP_HOST", "0.0.0.0")
HTTP_PORT = int(os.getenv("PHONE_GPS_HTTP_PORT", "8787"))
PHONE_GPS_TOKEN = os.getenv("PHONE_GPS_TOKEN", "")
PHONE_GPS_TTL_SEC = float(os.getenv("PHONE_GPS_TTL_SEC", "3.0"))
GPS_SOURCE_POLICY = os.getenv("GPS_SOURCE_POLICY", "hardware_first").strip().lower()
SIM_DISABLE_GPS = os.getenv("SIM_DISABLE_GPS", "0") == "1"

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


def _json_response(status_code: int, payload: dict) -> bytes:
    reason = {
        200: "OK",
        201: "Created",
        400: "Bad Request",
        401: "Unauthorized",
        404: "Not Found",
        405: "Method Not Allowed",
        413: "Payload Too Large",
    }.get(status_code, "OK")
    body = json.dumps(payload).encode("utf-8")
    headers = [
        f"HTTP/1.1 {status_code} {reason}",
        "Content-Type: application/json; charset=utf-8",
        f"Content-Length: {len(body)}",
        "Access-Control-Allow-Origin: *",
        "Access-Control-Allow-Headers: Content-Type, Authorization, X-Phone-Gps-Token",
        "Access-Control-Allow-Methods: POST, OPTIONS",
        "Connection: close",
        "",
        "",
    ]
    return ("\r\n".join(headers)).encode("utf-8") + body


def _parse_bearer(value: str) -> str:
    if not value:
        return ""
    parts = value.strip().split(" ", 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return ""


def _normalized_number(data: dict, *keys: str, default: float = 0.0) -> float:
    for key in keys:
        if key in data:
            try:
                return float(data[key])
            except (TypeError, ValueError):
                continue
    return default


@dataclass
class PhoneGpsSample:
    lat: float
    lng: float
    bearing: float
    speed_kph: float
    accuracy_m: float
    timestamp_ms: int
    fix_valid: bool
    heading_reliable: bool
    satellites: int
    source: str
    received_monotonic: float


class PhoneGpsStore:
    def __init__(self) -> None:
        self._sample: Optional[PhoneGpsSample] = None
        self._lock = asyncio.Lock()

    async def update(self, payload: dict, source: str) -> PhoneGpsSample:
        lat = _normalized_number(payload, "lat", "latitude")
        lng = _normalized_number(payload, "lng", "lon", "longitude")
        if not (-90.0 <= lat <= 90.0 and -180.0 <= lng <= 180.0):
            raise ValueError("lat/lng out of range")

        bearing = _normalized_number(payload, "bearing", "heading", "course", default=0.0) % 360.0
        speed_kph = max(0.0, _normalized_number(payload, "speedKph", "speed_kph", "speed", default=0.0))
        accuracy_m = max(0.0, _normalized_number(payload, "accuracyM", "accuracy", default=0.0))
        timestamp_ms = int(_normalized_number(payload, "timestampMs", "timestamp", "ts", default=time.time() * 1000))
        fix_valid = bool(payload.get("fixValid", payload.get("valid", True)))
        heading_reliable = bool(payload.get("headingReliable", payload.get("heading_reliable", speed_kph > 7.0)))
        satellites = int(_normalized_number(payload, "satellites", "sats", default=0))

        sample = PhoneGpsSample(
            lat=lat,
            lng=lng,
            bearing=bearing,
            speed_kph=speed_kph,
            accuracy_m=accuracy_m,
            timestamp_ms=timestamp_ms,
            fix_valid=fix_valid,
            heading_reliable=heading_reliable,
            satellites=satellites,
            source=source,
            received_monotonic=time.monotonic(),
        )
        async with self._lock:
            self._sample = sample
        return sample

    async def snapshot(self) -> Optional[PhoneGpsSample]:
        async with self._lock:
            return self._sample


class VehicleHub:
    def __init__(self) -> None:
        self.clients: set[websockets.WebSocketServerProtocol] = set()
        self.phone_gps = PhoneGpsStore()
        self._started_at = time.time()

    async def add_client(self, ws: websockets.WebSocketServerProtocol) -> None:
        self.clients.add(ws)
        print(f"[bbb_hub] client connected ({len(self.clients)} total)")

    async def remove_client(self, ws: websockets.WebSocketServerProtocol) -> None:
        self.clients.discard(ws)
        print(f"[bbb_hub] client disconnected ({len(self.clients)} total)")

    def _build_simulated_state(self, t: float) -> dict:
        speed = max(0.0, min(130.0, 65.0 + 65.0 * math.sin(t * 0.22)))
        lat = -27.4698 + 0.0030 * math.sin(t * 0.03)
        lng = 153.0251 + 0.0030 * math.cos(t * 0.03)
        bearing = (t * 18.0) % 360.0

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

        gps_block = {
            "lat": float(lat),
            "lng": float(lng),
            "bearing": float(bearing),
            "accuracyM": 3.0,
            "timestampMs": int(time.time() * 1000),
            "fixValid": True,
            "satellites": 12,
            "speedKph": float(speed),
            "headingReliable": True,
        }
        if SIM_DISABLE_GPS:
            gps_block = {
                "lat": float(lat),
                "lng": float(lng),
                "bearing": float(bearing),
                "accuracyM": 1000.0,
                "timestampMs": int(time.time() * 1000),
                "fixValid": False,
                "satellites": 0,
                "speedKph": 0.0,
                "headingReliable": False,
            }

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
            "gps": gps_block,
            "gpsSource": "sim",
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

    @staticmethod
    def _phone_fresh(sample: PhoneGpsSample) -> bool:
        return (time.monotonic() - sample.received_monotonic) <= PHONE_GPS_TTL_SEC

    def _should_use_phone(self, simulated: dict, sample: Optional[PhoneGpsSample]) -> bool:
        if sample is None:
            return False
        if not self._phone_fresh(sample):
            return False

        if GPS_SOURCE_POLICY == "phone_first":
            return True
        if GPS_SOURCE_POLICY not in {"hardware_first", "phone_first"}:
            return True

        gps = simulated.get("gps", {})
        fix_valid = bool(gps.get("fixValid", False))
        return not fix_valid

    async def next_state(self) -> dict:
        t = time.time() - self._started_at
        state = self._build_simulated_state(t)
        phone_sample = await self.phone_gps.snapshot()

        use_phone = self._should_use_phone(state, phone_sample)
        if use_phone and phone_sample is not None:
            state["gps"] = {
                "lat": phone_sample.lat,
                "lng": phone_sample.lng,
                "bearing": phone_sample.bearing,
                "accuracyM": phone_sample.accuracy_m,
                "timestampMs": phone_sample.timestamp_ms,
                "fixValid": phone_sample.fix_valid,
                "satellites": phone_sample.satellites,
                "speedKph": phone_sample.speed_kph,
                "headingReliable": phone_sample.heading_reliable,
            }
            state["gpsSource"] = "phone_web"

        age_ms = int((time.monotonic() - phone_sample.received_monotonic) * 1000) if phone_sample else -1
        phone_fresh = bool(phone_sample and self._phone_fresh(phone_sample))
        state["_health"]["phoneGpsFresh"] = phone_fresh
        state["_health"]["phoneGpsAgeMs"] = age_ms
        state["_health"]["gpsSourcePolicy"] = GPS_SOURCE_POLICY

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


async def phone_ingest_http(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, hub: VehicleHub) -> None:
    try:
        request_line = await asyncio.wait_for(reader.readline(), timeout=2.0)
        if not request_line:
            return
        parts = request_line.decode("utf-8", errors="replace").strip().split(" ")
        if len(parts) < 3:
            writer.write(_json_response(400, {"ok": False, "error": "invalid request line"}))
            await writer.drain()
            return
        method, path, _ = parts[0], parts[1], parts[2]

        headers = {}
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=2.0)
            if not line or line in {b"\r\n", b"\n"}:
                break
            text = line.decode("utf-8", errors="replace")
            if ":" in text:
                k, v = text.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        if method.upper() == "OPTIONS":
            writer.write(_json_response(200, {"ok": True}))
            await writer.drain()
            return

        if path != "/phone-gps":
            writer.write(_json_response(404, {"ok": False, "error": "not found"}))
            await writer.drain()
            return

        if method.upper() != "POST":
            writer.write(_json_response(405, {"ok": False, "error": "method not allowed"}))
            await writer.drain()
            return

        if PHONE_GPS_TOKEN:
            auth_header = headers.get("authorization", "")
            token_header = headers.get("x-phone-gps-token", "")
            token = _parse_bearer(auth_header) or token_header
            if token != PHONE_GPS_TOKEN:
                writer.write(_json_response(401, {"ok": False, "error": "bad token"}))
                await writer.drain()
                return

        length = int(headers.get("content-length", "0"))
        if length <= 0 or length > 8192:
            writer.write(_json_response(413, {"ok": False, "error": "invalid body length"}))
            await writer.drain()
            return

        body = await asyncio.wait_for(reader.readexactly(length), timeout=2.0)
        payload = json.loads(body.decode("utf-8"))
        sample = await hub.phone_gps.update(payload, source="http")

        writer.write(
            _json_response(
                201,
                {
                    "ok": True,
                    "gpsSource": "phone_web",
                    "lat": sample.lat,
                    "lng": sample.lng,
                    "timestampMs": sample.timestamp_ms,
                    "ttlSec": PHONE_GPS_TTL_SEC,
                },
            )
        )
        await writer.drain()
    except Exception as exc:
        writer.write(_json_response(400, {"ok": False, "error": str(exc)}))
        await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


async def main() -> None:
    if GPS_SOURCE_POLICY not in {"hardware_first", "phone_first"}:
        print(f"[bbb_hub] GPS_SOURCE_POLICY={GPS_SOURCE_POLICY} (custom, treated as phone-first)")

    hub = VehicleHub()
    ws_server = await websockets.serve(lambda ws: ws_handler(ws, hub), WS_HOST, WS_PORT)
    http_server = await asyncio.start_server(
        lambda reader, writer: phone_ingest_http(reader, writer, hub),
        HTTP_HOST,
        HTTP_PORT,
    )

    print(f"[bbb_hub] vehicle_state ws://{WS_HOST}:{WS_PORT}")
    print(f"[bbb_hub] phone GPS ingest http://{HTTP_HOST}:{HTTP_PORT}/phone-gps")
    print(f"[bbb_hub] phone token required: {'yes' if PHONE_GPS_TOKEN else 'no'}")
    print(f"[bbb_hub] gps source policy: {GPS_SOURCE_POLICY} | ttl={PHONE_GPS_TTL_SEC:.1f}s")
    print(f"[bbb_hub] sim gps disabled: {SIM_DISABLE_GPS}")

    broadcaster = asyncio.create_task(hub.broadcast_loop())
    try:
        await asyncio.gather(ws_server.wait_closed(), http_server.serve_forever(), broadcaster)
    finally:
        broadcaster.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await broadcaster


if __name__ == "__main__":
    asyncio.run(main())
