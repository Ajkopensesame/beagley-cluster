#!/usr/bin/env python3
"""End-to-end: real vehicle_hub_prod.py + pty GPS emitting RMC/GGA with a date, and gps_clock.py reading the
hub's WebSocket. The real system clock is never set: the helper runs with --dry-run (subprocess) or with an
injected recording setter (in-process)."""
from __future__ import annotations

import asyncio
import os
import re
import subprocess
import sys
import time
import unittest
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUB_DIR = os.path.join(ROOT, "tools", "bbb_hub")
sys.path.insert(0, HUB_DIR)

from test_hub_integration import _HubHarness, _nmea, pty, websockets  # noqa: E402

if websockets is not None:
    import gps_clock  # noqa: E402

CLOCK_SCRIPT = os.path.join(HUB_DIR, "gps_clock.py")


def _gps_lines(utc: datetime, *, rmc: bool = True) -> list[bytes]:
    # centisecond resolution (a fix-timestamp truncated to whole seconds would be up to 1 s behind)
    hhmmss = utc.strftime("%H%M%S") + f".{utc.microsecond // 10000:02d}"
    ddmmyy = utc.strftime("%d%m%y")
    lines = [_nmea(f"GPGGA,{hhmmss},2728.188,S,15301.506,E,1,08,0.9,10.0,M,0.0,M,,")]
    if rmc:
        lines.append(_nmea(f"GPRMC,{hhmmss},A,2728.188,S,15301.506,E,000.0,084.4,{ddmmyy},,"))
    return lines


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class GpsClockIntegrationTest(_HubHarness):
    # A fast stale threshold would not matter here; keep the GPS comfortably live while we feed it.
    extra_env = {"BBB_GPS_STALE_MS": "1500"}

    async def _feed_gps(self, offset_s: float, seconds: float, *, rmc: bool = True) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            gps_time = datetime.now(timezone.utc) + timedelta(seconds=offset_s)
            for line in _gps_lines(gps_time, rmc=rmc):
                os.write(self.gps_master, line)
            await asyncio.sleep(0.1)

    async def _run_helper(self, *extra: str, timeout: float = 12.0) -> tuple[int, str]:
        env = dict(os.environ)
        env.update({"GPS_CLOCK_HUB_URL": f"ws://127.0.0.1:{self.port}", "PYTHONUNBUFFERED": "1"})
        env.pop("GPS_CLOCK_DRY_RUN", None)
        proc = await asyncio.create_subprocess_exec(
            sys.executable, CLOCK_SCRIPT, "--once", "--timeout", str(timeout), *extra,
            env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
        )
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout + 10)
        return proc.returncode, out.decode()

    def _run(self, coro) -> None:
        asyncio.run(coro)

    def test_dry_run_reports_offset_vs_box_clock(self) -> None:
        async def scenario() -> None:
            await (await self._connect()).close()  # hub is up
            feeder = asyncio.create_task(self._feed_gps(3600.0, 14.0))
            try:
                rc, out = await self._run_helper("--dry-run")
            finally:
                feeder.cancel()
            self.assertEqual(rc, gps_clock.EXIT_WOULD_STEP, out)
            match = re.search(r"DRY RUN would step clock by ([+-][0-9.]+) s to (\S+)", out)
            self.assertIsNotNone(match, out)
            self.assertAlmostEqual(float(match.group(1)), 3600.0, delta=2.0)
            self.assertNotIn("stepped clock", out)

        self._run(scenario())

    def test_clock_already_correct_exits_zero_without_step(self) -> None:
        async def scenario() -> None:
            await (await self._connect()).close()
            feeder = asyncio.create_task(self._feed_gps(0.0, 14.0))
            try:
                rc, out = await self._run_helper("--dry-run")
            finally:
                feeder.cancel()
            self.assertEqual(rc, gps_clock.EXIT_OK, out)
            self.assertIn("no step", out)
            self.assertNotIn("would step", out)

        self._run(scenario())

    def test_injected_setter_receives_gps_time(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            await ws.close()
            calls: list[float] = []
            lines: list[str] = []
            cfg = gps_clock.Config(hub_url=f"ws://127.0.0.1:{self.port}")
            discipline = gps_clock.ClockDiscipline(cfg, setter=calls.append, emit=lines.append)
            feeder = asyncio.create_task(self._feed_gps(-7200.0, 12.0))
            try:
                rc = await gps_clock.run_once(cfg, 10.0, discipline)
            finally:
                feeder.cancel()
            self.assertEqual(rc, gps_clock.EXIT_OK)
            self.assertEqual(len(calls), 1, lines)
            self.assertAlmostEqual(calls[0], time.time() - 7200.0, delta=2.0)
            self.assertRegex(lines[0], r"^stepped clock by -7200\.\d{3} s to ")

        self._run(scenario())

    def test_gga_only_gps_never_produces_a_step(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            feeder = asyncio.create_task(self._feed_gps(3600.0, 9.0, rmc=False))
            try:
                # The hub sees a fix (GGA) but publishes no RMC UTC.
                frame = await self._wait_for(ws, lambda s: s.get("gps", {}).get("fixValid") is True, timeout=6.0)
                self.assertIs(frame["gps"]["utcValid"], False)
                rc, out = await self._run_helper("--dry-run", timeout=5.0)
            finally:
                feeder.cancel()
                await ws.close()
            self.assertEqual(rc, gps_clock.EXIT_NO_GPS, out)
            self.assertNotIn("step", out.replace("no usable GPS time", ""))

        self._run(scenario())

    def test_hub_unreachable_exits_3_and_never_steps(self) -> None:
        env = dict(os.environ, GPS_CLOCK_HUB_URL="ws://127.0.0.1:9", PYTHONUNBUFFERED="1")
        proc = subprocess.run(
            [sys.executable, CLOCK_SCRIPT, "--once", "--dry-run", "--timeout", "2"],
            env=env, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(proc.returncode, gps_clock.EXIT_ERROR, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
