#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.can_reverse_workbench.obd_anchors import (  # noqa: E402
    build_guided_session_payload_from_obd_log,
    decode_mode01_response,
    decode_supported_pids,
)


class ObdAnchorsTest(unittest.TestCase):
    def test_decodes_rpm_single_frame_response(self) -> None:
        result = decode_mode01_response("04 41 0C 1A F8 00 00 00", timestamp=12.5)

        self.assertEqual(result.pid, 0x0C)
        self.assertEqual(result.timestamp, 12.5)
        self.assertEqual(result.values, {"rpm": 1726.0})

    def test_decodes_common_standard_pids(self) -> None:
        self.assertEqual(decode_mode01_response("41 0D 58").values["speedKph"], 88.0)
        self.assertAlmostEqual(decode_mode01_response("41 10 01 2C").values["mafGps"], 3.0)
        self.assertAlmostEqual(decode_mode01_response("41 11 80").values["throttlePct"], 50.196, places=3)
        self.assertEqual(decode_mode01_response("41 0F 50").values["intakeAirTempC"], 40.0)

    def test_decodes_supported_pid_bitmask(self) -> None:
        supported = decode_supported_pids(0x00, bytes.fromhex("18 18 00 00"))

        self.assertEqual(supported, [0x04, 0x05, 0x0C, 0x0D])

    def test_builds_guided_session_from_obd_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "obd.jsonl"
            output = [
                {"timestamp": 1.0, "response": "04 41 0C 0F A0 00 00 00"},
                {"timestamp": 1.1, "pid": "0x0D", "data": "2A"},
                {"timestamp": 1.2, "signal": "gpsSpeedKph", "value": 42.1},
                {"timestamp": 1.3, "response": "06 41 00 18 18 00 00 00 00"},
            ]
            path.write_text("\n".join(json.dumps(item) for item in output) + "\n", encoding="utf-8")

            payload = build_guided_session_payload_from_obd_log(
                path,
                vehicle_profile="test make model year engine trim",
            )

        self.assertEqual(payload["vehicleProfile"], "test make model year engine trim")
        self.assertEqual(payload["anchors"]["rpm"], [{"timestamp": 1.0, "value": 1000.0}])
        self.assertEqual(payload["anchors"]["speedKph"], [{"timestamp": 1.1, "value": 42.0}])
        self.assertEqual(payload["anchors"]["gpsSpeedKph"], [{"timestamp": 1.2, "value": 42.1}])
        self.assertEqual(payload["obd"]["supportedPids"], ["0x04", "0x05", "0x0C", "0x0D"])
        self.assertEqual(payload["obd"]["warnings"], [])


if __name__ == "__main__":
    unittest.main()
