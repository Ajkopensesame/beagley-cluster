#!/usr/bin/env python3
"""A one-off wall-clock step (bbb-gps-clock) must not disturb hub-internal timing."""
from __future__ import annotations

import os
import sys
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub import transition_monitor, vehicle_baseline  # noqa: E402

STEP_S = 176 * 86400.0  # ~April -> October


class ClockStepResilienceTest(unittest.TestCase):
    def _assert_steady(self, monitor, module) -> None:
        real_time = module.time.time
        before = monitor._steady_now()
        with mock.patch.object(module.time, "time", lambda: real_time() + STEP_S):
            after = monitor._steady_now()
            # default-timestamp observe() must also be unaffected by the stepped wall clock
            self.assertLess(abs(after - before), 5.0)

    def test_transition_monitor_time_base_ignores_wall_step(self) -> None:
        monitor = transition_monitor.VehicleTransitionMonitor(transition_monitor.default_transition_profiles())
        self._assert_steady(monitor, transition_monitor)

    def test_vehicle_baseline_time_base_ignores_wall_step(self) -> None:
        monitor = vehicle_baseline.VehicleBaselineMonitor(vehicle_baseline.default_vehicle_baseline_profiles())
        self._assert_steady(monitor, vehicle_baseline)

    def test_history_is_kept_across_a_wall_step(self) -> None:
        monitor = transition_monitor.VehicleTransitionMonitor(transition_monitor.default_transition_profiles())
        real_time = transition_monitor.time.time
        monitor.observe({"speedKph": 0.0})
        monitor.observe({"speedKph": 0.0})
        self.assertEqual(len(monitor._history), 2)
        with mock.patch.object(transition_monitor.time, "time", lambda: real_time() + STEP_S):
            monitor.observe({"speedKph": 0.0})
        self.assertEqual(len(monitor._history), 3, "history must not be flushed by a forward wall-clock step")


if __name__ == "__main__":
    unittest.main()
