#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import select
import sys
import tempfile
import threading
import unittest
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.can_reverse_workbench.elm327 import (  # noqa: E402
    Elm327PollResult,
    capture_elm327_obd_log,
    clean_elm327_lines,
    elm327_poll_result_to_jsonl_row,
    extract_mode01_response,
    parse_pid_selection,
)
from tools.can_reverse_workbench.obd_anchors import build_guided_session_payload_from_obd_log, decode_mode01_response  # noqa: E402


class Elm327CaptureTest(unittest.TestCase):
    def test_pid_selection_accepts_names_hex_and_commands(self) -> None:
        self.assertEqual(parse_pid_selection(["rpm", "0x0D,0110", "throttle"]), (0x0C, 0x0D, 0x10, 0x11))

    def test_extracts_mode01_response_from_common_elm327_text(self) -> None:
        lines = clean_elm327_lines("010C\rSEARCHING...\r7E8 04 41 0C 1A F8\r>")
        response = extract_mode01_response(lines, 0x0C)

        self.assertEqual(response, "41 0C 1A F8")
        self.assertEqual(decode_mode01_response(response).values["rpm"], 1726.0)

    def test_jsonl_row_is_compatible_with_existing_obd_anchor_import(self) -> None:
        decoded = decode_mode01_response("41 0D 2A", timestamp=10.5)
        row = elm327_poll_result_to_jsonl_row(
            Elm327PollResult(
                timestamp=10.5,
                command="010D",
                pid=0x0D,
                raw_text="41 0D 2A\r>",
                raw_lines=("41 0D 2A",),
                response="41 0D 2A",
                decoded=decoded,
            )
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "elm327.jsonl"
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            payload = build_guided_session_payload_from_obd_log(path)

        self.assertEqual(payload["anchors"]["speedKph"], [{"timestamp": 10.5, "value": 42.0}])
        self.assertEqual(payload["obd"]["pidsSeen"], ["0x0D"])

    def test_capture_reads_from_fake_elm327_serial_device(self) -> None:
        master_fd, slave_fd = os.openpty()
        device = os.ttyname(slave_fd)
        stop = threading.Event()
        thread = threading.Thread(target=_fake_elm327, args=(master_fd, stop), daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                out = Path(temp_dir) / "elm327.jsonl"
                summary = capture_elm327_obd_log(
                    device=device,
                    out_path=out,
                    baud=38400,
                    pids=(0x0C, 0x0D),
                    duration_sec=0.18,
                    sample_interval_sec=0.01,
                    timeout_sec=0.5,
                    initialize=True,
                    supported_filter=True,
                    include_errors=True,
                )
                payload = build_guided_session_payload_from_obd_log(out)
        finally:
            stop.set()
            os.close(slave_fd)
            os.close(master_fd)
            thread.join(timeout=1.0)

        self.assertGreaterEqual(summary["rows"], 3)
        self.assertIn("rpm", payload["anchors"])
        self.assertIn("speedKph", payload["anchors"])
        self.assertEqual(payload["obd"]["supportedPids"], ["0x04", "0x05", "0x0C", "0x0D"])


def _fake_elm327(master_fd: int, stop: threading.Event) -> None:
    os.set_blocking(master_fd, False)
    buffer = bytearray()
    while not stop.is_set():
        try:
            readable, _, _ = select.select([master_fd], [], [], 0.05)
        except OSError:
            return
        if not readable:
            continue
        try:
            chunk = os.read(master_fd, 256)
        except (BlockingIOError, OSError):
            continue
        if not chunk:
            continue
        buffer.extend(chunk)
        while b"\r" in buffer:
            raw, _, rest = buffer.partition(b"\r")
            buffer = bytearray(rest)
            command = raw.decode("ascii", errors="ignore").strip().upper()
            response = _fake_response(command)
            try:
                os.write(master_fd, response.encode("ascii"))
            except OSError:
                return


def _fake_response(command: str) -> str:
    if command.startswith("AT"):
        return "OK\r>"
    if command == "0100":
        return "41 00 18 18 00 00\r>"
    if command == "010C":
        return "41 0C 0F A0\r>"
    if command == "010D":
        return "41 0D 2A\r>"
    return "NO DATA\r>"


if __name__ == "__main__":
    unittest.main()
