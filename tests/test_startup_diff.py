#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.can_reverse_workbench.startup_diff import compare_startup_logs  # noqa: E402


class StartupDiffTest(unittest.TestCase):
    def test_ranks_byte_that_moves_in_good_start_but_sticks_in_failed_start(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            good = root / "good.log"
            failed = root / "failed.log"
            _write_start_log(good, stuck=False)
            _write_start_log(failed, stuck=True)

            result = compare_startup_logs(
                good_logs=[good],
                failed_log=failed,
                window_seconds=3.0,
                min_samples=3,
                min_score=1.0,
                top=5,
            )

            self.assertGreater(result["findingCount"], 0)
            top = result["findings"][0]
            self.assertEqual(top["canId"], "0x184")
            self.assertEqual(top["byteIndex"], 2)
            self.assertIn("flat_in_failed", top["reason"])


def _write_start_log(path: Path, *, stuck: bool) -> None:
    lines = []
    for index in range(20):
        timestamp = index * 0.1
        moving_byte = 0x20 if stuck else 0x20 + index * 3
        data = bytes([0x10, 0x20, moving_byte & 0xFF, 0x40, 0x50, 0x60, 0x70, 0x80])
        stable_data = bytes([0xAA, 0x55, 0xAA, 0x55, 0, 0, 0, 0])
        lines.append(f"({timestamp:.3f}) can0 184#{data.hex().upper()}")
        lines.append(f"({timestamp:.3f}) can0 200#{stable_data.hex().upper()}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
