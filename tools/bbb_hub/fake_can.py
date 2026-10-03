"""Pure-Python stand-in for a SocketCAN interface, for tests and offline experiments.

No kernel CAN support, root or vcan needed. ``FakeCanBus`` is a connected ``AF_UNIX``/``SOCK_DGRAM``
socket pair: whatever is sent on the bus end arrives on the receive end as the same 16-byte
``struct can_frame`` datagram a real ``CAN_RAW`` socket delivers, so it can be handed to
``SocketCanSignalSource(..., socket_factory=bus.rx_factory)`` and exercises the hub's real receive,
parse, decode and staleness code. Nothing here ever touches hardware.

Also: ``obd_response`` builds ISO 15765-4 single-frame OBD-II Mode 01 responses, and
``replay_candump`` pushes a candump/CSV log (workbench parser) onto the bus.
"""
from __future__ import annotations

import socket
import struct
from pathlib import Path

CAN_EFF_FLAG = 0x80000000
CAN_RTR_FLAG = 0x40000000
CAN_ERR_FLAG = 0x20000000
CAN_FRAME_STRUCT = struct.Struct("=IB3x8s")  # same layout as input_adapters.CAN_FRAME_STRUCT


def pack_can_frame(can_id: int, data: bytes, *, extended: bool = False, flags: int = 0) -> bytes:
    """Pack a classic CAN frame (<= 8 data bytes) as Linux ``struct can_frame``."""
    if len(data) > 8:
        raise ValueError("classic CAN carries at most 8 data bytes")
    raw_id = can_id | flags | (CAN_EFF_FLAG if extended or can_id > 0x7FF else 0)
    return CAN_FRAME_STRUCT.pack(raw_id, len(data), data.ljust(8, b"\x00"))


def obd_response(pid: int, value_bytes: bytes, *, service: int = 0x01) -> bytes:
    """Single-frame OBD-II response payload: ``[length, 0x40+service, pid, A, B, ...]`` padded to 8 bytes."""
    body = bytes([0x40 + service, pid]) + bytes(value_bytes)
    if len(body) > 7:
        raise ValueError("single-frame OBD response carries at most 7 bytes after the length byte")
    return (bytes([len(body)]) + body).ljust(8, b"\x00")


class FakeCanBus:
    """``send*`` writes frames; ``rx_factory`` hands the receiving end to ``SocketCanSignalSource``."""

    def __init__(self) -> None:
        self._rx, self._tx = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)

    def rx_factory(self) -> socket.socket:
        return self._rx

    def send(self, can_id: int, data: bytes, *, extended: bool = False, flags: int = 0) -> None:
        self._tx.send(pack_can_frame(can_id, data, extended=extended, flags=flags))

    def send_obd(self, pid: int, value_bytes: bytes, *, can_id: int = 0x7E8) -> None:
        self.send(can_id, obd_response(pid, value_bytes))

    def close(self) -> None:
        for sock in (self._tx, self._rx):
            try:
                sock.close()
            except OSError:
                pass

    def __enter__(self) -> "FakeCanBus":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def replay_candump(path: str | Path, bus: FakeCanBus) -> int:
    """Send every frame of a candump/CSV log onto ``bus`` (as fast as possible, timestamps ignored)."""
    from tools.can_reverse_workbench.parser import parse_can_log

    frames, _stats = parse_can_log(path)
    for frame in frames:
        bus.send(frame.arbitration_id, frame.data, extended=frame.extended)
    return len(frames)
