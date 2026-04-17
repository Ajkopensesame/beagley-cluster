from __future__ import annotations

import time
from collections import Counter, deque
from dataclasses import dataclass, field
from typing import Any

from tools.can_reverse_workbench.parser import CanFrame
from tools.vehicle_analysis.findings import make_diagnostic_finding
from tools.vehicle_analysis.stats import clamp, median, stddev, value_range
from tools.vehicle_analysis.values import number_or_none


DYNAMIC_SIGNALS = {"rpm", "speedKph"}


@dataclass
class CanIdStats:
    can_id: str
    frame_count: int = 0
    first_seen_monotonic: float | None = None
    last_seen_monotonic: float | None = None
    last_dlc: int | None = None
    dlc_counts: Counter[int] = field(default_factory=Counter)
    intervals: deque[float] = field(default_factory=lambda: deque(maxlen=80))
    last_data_hex: str | None = None
    same_data_count: int = 0
    same_data_since_monotonic: float | None = None
    decoded_signals: set[str] = field(default_factory=set)


@dataclass
class DecodedSignalStats:
    name: str
    samples: int = 0
    first_seen_monotonic: float | None = None
    last_seen_monotonic: float | None = None
    last_value: float | None = None
    values: deque[tuple[float, float]] = field(default_factory=lambda: deque(maxlen=80))


