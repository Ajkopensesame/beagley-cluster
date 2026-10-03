from __future__ import annotations

import asyncio
import json
import os
import socket
import struct
import termios
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable

from tools.bbb_hub.can_diagnostics import CanDiagnosticsEngine
from tools.bbb_hub.sensor_calibration import SensorCalibration, load_sensor_calibration
from tools.can_reverse_workbench.bbb_decoder import CanSignalDictionary
from tools.can_reverse_workbench.parser import CanFrame


CAN_EFF_FLAG = 0x80000000
CAN_RTR_FLAG = 0x40000000
CAN_ERR_FLAG = 0x20000000
CAN_SFF_MASK = 0x000007FF
CAN_EFF_MASK = 0x1FFFFFFF
CAN_FRAME_STRUCT = struct.Struct("=IB3x8s")
SERIAL_BAUDS = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
}

WARNING_ALIASES = {
    "brake": "brake",
    "oil": "oil",
    "charge": "charge",
    "battery": "charge",
    "door": "door",
    "check": "check_engine",
    "engine": "check_engine",
    "check_engine": "check_engine",
    "cel": "check_engine",
    "at": "at",
    "trans": "at",
    "transmission": "at",
    "fuel": "fuel_low",
    "fuel_low": "fuel_low",
}
INDICATOR_ALIASES = {
    "left": "left",
    "indicator_left": "left",
    "turn_left": "left",
    "right": "right",
    "indicator_right": "right",
    "turn_right": "right",
    "high": "high_beam",
    "high_beam": "high_beam",
    "highbeam": "high_beam",
}
TOP_LEVEL_NUMERIC = {
    "rpm": "rpm",
    "speed": "speedKph",
    "speed_kph": "speedKph",
    "speedKph": "speedKph",
    "fuel_pct": "fuelPct",
    "fuelPct": "fuelPct",
    "coolant": "coolantC",
    "coolant_c": "coolantC",
    "coolantC": "coolantC",
    "maf": "mafGps",
    "maf_gps": "mafGps",
    "mafGps": "mafGps",
    "airflow": "mafGps",
    "throttle": "throttlePct",
    "throttle_pct": "throttlePct",
    "throttlePct": "throttlePct",
    "tps": "throttlePct",
    "engine_load": "engineLoadPct",
    "engine_load_pct": "engineLoadPct",
    "engineLoadPct": "engineLoadPct",
    "load": "engineLoadPct",
    "load_pct": "engineLoadPct",
    "iat": "intakeAirTempC",
    "intake_air_temp": "intakeAirTempC",
    "intake_air_temp_c": "intakeAirTempC",
    "intakeAirTempC": "intakeAirTempC",
    "map": "mapKpa",
    "map_kpa": "mapKpa",
    "mapKpa": "mapKpa",
}


@dataclass
class InputHealth:
    enabled: bool
    source: str
    stale_ms: int
    last_update_monotonic: float | None = None
    frames: int = 0
    parse_errors: int = 0
    last_error: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def snapshot(self) -> dict[str, Any]:
        now = time.monotonic()
        age_ms = None if self.last_update_monotonic is None else int((now - self.last_update_monotonic) * 1000)
        return {
            "enabled": self.enabled,
            "source": self.source,
            "stale": age_ms is None or age_ms > self.stale_ms,
            "ageMs": age_ms,
            "frames": self.frames,
            "parseErrors": self.parse_errors,
            "lastError": self.last_error,
            **self.metadata,
        }


def parse_vehicle_input_line(
    line: str,
    calibration: SensorCalibration | None = None,
    raw_out: dict[str, float] | None = None,
    faults_out: list[str] | None = None,
) -> dict[str, Any]:
    """Parse one serial line into a vehicle_state overlay.

    With ``calibration``, raw sender/pulse keys (a0, a1, speed_hz, rpm_hz) are
    converted to fuelPct/coolantC/speedKph/rpm. ``raw_out``/``faults_out`` (optional)
    receive the raw readings and any sensor-fault codes for health reporting.
    """
    stripped = line.strip()
    if not stripped:
        return {}
    if stripped.startswith("{"):
        payload = json.loads(stripped)
        if not isinstance(payload, dict):
            raise ValueError("serial JSON line must be an object")
        return _overlay_with_calibration(payload, calibration, raw_out, faults_out)
    raw: dict[str, Any] = {}
    for part in stripped.replace(";", ",").split(","):
        token = part.strip()
        if not token:
            continue
        if "=" not in token:
            raise ValueError(f"serial token missing '=': {token}")
        key, value = token.split("=", 1)
        raw[key.strip()] = _parse_scalar(value.strip())
    return _overlay_with_calibration(raw, calibration, raw_out, faults_out)


def _overlay_with_calibration(
    payload: dict[str, Any],
    calibration: SensorCalibration | None,
    raw_out: dict[str, float] | None,
    faults_out: list[str] | None,
) -> dict[str, Any]:
    overlay = normalize_vehicle_overlay(payload)
    if calibration is not None:
        raw = calibration.extract_raw(payload)
        if raw_out is not None:
            raw_out.update(raw)
        faults = calibration.apply(raw, overlay)
        if faults_out is not None:
            faults_out.extend(faults)
    return overlay


