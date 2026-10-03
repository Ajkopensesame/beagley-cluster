#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.input_adapters import parse_vehicle_input_line  # noqa: E402
from tools.bbb_hub.sensor_calibration import (  # noqa: E402
    calibration_from_config,
    load_sensor_calibration,
    piecewise_linear,
)

CAL = {
    "fuel": {"points": [[100, 0], [500, 50], [900, 100]], "low_pct": 10, "smoothing_alpha": 1.0},
    "coolant": {"points": [[900, 20], [500, 60], [200, 120]], "smoothing_alpha": 1.0},
    "speed": {"kph_per_hz": 0.5, "max": 300},
    "rpm": {"rpm_per_hz": 30.0, "max": 9000},
}


def parse(line, cal=None):
    raw, faults = {}, []
    overlay = parse_vehicle_input_line(line, calibration=cal, raw_out=raw, faults_out=faults)
    return overlay, raw, faults


class SensorCalibrationTest(unittest.TestCase):
    def test_piecewise_interpolates_and_clamps(self) -> None:
        pts = [(0.0, 0.0), (10.0, 100.0)]
        self.assertEqual(piecewise_linear(5, pts), 50.0)
        self.assertEqual(piecewise_linear(-5, pts), 0.0)
        self.assertEqual(piecewise_linear(50, pts), 100.0)

    def test_no_calibration_leaves_existing_behavior(self) -> None:
        overlay, raw, faults = parse("a0=500,a1=500,speed=35.5,left=1")
        self.assertEqual(overlay["speedKph"], 35.5)
        self.assertNotIn("fuelPct", overlay)
        self.assertEqual(raw, {})
        self.assertEqual(faults, [])

    def test_kv_line_converts_raw_senders_and_pulses(self) -> None:
        cal = calibration_from_config(CAL)
        overlay, raw, faults = parse("a0=500,a1=500,speed_hz=100,rpm_hz=50,left=1", cal)
        self.assertEqual(overlay["fuelPct"], 50.0)
        self.assertEqual(overlay["coolantC"], 60.0)
        self.assertEqual(overlay["speedKph"], 50.0)
        self.assertEqual(overlay["rpm"], 1500.0)
        self.assertTrue(overlay["indicators"]["left"])
        self.assertEqual(raw["a0"], 500.0)
        self.assertEqual(faults, [])

    def test_json_line_converts(self) -> None:
        cal = calibration_from_config(CAL)
        overlay, _, _ = parse('{"fuel_raw": 900, "coolant_raw": 900, "speed_hz": 10}', cal)
        self.assertEqual(overlay["fuelPct"], 100.0)
        self.assertEqual(overlay["coolantC"], 20.0)
        self.assertEqual(overlay["speedKph"], 5.0)

    def test_preconverted_values_win(self) -> None:
        cal = calibration_from_config(CAL)
        overlay, _, _ = parse("a0=500,fuel_pct=77,speed=12,speed_hz=100", cal)
        self.assertEqual(overlay["fuelPct"], 77.0)
        self.assertEqual(overlay["speedKph"], 12.0)

    def test_fuel_low_derived(self) -> None:
        cal = calibration_from_config(CAL)
        overlay, _, _ = parse("a0=120", cal)
        self.assertAlmostEqual(overlay["fuelPct"], 2.5)
        self.assertTrue(overlay["warnings"]["fuel_low"])
        overlay, _, _ = parse("a0=500", cal)
        self.assertNotIn("fuel_low", overlay.get("warnings", {}))

    def test_sender_fault_produces_no_value_and_reports(self) -> None:
        cal = calibration_from_config(CAL)
        overlay, raw, faults = parse("a0=1023,a1=2", cal)
        self.assertNotIn("fuelPct", overlay)
        self.assertNotIn("coolantC", overlay)
        self.assertEqual(sorted(faults), ["coolant_sender_fault", "fuel_sender_fault"])
        self.assertEqual(raw["a0"], 1023.0)

    def test_uncalibrated_signal_reports_no_fault(self) -> None:
        cal = calibration_from_config({"coolant": CAL["coolant"]})
        overlay, _, faults = parse("a0=1023,a1=500", cal)
        self.assertNotIn("fuelPct", overlay)
        self.assertEqual(faults, [])
        self.assertEqual(overlay["coolantC"], 60.0)

    def test_pulse_caps_and_negative_ignored(self) -> None:
        cal = calibration_from_config(CAL)
        overlay, _, _ = parse("speed_hz=100000,rpm_hz=100000", cal)
        self.assertEqual(overlay["speedKph"], 300.0)
        self.assertEqual(overlay["rpm"], 9000.0)
        overlay, _, _ = parse("speed_hz=-5", cal)
        self.assertNotIn("speedKph", overlay)

    def test_smoothing_applies_between_lines(self) -> None:
        cfg = json.loads(json.dumps(CAL))
        cfg["fuel"]["smoothing_alpha"] = 0.5
        cal = calibration_from_config(cfg)
        parse("a0=500", cal)
        overlay, _, _ = parse("a0=900", cal)  # smooth -> 700 -> 75%
        self.assertEqual(overlay["fuelPct"], 75.0)

    def test_bad_or_missing_calibration_file_is_safe(self) -> None:
        cal, err = load_sensor_calibration("/nonexistent/cal.json")
        self.assertFalse(cal.enabled)
        self.assertIn("not found", err)
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write("{nope")
        cal, err = load_sensor_calibration(f.name)
        self.assertFalse(cal.enabled)
        self.assertIn("unusable", err)

    def test_shipped_default_is_uncalibrated(self) -> None:
        cal, err = load_sensor_calibration()
        self.assertIsNone(err)
        self.assertFalse(cal.enabled)


if __name__ == "__main__":
    unittest.main()
