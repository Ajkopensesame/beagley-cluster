#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.input_adapters import (  # noqa: E402
    CAN_EFF_FLAG,
    CAN_FRAME_STRUCT,
    _parse_socketcan_frame,
    merge_vehicle_overlay,
    parse_vehicle_input_line,
)


class BbbInputAdaptersTest(unittest.TestCase):
    def test_serial_json_line_normalizes_vehicle_overlay(self) -> None:
        overlay = parse_vehicle_input_line(
            '{"brake": true, "left": 1, "high_beam": "on", "speed": 42.5, "gear": "D", "transfer_lock": true}'
        )
        self.assertEqual(overlay["speedKph"], 42.5)
        self.assertEqual(overlay["gear"], "D")
        self.assertTrue(overlay["warnings"]["brake"])
        self.assertTrue(overlay["indicators"]["left"])
        self.assertTrue(overlay["indicators"]["high_beam"])
        self.assertTrue(overlay["drivetrain"]["transfer_lock"])

    def test_serial_key_value_line_normalizes_vehicle_overlay(self) -> None:
        overlay = parse_vehicle_input_line(
            "brake=1,oil=0,left=on,rpm=1200,speed=35.5,mode=4wd,locked=true,"
            "maf=41.2,throttle=38,iat=27,map=96"
        )
        self.assertEqual(overlay["rpm"], 1200.0)
        self.assertEqual(overlay["speedKph"], 35.5)
        self.assertEqual(overlay["mafGps"], 41.2)
        self.assertEqual(overlay["throttlePct"], 38.0)
        self.assertEqual(overlay["intakeAirTempC"], 27.0)
        self.assertEqual(overlay["mapKpa"], 96.0)
        self.assertTrue(overlay["warnings"]["brake"])
        self.assertFalse(overlay["warnings"]["oil"])
        self.assertTrue(overlay["indicators"]["left"])
        self.assertEqual(overlay["drivetrain"]["mode"], "4wd")
        self.assertTrue(overlay["drivetrain"]["transfer_lock"])

    def test_merge_vehicle_overlay_preserves_unrelated_state(self) -> None:
        state = {
            "speedKph": 0.0,
            "warnings": {"brake": False, "oil": False},
            "indicators": {"left": False, "right": False},
        }
        merge_vehicle_overlay(state, {"warnings": {"brake": True}, "indicators": {"left": True}})
        self.assertTrue(state["warnings"]["brake"])
        self.assertFalse(state["warnings"]["oil"])
        self.assertTrue(state["indicators"]["left"])
        self.assertFalse(state["indicators"]["right"])

    def test_socketcan_frame_parser_handles_standard_and_extended_ids(self) -> None:
        standard = _parse_socketcan_frame(CAN_FRAME_STRUCT.pack(0x123, 2, b"\xAA\x55" + b"\x00" * 6))
        self.assertIsNotNone(standard)
        assert standard is not None
        self.assertEqual(standard.arbitration_id, 0x123)
        self.assertEqual(standard.data, b"\xAA\x55")

        extended = _parse_socketcan_frame(CAN_FRAME_STRUCT.pack(CAN_EFF_FLAG | 0x18DAF110, 3, b"\x01\x02\x03" + b"\x00" * 5))
        self.assertIsNotNone(extended)
        assert extended is not None
        self.assertEqual(extended.arbitration_id, 0x18DAF110)
        self.assertEqual(extended.data, b"\x01\x02\x03")


if __name__ == "__main__":
    unittest.main()
