from __future__ import annotations

from typing import Any

from .values import number_or_none


def operating_state(signals: dict[str, Any]) -> str:
    speed = number_or_none(signals.get("speedKph"))
    rpm = number_or_none(signals.get("rpm"))
    if speed is not None and speed <= 3.0:
        if rpm is None:
            return "stationary"
        if rpm < 450.0:
            return "engine_off_stationary"
        if rpm <= 1300.0:
            return "idle_stationary"
        return "rev_stationary"
    if speed is not None:
        if speed < 35.0:
            return "low_speed_drive"
        if speed < 90.0:
            return "road_speed_drive"
        return "highway_speed_drive"
    if rpm is not None:
        if rpm <= 1300.0:
            return "rpm_low_no_speed"
        return "rpm_high_no_speed"
    return "unknown_context"


def state_rules_description() -> dict[str, str]:
    return {
        "engine_off_stationary": "speedKph <= 3 and rpm < 450",
        "idle_stationary": "speedKph <= 3 and 450 <= rpm <= 1300",
        "rev_stationary": "speedKph <= 3 and rpm > 1300",
        "low_speed_drive": "3 < speedKph < 35",
        "road_speed_drive": "35 <= speedKph < 90",
        "highway_speed_drive": "speedKph >= 90",
        "unknown_context": "speedKph and rpm are unavailable",
    }
