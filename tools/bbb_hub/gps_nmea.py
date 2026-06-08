from __future__ import annotations

import asyncio
import calendar
import os
import termios
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional


def _parse_float(value: str) -> Optional[float]:
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def _parse_int(value: str) -> Optional[int]:
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _parse_lat_lng(raw: str, hemi: str, degree_digits: int) -> Optional[float]:
    if not raw or "." not in raw or len(raw) < degree_digits + 3:
        return None
    degrees = _parse_float(raw[:degree_digits])
    minutes = _parse_float(raw[degree_digits:])
    if degrees is None or minutes is None:
        return None
    value = degrees + minutes / 60.0
    if hemi in {"S", "W"}:
        value = -value
    return value


def _parse_lat(raw: str, hemi: str) -> Optional[float]:
    return _parse_lat_lng(raw, hemi, 2)


def _parse_lng(raw: str, hemi: str) -> Optional[float]:
    return _parse_lat_lng(raw, hemi, 3)


def _validate_sentence(line: str) -> list[str]:
    text = line.strip()
    if not text:
        raise ValueError("empty sentence")
    if not text.startswith("$"):
        raise ValueError("missing '$'")

    checksum_text = ""
    body = text[1:]
    if "*" in body:
        body, checksum_text = body.split("*", 1)
        checksum = 0
        for char in body:
            checksum ^= ord(char)
        try:
            expected = int(checksum_text[:2], 16)
        except ValueError as exc:
            raise ValueError("bad checksum field") from exc
        if checksum != expected:
            raise ValueError("checksum mismatch")

    fields = body.split(",")
    if not fields or len(fields[0]) < 3:
        raise ValueError("missing talker/type")
    return fields


def _timestamp_from_fields(
    time_field: str,
    date_field: str,
    received_wall_time: float,
) -> int:
    if not time_field:
        return int(received_wall_time * 1000)

    now_utc = datetime.fromtimestamp(received_wall_time, tz=timezone.utc)
    if date_field and len(date_field) >= 6:
        try:
            day = int(date_field[0:2])
            month = int(date_field[2:4])
            year = 2000 + int(date_field[4:6])
        except ValueError:
            year = now_utc.year
            month = now_utc.month
            day = now_utc.day
    else:
        year = now_utc.year
        month = now_utc.month
        day = now_utc.day

    try:
        hour = int(time_field[0:2]) if len(time_field) >= 2 else 0
        minute = int(time_field[2:4]) if len(time_field) >= 4 else 0
        sec_float = float(time_field[4:]) if len(time_field) > 4 else 0.0
    except ValueError:
        return int(received_wall_time * 1000)

    second = int(sec_float)
    microsecond = int(round((sec_float - second) * 1_000_000))
    dt = datetime(year, month, day, hour, minute, second, microsecond, tzinfo=timezone.utc)
    return int(calendar.timegm(dt.utctimetuple()) * 1000 + dt.microsecond / 1000)


def _estimate_accuracy_m(hdop: Optional[float], default_accuracy_m: float) -> float:
    if hdop is None or hdop <= 0.0:
        return default_accuracy_m
    return max(5.0, hdop * 5.0)


@dataclass
class GpsSample:
    lat: Optional[float]
    lng: Optional[float]
    bearing: float
    speed_kph: float
    accuracy_m: float
    timestamp_ms: int
    fix_valid: bool
    heading_reliable: bool
    satellites: int
    source: str
    received_monotonic: float


@dataclass
class GpsHealth:
    device: str
    serial_ok: bool
    stale: bool
    age_ms: int
    parse_errors: int
    last_error: str


