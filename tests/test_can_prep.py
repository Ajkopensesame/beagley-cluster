#!/usr/bin/env python3
"""CAN prep without a car: the OBD-II starter dictionary, the decoder's ``when`` multiplexer, and the hub's
live-CAN receive path fed by (a) a pure-Python fake SocketCAN socket (always runs) and (b) a real Linux
``vcan0`` interface (skipped cleanly unless one already exists and is up).

The starter (tools/bbb_hub/config/can_signals.obd2_example.json) is a public-standard example, NOT a verified
vehicle mapping; these tests only prove the plumbing and the SAE J1979 arithmetic."""
from __future__ import annotations

import asyncio
import copy
import json
import os
import socket
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUB_DIR = os.path.join(ROOT, "tools", "bbb_hub")
sys.path.insert(0, ROOT)
sys.path.insert(0, HUB_DIR)

from tools.bbb_hub.fake_can import FakeCanBus, obd_response, pack_can_frame, replay_candump  # noqa: E402
from tools.bbb_hub.input_adapters import SocketCanSignalSource  # noqa: E402
from tools.can_reverse_workbench.bbb_decoder import CanLogSignalReplay, CanSignalDictionary  # noqa: E402
from tools.can_reverse_workbench.export import validate_signal_dictionary  # noqa: E402
from tools.can_reverse_workbench.parser import CanFrame  # noqa: E402

try:
    import websockets  # noqa: F401
except ImportError:  # pragma: no cover
    websockets = None

STARTER = Path(ROOT) / "tools" / "bbb_hub" / "config" / "can_signals.obd2_example.json"

# (pid, payload bytes A[,B], expected {signal: value}); formulas from SAE J1979 / ISO 15765-4.
OBD_SAMPLES = [
    (0x0D, b"\x3c", {"speedKph": 60.0}),                       # A km/h
    (0x0C, b"\x1a\xf8", {"rpm": (0x1A * 256 + 0xF8) / 4.0}),   # (256A+B)/4 = 1726 rpm
    (0x05, b"\x7b", {"coolantC": 83.0}),                       # A-40
    (0x2F, b"\x80", {"fuelPct": 128 * 100 / 255}),             # A*100/255
]


