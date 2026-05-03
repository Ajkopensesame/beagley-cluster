from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Iterable

from .context import operating_state
from .stats import stddev, value_range
from .values import number_or_none


EVENT_TYPES = (
    "key_on",
    "crank_start",
    "first_fire",
    "idle_settle",
    "stall",
    "throttle_tip_in",
    "shift",
    "decel",
    "fan_on",
)

ANOMALY_CLASSES = (
    "no_response",
    "delayed_response",
    "too_small_delta",
    "too_large_delta",
    "stuck_flat",
    "wrong_sequence",
    "wrong_correlation",
    "unexpected_noise",
    "persistent_offset",
    "cross_signal_inconsistency",
)

SIGNAL_TIERS = {
    0: "trusted_anchor",
    1: "verified_decoded_signal",
    2: "derived_virtual_anchor",
    3: "raw_can_candidate",
}


@dataclass(frozen=True)
class TransitionEvent:
    name: str
    timestamp: float
    index: int
    evidence: dict[str, Any]

    def to_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "timestamp": self.timestamp,
            "index": self.index,
            "evidence": dict(self.evidence),
        }


class EventSegmenter:
    """Detects reusable vehicle operating transitions from normalized state."""

    def __init__(self, *, min_event_gap_seconds: float = 0.75) -> None:
        self.min_event_gap_seconds = max(0.0, min_event_gap_seconds)
        self._previous_state: dict[str, Any] | None = None
        self._previous_timestamp: float | None = None
        self._previous_context: str | None = None
        self._index = -1
        self._last_event_at: dict[str, float] = {}

    def observe(self, state: dict[str, Any], timestamp: float) -> list[TransitionEvent]:
        self._index += 1
        events: list[TransitionEvent] = []
        current_context = operating_state(state)
        previous = self._previous_state
        previous_timestamp = self._previous_timestamp
        dt = timestamp - previous_timestamp if previous_timestamp is not None else None

        rpm = read_number(state, "rpm")
        speed = read_number(state, "speedKph")
        throttle = read_number(state, "throttlePct")
        previous_rpm = read_number(previous, "rpm") if previous is not None else None
        previous_speed = read_number(previous, "speedKph") if previous is not None else None
        previous_throttle = read_number(previous, "throttlePct") if previous is not None else None

        if previous is None and _looks_powered(state):
            self._append_event(events, "key_on", timestamp, {"rpm": rpm, "speedKph": speed})

        if previous is not None:
            if _speed_is_stationary(speed) and previous_rpm is not None and rpm is not None:
                if previous_rpm < 120.0 <= rpm < 550.0:
                    self._append_event(
                        events,
                        "crank_start",
                        timestamp,
                        {"previousRpm": previous_rpm, "rpm": rpm, "speedKph": speed},
                    )
                if previous_rpm < 450.0 <= rpm:
                    self._append_event(
                        events,
                        "first_fire",
                        timestamp,
                        {"previousRpm": previous_rpm, "rpm": rpm, "speedKph": speed},
                    )
                if previous_rpm >= 450.0 and rpm < 150.0:
                    self._append_event(
                        events,
                        "stall",
                        timestamp,
                        {"previousRpm": previous_rpm, "rpm": rpm, "speedKph": speed},
                    )

            if current_context == "idle_stationary" and self._previous_context != "idle_stationary":
                self._append_event(events, "idle_settle", timestamp, {"rpm": rpm, "speedKph": speed})

            if previous_throttle is not None and throttle is not None:
                throttle_delta = throttle - previous_throttle
                throttle_rate = throttle_delta / max(dt or 0.001, 0.001)
                if throttle_delta >= 8.0 and throttle_rate >= 5.0:
                    self._append_event(
                        events,
                        "throttle_tip_in",
                        timestamp,
                        {
                            "previousThrottlePct": previous_throttle,
                            "throttlePct": throttle,
                            "ratePctPerSec": round(throttle_rate, 3),
                        },
                    )

            if previous_speed is not None and speed is not None and dt is not None and dt > 0.02:
                speed_rate = (speed - previous_speed) / dt
                if speed_rate <= -6.0 and speed >= 3.0:
                    self._append_event(
                        events,
                        "decel",
                        timestamp,
                        {
                            "previousSpeedKph": previous_speed,
                            "speedKph": speed,
                            "rateKphPerSec": round(speed_rate, 3),
                        },
                    )

            previous_gear = _read_gear(previous)
            current_gear = _read_gear(state)
            if previous_gear and current_gear and previous_gear != current_gear:
                self._append_event(
                    events,
                    "shift",
                    timestamp,
                    {"previousGear": previous_gear, "gear": current_gear, "speedKph": speed, "rpm": rpm},
                )

            if not _fan_active(previous) and _fan_active(state):
                self._append_event(events, "fan_on", timestamp, {"coolantC": read_number(state, "coolantC")})

        self._previous_state = state
        self._previous_timestamp = timestamp
        self._previous_context = current_context
        return events

    def _append_event(
        self,
        events: list[TransitionEvent],
        name: str,
        timestamp: float,
        evidence: dict[str, Any],
    ) -> None:
        if name not in EVENT_TYPES:
            return
        previous = self._last_event_at.get(name)
        if previous is not None and timestamp - previous < self.min_event_gap_seconds:
            return
        self._last_event_at[name] = timestamp
        clean_evidence = {key: value for key, value in evidence.items() if value is not None}
        events.append(TransitionEvent(name=name, timestamp=timestamp, index=self._index, evidence=clean_evidence))


