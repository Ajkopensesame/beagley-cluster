from __future__ import annotations

import math
from typing import Any


def number_or_none(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(numeric):
        return None
    return numeric


def numeric_signals(signals: dict[str, Any]) -> dict[str, float]:
    numeric: dict[str, float] = {}
    for key, value in signals.items():
        number = number_or_none(value)
        if number is not None:
            numeric[str(key)] = number
    return numeric


def rates(samples: list[tuple[float, float]], *, min_dt: float = 0.02) -> list[float]:
    result: list[float] = []
    for (previous_t, previous_v), (current_t, current_v) in zip(samples[:-1], samples[1:]):
        dt = current_t - previous_t
        if dt > min_dt:
            result.append((current_v - previous_v) / dt)
    return result


def sign_changes(values: list[float]) -> int:
    changes = 0
    previous_sign = 0
    for value in values:
        sign = 1 if value > 0 else -1 if value < 0 else 0
        if sign and previous_sign and sign != previous_sign:
            changes += 1
        if sign:
            previous_sign = sign
    return changes
