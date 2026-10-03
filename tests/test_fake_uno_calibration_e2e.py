#!/usr/bin/env python3
"""End-to-end calibration with a fake UNO: the real vehicle_hub_prod.py process reads UNO-format lines from a
pty (written by tools/bbb_hub/fake_uno.py's line builder), with a sensor calibration table loaded, and the
assertions are made on the WebSocket frames the display would receive. No hardware, no BBB, no GPS fix.

Covers: raw ADC/pulse Hz -> fuel %, coolant C, km/h, rpm; fuel_low warning; open/shorted sender faults
(no value, fault code reported, recovery); no calibration => no values (the frame keeps its 0.0 defaults and
the health block says so); stale stream => fail-safe; and the fake_uno CLI driving a hub through a pty link.
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUB_DIR = os.path.join(ROOT, "tools", "bbb_hub")
sys.path.insert(0, ROOT)
sys.path.insert(0, HUB_DIR)

from test_hub_integration import STALE_MS, _HubHarness, pty, websockets  # noqa: E402
from test_uno_firmware_line import _array, _documented_sample  # noqa: E402

from tools.bbb_hub import fake_uno  # noqa: E402
from tools.bbb_hub.input_adapters import parse_vehicle_input_line  # noqa: E402
from tools.bbb_hub.sensor_calibration import calibration_from_config, piecewise_linear  # noqa: E402

FAKE_UNO = os.path.join(HUB_DIR, "fake_uno.py")
SHIPPED_CALIBRATION = os.path.join(HUB_DIR, "config", "sensor_calibration.json")

FUEL_POINTS = [[120, 0], [300, 25], [520, 50], [700, 75], [880, 100]]
COOLANT_POINTS = [[900, 20], [500, 60], [250, 95]]
# smoothing_alpha 1.0 = no smoothing, so each line converts exactly (smoothing has its own unit test).
CALIBRATION = {
    "fuel": {"points": FUEL_POINTS, "low_pct": 10, "smoothing_alpha": 1.0},
    "coolant": {"points": COOLANT_POINTS, "smoothing_alpha": 1.0},
    "speed": {"kph_per_hz": 0.5, "max": 300},
    "rpm": {"rpm_per_hz": 30.0, "max": 9000},
}


def _uno(a0: float, a1: float, speed_hz: float = 0.0, rpm_hz: float = 0.0, **lamps: int) -> bytes:
    return (fake_uno.format_line(a0, a1, speed_hz, rpm_hz, lamps) + "\n").encode()


def _serial(frame: dict) -> dict:
    return frame["_health"]["serialVehicleInputs"]


def _write_calibration(config: dict) -> str:
    directory = tempfile.mkdtemp(prefix="fakeunocal")
    path = os.path.join(directory, "cal.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(config, fh)
    return path


class FakeUnoLineTest(unittest.TestCase):
    """The fake emits what the firmware emits (reusing the firmware-line test's helpers)."""

    def test_format_matches_documented_sample_shape_and_parses(self) -> None:
        sample = _documented_sample()
        mine = fake_uno.format_line(512, 430, 48.2, 37.5)
        self.assertEqual(mine, sample)
        raw: dict = {}
        cal = calibration_from_config({"speed": {"kph_per_hz": 0.5}})
        overlay = parse_vehicle_input_line(mine, cal, raw)
        self.assertEqual(raw, {"a0": 512.0, "a1": 430.0, "speed_hz": 48.2, "rpm_hz": 37.5})
        self.assertEqual(overlay["speedKph"], 24.1)

    def test_steps_sweep_is_the_firmware_bench_table(self) -> None:
        for index, step in enumerate(fake_uno.BENCH_STEPS):
            self.assertEqual(step["a0"], _array("BENCH_A0")[index])
            self.assertEqual(step["a1"], _array("BENCH_A1")[index])
            self.assertEqual(step["speed_hz"], _array("BENCH_SPEED_HZ")[index])
            self.assertEqual(step["rpm_hz"], _array("BENCH_RPM_HZ")[index])
        self.assertEqual(fake_uno.sample("steps", 12.0, {}, step_s=5.0), fake_uno.BENCH_STEPS[2])

    def test_ramp_and_fault_sweeps(self) -> None:
        fixed = {"a0": 512.0, "a1": 430.0, "speed_hz": 0.0, "rpm_hz": 0.0}
        lo = fake_uno.sample("ramp", 0.0, fixed, channels=("a0",), period=10.0)
        hi = fake_uno.sample("ramp", 5.0, fixed, channels=("a0",), period=10.0)
        self.assertEqual((lo["a0"], hi["a0"]), (120.0, 880.0))
        self.assertEqual(lo["a1"], 430.0)  # channels not selected stay fixed
        self.assertEqual(fake_uno.sample("fault", 0.0, fixed)["a0"], 1023.0)
        self.assertEqual(fake_uno.sample("fault", 5.0, fixed)["a1"], 0.0)


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class FakeUnoCalibratedHubTest(_HubHarness):
    @classmethod
    def setUpClass(cls) -> None:
        cls.extra_env = {"VEHICLE_SENSOR_CALIBRATION": _write_calibration(CALIBRATION)}

    def _run(self, coro_fn) -> None:
        async def main() -> None:
            ws = await self._connect()
            try:
                await coro_fn(ws)
            finally:
                await ws.close()

        asyncio.run(main())

    async def _live(self, ws, line: bytes, seconds: float = 1.2) -> dict:
        """Feed ``line`` at ~20 Hz and return the first frame in which that line (its a0/a1 raw) is the live one."""
        raw = {k: float(v) for k, v in (kv.split("=") for kv in line.decode().strip().split(","))
               if k in ("a0", "a1", "speed_hz", "rpm_hz")}
        feeder = asyncio.create_task(self._feed([line], seconds))
        try:
            return await self._wait_for(
                ws,
                lambda s: s["_health"].get("vehicleSource") == "serial" and not _serial(s)["stale"]
                and _serial(s)["raw"].get("a0") == raw["a0"] and _serial(s)["raw"].get("a1") == raw["a1"]
                and _serial(s)["raw"].get("speed_hz") == raw["speed_hz"],
            )
        finally:
            await feeder

    def test_raw_adc_and_pulses_become_calibrated_values(self) -> None:
        async def scenario(ws) -> None:
            live = await self._live(ws, _uno(610, 375, 60.0, 40.0))
            self.assertEqual(live["fuelPct"], 62.5)  # 610 on the 520->50 / 700->75 segment
            self.assertEqual(live["coolantC"], 77.5)  # 375 on the 500->60 / 250->95 segment
            self.assertEqual(live["speedKph"], 30.0)  # 60 Hz * 0.5 (no GPS fix: pulse is the source)
            self.assertEqual(live["rpm"], 1200.0)  # 40 Hz * 30
            self.assertFalse(live["warnings"]["fuel_low"])
            serial = _serial(live)
            self.assertEqual(serial["calibration"], {"fuel": True, "coolant": True, "speed": True, "rpm": True})
            self.assertEqual(serial["raw"], {"a0": 610.0, "a1": 375.0, "speed_hz": 60.0, "rpm_hz": 40.0})
            self.assertEqual(serial["sensorFaults"], [])
            self.assertEqual((serial["parseErrors"], serial["stale"], serial["source"]), (0, False, "serial"))
            self.assertGreater(serial["frames"], 0)
            self.assertEqual(live["_health"]["speedSource"]["active"], "pulse")

        self._run(scenario)

    def test_table_end_points_clamp_and_low_fuel_warns(self) -> None:
        async def scenario(ws) -> None:
            low = await self._live(ws, _uno(150, 900))  # fuel 150 -> 4.2 %, coolant at the hot-table end
            self.assertEqual(low["fuelPct"], 4.2)
            self.assertTrue(low["warnings"]["fuel_low"])
            self.assertEqual(low["coolantC"], 20.0)
            full = await self._live(ws, _uno(1017, 6))  # just inside the sender-fault limits: clamped, not a fault
            self.assertEqual(full["fuelPct"], 100.0)
            self.assertEqual(full["coolantC"], 95.0)
            self.assertEqual(_serial(full)["sensorFaults"], [])
            self.assertFalse(full["warnings"]["fuel_low"])

        self._run(scenario)

    def test_open_and_shorted_senders_give_no_value_and_a_fault_code(self) -> None:
        async def scenario(ws) -> None:
            await self._live(ws, _uno(520, 500))  # healthy first, so a stuck old value would show
            both = await self._live(ws, _uno(1018, 5, 20.0))  # fuel open (>=1018), coolant shorted (<=5)
            serial = _serial(both)
            self.assertEqual(sorted(serial["sensorFaults"]), ["coolant_sender_fault", "fuel_sender_fault"])
            self.assertEqual(serial["raw"]["a0"], 1018.0)
            self.assertEqual(both["fuelPct"], 0.0)  # hub default, not a stale 50 and not a fake reading
            self.assertEqual(both["coolantC"], 0.0)
            self.assertFalse(both["warnings"]["fuel_low"])  # no value, so no low-fuel claim
            self.assertEqual(both["speedKph"], 10.0)  # the healthy pulse path is unaffected
            ok = await self._live(ws, _uno(520, 500))
            self.assertEqual(_serial(ok)["sensorFaults"], [])
            self.assertEqual((ok["fuelPct"], ok["coolantC"]), (50.0, 60.0))

        self._run(scenario)

    def test_stream_stopping_fails_safe_then_recovers(self) -> None:
        async def scenario(ws) -> None:
            live = await self._live(ws, _uno(520, 500, 60.0, 40.0))
            self.assertEqual((live["fuelPct"], live["coolantC"]), (50.0, 60.0))
            stale = await self._wait_for(ws, lambda s: _serial(s)["stale"], timeout=STALE_MS / 1000 + 3)
            for key in ("fuelPct", "coolantC", "speedKph", "rpm"):
                self.assertEqual(stale[key], 0.0, key)  # never a frozen last value
            self.assertEqual(stale["_health"]["vehicleSource"], "none")
            self.assertTrue(stale["_health"]["stale"])
            self.assertGreater(_serial(stale)["ageMs"], STALE_MS)
            back = await self._live(ws, _uno(700, 250, 20.0, 10.0))
            self.assertEqual((back["fuelPct"], back["coolantC"], back["speedKph"], back["rpm"]), (75.0, 95.0, 10.0, 300.0))

        self._run(scenario)


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class FakeUnoNoCalibrationTest(_HubHarness):
    """The shipped calibration is empty: raw values are visible in health but nothing is converted."""

    extra_env = {"VEHICLE_SENSOR_CALIBRATION": SHIPPED_CALIBRATION}

    def test_no_calibration_means_no_values_not_zeros_passed_off_as_readings(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            try:
                feeder = asyncio.create_task(self._feed([_uno(520, 500, 60.0, 40.0, left=1)], 1.2))
                live = await self._wait_for(
                    ws, lambda s: s["_health"].get("vehicleSource") == "serial" and not _serial(s)["stale"]
                )
                await feeder
                serial = _serial(live)
                self.assertEqual(serial["calibration"], {"fuel": False, "coolant": False, "speed": False, "rpm": False})
                self.assertEqual(serial["raw"], {"a0": 520.0, "a1": 500.0, "speed_hz": 60.0, "rpm_hz": 40.0})
                for key in ("fuelPct", "coolantC", "speedKph", "rpm"):
                    self.assertEqual(live[key], 0.0, key)  # hub defaults: no conversion happened
                self.assertEqual(serial["sensorFaults"], [])  # no table, so nothing to call a fault
                self.assertTrue(live["indicators"]["left"])  # lamps still flow
                self.assertEqual(live["_health"]["speedSource"]["reason"], "no_valid_source")
                # an open sender with no table is not reported as a fault either
                feeder = asyncio.create_task(self._feed([_uno(1023, 0)], 0.8))
                open_ = await self._wait_for(ws, lambda s: _serial(s)["raw"].get("a0") == 1023.0)
                await feeder
                self.assertEqual(_serial(open_)["sensorFaults"], [])
                self.assertEqual((open_["fuelPct"], open_["coolantC"]), (0.0, 0.0))
            finally:
                await ws.close()

        asyncio.run(scenario())


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class FakeUnoPartialCalibrationTest(_HubHarness):
    """Only fuel is calibrated: coolant/speed/rpm stay unproduced."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.extra_env = {"VEHICLE_SENSOR_CALIBRATION": _write_calibration({"fuel": {"points": FUEL_POINTS}})}

    def test_uncalibrated_signals_stay_absent(self) -> None:
        async def scenario() -> None:
            ws = await self._connect()
            try:
                feeder = asyncio.create_task(self._feed([_uno(520, 500, 60.0, 40.0)], 1.2))
                live = await self._wait_for(
                    ws, lambda s: s["_health"].get("vehicleSource") == "serial" and not _serial(s)["stale"]
                )
                await feeder
                self.assertEqual(_serial(live)["calibration"], {"fuel": True, "coolant": False, "speed": False, "rpm": False})
                self.assertEqual(live["fuelPct"], 50.0)
                self.assertEqual((live["coolantC"], live["speedKph"], live["rpm"]), (0.0, 0.0, 0.0))
            finally:
                await ws.close()

        asyncio.run(scenario())


@unittest.skipIf(websockets is None or pty is None, "needs websockets and pty")
class FakeUnoCliTest(_HubHarness):
    """tools/bbb_hub/fake_uno.py as a subprocess owning the pty; the hub opens the symlink like a real /dev/ttyS4."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._cal = _write_calibration(CALIBRATION)

    def setUp(self) -> None:
        self._link_dir = tempfile.mkdtemp(prefix="fakeunolink")
        self.link = os.path.join(self._link_dir, "uno")
        self.uno = subprocess.Popen(
            [sys.executable, FAKE_UNO, "--link", self.link, "--sweep", "ramp", "--channels", "a0,a1",
             "--range", "a0=200:800", "--range", "a1=300:850", "--period", "4", "--rate", "20", "--stop-after", "5"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 5
        while not os.path.islink(self.link) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(os.path.islink(self.link), "fake_uno did not create its pty link")
        self.extra_env = {"VEHICLE_SENSOR_CALIBRATION": self._cal, "VEHICLE_INPUT_SERIAL_DEVICE": self.link}
        super().setUp()

    def tearDown(self) -> None:
        super().tearDown()
        self.uno.terminate()
        try:
            self.uno.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.uno.kill()
        if self.uno.stderr:
            self.uno.stderr.close()

    def test_cli_ramp_drives_calibrated_values_then_stop_after_goes_stale(self) -> None:
        fuel_pts = [(float(x), float(y)) for x, y in FUEL_POINTS]
        coolant_pts = [(float(x), float(y)) for x, y in COOLANT_POINTS]

        async def scenario() -> None:
            ws = await self._connect()
            try:
                await self._wait_for(ws, lambda s: s["_health"].get("vehicleSource") == "serial", timeout=8)
                fuels: list[float] = []
                deadline = time.monotonic() + 4.0
                while time.monotonic() < deadline:
                    frame = await self._frame(ws)
                    serial = _serial(frame)
                    if serial["stale"] or "a0" not in serial["raw"]:
                        continue
                    # Whatever the sweep is doing, the frame must equal the calibration applied to its own raw counts.
                    self.assertEqual(frame["fuelPct"], round(max(0.0, min(100.0, piecewise_linear(serial["raw"]["a0"], fuel_pts))), 1))
                    self.assertEqual(frame["coolantC"], round(piecewise_linear(serial["raw"]["a1"], coolant_pts), 1))
                    fuels.append(frame["fuelPct"])
                self.assertGreater(len(fuels), 20)
                self.assertGreater(max(fuels) - min(fuels), 25.0)  # the sweep actually moved the gauge
                # --stop-after 5: the fake goes silent (pty stays open, like a hung UNO) and the hub fails safe.
                stale = await self._wait_for(ws, lambda s: _serial(s)["stale"], timeout=8)
                self.assertEqual((stale["fuelPct"], stale["coolantC"]), (0.0, 0.0))
                self.assertEqual(stale["_health"]["vehicleSource"], "none")
            finally:
                await ws.close()

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
