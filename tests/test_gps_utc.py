#!/usr/bin/env python3
"""gps.utcMs / gps.utcValid: RMC-only UTC for the BBB clock helper (additive to timestampMs)."""
from __future__ import annotations

import os
import sys
import unittest
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "bbb_hub"))

from gps_nmea import NmeaGpsState, build_hardware_gps_payload  # noqa: E402

RMC_OK = "$GPRMC,123519.00,A,2728.188,S,15301.506,E,020.0,084.4,031026,,"
GGA_OK = "$GPGGA,123519.00,2728.188,S,15301.506,E,1,08,0.9,10.0,M,0.0,M,,"
EXPECTED_S = datetime(2026, 10, 3, 12, 35, 19, tzinfo=timezone.utc).timestamp()
# Deliberately wrong wall clock (the BBB shows April): must not influence utcMs.
WRONG_WALL = datetime(2026, 4, 10, 8, 0, 0, tzinfo=timezone.utc).timestamp()


def _feed(state: NmeaGpsState, line: str, mono: float):
    return state.feed_line(line, received_wall_time=WRONG_WALL + mono, received_monotonic=mono)


def _feed_bad(state: NmeaGpsState, line: str, mono: float) -> None:
    """Feed a sentence the hub may reject outright (legacy timestamp parsing raises; the hub counts a parse error)."""
    try:
        _feed(state, line, mono)
    except ValueError:
        pass


def _payload(sample, now_mono: float, stale: bool = False) -> dict:
    return build_hardware_gps_payload(sample, stale=stale, now_ms=0, now_monotonic=now_mono)


class GpsUtcTest(unittest.TestCase):
    def test_rmc_with_date_is_utc_valid_and_advances_monotonically(self) -> None:
        state = NmeaGpsState()
        _feed(state, RMC_OK, 100.0)
        sample = _feed(state, GGA_OK, 100.2)
        payload = _payload(sample, 101.5)
        self.assertTrue(payload["utcValid"])
        self.assertTrue(payload["fixValid"])
        self.assertAlmostEqual(payload["utcMs"] / 1000.0, EXPECTED_S + 1.5, places=2)

    def test_timestamp_ms_is_unchanged_and_still_uses_wall_date_for_gga(self) -> None:
        state = NmeaGpsState()
        _feed(state, RMC_OK, 100.0)
        sample = _feed(state, GGA_OK, 100.2)
        wall_date = datetime.fromtimestamp(WRONG_WALL + 100.2, tz=timezone.utc).date()
        got_date = datetime.fromtimestamp(sample.timestamp_ms / 1000.0, tz=timezone.utc).date()
        self.assertEqual(got_date, wall_date)  # the quirk we must NOT change
        self.assertNotEqual(got_date, datetime.fromtimestamp(EXPECTED_S, tz=timezone.utc).date())

    def test_gga_only_is_not_utc_valid(self) -> None:
        state = NmeaGpsState()
        sample = _feed(state, GGA_OK, 100.0)
        payload = _payload(sample, 100.1)
        self.assertTrue(payload["fixValid"])
        self.assertFalse(payload["utcValid"])
        self.assertEqual(payload["utcMs"], 0)

    def test_rmc_status_v_is_not_utc_valid_and_withdraws_earlier_utc(self) -> None:
        state = NmeaGpsState()
        _feed(state, RMC_OK, 100.0)
        _feed(state, GGA_OK, 100.1)
        sample = _feed(state, "$GPRMC,123520.00,V,2728.188,S,15301.506,E,020.0,084.4,031026,,", 101.0)
        self.assertFalse(_payload(sample, 101.1)["utcValid"])

    def test_bad_or_implausible_dates_are_not_utc_valid(self) -> None:
        for date in ("", "99", "321326", "310226", "000126", "abcdef", "031025", "010126x", "030125", "031026x"):
            with self.subTest(date=date):
                state = NmeaGpsState()
                _feed_bad(state, f"$GPRMC,123519.00,A,2728.188,S,15301.506,E,020.0,084.4,{date},,", 100.0)
                sample = _feed(state, GGA_OK, 100.1)
                self.assertFalse(_payload(sample, 100.2)["utcValid"])

    def test_bad_time_field_is_not_utc_valid(self) -> None:
        for tm in ("", "1235", "256100.00", "126100.00", "123561.00", "12ab19.00"):
            with self.subTest(time=tm):
                state = NmeaGpsState()
                _feed_bad(state, f"$GPRMC,{tm},A,2728.188,S,15301.506,E,020.0,084.4,031026,,", 100.0)
                sample = _feed(state, GGA_OK, 100.1)
                self.assertFalse(_payload(sample, 100.2)["utcValid"])

    def test_stale_payload_is_not_utc_valid(self) -> None:
        state = NmeaGpsState()
        _feed(state, RMC_OK, 100.0)
        sample = _feed(state, GGA_OK, 100.1)
        self.assertFalse(_payload(sample, 100.2, stale=True)["utcValid"])

    def test_rmc_utc_older_than_5_s_is_not_valid(self) -> None:
        state = NmeaGpsState()
        _feed(state, RMC_OK, 100.0)
        sample = _feed(state, GGA_OK, 100.1)
        self.assertTrue(_payload(sample, 104.9)["utcValid"])
        self.assertFalse(_payload(sample, 105.1)["utcValid"])

    def test_gga_keeps_arriving_but_rmc_stops_makes_utc_invalid(self) -> None:
        state = NmeaGpsState(fix_hold_seconds=60.0)
        _feed(state, RMC_OK, 100.0)
        sample = None
        for i in range(1, 9):
            sample = _feed(state, GGA_OK, 100.0 + i)
        self.assertFalse(_payload(sample, 108.1)["utcValid"])

    def test_held_fix_is_not_utc_valid(self) -> None:
        state = NmeaGpsState(fix_hold_seconds=10.0)
        _feed(state, RMC_OK, 100.0)
        _feed(state, GGA_OK, 100.1)
        _feed(state, "$GNRMC,123520.00,V,,,,,,,031026,,,N,V", 101.0)
        held = _feed(state, "$GNGGA,123520.00,,,,,0,00,99.99,,,,,,", 101.1)
        self.assertTrue(held.held)
        self.assertTrue(held.fix_valid)
        payload = _payload(held, 101.2)
        self.assertTrue(payload["fixValid"])
        self.assertFalse(payload["utcValid"])

    def test_no_sample_has_utc_fields_false(self) -> None:
        payload = build_hardware_gps_payload(None, stale=True, now_ms=0)
        self.assertEqual(payload["utcMs"], 0)
        self.assertFalse(payload["utcValid"])


if __name__ == "__main__":
    unittest.main()