async def _wait_until(predicate, timeout: float = 3.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        await asyncio.sleep(0.01)
    raise AssertionError("condition not reached in time")


class StarterDictionaryTest(unittest.TestCase):
    def test_starter_validates_and_is_clearly_unverified(self) -> None:
        payload = json.loads(STARTER.read_text(encoding="utf-8"))
        self.assertEqual(validate_signal_dictionary(payload), [])
        self.assertEqual(sorted(payload["signals"]), ["coolantC", "fuelPct", "rpm", "speedKph"])
        self.assertIn("STARTER", payload["source"]["note"])
        self.assertIn("NOT verified", payload["source"]["note"])
        for name, signal in payload["signals"].items():
            self.assertFalse(signal["verified"], name)  # never claims to be a verified mapping
            self.assertEqual(signal["confidence"], 0.0, name)
            self.assertEqual(signal["canId"], "0x7E8", name)

    def test_loads_with_the_hubs_real_loader(self) -> None:
        dictionary = CanSignalDictionary.from_path(STARTER)
        self.assertEqual(sorted(s.name for s in dictionary.signals), ["coolantC", "fuelPct", "rpm", "speedKph"])

    def test_decodes_obd_mode01_responses(self) -> None:
        dictionary = CanSignalDictionary.from_path(STARTER)
        for pid, value_bytes, expected in OBD_SAMPLES:
            decoded = dictionary.decode_frame(CanFrame(0.0, "can0", 0x7E8, obd_response(pid, value_bytes)))
            self.assertEqual(sorted(decoded), sorted(expected), hex(pid))  # only the matching PID decodes
            for key, value in expected.items():
                self.assertAlmostEqual(decoded[key], value, places=6, msg=hex(pid))

    def test_unrelated_traffic_decodes_nothing(self) -> None:
        dictionary = CanSignalDictionary.from_path(STARTER)
        ignored = [
            CanFrame(0.0, "can0", 0x123, b"\x03\x41\x0d\x3c\x00\x00\x00\x00"),   # wrong arbitration id
            CanFrame(0.0, "can0", 0x7E8, b"\x03\x7f\x01\x12\x00\x00\x00\x00"),   # negative response (0x7F)
            CanFrame(0.0, "can0", 0x7E8, obd_response(0x0D, b"\x3c", service=0x09)),  # not a Mode 01 reply
            CanFrame(0.0, "can0", 0x7E8, obd_response(0x11, b"\xff")),             # a PID we do not map
            CanFrame(0.0, "can0", 0x7E8, b"\x02\x41\x0c"),                         # truncated rpm response
            CanFrame(0.0, "can0", 0x7E0, obd_response(0x0D, b"\x3c")),             # the *request* side id
        ]
        for frame in ignored:
            self.assertEqual(dictionary.decode_frame(frame), {}, frame)

    def test_when_conditions_are_validated_and_optional(self) -> None:
        payload = json.loads(STARTER.read_text(encoding="utf-8"))
        broken = copy.deepcopy(payload)
        broken["signals"]["rpm"]["when"] = [{"startBit": -1, "length": 0, "value": "x"}, 5, {}]
        errors = validate_signal_dictionary(broken)
        self.assertTrue(any("when[0].startBit" in e for e in errors), errors)
        self.assertTrue(any("when[0].length" in e for e in errors), errors)
        self.assertTrue(any("when[1] must be an object" in e for e in errors), errors)
        notlist = copy.deepcopy(payload)
        notlist["signals"]["rpm"]["when"] = {"startBit": 0}
        self.assertTrue(any("when must be a list" in e for e in validate_signal_dictionary(notlist)))
        # original dictionaries (no "when") keep decoding every frame of their id
        plain = copy.deepcopy(payload)
        for signal in plain["signals"].values():
            signal.pop("when")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "plain.json"
            path.write_text(json.dumps(plain), encoding="utf-8")
            decoded = CanSignalDictionary.from_path(path).decode_frame(
                CanFrame(0.0, "can0", 0x7E8, obd_response(0x0D, b"\x3c"))
            )
        self.assertEqual(sorted(decoded), ["coolantC", "fuelPct", "rpm", "speedKph"])


class FakeSocketCanTest(unittest.TestCase):
    """The hub's real SocketCanSignalSource, fed by the pure-Python fake bus (runs everywhere)."""

    def test_frames_flow_through_receive_decode_and_health(self) -> None:
        async def scenario() -> None:
            with FakeCanBus() as bus:
                src = SocketCanSignalSource("fake0", str(STARTER), stale_ms=250, socket_factory=bus.rx_factory)
                self.assertTrue(src.health()["stale"])  # nothing received yet
                self.assertEqual(src.snapshot(), {})
                task = asyncio.create_task(src.run())
                try:
                    bus.send(0x555, b"\x01\x02\x03")  # noise on another id
                    for pid, value_bytes, _expected in OBD_SAMPLES:
                        bus.send_obd(pid, value_bytes)
                    await _wait_until(lambda: len(src.snapshot()) == 4)
                    values = src.snapshot()
                    self.assertEqual(values["speedKph"], 60.0)
                    self.assertEqual(values["rpm"], 1726.0)
                    self.assertEqual(values["coolantC"], 83.0)
                    self.assertAlmostEqual(values["fuelPct"], 50.196, places=3)
                    health = src.health()
                    self.assertFalse(health["stale"])
                    self.assertEqual(health["frames"], 5)
                    self.assertIsNone(health["lastError"])
                    diagnostics = src.diagnostics()
                    self.assertEqual(diagnostics["frameCount"], 5)
                    self.assertEqual(diagnostics["decodedSignals"], ["coolantC", "fuelPct", "rpm", "speedKph"])
                    # A later frame updates just its own signal.
                    bus.send_obd(0x0D, b"\x50")
                    await _wait_until(lambda: src.snapshot()["speedKph"] == 80.0)
                    self.assertEqual(src.snapshot()["rpm"], 1726.0)
                    # Bus goes quiet: the source reports stale (the hub then drops the values).
                    await _wait_until(lambda: src.health()["stale"], timeout=2.0)
                finally:
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)

        asyncio.run(scenario())

    def test_rtr_and_error_frames_are_ignored(self) -> None:
        async def scenario() -> None:
            with FakeCanBus() as bus:
                src = SocketCanSignalSource("fake0", str(STARTER), socket_factory=bus.rx_factory)
                task = asyncio.create_task(src.run())
                try:
                    from tools.bbb_hub.fake_can import CAN_ERR_FLAG, CAN_RTR_FLAG

                    bus.send(0x7E8, obd_response(0x0D, b"\x3c"), flags=CAN_RTR_FLAG)
                    bus.send(0x7E8, obd_response(0x0D, b"\x3c"), flags=CAN_ERR_FLAG)
                    bus.send_obd(0x05, b"\x7b")
                    await _wait_until(lambda: src.snapshot() != {})
                    self.assertEqual(src.snapshot(), {"coolantC": 83.0})
                finally:
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)

        asyncio.run(scenario())

    def test_candump_log_replays_through_the_fake_bus(self) -> None:
        lines = [
            f"({1000 + i * 0.01:.6f}) can0 7E8#{obd_response(pid, value).hex().upper()}"
            for i, (pid, value, _e) in enumerate(OBD_SAMPLES)
        ]
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "candump.log"
            log.write_text("\n".join(lines) + "\n", encoding="utf-8")

            async def scenario() -> None:
                with FakeCanBus() as bus:
                    src = SocketCanSignalSource("fake0", str(STARTER), socket_factory=bus.rx_factory)
                    task = asyncio.create_task(src.run())
                    try:
                        self.assertEqual(replay_candump(log, bus), 4)
                        await _wait_until(lambda: len(src.snapshot()) == 4)
                        self.assertEqual(src.snapshot()["speedKph"], 60.0)
                    finally:
                        task.cancel()
                        await asyncio.gather(task, return_exceptions=True)

            asyncio.run(scenario())

            # The hub's offline replay decoder reads the same log with the same starter.
            replay = CanLogSignalReplay(STARTER, log, repeat=False)
            self.assertEqual(replay.snapshot(now_monotonic=time.monotonic() + 5.0)["coolantC"], 83.0)

    def test_extended_id_packing_round_trips(self) -> None:
        from tools.bbb_hub.input_adapters import _parse_socketcan_frame

        frame = _parse_socketcan_frame(pack_can_frame(0x18DAF110, b"\x01\x02"))
        self.assertEqual((frame.arbitration_id, frame.data), (0x18DAF110, b"\x01\x02"))
        frame = _parse_socketcan_frame(pack_can_frame(0x7E8, b"\xaa"))
        self.assertEqual((frame.arbitration_id, frame.data), (0x7E8, b"\xaa"))