def read_path(state: dict[str, Any] | None, path: str) -> Any:
    if not isinstance(state, dict):
        return None
    if path in state:
        return state.get(path)
    current: Any = state
    for part in path.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return current


def read_number(state: dict[str, Any] | None, path: str) -> float | None:
    return number_or_none(read_path(state, path))


def transition_window_metrics(
    samples: Iterable[tuple[float, dict[str, Any]]],
    *,
    event_timestamp: float,
    target: str,
    reference_signals: Iterable[str] = (),
    before_seconds: float,
    after_seconds: float,
    response_threshold: float | None = None,
) -> dict[str, Any]:
    before_start = event_timestamp - max(0.0, before_seconds)
    after_end = event_timestamp + max(0.0, after_seconds)
    window = [
        (timestamp, state)
        for timestamp, state in samples
        if before_start <= timestamp <= after_end
    ]
    target_samples = [
        (timestamp, value)
        for timestamp, state in window
        if (value := read_number(state, target)) is not None
    ]
    before_values = [value for timestamp, value in target_samples if timestamp < event_timestamp]
    after_values = [value for timestamp, value in target_samples if timestamp >= event_timestamp]
    all_values = [value for _, value in target_samples]
    before_mean = _mean(before_values)
    after_mean = _mean(after_values)
    delta = None if before_mean is None or after_mean is None else after_mean - before_mean
    threshold = response_threshold
    if threshold is None:
        threshold = max(0.05, value_range(before_values) * 0.50, abs(delta or 0.0) * 0.20)

    correlations = {
        signal: _paired_correlation(window, target, signal, event_timestamp=event_timestamp)
        for signal in reference_signals
    }

    return {
        "signal": target,
        "beforeSeconds": float(before_seconds),
        "afterSeconds": float(after_seconds),
        "beforeCount": len(before_values),
        "afterCount": len(after_values),
        "totalCount": len(target_samples),
        "beforeMean": before_mean,
        "afterMean": after_mean,
        "delta": delta,
        "absDelta": abs(delta) if delta is not None else None,
        "beforeRange": value_range(before_values),
        "afterRange": value_range(after_values),
        "valueRange": value_range(all_values),
        "responseLagSeconds": _first_response_lag(target_samples, event_timestamp, before_mean, threshold),
        "slopeBefore": _slope([(t, v) for t, v in target_samples if t < event_timestamp]),
        "slopeAfter": _slope([(t, v) for t, v in target_samples if t >= event_timestamp]),
        "noiseScore": _noise_score(target_samples),
        "correlations": correlations,
    }


def _looks_powered(state: dict[str, Any]) -> bool:
    if read_number(state, "rpm") is not None:
        return True
    voltage = read_number(state, "controlModuleVoltage") or read_number(state, "batteryVoltage")
    return voltage is not None and voltage >= 9.0


def _speed_is_stationary(speed: float | None) -> bool:
    return speed is None or speed <= 3.0


def _read_gear(state: dict[str, Any] | None) -> str | None:
    value = read_path(state, "gear") or read_path(state, "drivetrain.gear") or read_path(state, "transmission.gear")
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _fan_active(state: dict[str, Any] | None) -> bool:
    for path in (
        "coolingFan",
        "fanOn",
        "radiatorFan",
        "cooling.fan",
        "cooling.fanOn",
        "fans.cooling",
    ):
        value = read_path(state, path)
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return value > 0
        if isinstance(value, str) and value.strip().lower() in {"1", "true", "on", "active"}:
            return True
    return False


def _mean(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def _first_response_lag(
    samples: list[tuple[float, float]],
    event_timestamp: float,
    before_mean: float | None,
    threshold: float,
) -> float | None:
    if before_mean is None:
        return None
    for timestamp, value in samples:
        if timestamp < event_timestamp:
            continue
        if abs(value - before_mean) >= threshold:
            return round(max(0.0, timestamp - event_timestamp), 3)
    return None


def _slope(samples: list[tuple[float, float]]) -> float | None:
    if len(samples) < 2:
        return None
    start_t, start_v = samples[0]
    end_t, end_v = samples[-1]
    dt = end_t - start_t
    if dt <= 0.02:
        return None
    return (end_v - start_v) / dt


def _noise_score(samples: list[tuple[float, float]]) -> float:
    if len(samples) < 3:
        return 0.0
    deltas = [
        current_v - previous_v
        for (_, previous_v), (_, current_v) in zip(samples[:-1], samples[1:])
    ]
    return stddev(deltas)


def _paired_correlation(
    samples: list[tuple[float, dict[str, Any]]],
    target: str,
    reference: str,
    *,
    event_timestamp: float,
) -> float | None:
    pairs: list[tuple[float, float]] = []
    for timestamp, state in samples:
        if timestamp < event_timestamp:
            continue
        target_value = read_number(state, target)
        reference_value = read_number(state, reference)
        if target_value is not None and reference_value is not None:
            pairs.append((target_value, reference_value))
    if len(pairs) < 3:
        return None
    xs = [pair[0] for pair in pairs]
    ys = [pair[1] for pair in pairs]
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in pairs)
    x_denom = math.sqrt(sum((x - x_mean) ** 2 for x in xs))
    y_denom = math.sqrt(sum((y - y_mean) ** 2 for y in ys))
    denominator = x_denom * y_denom
    if denominator <= 0.0:
        return None
    return max(-1.0, min(1.0, numerator / denominator))
