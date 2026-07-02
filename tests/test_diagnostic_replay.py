#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.diagnostic_replay import (  # noqa: E402
    LOW_TRUST_SHAPE_MISSING_CANDIDATE_ID_REASON,
    TRANSITION_FINDINGS_REPORT_LIMIT,
    _print_summary,
    _summarize_fault_events,
    _validate_sensor_surface_summary,
    load_diagnostic_candidate_signals,
    load_state_jsonl,
    main,
    run_diagnostic_replay,
)
from tools.bbb_hub.transition_monitor import (  # noqa: E402
    TransitionProfile,
    default_transition_profiles,
)
from tools.bbb_hub.vehicle_baseline import (  # noqa: E402
    BaselineFeature,
    BaselineProfile,
    default_vehicle_baseline_profiles,
)
from tools.vehicle_analysis.findings import SEVERITY_ORDER  # noqa: E402
from tools.vehicle_analysis.transitions import ANOMALY_CLASSES  # noqa: E402


SENSOR_COVERAGE_CLI_SURFACE_ORDER = (
    "signal_health",
    "source_agreement_anchor",
    "learned_baseline_target",
    "learned_baseline_context",
    "transition_target",
    "transition_reference",
    "transition_event_input",
)

SENSOR_COVERAGE_SURFACES = set(SENSOR_COVERAGE_CLI_SURFACE_ORDER)

SENSOR_COVERAGE_TRUST_TIERS = {
    "direct_anchor",
    "low_trust_candidate",
    "unknown",
    "verified_decoded",
}

SENSOR_COVERAGE_REASONS = {
    "covered": "Observed with deterministic signal-health, baseline, transition, or source-agreement coverage.",
    "low_trust": "Observed as low-trust diagnostic evidence only; needs promotion, rules, or known-good baseline support.",
    "unsupported": "Observed but no deterministic rule, learned model, transition profile, or low-trust policy covers it yet.",
}

SENSOR_COVERAGE_SHAPE_FINDING_CODES = {
    "low_trust_candidate_noisy_or_flapping",
    "low_trust_candidate_stuck_flat",
}