class CanDiagnosticsEngine:
    def __init__(
        self,
        *,
        source: str,
        enabled: bool = True,
        min_stale_seconds: float = 0.75,
        stale_interval_multiplier: float = 5.0,
        no_frame_grace_seconds: float = 2.0,
        jitter_ratio_threshold: float = 2.5,
        stuck_window_seconds: float = 5.0,
        stuck_min_samples: int = 20,
        event_retention_seconds: float = 30.0,
    ) -> None:
        self.source = source
        self.enabled = enabled
        self.min_stale_seconds = min_stale_seconds
        self.stale_interval_multiplier = stale_interval_multiplier
        self.no_frame_grace_seconds = no_frame_grace_seconds
        self.jitter_ratio_threshold = jitter_ratio_threshold
        self.stuck_window_seconds = stuck_window_seconds
        self.stuck_min_samples = stuck_min_samples
        self.event_retention_seconds = event_retention_seconds
        self._started_monotonic = time.monotonic()
        self._frame_count = 0
        self._id_stats: dict[str, CanIdStats] = {}
        self._signal_stats: dict[str, DecodedSignalStats] = {}
        self._recent_events: deque[tuple[float, dict[str, Any]]] = deque(maxlen=100)

    def observe_frame(
        self,
        frame: CanFrame,
        decoded: dict[str, float],
        *,
        now_monotonic: float | None = None,
    ) -> None:
        if not self.enabled:
            return
        now = time.monotonic() if now_monotonic is None else now_monotonic
        self._frame_count += 1
        can_id = frame.id_hex
        stats = self._id_stats.setdefault(can_id, CanIdStats(can_id=can_id))

        if stats.first_seen_monotonic is None:
            stats.first_seen_monotonic = now
        if stats.last_seen_monotonic is not None and now > stats.last_seen_monotonic:
            stats.intervals.append(now - stats.last_seen_monotonic)

        dlc = len(frame.data)
        if stats.last_dlc is not None and dlc != stats.last_dlc:
            self._record_event(
                now,
                can_id,
                "dlc_changed",
                "warning",
                f"{can_id} changed payload length from {stats.last_dlc} to {dlc}",
                confidence=0.82,
                previousDlc=stats.last_dlc,
                currentDlc=dlc,
                suspectedCauses=["wrong bus profile", "vehicle mode changed", "decoder mismatch", "frame corruption"],
            )
        stats.last_dlc = dlc
        stats.dlc_counts[dlc] += 1

        data_hex = frame.data_hex
        if data_hex == stats.last_data_hex:
            stats.same_data_count += 1
        else:
            stats.last_data_hex = data_hex
            stats.same_data_count = 1
            stats.same_data_since_monotonic = now

        stats.frame_count += 1
        stats.last_seen_monotonic = now
        for signal_name, value in decoded.items():
            stats.decoded_signals.add(signal_name)
            self._observe_signal(signal_name, value, now)

    def snapshot(self, now_monotonic: float | None = None) -> dict[str, Any]:
        now = time.monotonic() if now_monotonic is None else now_monotonic
        if not self.enabled:
            return {"enabled": False, "source": self.source, "ok": True, "findings": []}

        findings = self._fresh_events(now)
        findings.extend(self._bus_silence_findings(now))
        for stats in self._id_stats.values():
            findings.extend(self._id_timing_findings(stats, now))
            findings.extend(self._payload_stuck_findings(stats, now))
        for stats in self._signal_stats.values():
            findings.extend(self._signal_stuck_findings(stats, now))

        return {
            "enabled": True,
            "source": self.source,
            "ok": not any(finding.get("severity") in {"warning", "error"} for finding in findings),
            "frameCount": self._frame_count,
            "canIdCount": len(self._id_stats),
            "decodedSignals": sorted(self._signal_stats),
            "findings": findings,
            "ids": [self._id_summary(stats, now) for stats in sorted(self._id_stats.values(), key=lambda item: item.can_id)],
        }

    def _observe_signal(self, signal_name: str, raw_value: Any, now: float) -> None:
        value = number_or_none(raw_value)
        if value is None:
            return
        stats = self._signal_stats.setdefault(signal_name, DecodedSignalStats(name=signal_name))
        if stats.first_seen_monotonic is None:
            stats.first_seen_monotonic = now
        stats.samples += 1
        stats.last_seen_monotonic = now
        stats.last_value = value
        stats.values.append((now, value))

    def _record_event(
        self,
        now: float,
        subject: str,
        code: str,
        severity: str,
        message: str,
        *,
        confidence: float,
        **details: Any,
    ) -> None:
        self._recent_events.append(
            (
                now,
                _finding(
                    source=self.source,
                    subject=subject,
                    code=code,
                    severity=severity,
                    message=message,
                    confidence=confidence,
                    **details,
                ),
            )
        )

    def _fresh_events(self, now: float) -> list[dict[str, Any]]:
        while self._recent_events and now - self._recent_events[0][0] > self.event_retention_seconds:
            self._recent_events.popleft()
        return [event for _, event in self._recent_events]

    def _bus_silence_findings(self, now: float) -> list[dict[str, Any]]:
        if self._frame_count:
            return []
        age = now - self._started_monotonic
        if age <= self.no_frame_grace_seconds:
            return []
        return [
            _finding(
                source=self.source,
                subject="bus",
                code="bus_silence",
                severity="warning",
                message=f"{self.source} has not received any CAN frames for {age:.1f}s",
                confidence=0.86,
                ageSeconds=round(age, 3),
                suspectedCauses=["CAN interface down", "transceiver wiring fault", "vehicle/ECU not powered", "wrong bitrate"],
            )
        ]

    def _id_timing_findings(self, stats: CanIdStats, now: float) -> list[dict[str, Any]]:
        if stats.last_seen_monotonic is None or len(stats.intervals) < 5:
            return []
        median_interval = median(list(stats.intervals))
        if median_interval <= 0:
            return []
        age = now - stats.last_seen_monotonic
        stale_limit = max(self.min_stale_seconds, median_interval * self.stale_interval_multiplier)
        findings: list[dict[str, Any]] = []
        if age > stale_limit:
            findings.append(
                _finding(
                    source=self.source,
                    subject=stats.can_id,
                    code="can_id_dropout",
                    severity="warning",
                    message=f"{stats.can_id} stopped arriving; age {age:.2f}s exceeds learned limit {stale_limit:.2f}s",
                    confidence=clamp(age / (stale_limit * 2.0), 0.55, 0.98),
                    ageSeconds=round(age, 3),
                    learnedMedianIntervalSeconds=round(median_interval, 4),
                    staleLimitSeconds=round(stale_limit, 4),
                    suspectedCauses=["ECU stopped publishing", "wiring/transceiver issue", "bus load/dropout", "wrong CAN ID for this vehicle state"],
                )
            )
        interval_stddev = stddev(list(stats.intervals))
        if median_interval > 0 and len(stats.intervals) >= 10 and interval_stddev / median_interval > self.jitter_ratio_threshold:
            findings.append(
                _finding(
                    source=self.source,
                    subject=stats.can_id,
                    code="frame_rate_jitter",
                    severity="info",
                    message=f"{stats.can_id} frame timing is highly irregular",
                    confidence=0.55,
                    learnedMedianIntervalSeconds=round(median_interval, 4),
                    intervalStddevSeconds=round(interval_stddev, 4),
                    suspectedCauses=["variable-rate ECU message", "bus congestion", "logger/interface scheduling jitter"],
                )
            )
        return findings

    def _payload_stuck_findings(self, stats: CanIdStats, now: float) -> list[dict[str, Any]]:
        if not stats.decoded_signals or stats.same_data_since_monotonic is None:
            return []
        if not (stats.decoded_signals & DYNAMIC_SIGNALS):
            return []
        age = now - stats.same_data_since_monotonic
        if stats.same_data_count < self.stuck_min_samples or age < self.stuck_window_seconds:
            return []
        return [
            _finding(
                source=self.source,
                subject=stats.can_id,
                code="payload_stuck",
                severity="warning",
                message=f"{stats.can_id} payload has repeated unchanged for {age:.1f}s",
                confidence=0.68,
                ageSeconds=round(age, 3),
                repeatedFrames=stats.same_data_count,
                decodedSignals=sorted(stats.decoded_signals),
                suspectedCauses=["sensor stuck", "ECU fallback value", "decoder uses wrong field", "CAN gateway frozen"],
            )
        ]

    def _signal_stuck_findings(self, stats: DecodedSignalStats, now: float) -> list[dict[str, Any]]:
        if stats.name not in DYNAMIC_SIGNALS or len(stats.values) < self.stuck_min_samples:
            return []
        recent = [(timestamp, value) for timestamp, value in stats.values if now - timestamp <= self.stuck_window_seconds]
        if len(recent) < self.stuck_min_samples:
            return []
        values = [value for _, value in recent]
        if value_range(values) > _stuck_epsilon(stats.name):
            return []
        age = recent[-1][0] - recent[0][0]
        return [
            _finding(
                source=self.source,
                subject=stats.name,
                code="decoded_signal_stuck",
                severity="warning",
                message=f"{stats.name} decoded value is stuck at {values[-1]:.2f} for {age:.1f}s",
                confidence=0.62,
                value=values[-1],
                ageSeconds=round(age, 3),
                suspectedCauses=["sensor stuck", "decoder scale/field wrong", "vehicle not in expected test state", "ECU fallback value"],
            )
        ]

    def _id_summary(self, stats: CanIdStats, now: float) -> dict[str, Any]:
        median_interval = median(list(stats.intervals)) if stats.intervals else None
        return {
            "canId": stats.can_id,
            "frames": stats.frame_count,
            "ageSeconds": None if stats.last_seen_monotonic is None else round(now - stats.last_seen_monotonic, 3),
            "learnedHz": None if not median_interval else round(1.0 / median_interval, 3),
            "dlcCounts": {str(length): count for length, count in sorted(stats.dlc_counts.items())},
            "decodedSignals": sorted(stats.decoded_signals),
        }


def _finding(
    *,
    source: str,
    subject: str,
    code: str,
    severity: str,
    message: str,
    confidence: float,
    **details: Any,
) -> dict[str, Any]:
    return make_diagnostic_finding(
        source=source,
        subject=subject,
        code=code,
        severity=severity,
        message=message,
        confidence=confidence,
        **details,
    )


def _stuck_epsilon(signal_name: str) -> float:
    if signal_name == "rpm":
        return 5.0
    if signal_name == "speedKph":
        return 0.25
    return 0.0
