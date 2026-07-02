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
            self.assertEqual(event["kind"], "bbb_fault_event")
            self.assertEqual(event["eventId"], "1002000-0001")
            self.assertEqual(event["faultFingerprint"], "speedKph:source_disagreement:warning")
            self.assertEqual(event["faults"][0]["code"], "source_disagreement")
            self.assertEqual(event["sourceHealth"]["signalMonitor"]["ok"], False)
            self.assertEqual(event["sourceHealth"]["signalFaults"][0]["signal"], "speedKph")
            self.assertEqual(event["triggerState"]["speedKph"], 0.0)
            self.assertEqual(event["triggerState"]["_health"]["signalFaults"][0]["severity"], "warning")
            self.assertEqual(event["rollingBuffer"]["seconds"], 5.0)
            self.assertEqual(len(event["rollingBuffer"]["frames"]), 3)
            for frame in event["rollingBuffer"]["frames"]:
                self.assertIn("wallTime", frame)
                self.assertIn("wallTimestamp", frame)
                self.assertIn("monotonicTimestamp", frame)
                self.assertIn("state", frame)
            self.assertEqual(event["evidence"]["canLiveRecentFrames"][0]["canId"], "0x101")
            self.assertEqual(event["recorder"]["outputDir"], temp_dir)
            self.assertEqual(event["recorder"]["minIntervalSeconds"], 10.0)
            self.assertEqual(event["recorder"]["wallTimestamp"], 1002.0)
            self.assertEqual(event["recorder"]["monotonicTimestamp"], 3.0)

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

    def test_prunes_old_fault_events_by_count(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(
                temp_dir,
                min_interval_seconds=0.0,
                max_event_files=2,
                max_total_bytes=0,
            )

            first = recorder.observe(_fault_state("first"), wall_time=1000.0, monotonic_time=1.0)
            second = recorder.observe(_fault_state("second"), wall_time=1001.0, monotonic_time=2.0)
            third = recorder.observe(_fault_state("third"), wall_time=1002.0, monotonic_time=3.0)

            event_files = sorted(Path(temp_dir).glob("*.json"))
            self.assertEqual(len(event_files), 2)
            self.assertFalse(Path(first["lastEventPath"]).exists())
            self.assertTrue(Path(second["lastEventPath"]).exists())
            self.assertTrue(Path(third["lastEventPath"]).exists())

    def test_prunes_old_fault_events_by_total_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(
                temp_dir,
                min_interval_seconds=0.0,
                max_event_files=0,
                max_total_bytes=3500,
            )

            first = recorder.observe(_fault_state("first"), wall_time=1000.0, monotonic_time=1.0)
            second = recorder.observe(_fault_state("second"), wall_time=1001.0, monotonic_time=2.0)

            self.assertFalse(Path(first["lastEventPath"]).exists())
            self.assertTrue(Path(second["lastEventPath"]).exists())
            self.assertLessEqual(sum(path.stat().st_size for path in Path(temp_dir).glob("*.json")), 3500)

    def test_persists_vehicle_baseline_findings_when_not_in_signal_faults(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(temp_dir, min_interval_seconds=0.0)
            health = recorder.observe(
                _baseline_finding_state(),
                wall_time=1000.0,
                monotonic_time=1.0,
            )

            self.assertEqual(health["writes"], 1)
            event = json.loads(Path(health["lastEventPath"]).read_text(encoding="utf-8"))
            self.assertEqual(event["faultFingerprint"], "mafGps:intake_airflow_low:warning")
            self.assertEqual(event["faults"][0]["code"], "intake_airflow_low")
            self.assertEqual(event["sourceHealth"]["vehicleBaseline"]["findings"][0]["code"], "intake_airflow_low")

    def test_persists_transition_monitor_findings(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(temp_dir, min_interval_seconds=0.0)
            health = recorder.observe(
                _transition_finding_state(),
                wall_time=1000.0,
                monotonic_time=1.0,
            )

            self.assertEqual(health["writes"], 1)
            event = json.loads(Path(health["lastEventPath"]).read_text(encoding="utf-8"))
            self.assertEqual(event["faultFingerprint"], "mafGps:startup_maf_response_no_response:warning")
            self.assertEqual(event["faults"][0]["code"], "startup_maf_response_no_response")
            self.assertEqual(
                event["sourceHealth"]["transitionMonitor"]["findings"][0]["code"],
                "startup_maf_response_no_response",
            )

    def test_deduplicates_baseline_findings_already_present_in_signal_faults(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            recorder = FaultRecorder(temp_dir, min_interval_seconds=0.0)
            state = _baseline_finding_state()
            state["_health"]["signalFaults"] = [
                {
                    "signal": "mafGps",
                    "code": "intake_airflow_low",
                    "severity": "warning",
                    "message": "MAF airflow is below learned normal",
                }
            ]
            health = recorder.observe(state, wall_time=1000.0, monotonic_time=1.0)

            self.assertEqual(health["writes"], 1)
            event = json.loads(Path(health["lastEventPath"]).read_text(encoding="utf-8"))
            self.assertEqual(len(event["faults"]), 1)
            self.assertEqual(event["faultFingerprint"], "mafGps:intake_airflow_low:warning")


def _state(speed: float) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "speedKph": speed,
        "rpm": 1000.0,
        "_health": {"signalMonitor": {"enabled": True, "ok": True}},
    }


def _fault_state(signal: str = "speedKph") -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "speedKph": 0.0,
        "gps": {"fixValid": True, "speedKph": 55.0},
        "_health": {
            "signalMonitor": {"enabled": True, "ok": False},
            "signalFaults": [
                {
                    "signal": signal,
                    "code": "source_disagreement",
                    "severity": "warning",
                    "message": "CAN speed disagrees with GPS speed",
                    "details": {"deltaKph": 55.0},
                }
            ],
        },
    }


def _baseline_finding_state() -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "mafGps": 1.2,
        "_health": {
            "vehicleBaseline": {
                "enabled": True,
                "findings": [
                    {
                        "source": "vehicleBaseline",
                        "model": "intake_airflow",
                        "signal": "mafGps",
                        "code": "intake_airflow_low",
                        "severity": "warning",
                        "message": "MAF airflow is below learned normal",
                        "confidence": 0.77,
                    }
                ],
            }
        },
    }


def _transition_finding_state() -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "mafGps": 0.0,
        "_health": {
            "transitionMonitor": {
                "enabled": True,
                "findings": [
                    {
                        "source": "transitionMonitor",
                        "subject": "mafGps",
                        "code": "startup_maf_response_no_response",
                        "severity": "warning",
                        "message": "Startup MAF response did not match learned baseline",
                        "confidence": 0.81,
                    }
                ],
            }
        },
    }


if __name__ == "__main__":
    unittest.main()
