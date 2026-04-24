#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.can_diagnostics import CanDiagnosticsEngine  # noqa: E402
from tools.can_reverse_workbench.parser import CanFrame  # noqa: E402


class CanDiagnosticsEngineTest(unittest.TestCase):
    def test_flags_bus_silence_when_no_frames_arrive(self) -> None:
        engine = CanDiagnosticsEngine(source="test", no_frame_grace_seconds=1.0)
        engine._started_monotonic = 0.0
        snapshot = engine.snapshot(now_monotonic=2.0)
        self.assertFalse(snapshot["ok"])
        self.assertTrue(_has_finding(snapshot, "bus_silence"))

    def test_learns_cadence_and_flags_can_id_dropout(self) -> None:
        engine = CanDiagnosticsEngine(source="test", min_stale_seconds=0.2, stale_interval_multiplier=4.0)
        for index in range(8):
            engine.observe_frame(_frame(0x100, "0102"), {"rpm": 1000.0 + index}, now_monotonic=index * 0.1)
        snapshot = engine.snapshot(now_monotonic=1.3)
        self.assertFalse(snapshot["ok"])
        self.assertTrue(_has_finding(snapshot, "can_id_dropout", subject="0x100"))

    def test_flags_dlc_change(self) -> None:
        engine = CanDiagnosticsEngine(source="test")
        engine.observe_frame(_frame(0x100, "01020304"), {}, now_monotonic=1.0)
        engine.observe_frame(_frame(0x100, "0102"), {}, now_monotonic=1.1)
        snapshot = engine.snapshot(now_monotonic=1.2)
        self.assertFalse(snapshot["ok"])
        self.assertTrue(_has_finding(snapshot, "dlc_changed", subject="0x100"))

    def test_flags_stuck_dynamic_decoded_signal(self) -> None:
        engine = CanDiagnosticsEngine(source="test", stuck_window_seconds=3.0, stuck_min_samples=8)
        for index in range(10):
            engine.observe_frame(_frame(0x101, "0000"), {"speedKph": 0.0}, now_monotonic=index * 0.3)
        snapshot = engine.snapshot(now_monotonic=3.0)
        self.assertFalse(snapshot["ok"])
        self.assertTrue(_has_finding(snapshot, "payload_stuck", subject="0x101"))
        self.assertTrue(_has_finding(snapshot, "decoded_signal_stuck", subject="speedKph"))


def _frame(can_id: int, data_hex: str) -> CanFrame:
    return CanFrame(timestamp=0.0, interface="can0", arbitration_id=can_id, data=bytes.fromhex(data_hex))


def _has_finding(snapshot: dict, code: str, subject: str | None = None) -> bool:
    for finding in snapshot.get("findings", []):
        if finding.get("code") != code:
            continue
        if subject is not None and finding.get("subject") != subject:
            continue
        self_confidence = finding.get("confidence")
        if not isinstance(self_confidence, (int, float)) or self_confidence <= 0:
            continue
        return True
    return False


if __name__ == "__main__":
    unittest.main()
