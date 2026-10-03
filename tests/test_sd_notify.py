from __future__ import annotations

import os
import socket
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "bbb_hub"))
import sd_notify  # noqa: E402


class SdNotifyTest(unittest.TestCase):
    def tearDown(self) -> None:
        os.environ.pop("NOTIFY_SOCKET", None)
        os.environ.pop("WATCHDOG_USEC", None)

    def test_noop_without_socket(self) -> None:
        os.environ.pop("NOTIFY_SOCKET", None)
        self.assertFalse(sd_notify.notify("READY=1"))

    def test_sends_datagram(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "n.sock")
            srv = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            srv.bind(path)
            srv.settimeout(2)
            os.environ["NOTIFY_SOCKET"] = path
            self.assertTrue(sd_notify.notify("WATCHDOG=1"))
            self.assertEqual(srv.recv(64), b"WATCHDOG=1")
            srv.close()

    def test_dead_socket_is_not_fatal(self) -> None:
        os.environ["NOTIFY_SOCKET"] = "/nonexistent/notify.sock"
        self.assertFalse(sd_notify.notify("READY=1"))

    def test_watchdog_interval_is_half_of_usec(self) -> None:
        os.environ.pop("WATCHDOG_USEC", None)
        self.assertIsNone(sd_notify.watchdog_interval_sec())
        os.environ["WATCHDOG_USEC"] = "10000000"
        self.assertEqual(sd_notify.watchdog_interval_sec(), 5.0)
        os.environ["WATCHDOG_USEC"] = "junk"
        self.assertIsNone(sd_notify.watchdog_interval_sec())


if __name__ == "__main__":
    unittest.main()
