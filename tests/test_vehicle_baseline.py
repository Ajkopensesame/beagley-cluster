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

from tools.bbb_hub.vehicle_baseline import (  # noqa: E402
    BaselineCondition,
    BaselineFeature,
    BaselineProfile,
    VehicleBaselineMonitor,
)


class VehicleBaselineModelTest(unittest.TestCase):
    def test_learns_bucket_and_flags_repeated_low_maf(self) -> None:
        monitor = VehicleBaselineMonitor(
            [_test_intake_profile()],
            enabled=True,
            storage_path=None,
        )
        for index in range(6):
            health = monitor.observe(_state(maf=40.0 + (index % 2)), timestamp=1000.0 + index)
            self.assertTrue(health["ok"])

        finding_health = None
        for index in range(3):
            finding_health = monitor.observe(_state(maf=24.0), timestamp=1010.0 + index)

        self.assertIsNotNone(finding_health)
        self.assertFalse(finding_health["ok"])
        self.assertEqual(finding_health["findings"][0]["code"], "intake_airflow_low")
        self.assertGreater(finding_health["findings"][0]["confidence"], 0.5)

    def test_skips_learning_until_required_conditions_are_met(self) -> None:
        monitor = VehicleBaselineMonitor([_test_intake_profile()], enabled=True)
        health = monitor.observe(_state(maf=40.0, coolant=45.0), timestamp=1000.0)

        model = health["models"][0]
        self.assertEqual(model["status"], "skipped")
        self.assertIn("coolantC", model["reason"])
        self.assertEqual(model["totalSamples"], 0)

    def test_persists_and_loads_baseline_buckets(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "vehicle_baseline.json"
            monitor = VehicleBaselineMonitor(
                [_test_intake_profile()],
                storage_path=path,
                enabled=True,
                save_every_samples=1,
                min_save_interval_seconds=0.0,
            )
            monitor.observe(_state(maf=40.0), timestamp=1000.0)

            self.assertTrue(path.exists())
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertIn("intake_airflow", payload["models"])

            reloaded = VehicleBaselineMonitor([_test_intake_profile()], storage_path=path, enabled=True)
            snapshot = reloaded.snapshot()
            self.assertEqual(snapshot["models"][0]["totalSamples"], 1)


def _test_intake_profile() -> BaselineProfile:
    return BaselineProfile(
        name="intake_airflow",
        target="mafGps",
        unit="g/s",
        features=(
            BaselineFeature("rpm", 250.0),
            BaselineFeature("throttlePct", 10.0),
            BaselineFeature("intakeAirTempC", 10.0),
        ),
        conditions=(BaselineCondition("coolantC", minimum=70.0),),
        direction="low",
        min_bucket_samples=5,
        min_total_samples=5,
        min_anomaly_samples=3,
        min_anomaly_buckets=1,
        anomaly_window_seconds=60.0,
        drift_fraction=0.20,
        drift_abs=3.0,
        drift_stddev=2.0,
        low_code="intake_airflow_low",
        low_message="MAF airflow is below learned normal",
        suspected_causes=("dirty air filter", "blocked intake"),
    )


def _state(maf: float, coolant: float = 88.0) -> dict:
    return {
        "rpm": 2200.0,
        "throttlePct": 40.0,
        "intakeAirTempC": 27.0,
        "coolantC": coolant,
        "mafGps": maf,
        "_health": {},
    }


if __name__ == "__main__":
    unittest.main()
