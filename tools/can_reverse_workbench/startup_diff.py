#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.can_reverse_workbench.parser import parse_can_log  # noqa: E402


@dataclass
class ByteStats:
    count: int = 0
    mean: float = 0.0
    m2: float = 0.0
    minimum: int | None = None
    maximum: int | None = None
    first: int | None = None
    last: int | None = None

    @property
    def stddev(self) -> float:
        if self.count < 2:
            return 0.0
        return math.sqrt(max(0.0, self.m2 / (self.count - 1)))

    @property
    def value_range(self) -> float:
        if self.minimum is None or self.maximum is None:
            return 0.0
        return float(self.maximum - self.minimum)

    def observe(self, value: int) -> None:
        if self.count == 0:
            self.first = value
            self.minimum = value
            self.maximum = value
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        self.m2 += delta * (value - self.mean)
        self.minimum = value if self.minimum is None else min(self.minimum, value)
        self.maximum = value if self.maximum is None else max(self.maximum, value)
        self.last = value


def compare_startup_logs(
    *,
    good_logs: list[str | Path],
    failed_log: str | Path,
    window_seconds: float = 8.0,
    start_offset_seconds: float = 0.0,
    min_samples: int = 3,
    min_spread: float = 2.0,
    dynamic_range: float = 8.0,
    stuck_range_ratio: float = 0.25,
    min_score: float = 2.0,
    top: int = 25,
) -> dict[str, Any]:
    good_stats, good_parse = _collect_stats(good_logs, window_seconds, start_offset_seconds)
    failed_stats, failed_parse = _collect_stats([failed_log], window_seconds, start_offset_seconds)

    findings = []
    for key in sorted(set(good_stats) | set(failed_stats)):
        good = good_stats.get(key)
        failed = failed_stats.get(key)
        finding = _score_byte(
            key,
            good,
            failed,
            min_samples=min_samples,
            min_spread=min_spread,
            dynamic_range=dynamic_range,
            stuck_range_ratio=stuck_range_ratio,
        )
        if finding is not None and finding["score"] >= min_score:
            findings.append(finding)

    findings.sort(key=lambda item: item["score"], reverse=True)
    return {
        "version": 1,
        "mode": "startup_diff",
        "goodLogs": [str(path) for path in good_logs],
        "failedLog": str(failed_log),
        "windowSeconds": window_seconds,
        "startOffsetSeconds": start_offset_seconds,
        "minSamples": min_samples,
        "scoring": {
            "minSpread": min_spread,
            "dynamicRange": dynamic_range,
            "stuckRangeRatio": stuck_range_ratio,
            "minScore": min_score,
        },
        "parseStats": {
            "good": good_parse,
            "failed": failed_parse,
        },
        "findings": findings[:top],
        "findingCount": len(findings),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare known-good startup CAN logs against a failed startup log and rank raw fields that changed."
    )
    parser.add_argument("--good", action="append", required=True, help="known-good startup candump/CSV log; repeatable")
    parser.add_argument("--bad", "--failed", dest="failed", required=True, help="failed startup candump/CSV log")
    parser.add_argument("--window-sec", type=float, default=8.0, help="seconds to compare from each log start")
    parser.add_argument("--start-offset-sec", type=float, default=0.0, help="seconds after first frame to start comparison")
    parser.add_argument("--min-samples", type=int, default=3, help="minimum byte samples required to score")
    parser.add_argument("--min-score", type=float, default=2.0, help="minimum score to report")
    parser.add_argument("--top", type=int, default=25, help="number of findings to print/store")
    parser.add_argument("--out", help="optional JSON output path")
    args = parser.parse_args(argv)

    try:
        result = compare_startup_logs(
            good_logs=[Path(path) for path in args.good],
            failed_log=Path(args.failed),
            window_seconds=args.window_sec,
            start_offset_seconds=args.start_offset_sec,
            min_samples=args.min_samples,
            min_score=args.min_score,
            top=args.top,
        )
    except FileNotFoundError as exc:
        print(f"[startup-diff] missing log file: {exc.filename}", file=sys.stderr)
        return 2
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"[startup-diff] wrote {out_path}")
    _print_summary(result)
    return 0


