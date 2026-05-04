from __future__ import annotations

import json
import os
import re
import select
import termios
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .obd_anchors import ObdDecodeResult, decode_mode01_response


SERIAL_BAUDS = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
}
PID_ALIASES = {
    "engine_load": 0x04,
    "load": 0x04,
    "coolant": 0x05,
    "coolant_c": 0x05,
    "map": 0x0B,
    "map_kpa": 0x0B,
    "rpm": 0x0C,
    "speed": 0x0D,
    "speed_kph": 0x0D,
    "iat": 0x0F,
    "intake_air_temp": 0x0F,
    "maf": 0x10,
    "maf_gps": 0x10,
    "throttle": 0x11,
    "throttle_pct": 0x11,
    "fuel": 0x2F,
    "fuel_pct": 0x2F,
    "baro": 0x33,
    "barometric_pressure": 0x33,
    "voltage": 0x42,
    "module_voltage": 0x42,
    "oil_temp": 0x5C,
    "fuel_rate": 0x5E,
}
DEFAULT_PIDS = (0x0C, 0x0D, 0x04, 0x05, 0x0B, 0x0F, 0x10, 0x11, 0x42)
DEFAULT_INIT_COMMANDS = ("ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0")
NEGATIVE_RESPONSES = {
    "NO DATA",
    "STOPPED",
    "UNABLE TO CONNECT",
    "BUS INIT: ERROR",
    "CAN ERROR",
    "BUFFER FULL",
    "?",
}
HEX_TOKEN_RE = re.compile(r"^[0-9A-Fa-f]{1,2}$")


@dataclass(frozen=True)
class Elm327PollResult:
    timestamp: float
    command: str
    pid: int
    raw_text: str
    raw_lines: tuple[str, ...]
    response: str | None
    decoded: ObdDecodeResult | None
    error: str | None = None