@unittest.skipIf(websockets is None, "needs websockets (hub module imports it)")
class HubLiveCanOverlayTest(unittest.TestCase):
    """VehicleHub (in-process, no sockets/serial opened) with its live CAN source on the fake bus."""

    def test_hub_state_uses_can_values_then_fails_safe_when_the_bus_goes_quiet(self) -> None:
        import vehicle_hub_prod

        async def scenario() -> None:
            with FakeCanBus() as bus:
                hub = vehicle_hub_prod.VehicleHub()
                hub._can_live = SocketCanSignalSource("fake0", str(STARTER), stale_ms=300, socket_factory=bus.rx_factory)
                task = asyncio.create_task(hub._can_live.run())
                try:
                    state = await hub.next_state()
                    self.assertEqual(state["speedKph"], 0.0)  # nothing decoded yet: fail-safe defaults
                    self.assertEqual(state["_health"]["vehicleSource"], "none")
                    for pid, value_bytes, _expected in OBD_SAMPLES:
                        bus.send_obd(pid, value_bytes)
                    await _wait_until(lambda: len(hub._can_live.snapshot()) == 4)
                    state = await hub.next_state()
                    self.assertEqual(state["_health"]["vehicleSource"], "can_live")
                    self.assertFalse(state["_health"]["stale"])
                    self.assertEqual(state["_health"]["canDecodedSignals"], ["coolantC", "fuelPct", "rpm", "speedKph"])
                    self.assertEqual(state["rpm"], 1726.0)
                    self.assertEqual(state["coolantC"], 83.0)
                    self.assertAlmostEqual(state["fuelPct"], 50.196, places=3)
                    self.assertEqual(state["speedKph"], 60.0)
                    self.assertEqual(state["_health"]["speedSource"]["reason"], "can_speed")
                    self.assertEqual(state["_health"]["canLive"]["frames"], 4)
                    await asyncio.sleep(0.5)  # stale_ms=300 passes with no frames
                    state = await hub.next_state()
                    self.assertEqual((state["speedKph"], state["rpm"], state["coolantC"], state["fuelPct"]), (0.0,) * 4)
                    self.assertEqual(state["_health"]["vehicleSource"], "none")
                    self.assertTrue(state["_health"]["canLive"]["stale"])
                finally:
                    task.cancel()
                    await asyncio.gather(task, return_exceptions=True)

        asyncio.run(scenario())

    def test_hub_applies_log_replay_overlay(self) -> None:
        """Regression: CanLogSignalReplay.health() lacked ``stale`` so the hub always treated a replay as dead."""
        import vehicle_hub_prod

        lines = [f"({1000 + i * 0.001:.6f}) can0 7E8#{obd_response(p, v).hex().upper()}" for i, (p, v, _e) in enumerate(OBD_SAMPLES)]
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "candump.log"
            log.write_text("\n".join(lines) + "\n", encoding="utf-8")
            hub = vehicle_hub_prod.VehicleHub()
            hub._can_replay = CanLogSignalReplay(STARTER, log, repeat=False)

            async def scenario() -> dict:
                await asyncio.sleep(0.1)
                return await hub.next_state()

            state = asyncio.run(scenario())
        self.assertEqual(state["_health"]["vehicleSource"], "can_replay")
        self.assertEqual((state["speedKph"], state["rpm"], state["coolantC"]), (60.0, 1726.0, 83.0))
        self.assertFalse(state["_health"]["canReplay"]["stale"])

    def test_one_shot_replay_goes_stale_after_the_log_ends(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "candump.log"
            log.write_text("(1000.000000) can0 7E8#03410D3C00000000\n", encoding="utf-8")
            replay = CanLogSignalReplay(STARTER, log, repeat=False)
        self.assertFalse(replay.health()["stale"])
        replay._started_monotonic -= 5.0  # pretend 5 s have passed since the replay started
        self.assertTrue(replay.health()["stale"])


def _vcan_interface() -> str | None:
    """Name of an existing, up vcan interface we can bind to, else None (creating one needs root)."""
    if not hasattr(socket, "AF_CAN"):
        return None
    name = os.environ.get("VCAN_IFACE", "vcan0")
    try:
        with socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW) as probe:
            probe.bind((name,))
    except OSError:
        return None
    return name


@unittest.skipIf(_vcan_interface() is None, "no usable vcan0 (sudo modprobe vcan; sudo ip link add vcan0 type vcan; "
                 "sudo ip link set up vcan0; or set VCAN_IFACE)")
class VcanTest(unittest.TestCase):
    """Same assertions through the kernel: real AF_CAN sockets on a virtual CAN interface."""

    def test_socketcan_source_decodes_frames_sent_on_vcan(self) -> None:
        iface = _vcan_interface()

        async def scenario() -> None:
            src = SocketCanSignalSource(iface, str(STARTER), stale_ms=1000)
            task = asyncio.create_task(src.run())
            try:
                await asyncio.sleep(0.2)  # let it bind
                with socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW) as tx:
                    tx.bind((iface,))
                    for pid, value_bytes, _expected in OBD_SAMPLES:
                        tx.send(pack_can_frame(0x7E8, obd_response(pid, value_bytes)))
                await _wait_until(lambda: len(src.snapshot()) == 4)
                self.assertEqual(src.snapshot()["speedKph"], 60.0)
                self.assertEqual(src.snapshot()["rpm"], 1726.0)
                self.assertEqual(src.snapshot()["coolantC"], 83.0)
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
