#!/usr/bin/env python3
"""End-to-end hub test: real vehicle_hub_prod.py process, pty standing in for the UNO,
second pty standing in for the GPS, real WebSocket client.

Covers: serial data reaches the wire, stale source falls back to fail-safe values,
recovery after the source returns, and garbage lines not killing the hub.
Skipped when `websockets` is missing or ptys are unavailable.
"""
from __future__ import annotations

import asyncio
import json
import os
import socket
import subprocess
import sys
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUB_DIR = os.path.join(ROOT, "tools", "bbb_hub")

try:
    import pty
    import websockets
except ImportError:  # pragma: no cover
    websockets = None
    pty = None

STALE_MS = 400


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class HubIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.uno_master, uno_slave = pty.openpty()
        self.gps_master, gps_slave = pty.openpty()
        self.port = _free_port()
        env = dict(os.environ)
        env.update(
            {
                "PYTHONUNBUFFERED": "1",
                "BBB_HUB_HOST": "127.0.0.1",
                "BBB_HUB_PORT": str(self.port),
                "BBB_GPS_DEVICE": os.ttyname(gps_slave),
                "VEHICLE_INPUT_SERIAL_DEVICE": os.ttyname(uno_slave),
                "VEHICLE_INPUT_SERIAL_BAUD": "115200",
                "VEHICLE_INPUT_STALE_MS": str(STALE_MS),
                "VEHICLE_SENSOR_CALIBRATION": "/nonexistent/sensor_calibration.json",
                "BBB_VEHICLE_BENCH_SIM": "0",
            }
        )
        self.proc = subprocess.Popen(
            [sys.executable, os.path.join(HUB_DIR, "vehicle_hub_prod.py")],
            cwd=HUB_DIR,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        self._slaves = (uno_slave, gps_slave)

    def tearDown(self) -> None:
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        if self.proc.stderr:
            self.proc.stderr.close()
        for fd in (self.uno_master, self.gps_master, *self._slaves):
            try:
                os.close(fd)
            except OSError:
                pass

    async def _connect(self):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                err = self.proc.stderr.read().decode(errors="replace") if self.proc.stderr else ""
                self.fail(f"hub exited early ({self.proc.returncode}): {err[-800:]}")
            try:
                return await websockets.connect(f"ws://127.0.0.1:{self.port}")
            except OSError:
                await asyncio.sleep(0.2)
        self.fail("hub never started listening")

    async def _frame(self, ws) -> dict:
        return json.loads(await asyncio.wait_for(ws.recv(), timeout=3))

    async def _wait_for(self, ws, predicate, timeout: float = 5.0) -> dict:
        deadline = time.monotonic() + timeout
        last: dict = {}
        while time.monotonic() < deadline:
            last = await self._frame(ws)
            if predicate(last):
                return last
        self.fail(f"condition not reached; last serial health: {(last.get('_health') or {}).get('serialVehicleInputs')}")

    async def _feed(self, lines: list[bytes], seconds: float) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            for line in lines:
                os.write(self.uno_master, line)
            await asyncio.sleep(0.05)

    def test_serial_stale_failsafe_and_recovery(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            try:
                # 1. Nothing connected yet: fail-safe defaults, flagged stale, no vehicle source.
                first = await self._wait_for(ws, lambda s: "_health" in s)
                self.assertTrue(first["_health"]["stale"])
                self.assertEqual(first["speedKph"], 0.0)
                self.assertEqual(first["_health"]["vehicleSource"], "none")
                self.assertTrue(first["_health"]["serialVehicleInputs"]["enabled"])

                # 2. UNO talking: values flow through and the source is marked live.
                feeder = asyncio.create_task(
                    self._feed([b"speed=35.5,rpm=1200,fuel_pct=60,coolant_c=88,left=1,brake=0\n"], 1.5)
                )
                live = await self._wait_for(
                    ws,
                    lambda s: (s["_health"].get("vehicleSource") == "serial" and not s["_health"]["stale"]),
                )
                self.assertEqual(live["speedKph"], 35.5)
                self.assertEqual(live["rpm"], 1200.0)
                self.assertEqual(live["fuelPct"], 60.0)
                self.assertEqual(live["coolantC"], 88.0)
                self.assertTrue(live["indicators"]["left"])
                self.assertFalse(live["_health"]["serialVehicleInputs"]["stale"])
                await feeder

                # 3. UNO goes silent (unplugged / crashed): back to fail-safe within stale window.
                stale = await self._wait_for(
                    ws,
                    lambda s: s["_health"]["serialVehicleInputs"]["stale"],
                    timeout=STALE_MS / 1000 + 3,
                )
                self.assertEqual(stale["speedKph"], 0.0)
                self.assertEqual(stale["rpm"], 0.0)
                self.assertEqual(stale["_health"]["vehicleSource"], "none")
                self.assertTrue(stale["_health"]["stale"])

                # 4. Garbage must be counted, not fatal; valid data afterwards recovers.
                os.write(self.uno_master, b"%%%garbage\n{not json\n")
                feeder = asyncio.create_task(self._feed([b"speed=50,rpm=2000\n"], 1.2))
                back = await self._wait_for(
                    ws,
                    lambda s: s["_health"].get("vehicleSource") == "serial" and s["speedKph"] == 50.0,
                )
                self.assertGreaterEqual(back["_health"]["serialVehicleInputs"]["parseErrors"], 1)
                await feeder
                self.assertIsNone(self.proc.poll(), "hub must still be running")
            finally:
                await ws.close()

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