class NmeaGpsState:
    def __init__(
        self,
        *,
        min_heading_speed_kph: float = 7.0,
        default_accuracy_m: float = 25.0,
        fix_hold_seconds: float = 15.0,
    ) -> None:
        self._min_heading_speed_kph = min_heading_speed_kph
        self._default_accuracy_m = default_accuracy_m
        self._fix_hold_seconds = max(0.0, fix_hold_seconds)
        self._rmc_status: Optional[str] = None
        self._gga_fix_quality: Optional[int] = None
        self._lat: Optional[float] = None
        self._lng: Optional[float] = None
        self._bearing = 0.0
        self._course_present = False
        self._speed_kph = 0.0
        self._satellites = 0
        self._accuracy_m = default_accuracy_m
        self._timestamp_ms = 0
        self._last_received_monotonic = 0.0
        self._last_valid_sample: Optional[GpsSample] = None
        self._last_valid_monotonic = 0.0

    def _raw_fix_valid(self) -> bool:
        if self._lat is None or self._lng is None:
            return False
        if self._gga_fix_quality is not None and self._gga_fix_quality > 0:
            return True
        return self._rmc_status == "A"

    def _build_state_sample(self, received_monotonic: float, *, fix_valid: bool) -> GpsSample:
        timestamp_ms = self._timestamp_ms or int(time.time() * 1000)
        heading_reliable = self._course_present and fix_valid and self._speed_kph >= self._min_heading_speed_kph

        return GpsSample(
            lat=self._lat,
            lng=self._lng,
            bearing=self._bearing,
            speed_kph=self._speed_kph,
            accuracy_m=self._accuracy_m,
            timestamp_ms=timestamp_ms,
            fix_valid=fix_valid,
            heading_reliable=heading_reliable,
            satellites=self._satellites,
            source="hardware",
            received_monotonic=received_monotonic,
        )

    def _build_held_sample(self, received_monotonic: float) -> Optional[GpsSample]:
        if self._last_valid_sample is None:
            return None
        if received_monotonic - self._last_valid_monotonic > self._fix_hold_seconds:
            return None

        sample = self._last_valid_sample
        return GpsSample(
            lat=sample.lat,
            lng=sample.lng,
            bearing=sample.bearing,
            speed_kph=sample.speed_kph,
            accuracy_m=sample.accuracy_m,
            timestamp_ms=sample.timestamp_ms,
            fix_valid=True,
            heading_reliable=sample.heading_reliable,
            satellites=sample.satellites,
            source=sample.source,
            received_monotonic=received_monotonic,
        )

    def _build_sample(self, received_monotonic: float) -> GpsSample:
        if self._raw_fix_valid():
            sample = self._build_state_sample(received_monotonic, fix_valid=True)
            self._last_valid_sample = sample
            self._last_valid_monotonic = received_monotonic
            return sample

        held = self._build_held_sample(received_monotonic)
        if held is not None:
            return held

        return self._build_state_sample(received_monotonic, fix_valid=False)

    def feed_line(
        self,
        line: str,
        *,
        received_wall_time: Optional[float] = None,
        received_monotonic: Optional[float] = None,
    ) -> Optional[GpsSample]:
        received_wall_time = time.time() if received_wall_time is None else received_wall_time
        received_monotonic = time.monotonic() if received_monotonic is None else received_monotonic

        fields = _validate_sentence(line)
        sentence_type = fields[0][-3:]

        if sentence_type == "RMC":
            status = fields[2].strip().upper() if len(fields) > 2 else ""
            if status in {"A", "V"}:
                self._rmc_status = status

            lat = _parse_lat(fields[3] if len(fields) > 3 else "", fields[4].strip().upper() if len(fields) > 4 else "")
            lng = _parse_lng(fields[5] if len(fields) > 5 else "", fields[6].strip().upper() if len(fields) > 6 else "")
            if lat is not None:
                self._lat = lat
            if lng is not None:
                self._lng = lng

            speed_knots = _parse_float(fields[7] if len(fields) > 7 else "")
            if speed_knots is not None:
                self._speed_kph = max(0.0, speed_knots * 1.852)

            course = _parse_float(fields[8] if len(fields) > 8 else "")
            if course is not None:
                self._bearing = course % 360.0
                self._course_present = True
            else:
                self._course_present = False

            self._timestamp_ms = _timestamp_from_fields(
                fields[1] if len(fields) > 1 else "",
                fields[9] if len(fields) > 9 else "",
                received_wall_time,
            )
        elif sentence_type == "GGA":
            lat = _parse_lat(fields[2] if len(fields) > 2 else "", fields[3].strip().upper() if len(fields) > 3 else "")
            lng = _parse_lng(fields[4] if len(fields) > 4 else "", fields[5].strip().upper() if len(fields) > 5 else "")
            if lat is not None:
                self._lat = lat
            if lng is not None:
                self._lng = lng

            fix_quality = _parse_int(fields[6] if len(fields) > 6 else "")
            if fix_quality is not None:
                self._gga_fix_quality = fix_quality

            satellites = _parse_int(fields[7] if len(fields) > 7 else "")
            if satellites is not None:
                self._satellites = max(0, satellites)

            hdop = _parse_float(fields[8] if len(fields) > 8 else "")
            self._accuracy_m = _estimate_accuracy_m(hdop, self._default_accuracy_m)
            self._timestamp_ms = _timestamp_from_fields(
                fields[1] if len(fields) > 1 else "",
                "",
                received_wall_time,
            )
        else:
            return None

        self._last_received_monotonic = received_monotonic
        return self._build_sample(received_monotonic)

    def latest_sample(self) -> Optional[GpsSample]:
        if self._last_received_monotonic <= 0.0:
            return None
        return self._build_sample(self._last_received_monotonic)


