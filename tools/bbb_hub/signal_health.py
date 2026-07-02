from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass
from typing import Any

from tools.vehicle_analysis.findings import make_signal_fault
from tools.vehicle_analysis.stats import stddev
from tools.vehicle_analysis.values import number_or_none, rates, sign_changes


@dataclass(frozen=True)
class SignalRule:
    name: str
    minimum: float
    maximum: float
    unit: str
    max_rate_per_sec: float
    noisy_rate_stddev: float
    noisy_window_sec: float = 2.0
    minimum_samples: int = 8


DEFAULT_RULES = {
    "rpm": SignalRule("rpm", 0.0, 8500.0, "rpm", max_rate_per_sec=12000.0, noisy_rate_stddev=9000.0),
    "speedKph": SignalRule("speedKph", 0.0, 240.0, "kph", max_rate_per_sec=90.0, noisy_rate_stddev=75.0),
    "fuelPct": SignalRule("fuelPct", 0.0, 100.0, "pct", max_rate_per_sec=5.0, noisy_rate_stddev=4.0),
    "coolantC": SignalRule("coolantC", -40.0, 140.0, "C", max_rate_per_sec=10.0, noisy_rate_stddev=8.0),
    "mafGps": SignalRule("mafGps", 0.0, 500.0, "g/s", max_rate_per_sec=400.0, noisy_rate_stddev=250.0),
    "mapKpa": SignalRule("mapKpa", 5.0, 300.0, "kPa", max_rate_per_sec=500.0, noisy_rate_stddev=300.0),
    "throttlePct": SignalRule("throttlePct", 0.0, 100.0, "pct", max_rate_per_sec=500.0, noisy_rate_stddev=250.0),
    "intakeAirTempC": SignalRule("intakeAirTempC", -40.0, 120.0, "C", max_rate_per_sec=30.0, noisy_rate_stddev=20.0),
    "engineLoadPct": SignalRule("engineLoadPct", 0.0, 100.0, "pct", max_rate_per_sec=700.0, noisy_rate_stddev=350.0),
}


class SignalHealthMonitor:
    def __init__(
        self,
        *,
        enabled: bool = True,
        gps_speed_disagreement_kph: float = 18.0,
        history_limit: int = 80,
    ) -> None:
        self.enabled = enabled
        self.gps_speed_disagreement_kph = gps_speed_disagreement_kph
        self.history_limit = history_limit
        self._history: dict[str, deque[tuple[float, float]]] = {
            name: deque(maxlen=history_limit) for name in DEFAULT_RULES
        }

    def observe(self, state: dict[str, Any], now_monotonic: float | None = None) -> dict[str, Any]:
        now = time.monotonic() if now_monotonic is None else now_monotonic
        if not self.enabled:
            return {"enabled": False, "ok": True, "faults": []}

        faults: list[dict[str, Any]] = []
        for name, rule in DEFAULT_RULES.items():
            value = number_or_none(state.get(name))
            if value is None:
                continue
            faults.extend(self._observe_signal(rule, value, now))

        faults.extend(_source_stale_faults(state))
        faults.extend(_expert_can_faults(state))
        faults.extend(_vehicle_baseline_faults(state))
        faults.extend(self._gps_speed_disagreement_faults(state))

        return {
            "enabled": True,
            "ok": not faults,
            "faults": faults,
            "watching": sorted(name for name in DEFAULT_RULES if name in state),
        }

    def _observe_signal(self, rule: SignalRule, value: float, now: float) -> list[dict[str, Any]]:
        faults: list[dict[str, Any]] = []
        history = self._history[rule.name]
        if value < rule.minimum or value > rule.maximum:
            faults.append(
                _fault(
                    rule.name,
                    "out_of_range",
                    "error",
                    f"{rule.name}={value:.2f} {rule.unit} is outside expected range "
                    f"{rule.minimum:.0f}-{rule.maximum:.0f} {rule.unit}",
                    value=value,
                    minimum=rule.minimum,
                    maximum=rule.maximum,
                )
            )

        if history:
            previous_t, previous_v = history[-1]
            dt = now - previous_t
            if dt > 0.02:
                rate = abs(value - previous_v) / dt
                if rate > rule.max_rate_per_sec:
                    faults.append(
                        _fault(
                            rule.name,
                            "impossible_jump",
                            "warning",
                            f"{rule.name} changed too quickly: {rate:.1f} {rule.unit}/s",
                            value=value,
                            previous=previous_v,
                            ratePerSec=round(rate, 3),
                            limitPerSec=rule.max_rate_per_sec,
                        )
                    )

        history.append((now, value))
        recent = [(timestamp, sample) for timestamp, sample in history if now - timestamp <= rule.noisy_window_sec]
        if len(recent) >= rule.minimum_samples:
                rate_values = rates(recent)
                if len(rate_values) >= 4:
                    rate_stddev = stddev(rate_values)
                    change_count = sign_changes(rate_values)
                    if rate_stddev > rule.noisy_rate_stddev and change_count >= 4:
                        faults.append(
                            _fault(
                                rule.name,
                            "noisy_or_flapping",
                            "warning",
                                f"{rule.name} is oscillating rapidly across the last {rule.noisy_window_sec:.1f}s",
                                value=value,
                                rateStddev=round(rate_stddev, 3),
                                signChanges=change_count,
                            )
                        )
        return faults

    def _gps_speed_disagreement_faults(self, state: dict[str, Any]) -> list[dict[str, Any]]:
        speed = number_or_none(state.get("speedKph"))
        gps = state.get("gps")
        if speed is None or not isinstance(gps, dict) or not gps.get("fixValid", False):
            return []
        gps_speed = number_or_none(gps.get("speedKph"))
        if gps_speed is None or gps_speed < 8.0:
            return []
        delta = abs(speed - gps_speed)
        if delta <= self.gps_speed_disagreement_kph:
            return []
        return [
            _fault(
                "speedKph",
                "source_disagreement",
                "warning",
                f"CAN/top-level speed {speed:.1f} kph disagrees with GPS speed {gps_speed:.1f} kph",
                value=speed,
                gpsSpeedKph=gps_speed,
                deltaKph=round(delta, 3),
                limitKph=self.gps_speed_disagreement_kph,
            )
        ]


