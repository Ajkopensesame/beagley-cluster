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

from tools.bbb_hub.diagnostic_replay import load_state_jsonl, run_diagnostic_replay  # noqa: E402


class DiagnosticReplayTest(unittest.TestCase):
    def test_replay_flags_speed_disagreement_and_writes_fault_event(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            report = run_diagnostic_replay(
                [
                    _state(speed=0.0, gps_speed=55.0),
                    _state(speed=0.0, gps_speed=56.0),
                ],
                fault_recorder_dir=temp_dir,
                vehicle_baseline_enabled=False,
            )

            self.assertEqual(report["summary"]["frames"], 2)
            self.assertEqual(report["summary"]["anomalyFrames"], 2)
            self.assertEqual(report["summary"]["worstSeverity"], "warning")
            self.assertIn("source_disagreement", report["summary"]["findingCounts"])
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertTrue(Path(report["faultEventPaths"][0]).exists())
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertFalse(report["healthVerdict"]["abstain"]["required"])

    def test_replay_keeps_nominal_state_clean(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            report = run_diagnostic_replay(
                [_state(speed=40.0, gps_speed=41.0), _state(speed=42.0, gps_speed=43.0)],
                fault_recorder_dir=temp_dir,
                vehicle_baseline_enabled=False,
            )

            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["summary"]["worstSeverity"], "ok")
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])

    def test_replay_exercises_learned_map_pressure_baseline(self) -> None:
        states = []
        for _ in range(75):
            states.append(_map_state(rpm=2200.0, throttle=40.0, load=35.0, map_kpa=55.0))
            states.append(_map_state(rpm=2600.0, throttle=50.0, load=45.0, map_kpa=65.0))
        for _ in range(3):
            states.append(_map_state(rpm=2200.0, throttle=40.0, load=35.0, map_kpa=90.0))
            states.append(_map_state(rpm=2600.0, throttle=50.0, load=45.0, map_kpa=100.0))

        with tempfile.TemporaryDirectory() as temp_dir:
            report = run_diagnostic_replay(states, fault_recorder_dir=temp_dir)

            self.assertGreater(report["summary"]["anomalyFrames"], 0)
            self.assertIn("map_pressure_high", report["summary"]["findingCounts"])
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertTrue(Path(report["faultEventPaths"][0]).exists())
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertFalse(report["healthVerdict"]["abstain"]["required"])

    def test_replay_flags_flat_maf_start_transition_after_learning_good_starts(self) -> None:
        states = []
        for start_index in range(4):
            states.extend(_healthy_start(start_index * 10.0))
        states.extend(_flat_maf_start(50.0))

        with tempfile.TemporaryDirectory() as temp_dir:
            report = run_diagnostic_replay(
                states,
                frame_period_seconds=0.3,
                fault_recorder_dir=temp_dir,
                vehicle_baseline_enabled=False,
            )

            self.assertTrue(report["transitionBaselineReady"])
            self.assertEqual(_scenario_status(report, "startup_response"), "strong")
            self.assertGreater(report["summary"]["anomalyFrames"], 0)
            codes = set(report["summary"]["findingCounts"])
            self.assertTrue({"startup_maf_response_no_response", "startup_maf_response_stuck_flat"} & codes)
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")

    def test_load_state_jsonl_rejects_non_object_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "states.jsonl"
            path.write_text(json.dumps([1, 2, 3]) + "\n", encoding="utf-8")

            with self.assertRaises(ValueError):
                load_state_jsonl(path)


def _state(*, speed: float, gps_speed: float) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "speedKph": speed,
        "rpm": 1800.0,
        "fuelPct": 65.0,
        "coolantC": 88.0,
        "gps": {
            "fixValid": True,
            "speedKph": gps_speed,
        },
        "_health": {
            "stale": False,
        },
    }


def _map_state(*, rpm: float, throttle: float, load: float, map_kpa: float) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "rpm": rpm,
        "speedKph": 0.0,
        "fuelPct": 65.0,
        "coolantC": 88.0,
        "throttlePct": throttle,
        "engineLoadPct": load,
        "intakeAirTempC": 27.0,
        "mapKpa": map_kpa,
        "_health": {
            "stale": False,
        },
    }


def _healthy_start(base: float) -> list[dict]:
    return [
        _start_state(base + 0.0, rpm=0.0, maf=2.0, map_kpa=98.0),
        _start_state(base + 0.3, rpm=250.0, maf=3.0, map_kpa=96.0),
        _start_state(base + 0.6, rpm=800.0, maf=8.0, map_kpa=84.0),
        _start_state(base + 1.0, rpm=850.0, maf=11.0, map_kpa=78.0),
        _start_state(base + 1.5, rpm=860.0, maf=13.0, map_kpa=74.0),
        _start_state(base + 3.2, rpm=840.0, maf=12.0, map_kpa=76.0),
    ]


def _flat_maf_start(base: float) -> list[dict]:
    return [
        _start_state(base + 0.0, rpm=0.0, maf=2.0, map_kpa=98.0),
        _start_state(base + 0.3, rpm=250.0, maf=2.0, map_kpa=96.0),
        _start_state(base + 0.6, rpm=800.0, maf=2.0, map_kpa=84.0),
        _start_state(base + 1.0, rpm=850.0, maf=2.0, map_kpa=78.0),
        _start_state(base + 1.5, rpm=860.0, maf=2.0, map_kpa=74.0),
        _start_state(base + 3.2, rpm=120.0, maf=2.0, map_kpa=95.0),
    ]


def _start_state(timestamp: float, *, rpm: float, maf: float, map_kpa: float) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "timestamp": timestamp,
        "rpm": rpm,
        "speedKph": 0.0,
        "fuelPct": 65.0,
        "coolantC": 82.0,
        "mafGps": maf,
        "mapKpa": map_kpa,
        "engineLoadPct": 25.0 if rpm > 450.0 else 0.0,
        "throttlePct": 5.0,
        "_health": {
            "stale": False,
        },
    }


def _scenario_status(report: dict, key: str) -> str | None:
    for scenario in report.get("baselineCoverage", {}).get("scenarios", []):
        if scenario.get("key") == key:
            return scenario.get("status")
    return None


if __name__ == "__main__":
    unittest.main()
