#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.diagnostic_status import build_diagnostic_status  # noqa: E402


class DiagnosticStatusTest(unittest.TestCase):
    def test_nominal_state_is_ok(self) -> None:
        status = build_diagnostic_status(
            {
                "gps": {"fixValid": True},
                "_health": {"stale": False},
            }
        )

        self.assertTrue(status["ok"])
        self.assertEqual(status["severity"], "ok")
        self.assertEqual(status["status"], "nominal")
        self.assertEqual(status["summary"], "SYSTEMS NOMINAL")
        self.assertEqual(status["findingCount"], 0)
        self.assertTrue(status["captureQuality"]["gpsOk"])
        self.assertIsNone(status["captureQuality"]["canOk"])

    def test_signal_fault_becomes_active_display_finding(self) -> None:
        status = build_diagnostic_status(
            {
                "_health": {
                    "signalFaults": [
                        {
                            "signal": "speedKph",
                            "code": "source_disagreement",
                            "severity": "warning",
                            "message": "CAN speed disagrees with GPS speed",
                            "details": {
                                "deltaKph": 55.0,
                                "confidence": 0.91,
                                "internalOnly": "not exported",
                            },
                        }
                    ],
                },
            }
        )

        self.assertFalse(status["ok"])
        self.assertEqual(status["severity"], "warning")
        self.assertEqual(status["status"], "anomaly_detected")
        self.assertEqual(status["findingCount"], 1)
        self.assertEqual(status["activeFindings"][0]["subject"], "speedKph")
        self.assertEqual(status["activeFindings"][0]["code"], "source_disagreement")
        self.assertEqual(status["activeFindings"][0]["confidence"], 0.91)
        self.assertEqual(status["activeFindings"][0]["details"], {"deltaKph": 55.0})

    def test_deduplicates_signal_fault_and_raw_can_finding(self) -> None:
        status = build_diagnostic_status(
            {
                "_health": {
                    "signalFaults": [
                        {
                            "signal": "0x100",
                            "code": "can_id_dropout",
                            "severity": "warning",
                            "message": "0x100 stopped arriving",
                            "details": {"source": "canLive"},
                        }
                    ],
                    "canLiveDiagnostics": {
                        "enabled": True,
                        "findings": [
                            {
                                "source": "canLive",
                                "subject": "0x100",
                                "code": "can_id_dropout",
                                "severity": "warning",
                                "message": "0x100 stopped arriving",
                                "confidence": 0.86,
                            }
                        ],
                    },
                },
            }
        )

        self.assertEqual(status["findingCount"], 1)
        self.assertEqual(status["activeFindings"][0]["source"], "canLive")

    def test_capture_quality_limited_when_live_can_is_stale(self) -> None:
        status = build_diagnostic_status(
            {
                "_health": {
                    "canLive": {
                        "enabled": True,
                        "stale": True,
                    }
                }
            }
        )

        self.assertTrue(status["ok"])
        self.assertEqual(status["severity"], "info")
        self.assertEqual(status["status"], "limited")
        self.assertFalse(status["captureQuality"]["canOk"])

    def test_stale_health_overrides_nominal_summary(self) -> None:
        status = build_diagnostic_status({"_health": {"stale": True}})

        self.assertFalse(status["ok"])
        self.assertEqual(status["severity"], "warning")
        self.assertEqual(status["status"], "data_stale")
        self.assertEqual(status["summary"], "VEHICLE DATA STALE")


if __name__ == "__main__":
    unittest.main()