def normalize_vehicle_overlay(payload: dict[str, Any]) -> dict[str, Any]:
    overlay: dict[str, Any] = {}
    for key, value in payload.items():
        if value is None:
            continue
        normalized_key = _normalize_key(key)
        if normalized_key in TOP_LEVEL_NUMERIC:
            _set_overlay_value(overlay, TOP_LEVEL_NUMERIC[normalized_key], float(value))
        elif normalized_key in WARNING_ALIASES:
            _set_overlay_value(overlay, f"warnings.{WARNING_ALIASES[normalized_key]}", _parse_bool(value))
        elif normalized_key in INDICATOR_ALIASES:
            _set_overlay_value(overlay, f"indicators.{INDICATOR_ALIASES[normalized_key]}", _parse_bool(value))
        elif normalized_key in {"gear", "overdrive"}:
            _set_overlay_value(overlay, normalized_key, _parse_bool(value) if normalized_key == "overdrive" else str(value))
        elif normalized_key in {"drivetrain_mode", "drive_mode", "mode"}:
            _set_overlay_value(overlay, "drivetrain.mode", str(value))
        elif normalized_key in {"transfer_lock", "transferlock", "lock", "locked"}:
            _set_overlay_value(overlay, "drivetrain.transfer_lock", _parse_bool(value))
        elif normalized_key in {"warnings", "indicators", "drivetrain"} and isinstance(value, dict):
            overlay.setdefault(normalized_key, {}).update(normalize_vehicle_overlay(value).get(normalized_key, value))
    return overlay


def merge_vehicle_overlay(state: dict[str, Any], overlay: dict[str, Any]) -> None:
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(state.get(key), dict):
            merge_vehicle_overlay(state[key], value)
        else:
            state[key] = value


class SocketCanSignalSource:
    def __init__(
        self,
        interface: str,
        signal_dictionary_path: str,
        stale_ms: int = 1000,
        diagnostics_enabled: bool = True,
        socket_factory: Callable[[], socket.socket] | None = None,
    ) -> None:
        self.interface = interface
        # Test seam: a factory returning an already-connected socket that yields 16-byte SocketCAN
        # ``struct can_frame`` datagrams (see tools/bbb_hub/fake_can.py). None = real SocketCAN.
        self._socket_factory = socket_factory
        self.dictionary_path = signal_dictionary_path
        self.dictionary = CanSignalDictionary.from_path(signal_dictionary_path)
        self._latest: dict[str, float] = {}
        self._recent_frames: deque[dict[str, Any]] = deque(maxlen=100)
        self._diagnostics = CanDiagnosticsEngine(source="canLive", enabled=diagnostics_enabled)
        self._health = InputHealth(
            enabled=True,
            source="socketcan",
            stale_ms=stale_ms,
            metadata={"interface": interface, "dictionary": signal_dictionary_path},
        )

    async def run(self) -> None:
        while True:
            try:
                await self._run_socketcan_once()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self._health.last_error = str(exc)
                await asyncio.sleep(2.0)

    def snapshot(self) -> dict[str, float]:
        return dict(self._latest)

    def health(self) -> dict[str, Any]:
        return self._health.snapshot()

    def recent_frames(self) -> list[dict[str, Any]]:
        return list(self._recent_frames)

    def diagnostics(self) -> dict[str, Any]:
        return self._diagnostics.snapshot()

    def _open_socket(self) -> socket.socket:
        if self._socket_factory is not None:
            return self._socket_factory()
        sock = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        try:
            sock.bind((self.interface,))
        except OSError:
            sock.close()
            raise
        return sock

    async def _run_socketcan_once(self) -> None:
        loop = asyncio.get_running_loop()
        with self._open_socket() as sock:
            sock.setblocking(False)
            self._health.last_error = None
            while True:
                payload = await loop.sock_recv(sock, CAN_FRAME_STRUCT.size)
                if len(payload) < CAN_FRAME_STRUCT.size:
                    continue
                frame = _parse_socketcan_frame(payload)
                if frame is None:
                    continue
                decoded = self.dictionary.decode_frame(frame)
                self._recent_frames.append(_frame_evidence(frame, decoded))
                self._diagnostics.observe_frame(frame, decoded)
                if decoded:
                    self._latest.update(decoded)
                    self._health.last_update_monotonic = time.monotonic()
                self._health.frames += 1


