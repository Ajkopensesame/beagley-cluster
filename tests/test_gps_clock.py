#!/usr/bin/env python3
"""Decision logic of tools/bbb_hub/gps_clock.py (pure function + injected clock setter)."""
from __future__ import annotations

import os
import sys
import unittest
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "bbb_hub"))

import gps_clock  # noqa: E402
from gps_clock import ClockDiscipline, Config, Tracker, evaluate_frame  # noqa: E402

GPS_EPOCH = datetime(2026, 10, 3, 4, 35, 19, tzinfo=timezone.utc).timestamp()


def frame(utc_s: float, *, valid: bool = True, fix: bool = True, sats: int = 8) -> dict:
    return {
        "type": "vehicle_state",
        "version": 1,
        "gps": {"utcMs": int(utc_s * 1000), "utcValid": valid, "fixValid": fix, "satellites": sats},
    }


class FakeWorld:
    """Fake wall + monotonic clocks, plus a recording setter. wall = GPS time - skew."""

    def __init__(self, skew_s: float, config: Config, gps_epoch: float = GPS_EPOCH) -> None:
        self.mono = 1000.0
        self.gps0 = gps_epoch
        self.skew = skew_s  # wall = true - skew  (positive skew: system clock is behind GPS)
        self.set_calls: list[float] = []
        self.lines: list[str] = []
        self.setter_error: Exception | None = None
        self.discipline = ClockDiscipline(
            config,
            setter=self._set,
            wall_clock=lambda: self.true_now() - self.skew,
            monotonic=lambda: self.mono,
            emit=self.lines.append,
        )

    def true_now(self) -> float:
        return self.gps0 + (self.mono - 1000.0)

    def _set(self, epoch: float) -> None:
        if self.setter_error is not None:
            raise self.setter_error
        self.set_calls.append(epoch)
        self.skew = self.true_now() - epoch  # the system clock now equals `epoch`

    def send(self, n: int = 1, step_s: float = 0.1, **kw):
        decision = None
        for _ in range(n):
            self.mono += step_s
            decision = self.discipline.handle_frame(frame(self.true_now(), **kw))
        return decision

    def advance(self, seconds: float) -> None:
        self.mono += seconds


class EvaluateFrameTest(unittest.TestCase):
    def test_pure_function_does_not_mutate_and_needs_five_frames(self) -> None:
        cfg = Config()
        tracker = Tracker()
        wall = GPS_EPOCH - 3600.0
        for i in range(1, 5):
            tracker, decision = evaluate_frame(tracker, frame(GPS_EPOCH + i * 0.1), wall + i * 0.1, 10.0 + i * 0.1, cfg)
            self.assertEqual(decision.action, "none")
            self.assertEqual(tracker.streak, i)
        tracker, decision = evaluate_frame(tracker, frame(GPS_EPOCH + 0.5), wall + 0.5, 10.5, cfg)
        self.assertEqual(decision.action, "step")
        self.assertAlmostEqual(decision.offset_s, 3600.0, places=3)

    def test_within_threshold_is_not_a_step(self) -> None:
        cfg = Config(step_threshold_s=1.0)
        tracker = Tracker()
        decision = None
        for i in range(1, 6):
            tracker, decision = evaluate_frame(tracker, frame(GPS_EPOCH + i * 0.1), GPS_EPOCH + i * 0.1 - 0.9, 10.0 + i * 0.1, cfg)
        self.assertEqual(decision.action, "within")


