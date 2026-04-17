from __future__ import annotations

import json
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tools.bbb_hub.can_diagnostics import CanDiagnosticsEngine

from .bitfield import extract_signal_value
from .export import validate_signal_dictionary
from .parser import CanFrame, parse_can_log, parse_can_id


@dataclass(frozen=True)
class DecoderSignal:
    name: str
    can_id: int
    start_bit: int
    length: int
    endian: str
    signed: bool
    scale: float
    offset: float
    unit: str
    confidence: float

    @property
    def byte_index(self) -> int:
        return self.start_bit // 8

    @property
    def byte_length(self) -> int:
        return (self.start_bit % 8 + self.length + 7) // 8


class CanSignalDictionary:
    def __init__(self, signals: list[DecoderSignal], source: dict[str, Any] | None = None) -> None:
        self.signals = signals
        self.source = source or {}
        self._by_can_id: dict[int, list[DecoderSignal]] = {}
        for signal in signals:
            self._by_can_id.setdefault(signal.can_id, []).append(signal)

    @classmethod
    def from_path(cls, path: str | Path) -> "CanSignalDictionary":
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        errors = validate_signal_dictionary(payload)
        if errors:
            raise ValueError("; ".join(errors))
        signals = [_decode_signal(name, signal) for name, signal in payload["signals"].items()]
        return cls(signals=signals, source=payload.get("source", {}))

    def decode_frame(self, frame: CanFrame) -> dict[str, float]:
        decoded: dict[str, float] = {}
        for signal in self._by_can_id.get(frame.arbitration_id, []):
            if signal.start_bit + signal.length > len(frame.data) * 8:
                continue
            raw = extract_signal_value(frame.data, signal.start_bit, signal.length, signal.endian, signal.signed)
            decoded[signal.name] = raw * signal.scale + signal.offset
        return decoded

    def decode_frames(self, frames: list[CanFrame]) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        latest: dict[str, float] = {}
        for frame in frames:
            decoded = self.decode_frame(frame)
            if not decoded:
                continue
            latest.update(decoded)
            rows.append({"timestamp": frame.timestamp, "signals": dict(latest)})
        return rows


class CanLogSignalReplay:
    """Replay a raw CAN log as decoded vehicle_state overlays for BBB testing."""

    def __init__(
        self,
        signal_dictionary_path: str | Path,
        raw_log_path: str | Path,
        *,
        repeat: bool = True,
        diagnostics_enabled: bool = True,
    ) -> None:
        self.dictionary_path = str(signal_dictionary_path)
        self.raw_log_path = str(raw_log_path)
        self.dictionary = CanSignalDictionary.from_path(signal_dictionary_path)
        self.frames, self.parse_stats = parse_can_log(raw_log_path)
        if not self.frames:
            raise ValueError(f"CAN replay log has no frames: {raw_log_path}")
        self.repeat = repeat
        self._latest: dict[str, float] = {}
        self._recent_frames: deque[dict[str, Any]] = deque(maxlen=100)
        self._diagnostics = CanDiagnosticsEngine(source="canReplay", enabled=diagnostics_enabled)
        self._index = 0
        self._started_monotonic = time.monotonic()
        self._log_start = self.frames[0].timestamp
        self._log_end = self.frames[-1].timestamp

    def snapshot(self, now_monotonic: float | None = None) -> dict[str, float]:
        now = time.monotonic() if now_monotonic is None else now_monotonic
        replay_timestamp = self._log_start + (now - self._started_monotonic)
        if replay_timestamp > self._log_end and self.repeat:
            self._restart(now)
            replay_timestamp = self._log_start
        while self._index < len(self.frames) and self.frames[self._index].timestamp <= replay_timestamp:
            frame = self.frames[self._index]
            decoded = self.dictionary.decode_frame(frame)
            self._recent_frames.append(_frame_evidence(frame, decoded))
            self._diagnostics.observe_frame(frame, decoded, now_monotonic=now)
            self._latest.update(decoded)
            self._index += 1
        return dict(self._latest)

    def health(self) -> dict[str, Any]:
        return {
            "enabled": True,
            "dictionary": self.dictionary_path,
            "log": self.raw_log_path,
            "signals": [signal.name for signal in self.dictionary.signals],
            "frameIndex": self._index,
            "frameCount": len(self.frames),
            "parseSkipped": self.parse_stats.skipped,
            "repeat": self.repeat,
        }

    def recent_frames(self) -> list[dict[str, Any]]:
        return list(self._recent_frames)

    def diagnostics(self) -> dict[str, Any]:
        return self._diagnostics.snapshot()

    def _restart(self, now_monotonic: float) -> None:
        self._latest.clear()
        self._recent_frames.clear()
        self._index = 0
        self._started_monotonic = now_monotonic


def _decode_signal(name: str, payload: dict[str, Any]) -> DecoderSignal:
    return DecoderSignal(
        name=name,
        can_id=parse_can_id(str(payload["canId"])),
        start_bit=int(payload["startBit"]),
        length=int(payload["length"]),
        endian=str(payload["endian"]),
        signed=bool(payload["signed"]),
        scale=float(payload["scale"]),
        offset=float(payload["offset"]),
        unit=str(payload.get("unit", "")),
        confidence=float(payload.get("confidence", 0.0)),
    )


def _frame_evidence(frame: CanFrame, decoded: dict[str, float]) -> dict[str, Any]:
    return {
        "timestamp": frame.timestamp,
        "canId": frame.id_hex,
        "data": frame.data_hex,
        "decoded": decoded,
    }
