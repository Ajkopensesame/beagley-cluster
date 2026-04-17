#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.signal_health import SignalHealthMonitor  # noqa: E402


class SignalHealthMonitorTest(unittest.TestCase):
    def test_flags_out_of_range_rpm(self) -> None:
        monitor = SignalHealthMonitor()
        health = monitor.observe({"rpm": 9200.0, "_health": {}}, now_monotonic=1.0)
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "rpm", "out_of_range"))

    def test_flags_impossible_speed_jump(self) -> None:
        monitor = SignalHealthMonitor()
        monitor.observe({"speedKph": 10.0, "_health": {}}, now_monotonic=1.0)
        health = monitor.observe({"speedKph": 100.0, "_health": {}}, now_monotonic=1.5)
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "speedKph", "impossible_jump"))

    def test_flags_gps_speed_disagreement(self) -> None:
        monitor = SignalHealthMonitor(gps_speed_disagreement_kph=15.0)
        health = monitor.observe(
            {
                "speedKph": 0.0,
                "gps": {"fixValid": True, "speedKph": 55.0},
                "_health": {},
            },
            now_monotonic=1.0,
        )
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "speedKph", "source_disagreement"))

    def test_flags_stale_live_can_source(self) -> None:
        monitor = SignalHealthMonitor()
        health = monitor.observe(
            {
                "speedKph": 10.0,
                "_health": {
                    "canLive": {
                        "enabled": True,
                        "stale": True,
                        "ageMs": 2500,
                    }
                },
            },
            now_monotonic=1.0,
        )
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "can", "source_stale"))

    def test_bridges_expert_can_diagnostics_findings(self) -> None:
        monitor = SignalHealthMonitor()
        health = monitor.observe(
            {
                "_health": {
                    "canLiveDiagnostics": {
                        "enabled": True,
                        "findings": [
                            {
                                "source": "canLive",
                                "subject": "0x100",
                                "code": "can_id_dropout",
                                "severity": "warning",
                                "message": "0x100 stopped arriving",
                                "confidence": 0.88,
                                "details": {"suspectedCauses": ["ECU stopped publishing"]},
                            }
                        ],
                    }
                }
            },
            now_monotonic=1.0,
        )
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "0x100", "can_id_dropout"))

    def test_bridges_vehicle_baseline_findings(self) -> None:
        monitor = SignalHealthMonitor()
        health = monitor.observe(
            {
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
                                "details": {"suspectedCauses": ["dirty air filter"]},
                            }
                        ],
                    }
                }
            },
            now_monotonic=1.0,
        )
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "mafGps", "intake_airflow_low"))

    def test_flags_noisy_signal(self) -> None:
        monitor = SignalHealthMonitor()
        health = {"ok": True, "faults": []}
        for index, speed in enumerate([20, 45, 18, 48, 17, 50, 16, 52, 15]):
            health = monitor.observe({"speedKph": float(speed), "_health": {}}, now_monotonic=1.0 + index * 0.2)
        self.assertFalse(health["ok"])
        self.assertTrue(_has_fault(health, "speedKph", "noisy_or_flapping"))


def _has_fault(health: dict, signal: str, code: str) -> bool:
    return any(fault.get("signal") == signal and fault.get("code") == code for fault in health.get("faults", []))


if __name__ == "__main__":
    unittest.main()