def _collect_stats(
    paths: list[str | Path],
    window_seconds: float,
    start_offset_seconds: float,
) -> tuple[dict[tuple[str, int], ByteStats], list[dict[str, Any]]]:
    stats: dict[tuple[str, int], ByteStats] = {}
    parse_summaries: list[dict[str, Any]] = []
    for path in paths:
        frames, parse_stats = parse_can_log(path)
        parse_summaries.append(
            {
                "path": str(path),
                "parsed": parse_stats.parsed,
                "skipped": parse_stats.skipped,
                "outOfOrder": parse_stats.out_of_order,
                "warnings": parse_stats.warnings,
            }
        )
        if not frames:
            continue
        start = frames[0].timestamp + start_offset_seconds
        end = start + window_seconds
        for frame in frames:
            if frame.timestamp < start or frame.timestamp > end:
                continue
            for byte_index, value in enumerate(frame.data):
                stats.setdefault((frame.id_hex, byte_index), ByteStats()).observe(value)
    return stats, parse_summaries


def _score_byte(
    key: tuple[str, int],
    good: ByteStats | None,
    failed: ByteStats | None,
    *,
    min_samples: int,
    min_spread: float,
    dynamic_range: float,
    stuck_range_ratio: float,
) -> dict[str, Any] | None:
    can_id, byte_index = key
    if good is None and failed is None:
        return None
    if good is None:
        if failed is None or failed.count < min_samples:
            return None
        return _finding(can_id, byte_index, "new_in_failed_start", 3.0, None, failed)
    if failed is None:
        if good.count < min_samples:
            return None
        return _finding(can_id, byte_index, "missing_in_failed_start", 4.0, good, None)
    if good.count < min_samples and failed.count < min_samples:
        return None

    spread = max(good.stddev, min_spread)
    mean_delta = failed.mean - good.mean
    z_score = abs(mean_delta) / spread
    percent_delta = abs(mean_delta) / max(abs(good.mean), 1.0)
    stuck_bonus = 0.0
    reasons = []

    if good.value_range >= dynamic_range and failed.value_range <= max(min_spread, good.value_range * stuck_range_ratio):
        stuck_bonus = min(3.0, good.value_range / max(failed.value_range, min_spread) * 0.35)
        reasons.append("changed_during_good_starts_but_flat_in_failed_start")

    if z_score >= 2.5:
        reasons.append("mean_shift_high_z_score")
    if percent_delta >= 0.10:
        reasons.append("mean_shift_over_10_percent")
    if not reasons:
        reasons.append("moderate_raw_byte_change")

    score = z_score + min(2.0, percent_delta * 3.0) + stuck_bonus
    return _finding(can_id, byte_index, ",".join(reasons), score, good, failed)


def _finding(
    can_id: str,
    byte_index: int,
    reason: str,
    score: float,
    good: ByteStats | None,
    failed: ByteStats | None,
) -> dict[str, Any]:
    return {
        "canId": can_id,
        "byteIndex": byte_index,
        "reason": reason,
        "score": round(score, 3),
        "good": _stats_json(good),
        "failed": _stats_json(failed),
        "meanDelta": None if good is None or failed is None else round(failed.mean - good.mean, 3),
        "percentDelta": None
        if good is None or failed is None
        else round((failed.mean - good.mean) / max(abs(good.mean), 1.0), 4),
        "zScore": None
        if good is None or failed is None
        else round(abs(failed.mean - good.mean) / max(good.stddev, 2.0), 3),
    }


def _stats_json(stats: ByteStats | None) -> dict[str, Any] | None:
    if stats is None:
        return None
    return {
        "samples": stats.count,
        "mean": round(stats.mean, 3),
        "stddev": round(stats.stddev, 3),
        "min": stats.minimum,
        "max": stats.maximum,
        "range": round(stats.value_range, 3),
        "first": stats.first,
        "last": stats.last,
    }


def _print_summary(result: dict[str, Any]) -> None:
    print(
        "[startup-diff] compared "
        f"{len(result['goodLogs'])} good log(s) to {result['failedLog']} "
        f"over {result['windowSeconds']:.1f}s"
    )
    if not result["findings"]:
        print("[startup-diff] no raw byte changes exceeded the score threshold")
        return
    print("[startup-diff] top raw CAN byte changes:")
    for index, item in enumerate(result["findings"], start=1):
        good = item["good"] or {}
        failed = item["failed"] or {}
        print(
            f"{index:02d}. {item['canId']} byte {item['byteIndex']} "
            f"score={item['score']} reason={item['reason']} "
            f"good_mean={good.get('mean')} failed_mean={failed.get('mean')} "
            f"good_range={good.get('range')} failed_range={failed.get('range')} "
            f"delta_pct={item['percentDelta']}"
        )


if __name__ == "__main__":
    raise SystemExit(main())
