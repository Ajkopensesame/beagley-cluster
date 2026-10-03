"""Minimal systemd notify client (no dependencies). No-ops when not run under systemd."""
from __future__ import annotations

import os
import socket


def notify(message: str) -> bool:
    """Send e.g. 'READY=1' or 'WATCHDOG=1' to $NOTIFY_SOCKET. Returns True if sent."""
    addr = os.environ.get("NOTIFY_SOCKET", "")
    if not addr:
        return False
    if addr.startswith("@"):
        addr = "\0" + addr[1:]
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.connect(addr)
            sock.sendall(message.encode("utf-8"))
        return True
    except OSError:
        return False


def watchdog_interval_sec() -> float | None:
    """Half of WatchdogSec as seconds, or None when the watchdog is not enabled."""
    raw = os.environ.get("WATCHDOG_USEC", "")
    try:
        usec = int(raw)
    except ValueError:
        return None
    if usec <= 0:
        return None
    return max(0.5, usec / 2_000_000)
