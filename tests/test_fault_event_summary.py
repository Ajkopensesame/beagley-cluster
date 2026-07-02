#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.diagnostic_replay import main  # noqa: E402
from tools.vehicle_analysis.fault_events import (  # noqa: E402
    build_fault_event_summary,
    load_fault_event,
    summarize_fault_event_file,
)


class FaultEventSummaryTest(unittest.TestCase):
    def test_summarizes_cli_fault_event_without_repair_claims(self) -> None:
        fixture = Path(ROOT) / "tests" / "fixtures" / "diagnostic_replay_speed_disagreement.jsonl"
        with tempfile.TemporaryDirectory() as temp_dir:
            report_path = Path(temp_dir) / "report.json"
            fault_dir = Path(temp_dir) / "faults"
            with redirect_stdout(StringIO()):
                self.assertEqual(
                    main(
                        [
                            "--state-jsonl",
                            str(fixture),
                            "--report",
                            str(report_path),
                            "--fault-dir",
                            str(fault_dir),
                        ]
                    ),
                    0,
                )

            report = json.loads(report_path.read_text(encoding="utf-8"))
            event_path = Path(report["faultEventPaths"][0])
            event = load_fault_event(event_path)
            summary = summarize_fault_event_file(event_path)

            self.assertEqual(summary["kind"], "bbb_fault_event_summary")
            self.assertEqual(summary["eventRef"]["sourceKind"], "bbb_fault_event")
            self.assertEqual(summary["status"], "anomaly_recorded")
            self.assertEqual(summary["severity"], "warning")
            self.assertEqual(summary["primaryFinding"]["code"], "source_disagreement")
            self.assertNotIn("healthVerdict", event)
            trigger_findings = event["triggerState"]["_diagnostic"]["activeFindings"]
            self.assertIn(summary["primaryFinding"], trigger_findings)
            self.assertEqual(summary["triggerContext"]["diagnosticStatus"], "anomaly_detected")
            self.assertEqual(summary["triggerContext"]["signals"]["speedKph"], 0.0)
            self.assertEqual(summary["triggerContext"]["signals"]["gpsSpeedKph"], 55.0)
            self.assertGreaterEqual(summary["evidenceSummary"]["rollingFrames"], 1)
            self.assertIn("signalFaults", summary["evidenceSummary"]["sourceHealthKeys"])
            self.assertTrue(summary["responsibleUse"]["notRepairDirective"])
            self.assertTrue(summary["responsibleUse"]["requiresCorroboration"])
            lower_summary = summary["customerSummary"].lower()
            self.assertIn("evidence", lower_summary)
            for blocked in ("replace", "repair", "guaranteed", "safe to operate"):
                self.assertNotIn(blocked, lower_summary)

    def test_rejects_wrong_event_kind(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "wrong.json"
            path.write_text(json.dumps({"version": 1, "kind": "vehicle_state"}) + "\n", encoding="utf-8")

            with self.assertRaises(ValueError):
                load_fault_event(path)
            with self.assertRaises(ValueError):
                build_fault_event_summary({"version": 1, "kind": "vehicle_state"})


if __name__ == "__main__":
    unittest.main()
