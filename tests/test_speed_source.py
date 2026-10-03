#!/usr/bin/env python3
"""Unit tests for the GPS-first speed source selector (tools/bbb_hub/speed_source.py)."""
from __future__ import annotations

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tools.bbb_hub.gps_nmea import NmeaGpsState  # noqa: E402
from tools.bbb_hub.speed_source import SpeedSourceSelector, parse_mode  # noqa: E402


def _nmea(body: str) -> str:
    checksum = 0
    for ch in body:
        checksum ^= ord(ch)
    return f"${body}*{checksum:02X}"


GGA = _nmea("GPGGA,123519,2728.188,S,15301.506,E,1,08,0.9,10.0,M,0.0,M,,")
RMC = _nmea("GPRMC,123519,A,2728.188,S,15301.506,E,022.4,084.4,230394,,")


class ParseModeTest(unittest.TestCase):
    def test_default_and_valid_values(self) -> None:
        self.assertEqual(parse_mode(None), ("gps_first", None))
        self.assertEqual(parse_mode(""), ("gps_first", None))
        for mode in ("gps_first", "pulse_only", "gps_only"):
            self.assertEqual(parse_mode(f" {mode.upper()} "), (mode, None))

    def test_unknown_value_falls_back_with_warning(self) -> None:
        mode, warning = parse_mode("bogus")
        self.assertEqual(mode, "gps_first")
        self.assertIn("bogus", warning)


class SelectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.t = 100.0
        self.sel = SpeedSourceSelector("gps_first", lost_s=2.0, regain_s=2.0)

    def tick(self, dt=0.0, *, gps=None, pulse=None):
        """gps: speed (valid fix) or None; pulse: speed or None."""
        self.t += dt
        return self.sel.select(
            self.t,
            gps_valid=gps is not None,
            gps_speed_kph=gps or 0.0,
            gps_age_s=0.1 if gps is not None else None,
            pulse_speed_kph=pulse,
            pulse_age_s=0.05 if pulse is not None else None,
        )

    def test_gps_wins_over_different_pulse(self) -> None:
        speed, health = self.tick(gps=50.0, pulse=40.0)
        self.assertEqual(speed, 50.0)
        self.assertEqual(health["active"], "gps")
        self.assertTrue(health["gpsFix"])
        self.assertEqual(health["ageS"], 0.1)

    def test_pulse_used_when_gps_never_had_fix(self) -> None:
        speed, health = self.tick(pulse=40.0)
        self.assertEqual((speed, health["active"], health["gpsFix"]), (40.0, "pulse", False))
        self.assertEqual(health["ageS"], 0.05)

    def test_fallback_only_after_fix_lost_for_lost_s(self) -> None:
        self.tick(gps=50.0, pulse=40.0)
        speed, health = self.tick(0.5, pulse=40.0)  # fix just lost: hold, bounded
        self.assertEqual((speed, health["active"], health["reason"]), (50.0, "gps", "gps_lost_holding"))
        speed, health = self.tick(1.4, pulse=40.0)  # 1.4 s lost: still within 2 s
        self.assertEqual(health["active"], "gps")
        speed, health = self.tick(0.6, pulse=40.0)  # 2.0 s lost
        self.assertEqual((speed, health["active"], health["reason"]), (40.0, "pulse", "gps_lost_pulse_fallback"))

    def test_short_gps_dropout_does_not_flap(self) -> None:
        self.tick(gps=50.0, pulse=40.0)
        self.tick(1.0, pulse=40.0)
        speed, health = self.tick(0.5, gps=51.0, pulse=40.0)
        self.assertEqual((speed, health["active"]), (51.0, "gps"))
        speed, health = self.tick(1.5, pulse=40.0)  # new loss window starts from scratch
        self.assertEqual(health["active"], "gps")

    def test_switch_back_needs_continuous_valid_fix(self) -> None:
        self.tick(gps=50.0, pulse=40.0)
        self.tick(0.1, pulse=40.0)
        self.tick(2.5, pulse=40.0)
        self.assertEqual(self.tick(0.1, pulse=40.0)[1]["active"], "pulse")
        speed, health = self.tick(0.1, gps=60.0, pulse=40.0)  # fix returns
        self.assertEqual((speed, health["active"], health["reason"]), (40.0, "pulse", "gps_regain_wait"))
        self.tick(1.5, gps=60.0, pulse=40.0)
        self.tick(0.2, pulse=40.0)  # glitch: fix lost again -> regain timer restarts
        self.tick(0.1, gps=60.0, pulse=40.0)
        speed, health = self.tick(1.5, gps=60.0, pulse=40.0)
        self.assertEqual(health["active"], "pulse")
        speed, health = self.tick(0.6, gps=61.0, pulse=40.0)
        self.assertEqual((speed, health["active"], health["reason"]), (61.0, "gps", "gps_regained"))

    def test_gps_used_at_once_when_no_pulse_to_flap_against(self) -> None:
        speed, health = self.tick(gps=33.0)
        self.assertEqual((speed, health["active"]), (33.0, "gps"))
        self.tick(0.1)
        self.tick(2.5)
        # pulse fallback, then pulse disappears while GPS valid -> GPS immediately
        self.tick(0.1, pulse=40.0)
        self.assertEqual(self.tick(0.1, gps=70.0)[1]["reason"], "pulse_unavailable")

    def test_both_invalid_gives_none_never_frozen(self) -> None:
        self.tick(gps=50.0, pulse=40.0)
        self.tick(0.5)
        speed, health = self.tick(2.0)  # GPS lost >= 2 s and no pulse
        self.assertIsNone(speed)
        self.assertEqual((health["active"], health["reason"], health["ageS"]), ("none", "gps_lost_no_pulse", None))
        speed, health = self.tick(5.0)
        self.assertIsNone(speed)
        self.assertEqual(health["active"], "none")

    def test_pulse_stale_then_gps_lost_gives_none(self) -> None:
        self.tick(pulse=40.0)
        speed, health = self.tick(0.1)
        self.assertIsNone(speed)
        self.assertEqual(health["active"], "none")

    def test_pulse_only_ignores_gps(self) -> None:
        sel = SpeedSourceSelector("pulse_only")
        speed, health = sel.select(1.0, gps_valid=True, gps_speed_kph=80.0, gps_age_s=0.1, pulse_speed_kph=40.0, pulse_age_s=0.1)
        self.assertEqual((speed, health["active"]), (40.0, "pulse"))
        speed, health = sel.select(2.0, gps_valid=True, gps_speed_kph=80.0, gps_age_s=0.1, pulse_speed_kph=None, pulse_age_s=None)
        self.assertEqual((speed, health["active"]), (None, "none"))

    def test_gps_only_ignores_pulse(self) -> None:
        sel = SpeedSourceSelector("gps_only")
        speed, health = sel.select(1.0, gps_valid=False, gps_speed_kph=0.0, gps_age_s=None, pulse_speed_kph=40.0, pulse_age_s=0.1)
        self.assertEqual((speed, health["active"], health["reason"]), (None, "none", "gps_only_no_fix"))
        speed, health = sel.select(2.0, gps_valid=True, gps_speed_kph=80.0, gps_age_s=0.1, pulse_speed_kph=40.0, pulse_age_s=0.1)
        self.assertEqual((speed, health["active"]), (80.0, "gps"))

    def test_zero_thresholds_switch_immediately(self) -> None:
        sel = SpeedSourceSelector("gps_first", lost_s=0.0, regain_s=0.0)
        sel.select(1.0, gps_valid=True, gps_speed_kph=50.0, gps_age_s=0.0, pulse_speed_kph=40.0, pulse_age_s=0.0)
        _, health = sel.select(1.1, gps_valid=False, gps_speed_kph=0.0, gps_age_s=None, pulse_speed_kph=40.0, pulse_age_s=0.0)
        self.assertEqual(health["active"], "pulse")


class GpsHeldFlagTest(unittest.TestCase):
    def test_live_fix_is_not_held_and_lost_fix_is_flagged_held(self) -> None:
        gps = NmeaGpsState()
        gps.feed_line(GGA, received_monotonic=10.0)
        sample = gps.feed_line(RMC, received_monotonic=10.1)
        self.assertTrue(sample.fix_valid)
        self.assertFalse(sample.held)
        self.assertAlmostEqual(sample.speed_kph, 22.4 * 1.852, places=3)
        lost = gps.feed_line(_nmea("GPGGA,123520,2728.188,S,15301.506,E,0,00,99.9,,M,,M,,"), received_monotonic=11.0)
        self.assertTrue(lost.fix_valid)  # existing 15 s fix hold is unchanged...
        self.assertTrue(lost.held)  # ...but flagged so speed selection does not trust it


if __name__ == "__main__":
    unittest.main()
