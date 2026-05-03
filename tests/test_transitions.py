#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.transition_monitor import VehicleTransitionMonitor, default_transition_profiles  # noqa: E402
from tools.vehicle_analysis.transitions import EventSegmenter, transition_window_metrics  # noqa: E402


class TransitionAnalysisTest(unittest.TestCase):
    def test_event_segmenter_detects_startup_events(self) -> None:
        segmenter = EventSegmenter()

        first = segmenter.observe(_state(0.0, 0.0, maf=2.0, map_kpa=98.0), 100.0)
        crank = segmenter.observe(_state(260.0, 0.0, maf=3.0, map_kpa=96.0), 100.2)
        fire = segmenter.observe(_state(820.0, 0.0, maf=9.0, map_kpa=82.0), 100.4)

        self.assertEqual([event.name for event in first], ["key_on"])
        self.assertIn("crank_start", [event.name for event in crank])
        self.assertIn("first_fire", [event.name for event in fire])
        self.assertIn("idle_settle", [event.name for event in fire])

    def test_transition_window_metrics_capture_response_shape(self) -> None:
        samples = [
            (99.0, _state(0.0, 0.0, maf=2.0, map_kpa=98.0)),
            (99.5, _state(250.0, 0.0, maf=3.0, map_kpa=96.0)),
            (100.0, _state(800.0, 0.0, maf=8.0, map_kpa=84.0)),
            (100.5, _state(850.0, 0.0, maf=12.0, map_kpa=76.0)),
        ]

        metrics = transition_window_metrics(
            samples,
            event_timestamp=100.0,
            target="mafGps",
            reference_signals=("rpm", "mapKpa"),
            before_seconds=1.2,
            after_seconds=1.0,
        )

        self.assertGreater(metrics["absDelta"], 5.0)
        self.assertEqual(metrics["beforeCount"], 2)
        self.assertEqual(metrics["afterCount"], 2)
        self.assertIn("rpm", metrics["correlations"])

    def test_transition_monitor_flags_flat_maf_after_known_good_starts(self) -> None:
        monitor = VehicleTransitionMonitor(default_transition_profiles(), storage_path=None, enabled=True)
        timestamp = 1000.0

        for start_index in range(4):
            for offset, state in _healthy_start(timestamp + start_index * 10.0):
                health = monitor.observe(state, timestamp=offset)
                self.assertTrue(health["ok"])

        self.assertTrue(_model_ready(monitor.snapshot(), "startup_maf_response"))

        finding_health = None
        for offset, state in _flat_maf_start(timestamp + 50.0):
            finding_health = monitor.observe(state, timestamp=offset)

        self.assertIsNotNone(finding_health)
        self.assertFalse(finding_health["ok"])
        codes = {finding["code"] for finding in finding_health["findings"]}
        self.assertTrue({"startup_maf_response_no_response", "startup_maf_response_stuck_flat"} & codes)

    def test_transition_monitor_persists_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "transition_baseline.json"
            monitor = VehicleTransitionMonitor(
                default_transition_profiles(),
                storage_path=path,
                enabled=True,
                save_every_windows=1,
                min_save_interval_seconds=0.0,
            )
            for start_index in range(4):
                for offset, state in _healthy_start(2000.0 + start_index * 10.0):
                    monitor.observe(state, timestamp=offset)

            self.assertTrue(path.exists())
            reloaded = VehicleTransitionMonitor(default_transition_profiles(), storage_path=path, enabled=True)
            self.assertTrue(_model_ready(reloaded.snapshot(), "startup_maf_response"))


def _healthy_start(base: float) -> list[tuple[float, dict]]:
    return [
        (base + 0.0, _state(0.0, 0.0, maf=2.0, map_kpa=98.0)),
        (base + 0.3, _state(250.0, 0.0, maf=3.0, map_kpa=96.0)),
        (base + 0.6, _state(800.0, 0.0, maf=8.0, map_kpa=84.0)),
        (base + 1.0, _state(850.0, 0.0, maf=11.0, map_kpa=78.0)),
        (base + 1.5, _state(860.0, 0.0, maf=13.0, map_kpa=74.0)),
        (base + 3.2, _state(840.0, 0.0, maf=12.0, map_kpa=76.0)),
    ]


def _flat_maf_start(base: float) -> list[tuple[float, dict]]:
    return [
        (base + 0.0, _state(0.0, 0.0, maf=2.0, map_kpa=98.0)),
        (base + 0.3, _state(250.0, 0.0, maf=2.0, map_kpa=96.0)),
        (base + 0.6, _state(800.0, 0.0, maf=2.0, map_kpa=84.0)),
        (base + 1.0, _state(850.0, 0.0, maf=2.0, map_kpa=78.0)),
        (base + 1.5, _state(860.0, 0.0, maf=2.0, map_kpa=74.0)),
        (base + 3.2, _state(120.0, 0.0, maf=2.0, map_kpa=95.0)),
    ]


def _state(rpm: float, speed: float, *, maf: float, map_kpa: float) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "rpm": rpm,
        "speedKph": speed,
        "mafGps": maf,
        "mapKpa": map_kpa,
        "engineLoadPct": 25.0 if rpm > 450.0 else 0.0,
        "throttlePct": 5.0,
        "coolantC": 82.0,
        "_health": {
            "stale": False,
        },
    }


def _model_ready(snapshot: dict, name: str) -> bool:
    for model in snapshot.get("models", []):
        if model.get("name") == name:
            return bool(model.get("ready"))
    return False


if __name__ == "__main__":
    unittest.main()
