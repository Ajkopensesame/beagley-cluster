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

from tools.can_reverse_workbench.bbb_decoder import CanSignalDictionary, CanLogSignalReplay  # noqa: E402
from tools.can_reverse_workbench.baseline import (  # noqa: E402
    build_consent_record,
    build_health_baseline,
    diagnose_against_baseline,
    render_customer_report,
)
from tools.can_reverse_workbench.discovery import analyze_frames  # noqa: E402
from tools.can_reverse_workbench.export import build_signal_dictionary, validate_signal_dictionary  # noqa: E402
from tools.can_reverse_workbench.labels import load_guided_session  # noqa: E402
from tools.can_reverse_workbench.parser import CanFrame, parse_can_log  # noqa: E402


class CanReverseWorkbenchTest(unittest.TestCase):
    def test_parser_accepts_candump_csv_extended_ids_and_orders_timestamps(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            candump = Path(temp_dir) / "sample.log"
            candump.write_text(
                "\n".join(
                    [
                        "(2.000000) can0 18DAF110#AABBCC",
                        "(1.000000) can0 123#0102",
                        "(3.000000) can0 broken",
                        "(4.000000) can0 124#ABC",
                    ]
                ),
                encoding="utf-8",
            )
            frames, stats = parse_can_log(candump)
            self.assertEqual(len(frames), 2)
            self.assertEqual(stats.parsed, 2)
            self.assertEqual(stats.skipped, 2)
            self.assertEqual(stats.out_of_order, 1)
            self.assertEqual([frame.timestamp for frame in frames], [1.0, 2.0])
            self.assertTrue(frames[1].extended)

            csv_log = Path(temp_dir) / "sample.csv"
            csv_log.write_text(
                "\n".join(
                    [
                        "timestamp,interface,id,data",
                        "0.2,can1,0x456,AA BB",
                        "0.1,can1,0x123,01",
                        "bad,can1,0x123,ZZ",
                    ]
                ),
                encoding="utf-8",
            )
            csv_frames, csv_stats = parse_can_log(csv_log)
            self.assertEqual(len(csv_frames), 2)
            self.assertEqual(csv_stats.skipped, 1)
            self.assertEqual(csv_frames[0].arbitration_id, 0x123)
            self.assertEqual(csv_frames[1].data.hex().upper(), "AABB")

    def test_synthetic_log_ranks_rpm_and_speed_candidates_first(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path, anchors = _write_synthetic_session(Path(temp_dir))
            frames, stats = parse_can_log(log_path)
            session = load_guided_session(labels_path)
            analysis = analyze_frames(frames, session=session, parse_stats=stats)

            rpm = analysis["candidateRankings"]["rpm"][0]
            self.assertEqual(rpm["canId"], "0x100")
            self.assertEqual(rpm["startBit"], 0)
            self.assertEqual(rpm["length"], 16)
            self.assertEqual(rpm["endian"], "big")
            self.assertFalse(rpm["signed"])
            self.assertGreater(rpm["confidence"], 0.75)
            self.assertTrue(rpm["verified"])
            self.assertEqual(rpm["verificationStatus"], "verified")
            self.assertIn("bitAnalysis", rpm["pipeline"]["stages"])
            self.assertIn("correlation", rpm["pipeline"]["stages"])
            self.assertIn("scaling", rpm["pipeline"]["stages"])
            self.assertIn("validation", rpm["pipeline"]["stages"])

            speed = analysis["candidateRankings"]["speedKph"][0]
            self.assertEqual(speed["canId"], "0x101")
            self.assertEqual(speed["startBit"], 16)
            self.assertEqual(speed["length"], 16)
            self.assertEqual(speed["endian"], "little")
            self.assertFalse(speed["signed"])
            self.assertGreater(speed["confidence"], 0.75)
            self.assertTrue(speed["verified"])

            self.assertEqual(analysis["signalDecisions"]["rpm"]["status"], "verified")
            self.assertEqual(analysis["signalDecisions"]["speedKph"]["status"], "verified")
            packet_decisions = {item["canId"]: item for item in analysis["packetDecisions"]}
            self.assertEqual(packet_decisions["0x100"]["assignedSignals"], ["rpm"])
            self.assertEqual(packet_decisions["0x101"]["assignedSignals"], ["speedKph"])
            self.assertEqual(packet_decisions["0x200"]["status"], "unknown")
            self.assertIn("confidence", packet_decisions["0x200"])

            signal_dictionary = build_signal_dictionary(analysis, source_log=str(log_path), source_labels=str(labels_path))
            self.assertEqual(validate_signal_dictionary(signal_dictionary), [])
            self.assertIn("rpm", signal_dictionary["signals"])
            self.assertIn("speedKph", signal_dictionary["signals"])

            signals_path = Path(temp_dir) / "can_signals.json"
            signals_path.write_text(json.dumps(signal_dictionary), encoding="utf-8")
            decoder = CanSignalDictionary.from_path(signals_path)
            decoded_rows = decoder.decode_frames(frames)
            self.assertTrue(any("rpm" in row["signals"] for row in decoded_rows))
            self.assertTrue(any("speedKph" in row["signals"] for row in decoded_rows))
            latest = decoded_rows[-1]["signals"]
            self.assertAlmostEqual(latest["rpm"], anchors["rpm"][-1]["value"], delta=2.0)
            self.assertAlmostEqual(latest["speedKph"], anchors["speedKph"][-1]["value"], delta=0.5)

    def test_unanchored_candidates_are_not_exported_as_human_signals(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path, _anchors = _write_synthetic_session(Path(temp_dir), include_anchors=False)
            frames, stats = parse_can_log(log_path)
            session = load_guided_session(labels_path)
            analysis = analyze_frames(frames, session=session, parse_stats=stats)

            rpm = analysis["candidateRankings"]["rpm"][0]
            self.assertFalse(rpm["verified"])
            self.assertEqual(rpm["pipeline"]["stages"]["scaling"]["verified"], False)

            signal_dictionary = build_signal_dictionary(analysis, source_log=str(log_path), source_labels=str(labels_path))
            self.assertEqual(signal_dictionary["signals"], {})
            self.assertIn("rpm", signal_dictionary["rejectedSignals"])
            self.assertGreater(signal_dictionary["rejectedSignals"]["rpm"]["confidence"], 0.0)

    def test_can_log_replay_produces_vehicle_state_overlays(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path, labels_path, _anchors = _write_synthetic_session(Path(temp_dir))
            frames, stats = parse_can_log(log_path)
            session = load_guided_session(labels_path)
            analysis = analyze_frames(frames, session=session, parse_stats=stats)
            signal_dictionary = build_signal_dictionary(analysis, source_log=str(log_path), source_labels=str(labels_path))
            signals_path = Path(temp_dir) / "can_signals.json"
            signals_path.write_text(json.dumps(signal_dictionary), encoding="utf-8")

            replay = CanLogSignalReplay(signals_path, log_path, repeat=False)
            replay._started_monotonic = 0.0
            overlay = replay.snapshot(now_monotonic=12.5)
            self.assertIn("rpm", overlay)
            self.assertIn("speedKph", overlay)
            self.assertIsInstance(overlay["rpm"], float)
            self.assertIsInstance(overlay["speedKph"], float)

    def test_non_byte_aligned_dictionary_decode_uses_shared_bitfield_extractor(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            signals_path = Path(temp_dir) / "can_signals.json"
            signals_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "signals": {
                            "testSignal": {
                                "canId": "0x555",
                                "startBit": 4,
                                "length": 12,
                                "endian": "big",
                                "signed": False,
                                "scale": 1.0,
                                "offset": 0.0,
                                "unit": "raw",
                                "confidence": 0.9,
                                "verified": True,
                                "pipeline": {},
                                "evidence": {},
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            decoder = CanSignalDictionary.from_path(signals_path)
            decoded = decoder.decode_frame(CanFrame(timestamp=1.0, interface="can0", arbitration_id=0x555, data=bytes.fromhex("ABCD")))
            self.assertEqual(decoded["testSignal"], 0xBCD)

    def test_lagged_anchor_correlation_recovers_delayed_signal(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            log_path = root / "lagged.log"
            labels_path = root / "lagged_labels.json"
            delay = 0.3
            lines: list[str] = []
            anchors: list[dict[str, float]] = []
            for index in range(240):
                timestamp = round(index * 0.1, 3)
                rpm, _speed = _synthetic_values(max(0.0, timestamp - delay))
                rpm_raw = int(round(rpm * 4.0))
                data = rpm_raw.to_bytes(2, "big") + bytes([0, 0, 0, 0, 0, 0])
                lines.append(f"({timestamp:.3f}) can0 300#{data.hex().upper()}")
                if index % 5 == 0 and 1.0 <= timestamp <= 22.0:
                    anchor_rpm, _ = _synthetic_values(timestamp)
                    anchors.append({"timestamp": timestamp, "value": anchor_rpm})
            log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            labels_path.write_text(json.dumps({"anchors": {"rpm": anchors}}), encoding="utf-8")

            frames, stats = parse_can_log(log_path)
            session = load_guided_session(labels_path)
            analysis = analyze_frames(frames, session=session, parse_stats=stats, targets=("rpm",), max_candidates=5)
            rpm = analysis["candidateRankings"]["rpm"][0]
            self.assertEqual(rpm["canId"], "0x300")
            self.assertEqual(rpm["startBit"], 0)
            self.assertEqual(rpm["length"], 16)
            self.assertAlmostEqual(rpm["evidence"]["lagSec"], delay, delta=0.051)
            self.assertGreater(rpm["evidence"]["anchorR2"], 0.98)
            self.assertTrue(rpm["verified"])

    def test_health_baseline_diagnosis_flags_matched_state_anomaly_without_repair_directive(self) -> None:
        good_rows = _decoded_rows(rpm_offset=0.0)
        suspect_rows = _decoded_rows(rpm_offset=420.0)
        baseline = build_health_baseline(
            good_rows,
            source="car-a.jsonl",
            vehicle_profile="example-platform",
            purpose="known-good baseline validation",
            owner_consent=True,
        )
        report = diagnose_against_baseline(
            baseline,
            suspect_rows,
            source="car-b.jsonl",
            vehicle_profile="example-platform",
            purpose="owner-authorized engine fault triage",
            owner_consent=True,
        )
        self.assertEqual(report["summary"]["status"], "anomalies_detected")
        self.assertGreaterEqual(report["summary"]["findingCount"], 1)
        top = report["findings"][0]
        self.assertEqual(top["signal"], "rpm")
        self.assertEqual(top["state"], "idle_stationary")
        self.assertTrue(top["notRepairDirective"])
        self.assertIn("nextChecks", top)
        self.assertTrue(report["responsibleUse"]["ownerConsentConfirmed"])

    def test_health_baseline_requires_owner_consent_and_recorded_purpose(self) -> None:
        with self.assertRaises(ValueError):
            build_health_baseline(
                _decoded_rows(rpm_offset=0.0),
                source="car-a.jsonl",
                vehicle_profile="example-platform",
                purpose="",
                owner_consent=True,
            )
        with self.assertRaises(ValueError):
            build_health_baseline(
                _decoded_rows(rpm_offset=0.0),
                source="car-a.jsonl",
                vehicle_profile="example-platform",
                purpose="known-good baseline validation",
                owner_consent=False,
            )

    def test_consent_record_retention_and_customer_report_template(self) -> None:
        purpose = "owner-authorized engine fault triage"
        consent = build_consent_record(
            owner_reference="work-order-1234",
            vehicle_profile="example-platform",
            purpose=purpose,
            owner_consent=True,
            retention_days=14,
        )
        self.assertEqual(consent["kind"], "vehicle_diagnostic_consent")
        self.assertEqual(consent["retentionPolicy"]["retentionDays"], 14)
        baseline = build_health_baseline(
            _decoded_rows(rpm_offset=0.0),
            source="car-a.jsonl",
            vehicle_profile="example-platform",
            purpose=purpose,
            owner_consent=True,
            consent_record=consent,
            retention_days=14,
        )
        report = diagnose_against_baseline(
            baseline,
            _decoded_rows(rpm_offset=420.0),
            source="car-b.jsonl",
            vehicle_profile="example-platform",
            purpose=purpose,
            owner_consent=True,
            consent_record=consent,
            retention_days=14,
        )
        rendered = render_customer_report(report)
        self.assertIn("Vehicle Diagnostic Evidence Report", rendered)
        self.assertIn("Not a repair directive: true", rendered)
        self.assertIn("delete-after", rendered)

    def test_consent_record_rejects_unapproved_purpose(self) -> None:
        consent = build_consent_record(
            owner_reference="work-order-1234",
            vehicle_profile="example-platform",
            purpose="baseline only",
            owner_consent=True,
            retention_days=30,
        )
        with self.assertRaises(ValueError):
            diagnose_against_baseline(
                build_health_baseline(
                    _decoded_rows(rpm_offset=0.0),
                    source="car-a.jsonl",
                    vehicle_profile="example-platform",
                    purpose="baseline only",
                    owner_consent=True,
                    consent_record=consent,
                ),
                _decoded_rows(rpm_offset=420.0),
                source="car-b.jsonl",
                vehicle_profile="example-platform",
                purpose="different purpose",
                owner_consent=True,
                consent_record=consent,
            )


def _write_synthetic_session(root: Path, include_anchors: bool = True) -> tuple[Path, Path, dict[str, list[dict[str, float]]]]:
    log_path = root / "synthetic.log"
    labels_path = root / "labels.json"
    lines: list[str] = []
    rpm_anchors: list[dict[str, float]] = []
    speed_anchors: list[dict[str, float]] = []
    for index in range(200):
        timestamp = round(index * 0.1, 3)
        rpm, speed = _synthetic_values(timestamp)
        rpm_raw = int(round(rpm * 4.0))
        speed_raw = int(round(speed * 100.0))
        rpm_data = rpm_raw.to_bytes(2, "big") + bytes([(index * 7) & 0xFF, (255 - index) & 0xFF, 0, 0, 0, 0])
        speed_data = bytes([(index * 13) & 0xFF, (index * 3) & 0xFF]) + speed_raw.to_bytes(2, "little") + bytes([0, 0, 0, 0])
        noise_data = bytes([(index + offset) & 0xFF for offset in range(8)])
        lines.append(f"({timestamp:.3f}) can0 100#{rpm_data.hex().upper()}")
        lines.append(f"({timestamp:.3f}) can0 101#{speed_data.hex().upper()}")
        lines.append(f"({timestamp:.3f}) can0 200#{noise_data.hex().upper()}")
        if include_anchors and timestamp in {0.5, 6.0, 12.0, 19.9}:
            rpm_anchors.append({"timestamp": timestamp, "value": rpm})
        if include_anchors and timestamp in {0.5, 11.0, 14.0, 19.9}:
            speed_anchors.append({"timestamp": timestamp, "value": speed})
    log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    labels_path.write_text(
        json.dumps(
            {
                "windows": [
                    {"label": "idle", "start": 0.0, "end": 3.0},
                    {"label": "stationary_rev", "start": 4.0, "end": 8.0},
                    {"label": "accelerate", "start": 9.0, "end": 14.0},
                    {"label": "decelerate", "start": 15.0, "end": 19.9},
                ],
                "anchors": {"rpm": rpm_anchors, "speedKph": speed_anchors},
            }
        ),
        encoding="utf-8",
    )
    return log_path, labels_path, {"rpm": rpm_anchors, "speedKph": speed_anchors}


def _synthetic_values(timestamp: float) -> tuple[float, float]:
    if timestamp <= 3.0:
        return 820.0 + 8.0 * timestamp, 0.0
    if timestamp <= 8.0:
        return 900.0 + (timestamp - 4.0) * 650.0, 0.0
    if timestamp <= 14.0:
        speed = max(0.0, min(80.0, (timestamp - 9.0) * 16.0))
        return 1400.0 + speed * 18.0, speed
    speed = max(10.0, 80.0 - (timestamp - 15.0) * 14.0)
    return 1200.0 + speed * 14.0, speed


def _decoded_rows(rpm_offset: float) -> list[dict]:
    rows = []
    for index in range(100):
        timestamp = round(index * 0.2, 3)
        rpm, speed = _synthetic_values(timestamp)
        if speed <= 3.0 and 450.0 <= rpm <= 1300.0:
            rpm += rpm_offset
        rows.append({"timestamp": timestamp, "signals": {"rpm": rpm, "speedKph": speed}})
    return rows


if __name__ == "__main__":
    unittest.main()
