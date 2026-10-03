#!/usr/bin/env python3
"""End-to-end hub test: real vehicle_hub_prod.py process, a pty standing in for the UNO,
a second pty standing in for the GPS, and a real WebSocket client.

Covers: serial data reaches the wire, a stale source falls back to fail-safe values,
recovery when the source returns, garbage lines not killing the hub, and the systemd
notify/watchdog heartbeat. Skipped when `websockets` or ptys are unavailable.
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
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


class _HubHarness(unittest.TestCase):
    extra_env: dict = {}

    def setUp(self) -> None:
        self.uno_master, uno_slave = pty.openpty()
        self.gps_master, gps_slave = pty.openpty()
        self._slaves = (uno_slave, gps_slave)
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
        env.update(self.extra_env)
        self.proc = subprocess.Popen(
            [sys.executable, os.path.join(HUB_DIR, "vehicle_hub_prod.py")],
            cwd=HUB_DIR,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )

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


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class HubIntegrationTest(_HubHarness):
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
                    lambda s: s["_health"].get("vehicleSource") == "serial" and not s["_health"]["stale"],
                )
                self.assertEqual(live["speedKph"], 35.5)
                self.assertEqual(live["rpm"], 1200.0)
                self.assertEqual(live["fuelPct"], 60.0)
                self.assertEqual(live["coolantC"], 88.0)
                self.assertTrue(live["indicators"]["left"])
                await feeder

                # 3. UNO goes silent (unplugged / crashed): back to fail-safe within the stale window.
                stale = await self._wait_for(
                    ws,
                    lambda s: s["_health"]["serialVehicleInputs"]["stale"],
                    timeout=STALE_MS / 1000 + 3,
                )
                self.assertEqual(stale["speedKph"], 0.0)
                self.assertEqual(stale["rpm"], 0.0)
                self.assertFalse(stale["indicators"]["left"])
                self.assertEqual(stale["_health"]["vehicleSource"], "none")
                self.assertTrue(stale["_health"]["stale"])

                # 4. Garbage is counted, not fatal; valid data afterwards recovers.
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


    def test_health_check_script(self) -> None:
        script = os.path.join(HUB_DIR, "check_hub_health.py")
        url = f"ws://127.0.0.1:{self.port}"

        async def wait_up() -> None:
            ws = await self._connect()
            await ws.close()

        asyncio.run(wait_up())
        # No UNO data yet: hub is reachable, but a required serial source is stale -> exit 1.
        res = subprocess.run([sys.executable, script, url, "--require-serial"], capture_output=True, text=True, timeout=30)
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn("serial stale", res.stdout)
        # Nothing required: reachable and well-formed -> exit 0.
        res = subprocess.run([sys.executable, script, url], capture_output=True, text=True, timeout=30)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        # Wrong port: exit 2.
        res = subprocess.run([sys.executable, script, f"ws://127.0.0.1:{_free_port()}"], capture_output=True, text=True, timeout=30)
        self.assertEqual(res.returncode, 2, res.stdout + res.stderr)


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class HubWatchdogTest(_HubHarness):
    """The hub speaks the systemd notify protocol: READY=1 once, then WATCHDOG=1 heartbeats."""

    def setUp(self) -> None:
        self._dir = tempfile.mkdtemp(prefix="hubnotify")
        notify_path = os.path.join(self._dir, "notify.sock")
        self.notify_sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.notify_sock.bind(notify_path)
        self.notify_sock.settimeout(10)
        type(self).extra_env = {"NOTIFY_SOCKET": notify_path, "WATCHDOG_USEC": "1000000"}
        super().setUp()

    def tearDown(self) -> None:
        super().tearDown()
        type(self).extra_env = {}
        self.notify_sock.close()
        shutil.rmtree(self._dir, ignore_errors=True)

    def test_ready_then_watchdog_heartbeats(self) -> None:
        got = [self.notify_sock.recv(256).decode() for _ in range(3)]
        self.assertEqual(got[0], "READY=1")
        self.assertEqual(got[1:], ["WATCHDOG=1", "WATCHDOG=1"])


def _nmea(body: str) -> bytes:
    checksum = 0
    for ch in body:
        checksum ^= ord(ch)
    return f"${body}*{checksum:02X}\r\n".encode()


# Live fix: GGA quality 1 / 8 sats / hdop 0.9 plus RMC status A at 20.0 knots = 37.04 km/h -> 37.0.
GPS_FIX_LINES = [
    _nmea("GPGGA,123519,2728.188,S,15301.506,E,1,08,0.9,10.0,M,0.0,M,,"),
    _nmea("GPRMC,123519,A,2728.188,S,15301.506,E,020.0,084.4,230394,,"),
]
# UNO pulse: speed_hz=60 with the bench calibration below (0.5 km/h per Hz) = 30.0 km/h.
UNO_PULSE_LINE = b"a0=512,a1=430,speed_hz=60.0,rpm_hz=40.0\n"
GPS_KPH = 37.0
PULSE_KPH = 30.0


class _SpeedSourceHarness(_HubHarness):
    speed_source = "gps_first"

    @classmethod
    def setUpClass(cls) -> None:
        cls._cal_dir = tempfile.mkdtemp(prefix="hubcal")
        cal = os.path.join(cls._cal_dir, "cal.json")
        with open(cal, "w", encoding="utf-8") as fh:
            json.dump({"speed": {"kph_per_hz": 0.5, "max": 300}}, fh)
        cls.extra_env = {
            "VEHICLE_SENSOR_CALIBRATION": cal,
            "VEHICLE_SPEED_SOURCE": cls.speed_source,
            "BBB_GPS_STALE_MS": "600",
            "VEHICLE_SPEED_GPS_LOST_S": "1.0",
            "VEHICLE_SPEED_GPS_REGAIN_S": "1.0",
        }

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls._cal_dir, ignore_errors=True)

    async def _feed_both(self, uno: bool, gps: bool, seconds: float) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if uno:
                os.write(self.uno_master, UNO_PULSE_LINE)
            if gps:
                for line in GPS_FIX_LINES:
                    os.write(self.gps_master, line)
            await asyncio.sleep(0.05)


def _src(state: dict) -> dict:
    return state["_health"]["speedSource"]


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class HubGpsFirstSpeedTest(_SpeedSourceHarness):
    def test_gps_first_with_pulse_fallback_and_both_stale(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            try:
                # 1. GPS fix + UNO pulse that disagrees: GPS speed wins.
                feeder = asyncio.create_task(self._feed_both(True, True, 2.0))
                live = await self._wait_for(
                    ws, lambda s: s["_health"].get("speedSource", {}).get("active") == "gps" and s["gps"]["fixValid"]
                )
                self.assertEqual(live["speedKph"], GPS_KPH)
                self.assertEqual(_src(live)["policy"], "gps_first")
                self.assertTrue(_src(live)["gpsFix"])
                self.assertEqual(live["_health"]["serialVehicleInputs"]["raw"]["speed_hz"], 60.0)
                await feeder

                # 2. GPS goes silent, UNO keeps sending: GPS speed is held only briefly, then pulse.
                feeder = asyncio.create_task(self._feed_both(True, False, 4.0))
                holding = await self._wait_for(ws, lambda s: _src(s).get("reason") == "gps_lost_holding", timeout=3)
                self.assertEqual(_src(holding)["active"], "gps")
                fallback = await self._wait_for(ws, lambda s: _src(s).get("active") == "pulse", timeout=4)
                self.assertEqual(fallback["speedKph"], PULSE_KPH)
                self.assertFalse(_src(fallback)["gpsFix"])
                self.assertEqual(_src(fallback)["reason"], "gps_lost_pulse_fallback")

                # 3. GPS returns: pulse stays until the fix has been valid for the regain window.
                await feeder
                feeder = asyncio.create_task(self._feed_both(True, True, 3.5))
                waiting = await self._wait_for(ws, lambda s: _src(s).get("reason") == "gps_regain_wait", timeout=3)
                self.assertEqual(waiting["speedKph"], PULSE_KPH)
                regained = await self._wait_for(ws, lambda s: _src(s).get("active") == "gps", timeout=4)
                self.assertEqual(regained["speedKph"], GPS_KPH)
                await feeder

                # 4. Both sources go silent: speed is 0 / source none, nothing frozen.
                none = await self._wait_for(ws, lambda s: _src(s).get("active") == "none", timeout=6)
                self.assertEqual(none["speedKph"], 0.0)
                self.assertIsNone(_src(none)["ageS"])
                self.assertFalse(_src(none)["gpsFix"])
                self.assertTrue(none["_health"]["serialVehicleInputs"]["stale"])
                self.assertIsNone(self.proc.poll(), "hub must still be running")
            finally:
                await ws.close()

        asyncio.run(scenario())


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class HubPulseOnlySpeedTest(_SpeedSourceHarness):
    speed_source = "pulse_only"

    def test_pulse_only_ignores_gps_fix(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            try:
                feeder = asyncio.create_task(self._feed_both(True, True, 1.5))
                live = await self._wait_for(
                    ws, lambda s: _src(s).get("active") == "pulse" and s["gps"]["fixValid"]
                )
                self.assertEqual(live["speedKph"], PULSE_KPH)
                self.assertEqual(_src(live)["policy"], "pulse_only")
                await feeder
                stale = await self._wait_for(ws, lambda s: _src(s).get("active") == "none", timeout=4)
                self.assertEqual(stale["speedKph"], 0.0)
            finally:
                await ws.close()

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