class ClockDisciplineTest(unittest.TestCase):
    def test_steps_when_off_by_more_than_threshold(self) -> None:
        world = FakeWorld(skew_s=3600.0 * 24 * 176, config=Config())  # ~Apr vs Oct
        world.send(4)
        self.assertEqual(world.set_calls, [])
        world.send(1)
        self.assertEqual(len(world.set_calls), 1)
        self.assertAlmostEqual(world.set_calls[0], world.true_now(), delta=0.2)
        self.assertEqual(len(world.lines), 1)
        self.assertRegex(world.lines[0], r"^stepped clock by \+15206400\.\d{3} s to 2026-10-03T04:35:19\.\d{3}Z$")

    def test_negative_offset_logs_sign(self) -> None:
        world = FakeWorld(skew_s=-120.0, config=Config())
        world.send(5)
        self.assertEqual(len(world.set_calls), 1)
        self.assertIn("stepped clock by -120.", world.lines[0])

    def test_no_step_within_threshold(self) -> None:
        world = FakeWorld(skew_s=0.6, config=Config(step_threshold_s=1.0))
        world.send(10)
        self.assertEqual(world.set_calls, [])
        self.assertEqual(len(world.lines), 1)
        self.assertIn("no step", world.lines[0])

    def test_threshold_is_configurable(self) -> None:
        world = FakeWorld(skew_s=0.6, config=Config(step_threshold_s=0.5))
        world.send(5)
        self.assertEqual(len(world.set_calls), 1)

    def test_needs_five_consecutive_valid_frames(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config())
        world.send(4)
        world.send(1, valid=False)  # breaks the streak
        world.send(4)
        self.assertEqual(world.set_calls, [])
        world.send(1)
        self.assertEqual(len(world.set_calls), 1)

    def test_fewer_than_four_satellites_never_counts(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config())
        world.send(50, sats=3)
        self.assertEqual(world.set_calls, [])
        world.send(5, sats=4)
        self.assertEqual(len(world.set_calls), 1)

    def test_no_fix_or_missing_fields_never_count(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config())
        world.send(30, fix=False)
        for bad in (None, {}, {"gps": None}, {"gps": {}}, {"gps": {"utcValid": True}}, {"gps": {"utcValid": "true", "fixValid": True, "satellites": 9, "utcMs": 1}}, "x", [1]):
            for _ in range(10):
                world.mono += 0.1
                world.discipline.handle_frame(bad)
        self.assertEqual(world.set_calls, [])

    def test_held_or_stale_frames_are_ignored(self) -> None:
        # The hub reports utcValid=false for held and stale fixes; the helper must never step from them.
        world = FakeWorld(skew_s=500.0, config=Config())
        world.send(100, valid=False)
        self.assertEqual(world.set_calls, [])

    def test_rejects_pre_2026_date(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config(), gps_epoch=datetime(2025, 12, 31, 23, 0, tzinfo=timezone.utc).timestamp())
        world.send(20)
        self.assertEqual(world.set_calls, [])

    def test_rejects_post_2040_date_and_week_rollover_style_garbage(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config(), gps_epoch=datetime(2040, 1, 1, 0, 0, tzinfo=timezone.utc).timestamp())
        world.send(20)
        self.assertEqual(world.set_calls, [])
        world = FakeWorld(skew_s=100.0, config=Config(), gps_epoch=datetime(2006, 5, 1, tzinfo=timezone.utc).timestamp())
        world.send(20)
        self.assertEqual(world.set_calls, [])

    def test_accepts_boundary_dates(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config(), gps_epoch=datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc).timestamp())
        world.send(5)
        self.assertEqual(len(world.set_calls), 1)

    def test_dry_run_never_calls_setter(self) -> None:
        world = FakeWorld(skew_s=3600.0, config=Config(dry_run=True))
        world.send(10)
        self.assertEqual(world.set_calls, [])
        self.assertEqual(len(world.lines), 1)
        self.assertRegex(world.lines[0], r"^DRY RUN would step clock by \+3600\.\d{3} s to 2026-")

    def test_inconsistent_gps_time_jump_resets_streak(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config())
        world.send(4)
        world.mono += 0.1
        world.discipline.handle_frame(frame(world.true_now() + 30.0))  # GPS jumps +30 s in 0.1 s of real time
        self.assertEqual(world.set_calls, [])
        world.send(3)
        self.assertEqual(world.set_calls, [])  # streak restarted at the jump, only 4 consistent frames so far

    def test_recheck_is_rate_limited_and_steps_again_after_interval(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config(recheck_s=600.0))
        world.send(5)
        self.assertEqual(len(world.set_calls), 1)
        world.skew = 50.0  # clock drifts / is disturbed again
        world.send(50)
        self.assertEqual(len(world.set_calls), 1, "must not re-check inside GPS_CLOCK_RECHECK_S")
        world.advance(600.0)
        world.send(5)
        self.assertEqual(len(world.set_calls), 2)

    def test_recheck_within_threshold_makes_no_second_step(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config(recheck_s=60.0))
        world.send(5)
        world.advance(61.0)
        world.skew = 0.2
        world.send(6)
        self.assertEqual(len(world.set_calls), 1)

    def test_setter_failure_never_raises_and_is_retried_after_cooldown(self) -> None:
        world = FakeWorld(skew_s=100.0, config=Config())
        world.setter_error = PermissionError(1, "Operation not permitted")
        world.send(5)
        self.assertEqual(world.set_calls, [])
        self.assertIn("ERROR could not set clock (PermissionError", world.lines[0])
        world.send(50, step_s=0.1)  # 5 s later, still cooling down
        self.assertEqual(len(world.lines), 1)
        world.setter_error = None
        world.advance(gps_clock.SET_RETRY_COOLDOWN_S)
        world.send(5)
        self.assertEqual(len(world.set_calls), 1)

    def test_config_from_env(self) -> None:
        old = {k: os.environ.get(k) for k in ("GPS_CLOCK_HUB_URL", "GPS_CLOCK_STEP_THRESHOLD_S", "GPS_CLOCK_RECHECK_S", "GPS_CLOCK_DRY_RUN")}
        try:
            for k in old:
                os.environ.pop(k, None)
            cfg = Config.from_env()
            self.assertEqual((cfg.hub_url, cfg.step_threshold_s, cfg.recheck_s, cfg.dry_run), ("ws://127.0.0.1:8765", 1.0, 600.0, False))
            os.environ.update({"GPS_CLOCK_HUB_URL": "ws://x:1", "GPS_CLOCK_STEP_THRESHOLD_S": "2.5", "GPS_CLOCK_RECHECK_S": "nan", "GPS_CLOCK_DRY_RUN": "1"})
            cfg = Config.from_env()
            self.assertEqual((cfg.hub_url, cfg.step_threshold_s, cfg.recheck_s, cfg.dry_run), ("ws://x:1", 2.5, 600.0, True))
        finally:
            for k, v in old.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


if __name__ == "__main__":
    unittest.main()
