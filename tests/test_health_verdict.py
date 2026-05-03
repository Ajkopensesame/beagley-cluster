#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.health_verdict import build_coverage_summary, build_vehicle_health_verdict  # noqa: E402


class VehicleHealthVerdictTest(unittest.TestCase):
    def test_high_coverage_nominal_capture_can_be_healthy(self) -> None:
        verdict = build_vehicle_health_verdict(
            _state(),
            mode="replay",
            vehicle_profile="test vehicle",
            capture_ref={"sessionId": "capture-001", "durationSec": 900.0},
            coverage=build_coverage_summary(
                observed_contexts=["startup", "idle_stationary", "road_speed_drive", "highway_speed_drive", "cold_start", "heavy_load"],
                source_coverage={"can": "good", "gps": "good", "serial": "not_used"},
                sample_counts={"frames": 900, "signalSamples": 4200},
                duration_sec=900.0,
            ),
            baseline_snapshot=_baseline_snapshot(ready=True),
            direct_anchors=["rpm", "speedKph", "mafGps", "coolantC"],
        )

        self.assertEqual(verdict["verdict"]["label"], "healthy")
        self.assertTrue(verdict["verdict"]["ok"])
        self.assertFalse(verdict["abstain"]["required"])
        self.assertGreaterEqual(verdict["confidenceModel"]["score"], 0.9)

    def test_short_nominal_capture_abstains_as_insufficient_evidence(self) -> None:
        verdict = build_vehicle_health_verdict(
            _state(),
            coverage=build_coverage_summary(
                observed_contexts=["road_speed_drive"],
                source_coverage={"can": "not_used", "gps": "good", "serial": "not_used"},
                sample_counts={"frames": 2, "signalSamples": 8},
                duration_sec=0.2,
            ),
            baseline_snapshot=_baseline_snapshot(ready=False),
        )

        self.assertEqual(verdict["verdict"]["label"], "insufficient_evidence")
        self.assertIsNone(verdict["verdict"]["ok"])
        self.assertTrue(verdict["abstain"]["required"])
        self.assertIn("coverage_too_low", verdict["abstain"]["reasons"])

    def test_warning_anomaly_with_good_sources_becomes_anomaly_likely(self) -> None:
        verdict = build_vehicle_health_verdict(
            _anomalous_state(),
            mode="replay",
            vehicle_profile="test vehicle",
            coverage=build_coverage_summary(
                observed_contexts=["rev_stationary", "heavy_load"],
                source_coverage={"can": "good", "gps": "good", "serial": "not_used"},
                sample_counts={"frames": 180, "signalSamples": 900},
                duration_sec=18.0,
            ),
            baseline_snapshot=_baseline_snapshot(ready=True),
        )

        self.assertEqual(verdict["verdict"]["label"], "anomaly_likely")
        self.assertFalse(verdict["verdict"]["ok"])
        self.assertFalse(verdict["abstain"]["required"])
        self.assertIn("map_pressure_high", verdict["evidenceInputs"]["findingSummary"]["codes"])


def _state() -> dict:
    return {
        "rpm": 2200.0,
        "speedKph": 88.0,
        "mafGps": 38.0,
        "coolantC": 88.0,
        "_health": {
            "stale": False,
            "vehicleBaseline": {
                "enabled": True,
                "findings": [],
            },
        },
        "_diagnostic": {
            "mode": "replay",
            "severity": "ok",
            "status": "nominal",
            "findingCount": 0,
            "activeFindings": [],
            "captureQuality": {
                "gpsOk": True,
                "canOk": True,
                "serialOk": None,
                "linkStale": False,
            },
        },
    }


def _anomalous_state() -> dict:
    state = _state()
    state["mapKpa"] = 100.0
    state["_health"]["vehicleBaseline"]["findings"] = [
        {
            "source": "vehicleBaseline",
            "model": "map_pressure",
            "signal": "mapKpa",
            "code": "map_pressure_high",
            "severity": "warning",
            "message": "MAP pressure is above learned normal",
            "confidence": 0.84,
        }
    ]
    state["_diagnostic"] = {
        "mode": "replay",
        "severity": "warning",
        "status": "anomaly_detected",
        "findingCount": 1,
        "activeFindings": [
            {
                "source": "vehicleBaseline",
                "subject": "mapKpa",
                "code": "map_pressure_high",
                "severity": "warning",
                "message": "MAP pressure is above learned normal",
                "confidence": 0.84,
            }
        ],
        "captureQuality": {
            "gpsOk": True,
            "canOk": True,
            "serialOk": None,
            "linkStale": False,
        },
    }
    return state


def _baseline_snapshot(*, ready: bool) -> dict:
    return {
        "enabled": True,
        "models": [
            {
                "name": "intake_airflow",
                "ready": ready,
            },
            {
                "name": "map_pressure",
                "ready": ready,
            },
        ],
    }


if __name__ == "__main__":
    unittest.main()
