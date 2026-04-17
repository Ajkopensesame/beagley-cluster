from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .labels import AnchorPoint


Decoder = Callable[[bytes], float]


@dataclass(frozen=True)
class ObdPidDefinition:
    pid: int
    signal: str
    unit: str
    data_length: int
    decode: Decoder
    description: str


@dataclass(frozen=True)
class ObdDecodeResult:
    timestamp: float
    mode: int
    pid: int
    values: dict[str, float]
    supported_pids: tuple[int, ...] = ()


def _u16(data: bytes) -> int:
    return data[0] * 256 + data[1]


def _fuel_trim(data: bytes) -> float:
    return (data[0] - 128.0) * 100.0 / 128.0


STANDARD_MODE_01_PIDS: dict[int, ObdPidDefinition] = {
    0x04: ObdPidDefinition(0x04, "engineLoadPct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "calculated engine load"),
    0x05: ObdPidDefinition(0x05, "coolantC", "C", 1, lambda data: data[0] - 40.0, "engine coolant temperature"),
    0x06: ObdPidDefinition(0x06, "shortFuelTrimBank1Pct", "pct", 1, _fuel_trim, "short term fuel trim bank 1"),
    0x07: ObdPidDefinition(0x07, "longFuelTrimBank1Pct", "pct", 1, _fuel_trim, "long term fuel trim bank 1"),
    0x0B: ObdPidDefinition(0x0B, "mapKpa", "kPa", 1, lambda data: float(data[0]), "intake manifold absolute pressure"),
    0x0C: ObdPidDefinition(0x0C, "rpm", "rpm", 2, lambda data: _u16(data) / 4.0, "engine speed"),
    0x0D: ObdPidDefinition(0x0D, "speedKph", "kph", 1, lambda data: float(data[0]), "vehicle speed"),
    0x0E: ObdPidDefinition(0x0E, "timingAdvanceDeg", "deg", 1, lambda data: data[0] / 2.0 - 64.0, "timing advance"),
    0x0F: ObdPidDefinition(0x0F, "intakeAirTempC", "C", 1, lambda data: data[0] - 40.0, "intake air temperature"),
    0x10: ObdPidDefinition(0x10, "mafGps", "g/s", 2, lambda data: _u16(data) / 100.0, "mass air flow rate"),
    0x11: ObdPidDefinition(0x11, "throttlePct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "throttle position"),
    0x1F: ObdPidDefinition(0x1F, "engineRunTimeSec", "s", 2, lambda data: float(_u16(data)), "run time since engine start"),
    0x2F: ObdPidDefinition(0x2F, "fuelPct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "fuel tank level input"),
    0x33: ObdPidDefinition(0x33, "barometricPressureKpa", "kPa", 1, lambda data: float(data[0]), "absolute barometric pressure"),
    0x42: ObdPidDefinition(0x42, "controlModuleVoltage", "V", 2, lambda data: _u16(data) / 1000.0, "control module voltage"),
    0x43: ObdPidDefinition(0x43, "absoluteLoadPct", "pct", 2, lambda data: _u16(data) * 100.0 / 255.0, "absolute load value"),
    0x44: ObdPidDefinition(0x44, "commandedEquivalenceRatio", "ratio", 2, lambda data: _u16(data) / 32768.0, "commanded equivalence ratio"),
    0x45: ObdPidDefinition(0x45, "relativeThrottlePct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "relative throttle position"),
    0x46: ObdPidDefinition(0x46, "ambientAirTempC", "C", 1, lambda data: data[0] - 40.0, "ambient air temperature"),
    0x49: ObdPidDefinition(0x49, "acceleratorPedalDPct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "accelerator pedal position D"),
    0x4A: ObdPidDefinition(0x4A, "acceleratorPedalEPct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "accelerator pedal position E"),
    0x4B: ObdPidDefinition(0x4B, "acceleratorPedalFPct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "accelerator pedal position F"),
    0x4C: ObdPidDefinition(0x4C, "commandedThrottleActuatorPct", "pct", 1, lambda data: data[0] * 100.0 / 255.0, "commanded throttle actuator"),
    0x5C: ObdPidDefinition(0x5C, "engineOilTempC", "C", 1, lambda data: data[0] - 40.0, "engine oil temperature"),
    0x5E: ObdPidDefinition(0x5E, "engineFuelRateLph", "L/h", 2, lambda data: _u16(data) * 0.05, "engine fuel rate"),
}


SUPPORTED_PID_PAGES = {0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0}


def decode_mode01_response(payload: str | bytes, *, timestamp: float = 0.0) -> ObdDecodeResult:
    data = _normalize_payload(payload)
    data = _strip_single_frame_prefix(data)
    if len(data) < 2 or data[0] != 0x41:
        raise ValueError("expected OBD Mode 01 response payload starting with 0x41")
    pid = data[1]
    response_data = data[2:]
    if pid in SUPPORTED_PID_PAGES:
        supported = decode_supported_pids(pid, response_data)
        return ObdDecodeResult(timestamp=timestamp, mode=1, pid=pid, values={}, supported_pids=tuple(supported))

    definition = STANDARD_MODE_01_PIDS.get(pid)
    if definition is None:
        return ObdDecodeResult(timestamp=timestamp, mode=1, pid=pid, values={})
    if len(response_data) < definition.data_length:
        raise ValueError(f"PID 0x{pid:02X} response needs {definition.data_length} data byte(s)")
    value = definition.decode(response_data[: definition.data_length])
    return ObdDecodeResult(timestamp=timestamp, mode=1, pid=pid, values={definition.signal: float(value)})


def decode_supported_pids(base_pid: int, data: bytes) -> list[int]:
    if len(data) < 4:
        raise ValueError("supported PID response needs 4 data bytes")
    supported: list[int] = []
    for bit_index in range(32):
        byte = data[bit_index // 8]
        mask = 0x80 >> (bit_index % 8)
        if byte & mask:
            supported.append(base_pid + bit_index + 1)
    return supported


def build_guided_session_payload_from_obd_log(
    path: str | Path,
    *,
    vehicle_profile: str | None = None,
) -> dict[str, Any]:
    anchors, supported_pids, pids_seen, warnings = load_obd_anchor_log(path)
    payload: dict[str, Any] = {
        "version": 1,
        "source": {
            "type": "obd_mode_01_anchor_log",
            "path": str(path),
        },
        "windows": [],
        "anchors": {
            signal: [{"timestamp": point.timestamp, "value": point.value} for point in points]
            for signal, points in sorted(anchors.items())
        },
        "obd": {
            "mode": 1,
            "decodedSignals": sorted(anchors),
            "pidsSeen": [f"0x{pid:02X}" for pid in sorted(pids_seen)],
            "supportedPids": [f"0x{pid:02X}" for pid in sorted(supported_pids)],
            "warnings": warnings,
        },
    }
    if vehicle_profile:
        payload["vehicleProfile"] = vehicle_profile
    return payload


def load_obd_anchor_log(path: str | Path) -> tuple[dict[str, list[AnchorPoint]], set[int], set[int], list[str]]:
    anchors: dict[str, list[AnchorPoint]] = {}
    supported_pids: set[int] = set()
    pids_seen: set[int] = set()
    warnings: list[str] = []

    with Path(path).open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                item = json.loads(line)
                decoded = _parse_jsonl_item(item)
            except (TypeError, ValueError, json.JSONDecodeError) as exc:
                warnings.append(f"line {line_number}: {exc}")
                continue

            for result in decoded:
                if result.pid >= 0:
                    pids_seen.add(result.pid)
                supported_pids.update(result.supported_pids)
                for signal, value in result.values.items():
                    anchors.setdefault(signal, []).append(AnchorPoint(signal=signal, timestamp=result.timestamp, value=value))

    for signal in anchors:
        anchors[signal].sort(key=lambda point: point.timestamp)
    return anchors, supported_pids, pids_seen, warnings


def _parse_jsonl_item(item: dict[str, Any]) -> list[ObdDecodeResult]:
    timestamp = float(item.get("timestamp", item.get("time", 0.0)))
    if "signals" in item and isinstance(item["signals"], dict):
        return [
            ObdDecodeResult(
                timestamp=timestamp,
                mode=1,
                pid=-1,
                values={str(signal): float(value) for signal, value in item["signals"].items()},
            )
        ]
    if "signal" in item and "value" in item:
        return [
            ObdDecodeResult(
                timestamp=timestamp,
                mode=1,
                pid=-1,
                values={str(item["signal"]): float(item["value"])},
            )
        ]
    if "response" in item:
        return [decode_mode01_response(item["response"], timestamp=timestamp)]
    if "pid" in item and "data" in item:
        pid = _parse_pid(item["pid"])
        data = _normalize_payload(item["data"])
        return [decode_mode01_response(bytes([0x41, pid]) + data, timestamp=timestamp)]
    raise ValueError("expected response, pid+data, signal+value, or signals object")


def _parse_pid(value: Any) -> int:
    if isinstance(value, int):
        return value
    text = str(value).strip().lower()
    return int(text, 16) if text.startswith("0x") else int(text)


def _normalize_payload(payload: str | bytes) -> bytes:
    if isinstance(payload, bytes):
        return payload
    text = payload.replace(",", " ").replace("#", " ").strip()
    if not text:
        return b""
    if " " not in text and len(text) % 2 == 0:
        return bytes.fromhex(text)
    return bytes(int(part, 16) for part in text.split())


def _strip_single_frame_prefix(data: bytes) -> bytes:
    if len(data) >= 3 and data[0] <= 0x07 and len(data) >= data[0] + 1 and data[1] == 0x41:
        return data[1 : data[0] + 1]
    return data
