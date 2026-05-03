#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.can_reverse_workbench.capture_session import (  # noqa: E402
    build_capture_session_from_logs,
    build_guided_session_payload_from_capture,
    create_capture_session,
    export_capture_session,
    import_can_log,
    import_obd_anchor_log,
)
from tools.can_reverse_workbench.labels import load_guided_session  # noqa: E402
from tools.can_reverse_workbench.parser import parse_can_log  # noqa: E402


class CaptureSessionTest(unittest.TestCase):
    def test_builds_sqlite_capture_session_and_exports_analyzer_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            can_log = _write_can_log(root)
            obd_log = _write_obd_log(root)
            db_path = root / "capture.sqlite"
            out_dir = root / "exported"

            summary = build_capture_session_from_logs(
                db_path=db_path,
                can_log=can_log,
                obd_log=obd_log,
                out_dir=out_dir,
                session_id="test-session",
                vehicle_profile="test vehicle profile",
                purpose="owner-authorized raw CAN discovery",
                thermal_start_class="cold",
                off_time_sec=3600.0,
                session_labels=["known_good", "startup"],
                decoder_version="can_signals_v1:test",
            )

            self.assertEqual(summary.session_id, "test-session")
            self.assertEqual(summary.raw_can_frames, 2)
            self.assertEqual(summary.anchor_samples, 3)
            self.assertEqual(summary.supported_pids, 4)
            self.assertEqual(summary.warnings, 0)

            exported_can = Path(summary.exports["rawCanLog"])
            exported_labels = Path(summary.exports["guidedSession"])
            exported_obd = Path(summary.exports["obdAnchorJsonl"])
            self.assertTrue(exported_can.exists())
            self.assertTrue(exported_labels.exists())
            self.assertTrue(exported_obd.exists())

            frames, stats = parse_can_log(exported_can)
            self.assertEqual(stats.parsed, 2)
            self.assertEqual(frames[0].arbitration_id, 0x100)
            self.assertEqual(frames[1].data_hex, "2A")

            guided = load_guided_session(exported_labels)
            self.assertEqual(guided.anchors["rpm"][0].value, 1000.0)
            self.assertEqual(guided.anchors["speedKph"][0].value, 42.0)
            self.assertEqual(guided.anchors["gpsSpeedKph"][0].value, 42.1)

            payload = json.loads(exported_labels.read_text(encoding="utf-8"))
            self.assertEqual(payload["vehicleProfile"], "test vehicle profile")
            self.assertEqual(payload["captureSession"]["rawCanFrames"], 2)
            self.assertEqual(payload["captureSession"]["thermalStartClass"], "cold")
            self.assertEqual(payload["captureSession"]["offTimeSec"], 3600.0)
            self.assertEqual(payload["captureSession"]["sessionLabels"], ["known_good", "startup"])
            self.assertEqual(payload["captureSession"]["decoderVersion"], "can_signals_v1:test")
            self.assertEqual(payload["obd"]["supportedPids"], ["0x04", "0x05", "0x0C", "0x0D"])

    def test_can_import_and_obd_import_can_run_as_separate_steps(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            db_path = root / "capture.sqlite"
            session_id = create_capture_session(db_path, session_id="manual-session")

            can_summary = import_can_log(db_path, session_id, _write_can_log(root))
            obd_summary = import_obd_anchor_log(db_path, session_id, _write_obd_log(root))
            exports = export_capture_session(db_path, session_id, root / "manual-export")
            payload = build_guided_session_payload_from_capture(db_path, session_id)

            self.assertEqual(can_summary.rows, 2)
            self.assertEqual(obd_summary.rows, 3)
            self.assertEqual(payload["captureSession"]["id"], "manual-session")
            self.assertTrue(Path(exports["manifest"]).exists())

            with sqlite3.connect(db_path) as db:
                raw_count = db.execute("SELECT COUNT(*) FROM raw_can_frames").fetchone()[0]
                anchor_count = db.execute("SELECT COUNT(*) FROM anchor_samples").fetchone()[0]
            self.assertEqual(raw_count, 2)
            self.assertEqual(anchor_count, 3)


def _write_can_log(root: Path) -> Path:
    path = root / "raw.log"
    path.write_text(
        "\n".join(
            [
                "(1.000000) can0 100#0FA0",
                "(1.100000) can0 101#2A",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    return path


def _write_obd_log(root: Path) -> Path:
    path = root / "obd.jsonl"
    rows = [
        {"timestamp": 1.0, "response": "04 41 0C 0F A0 00 00 00"},
        {"timestamp": 1.1, "pid": "0x0D", "data": "2A"},
        {"timestamp": 1.2, "signal": "gpsSpeedKph", "value": 42.1},
        {"timestamp": 1.3, "response": "06 41 00 18 18 00 00 00 00"},
    ]
    path.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")
    return path


if __name__ == "__main__":
    unittest.main()
