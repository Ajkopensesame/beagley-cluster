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

from tools.bbb_hub.fault_recorder import FaultRecorder  # noqa: E402


class FaultRecorderTest(unittest.TestCase):
    def test_writes_fault_event_with_rolling_buffer_and_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(temp_dir, buffer_seconds=5.0, min_interval_seconds=10.0)
            recorder.observe(_state(speed=10.0), wall_time=1000.0, monotonic_time=1.0)
            recorder.observe(_state(speed=20.0), wall_time=1001.0, monotonic_time=2.0)

            health = recorder.observe(
                _fault_state(),
                evidence={"canLiveRecentFrames": [{"canId": "0x101", "data": "0102", "decoded": {"speedKph": 0.0}}]},
                wall_time=1002.0,
                monotonic_time=3.0,
            )

            self.assertIsNone(health["lastError"])
            self.assertEqual(health["writes"], 1)
            event_path = Path(health["lastEventPath"])
            self.assertTrue(event_path.exists())

            event = json.loads(event_path.read_text(encoding="utf-8"))
            self.assertEqual(event["version"], 1)
            self.assertEqual(event["faults"][0]["code"], "source_disagreement")
            self.assertEqual(event["triggerState"]["speedKph"], 0.0)
            self.assertEqual(len(event["rollingBuffer"]["frames"]), 3)
            self.assertEqual(event["evidence"]["canLiveRecentFrames"][0]["canId"], "0x101")

    def test_suppresses_duplicate_fault_fingerprint_inside_interval(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(temp_dir, min_interval_seconds=10.0)
            first = recorder.observe(_fault_state(), wall_time=1000.0, monotonic_time=1.0)
            second = recorder.observe(_fault_state(), wall_time=1001.0, monotonic_time=2.0)

            self.assertEqual(first["writes"], 1)
            self.assertEqual(second["writes"], 1)
            self.assertTrue(second["suppressed"])
            self.assertEqual(len(list(Path(temp_dir).glob("*.json"))), 1)

    def test_disabled_recorder_keeps_buffer_but_does_not_write(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(temp_dir, enabled=False)
            health = recorder.observe(_fault_state(), wall_time=1000.0, monotonic_time=1.0)

            self.assertFalse(health["enabled"])
            self.assertEqual(health["bufferFrames"], 1)
            self.assertEqual(len(list(Path(temp_dir).glob("*.json"))), 0)


def _state(speed: float) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "speedKph": speed,
        "rpm": 1000.0,
        "_health": {"signalMonitor": {"enabled": True, "ok": True}},
    }


def _fault_state() -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "speedKph": 0.0,
        "gps": {"fixValid": True, "speedKph": 55.0},
        "_health": {
            "signalMonitor": {"enabled": True, "ok": False},
            "signalFaults": [
                {
                    "signal": "speedKph",
                    "code": "source_disagreement",
                    "severity": "warning",
                    "message": "CAN speed disagrees with GPS speed",
                    "details": {"deltaKph": 55.0},
                }
            ],
        },
    }


if __name__ == "__main__":
    unittest.main()
