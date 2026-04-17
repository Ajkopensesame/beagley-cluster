#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.vehicle_analysis.context import operating_state  # noqa: E402
from tools.vehicle_analysis.findings import make_signal_fault, normalize_signal_fault  # noqa: E402
from tools.vehicle_analysis.stats import median, summary_stats  # noqa: E402
from tools.vehicle_analysis.values import number_or_none, rates, sign_changes  # noqa: E402


class VehicleAnalysisHelpersTest(unittest.TestCase):
    def test_operating_state_matches_stationary_and_drive_buckets(self) -> None:
        self.assertEqual(operating_state({"speedKph": 0.0, "rpm": 0.0}), "engine_off_stationary")
        self.assertEqual(operating_state({"speedKph": 0.0, "rpm": 850.0}), "idle_stationary")
        self.assertEqual(operating_state({"speedKph": 55.0, "rpm": 2200.0}), "road_speed_drive")

    def test_summary_stats_preserves_baseline_shape(self) -> None:
        stats = summary_stats([1.0, 2.0, 3.0, 4.0])

        self.assertEqual(stats["count"], 4)
        self.assertEqual(stats["mean"], 2.5)
        self.assertEqual(stats["median"], 2.5)
        self.assertIn("p05", stats)
        self.assertIn("p95", stats)

    def test_numeric_helpers_ignore_invalid_values(self) -> None:
        self.assertIsNone(number_or_none(True))
        self.assertIsNone(number_or_none("not-a-number"))
        self.assertEqual(number_or_none("12.5"), 12.5)
        self.assertEqual(median([3.0, 1.0, 2.0]), 2.0)

    def test_rate_helpers_preserve_signal_health_behavior(self) -> None:
        speed_rates = rates([(0.0, 20.0), (0.2, 45.0), (0.4, 18.0), (0.6, 48.0)])

        self.assertEqual(len(speed_rates), 3)
        self.assertGreaterEqual(sign_changes(speed_rates), 2)

    def test_finding_normalization_exports_public_details_only(self) -> None:
        fault = make_signal_fault(
            "speedKph",
            "source_disagreement",
            "warning",
            "CAN speed disagrees with GPS speed",
            deltaKph=55.0,
            confidence=0.91,
            internalOnly="not exported",
        )

        normalized = normalize_signal_fault(fault)

        self.assertEqual(normalized["subject"], "speedKph")
        self.assertEqual(normalized["confidence"], 0.91)
        self.assertEqual(normalized["details"], {"deltaKph": 55.0})


if __name__ == "__main__":
    unittest.main()
