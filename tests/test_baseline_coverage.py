#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.vehicle_analysis.baseline_coverage import build_baseline_coverage_report  # noqa: E402


class BaselineCoverageReportTest(unittest.TestCase):
    def test_reports_strong_weak_and_missing_scenarios(self) -> None:
        report = build_baseline_coverage_report(
            coverage={
                "observedContexts": ["startup", "cold_start", "road_speed_drive"],
                "missingContexts": ["hot_start", "heavy_load"],
            },
            vehicle_baseline_snapshot={
                "enabled": True,
                "models": [
                    {"name": "intake_airflow", "ready": True, "totalSamples": 180, "bucketCount": 4},
                    {"name": "map_pressure", "ready": False, "totalSamples": 25, "bucketCount": 1},
                ],
            },
            transition_snapshot={
                "enabled": True,
                "coverage": {"eventsSeen": {"first_fire": 6, "throttle_tip_in": 1}},
                "models": [
                    {"name": "startup_maf_response", "ready": True, "windows": 6, "eventType": "first_fire"},
                    {
                        "name": "throttle_tip_in_maf_response",
                        "ready": False,
                        "windows": 1,
                        "eventType": "throttle_tip_in",
                    },
                ],
            },
        )

        by_key = {scenario["key"]: scenario for scenario in report["scenarios"]}

        self.assertEqual(by_key["startup_response"]["status"], "strong")
        self.assertEqual(by_key["cold_start"]["status"], "strong")
        self.assertEqual(by_key["hot_restart"]["status"], "weak")
        self.assertEqual(by_key["map_pressure"]["status"], "weak")
        self.assertEqual(by_key["shift_response"]["status"], "missing")
        self.assertIn("startup_maf_response", report["transitions"]["readyModels"])
        self.assertIn("intake_airflow", report["steadyState"]["readyModels"])
        self.assertGreater(report["summary"]["strongScenarios"], 0)
        self.assertGreater(report["summary"]["missingScenarios"], 0)
        next_steps = report["summary"]["nextSteps"]
        self.assertLessEqual(len(next_steps), 5)
        self.assertEqual(next_steps[0]["status"], "missing")
        self.assertIn("nextStep", next_steps[0])
        self.assertIn("missing", next_steps[0])
        self.assertIn(next_steps[0]["scenario"], {scenario["key"] for scenario in report["scenarios"]})


if __name__ == "__main__":
    unittest.main()
