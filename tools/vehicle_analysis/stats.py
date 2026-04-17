from __future__ import annotations

import math
from dataclasses import dataclass


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    midpoint = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[midpoint]
    return (ordered[midpoint - 1] + ordered[midpoint]) / 2.0


def percentile(ordered: list[float], fraction: float) -> float:
    if not ordered:
        return 0.0
    if len(ordered) == 1:
        return ordered[0]
    position = fraction * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    ratio = position - lower
    return ordered[lower] * (1.0 - ratio) + ordered[upper] * ratio


def stddev(values: list[float], *, sample: bool = False) -> float:
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    denominator = len(values) - 1 if sample else len(values)
    return math.sqrt(sum((value - mean) ** 2 for value in values) / denominator)


def value_range(values: list[float]) -> float:
    return max(values) - min(values) if values else 0.0


def summary_stats(values: list[float]) -> dict[str, float | int]:
    ordered = sorted(values)
    count = len(ordered)
    if count == 0:
        raise ValueError("summary_stats requires at least one value")
    mean = sum(ordered) / count
    variance = sum((value - mean) ** 2 for value in ordered) / count if count > 1 else 0.0
    return {
        "count": count,
        "mean": round(mean, 6),
        "stdev": round(math.sqrt(variance), 6),
        "min": round(ordered[0], 6),
        "p05": round(percentile(ordered, 0.05), 6),
        "median": round(percentile(ordered, 0.50), 6),
        "p95": round(percentile(ordered, 0.95), 6),
        "max": round(ordered[-1], 6),
    }


@dataclass
class RunningStats:
    count: int = 0
    mean: float = 0.0
    m2: float = 0.0
    minimum: float | None = None
    maximum: float | None = None
    first_seen: float | None = None
    last_seen: float | None = None

    @property
    def stddev(self) -> float:
        if self.count < 2:
            return 0.0
        return math.sqrt(max(0.0, self.m2 / (self.count - 1)))

    def update(self, value: float, timestamp: float) -> None:
        if self.count == 0:
            self.first_seen = timestamp
            self.minimum = value
            self.maximum = value
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        self.m2 += delta * (value - self.mean)
        self.minimum = value if self.minimum is None else min(self.minimum, value)
        self.maximum = value if self.maximum is None else max(self.maximum, value)
        self.last_seen = timestamp
