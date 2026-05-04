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

from tools.can_reverse_workbench.discovery import analyze_frames  # noqa: E402
from tools.can_reverse_workbench.export import build_signal_dictionary  # noqa: E402
from tools.can_reverse_workbench.identity import (  # noqa: E402
    build_diagnostic_candidate_signals,
    build_signal_identity_report,
)
from tools.can_reverse_workbench.labels import GuidedSession, load_guided_session  # noqa: E402
from tools.can_reverse_workbench.parser import parse_can_log  # noqa: E402


class SignalIdentityReportTest(unittest.TestCase):
    def test_wheel_speed_like_candidate_becomes_probable_low_trust_export(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path = _write_identity_fixture(Path(temp_dir))
            frames, stats = parse_can_log(log_path)
            report = build_signal_identity_report(
                frames,
                session=load_guided_session(labels_path),
                parse_stats=stats,
                source={"log": str(log_path), "labels": str(labels_path)},
                max_candidates=500,
            )

            wheel = _find_candidate(report, "0x221:b16:l16:little:u")
            self.assertEqual(wheel["suggested"]["class"], "speed_like")
            self.assertEqual(wheel["safety"]["promotionStatus"], "probable")
            self.assertTrue(wheel["safety"]["safeToUse"])
            self.assertIn("diagnostic_low_trust", wheel["safety"]["allowedUses"])
            self.assertIn("authoritative_health_verdict", wheel["safety"]["blockedUses"])
            self.assertGreaterEqual(wheel["suggested"]["confidence"], 0.78)
            self.assertGreaterEqual(wheel["evidence"]["bestCorrelationScore"], 0.95)

            export = build_diagnostic_candidate_signals(report)
            exported_ids = {item["candidateId"] for item in export["candidates"].values()}
            self.assertIn(wheel["candidateId"], exported_ids)
            self.assertTrue(export["exportPolicy"]["mustNotMergeIntoCanSignals"])

    def test_brake_switch_candidate_uses_event_response_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path = _write_identity_fixture(Path(temp_dir))
            frames, stats = parse_can_log(log_path)
            report = build_signal_identity_report(
                frames,
                session=load_guided_session(labels_path),
                parse_stats=stats,
                max_candidates=500,
            )

            brake = _find_candidate(report, "0x222:b0:l8:big:u")
            self.assertIn(brake["suggested"]["class"], {"switch", "warning_lamp"})
            self.assertIn(brake["safety"]["promotionStatus"], {"candidate", "probable"})
            self.assertGreaterEqual(brake["evidence"]["bestEventScore"], 0.8)
            self.assertTrue(any(item["label"] == "brake" for item in brake["evidence"]["eventResponses"]))

    def test_counter_and_checksum_fields_are_rejected_and_not_exported(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path = _write_identity_fixture(Path(temp_dir))
            frames, stats = parse_can_log(log_path)
            report = build_signal_identity_report(
                frames,
                session=load_guided_session(labels_path),
                parse_stats=stats,
                max_candidates=700,
            )
            export = build_diagnostic_candidate_signals(report)
            exported_ids = {item["candidateId"] for item in export["candidates"].values()}

            counter = _find_candidate(report, "0x223:b0:l4:little:u")
            self.assertEqual(counter["suggested"]["class"], "counter")
            self.assertEqual(counter["safety"]["promotionStatus"], "rejected")
            self.assertNotIn(counter["candidateId"], exported_ids)

            checksum = _find_candidate(report, "0x224:b0:l8:big:u")
            self.assertEqual(checksum["suggested"]["class"], "checksum_or_crc")
            self.assertEqual(checksum["safety"]["promotionStatus"], "rejected")
            self.assertNotIn(checksum["candidateId"], exported_ids)

    def test_ai_command_can_rename_but_cannot_override_deterministic_rejection(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            log_path, labels_path = _write_identity_fixture(root)
            ai_stub = root / "ai_stub.py"
            ai_stub.write_text(
                "\n".join(
                    [
                        "import json, sys",
                        "payload = json.load(sys.stdin)",
                        "non_rejected = next(c for c in payload['candidates'] if c['safety']['promotionStatus'] != 'rejected')",
                        "rejected = next(c for c in payload['candidates'] if c['canId'] == '0x223' and c['safety']['promotionStatus'] == 'rejected')",
                        "json.dump({'suggestions': [",
                        "  {'candidateId': non_rejected['candidateId'], 'name': 'front left wheel speed', 'class': 'speed_like', 'confidence': 0.99, 'rationale': 'tracks road speed'},",
                        "  {'candidateId': rejected['candidateId'], 'name': 'fake useful signal', 'class': 'speed_like', 'confidence': 0.99, 'rationale': 'try to override'}",
                        "]}, sys.stdout)",
                    ]
                ),
                encoding="utf-8",
            )
            frames, stats = parse_can_log(log_path)
            report = build_signal_identity_report(
                frames,
                session=load_guided_session(labels_path),
                parse_stats=stats,
                max_candidates=700,
                ai_command=f"{sys.executable} {ai_stub}",
            )

            renamed = next(
                item
                for item in report["hypotheses"]
                if item.get("suggested", {}).get("name") == "front_left_wheel_speed"
            )
            self.assertEqual(renamed["suggested"]["source"], "deterministic_ai_assisted")
            self.assertIn("aiSuggestion", renamed)

            rejected = next(
                item
                for item in report["hypotheses"]
                if item["canId"] == "0x223" and item["safety"]["promotionStatus"] == "rejected" and "aiSuggestion" in item
            )
            self.assertEqual(rejected["suggested"]["class"], "counter")
            self.assertEqual(rejected["safety"]["promotionStatus"], "rejected")

    def test_decoded_only_report_summarizes_decoded_signals_without_raw_hypotheses(self) -> None:
        rows = [
            {"timestamp": index * 0.1, "rpm": 750.0 + index, "speedKph": float(index % 30)}
            for index in range(60)
        ]
        report = build_signal_identity_report([], decoded_rows=rows)
        self.assertTrue(report["inputs"]["decodedVehicleState"])
        self.assertFalse(report["inputs"]["rawCan"])
        self.assertEqual(report["summary"]["hypothesisCount"], 0)
        self.assertEqual(report["decodedSignalSummary"]["signalCount"], 2)

    def test_hypotheses_do_not_leak_into_can_signals_export(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path = _write_identity_fixture(Path(temp_dir))
            frames, stats = parse_can_log(log_path)
            report = build_signal_identity_report(
                frames,
                session=load_guided_session(labels_path),
                parse_stats=stats,
                max_candidates=500,
            )
            diagnostic_export = build_diagnostic_candidate_signals(report)
            analysis = analyze_frames(frames, session=GuidedSession.empty(), parse_stats=stats)
            can_signals = build_signal_dictionary(analysis, source_log=str(log_path), source_labels=None)
            self.assertEqual(can_signals["signals"], {})
            self.assertTrue(diagnostic_export["candidates"])
            self.assertTrue(set(diagnostic_export["candidates"]).isdisjoint(can_signals["signals"]))


def _find_candidate(report: dict, candidate_id: str) -> dict:
    for item in report["hypotheses"]:
        if item["candidateId"] == candidate_id:
            return item
    raise AssertionError(f"candidate not found: {candidate_id}")


def _write_identity_fixture(root: Path) -> tuple[Path, Path]:
    log_path = root / "identity.candump"
    labels_path = root / "identity_labels.json"
    lines: list[str] = []
    speed_anchors: list[dict[str, float]] = []
    for index in range(220):
        timestamp = round(index * 0.1, 3)
        speed = _speed_profile(timestamp)
        wheel_raw = int(round(speed * 100.0))
        brake = 1 if 14.0 <= timestamp <= 17.0 else 0
        counter = index % 16
        checksum = (index * 37 + (index // 3) * 11) % 256

        wheel_data = bytearray(8)
        wheel_data[2:4] = wheel_raw.to_bytes(2, "little")
        lines.append(f"({timestamp:.3f}) can0 221#{bytes(wheel_data).hex().upper()}")
        lines.append(f"({timestamp:.3f}) can0 222#{bytes([brake, 0, 0, 0, 0, 0, 0, 0]).hex().upper()}")
        lines.append(f"({timestamp:.3f}) can0 223#{bytes([counter, 0, 0, 0, 0, 0, 0, 0]).hex().upper()}")
        lines.append(f"({timestamp:.3f}) can0 224#{bytes([checksum, 0, 0, 0, 0, 0, 0, 0]).hex().upper()}")
        if index % 2 == 0:
            speed_anchors.append({"timestamp": timestamp, "value": speed})

    log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    labels_path.write_text(
        json.dumps(
            {
                "windows": [
                    {"label": "accelerate", "start": 2.0, "end": 8.0, "target": "speedKph", "trend": "increasing"},
                    {"label": "brake", "start": 14.0, "end": 17.0},
                    {"label": "decelerate", "start": 14.0, "end": 19.0, "target": "speedKph", "trend": "decreasing"},
                ],
                "anchors": {"speedKph": speed_anchors},
            }
        ),
        encoding="utf-8",
    )
    return log_path, labels_path


def _speed_profile(timestamp: float) -> float:
    if timestamp < 2.0:
        return 0.0
    if timestamp < 8.0:
        return (timestamp - 2.0) * 12.0
    if timestamp < 14.0:
        return 72.0
    if timestamp < 19.0:
        return max(0.0, 72.0 - (timestamp - 14.0) * 14.4)
    return 0.0


if __name__ == "__main__":
    unittest.main()