def _source_stale_faults(state: dict[str, Any]) -> list[dict[str, Any]]:
    health = state.get("_health")
    if not isinstance(health, dict):
        return []
    faults: list[dict[str, Any]] = []
    for source_key, signal_name in (("canLive", "can"), ("canReplay", "can"), ("serialVehicleInputs", "serial")):
        source = health.get(source_key)
        if not isinstance(source, dict) or not source.get("enabled"):
            continue
        if source.get("stale"):
            faults.append(
                _fault(
                    signal_name,
                    "source_stale",
                    "warning",
                    f"{source_key} input is stale",
                    source=source_key,
                    ageMs=source.get("ageMs"),
                )
            )
    return faults


def _expert_can_faults(state: dict[str, Any]) -> list[dict[str, Any]]:
    health = state.get("_health")
    if not isinstance(health, dict):
        return []
    faults: list[dict[str, Any]] = []
    for diagnostics_key in ("canLiveDiagnostics", "canReplayDiagnostics"):
        diagnostics = health.get(diagnostics_key)
        if not isinstance(diagnostics, dict) or not diagnostics.get("enabled"):
            continue
        for finding in diagnostics.get("findings", []):
            if not isinstance(finding, dict):
                continue
            if finding.get("severity") not in {"warning", "error"}:
                continue
            faults.append(
                _fault(
                    str(finding.get("subject", "can")),
                    str(finding.get("code", "can_diagnostic")),
                    str(finding.get("severity", "warning")),
                    str(finding.get("message", "CAN diagnostic finding")),
                    source=finding.get("source"),
                    confidence=finding.get("confidence"),
                    diagnostics=diagnostics_key,
                    **(finding.get("details", {}) if isinstance(finding.get("details"), dict) else {}),
                )
            )
    return faults


def _vehicle_baseline_faults(state: dict[str, Any]) -> list[dict[str, Any]]:
    health = state.get("_health")
    if not isinstance(health, dict):
        return []
    baseline = health.get("vehicleBaseline")
    if not isinstance(baseline, dict) or not baseline.get("enabled"):
        return []
    faults: list[dict[str, Any]] = []
    for finding in baseline.get("findings", []):
        if not isinstance(finding, dict):
            continue
        if finding.get("severity") not in {"warning", "error"}:
            continue
        faults.append(
            _fault(
                str(finding.get("signal", "vehicleBaseline")),
                str(finding.get("code", "vehicle_baseline_diagnostic")),
                str(finding.get("severity", "warning")),
                str(finding.get("message", "Vehicle baseline diagnostic finding")),
                source=finding.get("source"),
                model=finding.get("model"),
                confidence=finding.get("confidence"),
                **(finding.get("details", {}) if isinstance(finding.get("details"), dict) else {}),
            )
        )
    return faults


def _fault(signal: str, code: str, severity: str, message: str, **details: Any) -> dict[str, Any]:
    return make_signal_fault(signal, code, severity, message, **details)
