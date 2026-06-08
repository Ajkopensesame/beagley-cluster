#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "bbb_hub"))

from gps_nmea import NmeaGpsState, build_hardware_gps_payload  # noqa: E402


class NmeaGpsStateTest(unittest.TestCase):
    def test_valid_rmc_and_gga_produce_hardware_fix(self) -> None:
        state = NmeaGpsState(min_heading_speed_kph=7.0)
        state.feed_line(
            "$GPRMC,092751.000,A,5321.6802,N,00630.3372,W,12.4,84.4,230394,003.1,W",
            received_wall_time=1_710_000_000.0,
            received_monotonic=10.0,
        )
        sample = state.feed_line(
            "$GPGGA,092751.000,5321.6802,N,00630.3372,W,1,08,0.9,545.4,M,46.9,M,,",
            received_wall_time=1_710_000_000.2,
            received_monotonic=10.2,
        )

        self.assertIsNotNone(sample)
        assert sample is not None
        self.assertTrue(sample.fix_valid)
        self.assertEqual(sample.source, "hardware")
        self.assertAlmostEqual(sample.lat, 53.3613367, places=5)
        self.assertAlmostEqual(sample.lng, -6.50562, places=5)
        self.assertAlmostEqual(sample.speed_kph, 22.9648, places=3)
        self.assertAlmostEqual(sample.bearing, 84.4, places=1)
        self.assertTrue(sample.heading_reliable)
        self.assertEqual(sample.satellites, 8)
        self.assertAlmostEqual(sample.accuracy_m, 5.0, places=1)

    def test_no_fix_retains_metadata_but_stays_invalid(self) -> None:
        state = NmeaGpsState(min_heading_speed_kph=7.0)
        state.feed_line(
            "$GPRMC,092752.000,V,5321.6802,N,00630.3372,W,0.1,12.0,230394,003.1,W",
            received_wall_time=1_710_000_005.0,
            received_monotonic=15.0,
        )
        sample = state.feed_line(
            "$GPGGA,092752.000,5321.6802,N,00630.3372,W,0,03,2.4,545.4,M,46.9,M,,",
            received_wall_time=1_710_000_005.1,
            received_monotonic=15.1,
        )

        self.assertIsNotNone(sample)
        assert sample is not None
        self.assertFalse(sample.fix_valid)
        self.assertFalse(sample.heading_reliable)
        self.assertEqual(sample.satellites, 3)
        self.assertAlmostEqual(sample.lat, 53.3613367, places=5)
        self.assertAlmostEqual(sample.lng, -6.50562, places=5)

        payload = build_hardware_gps_payload(sample, stale=False, now_ms=sample.timestamp_ms)
        self.assertFalse(payload["fixValid"])
        self.assertEqual(payload["satellites"], 3)
        self.assertIn("lat", payload)
        self.assertIn("lng", payload)

    def test_transient_invalid_sentences_hold_recent_valid_fix(self) -> None:
        state = NmeaGpsState(min_heading_speed_kph=7.0, fix_hold_seconds=3.0)
        state.feed_line(
            "$GPRMC,092751.000,A,5321.6802,N,00630.3372,W,12.4,84.4,230394,003.1,W",
            received_wall_time=1_710_000_000.0,
            received_monotonic=10.0,
        )
        valid = state.feed_line(
            "$GPGGA,092751.000,5321.6802,N,00630.3372,W,1,08,0.9,545.4,M,46.9,M,,",
            received_wall_time=1_710_000_000.1,
            received_monotonic=10.1,
        )
        self.assertIsNotNone(valid)
        assert valid is not None
        self.assertTrue(valid.fix_valid)

        state.feed_line(
            "$GNRMC,092752.000,V,,,,,,,230394,,,N,V",
            received_wall_time=1_710_000_001.0,
            received_monotonic=11.0,
        )
        held = state.feed_line(
            "$GNGGA,092752.000,,,,,0,00,99.99,,,,,,",
            received_wall_time=1_710_000_001.1,
            received_monotonic=11.1,
        )
        self.assertIsNotNone(held)
        assert held is not None
        self.assertTrue(held.fix_valid)
        self.assertAlmostEqual(held.lat, valid.lat)
        self.assertAlmostEqual(held.lng, valid.lng)
        self.assertAlmostEqual(held.accuracy_m, valid.accuracy_m)
        self.assertEqual(held.satellites, valid.satellites)

        expired = state.feed_line(
            "$GNGGA,092756.000,,,,,0,00,99.99,,,,,,",
            received_wall_time=1_710_000_006.0,
            received_monotonic=16.0,
        )
        self.assertIsNotNone(expired)
        assert expired is not None
        self.assertFalse(expired.fix_valid)
        self.assertAlmostEqual(expired.accuracy_m, 499.95)
        self.assertEqual(expired.satellites, 0)

    def test_malformed_sentence_does_not_poison_latest_sample(self) -> None:
        state = NmeaGpsState()
        with self.assertRaises(ValueError):
            state.feed_line("$GPRMC,broken*00", received_wall_time=1_710_000_010.0, received_monotonic=20.0)
        self.assertIsNone(state.latest_sample())

        sample = state.feed_line(
            "$GPRMC,092753.000,A,5321.6802,N,00630.3372,W,2.1,0.0,230394,003.1,W",
            received_wall_time=1_710_000_011.0,
            received_monotonic=21.0,
        )
        self.assertIsNotNone(sample)

    def test_heading_reliability_respects_speed_threshold(self) -> None:
        state = NmeaGpsState(min_heading_speed_kph=10.0)
        sample = state.feed_line(
            "$GPRMC,092754.000,A,5321.6802,N,00630.3372,W,3.0,180.0,230394,003.1,W",
            received_wall_time=1_710_000_020.0,
            received_monotonic=30.0,
        )
        self.assertIsNotNone(sample)
        assert sample is not None
        self.assertFalse(sample.heading_reliable)

        sample = state.feed_line(
            "$GPRMC,092755.000,A,5321.6802,N,00630.3372,W,8.0,181.0,230394,003.1,W",
            received_wall_time=1_710_000_021.0,
            received_monotonic=31.0,
        )
        self.assertIsNotNone(sample)
        assert sample is not None
        self.assertTrue(sample.heading_reliable)

    def test_stale_payload_forces_fix_invalid(self) -> None:
        state = NmeaGpsState()
        sample = state.feed_line(
            "$GPRMC,092756.000,A,5321.6802,N,00630.3372,W,12.0,90.0,230394,003.1,W",
            received_wall_time=1_710_000_030.0,
            received_monotonic=40.0,
        )
        self.assertIsNotNone(sample)
        assert sample is not None

        payload = build_hardware_gps_payload(sample, stale=True, now_ms=sample.timestamp_ms + 4000)
        self.assertFalse(payload["fixValid"])
        self.assertFalse(payload["headingReliable"])
        self.assertIn("lat", payload)


if __name__ == "__main__":
    unittest.main()