class Elm327Connection:
    """Small stdlib-only serial client for read-only ELM327 Mode 01 polling."""

    def __init__(
        self,
        device: str | Path,
        *,
        baud: int = 38400,
        timeout_sec: float = 2.0,
        settle_sec: float = 0.05,
    ) -> None:
        if baud not in SERIAL_BAUDS:
            raise ValueError(f"unsupported ELM327 baud {baud}; expected one of {sorted(SERIAL_BAUDS)}")
        self.device = str(device)
        self.baud = baud
        self.timeout_sec = timeout_sec
        self.settle_sec = settle_sec
        self._fd: int | None = None

    def __enter__(self) -> "Elm327Connection":
        self.open()
        return self

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        self.close()

    def open(self) -> None:
        if self._fd is not None:
            return
        fd = os.open(self.device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        try:
            _configure_serial(fd, self.baud)
            termios.tcflush(fd, termios.TCIOFLUSH)
        except Exception:
            os.close(fd)
            raise
        self._fd = fd

    def close(self) -> None:
        if self._fd is None:
            return
        os.close(self._fd)
        self._fd = None

    def initialize(self, commands: Iterable[str] = DEFAULT_INIT_COMMANDS) -> list[tuple[str, str]]:
        responses: list[tuple[str, str]] = []
        for command in commands:
            timeout = max(self.timeout_sec, 4.0) if command.upper() == "ATZ" else self.timeout_sec
            raw = self.command(command, timeout_sec=timeout)
            responses.append((command, raw))
            time.sleep(self.settle_sec)
        return responses

    def command(self, command: str, *, timeout_sec: float | None = None) -> str:
        if self._fd is None:
            raise RuntimeError("ELM327 connection is not open")
        text = command.strip().upper()
        os.write(self._fd, (text + "\r").encode("ascii"))
        return self._read_until_prompt(timeout_sec=timeout_sec or self.timeout_sec)

    def poll_pid(self, pid: int) -> Elm327PollResult:
        command = f"01{pid:02X}"
        timestamp = time.time()
        try:
            raw_text = self.command(command)
            raw_lines = tuple(clean_elm327_lines(raw_text))
            response = extract_mode01_response(raw_lines, pid)
            decoded = decode_mode01_response(response, timestamp=timestamp) if response else None
            error = None if response else _negative_response(raw_lines) or "no Mode 01 response"
            return Elm327PollResult(
                timestamp=timestamp,
                command=command,
                pid=pid,
                raw_text=raw_text,
                raw_lines=raw_lines,
                response=response,
                decoded=decoded,
                error=error,
            )
        except (OSError, ValueError, RuntimeError) as exc:
            return Elm327PollResult(
                timestamp=timestamp,
                command=command,
                pid=pid,
                raw_text="",
                raw_lines=(),
                response=None,
                decoded=None,
                error=str(exc),
            )

    def _read_until_prompt(self, *, timeout_sec: float) -> str:
        assert self._fd is not None
        deadline = time.monotonic() + timeout_sec
        chunks: list[bytes] = []
        while time.monotonic() < deadline:
            remaining = max(deadline - time.monotonic(), 0.0)
            readable, _, _ = select.select([self._fd], [], [], min(remaining, 0.1))
            if not readable:
                continue
            try:
                chunk = os.read(self._fd, 1024)
            except BlockingIOError:
                continue
            if not chunk:
                continue
            chunks.append(chunk)
            if b">" in chunk:
                break
        return b"".join(chunks).decode("ascii", errors="replace")


def capture_elm327_obd_log(
    *,
    device: str | Path,
    out_path: str | Path,
    baud: int = 38400,
    pids: Iterable[int] = DEFAULT_PIDS,
    duration_sec: float | None = None,
    sample_interval_sec: float = 0.25,
    timeout_sec: float = 2.0,
    initialize: bool = True,
    supported_filter: bool = True,
    include_errors: bool = True,
    print_rows: bool = False,
) -> dict[str, Any]:
    pid_cycle = tuple(dict.fromkeys(int(pid) for pid in pids))
    if not pid_cycle:
        raise ValueError("at least one PID is required")

    output = Path(out_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    rows = 0
    errors = 0
    decoded_signals: set[str] = set()
    supported_pids: set[int] = set()
    pids_polled: set[int] = set()

    with Elm327Connection(device, baud=baud, timeout_sec=timeout_sec) as connection:
        init_responses = connection.initialize() if initialize else []
        with output.open("w", encoding="utf-8") as handle:
            supported = connection.poll_pid(0x00) if supported_filter else None
            if supported is not None:
                row = elm327_poll_result_to_jsonl_row(supported)
                handle.write(json.dumps(row, sort_keys=True) + "\n")
                rows += 1
                if supported.decoded is not None:
                    supported_pids.update(supported.decoded.supported_pids)
                if print_rows:
                    print(json.dumps(row, sort_keys=True))

            active_pids = _filter_supported_pids(pid_cycle, supported_pids) if supported_pids else pid_cycle
            deadline = None if duration_sec is None else time.monotonic() + max(duration_sec, 0.0)
            while deadline is None or time.monotonic() < deadline:
                for pid in active_pids:
                    if deadline is not None and time.monotonic() >= deadline:
                        break
                    result = connection.poll_pid(pid)
                    pids_polled.add(pid)
                    if result.error:
                        errors += 1
                    if result.decoded:
                        decoded_signals.update(result.decoded.values)
                    if result.response or include_errors:
                        row = elm327_poll_result_to_jsonl_row(result)
                        handle.write(json.dumps(row, sort_keys=True) + "\n")
                        rows += 1
                        if print_rows:
                            print(json.dumps(row, sort_keys=True))
                    time.sleep(max(sample_interval_sec, 0.0))

    return {
        "startedAt": started,
        "endedAt": time.time(),
        "device": str(device),
        "baud": baud,
        "output": str(output),
        "rows": rows,
        "errors": errors,
        "pidsPolled": [f"0x{pid:02X}" for pid in sorted(pids_polled)],
        "supportedPids": [f"0x{pid:02X}" for pid in sorted(supported_pids)],
        "decodedSignals": sorted(decoded_signals),
        "initialized": initialize,
        "initCommands": [command for command, _ in init_responses],
    }


def elm327_poll_result_to_jsonl_row(result: Elm327PollResult) -> dict[str, Any]:
    row: dict[str, Any] = {
        "timestamp": result.timestamp,
        "source": "elm327",
        "mode": 1,
        "pid": f"0x{result.pid:02X}",
        "command": result.command,
        "rawLines": list(result.raw_lines),
    }
    if result.response:
        row["response"] = result.response
    if result.decoded is not None and result.decoded.values:
        row["signals"] = result.decoded.values
    if result.decoded is not None and result.decoded.supported_pids:
        row["supportedPids"] = [f"0x{pid:02X}" for pid in result.decoded.supported_pids]
    if result.error:
        row["error"] = result.error
    return row


def parse_pid_selection(values: Iterable[str] | None) -> tuple[int, ...]:
    if not values:
        return DEFAULT_PIDS
    pids: list[int] = []
    for value in values:
        for token in str(value).replace(";", ",").split(","):
            stripped = token.strip()
            if not stripped:
                continue
            pids.append(parse_pid(stripped))
    return tuple(dict.fromkeys(pids))


def parse_pid(value: str | int) -> int:
    if isinstance(value, int):
        pid = value
    else:
        text = value.strip().lower()
        if text in PID_ALIASES:
            pid = PID_ALIASES[text]
        elif text.startswith("01") and len(text) == 4:
            pid = int(text[2:], 16)
        elif text.startswith("0x"):
            pid = int(text, 16)
        else:
            pid = int(text, 16)
    if not 0x00 <= pid <= 0xFF:
        raise ValueError(f"PID out of byte range: 0x{pid:X}")
    return pid


def clean_elm327_lines(raw_text: str) -> list[str]:
    text = raw_text.replace("\r", "\n").replace(">", "\n")
    lines: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        upper = line.upper()
        if upper in {"OK", "SEARCHING..."}:
            continue
        if upper.startswith("ELM327") or upper.startswith("AT"):
            continue
        lines.append(upper)
    return lines


def extract_mode01_response(lines: Iterable[str], pid: int) -> str | None:
    for line in lines:
        upper = line.strip().upper()
        if upper in NEGATIVE_RESPONSES or upper.startswith("SEARCHING"):
            continue
        bytes_for_line = _line_to_bytes(upper)
        if not bytes_for_line:
            continue
        for index in range(len(bytes_for_line) - 1):
            if bytes_for_line[index] == 0x41 and bytes_for_line[index + 1] == pid:
                return " ".join(f"{byte:02X}" for byte in bytes_for_line[index:])
    return None


def _line_to_bytes(line: str) -> list[int]:
    cleaned = line.replace(":", " ").replace(",", " ").replace("#", " ")
    tokens = cleaned.split()
    if len(tokens) == 1 and len(tokens[0]) % 2 == 0 and re.fullmatch(r"[0-9A-Fa-f]+", tokens[0]):
        text = tokens[0]
        return [int(text[index : index + 2], 16) for index in range(0, len(text), 2)]
    values: list[int] = []
    for token in tokens:
        if HEX_TOKEN_RE.fullmatch(token):
            values.append(int(token, 16))
    return values


def _negative_response(lines: Iterable[str]) -> str | None:
    for line in lines:
        upper = line.upper()
        if upper in NEGATIVE_RESPONSES:
            return upper
        if upper.startswith("7F"):
            return upper
    return None


def _filter_supported_pids(pids: tuple[int, ...], supported_pids: set[int]) -> tuple[int, ...]:
    filtered = tuple(pid for pid in pids if pid in supported_pids)
    return filtered or pids


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
