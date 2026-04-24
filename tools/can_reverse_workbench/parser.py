from __future__ import annotations

import csv
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


_CANDUMP_HASH_RE = re.compile(
    r"^\s*(?:\((?P<timestamp>[-+]?\d+(?:\.\d+)?)\)\s+)?"
    r"(?P<interface>[A-Za-z0-9_.:-]+)\s+"
    r"(?P<can_id>[0-9A-Fa-f]+)#(?P<data>[0-9A-Fa-f]*)"
)
_CANDUMP_BRACKET_RE = re.compile(
    r"^\s*(?:\((?P<timestamp>[-+]?\d+(?:\.\d+)?)\)\s+)?"
    r"(?P<interface>[A-Za-z0-9_.:-]+)\s+"
    r"(?P<can_id>[0-9A-Fa-f]+)\s+\[\d+\]\s+(?P<data>[0-9A-Fa-f ,:_-]+)"
)


@dataclass(frozen=True)
class CanFrame:
    timestamp: float
    interface: str
    arbitration_id: int
    data: bytes
    source_line: int = 0

    @property
    def id_hex(self) -> str:
        width = 3 if self.arbitration_id <= 0x7FF else 8
        return f"0x{self.arbitration_id:0{width}X}"

    @property
    def data_hex(self) -> str:
        return self.data.hex().upper()

    @property
    def extended(self) -> bool:
        return self.arbitration_id > 0x7FF


@dataclass
class ParseStats:
    total_lines: int = 0
    parsed: int = 0
    skipped: int = 0
    out_of_order: int = 0
    warnings: list[str] = field(default_factory=list)

    def warn(self, line_no: int, message: str) -> None:
        self.skipped += 1
        if len(self.warnings) < 25:
            self.warnings.append(f"line {line_no}: {message}")


def parse_can_log(path: str | Path) -> tuple[list[CanFrame], ParseStats]:
    """Parse a candump or CSV CAN log and return frames sorted by timestamp."""
    source = Path(path)
    text = source.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if _looks_like_csv(source, lines):
        frames, stats = _parse_csv_lines(lines)
    else:
        frames, stats = _parse_candump_lines(lines)
    stats.out_of_order = _count_out_of_order(frames)
    frames = sorted(frames, key=lambda frame: (frame.timestamp, frame.source_line))
    return frames, stats


def parse_data_bytes(value: str) -> bytes:
    data = value.strip()
    if "#" in data:
        data = data.split("#", 1)[1]
    data = re.sub(r"[\s,:\-_]", "", data)
    if len(data) % 2:
        raise ValueError("data hex has odd length")
    if not re.fullmatch(r"[0-9A-Fa-f]*", data):
        raise ValueError("data hex contains non-hex characters")
    return bytes.fromhex(data)


def parse_can_id(value: str) -> int:
    raw = value.strip()
    if raw.lower().startswith("0x"):
        return int(raw, 16)
    return int(raw, 16)


def _looks_like_csv(source: Path, lines: Iterable[str]) -> bool:
    if source.suffix.lower() == ".csv":
        return True
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lowered = stripped.lower()
        return "," in stripped and "timestamp" in lowered and ("data" in lowered or "payload" in lowered)
    return False


def _parse_candump_lines(lines: list[str]) -> tuple[list[CanFrame], ParseStats]:
    frames: list[CanFrame] = []
    stats = ParseStats()
    implicit_timestamp = 0.0
    for line_no, line in enumerate(lines, start=1):
        stats.total_lines += 1
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = _CANDUMP_HASH_RE.match(stripped) or _CANDUMP_BRACKET_RE.match(stripped)
        if not match:
            stats.warn(line_no, "not a recognized candump frame")
            continue
        try:
            timestamp_text = match.group("timestamp")
            if timestamp_text is None:
                implicit_timestamp += 1e-6
                timestamp = implicit_timestamp
            else:
                timestamp = float(timestamp_text)
                implicit_timestamp = timestamp
            frames.append(
                CanFrame(
                    timestamp=timestamp,
                    interface=match.group("interface"),
                    arbitration_id=parse_can_id(match.group("can_id")),
                    data=parse_data_bytes(match.group("data")),
                    source_line=line_no,
                )
            )
            stats.parsed += 1
        except ValueError as exc:
            stats.warn(line_no, str(exc))
    return frames, stats


def _parse_csv_lines(lines: list[str]) -> tuple[list[CanFrame], ParseStats]:
    stats = ParseStats(total_lines=len(lines))
    frames: list[CanFrame] = []
    reader = csv.DictReader(lines)
    if not reader.fieldnames:
        return frames, stats
    fields = {_normalize_field(name): name for name in reader.fieldnames}
    timestamp_key = _first_present(fields, "timestamp", "time", "ts")
    interface_key = _first_present(fields, "interface", "iface", "channel", "bus")
    can_id_key = _first_present(fields, "id", "canid", "can_id", "arbitrationid", "arbitration_id")
    data_key = _first_present(fields, "data", "payload", "bytes")
    if not timestamp_key or not can_id_key or not data_key:
        stats.warn(1, "CSV must include timestamp, id, and data columns")
        return frames, stats

    for row_no, row in enumerate(reader, start=2):
        try:
            frames.append(
                CanFrame(
                    timestamp=float(row[timestamp_key]),
                    interface=(row.get(interface_key) if interface_key else None) or "can0",
                    arbitration_id=parse_can_id(row[can_id_key]),
                    data=parse_data_bytes(row[data_key]),
                    source_line=row_no,
                )
            )
            stats.parsed += 1
        except (TypeError, ValueError, KeyError) as exc:
            stats.warn(row_no, str(exc))
    return frames, stats


def _normalize_field(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.strip().lower())


def _first_present(fields: dict[str, str], *names: str) -> str | None:
    for name in names:
        normalized = _normalize_field(name)
        if normalized in fields:
            return fields[normalized]
    return None


def _count_out_of_order(frames: list[CanFrame]) -> int:
    count = 0
    previous = None
    for frame in frames:
        if previous is not None and frame.timestamp < previous:
            count += 1
        previous = frame.timestamp
    return count
