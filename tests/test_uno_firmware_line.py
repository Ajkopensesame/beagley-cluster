#!/usr/bin/env python3
"""The UNO sketch (firmware/uno_vehicle_input) must emit what the hub's real parser accepts.

No hardware or compiler involved: the documented sample line goes through
tools.bbb_hub.input_adapters.parse_vehicle_input_line, and the keys the sketch prints (read from
the .ino source) are checked against the documented line and the BENCH_SIM steps are parsed too.
"""
from __future__ import annotations

import os
import re
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.input_adapters import parse_vehicle_input_line  # noqa: E402
from tools.bbb_hub.sensor_calibration import calibration_from_config  # noqa: E402

SKETCH = os.path.join(ROOT, "firmware", "uno_vehicle_input", "uno_vehicle_input.ino")
PROTOCOL_DOC = os.path.join(ROOT, "docs", "serial_vehicle_input_protocol.md")
DOC_KEYS = ["left", "right", "high_beam", "brake", "oil", "charge", "door", "a0", "a1", "speed_hz", "rpm_hz"]


def _documented_sample() -> str:
    text = open(PROTOCOL_DOC, encoding="utf-8").read()
    match = re.search(r"^(left=0,right=0,[^\n]*rpm_hz=[0-9.]+)$", text, re.M)
    assert match, "sample line not found in docs/serial_vehicle_input_protocol.md"
    return match.group(1)


def _sketch() -> str:
    return open(SKETCH, encoding="utf-8").read()


def _sketch_keys() -> list[str]:
    keys = re.findall(r'Serial\.print\(F\("[,]?([a-z0-9_]+)="\)\)', _sketch())
    return keys


def _array(name: str) -> list[float]:
    match = re.search(rf"{name}\[BENCH_STEPS\]\s*=\s*\{{([^}}]*)\}}", _sketch())
    assert match, name
    return [float(v.strip().rstrip("f")) for v in match.group(1).split(",")]


class UnoFirmwareLineTest(unittest.TestCase):
    def test_documented_sample_line_parses_with_raw_values(self) -> None:
        raw: dict = {}
        faults: list = []
        cal = calibration_from_config({"speed": {"kph_per_hz": 0.5}, "rpm": {"rpm_per_hz": 30.0}})
        overlay = parse_vehicle_input_line(_documented_sample(), cal, raw, faults)
        self.assertEqual(raw, {"a0": 512.0, "a1": 430.0, "speed_hz": 48.2, "rpm_hz": 37.5})
        self.assertEqual(faults, [])
        self.assertEqual(overlay["speedKph"], 24.1)  # 48.2 Hz * 0.5
        self.assertEqual(overlay["rpm"], 1125.0)  # 37.5 Hz * 30
        self.assertFalse(overlay["indicators"]["left"])
        self.assertFalse(overlay["warnings"]["brake"])

    def test_sketch_prints_exactly_the_documented_keys_in_order(self) -> None:
        self.assertEqual(_sketch_keys(), DOC_KEYS)
        self.assertIn("Serial.begin(BAUD)", _sketch())
        self.assertIn("BAUD = 115200UL", _sketch())

    def test_every_documented_key_is_consumed_by_the_parser(self) -> None:
        line = ",".join(f"{k}=1" if k not in ("a0", "a1", "speed_hz", "rpm_hz") else f"{k}=100.0" for k in DOC_KEYS)
        raw: dict = {}
        overlay = parse_vehicle_input_line(line, calibration_from_config({}), raw, [])
        self.assertEqual(set(raw), {"a0", "a1", "speed_hz", "rpm_hz"})
        self.assertTrue(overlay["indicators"]["left"] and overlay["indicators"]["right"] and overlay["indicators"]["high_beam"])
        for warning in ("brake", "oil", "charge", "door"):
            self.assertTrue(overlay["warnings"][warning], warning)

    def test_bench_sim_steps_format_and_adc_counts(self) -> None:
        a0, a1 = _array("BENCH_A0"), _array("BENCH_A1")
        speed, rpm = _array("BENCH_SPEED_HZ"), _array("BENCH_RPM_HZ")
        self.assertEqual(a0, [round(v / 5 * 1023) for v in (0, 1.25, 2.5, 3.75, 5)])
        self.assertTrue(all(0 <= v <= 1023 for v in a0 + a1))
        for i in range(len(a0)):
            line = (
                "left=0,right=0,high_beam=0,brake=0,oil=0,charge=0,door=0,"
                f"a0={int(a0[i])},a1={int(a1[i])},speed_hz={speed[i]:.1f},rpm_hz={rpm[i]:.1f}"
            )
            raw: dict = {}
            parse_vehicle_input_line(line, calibration_from_config({}), raw, [])
            self.assertEqual(raw, {"a0": a0[i], "a1": a1[i], "speed_hz": speed[i], "rpm_hz": rpm[i]})


if __name__ == "__main__":
    unittest.main()