class SerialVehicleInputSource:
    def __init__(
        self,
        device: str,
        baud: int = 115200,
        stale_ms: int = 1000,
        calibration: SensorCalibration | None = None,
    ) -> None:
        if baud not in SERIAL_BAUDS:
            raise ValueError(f"unsupported serial baud {baud}; expected one of {sorted(SERIAL_BAUDS)}")
        self.device = device
        self.baud = baud
        self._latest: dict[str, Any] = {}
        self._raw: dict[str, float] = {}
        if calibration is None:
            calibration, calibration_error = load_sensor_calibration()
        else:
            calibration_error = None
        self.calibration = calibration
        self._health = InputHealth(
            enabled=True,
            source="serial",
            stale_ms=stale_ms,
            metadata={
                "device": device,
                "baud": baud,
                "calibration": calibration.summary(),
                "raw": {},
                "sensorFaults": [],
            },
        )
        if calibration_error:
            self._health.last_error = calibration_error

    async def run(self) -> None:
        while True:
            try:
                await self._run_serial_once()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self._health.last_error = str(exc)
                await asyncio.sleep(2.0)

    def snapshot(self) -> dict[str, Any]:
        return dict(self._latest)

    def health(self) -> dict[str, Any]:
        return self._health.snapshot()

    async def _run_serial_once(self) -> None:
        loop = asyncio.get_running_loop()
        fd = os.open(self.device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        try:
            _configure_serial(fd, self.baud)
            self._health.last_error = None
            buffer = bytearray()
            while True:
                await _wait_readable(loop, fd)
                try:
                    chunk = os.read(fd, 256)
                except BlockingIOError:
                    continue
                if not chunk:
                    await asyncio.sleep(0.05)
                    continue
                buffer.extend(chunk)
                while b"\n" in buffer:
                    raw_line, _, remainder = buffer.partition(b"\n")
                    buffer = bytearray(remainder)
                    line = raw_line.decode("utf-8", errors="replace").strip()
                    if not line:
                        continue
                    try:
                        raw_line: dict[str, float] = {}
                        faults: list[str] = []
                        overlay = parse_vehicle_input_line(line, self.calibration, raw_line, faults)
                        if raw_line:
                            self._raw.update(raw_line)
                            self._health.metadata["raw"] = dict(self._raw)
                        self._health.metadata["sensorFaults"] = faults
                        if overlay or raw_line:
                            self._latest = overlay
                            self._health.last_update_monotonic = time.monotonic()
                        self._health.frames += 1
                    except (TypeError, ValueError, json.JSONDecodeError) as exc:
                        self._health.parse_errors += 1
                        self._health.last_error = f"parse error: {exc}"
        finally:
            os.close(fd)


def _parse_socketcan_frame(payload: bytes) -> CanFrame | None:
    can_id_raw, can_dlc, data = CAN_FRAME_STRUCT.unpack(payload)
    if can_id_raw & (CAN_RTR_FLAG | CAN_ERR_FLAG):
        return None
    can_id = can_id_raw & (CAN_EFF_MASK if can_id_raw & CAN_EFF_FLAG else CAN_SFF_MASK)
    return CanFrame(
        timestamp=time.time(),
        interface="socketcan",
        arbitration_id=can_id,
        data=data[: min(can_dlc, 8)],
    )


def _frame_evidence(frame: CanFrame, decoded: dict[str, float]) -> dict[str, Any]:
    return {
        "timestamp": frame.timestamp,
        "canId": frame.id_hex,
        "data": frame.data_hex,
        "decoded": decoded,
    }


def _configure_serial(fd: int, baud: int) -> None:
    attrs = termios.tcgetattr(fd)
    attrs[0] = attrs[0] & ~(termios.BRKINT | termios.ICRNL | termios.INPCK | termios.ISTRIP | termios.IXON)
    attrs[1] = 0
    attrs[2] = (attrs[2] | termios.CLOCAL | termios.CREAD | termios.CS8) & ~termios.PARENB
    attrs[2] = attrs[2] & ~termios.CSIZE | termios.CS8
    attrs[3] = 0
    attrs[4] = SERIAL_BAUDS[baud]
    attrs[5] = SERIAL_BAUDS[baud]
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


async def _wait_readable(loop: asyncio.AbstractEventLoop, fd: int) -> None:
    future: asyncio.Future[None] = loop.create_future()

    def ready() -> None:
        loop.remove_reader(fd)
        if not future.done():
            future.set_result(None)

    loop.add_reader(fd, ready)
    try:
        await future
    finally:
        loop.remove_reader(fd)


def _parse_scalar(value: str) -> Any:
    lowered = value.strip().lower()
    if lowered in {"true", "false", "on", "off", "yes", "no"}:
        return _parse_bool(lowered)
    if lowered in {"1", "0"}:
        return lowered == "1"
    try:
        if "." in lowered:
            return float(lowered)
        return int(lowered)
    except ValueError:
        return value


def _parse_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    lowered = str(value).strip().lower()
    if lowered in {"1", "true", "on", "yes", "high", "active"}:
        return True
    if lowered in {"0", "false", "off", "no", "low", "inactive"}:
        return False
    raise ValueError(f"not a boolean value: {value!r}")


def _normalize_key(key: str) -> str:
    return key.strip().replace("-", "_").replace(" ", "_")


def _set_overlay_value(overlay: dict[str, Any], path: str, value: Any) -> None:
    target = overlay
    parts = path.split(".")
    for part in parts[:-1]:
        target = target.setdefault(part, {})
    target[parts[-1]] = value