SENSOR_COVERAGE_TRUST_METADATA_SOURCES = {
    "_health.diagnosticCandidateSignals",
    "_health.sensorTrust",
    "diagnosticCandidateSignals",
    "diagnostic_candidate_signals_sidecar",
    "sensorTrust",
}


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
            self.assertEqual(report["signalMonitor"]["faultCount"], 1)
            self.assertTrue(Path(report["faultEventPaths"][0]).exists())
            self.assertEqual(report["faultEventSummaries"][0]["kind"], "bbb_fault_event_summary")
            self.assertEqual(report["faultEventSummaries"][0]["primaryFinding"]["code"], "source_disagreement")
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertFalse(report["healthVerdict"]["abstain"]["required"])

    def test_replay_suppressed_duplicate_faults_preserve_detection_truth(self) -> None:
        states = [_state(speed=0.0, gps_speed=55.0 + (index % 2)) for index in range(12)]
        with tempfile.TemporaryDirectory() as temp_dir:
            fault_dir = Path(temp_dir) / "faults"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            report = run_diagnostic_replay(
                states,
                fault_recorder_dir=fault_dir,
                enriched_jsonl=enriched_path,
                vehicle_baseline_enabled=False,
            )

            _assert_replay_report_contract(self, report)
            self.assertEqual(report["summary"]["frames"], 12)
            self.assertEqual(report["summary"]["anomalyFrames"], 12)
            self.assertEqual(report["summary"]["findingCounts"]["source_disagreement"], 12)
            self.assertEqual(report["diagnosticStatusCounts"]["anomaly_detected"], 12)
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertEqual(len(report["faultEventPaths"]), 1)
            self.assertEqual(len(report["faultEventSummaries"]), 1)
            self.assertEqual(report["faultRecorder"]["writes"], 1)
            self.assertEqual(report["faultRecorder"]["lastEventPath"], report["faultEventPaths"][0])

            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(len(enriched_states), 12)
            self.assertEqual(enriched_states[-1]["_diagnostic"]["status"], "anomaly_detected")
            self.assertTrue(enriched_states[-1]["_health"]["faultRecorder"]["suppressed"])
            self.assertEqual(
                enriched_states[-1]["_health"]["faultRecorder"]["suppressedFingerprint"],
                "speedKph:source_disagreement:warning",
            )

    def test_replay_rewrites_fault_event_after_suppression_interval_expires(self) -> None:
        states = [_state(speed=0.0, gps_speed=55.0 + index) for index in range(3)]
        with tempfile.TemporaryDirectory() as temp_dir:
            fault_dir = Path(temp_dir) / "faults"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            report = run_diagnostic_replay(
                states,
                frame_period_seconds=6.0,
                fault_recorder_dir=fault_dir,
                enriched_jsonl=enriched_path,
                vehicle_baseline_enabled=False,
            )

            _assert_replay_report_contract(self, report)
            self.assertEqual(report["summary"]["frames"], 3)
            self.assertEqual(report["summary"]["anomalyFrames"], 3)
            self.assertEqual(report["summary"]["findingCounts"]["source_disagreement"], 3)
            self.assertEqual(report["summary"]["faultEvents"], 2)
            self.assertEqual(report["faultRecorder"]["writes"], 2)
            self.assertEqual(len(report["faultEventPaths"]), 2)
            self.assertEqual(len(report["faultEventSummaries"]), 2)
            self.assertEqual(report["faultRecorder"]["lastEventPath"], report["faultEventPaths"][-1])

            event_monotonic_times = [
                json.loads(Path(path).read_text(encoding="utf-8"))["recorder"]["monotonicTimestamp"]
                for path in report["faultEventPaths"]
            ]
            self.assertEqual(event_monotonic_times, [0.0, 12.0])
            for summary in report["faultEventSummaries"]:
                self.assertEqual(summary["primaryFinding"]["code"], "source_disagreement")

            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            fault_recorder_health = [
                state["_health"]["faultRecorder"]
                for state in enriched_states
            ]
            self.assertNotIn("suppressed", fault_recorder_health[0])
            self.assertTrue(fault_recorder_health[1]["suppressed"])
            self.assertNotIn("suppressed", fault_recorder_health[2])
            self.assertEqual([health["writes"] for health in fault_recorder_health], [1, 1, 2])

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

    def test_replay_reports_low_trust_and_unsupported_sensor_coverage(self) -> None:
        states = [
            {
                "type": "vehicle_state",
                "version": 1,
                "rpm": 1800.0,
                "speedKph": 42.0,
                "autoWheelSpeedKph": 41.5,
                "mysteryVoltage": 2.8,
                "_health": {
                    "stale": False,
                    "sensorTrust": {
                        "autoWheelSpeedKph": {
                            "trust": "low",
                            "source": "diagnostic_candidate_signals",
                            "candidateId": "0x221:b16:l16:little:u",
                        }
                    },
                },
            },
            {
                "type": "vehicle_state",
                "version": 1,
                "rpm": 1810.0,
                "speedKph": 43.0,
                "autoWheelSpeedKph": 42.4,
                "mysteryVoltage": 2.9,
                "_health": {
                    "stale": False,
                    "sensorTrust": {
                        "autoWheelSpeedKph": {
                            "trust": "low",
                            "source": "diagnostic_candidate_signals",
                            "candidateId": "0x221:b16:l16:little:u",
                        }
                    },
                },
            },
        ]

        report = run_diagnostic_replay(
            states,
            fault_recorder_enabled=False,
            vehicle_baseline_enabled=False,
            transition_monitor_enabled=False,
        )

        _assert_replay_report_contract(self, report)
        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in report["sensorCoverage"]["sensors"]
        }
        self.assertEqual(coverage_by_name["rpm"]["status"], "covered")
        self.assertIn("signal_health", coverage_by_name["rpm"]["surfaces"])
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["mysteryVoltage"]["status"], "unsupported")
        self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustSensors"], 1)
        self.assertEqual(report["sensorCoverage"]["summary"]["unsupportedSensors"], 1)
        self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)
        self.assertEqual(report["sensorCoverage"]["summary"]["coverageRatio"], 0.5)
        self.assertEqual(report["sensorCoverage"]["summary"]["gapRatio"], 0.5)
        self.assertEqual(report["sensorCoverage"]["shapeFindings"], [])
        self.assertEqual(
            report["sensorCoverage"]["surfaceSummary"]["statusSensors"]["low_trust"],
            ["autoWheelSpeedKph"],
        )
        self.assertEqual(
            report["sensorCoverage"]["surfaceSummary"]["statusSensors"]["unsupported"],
            ["mysteryVoltage"],
        )
        self.assertEqual(
            report["sensorCoverage"]["surfaceSummary"]["gapSensors"],
            ["autoWheelSpeedKph", "mysteryVoltage"],
        )
        self.assertEqual(
            report["sensorCoverage"]["surfaceSummary"]["surfaceSensors"]["signal_health"],
            ["rpm", "speedKph"],
        )
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["shapeFindings"], [])
        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)
        text = output.getvalue()
        self.assertIn(
            "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=1 unsupported=1 shape_findings=0",
            text,
        )
        self.assertIn("coverage_ratio=0.500", text)
        self.assertIn("gap_ratio=0.500", text)
        self.assertIn(
            "[diagnostic-replay] sensor_surfaces signal_health=2 source_agreement_anchor=0 learned_baseline_target=0 learned_baseline_context=0 transition_target=0 transition_reference=0 transition_event_input=0 gaps=2",
            text,
        )
        self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

    def test_sensor_surface_summary_rejects_gap_and_surface_drift(self) -> None:
        sensors = [
            {"name": "rpm", "status": "covered", "surfaces": ["signal_health", "transition_target"]},
            {"name": "speedKph", "status": "covered", "surfaces": ["signal_health"]},
            {"name": "autoWheelSpeedKph", "status": "low_trust", "surfaces": []},
            {"name": "mysteryVoltage", "status": "unsupported", "surfaces": []},
        ]
        valid_summary = {
            "statusSensors": {
                "covered": ["rpm", "speedKph"],
                "low_trust": ["autoWheelSpeedKph"],
                "unsupported": ["mysteryVoltage"],
            },
            "surfaceSensors": {
                "learned_baseline_context": [],
                "learned_baseline_target": [],
                "signal_health": ["rpm", "speedKph"],
                "source_agreement_anchor": [],
                "transition_event_input": [],
                "transition_reference": [],
                "transition_target": ["rpm"],
            },
            "surfaceCounts": {
                "learned_baseline_context": 0,
                "learned_baseline_target": 0,
                "signal_health": 2,
                "source_agreement_anchor": 0,
                "transition_event_input": 0,
                "transition_reference": 0,
                "transition_target": 1,
            },
            "gapSensors": ["autoWheelSpeedKph", "mysteryVoltage"],
        }
        _validate_sensor_surface_summary(sensors, valid_summary)

        stale_status_summary = json.loads(json.dumps(valid_summary))
        stale_status_summary["statusSensors"]["covered"] = ["rpm"]
        with self.assertRaisesRegex(ValueError, "statusSensors must exactly match"):
            _validate_sensor_surface_summary(sensors, stale_status_summary)

        stale_surface_summary = json.loads(json.dumps(valid_summary))
        stale_surface_summary["surfaceSensors"]["signal_health"] = ["rpm"]
        with self.assertRaisesRegex(ValueError, "surfaceSensors must exactly match"):
            _validate_sensor_surface_summary(sensors, stale_surface_summary)

        stale_count_summary = json.loads(json.dumps(valid_summary))
        stale_count_summary["surfaceCounts"]["signal_health"] = 1
        with self.assertRaisesRegex(ValueError, "surfaceCounts must exactly match"):
            _validate_sensor_surface_summary(sensors, stale_count_summary)

        stale_summary = {
            "statusSensors": valid_summary["statusSensors"],
            "surfaceSensors": valid_summary["surfaceSensors"],
            "surfaceCounts": valid_summary["surfaceCounts"],
            "gapSensors": ["autoWheelSpeedKph"],
        }
        with self.assertRaisesRegex(ValueError, "gapSensors must exactly match"):
            _validate_sensor_surface_summary(sensors, stale_summary)

    def test_sensor_coverage_summary_navigation_is_report_only(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_low_trust.jsonl"
        candidate_signals = Path(ROOT) / "tests" / "fixtures" / "diagnostic_candidate_signals_low_trust.json"
        report = run_diagnostic_replay(
            load_state_jsonl(fixture),
            diagnostic_candidate_signals=load_diagnostic_candidate_signals(candidate_signals),
        )

        self.assertEqual(report["sensorCoverage"]["summary"]["coverageRatio"], 0.5)
        self.assertEqual(report["sensorCoverage"]["summary"]["gapRatio"], 0.5)
        self.assertEqual(
            report["sensorCoverage"]["surfaceSummary"]["gapSensors"],
            ["autoWheelSpeedKph", "mysteryVoltage"],
        )
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["lastDiagnostic"]["activeFindings"], [])
        self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
        self.assertTrue(report["healthVerdict"]["abstain"]["required"])
        _assert_sensor_coverage_navigation_fields_report_only(self, report)

    def test_replay_honors_row_level_future_sensor_trust_without_candidate_file(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_row_trust.jsonl"
        report = run_diagnostic_replay(
            load_state_jsonl(fixture),
            fault_recorder_enabled=False,
            vehicle_baseline_enabled=False,
            transition_monitor_enabled=False,
        )

        _assert_replay_report_contract(self, report)
        self.assertEqual(report["summary"]["anomalyFrames"], 0)
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")

        coverage = report["sensorCoverage"]
        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in coverage["sensors"]
        }
        self.assertEqual(coverage["summary"]["lowTrustSensors"], 2)
        self.assertEqual(coverage["summary"]["unsupportedSensors"], 1)
        self.assertEqual(coverage["summary"]["lowTrustShapeFindings"], 0)
        self.assertEqual(coverage["shapeFindings"], [])
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["autoBoostGuessKpa"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoBoostGuessKpa"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["mysteryVoltage"]["status"], "unsupported")

        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)
        text = output.getvalue()
        self.assertIn(
            "[diagnostic-replay] sensor_coverage observed=5 covered=2 low_trust=2 unsupported=1 shape_findings=0",
            text,
        )

    def test_replay_honors_top_level_future_sensor_trust_without_candidate_file(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_top_level_trust.jsonl"
        report = run_diagnostic_replay(
            load_state_jsonl(fixture),
            fault_recorder_enabled=False,
            vehicle_baseline_enabled=False,
            transition_monitor_enabled=False,
        )

        _assert_replay_report_contract(self, report)
        self.assertEqual(report["summary"]["anomalyFrames"], 0)
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")

        coverage = report["sensorCoverage"]
        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in coverage["sensors"]
        }
        self.assertEqual(coverage["summary"]["lowTrustSensors"], 2)
        self.assertEqual(coverage["summary"]["unsupportedSensors"], 1)
        self.assertEqual(coverage["summary"]["lowTrustShapeFindings"], 0)
        self.assertEqual(coverage["shapeFindings"], [])
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["autoTorqueGuessNm"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoTorqueGuessNm"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["mysteryVoltage"]["status"], "unsupported")

        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)
        text = output.getvalue()
        self.assertIn(
            "[diagnostic-replay] sensor_coverage observed=5 covered=2 low_trust=2 unsupported=1 shape_findings=0",
            text,
        )

    def test_replay_reports_verified_future_sensor_without_surfaces_as_unsupported(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_verified_unsupported.jsonl"
        report = run_diagnostic_replay(
            load_state_jsonl(fixture),
            fault_recorder_enabled=False,
            vehicle_baseline_enabled=False,
            transition_monitor_enabled=False,
        )

        _assert_replay_report_contract(self, report)
        self.assertEqual(report["summary"]["anomalyFrames"], 0)
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")

        coverage = report["sensorCoverage"]
        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in coverage["sensors"]
        }
        self.assertEqual(coverage["summary"]["coveredSensors"], 2)
        self.assertEqual(coverage["summary"]["lowTrustSensors"], 0)
        self.assertEqual(coverage["summary"]["unsupportedSensors"], 1)
        self.assertEqual(coverage["summary"]["lowTrustShapeFindings"], 0)
        self.assertEqual(coverage_by_name["futureCabinPressureKpa"]["trustTier"], "verified_decoded")
        self.assertEqual(coverage_by_name["futureCabinPressureKpa"]["status"], "unsupported")
        self.assertEqual(coverage_by_name["futureCabinPressureKpa"]["surfaces"], [])
        self.assertEqual(coverage_by_name["futureCabinPressureKpa"]["shapeFindings"], [])

        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)
        text = output.getvalue()
        self.assertIn(
            "[diagnostic-replay] sensor_coverage observed=3 covered=2 low_trust=0 unsupported=1 shape_findings=0",
            text,
        )

    def test_replay_marks_verified_future_sensor_covered_with_model_surfaces(self) -> None:
        states = [
            {
                "type": "vehicle_state",
                "version": 1,
                "wallTimestamp": 1700000800.0,
                "rpm": 1800.0,
                "futureCabinHumidityPct": 44.0,
                "futureCabinPressureKpa": 100.1,
                "sensorTrust": {
                    "futureCabinHumidityPct": {
                        "source": "confirmed_dictionary",
                        "trust": "verified_decoded",
                        "verified": True,
                    },
                    "futureCabinPressureKpa": {
                        "source": "confirmed_dictionary",
                        "trust": "verified_decoded",
                        "verified": True,
                    }
                },
            },
            {
                "type": "vehicle_state",
                "version": 1,
                "wallTimestamp": 1700000800.1,
                "rpm": 1810.0,
                "futureCabinHumidityPct": 45.0,
                "futureCabinPressureKpa": 100.3,
                "sensorTrust": {
                    "futureCabinHumidityPct": {
                        "source": "confirmed_dictionary",
                        "trust": "verified_decoded",
                        "verified": True,
                    },
                    "futureCabinPressureKpa": {
                        "source": "confirmed_dictionary",
                        "trust": "verified_decoded",
                        "verified": True,
                    }
                },
            },
        ]
        report = run_diagnostic_replay(
            states,
            fault_recorder_enabled=False,
            baseline_profiles=default_vehicle_baseline_profiles()
            + [
                BaselineProfile(
                    name="future_cabin_pressure",
                    target="futureCabinPressureKpa",
                    unit="kPa",
                    features=(
                        BaselineFeature("rpm", 250.0),
                        BaselineFeature("futureCabinHumidityPct", 5.0),
                    ),
                )
            ],
            transition_profiles=default_transition_profiles()
            + [
                TransitionProfile(
                    name="startup_future_cabin_pressure_response",
                    event_type="first_fire",
                    target="futureCabinPressureKpa",
                    unit="kPa",
                    reference_signals=("rpm", "futureCabinHumidityPct"),
                )
            ],
        )

        _assert_replay_report_contract(self, report)
        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in report["sensorCoverage"]["sensors"]
        }
        future_sensor = coverage_by_name["futureCabinPressureKpa"]
        future_context_sensor = coverage_by_name["futureCabinHumidityPct"]
        self.assertEqual(report["summary"]["anomalyFrames"], 0)
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["summary"]["faultEvents"], 0)
        self.assertEqual(future_sensor["trustTier"], "verified_decoded")
        self.assertEqual(future_sensor["status"], "covered")
        self.assertEqual(
            future_sensor["surfaces"],
            ["learned_baseline_target", "transition_target"],
        )
        self.assertEqual(
            future_sensor["reason"],
            "Observed with deterministic signal-health, baseline, transition, or source-agreement coverage.",
        )
        self.assertNotIn("signal_health", future_sensor["surfaces"])
        self.assertEqual(future_context_sensor["trustTier"], "verified_decoded")
        self.assertEqual(future_context_sensor["status"], "covered")
        self.assertEqual(
            future_context_sensor["surfaces"],
            ["learned_baseline_context", "transition_reference"],
        )
        self.assertEqual(
            future_context_sensor["reason"],
            "Observed with deterministic signal-health, baseline, transition, or source-agreement coverage.",
        )
        self.assertNotIn("signal_health", future_context_sensor["surfaces"])
        surface_summary = report["sensorCoverage"]["surfaceSummary"]
        self.assertEqual(surface_summary["gapSensors"], [])
        self.assertEqual(
            surface_summary["surfaceSensors"]["learned_baseline_target"],
            ["futureCabinPressureKpa"],
        )
        self.assertEqual(
            surface_summary["surfaceSensors"]["learned_baseline_context"],
            ["futureCabinHumidityPct", "rpm"],
        )
        self.assertEqual(
            surface_summary["surfaceSensors"]["transition_target"],
            ["futureCabinPressureKpa", "rpm"],
        )
        self.assertEqual(
            surface_summary["surfaceSensors"]["transition_reference"],
            ["futureCabinHumidityPct", "rpm"],
        )

    def test_replay_reports_low_trust_flat_shape_evidence_without_diagnostic_truth(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_low_trust_flat.jsonl"
        candidate_signals = Path(ROOT) / "tests" / "fixtures" / "diagnostic_candidate_signals_low_trust.json"
        with tempfile.TemporaryDirectory() as temp_dir:
            report = run_diagnostic_replay(
                load_state_jsonl(fixture),
                fault_recorder_dir=temp_dir,
                diagnostic_candidate_signals=load_diagnostic_candidate_signals(candidate_signals),
            )

        _assert_replay_report_contract(self, report)
        self.assertEqual(report["summary"]["anomalyFrames"], 0)
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["summary"]["faultEvents"], 0)
        self.assertEqual(report["faultEventSummaries"], [])
        self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
        self.assertEqual(report["lastDiagnostic"]["status"], "nominal")
        self.assertEqual(report["lastDiagnostic"]["activeFindings"], [])

        coverage = report["sensorCoverage"]
        self.assertEqual(coverage["summary"]["lowTrustShapeFindings"], 1)
        self.assertEqual(len(coverage["shapeFindings"]), 1)
        shape_finding = coverage["shapeFindings"][0]
        self.assertEqual(shape_finding["source"], "sensorCoverage")
        self.assertEqual(shape_finding["subject"], "autoWheelSpeedKph")
        self.assertEqual(shape_finding["code"], "low_trust_candidate_stuck_flat")
        self.assertEqual(shape_finding["severity"], "info")
        self.assertNotIn("low_trust_candidate_stuck_flat", report["summary"]["findingCounts"])

        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in coverage["sensors"]
        }
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["shapeFindings"], [shape_finding])

        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)
        text = output.getvalue()
        self.assertIn(
            "[diagnostic-replay] sensor_coverage observed=3 covered=2 low_trust=1 unsupported=0 shape_findings=1",
            text,
        )
        self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

    def test_replay_reports_low_trust_noisy_shape_evidence_without_diagnostic_truth(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_low_trust_noisy.jsonl"
        candidate_signals = Path(ROOT) / "tests" / "fixtures" / "diagnostic_candidate_signals_low_trust.json"
        with tempfile.TemporaryDirectory() as temp_dir:
            report = run_diagnostic_replay(
                load_state_jsonl(fixture),
                fault_recorder_dir=temp_dir,
                diagnostic_candidate_signals=load_diagnostic_candidate_signals(candidate_signals),
            )

        _assert_replay_report_contract(self, report)
        self.assertEqual(report["summary"]["anomalyFrames"], 0)
        self.assertEqual(report["summary"]["findingCounts"], {})
        self.assertEqual(report["summary"]["faultEvents"], 0)
        self.assertEqual(report["faultEventSummaries"], [])
        self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
        self.assertEqual(report["lastDiagnostic"]["status"], "nominal")
        self.assertEqual(report["lastDiagnostic"]["activeFindings"], [])

        coverage = report["sensorCoverage"]
        self.assertEqual(coverage["summary"]["lowTrustShapeFindings"], 1)
        self.assertEqual(len(coverage["shapeFindings"]), 1)
        shape_finding = coverage["shapeFindings"][0]
        self.assertEqual(shape_finding["source"], "sensorCoverage")
        self.assertEqual(shape_finding["subject"], "autoWheelSpeedKph")
        self.assertEqual(shape_finding["code"], "low_trust_candidate_noisy_or_flapping")
        self.assertEqual(shape_finding["severity"], "info")
        self.assertEqual(shape_finding["details"]["shape"], "noisy_or_flapping")
        self.assertGreaterEqual(shape_finding["details"]["directionChanges"], 5)
        self.assertNotIn("low_trust_candidate_noisy_or_flapping", report["summary"]["findingCounts"])

        coverage_by_name = {
            sensor["name"]: sensor
            for sensor in coverage["sensors"]
        }
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
        self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["shapeFindings"], [shape_finding])

        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)
        text = output.getvalue()
        self.assertIn(
            "[diagnostic-replay] sensor_coverage observed=3 covered=2 low_trust=1 unsupported=0 shape_findings=1",
            text,
        )
        self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

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

    def test_replay_caps_transition_findings_without_truncating_detection_truth(self) -> None:
        states = []
        for start_index in range(4):
            states.extend(_healthy_start(start_index * 10.0))
        for start_index in range(30):
            states.extend(_flat_maf_start(50.0 + start_index * 10.0))

        report = run_diagnostic_replay(
            states,
            frame_period_seconds=0.3,
            fault_recorder_enabled=False,
            vehicle_baseline_enabled=False,
        )

        _assert_replay_report_contract(self, report)
        self.assertEqual(len(report["transitionFindings"]), TRANSITION_FINDINGS_REPORT_LIMIT)
        self.assertEqual(report["summary"]["findingCounts"]["startup_maf_response_no_response"], 30)
        self.assertEqual(report["summary"]["findingCounts"]["startup_maf_response_stuck_flat"], 30)
        self.assertGreater(sum(report["summary"]["findingCounts"].values()), len(report["transitionFindings"]))

        baseline_states = []
        for start_index in range(4):
            baseline_states.extend(_healthy_start(start_index * 10.0))
        baseline_states.extend(_flat_maf_start(50.0))
        baseline_report = run_diagnostic_replay(
            baseline_states,
            frame_period_seconds=0.3,
            fault_recorder_enabled=False,
            vehicle_baseline_enabled=False,
        )
        self.assertGreater(len(baseline_report["transitionFindings"]), 0)
        self.assertEqual(
            report["transitionFindings"][0]["code"],
            baseline_report["transitionFindings"][0]["code"],
        )
        self.assertEqual(
            report["transitionFindings"][0]["subject"],
            baseline_report["transitionFindings"][0]["subject"],
        )

        self.assertEqual(report["healthVerdict"]["kind"], "vehicle_health_verdict")
        self.assertNotIn("transitionFindings", report["healthVerdict"])

    def test_load_state_jsonl_rejects_non_object_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "states.jsonl"
            path.write_text(json.dumps([1, 2, 3]) + "\n", encoding="utf-8")

            with self.assertRaises(ValueError):
                load_state_jsonl(path)

    def test_load_state_jsonl_skips_blank_lines_and_preserves_objects(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "states.jsonl"
            first = {"type": "vehicle_state", "version": 1, "speedKph": 12.5}
            second = {"type": "vehicle_state", "version": 1, "rpm": 1800.0}
            path.write_text(
                "\n"
                "  \n"
                f"{json.dumps(first, sort_keys=True)}\n"
                "\t\n"
                f"{json.dumps(second, sort_keys=True)}\n"
                "\n",
                encoding="utf-8",
            )

            self.assertEqual(load_state_jsonl(path), [first, second])

    def test_cli_rejects_non_object_jsonl_without_outputs(self) -> None:
        _assert_cli_rejects_jsonl_without_outputs(
            self,
            state_text=json.dumps([1, 2, 3]) + "\n",
            expected_error_fragments=("line 1 is not a JSON object",),
        )

    def test_cli_rejects_mixed_valid_then_non_object_jsonl_without_partial_outputs(self) -> None:
        valid_state = _state(speed=12.0, gps_speed=12.5)
        _assert_cli_rejects_jsonl_without_outputs(
            self,
            state_text=f"{json.dumps(valid_state, sort_keys=True)}\n{json.dumps([1, 2, 3])}\n",
            expected_error_fragments=("line 2 is not a JSON object",),
        )

    def test_cli_rejects_mixed_valid_then_malformed_jsonl_without_partial_outputs(self) -> None:
        valid_state = _state(speed=12.0, gps_speed=12.5)
        _assert_cli_rejects_jsonl_without_outputs(
            self,
            state_text=f"{json.dumps(valid_state, sort_keys=True)}\n{{\"type\": \"vehicle_state\"\n",
            expected_error_fragments=("Expecting", "line 1 column"),
        )

    def test_cli_rejects_malformed_jsonl_without_outputs(self) -> None:
        _assert_cli_rejects_jsonl_without_outputs(
            self,
            state_text='{"type": "vehicle_state", "version": 1\n',
            expected_error_fragments=("Expecting", "line 1 column"),
        )

    def test_cli_rejects_missing_jsonl_without_outputs(self) -> None:
        _assert_cli_rejects_jsonl_without_outputs(
            self,
            state_text=None,
            state_filename="missing-states.jsonl",
            expected_error_fragments=("No such file or directory", "missing-states.jsonl"),
        )

    def test_print_summary_includes_prioritized_baseline_next_steps(self) -> None:
        report = {
            "summary": {
                "frames": 4,
                "anomalyFrames": 0,
                "worstSeverity": "ok",
                "faultEvents": 0,
                "findingCounts": {},
            },
            "healthVerdict": {"verdict": {"label": "insufficient_evidence"}},
            "baselineCoverage": {
                "summary": {
                    "score": 0.2,
                    "strongScenarios": 0,
                    "weakScenarios": 1,
                    "missingScenarios": 2,
                    "nextSteps": [
                        {
                            "scenario": "road_cruise",
                            "status": "missing",
                            "nextStep": "Capture steady road or highway driving after the engine is warm.",
                        }
                    ],
                }
            },
        }

        output = StringIO()
        with redirect_stdout(output):
            _print_summary(report)

        text = output.getvalue()
        self.assertIn("[diagnostic-replay] next baseline steps:", text)
        self.assertIn("road_cruise (missing)", text)
        self.assertIn("Capture steady road or highway driving", text)

    def test_diagnostic_replay_fixture_index_matches_reports(self) -> None:
        index_path = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_fixture_index.json"
        index = json.loads(index_path.read_text(encoding="utf-8"))
        self.assertEqual(index["version"], 1)
        self.assertEqual(index["kind"], "bbb_diagnostic_replay_fixture_index")
        fixtures = index["fixtures"]
        self.assertIsInstance(fixtures, list)
        self.assertGreater(len(fixtures), 0)

        indexed_paths: set[Path] = set()
        for entry in fixtures:
            fixture_path = Path(ROOT) / entry["path"]
            self.assertTrue(fixture_path.exists(), str(fixture_path))
            self.assertNotIn(fixture_path, indexed_paths)
            indexed_paths.add(fixture_path)
            self.assertIsInstance(entry["proves"], str)
            self.assertTrue(entry["proves"])

            expected = entry["expected"]
            states = load_state_jsonl(fixture_path)
            inline_trust_metadata_sensors = _inline_trust_metadata_sensor_names(states)
            candidate_signals = None
            if entry.get("diagnosticCandidateSignals"):
                candidate_path = Path(ROOT) / entry["diagnosticCandidateSignals"]
                self.assertTrue(candidate_path.exists(), str(candidate_path))
                candidate_signals = load_diagnostic_candidate_signals(candidate_path)
            replay_options = entry.get("replayOptions", {})
            self.assertIsInstance(replay_options, dict)
            for option_name, option_value in replay_options.items():
                self.assertIn(
                    option_name,
                    {
                        "signalHealthEnabled",
                        "vehicleBaselineEnabled",
                        "transitionMonitorEnabled",
                        "faultRecorderEnabled",
                    },
                )
                self.assertIsInstance(option_value, bool)
            baseline_profiles = default_vehicle_baseline_profiles() + _fixture_baseline_profiles(self, entry)
            transition_profiles = default_transition_profiles() + _fixture_transition_profiles(self, entry)
            with tempfile.TemporaryDirectory() as temp_dir:
                enriched_path = Path(temp_dir) / "enriched.jsonl"
                report = run_diagnostic_replay(
                    states,
                    fault_recorder_dir=temp_dir,
                    enriched_jsonl=enriched_path,
                    diagnostic_candidate_signals=candidate_signals,
                    fault_recorder_enabled=replay_options.get("faultRecorderEnabled", True),
                    signal_health_enabled=replay_options.get("signalHealthEnabled", True),
                    vehicle_baseline_enabled=replay_options.get("vehicleBaselineEnabled", True),
                    transition_monitor_enabled=replay_options.get("transitionMonitorEnabled", True),
                    baseline_profiles=baseline_profiles,
                    transition_profiles=transition_profiles,
                )
                _assert_replay_report_contract(self, report)
                self.assertEqual(len(states), expected["frames"])
                self.assertEqual(report["summary"]["frames"], expected["frames"])
                self.assertEqual(report["summary"]["anomalyFrames"], expected["anomalyFrames"])
                self.assertEqual(report["summary"]["faultEvents"], expected["faultEvents"])
                self.assertEqual(report["diagnosticStatusCounts"], expected["diagnosticStatusCounts"])
                self.assertEqual(report["severityCounts"], expected["severityCounts"])
                self.assertEqual(report["summary"]["findingCounts"], expected["findingCounts"])
                self.assertEqual(report["healthVerdict"]["verdict"]["label"], expected["healthVerdictLabel"])
                if "healthVerdictAbstainRequired" in expected:
                    self.assertEqual(
                        report["healthVerdict"]["abstain"]["required"],
                        expected["healthVerdictAbstainRequired"],
                    )
                self.assertEqual(report["transitionBaselineReady"], expected["transitionBaselineReady"])
                expected_last_diagnostic = expected["lastDiagnostic"]
                last_diagnostic = report["lastDiagnostic"]
                if expected_last_diagnostic is None:
                    self.assertEqual(expected["frames"], 0)
                    self.assertIsNone(last_diagnostic)
                else:
                    self.assertIsNotNone(last_diagnostic)
                    _assert_diagnostic_matches_fixture_expectation(self, last_diagnostic, expected_last_diagnostic)

                enriched_states = [
                    json.loads(line)
                    for line in enriched_path.read_text(encoding="utf-8").splitlines()
                    if line.strip()
                ]
                self.assertEqual(len(enriched_states), expected["frames"])
                enriched_status_counts = _diagnostic_field_counts(enriched_states, "status")
                enriched_severity_counts = _diagnostic_field_counts(enriched_states, "severity")
                self.assertEqual(enriched_status_counts, expected["diagnosticStatusCounts"])
                self.assertEqual(enriched_status_counts, report["diagnosticStatusCounts"])
                self.assertEqual(enriched_severity_counts, expected["severityCounts"])
                self.assertEqual(enriched_severity_counts, report["severityCounts"])
                if expected_last_diagnostic is None:
                    self.assertEqual(enriched_states, [])
                else:
                    final_enriched_diagnostic = enriched_states[-1]["_diagnostic"]
                    _assert_normalized_diagnostic_contract(self, final_enriched_diagnostic)
                    _assert_diagnostic_matches_fixture_expectation(
                        self,
                        final_enriched_diagnostic,
                        expected_last_diagnostic,
                    )
                    self.assertEqual(final_enriched_diagnostic, last_diagnostic)
                expected_first_anomaly = expected["firstAnomaly"]
                anomaly_rows = [
                    (index, state)
                    for index, state in enumerate(enriched_states)
                    if state["_diagnostic"]["status"] == "anomaly_detected"
                ]
                if expected_first_anomaly is None:
                    self.assertIsNone(report["firstAnomaly"])
                    self.assertEqual(anomaly_rows, [])
                else:
                    first_anomaly = report["firstAnomaly"]
                    self.assertIsNotNone(first_anomaly)
                    self.assertEqual(first_anomaly["frame"], expected_first_anomaly["frame"])
                    _assert_diagnostic_matches_fixture_expectation(
                        self,
                        first_anomaly["diagnostic"],
                        expected_first_anomaly,
                    )
                    self.assertGreater(len(anomaly_rows), 0)
                    first_anomaly_frame, first_anomaly_state = anomaly_rows[0]
                    self.assertEqual(first_anomaly_frame, expected_first_anomaly["frame"])
                    self.assertEqual(first_anomaly_frame, first_anomaly["frame"])
                    first_enriched_diagnostic = first_anomaly_state["_diagnostic"]
                    _assert_normalized_diagnostic_contract(self, first_enriched_diagnostic)
                    _assert_diagnostic_matches_fixture_expectation(
                        self,
                        first_enriched_diagnostic,
                        expected_first_anomaly,
                    )
                    self.assertEqual(first_enriched_diagnostic, first_anomaly["diagnostic"])
                expected_signal_monitor = expected["signalMonitor"]
                self.assertEqual(
                    {
                        "enabled": report["signalMonitor"]["enabled"],
                        "ok": report["signalMonitor"]["ok"],
                        "faultCount": report["signalMonitor"]["faultCount"],
                        "watching": report["signalMonitor"]["watching"],
                    },
                    expected_signal_monitor,
                )
                expected_sensor_coverage = expected["sensorCoverage"]
                self.assertIsInstance(expected_sensor_coverage, dict)
                for key, expected_value in expected_sensor_coverage.items():
                    self.assertIn(key, report["sensorCoverage"]["summary"])
                    self.assertEqual(report["sensorCoverage"]["summary"][key], expected_value)
                if "sensorCoverageSurfaceSummary" in expected:
                    _assert_sensor_coverage_surface_summary_expectation(
                        self,
                        report["sensorCoverage"]["surfaceSummary"],
                        expected["sensorCoverageSurfaceSummary"],
                    )
                expected_sensor_coverage_sensors = expected.get("sensorCoverageSensors", {})
                self.assertIsInstance(expected_sensor_coverage_sensors, dict)
                coverage_by_name = {
                    sensor["name"]: sensor
                    for sensor in report["sensorCoverage"]["sensors"]
                }
                absent_sensor_coverage_sensors = expected.get("absentSensorCoverageSensors", [])
                self.assertIsInstance(absent_sensor_coverage_sensors, list)
                for sensor_name in absent_sensor_coverage_sensors:
                    self.assertIsInstance(sensor_name, str)
                    self.assertNotIn(sensor_name, coverage_by_name)
                    metadata_only_sensors = set(inline_trust_metadata_sensors)
                    if candidate_signals is not None:
                        metadata_only_sensors.update(candidate_signals.get("candidates", {}))
                    self.assertIn(sensor_name, metadata_only_sensors)
                ignored_sensor_coverage_sensors = expected.get("ignoredSensorCoverageSensors", [])
                self.assertIsInstance(ignored_sensor_coverage_sensors, list)
                for sensor_name in ignored_sensor_coverage_sensors:
                    self.assertIsInstance(sensor_name, str)
                    self.assertNotIn(sensor_name, coverage_by_name)
                    self.assertTrue(
                        any(_read_state_path(state, sensor_name) is not _MISSING for state in states),
                        f"{sensor_name} must be present in at least one fixture row",
                    )
                for sensor_name, expected_sensor in expected_sensor_coverage_sensors.items():
                    self.assertIn(sensor_name, coverage_by_name)
                    self.assertIsInstance(expected_sensor, dict)
                    actual_sensor = coverage_by_name[sensor_name]
                    for key in ("sampleCount", "status", "trustTier", "surfaces"):
                        if key in expected_sensor:
                            self.assertEqual(actual_sensor[key], expected_sensor[key])
                    if "reason" in expected_sensor:
                        self.assertEqual(actual_sensor["reason"], expected_sensor["reason"])
                    if "shapeFindingSuppressedReason" in expected_sensor:
                        self.assertEqual(
                            actual_sensor.get("shapeFindingSuppressedReason"),
                            expected_sensor["shapeFindingSuppressedReason"],
                        )
                    if "shapeFindingCodes" in expected_sensor:
                        self.assertEqual(
                            [
                                finding["code"]
                                for finding in actual_sensor["shapeFindings"]
                            ],
                            expected_sensor["shapeFindingCodes"],
                        )
                    if "shapeFindingCandidateIds" in expected_sensor:
                        expected_candidate_ids = expected_sensor["shapeFindingCandidateIds"]
                        self.assertIsInstance(expected_candidate_ids, list)
                        self.assertEqual(
                            [
                                finding["details"]["candidateId"]
                                for finding in actual_sensor["shapeFindings"]
                            ],
                            expected_candidate_ids,
                        )
                        if candidate_signals is not None:
                            candidate = candidate_signals.get("candidates", {}).get(sensor_name)
                            self.assertIsInstance(candidate, dict)
                            for candidate_id in expected_candidate_ids:
                                self.assertEqual(candidate_id, candidate["candidateId"])
                    if "shapeFindingTrustMetadataSources" in expected_sensor:
                        expected_sources = expected_sensor["shapeFindingTrustMetadataSources"]
                        self.assertIsInstance(expected_sources, list)
                        self.assertEqual(
                            [
                                finding["details"]["trustMetadataSource"]
                                for finding in actual_sensor["shapeFindings"]
                            ],
                            expected_sources,
                        )
                if "baselineCoverage" in expected:
                    expected_baseline_coverage = expected["baselineCoverage"]
                    self.assertIsInstance(expected_baseline_coverage, dict)
                    steady_state_expectations = expected_baseline_coverage.get("steadyState", {})
                    self.assertIsInstance(steady_state_expectations, dict)
                    baseline_steady_state = report["baselineCoverage"]["steadyState"]
                    for key, expected_value in steady_state_expectations.items():
                        self.assertIn(key, baseline_steady_state)
                        self.assertEqual(baseline_steady_state[key], expected_value)
                if "transitionCoverage" in expected:
                    expected_transition_coverage = expected["transitionCoverage"]
                    self.assertIsInstance(expected_transition_coverage, dict)
                    for key, expected_value in expected_transition_coverage.items():
                        self.assertIn(key, report["transitionCoverage"])
                        self.assertEqual(report["transitionCoverage"][key], expected_value)
                if "cliSummaryIncludes" in expected or "cliSummaryExcludes" in expected:
                    output = StringIO()
                    with redirect_stdout(output):
                        _print_summary(report)
                    summary_text = output.getvalue()
                    cli_summary_includes = expected.get("cliSummaryIncludes", [])
                    self.assertIsInstance(cli_summary_includes, list)
                    for snippet in cli_summary_includes:
                        self.assertIsInstance(snippet, str)
                        self.assertIn(snippet, summary_text)
                    cli_summary_excludes = expected.get("cliSummaryExcludes", [])
                    self.assertIsInstance(cli_summary_excludes, list)
                    for snippet in cli_summary_excludes:
                        self.assertIsInstance(snippet, str)
                        self.assertNotIn(snippet, summary_text)
                expected_fault_recorder = expected["faultRecorder"]
                self.assertEqual(report["faultRecorder"]["enabled"], expected_fault_recorder["enabled"])
                self.assertEqual(report["faultRecorder"]["writes"], expected_fault_recorder["writes"])
                self.assertEqual(
                    bool(report["faultRecorder"]["lastEventPath"]),
                    expected_fault_recorder["hasLastEvent"],
                )

        fixture_paths = set((Path(ROOT) / "tests" / "fixtures").glob("diagnostic_replay_*.jsonl"))
        self.assertEqual(indexed_paths, fixture_paths)

    def test_cli_replays_representative_fixture_end_to_end(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_representative.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=12", text)
            self.assertIn("[diagnostic-replay] signal_health enabled=true ok=true faults=0", text)
            self.assertIn("[diagnostic-replay] next baseline steps:", text)
            self.assertIn("shift_response (missing)", text)
            self.assertIn("[diagnostic-replay] vehicle_baseline enabled=true ready_models=none", text)
            self.assertIn("[diagnostic-replay] transitions enabled=true baseline_ready=false findings=0 ready_models=none", text)
            self.assertIn("transition guidance: capture repeated known-good transition events", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["frames"], 12)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertFalse(report["baselineCoverage"]["summary"]["ready"])
            self.assertGreaterEqual(len(report["baselineCoverage"]["summary"]["nextSteps"]), 3)
            self.assertEqual(
                len(enriched_path.read_text(encoding="utf-8").strip().splitlines()),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_future_sensor_fixture_with_candidate_export(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_low_trust.jsonl"
        candidate_signals = Path(ROOT) / "tests" / "fixtures" / "diagnostic_candidate_signals_low_trust.json"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--diagnostic-candidate-signals",
                        str(candidate_signals),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=1 unsupported=1 shape_findings=0",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            sidecar_candidates = load_diagnostic_candidate_signals(candidate_signals)["candidates"]
            self.assertIn("autoBoostGuessKpa", sidecar_candidates)
            self.assertNotIn("autoBoostGuessKpa", coverage_by_name)
            self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
            self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
            self.assertEqual(coverage_by_name["mysteryVoltage"]["status"], "unsupported")
            self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")

    def test_cli_replays_future_sensor_row_trust_without_candidate_export(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_row_trust.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=5 covered=2 low_trust=2 unsupported=1 shape_findings=0",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            self.assertEqual(coverage_by_name["autoBoostGuessKpa"]["status"], "low_trust")
            self.assertEqual(coverage_by_name["autoBoostGuessKpa"]["trustTier"], "low_trust_candidate")
            self.assertEqual(
                coverage_by_name["autoBoostGuessKpa"]["reason"],
                "Observed as low-trust diagnostic evidence only; needs promotion, rules, or known-good baseline support.",
            )
            self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
            self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
            self.assertEqual(coverage_by_name["mysteryVoltage"]["status"], "unsupported")
            self.assertEqual(
                coverage_by_name["mysteryVoltage"]["reason"],
                "Observed but no deterministic rule, learned model, transition profile, or low-trust policy covers it yet.",
            )
            self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)

    def test_cli_excludes_inline_trust_metadata_without_observed_sensor_values(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_inline_trust_unobserved.jsonl"
        states = load_state_jsonl(fixture)
        self.assertEqual(
            _inline_trust_metadata_sensor_names(states),
            {"autoBoostGuessKpa", "autoWheelSpeedKph"},
        )
        for state in states:
            self.assertNotIn("autoBoostGuessKpa", state)
            self.assertNotIn("autoWheelSpeedKph", state)

        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=2 covered=2 low_trust=0 unsupported=0 shape_findings=0",
                text,
            )

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            self.assertEqual(set(coverage_by_name), {"rpm", "speedKph"})
            self.assertNotIn("autoBoostGuessKpa", coverage_by_name)
            self.assertNotIn("autoWheelSpeedKph", coverage_by_name)
            self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)
            self.assertEqual(report["sensorCoverage"]["shapeFindings"], [])
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])

    def test_cli_replays_row_level_low_trust_shape_without_candidate_export(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_row_trust_shape.jsonl"
        for state in load_state_jsonl(fixture):
            boost_candidate = state["_health"]["diagnosticCandidateSignals"]["candidates"]["autoBoostGuessKpa"]
            wheel_trust = state["_health"]["sensorTrust"]["autoWheelSpeedKph"]
            self.assertEqual(boost_candidate["candidateId"], "0x330:b8:l8:u")
            self.assertNotIn("trustMetadataSource", boost_candidate)
            self.assertEqual(wheel_trust["candidateId"], "0x221:b16:l16:little:u")
            self.assertNotIn("trustMetadataSource", wheel_trust)
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=8", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=2 unsupported=0 shape_findings=2",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            shape_findings = report["sensorCoverage"]["shapeFindings"]
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            self.assertEqual(
                [
                    (
                        finding["subject"],
                        finding["code"],
                        finding["details"]["candidateId"],
                        finding["details"]["trustMetadataSource"],
                    )
                    for finding in shape_findings
                ],
                [
                    ("autoBoostGuessKpa", "low_trust_candidate_stuck_flat", "0x330:b8:l8:u", "_health.diagnosticCandidateSignals"),
                    ("autoWheelSpeedKph", "low_trust_candidate_noisy_or_flapping", "0x221:b16:l16:little:u", "_health.sensorTrust"),
                ],
            )

    def test_cli_replays_future_sensor_top_level_trust_without_candidate_export(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_top_level_trust.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=5 covered=2 low_trust=2 unsupported=1 shape_findings=0",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            self.assertEqual(coverage_by_name["autoTorqueGuessNm"]["status"], "low_trust")
            self.assertEqual(coverage_by_name["autoTorqueGuessNm"]["trustTier"], "low_trust_candidate")
            self.assertEqual(
                coverage_by_name["autoTorqueGuessNm"]["reason"],
                "Observed as low-trust diagnostic evidence only; needs promotion, rules, or known-good baseline support.",
            )
            self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["status"], "low_trust")
            self.assertEqual(coverage_by_name["autoWheelSpeedKph"]["trustTier"], "low_trust_candidate")
            self.assertEqual(coverage_by_name["mysteryVoltage"]["status"], "unsupported")
            self.assertEqual(
                coverage_by_name["mysteryVoltage"]["reason"],
                "Observed but no deterministic rule, learned model, transition profile, or low-trust policy covers it yet.",
            )
            self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)

    def test_cli_replays_top_level_low_trust_shape_without_candidate_export(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_top_level_trust_shape.jsonl"
        for state in load_state_jsonl(fixture):
            torque_candidate = state["diagnosticCandidateSignals"]["candidates"]["autoTorqueGuessNm"]
            wheel_trust = state["sensorTrust"]["autoWheelSpeedKph"]
            self.assertEqual(torque_candidate["candidateId"], "0x331:b16:l16:u")
            self.assertNotIn("trustMetadataSource", torque_candidate)
            self.assertEqual(wheel_trust["candidateId"], "0x221:b16:l16:little:u")
            self.assertNotIn("trustMetadataSource", wheel_trust)
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=8", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=2 unsupported=0 shape_findings=2",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            shape_findings = report["sensorCoverage"]["shapeFindings"]
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            self.assertEqual(
                [
                    (
                        finding["subject"],
                        finding["code"],
                        finding["details"]["candidateId"],
                        finding["details"]["trustMetadataSource"],
                    )
                    for finding in shape_findings
                ],
                [
                    ("autoTorqueGuessNm", "low_trust_candidate_stuck_flat", "0x331:b16:l16:u", "diagnosticCandidateSignals"),
                    ("autoWheelSpeedKph", "low_trust_candidate_noisy_or_flapping", "0x221:b16:l16:little:u", "sensorTrust"),
                ],
            )

    def test_cli_suppresses_low_trust_shape_without_candidate_id_provenance(self) -> None:
        fixture = (
            Path(ROOT)
            / "tests"
            / "fixtures"
            / "diagnostic_replay_future_sensor_low_trust_missing_candidate_id_shape.jsonl"
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=8", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=2 unsupported=0 shape_findings=0",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)
            self.assertEqual(report["sensorCoverage"]["shapeFindings"], [])
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            for sensor_name in ("autoTorqueGuessNm", "autoWheelSpeedKph"):
                sensor = coverage_by_name[sensor_name]
                self.assertEqual(sensor["status"], "low_trust")
                self.assertEqual(sensor["trustTier"], "low_trust_candidate")
                self.assertEqual(sensor["shapeFindings"], [])
                self.assertEqual(
                    sensor["shapeFindingSuppressedReason"],
                    LOW_TRUST_SHAPE_MISSING_CANDIDATE_ID_REASON,
                )

    def test_cli_suppresses_sidecar_low_trust_shape_without_candidate_id_provenance(self) -> None:
        fixture = (
            Path(ROOT)
            / "tests"
            / "fixtures"
            / "diagnostic_replay_future_sensor_sidecar_low_trust_missing_candidate_id_shape.jsonl"
        )
        candidate_signals_path = (
            Path(ROOT)
            / "tests"
            / "fixtures"
            / "diagnostic_candidate_signals_low_trust_missing_candidate_id.json"
        )
        candidate_signals = load_diagnostic_candidate_signals(candidate_signals_path)
        self.assertNotIn("candidateId", candidate_signals["candidates"]["autoTorqueGuessNm"])
        self.assertEqual(candidate_signals["candidates"]["autoWheelSpeedKph"]["candidateId"].strip(), "")

        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--diagnostic-candidate-signals",
                        str(candidate_signals_path),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=8", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=2 unsupported=0 shape_findings=0",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertEqual(report["sensorCoverage"]["summary"]["lowTrustShapeFindings"], 0)
            self.assertEqual(report["sensorCoverage"]["shapeFindings"], [])
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            for sensor_name in ("autoTorqueGuessNm", "autoWheelSpeedKph"):
                sensor = coverage_by_name[sensor_name]
                self.assertEqual(sensor["status"], "low_trust")
                self.assertEqual(sensor["trustTier"], "low_trust_candidate")
                self.assertEqual(sensor["shapeFindings"], [])
                self.assertEqual(
                    sensor["shapeFindingSuppressedReason"],
                    LOW_TRUST_SHAPE_MISSING_CANDIDATE_ID_REASON,
                )

    def test_cli_replays_low_trust_shape_evidence_without_diagnostic_truth(self) -> None:
        candidate_signals = Path(ROOT) / "tests" / "fixtures" / "diagnostic_candidate_signals_low_trust.json"
        cases = [
            (
                "flat",
                "diagnostic_replay_future_sensor_low_trust_flat.jsonl",
                [("autoWheelSpeedKph", "low_trust_candidate_stuck_flat")],
                "[diagnostic-replay] sensor_coverage observed=3 covered=2 low_trust=1 unsupported=0 shape_findings=1",
            ),
            (
                "noisy",
                "diagnostic_replay_future_sensor_low_trust_noisy.jsonl",
                [("autoWheelSpeedKph", "low_trust_candidate_noisy_or_flapping")],
                "[diagnostic-replay] sensor_coverage observed=3 covered=2 low_trust=1 unsupported=0 shape_findings=1",
            ),
            (
                "multi",
                "diagnostic_replay_future_sensor_low_trust_multi_shape.jsonl",
                [
                    ("autoBoostGuessKpa", "low_trust_candidate_stuck_flat"),
                    ("autoWheelSpeedKph", "low_trust_candidate_noisy_or_flapping"),
                ],
                "[diagnostic-replay] sensor_coverage observed=4 covered=2 low_trust=2 unsupported=0 shape_findings=2",
            ),
        ]
        for case_name, fixture_name, expected_shape_findings, expected_sensor_coverage_line in cases:
            with self.subTest(case=case_name), tempfile.TemporaryDirectory() as temp_dir:
                fixture = Path(ROOT) / "tests" / "fixtures" / fixture_name
                report_path = Path(temp_dir) / "report.json"
                enriched_path = Path(temp_dir) / "enriched.jsonl"
                fault_dir = Path(temp_dir) / "faults"
                output = StringIO()

                with redirect_stdout(output):
                    exit_code = main(
                        [
                            "--state-jsonl",
                            str(fixture),
                            "--diagnostic-candidate-signals",
                            str(candidate_signals),
                            "--report",
                            str(report_path),
                            "--enriched-jsonl",
                            str(enriched_path),
                            "--fault-dir",
                            str(fault_dir),
                        ]
                    )

                self.assertEqual(exit_code, 0)
                text = output.getvalue()
                self.assertIn("[diagnostic-replay] frames=8", text)
                self.assertIn("anomaly_frames=0", text)
                self.assertIn("fault_events=0", text)
                self.assertIn("verdict=insufficient_evidence", text)
                self.assertIn(expected_sensor_coverage_line, text)
                self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

                report = json.loads(report_path.read_text(encoding="utf-8"))
                _assert_replay_report_contract(self, report)
                _assert_enriched_finding_counts_match_report(self, report, enriched_path)
                enriched_states = [
                    json.loads(line)
                    for line in enriched_path.read_text(encoding="utf-8").splitlines()
                    if line.strip()
                ]
                coverage_by_name = {
                    sensor["name"]: sensor
                    for sensor in report["sensorCoverage"]["sensors"]
                }
                shape_findings = report["sensorCoverage"]["shapeFindings"]
                self.assertEqual(report["summary"]["anomalyFrames"], 0)
                self.assertEqual(report["summary"]["findingCounts"], {})
                self.assertEqual(report["summary"]["faultEvents"], 0)
                self.assertEqual(report["faultEventPaths"], [])
                self.assertEqual(report["faultEventSummaries"], [])
                self.assertEqual(report["lastDiagnostic"]["status"], "nominal")
                self.assertEqual(report["lastDiagnostic"]["activeFindings"], [])
                self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
                self.assertTrue(report["healthVerdict"]["abstain"]["required"])
                self.assertEqual(
                    [(finding["subject"], finding["code"]) for finding in shape_findings],
                    expected_shape_findings,
                )
                for expected_subject, expected_shape_code in expected_shape_findings:
                    matching_findings = [
                        finding
                        for finding in shape_findings
                        if finding["subject"] == expected_subject and finding["code"] == expected_shape_code
                    ]
                    self.assertEqual(len(matching_findings), 1)
                    self.assertEqual(matching_findings[0]["source"], "sensorCoverage")
                    self.assertEqual(matching_findings[0]["severity"], "info")
                    self.assertEqual(coverage_by_name[expected_subject]["status"], "low_trust")
                    self.assertEqual(coverage_by_name[expected_subject]["shapeFindings"], matching_findings)
                self.assertEqual(
                    {state["_diagnostic"]["status"] for state in enriched_states},
                    {"nominal"},
                )
                self.assertEqual(
                    {
                        tuple(
                            finding["code"]
                            for finding in state["_diagnostic"]["activeFindings"]
                        )
                        for state in enriched_states
                    },
                    {()},
                )

    def test_cli_replays_verified_future_sensor_without_surfaces_as_unsupported(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_future_sensor_verified_unsupported.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("fault_events=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn(
                "[diagnostic-replay] sensor_coverage observed=3 covered=2 low_trust=0 unsupported=1 shape_findings=0",
                text,
            )
            self.assertIn("low-trust or unsupported sensors need promotion, rules, or learned fixtures", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            coverage_by_name = {
                sensor["name"]: sensor
                for sensor in report["sensorCoverage"]["sensors"]
            }
            future_sensor = coverage_by_name["futureCabinPressureKpa"]
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["faultEventPaths"], [])
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertEqual(report["lastDiagnostic"]["status"], "nominal")
            self.assertEqual(report["lastDiagnostic"]["activeFindings"], [])
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertTrue(report["healthVerdict"]["abstain"]["required"])
            self.assertEqual(future_sensor["trustTier"], "verified_decoded")
            self.assertEqual(future_sensor["status"], "unsupported")
            self.assertEqual(future_sensor["surfaces"], [])
            self.assertEqual(future_sensor["shapeFindings"], [])
            self.assertEqual(
                future_sensor["reason"],
                "Observed but no deterministic rule, learned model, transition profile, or low-trust policy covers it yet.",
            )
            self.assertEqual(
                {state["_diagnostic"]["status"] for state in enriched_states},
                {"nominal"},
            )
            self.assertEqual(
                {
                    tuple(
                        finding["code"]
                        for finding in state["_diagnostic"]["activeFindings"]
                    )
                    for state in enriched_states
                },
                {()},
            )

    def test_cli_replays_speed_disagreement_with_signal_health_disabled(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_speed_disagreement.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                        "--disable-signal-health",
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn("[diagnostic-replay] signal_health enabled=false ok=true faults=0 watching=none", text)
            self.assertIn("signal health guidance: signal health monitor disabled for this replay", text)
            self.assertNotIn("source_disagreement", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertFalse(report["signalMonitor"]["enabled"])
            self.assertTrue(report["signalMonitor"]["ok"])
            self.assertEqual(report["signalMonitor"]["watching"], [])
            self.assertEqual(report["signalMonitor"]["faultCount"], 0)
            self.assertEqual(report["summary"]["frames"], 2)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertEqual(report["faultEventPaths"], [])
            self.assertEqual(report["faultEventSummaries"], [])

            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(
                len(enriched_states),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )
            self.assertFalse(enriched_states[-1]["_health"]["signalMonitor"]["enabled"])
            self.assertNotIn("signalFaults", enriched_states[-1]["_health"])
            self.assertEqual(enriched_states[-1]["_diagnostic"]["status"], "nominal")

    def test_cli_replays_representative_fixture_with_vehicle_baseline_disabled(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_representative.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                        "--disable-vehicle-baseline",
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=12", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn("[diagnostic-replay] vehicle_baseline enabled=false ready_models=none", text)
            self.assertIn("vehicle baseline guidance: vehicle baseline disabled for this replay", text)
            self.assertNotIn("[diagnostic-replay] next baseline steps:", text)
            self.assertNotIn("Drive warm with varied RPM and throttle so MAF can learn comparable buckets", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertFalse(report["vehicleBaseline"]["enabled"])
            self.assertFalse(report["baselineCoverage"]["summary"]["ready"])
            self.assertEqual(report["baselineCoverage"]["steadyState"]["readyModels"], [])
            self.assertGreater(len(report["baselineCoverage"]["summary"]["nextSteps"]), 0)
            self.assertEqual(report["summary"]["frames"], 12)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertEqual(report["faultEventPaths"], [])
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertEqual(
                len(enriched_path.read_text(encoding="utf-8").strip().splitlines()),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_transition_fixture_end_to_end(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_transition_flat_maf.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=30", text)
            self.assertIn("anomaly_frames=1", text)
            self.assertIn("verdict=anomaly_likely", text)
            self.assertIn(
                "[diagnostic-replay] transitions enabled=true baseline_ready=true findings=2 ready_models=startup_maf_response,startup_map_response",
                text,
            )
            self.assertIn("transition guidance: inspect transitionFindings", text)
            self.assertIn("startup_maf_response_no_response: 1", text)
            self.assertIn("startup_maf_response_stuck_flat: 1", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["frames"], 30)
            self.assertEqual(report["summary"]["anomalyFrames"], 1)
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertEqual(report["summary"]["findingCounts"]["startup_maf_response_no_response"], 1)
            self.assertEqual(report["summary"]["findingCounts"]["startup_maf_response_stuck_flat"], 1)
            self.assertTrue(report["transitionBaselineReady"])
            self.assertEqual(_scenario_status(report, "startup_response"), "strong")
            transition_codes = {finding["code"] for finding in report["transitionFindings"]}
            self.assertEqual(
                transition_codes,
                {"startup_maf_response_no_response", "startup_maf_response_stuck_flat"},
            )
            self.assertIn("startup_maf_response", report["transitionCoverage"]["readyModels"])
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertEqual(len(report["faultEventPaths"]), 1)
            self.assertEqual(len(report["faultEventSummaries"]), 1)
            self.assertEqual(
                len(enriched_path.read_text(encoding="utf-8").strip().splitlines()),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_shift_rpm_transition_fixture_end_to_end(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_transition_flat_rpm_shift.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=36", text)
            self.assertIn("anomaly_frames=1", text)
            self.assertIn("verdict=anomaly_likely", text)
            self.assertIn(
                "[diagnostic-replay] transitions enabled=true baseline_ready=true findings=2 ready_models=shift_rpm_response",
                text,
            )
            self.assertIn("transition guidance: inspect transitionFindings", text)
            self.assertIn("shift_rpm_response_no_response: 1", text)
            self.assertIn("shift_rpm_response_stuck_flat: 1", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["frames"], 36)
            self.assertEqual(report["summary"]["anomalyFrames"], 1)
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertEqual(report["summary"]["findingCounts"]["shift_rpm_response_no_response"], 1)
            self.assertEqual(report["summary"]["findingCounts"]["shift_rpm_response_stuck_flat"], 1)
            self.assertTrue(report["transitionBaselineReady"])
            self.assertEqual(_scenario_status(report, "shift_response"), "strong")
            transition_codes = {finding["code"] for finding in report["transitionFindings"]}
            self.assertEqual(
                transition_codes,
                {"shift_rpm_response_no_response", "shift_rpm_response_stuck_flat"},
            )
            self.assertIn("shift_rpm_response", report["transitionCoverage"]["readyModels"])
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertEqual(len(report["faultEventPaths"]), 1)
            self.assertEqual(len(report["faultEventSummaries"]), 1)
            self.assertEqual(
                len(enriched_path.read_text(encoding="utf-8").strip().splitlines()),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_transition_fixture_with_monitor_disabled(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_transition_flat_maf.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                        "--disable-transition-monitor",
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=30", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn("[diagnostic-replay] transitions enabled=false baseline_ready=false findings=0 ready_models=none", text)
            self.assertIn("transition guidance: transition monitor disabled for this replay", text)
            self.assertNotIn("transition guidance: capture repeated known-good transition events", text)
            self.assertNotIn("transition guidance: inspect transitionFindings", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertFalse(report["transitionMonitor"]["enabled"])
            self.assertFalse(report["transitionBaselineReady"])
            self.assertEqual(report["transitionFindings"], [])
            self.assertEqual(report["transitionCoverage"]["readyModels"], [])
            self.assertEqual(report["transitionCoverage"]["windowsScored"], 0)
            self.assertEqual(report["transitionCoverage"]["windowsLearned"], 0)
            self.assertEqual(report["summary"]["frames"], 30)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertEqual(report["faultEventPaths"], [])
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertEqual(
                len(enriched_path.read_text(encoding="utf-8").strip().splitlines()),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_with_vehicle_baseline_and_transition_monitor_disabled(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_transition_flat_maf.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                        "--disable-vehicle-baseline",
                        "--disable-transition-monitor",
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=30", text)
            self.assertIn("anomaly_frames=0", text)
            self.assertIn("verdict=insufficient_evidence", text)
            self.assertIn("[diagnostic-replay] vehicle_baseline enabled=false ready_models=none", text)
            self.assertIn("vehicle baseline guidance: vehicle baseline disabled for this replay", text)
            self.assertIn("[diagnostic-replay] transitions enabled=false baseline_ready=false findings=0 ready_models=none", text)
            self.assertIn("transition guidance: transition monitor disabled for this replay", text)
            self.assertNotIn("[diagnostic-replay] next baseline steps:", text)
            self.assertNotIn("transition guidance: capture repeated known-good transition events", text)
            self.assertNotIn("transition guidance: inspect transitionFindings", text)
            self.assertNotIn("startup_maf_response_no_response", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertFalse(report["vehicleBaseline"]["enabled"])
            self.assertFalse(report["transitionMonitor"]["enabled"])
            self.assertFalse(report["baselineCoverage"]["summary"]["ready"])
            self.assertEqual(report["baselineCoverage"]["steadyState"]["readyModels"], [])
            self.assertEqual(report["baselineCoverage"]["transitions"]["readyModels"], [])
            self.assertGreater(len(report["baselineCoverage"]["summary"]["nextSteps"]), 0)
            self.assertFalse(report["transitionBaselineReady"])
            self.assertEqual(report["transitionFindings"], [])
            self.assertEqual(report["transitionCoverage"]["readyModels"], [])
            self.assertEqual(report["transitionCoverage"]["windowsScored"], 0)
            self.assertEqual(report["transitionCoverage"]["windowsLearned"], 0)
            self.assertEqual(report["summary"]["frames"], 30)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["summary"]["findingCounts"], {})
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "insufficient_evidence")
            self.assertEqual(report["faultEventPaths"], [])
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertEqual(
                len(enriched_path.read_text(encoding="utf-8").strip().splitlines()),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_valid_rows_with_surrounding_blank_lines_in_order(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            state_path = Path(temp_dir) / "states.jsonl"
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            first = _state(speed=12.0, gps_speed=12.5)
            second = _state(speed=12.5, gps_speed=13.0)
            state_path.write_text(
                "\n"
                "  \n"
                f"{json.dumps(first, sort_keys=True)}\n"
                "\t\n"
                f"{json.dumps(second, sort_keys=True)}\n"
                "\n",
                encoding="utf-8",
            )
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(state_path),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=0", text)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["frames"], 2)
            self.assertEqual(report["summary"]["anomalyFrames"], 0)
            self.assertEqual(report["summary"]["faultEvents"], 0)

            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(len(enriched_states), 2)
            self.assertEqual([state["speedKph"] for state in enriched_states], [12.0, 12.5])
            self.assertEqual([state["gps"]["speedKph"] for state in enriched_states], [12.5, 13.0])
            self.assertEqual([state["_diagnostic"]["status"] for state in enriched_states], ["nominal", "nominal"])
            self.assertFalse(fault_dir.exists() and any(fault_dir.iterdir()))

    def test_cli_replays_empty_jsonl_with_abstaining_report_contract(self) -> None:
        _assert_cli_replays_zero_frame_jsonl(self, state_text="")

    def test_cli_replays_whitespace_only_jsonl_with_abstaining_report_contract(self) -> None:
        _assert_cli_replays_zero_frame_jsonl(self, state_text="\n  \n\t\n")

    def test_cli_replays_anomaly_fixture_and_writes_fault_event(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_speed_disagreement.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=2", text)
            self.assertIn("verdict=anomaly_likely", text)
            self.assertIn("[diagnostic-replay] fault_recorder enabled=true writes=1 last_event=present", text)
            self.assertNotIn("fault recorder guidance: fault recorder disabled for this replay", text)
            self.assertIn(
                "[diagnostic-replay] signal_health enabled=true ok=false faults=1 watching=coolantC,fuelPct,rpm,speedKph",
                text,
            )
            self.assertIn("source_disagreement: 2", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["anomalyFrames"], 2)
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertEqual(report["summary"]["findingCounts"]["source_disagreement"], 2)
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertTrue(report["faultRecorder"]["enabled"])
            self.assertEqual(report["faultRecorder"]["writes"], 1)
            self.assertTrue(report["signalMonitor"]["enabled"])
            self.assertFalse(report["signalMonitor"]["ok"])
            self.assertEqual(report["signalMonitor"]["faultCount"], 1)
            self.assertEqual(report["signalMonitor"]["watching"], ["coolantC", "fuelPct", "rpm", "speedKph"])
            self.assertEqual(report["lastDiagnostic"]["status"], "anomaly_detected")
            self.assertEqual(report["lastDiagnostic"]["findingCount"], report["signalMonitor"]["faultCount"])
            diagnostic_codes = [
                finding["code"]
                for finding in report["lastDiagnostic"]["activeFindings"]
                if isinstance(finding, dict)
            ]
            self.assertEqual(diagnostic_codes, ["source_disagreement"])
            self.assertEqual(len(report["faultEventPaths"]), 1)
            self.assertEqual(len(report["faultEventSummaries"]), 1)
            self.assertEqual(report["faultRecorder"]["lastEventPath"], report["faultEventPaths"][0])
            summary = report["faultEventSummaries"][0]
            self.assertEqual(summary["kind"], "bbb_fault_event_summary")
            self.assertEqual(summary["eventRef"]["path"], report["faultRecorder"]["lastEventPath"])
            self.assertEqual(summary["primaryFinding"]["code"], diagnostic_codes[0])
            self.assertEqual(summary["triggerContext"]["diagnosticStatus"], "anomaly_detected")
            self.assertTrue(summary["responsibleUse"]["notRepairDirective"])
            self.assertNotIn("replace", summary["customerSummary"].lower())
            fault_event = json.loads(Path(report["faultEventPaths"][0]).read_text(encoding="utf-8"))
            self.assertEqual(fault_event["kind"], "bbb_fault_event")
            self.assertEqual(fault_event["faults"][0]["code"], "source_disagreement")
            self.assertEqual(fault_event["triggerState"]["_diagnostic"]["status"], "anomaly_detected")
            self.assertEqual(fault_event["triggerState"]["_diagnostic"]["findingCount"], 1)
            self.assertEqual(fault_event["triggerState"]["_diagnostic"]["activeFindings"][0]["code"], diagnostic_codes[0])
            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(enriched_states[-1]["_diagnostic"]["activeFindings"][0]["code"], diagnostic_codes[0])
            self.assertEqual(
                len(enriched_states[-1]["_health"]["signalFaults"]),
                report["signalMonitor"]["faultCount"],
            )
            self.assertEqual(
                len(enriched_states),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )

    def test_cli_replays_suppressed_duplicates_without_losing_detection_truth(self) -> None:
        states = [_state(speed=0.0, gps_speed=55.0 + (index % 2)) for index in range(12)]
        with tempfile.TemporaryDirectory() as temp_dir:
            state_path = Path(temp_dir) / "states.jsonl"
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            state_path.write_text(
                "".join(json.dumps(state, sort_keys=True) + "\n" for state in states),
                encoding="utf-8",
            )
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(state_path),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=12", text)
            self.assertIn("anomaly_frames=12", text)
            self.assertIn("fault_events=1", text)
            self.assertIn("[diagnostic-replay] fault_recorder enabled=true writes=1 last_event=present", text)
            self.assertIn("source_disagreement: 12", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["frames"], 12)
            self.assertEqual(report["summary"]["anomalyFrames"], 12)
            self.assertEqual(report["summary"]["findingCounts"]["source_disagreement"], 12)
            self.assertEqual(report["diagnosticStatusCounts"]["anomaly_detected"], 12)
            self.assertEqual(report["summary"]["faultEvents"], 1)
            self.assertEqual(report["faultRecorder"]["writes"], 1)
            self.assertEqual(report["faultRecorder"]["lastEventPath"], report["faultEventPaths"][0])
            self.assertEqual(len(report["faultEventPaths"]), 1)
            self.assertEqual(len(report["faultEventSummaries"]), 1)
            self.assertEqual(report["faultEventSummaries"][0]["primaryFinding"]["code"], "source_disagreement")

            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(len(enriched_states), len(states))
            suppressed = [
                state["_health"]["faultRecorder"]
                for state in enriched_states
                if state["_health"]["faultRecorder"].get("suppressed")
            ]
            self.assertEqual(len(suppressed), 11)
            self.assertEqual(enriched_states[-1]["_diagnostic"]["status"], "anomaly_detected")
            self.assertTrue(enriched_states[-1]["_health"]["faultRecorder"]["suppressed"])
            self.assertEqual(
                enriched_states[-1]["_health"]["faultRecorder"]["suppressedFingerprint"],
                "speedKph:source_disagreement:warning",
            )
            self.assertEqual(
                [state["_diagnostic"]["activeFindings"][0]["code"] for state in enriched_states],
                ["source_disagreement"] * len(states),
            )

    def test_cli_replays_suppression_expiry_fixture_end_to_end(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_suppression_expiry.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=3", text)
            self.assertIn("anomaly_frames=3", text)
            self.assertIn("fault_events=2", text)
            self.assertIn("[diagnostic-replay] fault_recorder enabled=true writes=2 last_event=present", text)
            self.assertIn("source_disagreement: 3", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["anomalyFrames"], 3)
            self.assertEqual(report["summary"]["findingCounts"]["source_disagreement"], 3)
            self.assertEqual(report["summary"]["faultEvents"], 2)
            self.assertEqual(len(report["faultEventPaths"]), 2)
            self.assertEqual(len(report["faultEventSummaries"]), 2)
            self.assertEqual(report["faultRecorder"]["writes"], 2)
            self.assertEqual(report["faultRecorder"]["lastEventPath"], report["faultEventPaths"][-1])

            persisted_events = [
                json.loads(Path(path).read_text(encoding="utf-8"))
                for path in report["faultEventPaths"]
            ]
            event_monotonic_times = [event["recorder"]["monotonicTimestamp"] for event in persisted_events]
            self.assertEqual(event_monotonic_times, [0.0, 12.0])
            for path, summary, event in zip(report["faultEventPaths"], report["faultEventSummaries"], persisted_events):
                self.assertEqual(summary["eventRef"]["path"], path)
                self.assertEqual(summary["primaryFinding"]["code"], "source_disagreement")
                self.assertEqual(summary["triggerContext"]["diagnosticStatus"], "anomaly_detected")
                self.assertEqual(event["faults"][0]["code"], summary["primaryFinding"]["code"])
                self.assertEqual(event["triggerState"]["_diagnostic"]["status"], "anomaly_detected")
                self.assertEqual(event["triggerState"]["_diagnostic"]["activeFindings"][0]["code"], "source_disagreement")

            enriched_states = [
                json.loads(line)
                for line in enriched_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(len(enriched_states), 3)
            recorder_health = [state["_health"]["faultRecorder"] for state in enriched_states]
            self.assertNotIn("suppressed", recorder_health[0])
            self.assertTrue(recorder_health[1]["suppressed"])
            self.assertNotIn("suppressed", recorder_health[2])
            self.assertEqual([health["writes"] for health in recorder_health], [1, 1, 2])

    def test_cli_replays_anomaly_fixture_with_fault_recorder_disabled(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_speed_disagreement.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            enriched_path = Path(temp_dir) / "enriched.jsonl"
            fault_dir = Path(temp_dir) / "faults"
            output = StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    [
                        "--state-jsonl",
                        str(fixture),
                        "--report",
                        str(report_path),
                        "--enriched-jsonl",
                        str(enriched_path),
                        "--fault-dir",
                        str(fault_dir),
                        "--disable-fault-recorder",
                    ]
                )

            self.assertEqual(exit_code, 0)
            text = output.getvalue()
            self.assertIn("[diagnostic-replay] frames=2", text)
            self.assertIn("anomaly_frames=2", text)
            self.assertIn("fault_events=0", text)
            self.assertIn("verdict=anomaly_likely", text)
            self.assertIn("[diagnostic-replay] fault_recorder enabled=false writes=0 last_event=none", text)
            self.assertIn("fault recorder guidance: fault recorder disabled for this replay", text)
            self.assertIn("[diagnostic-replay] signal_health enabled=true ok=false faults=1", text)
            self.assertIn("source_disagreement: 2", text)

            report = json.loads(report_path.read_text(encoding="utf-8"))
            _assert_replay_report_contract(self, report)
            _assert_enriched_finding_counts_match_report(self, report, enriched_path)
            self.assertEqual(report["summary"]["anomalyFrames"], 2)
            self.assertEqual(report["summary"]["faultEvents"], 0)
            self.assertEqual(report["summary"]["findingCounts"]["source_disagreement"], 2)
            self.assertEqual(report["healthVerdict"]["verdict"]["label"], "anomaly_likely")
            self.assertEqual(report["lastDiagnostic"]["status"], "anomaly_detected")
            self.assertEqual(report["lastDiagnostic"]["activeFindings"][0]["code"], "source_disagreement")
            self.assertEqual(report["faultEventPaths"], [])
            self.assertEqual(report["faultEventSummaries"], [])
            self.assertFalse(report["faultRecorder"]["enabled"])
            self.assertEqual(report["faultRecorder"]["writes"], 0)
            self.assertIsNone(report["faultRecorder"]["lastEventPath"])
            self.assertFalse(fault_dir.exists() and any(fault_dir.iterdir()))

            enriched_lines = enriched_path.read_text(encoding="utf-8").strip().splitlines()
            self.assertEqual(
                len(enriched_lines),
                len(fixture.read_text(encoding="utf-8").strip().splitlines()),
            )
            last_state = json.loads(enriched_lines[-1])
            self.assertEqual(last_state["_diagnostic"]["status"], "anomaly_detected")
            self.assertFalse(last_state["_health"]["faultRecorder"]["enabled"])
            self.assertEqual(last_state["_health"]["faultRecorder"]["writes"], 0)

    def test_missing_fault_event_path_produces_summary_error_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            missing_path = str(Path(temp_dir) / "missing-fault-event.json")
            report = {
                "version": 1,
                "kind": "bbb_diagnostic_replay_report",
                "summary": {
                    "frames": 2,
                    "anomalyFrames": 2,
                    "limitedFrames": 0,
                    "staleFrames": 0,
                    "worstSeverity": "warning",
                    "findingCounts": {"source_disagreement": 2},
                    "faultEvents": 1,
                },
                "diagnosticStatusCounts": {"anomaly_detected": 2},
                "severityCounts": {"warning": 2},
                "firstAnomaly": {
                    "frame": 0,
                    "timestamp": 1700000100.0,
                    "diagnostic": _diagnostic(
                        status="anomaly_detected",
                        severity="warning",
                        summary="CAN/TOP-LEVEL SPEED DISAGREES WITH GPS SPEED",
                        finding_count=1,
                        active_findings=[
                            {
                                "source": "signalMonitor",
                                "subject": "speedKph",
                                "code": "source_disagreement",
                                "severity": "warning",
                                "message": "CAN/top-level speed disagrees with GPS speed.",
                                "confidence": 0.9,
                                "details": {"gpsSpeedKph": 55.0, "deltaKph": 55.0},
                            }
                        ],
                    ),
                },
                "lastDiagnostic": _diagnostic(
                    status="anomaly_detected",
                    severity="warning",
                    summary="CAN/TOP-LEVEL SPEED DISAGREES WITH GPS SPEED",
                    finding_count=1,
                    active_findings=[
                        {
                            "source": "signalMonitor",
                            "subject": "speedKph",
                            "code": "source_disagreement",
                            "severity": "warning",
                            "message": "CAN/top-level speed disagrees with GPS speed.",
                            "confidence": 0.9,
                            "details": {"gpsSpeedKph": 56.0, "deltaKph": 56.0},
                        }
                    ],
                ),
                "faultEventPaths": [missing_path],
                "faultEventSummaries": _summarize_fault_events([missing_path]),
                "healthVerdict": _health_verdict(label="anomaly_likely", ok=False, abstain_required=False),
                "signalMonitor": {
                    "enabled": True,
                    "ok": False,
                    "watching": ["coolantC", "fuelPct", "rpm", "speedKph"],
                    "faultCount": 1,
                },
                "sensorCoverage": _sensor_coverage_report(),
                "baselineCoverage": _baseline_coverage_report(),
                "vehicleBaseline": _vehicle_baseline_snapshot(),
                "transitionMonitor": _transition_monitor_snapshot(),
                "transitionCoverage": _transition_monitor_snapshot()["coverage"],
                "transitionFindings": [],
                "transitionBaselineReady": False,
                "faultRecorder": {
                    "enabled": True,
                    "outputDir": temp_dir,
                    "bufferSeconds": 20.0,
                    "bufferFrames": 2,
                    "maxEventFiles": 500,
                    "maxTotalBytes": 64 * 1024 * 1024,
                    "writes": 1,
                    "lastEventPath": missing_path,
                    "lastError": None,
                },
            }

        _assert_replay_report_contract(self, report)
        self.assertEqual(report["faultEventSummaries"][0]["kind"], "bbb_fault_event_summary_error")
        self.assertEqual(report["faultEventSummaries"][0]["eventRef"]["path"], missing_path)
        self.assertIn("No such file", report["faultEventSummaries"][0]["error"])


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


def _assert_cli_replays_zero_frame_jsonl(test: unittest.TestCase, *, state_text: str) -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        state_path = Path(temp_dir) / "states.jsonl"
        report_path = Path(temp_dir) / "report.json"
        enriched_path = Path(temp_dir) / "enriched.jsonl"
        fault_dir = Path(temp_dir) / "faults"
        state_path.write_text(state_text, encoding="utf-8")
        output = StringIO()

        with redirect_stdout(output):
            exit_code = main(
                [
                    "--state-jsonl",
                    str(state_path),
                    "--report",
                    str(report_path),
                    "--enriched-jsonl",
                    str(enriched_path),
                    "--fault-dir",
                    str(fault_dir),
                ]
            )

        test.assertEqual(exit_code, 0)
        text = output.getvalue()
        test.assertIn("[diagnostic-replay] frames=0", text)
        test.assertIn("anomaly_frames=0", text)
        test.assertIn("fault_events=0", text)
        test.assertIn("verdict=capture_limited", text)
        test.assertIn(
            "sensor_coverage observed=0 covered=0 low_trust=0 unsupported=0 "
            "shape_findings=0 coverage_ratio=0.000 gap_ratio=0.000",
            text,
        )
        expected_surface_counts = " ".join(
            f"{surface}=0"
            for surface in SENSOR_COVERAGE_CLI_SURFACE_ORDER
        )
        test.assertIn(f"sensor_surfaces {expected_surface_counts} gaps=0", text)

        report = json.loads(report_path.read_text(encoding="utf-8"))
        _assert_replay_report_contract(test, report)
        test.assertEqual(report["summary"]["frames"], 0)
        test.assertEqual(report["summary"]["anomalyFrames"], 0)
        test.assertEqual(report["summary"]["limitedFrames"], 0)
        test.assertEqual(report["summary"]["staleFrames"], 0)
        test.assertEqual(report["summary"]["worstSeverity"], "ok")
        test.assertEqual(report["summary"]["findingCounts"], {})
        test.assertEqual(report["summary"]["faultEvents"], 0)
        test.assertEqual(report["diagnosticStatusCounts"], {})
        test.assertEqual(report["severityCounts"], {})
        test.assertIsNone(report["firstAnomaly"])
        test.assertIsNone(report["lastDiagnostic"])
        sensor_coverage = report["sensorCoverage"]
        test.assertEqual(
            sensor_coverage["summary"],
            {
                "observedSensors": 0,
                "coveredSensors": 0,
                "lowTrustSensors": 0,
                "unsupportedSensors": 0,
                "lowTrustShapeFindings": 0,
                "coverageRatio": 0.0,
                "gapRatio": 0.0,
            },
        )
        test.assertEqual(sensor_coverage["sensors"], [])
        test.assertEqual(sensor_coverage["shapeFindings"], [])
        surface_summary = sensor_coverage["surfaceSummary"]
        test.assertEqual(
            surface_summary["statusSensors"],
            {
                "covered": [],
                "low_trust": [],
                "unsupported": [],
            },
        )
        test.assertEqual(set(surface_summary["surfaceSensors"]), SENSOR_COVERAGE_SURFACES)
        test.assertEqual(set(surface_summary["surfaceCounts"]), SENSOR_COVERAGE_SURFACES)
        for surface in SENSOR_COVERAGE_SURFACES:
            test.assertEqual(surface_summary["surfaceSensors"][surface], [])
            test.assertEqual(surface_summary["surfaceCounts"][surface], 0)
        test.assertEqual(surface_summary["gapSensors"], [])
        test.assertEqual(report["faultEventPaths"], [])
        test.assertEqual(report["faultEventSummaries"], [])
        test.assertTrue(report["healthVerdict"]["abstain"]["required"])
        test.assertEqual(report["healthVerdict"]["abstain"]["recommendedLabel"], "capture_limited")
        test.assertEqual(report["healthVerdict"]["verdict"]["label"], "capture_limited")
        test.assertIsNone(report["healthVerdict"]["verdict"]["ok"])
        test.assertFalse(report["baselineCoverage"]["summary"]["ready"])
        test.assertEqual(enriched_path.read_text(encoding="utf-8"), "")
        test.assertFalse(fault_dir.exists() and any(fault_dir.iterdir()))


def _assert_cli_rejects_jsonl_without_outputs(
    test: unittest.TestCase,
    *,
    state_text: str | None,
    state_filename: str = "states.jsonl",
    expected_error_fragments: tuple[str, ...],
) -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        state_path = Path(temp_dir) / state_filename
        report_path = Path(temp_dir) / "report.json"
        enriched_path = Path(temp_dir) / "enriched.jsonl"
        fault_dir = Path(temp_dir) / "faults"
        if state_text is not None:
            state_path.write_text(state_text, encoding="utf-8")
        stdout = StringIO()
        stderr = StringIO()

        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = main(
                [
                    "--state-jsonl",
                    str(state_path),
                    "--report",
                    str(report_path),
                    "--enriched-jsonl",
                    str(enriched_path),
                    "--fault-dir",
                    str(fault_dir),
                ]
            )

        test.assertEqual(exit_code, 2)
        test.assertEqual(stdout.getvalue(), "")
        error = stderr.getvalue()
        test.assertIn("[diagnostic-replay] failed:", error)
        for fragment in expected_error_fragments:
            test.assertIn(fragment, error)
        test.assertFalse(report_path.exists())
        test.assertFalse(enriched_path.exists())
        test.assertFalse(fault_dir.exists() and any(fault_dir.iterdir()))


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


def _diagnostic(
    *,
    status: str,
    severity: str,
    summary: str,
    finding_count: int = 0,
    active_findings: list[dict] | None = None,
) -> dict:
    return {
        "version": 1,
        "mode": "replay",
        "ok": status != "anomaly_detected",
        "severity": severity,
        "status": status,
        "summary": summary,
        "findingCount": finding_count,
        "activeFindings": active_findings or [],
        "captureQuality": {
            "gpsOk": True,
            "canOk": True,
            "serialOk": True,
            "linkStale": False,
        },
    }


def _assert_replay_report_contract(test: unittest.TestCase, report: dict) -> None:
    test.assertEqual(report["version"], 1)
    test.assertEqual(report["kind"], "bbb_diagnostic_replay_report")
    for key in (
        "summary",
        "diagnosticStatusCounts",
        "severityCounts",
        "firstAnomaly",
        "lastDiagnostic",
        "faultEventPaths",
        "faultEventSummaries",
        "healthVerdict",
        "signalMonitor",
        "sensorCoverage",
        "baselineCoverage",
        "vehicleBaseline",
        "transitionMonitor",
        "transitionCoverage",
        "transitionFindings",
        "transitionBaselineReady",
        "faultRecorder",
    ):
        test.assertIn(key, report)
    summary = report["summary"]
    for key in ("frames", "anomalyFrames", "limitedFrames", "staleFrames", "worstSeverity", "findingCounts", "faultEvents"):
        test.assertIn(key, summary)
    finding_counts = summary["findingCounts"]
    test.assertIsInstance(finding_counts, dict)
    for finding_code, count in finding_counts.items():
        test.assertIsInstance(finding_code, str)
        test.assertTrue(finding_code)
        test.assertIsInstance(count, int)
        test.assertGreaterEqual(count, 0)
    if summary["anomalyFrames"] > 0:
        test.assertGreaterEqual(sum(finding_counts.values()), summary["anomalyFrames"])
    diagnostic_status_counts = report["diagnosticStatusCounts"]
    test.assertIsInstance(diagnostic_status_counts, dict)
    for status, count in diagnostic_status_counts.items():
        test.assertIsInstance(status, str)
        test.assertIsInstance(count, int)
        test.assertGreaterEqual(count, 0)
    test.assertEqual(summary["frames"], sum(diagnostic_status_counts.values()))
    test.assertEqual(summary["anomalyFrames"], diagnostic_status_counts.get("anomaly_detected", 0))
    test.assertEqual(summary["limitedFrames"], diagnostic_status_counts.get("limited", 0))
    test.assertEqual(summary["staleFrames"], diagnostic_status_counts.get("data_stale", 0))
    severity_counts = report["severityCounts"]
    test.assertIsInstance(severity_counts, dict)
    for severity, count in severity_counts.items():
        test.assertIsInstance(severity, str)
        test.assertIsInstance(count, int)
        test.assertGreaterEqual(count, 0)
    test.assertEqual(summary["frames"], sum(severity_counts.values()))
    test.assertIn(summary["worstSeverity"], SEVERITY_ORDER)
    test.assertEqual(summary["worstSeverity"], _worst_report_severity(severity_counts))
    _assert_replay_diagnostic_snapshot_contract(test, report)
    _assert_replay_finding_count_snapshot_contract(test, report)
    _assert_vehicle_health_verdict_contract(test, report["healthVerdict"])
    _assert_signal_monitor_contract(test, report["signalMonitor"])
    _assert_sensor_coverage_contract(test, report["sensorCoverage"])
    _assert_sensor_coverage_shape_findings_report_only(test, report)
    _assert_sensor_coverage_navigation_fields_report_only(test, report)
    _assert_baseline_coverage_contract(test, report["baselineCoverage"])
    _assert_vehicle_baseline_contract(test, report["vehicleBaseline"])
    _assert_transition_surfaces_contract(test, report)
    test.assertEqual(summary["faultEvents"], len(report["faultEventPaths"]))
    test.assertEqual(len(report["faultEventSummaries"]), len(report["faultEventPaths"]))
    for fault_event_path, fault_event_summary in zip(report["faultEventPaths"], report["faultEventSummaries"]):
        test.assertIsInstance(fault_event_path, str)
        test.assertTrue(fault_event_path)
        test.assertIn(
            fault_event_summary["kind"],
            {"bbb_fault_event_summary", "bbb_fault_event_summary_error"},
        )
        if fault_event_summary["kind"] == "bbb_fault_event_summary":
            _assert_fault_event_summary_contract(test, fault_event_summary)
            _assert_fault_event_summary_traceability_contract(test, fault_event_path, fault_event_summary)
        else:
            _assert_fault_event_summary_error_contract(test, fault_event_summary)
        test.assertEqual(fault_event_summary["eventRef"]["path"], fault_event_path)
    _assert_fault_recorder_contract(test, report)


def _worst_report_severity(severity_counts: dict[str, int]) -> str:
    worst = "ok"
    for severity, count in severity_counts.items():
        if count <= 0:
            continue
        normalized = severity if severity in SEVERITY_ORDER else "info"
        if SEVERITY_ORDER[normalized] > SEVERITY_ORDER[worst]:
            worst = normalized
    return worst


def _assert_signal_monitor_contract(test: unittest.TestCase, monitor: dict) -> None:
    test.assertIsInstance(monitor, dict)
    for key in ("enabled", "ok", "watching", "faultCount"):
        test.assertIn(key, monitor)
    test.assertIsInstance(monitor["enabled"], bool)
    test.assertIsInstance(monitor["ok"], bool)
    test.assertIsInstance(monitor["watching"], list)
    for signal in monitor["watching"]:
        test.assertIsInstance(signal, str)
        test.assertTrue(signal)
    test.assertIsInstance(monitor["faultCount"], int)
    test.assertGreaterEqual(monitor["faultCount"], 0)


def _assert_sensor_coverage_contract(test: unittest.TestCase, coverage: dict) -> None:
    test.assertIsInstance(coverage, dict)
    test.assertEqual(coverage["version"], 1)
    test.assertEqual(coverage["kind"], "bbb_sensor_coverage_report")
    summary = coverage["summary"]
    test.assertIsInstance(summary, dict)
    for key in (
        "observedSensors",
        "coveredSensors",
        "lowTrustSensors",
        "unsupportedSensors",
        "lowTrustShapeFindings",
    ):
        test.assertIn(key, summary)
        test.assertIsInstance(summary[key], int)
        test.assertGreaterEqual(summary[key], 0)
    test.assertIn("coverageRatio", summary)
    test.assertIsInstance(summary["coverageRatio"], (int, float))
    test.assertGreaterEqual(summary["coverageRatio"], 0.0)
    test.assertLessEqual(summary["coverageRatio"], 1.0)
    test.assertIn("gapRatio", summary)
    test.assertIsInstance(summary["gapRatio"], (int, float))
    test.assertGreaterEqual(summary["gapRatio"], 0.0)
    test.assertLessEqual(summary["gapRatio"], 1.0)
    sensors = coverage["sensors"]
    test.assertIsInstance(sensors, list)
    shape_findings = coverage["shapeFindings"]
    test.assertIsInstance(shape_findings, list)
    surface_summary = coverage["surfaceSummary"]
    test.assertIsInstance(surface_summary, dict)
    for key in ("statusSensors", "surfaceSensors", "surfaceCounts", "gapSensors"):
        test.assertIn(key, surface_summary)
    status_sensors = surface_summary["statusSensors"]
    surface_sensors = surface_summary["surfaceSensors"]
    surface_counts = surface_summary["surfaceCounts"]
    gap_sensors = surface_summary["gapSensors"]
    test.assertIsInstance(status_sensors, dict)
    test.assertIsInstance(surface_sensors, dict)
    test.assertIsInstance(surface_counts, dict)
    test.assertIsInstance(gap_sensors, list)
    test.assertEqual(summary["lowTrustShapeFindings"], len(shape_findings))
    for finding in shape_findings:
        _assert_normalized_finding_contract(test, finding)
        test.assertEqual(finding["source"], "sensorCoverage")
        test.assertEqual(finding["severity"], "info")
        test.assertIn(finding["code"], SENSOR_COVERAGE_SHAPE_FINDING_CODES)
    test.assertEqual(summary["observedSensors"], len(sensors))
    test.assertEqual(
        summary["coveredSensors"],
        sum(1 for sensor in sensors if sensor.get("status") == "covered"),
    )
    test.assertEqual(
        summary["lowTrustSensors"],
        sum(1 for sensor in sensors if sensor.get("status") == "low_trust"),
    )
    test.assertEqual(
        summary["unsupportedSensors"],
        sum(1 for sensor in sensors if sensor.get("status") == "unsupported"),
    )
    expected_coverage_ratio = (
        round(summary["coveredSensors"] / summary["observedSensors"], 6)
        if summary["observedSensors"]
        else 0.0
    )
    test.assertEqual(summary["coverageRatio"], expected_coverage_ratio)
    expected_gap_ratio = (
        round((summary["lowTrustSensors"] + summary["unsupportedSensors"]) / summary["observedSensors"], 6)
        if summary["observedSensors"]
        else 0.0
    )
    test.assertEqual(summary["gapRatio"], expected_gap_ratio)
    sensor_names_by_status = {
        status: sorted(
            sensor["name"]
            for sensor in sensors
            if sensor.get("status") == status
        )
        for status in ("covered", "low_trust", "unsupported")
    }
    for status, names in sensor_names_by_status.items():
        test.assertIn(status, status_sensors)
        test.assertEqual(status_sensors[status], names)
    test.assertEqual(
        gap_sensors,
        sorted(sensor_names_by_status["low_trust"] + sensor_names_by_status["unsupported"]),
    )
    for surface in SENSOR_COVERAGE_SURFACES:
        test.assertIn(surface, surface_sensors)
        test.assertIn(surface, surface_counts)
        expected_names = sorted(
            sensor["name"]
            for sensor in sensors
            if surface in sensor.get("surfaces", [])
        )
        test.assertEqual(surface_sensors[surface], expected_names)
        test.assertEqual(surface_counts[surface], len(expected_names))
    for names in list(status_sensors.values()) + list(surface_sensors.values()):
        test.assertIsInstance(names, list)
        test.assertEqual(names, sorted(names))
        for name in names:
            test.assertIsInstance(name, str)
            test.assertTrue(name)
    for sensor in sensors:
        test.assertIsInstance(sensor, dict)
        for key in ("name", "sampleCount", "trustTier", "status", "surfaces", "shapeFindings", "reason"):
            test.assertIn(key, sensor)
        test.assertIsInstance(sensor["name"], str)
        test.assertTrue(sensor["name"])
        test.assertIsInstance(sensor["sampleCount"], int)
        test.assertGreater(sensor["sampleCount"], 0)
        test.assertIn(sensor["trustTier"], SENSOR_COVERAGE_TRUST_TIERS)
        test.assertIn(sensor["status"], {"covered", "low_trust", "unsupported"})
        test.assertIsInstance(sensor["surfaces"], list)
        for surface in sensor["surfaces"]:
            test.assertIsInstance(surface, str)
            test.assertTrue(surface)
            test.assertIn(surface, SENSOR_COVERAGE_SURFACES)
        test.assertIsInstance(sensor["shapeFindings"], list)
        for finding in sensor["shapeFindings"]:
            _assert_normalized_finding_contract(test, finding)
            test.assertIn(finding, shape_findings)
            test.assertEqual(finding["source"], "sensorCoverage")
            test.assertEqual(finding["subject"], sensor["name"])
            test.assertEqual(sensor["status"], "low_trust")
            _assert_sensor_coverage_shape_finding_details_contract(test, finding, sensor)
        test.assertIsInstance(sensor["reason"], str)
        test.assertTrue(sensor["reason"])
        test.assertEqual(sensor["reason"], SENSOR_COVERAGE_REASONS[sensor["status"]])
        if sensor["status"] == "covered":
            test.assertNotEqual(sensor["trustTier"], "low_trust_candidate")
            test.assertGreater(len(sensor["surfaces"]), 0)
        elif sensor["status"] == "low_trust":
            test.assertEqual(sensor["trustTier"], "low_trust_candidate")
        else:
            test.assertEqual(sensor["status"], "unsupported")
            test.assertNotEqual(sensor["trustTier"], "low_trust_candidate")
            test.assertEqual(sensor["surfaces"], [])
            test.assertEqual(sensor["shapeFindings"], [])
        if "shapeFindingSuppressedReason" in sensor:
            test.assertEqual(sensor["status"], "low_trust")
            test.assertEqual(sensor["shapeFindings"], [])
            test.assertEqual(
                sensor["shapeFindingSuppressedReason"],
                LOW_TRUST_SHAPE_MISSING_CANDIDATE_ID_REASON,
            )
    per_sensor_shape_findings = [
        finding
        for sensor in sensors
        for finding in sensor["shapeFindings"]
    ]
    test.assertEqual(shape_findings, per_sensor_shape_findings)


def _assert_sensor_coverage_shape_findings_report_only(test: unittest.TestCase, report: dict) -> None:
    shape_codes = {finding["code"] for finding in report["sensorCoverage"]["shapeFindings"]}
    test.assertLessEqual(shape_codes, SENSOR_COVERAGE_SHAPE_FINDING_CODES)
    for code in SENSOR_COVERAGE_SHAPE_FINDING_CODES:
        test.assertNotIn(code, report["summary"]["findingCounts"])

    diagnostics = []
    if report["lastDiagnostic"] is not None:
        diagnostics.append(("lastDiagnostic", report["lastDiagnostic"]))
    if report["firstAnomaly"] is not None:
        diagnostics.append(("firstAnomaly.diagnostic", report["firstAnomaly"]["diagnostic"]))

    for name, diagnostic in diagnostics:
        for finding in diagnostic["activeFindings"]:
            test.assertNotIn(finding["code"], SENSOR_COVERAGE_SHAPE_FINDING_CODES, f"{name} leaked report-only shape finding")
            test.assertNotEqual(finding["source"], "sensorCoverage", f"{name} leaked sensorCoverage evidence into diagnostic truth")


def _assert_sensor_coverage_navigation_fields_report_only(test: unittest.TestCase, report: dict) -> None:
    coverage_summary = report["sensorCoverage"]["summary"]
    surface_summary = report["sensorCoverage"]["surfaceSummary"]
    test.assertIsInstance(coverage_summary, dict)
    test.assertIsInstance(surface_summary, dict)
    report_only_keys = {
        "coverageRatio",
        "gapRatio",
        "surfaceSummary",
        "statusSensors",
        "surfaceSensors",
        "surfaceCounts",
        "gapSensors",
    }
    for key in report_only_keys:
        test.assertNotIn(key, report["summary"]["findingCounts"])

    diagnostics = []
    if report["lastDiagnostic"] is not None:
        diagnostics.append(("lastDiagnostic", report["lastDiagnostic"]))
    if report["firstAnomaly"] is not None:
        diagnostics.append(("firstAnomaly.diagnostic", report["firstAnomaly"]["diagnostic"]))

    for name, diagnostic in diagnostics:
        diagnostic_text = json.dumps(diagnostic, sort_keys=True)
        for key in report_only_keys:
            test.assertNotIn(key, diagnostic_text, f"{name} leaked sensorCoverage report-only field {key}")

    health_verdict_text = json.dumps(report["healthVerdict"], sort_keys=True)
    for key in report_only_keys:
        test.assertNotIn(key, health_verdict_text, f"healthVerdict leaked sensorCoverage report-only field {key}")


def _assert_sensor_coverage_surface_summary_expectation(
    test: unittest.TestCase,
    actual: dict,
    expected: dict,
) -> None:
    test.assertIsInstance(actual, dict)
    test.assertIsInstance(expected, dict)
    test.assertGreater(len(expected), 0)
    for key, expected_value in expected.items():
        test.assertIn(key, actual)
        if key in {"statusSensors", "surfaceSensors", "surfaceCounts"}:
            test.assertIsInstance(expected_value, dict)
            test.assertIsInstance(actual[key], dict)
            for nested_key, nested_expected in expected_value.items():
                test.assertIn(nested_key, actual[key])
                test.assertEqual(actual[key][nested_key], nested_expected)
        else:
            test.assertEqual(actual[key], expected_value)


def _assert_sensor_coverage_shape_finding_details_contract(
    test: unittest.TestCase,
    finding: dict,
    sensor: dict,
) -> None:
    details = finding.get("details")
    test.assertIsInstance(details, dict)
    test.assertIsInstance(details["candidateId"], str)
    test.assertTrue(details["candidateId"])
    test.assertEqual(details["trustTier"], "low_trust_candidate")
    test.assertIn(details["trustMetadataSource"], SENSOR_COVERAGE_TRUST_METADATA_SOURCES)
    test.assertEqual(details["sampleCount"], sensor["sampleCount"])
    test.assertIsInstance(details["durationSec"], (int, float))
    test.assertNotIsInstance(details["durationSec"], bool)
    test.assertGreaterEqual(details["durationSec"], 0.0)
    test.assertIsInstance(details["valueRange"], (int, float))
    test.assertNotIsInstance(details["valueRange"], bool)
    test.assertGreaterEqual(details["valueRange"], 0.0)

    if finding["code"] == "low_trust_candidate_stuck_flat":
        test.assertEqual(details["shape"], "stuck_flat")
        test.assertIsInstance(details["flatLimit"], (int, float))
        test.assertNotIsInstance(details["flatLimit"], bool)
        test.assertGreaterEqual(details["flatLimit"], 0.0)
    else:
        test.assertEqual(finding["code"], "low_trust_candidate_noisy_or_flapping")
        test.assertEqual(details["shape"], "noisy_or_flapping")
        test.assertIsInstance(details["directionChanges"], int)
        test.assertGreater(details["directionChanges"], 0)
        test.assertIsInstance(details["significantSteps"], int)
        test.assertGreater(details["significantSteps"], 0)
        for key in ("stepEpsilon", "noisyRangeLimit"):
            test.assertIsInstance(details[key], (int, float))
            test.assertNotIsInstance(details[key], bool)
            test.assertGreaterEqual(details[key], 0.0)


def _health_verdict(*, label: str, ok: bool | None, abstain_required: bool) -> dict:
    return {
        "version": 1,
        "kind": "vehicle_health_verdict",
        "generatedAt": "2026-05-03T08:15:00+00:00",
        "mode": "replay",
        "vehicleProfile": None,
        "captureRef": {"source": "diagnostic_replay", "durationSec": 0.1},
        "verdict": {
            "label": label,
            "summary": "Synthetic verdict for replay report contract coverage.",
            "ok": ok,
        },
        "coverage": {
            "score": 0.5,
            "confidence": 0.5,
            "observedContexts": ["road_speed_drive"],
            "missingContexts": ["cold_start"],
            "sourceCoverage": {"gps": "good", "can": "not_used", "serial": "not_used"},
            "sampleCounts": {"frames": 2},
            "durationSec": 0.1,
        },
        "confidenceModel": {
            "score": 0.6,
            "evidenceConsistency": 0.8,
            "sourceTrust": 0.9,
            "modelApplicability": 0.7,
            "penalties": [
                {
                    "code": "coverage_partial",
                    "weight": 0.08,
                    "message": "Observed operating coverage was only partial",
                }
            ],
        },
        "evidenceInputs": {
            "captureQuality": {
                "gpsOk": True,
                "canOk": None,
                "serialOk": None,
                "linkStale": False,
            },
            "findingSummary": {
                "worstSeverity": "warning" if ok is False else "ok",
                "activeFindingCount": 1 if ok is False else 0,
                "codes": ["source_disagreement"] if ok is False else [],
            },
            "sourceHealth": {
                "busSilenceSeen": False,
                "canIdDropouts": 0,
                "payloadStuckEvents": 0,
                "decodedSignalStuckEvents": 0,
            },
            "signalHealth": {
                "outOfRangeEvents": 0,
                "impossibleJumpEvents": 0,
                "sourceDisagreementEvents": 1 if ok is False else 0,
            },
            "baselineHealth": {
                "enabled": False,
                "readyModels": [],
                "anomalyCount": 0,
                "modelCount": 0,
            },
            "transitionHealth": {
                "enabled": False,
                "readyModels": [],
                "anomalyCount": 0,
                "modelCount": 0,
                "windowsScored": 0,
                "windowsLearned": 0,
            },
            "anchors": {
                "direct": ["speedKph"],
                "derived": [],
            },
        },
        "abstain": {
            "required": abstain_required,
            "reasons": ["coverage_too_low"] if abstain_required else [],
            "recommendedLabel": label if abstain_required else None,
        },
        "allowedLanguage": {
            "maySay": ["capture limited", "insufficient evidence", "anomaly likely"],
            "mustAvoid": ["guaranteed healthy", "fault free", "safe to operate"],
            "mustIncludeLimitationsWhenPresent": True,
        },
        "limitations": ["Observed conditions were narrower than a full health assessment"],
    }


def _sensor_coverage_report() -> dict:
    return {
        "version": 1,
        "kind": "bbb_sensor_coverage_report",
        "summary": {
            "observedSensors": 2,
            "coveredSensors": 2,
            "lowTrustSensors": 0,
            "unsupportedSensors": 0,
            "lowTrustShapeFindings": 0,
            "coverageRatio": 1.0,
            "gapRatio": 0.0,
        },
        "surfaceSummary": {
            "statusSensors": {
                "covered": ["rpm", "speedKph"],
                "low_trust": [],
                "unsupported": [],
            },
            "surfaceSensors": {
                "signal_health": ["rpm", "speedKph"],
                "source_agreement_anchor": [],
                "learned_baseline_target": [],
                "learned_baseline_context": [],
                "transition_target": [],
                "transition_reference": [],
                "transition_event_input": [],
            },
            "surfaceCounts": {
                "signal_health": 2,
                "source_agreement_anchor": 0,
                "learned_baseline_target": 0,
                "learned_baseline_context": 0,
                "transition_target": 0,
                "transition_reference": 0,
                "transition_event_input": 0,
            },
            "gapSensors": [],
        },
        "sensors": [
            {
                "name": "rpm",
                "sampleCount": 2,
                "trustTier": "verified_decoded",
                "status": "covered",
                "surfaces": ["signal_health"],
                "shapeFindings": [],
                "reason": "Observed with deterministic signal-health, baseline, transition, or source-agreement coverage.",
            },
            {
                "name": "speedKph",
                "sampleCount": 2,
                "trustTier": "verified_decoded",
                "status": "covered",
                "surfaces": ["signal_health"],
                "shapeFindings": [],
                "reason": "Observed with deterministic signal-health, baseline, transition, or source-agreement coverage.",
            },
        ],
        "shapeFindings": [],
    }


def _baseline_coverage_report() -> dict:
    return {
        "version": 1,
        "kind": "baseline_coverage_report",
        "summary": {
            "score": 0.0,
            "statusCounts": {"strong": 0, "weak": 0, "missing": 1},
            "strongScenarios": 0,
            "weakScenarios": 0,
            "missingScenarios": 1,
            "ready": False,
            "nextSteps": [
                {
                    "scenario": "road_cruise",
                    "label": "Road cruise",
                    "status": "missing",
                    "score": 0.0,
                    "nextStep": "Capture steady road or highway driving after the engine is warm.",
                    "missing": {
                        "contexts": ["road_speed_drive", "highway_speed_drive"],
                        "steadyModels": ["intake_airflow", "map_pressure"],
                    },
                }
            ],
        },
        "scenarios": [
            {
                "key": "road_cruise",
                "label": "Road cruise",
                "category": "drive_context",
                "status": "missing",
                "score": 0.0,
                "evidence": {
                    "contexts": [],
                    "steadyModels": [],
                    "transitionModels": [],
                    "eventsSeen": {},
                },
                "missing": {
                    "contexts": ["road_speed_drive", "highway_speed_drive"],
                    "steadyModels": ["intake_airflow", "map_pressure"],
                },
                "nextStep": "Capture steady road or highway driving after the engine is warm.",
            }
        ],
        "operatingContexts": {"observed": [], "missing": ["road_speed_drive", "highway_speed_drive"]},
        "steadyState": {"models": [], "readyModels": []},
        "transitions": {"eventsSeen": {}, "models": [], "readyModels": []},
    }


def _vehicle_baseline_snapshot() -> dict:
    return {
        "enabled": True,
        "storagePath": None,
        "writes": 0,
        "lastError": None,
        "models": [
            {
                "name": "map_pressure",
                "target": "mapKpa",
                "unit": "kPa",
                "status": "waiting",
                "reason": None,
                "confidence": 0.0,
                "ready": False,
                "bucketCount": 0,
                "totalSamples": 0,
                "lastBucket": None,
                "activeAnomalies": 0,
            }
        ],
    }


def _transition_monitor_snapshot() -> dict:
    return {
        "enabled": True,
        "ok": True,
        "storagePath": None,
        "activeEvent": None,
        "coverage": {
            "eventsSeen": {},
            "windowsScored": 0,
            "windowsLearned": 0,
            "pendingWindows": 0,
            "readyModels": [],
        },
        "models": [
            {
                "name": "startup_maf_response",
                "eventType": "first_fire",
                "target": "mafGps",
                "unit": "g/s",
                "signalTier": 0,
                "signalTierName": "trusted_anchor",
                "ready": False,
                "windows": 0,
                "firstSeen": None,
                "lastSeen": None,
                "eventCounts": {},
                "metrics": {},
            }
        ],
        "findings": [],
        "lastError": None,
    }


def _assert_replay_diagnostic_snapshot_contract(test: unittest.TestCase, report: dict) -> None:
    summary = report["summary"]
    frames = summary["frames"]
    anomaly_frames = summary["anomalyFrames"]
    test.assertIsInstance(frames, int)
    test.assertGreaterEqual(frames, 0)
    test.assertIsInstance(anomaly_frames, int)
    test.assertGreaterEqual(anomaly_frames, 0)
    test.assertLessEqual(anomaly_frames, frames)

    last_diagnostic = report["lastDiagnostic"]
    first_anomaly = report["firstAnomaly"]
    if frames == 0:
        test.assertIsNone(last_diagnostic)
        test.assertIsNone(first_anomaly)
        test.assertEqual(anomaly_frames, 0)
        return

    _assert_normalized_diagnostic_contract(test, last_diagnostic)
    test.assertIn(last_diagnostic["status"], report["diagnosticStatusCounts"])

    if anomaly_frames == 0:
        test.assertIsNone(first_anomaly)
        return

    test.assertIsInstance(first_anomaly, dict)
    for key in ("frame", "timestamp", "diagnostic"):
        test.assertIn(key, first_anomaly)
    test.assertIsInstance(first_anomaly["frame"], int)
    test.assertGreaterEqual(first_anomaly["frame"], 0)
    test.assertLess(first_anomaly["frame"], frames)
    test.assertLessEqual(first_anomaly["frame"], frames - anomaly_frames)
    test.assertIsInstance(first_anomaly["timestamp"], (int, float))
    _assert_normalized_diagnostic_contract(test, first_anomaly["diagnostic"])
    test.assertEqual(first_anomaly["diagnostic"]["status"], "anomaly_detected")
    test.assertFalse(first_anomaly["diagnostic"]["ok"])
    test.assertIn(first_anomaly["diagnostic"]["severity"], {"warning", "error"})
    test.assertGreater(first_anomaly["diagnostic"]["findingCount"], 0)


def _assert_replay_finding_count_snapshot_contract(test: unittest.TestCase, report: dict) -> None:
    finding_counts = report["summary"]["findingCounts"]
    diagnostics = []
    if report["lastDiagnostic"] is not None:
        diagnostics.append(("lastDiagnostic", report["lastDiagnostic"]))
    if report["firstAnomaly"] is not None:
        diagnostics.append(("firstAnomaly.diagnostic", report["firstAnomaly"]["diagnostic"]))

    for name, diagnostic in diagnostics:
        active_findings = diagnostic["activeFindings"]
        if not finding_counts:
            test.assertEqual(active_findings, [], f"{name} findings must be empty when summary.findingCounts is empty")
            continue
        for finding in active_findings:
            code = finding["code"]
            test.assertIn(code, finding_counts, f"{name} finding code missing from summary.findingCounts")
            test.assertGreater(finding_counts[code], 0, f"{name} finding code has no positive observations")


def _assert_enriched_finding_counts_match_report(
    test: unittest.TestCase,
    report: dict,
    enriched_path: Path,
) -> None:
    from tools.bbb_hub.diagnostic_status import _collect_findings  # noqa: E402

    observed_counts: dict[str, int] = {}
    for line in enriched_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        state = json.loads(line)
        diagnostic = state.get("_diagnostic")
        _assert_normalized_diagnostic_contract(test, diagnostic)
        health = state.get("_health")
        health = health if isinstance(health, dict) else {}
        for finding in _collect_findings(health):
            code = finding["code"]
            test.assertNotIn(code, SENSOR_COVERAGE_SHAPE_FINDING_CODES)
            test.assertNotEqual(finding["source"], "sensorCoverage")
            observed_counts[code] = observed_counts.get(code, 0) + 1
    test.assertEqual(report["summary"]["findingCounts"], observed_counts)


def _assert_diagnostic_matches_fixture_expectation(
    test: unittest.TestCase,
    diagnostic: dict,
    expected: dict,
) -> None:
    test.assertEqual(diagnostic["status"], expected["status"])
    test.assertEqual(diagnostic["severity"], expected["severity"])
    test.assertEqual(diagnostic["findingCount"], expected["findingCount"])
    test.assertEqual(
        [finding["code"] for finding in diagnostic["activeFindings"]],
        expected["activeFindingCodes"],
    )


def _diagnostic_field_counts(states: list[dict], field: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for state in states:
        value = state["_diagnostic"][field]
        counts[value] = counts.get(value, 0) + 1
    return counts


_MISSING = object()


def _read_state_path(state: dict, path: str) -> object:
    current: object = state
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return _MISSING
        current = current[part]
    return current


def _inline_trust_metadata_sensor_names(states: list[dict]) -> set[str]:
    names: set[str] = set()
    for state in states:
        health = state.get("_health")
        health = health if isinstance(health, dict) else {}
        for container in (state.get("sensorTrust"), health.get("sensorTrust")):
            if isinstance(container, dict):
                names.update(str(name) for name in container)
        for container in (
            state.get("diagnosticCandidateSignals"),
            health.get("diagnosticCandidateSignals"),
        ):
            if not isinstance(container, dict):
                continue
            candidates = container.get("candidates")
            if isinstance(candidates, dict):
                names.update(str(name) for name in candidates)
    return names


def _fixture_baseline_profiles(test: unittest.TestCase, entry: dict) -> list[BaselineProfile]:
    payload = entry.get("baselineProfiles", [])
    test.assertIsInstance(payload, list)
    profiles: list[BaselineProfile] = []
    for profile_payload in payload:
        test.assertIsInstance(profile_payload, dict)
        features_payload = profile_payload.get("features", [])
        test.assertIsInstance(features_payload, list)
        test.assertGreater(len(features_payload), 0)
        features: list[BaselineFeature] = []
        for feature_payload in features_payload:
            test.assertIsInstance(feature_payload, dict)
            signal = feature_payload.get("signal")
            bucket_size = feature_payload.get("bucketSize")
            test.assertIsInstance(signal, str)
            test.assertTrue(signal)
            test.assertIsInstance(bucket_size, (int, float))
            features.append(BaselineFeature(signal, float(bucket_size)))
        name = profile_payload.get("name")
        target = profile_payload.get("target")
        unit = profile_payload.get("unit")
        test.assertIsInstance(name, str)
        test.assertIsInstance(target, str)
        test.assertIsInstance(unit, str)
        test.assertTrue(name)
        test.assertTrue(target)
        test.assertTrue(unit)
        profiles.append(
            BaselineProfile(
                name=name,
                target=target,
                unit=unit,
                features=tuple(features),
            )
        )
    return profiles


def _fixture_transition_profiles(test: unittest.TestCase, entry: dict) -> list[TransitionProfile]:
    payload = entry.get("transitionProfiles", [])
    test.assertIsInstance(payload, list)
    profiles: list[TransitionProfile] = []
    for profile_payload in payload:
        test.assertIsInstance(profile_payload, dict)
        refs_payload = profile_payload.get("referenceSignals", [])
        test.assertIsInstance(refs_payload, list)
        reference_signals: list[str] = []
        for signal in refs_payload:
            test.assertIsInstance(signal, str)
            test.assertTrue(signal)
            reference_signals.append(signal)
        name = profile_payload.get("name")
        event_type = profile_payload.get("eventType")
        target = profile_payload.get("target")
        unit = profile_payload.get("unit")
        test.assertIsInstance(name, str)
        test.assertIsInstance(event_type, str)
        test.assertIsInstance(target, str)
        test.assertIsInstance(unit, str)
        test.assertTrue(name)
        test.assertTrue(event_type)
        test.assertTrue(target)
        test.assertTrue(unit)
        profiles.append(
            TransitionProfile(
                name=name,
                event_type=event_type,
                target=target,
                unit=unit,
                reference_signals=tuple(reference_signals),
            )
        )
    return profiles


def _assert_vehicle_health_verdict_contract(test: unittest.TestCase, verdict: dict) -> None:
    test.assertIsInstance(verdict, dict)
    test.assertEqual(verdict["version"], 1)
    test.assertEqual(verdict["kind"], "vehicle_health_verdict")
    test.assertIsInstance(verdict["generatedAt"], str)
    test.assertTrue(verdict["generatedAt"])
    test.assertIsInstance(verdict["mode"], str)
    test.assertTrue(verdict["mode"])
    test.assertTrue(verdict["vehicleProfile"] is None or isinstance(verdict["vehicleProfile"], str))
    test.assertIsInstance(verdict["captureRef"], dict)

    verdict_payload = verdict["verdict"]
    test.assertIsInstance(verdict_payload, dict)
    test.assertIn(
        verdict_payload["label"],
        {"healthy", "probably_healthy", "capture_limited", "insufficient_evidence", "anomaly_likely", "anomaly_detected"},
    )
    test.assertIsInstance(verdict_payload["summary"], str)
    test.assertTrue(verdict_payload["summary"])
    test.assertTrue(verdict_payload["ok"] is None or isinstance(verdict_payload["ok"], bool))
    if verdict_payload["label"] in {"healthy", "probably_healthy"}:
        test.assertTrue(verdict_payload["ok"])
    if verdict_payload["label"] in {"anomaly_likely", "anomaly_detected"}:
        test.assertFalse(verdict_payload["ok"])
    if verdict_payload["label"] in {"capture_limited", "insufficient_evidence"}:
        test.assertIsNone(verdict_payload["ok"])

    coverage = verdict["coverage"]
    test.assertIsInstance(coverage, dict)
    _assert_unit_interval(test, coverage["score"])
    _assert_unit_interval(test, coverage["confidence"])
    for key in ("observedContexts", "missingContexts"):
        test.assertIsInstance(coverage[key], list)
        for context in coverage[key]:
            test.assertIsInstance(context, str)
            test.assertTrue(context)
    test.assertIsInstance(coverage["sourceCoverage"], dict)
    for source, status in coverage["sourceCoverage"].items():
        test.assertIsInstance(source, str)
        test.assertTrue(source)
        test.assertIsInstance(status, str)
        test.assertTrue(status)
    test.assertIsInstance(coverage["sampleCounts"], dict)
    for name, count in coverage["sampleCounts"].items():
        test.assertIsInstance(name, str)
        test.assertTrue(name)
        test.assertIsInstance(count, int)
        test.assertGreaterEqual(count, 0)
    if "durationSec" in coverage:
        test.assertIsInstance(coverage["durationSec"], (int, float))
        test.assertGreaterEqual(coverage["durationSec"], 0)

    confidence_model = verdict["confidenceModel"]
    test.assertIsInstance(confidence_model, dict)
    for key in ("score", "evidenceConsistency", "sourceTrust", "modelApplicability"):
        _assert_unit_interval(test, confidence_model[key])
    test.assertIsInstance(confidence_model["penalties"], list)
    for penalty in confidence_model["penalties"]:
        test.assertIsInstance(penalty, dict)
        test.assertIsInstance(penalty["code"], str)
        test.assertTrue(penalty["code"])
        test.assertIsInstance(penalty["message"], str)
        test.assertTrue(penalty["message"])
        test.assertIsInstance(penalty["weight"], (int, float))
        test.assertGreaterEqual(penalty["weight"], 0)

    evidence_inputs = verdict["evidenceInputs"]
    test.assertIsInstance(evidence_inputs, dict)
    for key in ("captureQuality", "findingSummary", "sourceHealth", "signalHealth", "baselineHealth", "transitionHealth", "anchors"):
        test.assertIn(key, evidence_inputs)
    capture_quality = evidence_inputs["captureQuality"]
    test.assertIsInstance(capture_quality, dict)
    test.assertIn(capture_quality["gpsOk"], {True, False, None})
    test.assertIn(capture_quality["canOk"], {True, False, None})
    test.assertIn(capture_quality["serialOk"], {True, False, None})
    test.assertIsInstance(capture_quality["linkStale"], bool)

    finding_summary = evidence_inputs["findingSummary"]
    test.assertIn(finding_summary["worstSeverity"], SEVERITY_ORDER)
    test.assertIsInstance(finding_summary["activeFindingCount"], int)
    test.assertGreaterEqual(finding_summary["activeFindingCount"], 0)
    test.assertIsInstance(finding_summary["codes"], list)
    for code in finding_summary["codes"]:
        test.assertIsInstance(code, str)
        test.assertTrue(code)

    _assert_counter_map(test, evidence_inputs["sourceHealth"])
    _assert_counter_map(test, evidence_inputs["signalHealth"])
    _assert_model_health(test, evidence_inputs["baselineHealth"])
    _assert_model_health(test, evidence_inputs["transitionHealth"], transition=True)
    anchors = evidence_inputs["anchors"]
    test.assertIsInstance(anchors, dict)
    test.assertIsInstance(anchors["direct"], list)
    for anchor in anchors["direct"]:
        test.assertIsInstance(anchor, str)
        test.assertTrue(anchor)
    test.assertIsInstance(anchors["derived"], list)
    for anchor in anchors["derived"]:
        test.assertIsInstance(anchor, dict)

    abstain = verdict["abstain"]
    test.assertIsInstance(abstain, dict)
    test.assertIsInstance(abstain["required"], bool)
    test.assertIsInstance(abstain["reasons"], list)
    for reason in abstain["reasons"]:
        test.assertIsInstance(reason, str)
        test.assertTrue(reason)
    test.assertTrue(abstain["recommendedLabel"] is None or isinstance(abstain["recommendedLabel"], str))
    if abstain["required"]:
        test.assertIn(abstain["recommendedLabel"], {"capture_limited", "insufficient_evidence"})
        test.assertEqual(verdict_payload["label"], abstain["recommendedLabel"])
    else:
        test.assertEqual(abstain["reasons"], [])
        test.assertIsNone(abstain["recommendedLabel"])

    allowed_language = verdict["allowedLanguage"]
    test.assertIsInstance(allowed_language, dict)
    for key in ("maySay", "mustAvoid"):
        test.assertIsInstance(allowed_language[key], list)
        test.assertGreater(len(allowed_language[key]), 0)
        for phrase in allowed_language[key]:
            test.assertIsInstance(phrase, str)
            test.assertTrue(phrase)
    test.assertIsInstance(allowed_language["mustIncludeLimitationsWhenPresent"], bool)
    test.assertIsInstance(verdict["limitations"], list)
    for limitation in verdict["limitations"]:
        test.assertIsInstance(limitation, str)
        test.assertTrue(limitation)


def _assert_baseline_coverage_contract(test: unittest.TestCase, report: dict) -> None:
    coverage_statuses = {"strong", "weak", "missing"}
    test.assertIsInstance(report, dict)
    test.assertEqual(report["version"], 1)
    test.assertEqual(report["kind"], "baseline_coverage_report")

    summary = report["summary"]
    test.assertIsInstance(summary, dict)
    _assert_unit_interval(test, summary["score"])
    status_counts = summary["statusCounts"]
    test.assertIsInstance(status_counts, dict)
    test.assertEqual(set(status_counts), coverage_statuses)
    for status, count in status_counts.items():
        test.assertIn(status, coverage_statuses)
        _assert_non_negative_int(test, count)
    test.assertEqual(summary["strongScenarios"], status_counts["strong"])
    test.assertEqual(summary["weakScenarios"], status_counts["weak"])
    test.assertEqual(summary["missingScenarios"], status_counts["missing"])
    test.assertIsInstance(summary["ready"], bool)

    scenarios = report["scenarios"]
    test.assertIsInstance(scenarios, list)
    test.assertGreater(len(scenarios), 0)
    scenario_counts = {status: 0 for status in coverage_statuses}
    scenario_by_key: dict[str, dict] = {}
    for scenario in scenarios:
        test.assertIsInstance(scenario, dict)
        for key in ("key", "label", "category"):
            test.assertIsInstance(scenario[key], str)
            test.assertTrue(scenario[key])
        test.assertNotIn(scenario["key"], scenario_by_key)
        scenario_by_key[scenario["key"]] = scenario
        test.assertIn(scenario["status"], coverage_statuses)
        scenario_counts[scenario["status"]] += 1
        _assert_unit_interval(test, scenario["score"])

        evidence = scenario["evidence"]
        test.assertIsInstance(evidence, dict)
        _assert_string_list(test, evidence["contexts"])
        _assert_model_coverage_list(test, evidence["steadyModels"], count_keys=("totalSamples", "samples", "bucketCount"))
        _assert_model_coverage_list(test, evidence["transitionModels"], count_keys=("windows",))
        _assert_counter_map(test, evidence["eventsSeen"])

        missing = scenario["missing"]
        test.assertIsInstance(missing, dict)
        for missing_key, missing_values in missing.items():
            test.assertIn(missing_key, {"contexts", "steadyModels", "transitionModels", "events"})
            _assert_string_list(test, missing_values)
        next_step = scenario["nextStep"]
        if scenario["status"] == "strong":
            test.assertIsNone(next_step)
        else:
            test.assertIsInstance(next_step, str)
            test.assertTrue(next_step)

    test.assertEqual(status_counts, scenario_counts)
    expected_score = round(sum(float(scenario["score"]) for scenario in scenarios) / len(scenarios), 3)
    test.assertEqual(summary["score"], expected_score)
    expected_ready = status_counts["missing"] == 0 and status_counts["weak"] <= max(1, len(scenarios) // 4)
    test.assertEqual(summary["ready"], expected_ready)

    next_steps = summary["nextSteps"]
    test.assertIsInstance(next_steps, list)
    test.assertLessEqual(len(next_steps), 5)
    for next_step in next_steps:
        test.assertIsInstance(next_step, dict)
        for key in ("scenario", "label", "status", "nextStep"):
            test.assertIsInstance(next_step[key], str)
            test.assertTrue(next_step[key])
        test.assertIn(next_step["scenario"], scenario_by_key)
        scenario = scenario_by_key[next_step["scenario"]]
        test.assertNotEqual(scenario["status"], "strong")
        test.assertEqual(next_step["label"], scenario["label"])
        test.assertEqual(next_step["status"], scenario["status"])
        test.assertEqual(next_step["nextStep"], scenario["nextStep"])
        _assert_unit_interval(test, next_step["score"])
        test.assertEqual(next_step["score"], scenario["score"])
        test.assertIsInstance(next_step["missing"], dict)

    operating_contexts = report["operatingContexts"]
    test.assertIsInstance(operating_contexts, dict)
    _assert_string_list(test, operating_contexts["observed"])
    _assert_string_list(test, operating_contexts["missing"])

    steady_state = report["steadyState"]
    test.assertIsInstance(steady_state, dict)
    steady_models = steady_state["models"]
    _assert_model_coverage_list(test, steady_models, count_keys=("totalSamples", "samples", "bucketCount"))
    _assert_ready_models(test, steady_state["readyModels"], steady_models)

    transitions = report["transitions"]
    test.assertIsInstance(transitions, dict)
    _assert_counter_map(test, transitions["eventsSeen"])
    transition_models = transitions["models"]
    _assert_model_coverage_list(test, transition_models, count_keys=("windows",))
    _assert_ready_models(test, transitions["readyModels"], transition_models)


def _assert_vehicle_baseline_contract(test: unittest.TestCase, baseline: dict) -> None:
    test.assertIsInstance(baseline, dict)
    for key in ("enabled", "storagePath", "writes", "lastError", "models"):
        test.assertIn(key, baseline)
    test.assertIsInstance(baseline["enabled"], bool)
    test.assertTrue(baseline["storagePath"] is None or isinstance(baseline["storagePath"], str))
    if isinstance(baseline["storagePath"], str):
        test.assertTrue(baseline["storagePath"])
    _assert_non_negative_int(test, baseline["writes"])
    test.assertTrue(baseline["lastError"] is None or isinstance(baseline["lastError"], str))
    if isinstance(baseline["lastError"], str):
        test.assertTrue(baseline["lastError"])

    models = baseline["models"]
    test.assertIsInstance(models, list)
    test.assertGreater(len(models), 0)
    model_names: set[str] = set()
    for model in models:
        _assert_vehicle_baseline_model_contract(test, model)
        test.assertNotIn(model["name"], model_names)
        model_names.add(model["name"])


def _assert_vehicle_baseline_model_contract(test: unittest.TestCase, model: dict) -> None:
    test.assertIsInstance(model, dict)
    for key in ("name", "target", "unit", "status"):
        test.assertIsInstance(model[key], str)
        test.assertTrue(model[key])
    test.assertTrue(model["reason"] is None or isinstance(model["reason"], str))
    if isinstance(model["reason"], str):
        test.assertTrue(model["reason"])
    _assert_unit_interval(test, model["confidence"])
    test.assertIsInstance(model["ready"], bool)
    for key in ("bucketCount", "totalSamples", "activeAnomalies"):
        _assert_non_negative_int(test, model[key])
    test.assertTrue(model["lastBucket"] is None or isinstance(model["lastBucket"], str))
    if isinstance(model["lastBucket"], str):
        test.assertTrue(model["lastBucket"])
    if model["ready"]:
        test.assertGreater(model["bucketCount"], 0)
        test.assertGreater(model["totalSamples"], 0)
    if model["lastBucket"] is not None:
        test.assertGreater(model["bucketCount"], 0)


def _assert_transition_surfaces_contract(test: unittest.TestCase, report: dict) -> None:
    transition_monitor = report["transitionMonitor"]
    test.assertIsInstance(transition_monitor, dict)
    for key in ("enabled", "ok", "storagePath", "activeEvent", "coverage", "models", "findings", "lastError"):
        test.assertIn(key, transition_monitor)
    test.assertIsInstance(transition_monitor["enabled"], bool)
    test.assertIsInstance(transition_monitor["ok"], bool)
    test.assertTrue(transition_monitor["storagePath"] is None or isinstance(transition_monitor["storagePath"], str))
    if isinstance(transition_monitor["storagePath"], str):
        test.assertTrue(transition_monitor["storagePath"])
    test.assertTrue(transition_monitor["lastError"] is None or isinstance(transition_monitor["lastError"], str))
    if isinstance(transition_monitor["lastError"], str):
        test.assertTrue(transition_monitor["lastError"])
    if transition_monitor["activeEvent"] is not None:
        _assert_transition_event_contract(test, transition_monitor["activeEvent"])

    transition_coverage = transition_monitor["coverage"]
    test.assertIsInstance(transition_coverage, dict)
    test.assertEqual(report["transitionCoverage"], transition_coverage)
    for key in ("eventsSeen", "windowsScored", "windowsLearned", "pendingWindows", "readyModels"):
        test.assertIn(key, transition_coverage)
    _assert_counter_map(test, transition_coverage["eventsSeen"])
    for key in ("windowsScored", "windowsLearned", "pendingWindows"):
        _assert_non_negative_int(test, transition_coverage[key])
    test.assertLessEqual(transition_coverage["windowsLearned"], transition_coverage["windowsScored"])

    models = transition_monitor["models"]
    test.assertIsInstance(models, list)
    model_by_name: dict[str, dict] = {}
    for model in models:
        _assert_transition_model_contract(test, model)
        test.assertNotIn(model["name"], model_by_name)
        model_by_name[model["name"]] = model

    ready_models = transition_coverage["readyModels"]
    _assert_ready_models(test, ready_models, models)
    test.assertEqual(sorted(ready_models), sorted(model["name"] for model in models if model["ready"]))
    test.assertEqual(report["transitionBaselineReady"], any(model["ready"] for model in models))

    monitor_findings = transition_monitor["findings"]
    test.assertIsInstance(monitor_findings, list)
    for finding in monitor_findings:
        _assert_transition_finding_contract(test, finding)

    transition_findings = report["transitionFindings"]
    test.assertIsInstance(transition_findings, list)
    test.assertLessEqual(len(transition_findings), TRANSITION_FINDINGS_REPORT_LIMIT)
    for finding in transition_findings:
        _assert_transition_finding_contract(test, finding)


def _assert_transition_model_contract(test: unittest.TestCase, model: dict) -> None:
    test.assertIsInstance(model, dict)
    for key in ("name", "eventType", "target", "unit", "signalTierName"):
        test.assertIsInstance(model[key], str)
        test.assertTrue(model[key])
    _assert_non_negative_int(test, model["signalTier"])
    test.assertIsInstance(model["ready"], bool)
    _assert_non_negative_int(test, model["windows"])
    if model["ready"]:
        test.assertGreater(model["windows"], 0)
    for key in ("firstSeen", "lastSeen"):
        test.assertTrue(model[key] is None or isinstance(model[key], (int, float)))
    if model["firstSeen"] is not None and model["lastSeen"] is not None:
        test.assertLessEqual(model["firstSeen"], model["lastSeen"])
    _assert_counter_map(test, model["eventCounts"])
    metrics = model["metrics"]
    test.assertIsInstance(metrics, dict)
    for metric_name, metric in metrics.items():
        test.assertIsInstance(metric_name, str)
        test.assertTrue(metric_name)
        _assert_running_stats_snapshot_contract(test, metric)


def _assert_running_stats_snapshot_contract(test: unittest.TestCase, stats: dict) -> None:
    test.assertIsInstance(stats, dict)
    _assert_non_negative_int(test, stats["count"])
    for key in ("mean", "stddev"):
        test.assertIsInstance(stats[key], (int, float))
    test.assertGreaterEqual(stats["stddev"], 0.0)
    for key in ("min", "max"):
        test.assertTrue(stats[key] is None or isinstance(stats[key], (int, float)))
    if stats["min"] is not None and stats["max"] is not None:
        test.assertLessEqual(stats["min"], stats["max"])


def _assert_transition_event_contract(test: unittest.TestCase, event: dict) -> None:
    test.assertIsInstance(event, dict)
    test.assertIsInstance(event["name"], str)
    test.assertTrue(event["name"])
    test.assertIsInstance(event["timestamp"], (int, float))
    _assert_non_negative_int(test, event["index"])
    test.assertIsInstance(event["evidence"], dict)


def _assert_transition_finding_contract(test: unittest.TestCase, finding: dict) -> None:
    _assert_normalized_finding_contract(test, finding)
    test.assertEqual(finding["source"], "transitionMonitor")
    for key in ("verdict", "abstain", "allowedLanguage", "limitations", "healthVerdict"):
        test.assertNotIn(key, finding)
    details = finding.get("details")
    test.assertIsInstance(details, dict)
    test.assertIsInstance(details["eventType"], str)
    test.assertTrue(details["eventType"])
    test.assertIn(details["anomalyClass"], set(ANOMALY_CLASSES))
    _assert_non_negative_int(test, details["baselineWindows"])
    _assert_non_negative_int(test, details["signalTier"])
    for key in (
        "observedDelta",
        "expectedDelta",
        "observedRange",
        "expectedRange",
        "observedLagSeconds",
        "expectedLagSeconds",
    ):
        test.assertTrue(details[key] is None or isinstance(details[key], (int, float)))
    if "suspectedCauses" in details:
        _assert_string_list(test, details["suspectedCauses"])


def _assert_unit_interval(test: unittest.TestCase, value: object) -> None:
    test.assertIsInstance(value, (int, float))
    test.assertGreaterEqual(value, 0.0)
    test.assertLessEqual(value, 1.0)


def _assert_non_negative_int(test: unittest.TestCase, value: object) -> None:
    test.assertIsInstance(value, int)
    test.assertNotIsInstance(value, bool)
    test.assertGreaterEqual(value, 0)


def _assert_string_list(test: unittest.TestCase, values: object) -> None:
    test.assertIsInstance(values, list)
    for value in values:
        test.assertIsInstance(value, str)
        test.assertTrue(value)


def _assert_counter_map(test: unittest.TestCase, payload: dict) -> None:
    test.assertIsInstance(payload, dict)
    for key, value in payload.items():
        test.assertIsInstance(key, str)
        test.assertTrue(key)
        test.assertIsInstance(value, (bool, int))
        if isinstance(value, int) and not isinstance(value, bool):
            test.assertGreaterEqual(value, 0)


def _assert_model_coverage_list(test: unittest.TestCase, models: object, *, count_keys: tuple[str, ...]) -> None:
    test.assertIsInstance(models, list)
    for model in models:
        test.assertIsInstance(model, dict)
        test.assertIsInstance(model["name"], str)
        test.assertTrue(model["name"])
        test.assertIsInstance(model["ready"], bool)
        for count_key in count_keys:
            _assert_non_negative_int(test, model[count_key])
        for text_key in ("status", "eventType", "target"):
            if text_key in model:
                test.assertIsInstance(model[text_key], str)


def _assert_ready_models(test: unittest.TestCase, ready_models: object, models: list[dict]) -> None:
    _assert_string_list(test, ready_models)
    by_name = {model["name"]: model for model in models}
    for model_name in ready_models:
        test.assertIn(model_name, by_name)
        test.assertTrue(by_name[model_name]["ready"])


def _assert_model_health(test: unittest.TestCase, payload: dict, *, transition: bool = False) -> None:
    test.assertIsInstance(payload, dict)
    test.assertIsInstance(payload["enabled"], bool)
    test.assertIsInstance(payload["readyModels"], list)
    for model in payload["readyModels"]:
        test.assertIsInstance(model, str)
        test.assertTrue(model)
    for key in ("anomalyCount", "modelCount"):
        test.assertIsInstance(payload[key], int)
        test.assertGreaterEqual(payload[key], 0)
    if transition:
        for key in ("windowsScored", "windowsLearned"):
            test.assertIsInstance(payload[key], int)
            test.assertGreaterEqual(payload[key], 0)


def _assert_fault_event_summary_contract(test: unittest.TestCase, summary: dict) -> None:
    test.assertEqual(summary["version"], 1)
    test.assertEqual(summary["kind"], "bbb_fault_event_summary")
    for key in ("healthVerdict", "verdict", "abstain", "allowedLanguage"):
        test.assertNotIn(key, summary)
    event_ref = summary["eventRef"]
    test.assertIsInstance(event_ref, dict)
    for key in ("eventId", "generatedAt", "faultFingerprint", "sourceKind", "path"):
        test.assertIsInstance(event_ref[key], str)
        test.assertTrue(event_ref[key])
    test.assertEqual(event_ref["sourceKind"], "bbb_fault_event")
    test.assertIn(summary["status"], {"anomaly_recorded", "evidence_recorded"})
    test.assertIn(summary["severity"], SEVERITY_ORDER)
    test.assertIsInstance(summary["customerSummary"], str)
    test.assertTrue(summary["customerSummary"])
    findings = summary["findings"]
    test.assertIsInstance(findings, list)
    for finding in findings:
        _assert_normalized_finding_contract(test, finding)
    if findings:
        test.assertEqual(summary["primaryFinding"], findings[0])
    else:
        test.assertIsNone(summary["primaryFinding"])

    trigger_context = summary["triggerContext"]
    test.assertIsInstance(trigger_context, dict)
    for key in ("operatingState", "diagnosticStatus", "diagnosticSummary"):
        test.assertIsInstance(trigger_context[key], str)
    test.assertIsInstance(trigger_context["captureQuality"], dict)
    signals = trigger_context["signals"]
    test.assertIsInstance(signals, dict)
    for signal_name, value in signals.items():
        test.assertIsInstance(signal_name, str)
        test.assertTrue(signal_name)
        test.assertIsInstance(value, (int, float))

    evidence_summary = summary["evidenceSummary"]
    test.assertIsInstance(evidence_summary, dict)
    test.assertIsInstance(evidence_summary["rollingFrames"], int)
    test.assertGreaterEqual(evidence_summary["rollingFrames"], 0)
    test.assertTrue(evidence_summary["bufferSeconds"] is None or isinstance(evidence_summary["bufferSeconds"], (int, float)))
    for key in ("evidenceKeys", "sourceHealthKeys"):
        test.assertIsInstance(evidence_summary[key], list)
        for value in evidence_summary[key]:
            test.assertIsInstance(value, str)

    responsible_use = summary["responsibleUse"]
    test.assertIsInstance(responsible_use, dict)
    test.assertTrue(responsible_use["notRepairDirective"])
    test.assertTrue(responsible_use["requiresCorroboration"])
    test.assertIsInstance(responsible_use["allowedUse"], str)
    test.assertTrue(responsible_use["allowedUse"])
    test.assertIsInstance(responsible_use["mustAvoid"], list)
    test.assertGreater(len(responsible_use["mustAvoid"]), 0)
    for value in responsible_use["mustAvoid"]:
        test.assertIsInstance(value, str)
        test.assertTrue(value)


def _assert_fault_event_summary_traceability_contract(
    test: unittest.TestCase,
    fault_event_path: str,
    summary: dict,
) -> None:
    event = json.loads(Path(fault_event_path).read_text(encoding="utf-8"))
    test.assertEqual(event["version"], 1)
    test.assertEqual(event["kind"], "bbb_fault_event")
    test.assertNotIn("healthVerdict", event)
    trigger_state = event["triggerState"]
    test.assertIsInstance(trigger_state, dict)
    diagnostic = trigger_state["_diagnostic"]
    _assert_normalized_diagnostic_contract(test, diagnostic)
    trigger_finding_identities = {
        _finding_identity(finding)
        for finding in diagnostic["activeFindings"]
    }

    primary_finding = summary["primaryFinding"]
    if primary_finding is None:
        test.assertEqual(summary["findings"], [])
        test.assertEqual(trigger_finding_identities, set())
        return

    test.assertIn(_finding_identity(primary_finding), trigger_finding_identities)
    for finding in summary["findings"]:
        test.assertIn(finding["code"], summary["eventRef"]["faultFingerprint"])


def _finding_identity(finding: dict) -> tuple[str, str, str, str, str]:
    return (
        str(finding.get("source", "")),
        str(finding.get("subject", "")),
        str(finding.get("code", "")),
        str(finding.get("severity", "")),
        str(finding.get("message", "")),
    )


def _assert_fault_event_summary_error_contract(test: unittest.TestCase, summary: dict) -> None:
    test.assertEqual(summary["version"], 1)
    test.assertEqual(summary["kind"], "bbb_fault_event_summary_error")
    test.assertIsInstance(summary["eventRef"], dict)
    test.assertIsInstance(summary["eventRef"]["path"], str)
    test.assertTrue(summary["eventRef"]["path"])
    test.assertIsInstance(summary["error"], str)
    test.assertTrue(summary["error"])


def _assert_fault_recorder_contract(test: unittest.TestCase, report: dict) -> None:
    fault_recorder = report["faultRecorder"]
    test.assertIsInstance(fault_recorder, dict)
    for key in (
        "enabled",
        "outputDir",
        "bufferSeconds",
        "bufferFrames",
        "maxEventFiles",
        "maxTotalBytes",
        "writes",
        "lastEventPath",
        "lastError",
    ):
        test.assertIn(key, fault_recorder)
    test.assertIsInstance(fault_recorder["enabled"], bool)
    test.assertIsInstance(fault_recorder["outputDir"], str)
    test.assertTrue(fault_recorder["outputDir"])
    test.assertIsInstance(fault_recorder["bufferSeconds"], (int, float))
    test.assertGreaterEqual(fault_recorder["bufferSeconds"], 0)
    for key in ("bufferFrames", "maxEventFiles", "maxTotalBytes", "writes"):
        test.assertIsInstance(fault_recorder[key], int)
        test.assertGreaterEqual(fault_recorder[key], 0)
    last_event_path = fault_recorder["lastEventPath"]
    test.assertTrue(last_event_path is None or isinstance(last_event_path, str))
    if isinstance(last_event_path, str):
        test.assertTrue(last_event_path)
    last_error = fault_recorder["lastError"]
    test.assertTrue(last_error is None or isinstance(last_error, str))
    if isinstance(last_error, str):
        test.assertTrue(last_error)

    fault_event_paths = report["faultEventPaths"]
    test.assertEqual(fault_recorder["writes"], len(fault_event_paths))
    if fault_event_paths:
        test.assertEqual(fault_recorder["lastEventPath"], fault_event_paths[-1])
    else:
        test.assertIsNone(fault_recorder["lastEventPath"])
    if not fault_recorder["enabled"]:
        test.assertEqual(fault_recorder["writes"], 0)
        test.assertIsNone(fault_recorder["lastEventPath"])
        test.assertEqual(report["summary"]["faultEvents"], 0)
        test.assertEqual(report["faultEventPaths"], [])
        test.assertEqual(report["faultEventSummaries"], [])


def _assert_normalized_diagnostic_contract(test: unittest.TestCase, diagnostic: dict) -> None:
    test.assertIsInstance(diagnostic, dict)
    test.assertEqual(diagnostic["version"], 1)
    test.assertIsInstance(diagnostic["mode"], str)
    test.assertTrue(diagnostic["mode"])
    test.assertIsInstance(diagnostic["ok"], bool)
    test.assertIn(diagnostic["severity"], {"ok", "info", "warning", "error"})
    test.assertIn(diagnostic["status"], {"nominal", "limited", "data_stale", "anomaly_detected"})
    test.assertIsInstance(diagnostic["summary"], str)
    test.assertTrue(diagnostic["summary"])
    test.assertIsInstance(diagnostic["findingCount"], int)
    test.assertGreaterEqual(diagnostic["findingCount"], 0)
    test.assertIsInstance(diagnostic["activeFindings"], list)
    test.assertLessEqual(len(diagnostic["activeFindings"]), diagnostic["findingCount"])
    for finding in diagnostic["activeFindings"]:
        _assert_normalized_finding_contract(test, finding)

    capture_quality = diagnostic["captureQuality"]
    test.assertIsInstance(capture_quality, dict)
    test.assertIsInstance(capture_quality["gpsOk"], bool)
    test.assertIn(capture_quality["canOk"], {True, False, None})
    test.assertIn(capture_quality["serialOk"], {True, False, None})
    test.assertIsInstance(capture_quality["linkStale"], bool)


def _assert_normalized_finding_contract(test: unittest.TestCase, finding: dict) -> None:
    test.assertIsInstance(finding, dict)
    for key in ("source", "subject", "code", "severity", "message"):
        test.assertIsInstance(finding[key], str)
        test.assertTrue(finding[key])
    test.assertIn(finding["severity"], {"ok", "info", "warning", "error"})
    if "confidence" in finding:
        test.assertIsInstance(finding["confidence"], (int, float))
        test.assertNotIsInstance(finding["confidence"], bool)
        test.assertGreaterEqual(finding["confidence"], 0.0)
        test.assertLessEqual(finding["confidence"], 1.0)
    if "details" in finding:
        test.assertIsInstance(finding["details"], dict)
    if finding["source"] == "vehicleBaseline":
        _assert_vehicle_baseline_finding_contract(test, finding)


def _assert_vehicle_baseline_finding_contract(test: unittest.TestCase, finding: dict) -> None:
    test.assertIn(finding["severity"], {"warning", "error"})
    test.assertGreater(finding.get("confidence", 0.0), 0.0)
    details = finding.get("details", {})
    test.assertIsInstance(details, dict)
    if "model" in details:
        test.assertIsInstance(details["model"], str)
        test.assertTrue(details["model"])
    if "value" in details:
        test.assertIsInstance(details["value"], (int, float))
    if "suspectedCauses" in details:
        _assert_string_list(test, details["suspectedCauses"])


if __name__ == "__main__":
    unittest.main()