class NmeaSerialGpsSource:
    def __init__(
        self,
        *,
        device: str,
        baud: int,
        read_timeout_ms: int,
        stale_ms: int,
        min_heading_speed_kph: float,
    ) -> None:
        self._device = device
        self._baud = baud
        self._read_timeout_ms = max(10, read_timeout_ms)
        self._stale_ms = max(100, stale_ms)
        self._parser = NmeaGpsState(min_heading_speed_kph=min_heading_speed_kph)
        self._fd: Optional[int] = None
        self._buffer = ""
        self._latest_sample: Optional[GpsSample] = None
        self._last_sentence_monotonic = 0.0
        self._parse_errors = 0
        self._last_error = ""
        self._serial_ok = False

    @property
    def device(self) -> str:
        return self._device

    def _baud_constant(self) -> int:
        mapping = {
            4800: termios.B4800,
            9600: termios.B9600,
            19200: termios.B19200,
            38400: termios.B38400,
            57600: termios.B57600,
            115200: termios.B115200,
        }
        if self._baud not in mapping:
            raise ValueError(f"unsupported baud rate: {self._baud}")
        return mapping[self._baud]

    def _configure_fd(self, fd: int) -> None:
        attrs = termios.tcgetattr(fd)
        baud_flag = self._baud_constant()
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CLOCAL | termios.CREAD | termios.CS8
        attrs[3] = 0
        attrs[4] = baud_flag
        attrs[5] = baud_flag
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = max(1, int(round(self._read_timeout_ms / 100.0)))
        termios.tcsetattr(fd, termios.TCSANOW, attrs)

    def _close_fd(self) -> None:
        if self._fd is not None:
            try:
                os.close(self._fd)
            except OSError:
                pass
        self._fd = None
        self._serial_ok = False

    def _open_fd(self) -> None:
        fd = os.open(self._device, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
        self._configure_fd(fd)
        self._fd = fd
        self._serial_ok = True
        self._last_error = ""

    def _handle_line(self, line: str, now_wall: float, now_mono: float) -> None:
        if not line.strip():
            return
        sample = self._parser.feed_line(
            line,
            received_wall_time=now_wall,
            received_monotonic=now_mono,
        )
        if sample is not None:
            self._latest_sample = sample
            self._last_sentence_monotonic = now_mono

    async def run(self) -> None:
        sleep_sec = self._read_timeout_ms / 1000.0
        while True:
            if self._fd is None:
                try:
                    self._open_fd()
                    print(f"[bbb_hub] GPS serial opened {self._device} @ {self._baud}")
                except Exception as exc:
                    self._last_error = str(exc)
                    self._serial_ok = False
                    await asyncio.sleep(1.0)
                    continue

            try:
                chunk = os.read(self._fd, 4096)
                if not chunk:
                    await asyncio.sleep(sleep_sec)
                    continue
                self._buffer += chunk.decode("ascii", errors="ignore")
                while "\n" in self._buffer:
                    line, self._buffer = self._buffer.split("\n", 1)
                    now_wall = time.time()
                    now_mono = time.monotonic()
                    try:
                        self._handle_line(line, now_wall, now_mono)
                    except Exception as exc:
                        self._parse_errors += 1
                        self._last_error = str(exc)
            except BlockingIOError:
                await asyncio.sleep(sleep_sec)
            except OSError as exc:
                self._last_error = str(exc)
                self._close_fd()
                await asyncio.sleep(1.0)

    def snapshot(self) -> tuple[Optional[GpsSample], GpsHealth]:
        now = time.monotonic()
        if self._last_sentence_monotonic > 0.0:
            age_ms = int((now - self._last_sentence_monotonic) * 1000)
        else:
            age_ms = -1
        stale = age_ms < 0 or age_ms > self._stale_ms
        health = GpsHealth(
            device=self._device,
            serial_ok=self._serial_ok,
            stale=stale,
            age_ms=age_ms,
            parse_errors=self._parse_errors,
            last_error=self._last_error,
        )
        return self._latest_sample, health


def build_hardware_gps_payload(
    sample: Optional[GpsSample],
    *,
    stale: bool,
    now_ms: Optional[int] = None,
) -> dict:
    now_ms = int(time.time() * 1000) if now_ms is None else now_ms
    payload = {
        "bearing": sample.bearing if sample is not None else 0.0,
        "accuracyM": sample.accuracy_m if sample is not None else 25.0,
        "timestampMs": sample.timestamp_ms if sample is not None else now_ms,
        "fixValid": bool(sample is not None and sample.fix_valid and not stale),
        "satellites": sample.satellites if sample is not None else 0,
        "speedKph": sample.speed_kph if sample is not None else 0.0,
        "headingReliable": bool(sample is not None and sample.heading_reliable and not stale),
    }
    if sample is not None and sample.lat is not None:
        payload["lat"] = sample.lat
    if sample is not None and sample.lng is not None:
        payload["lng"] = sample.lng
    return payload
