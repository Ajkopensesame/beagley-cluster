"""Offline CAN reverse-engineering workbench.

The workbench is intentionally Mac-first and deterministic. It ingests raw CAN
logs plus guided labels, ranks candidate signals, and exports a signal
dictionary that can be consumed upstream of the existing cluster UI contract.
"""

__all__ = [
    "baseline",
    "bitfield",
    "capture_session",
    "discovery",
    "export",
    "labels",
    "obd_anchors",
    "parser",
    "startup_diff",
]
