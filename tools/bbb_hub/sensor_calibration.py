"""Sensor calibration for the BBB serial vehicle-input overlay.

The UNO/serial module sends raw readings; this module turns them into the
engineering values the vehicle_state contract expects (``fuelPct``,
``coolantC``, ``speedKph``, ``rpm``) without changing the wire format.

Raw keys accepted on a serial line (case/hyphen insensitive):
  a0 / fuel_raw      ADC counts (0..1023) of the fuel sender
  a1 / coolant_raw   ADC counts (0..1023) of the coolant sender
  speed_hz           vehicle-speed pulse frequency (Hz)
  rpm_hz             tach pulse frequency (Hz)

Rules:
  * A signal with no calibration is simply not produced (hub keeps its 0.0 default).
  * A value the line already supplies pre-converted (fuel_pct, coolant_c, speed, rpm)
    always wins over a calibrated raw value.
  * Open/shorted sender (raw <= fault_low or >= fault_high) produces no value and is
    reported through ``sensorFaults``, never as a fake number.
Calibration JSON path: ``VEHICLE_SENSOR_CALIBRATION`` (default
``tools/bbb_hub/config/sensor_calibration.json``). Bad/missing file => no calibration.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

DEFAULT_PATH = str(Path(__file__).resolve().parent / "config" / "sensor_calibration.json")
DEFAULT_FAULT_LOW = 5
DEFAULT_FAULT_HIGH = 1018

RAW_ALIASES = {
    "a0": "a0", "fuel_raw": "a0", "fuel_adc": "a0",
    "a1": "a1", "coolant_raw": "a1", "coolant_adc": "a1",
    "speed_hz": "speed_hz", "speedhz": "speed_hz",
    "rpm_hz": "rpm_hz", "rpmhz": "rpm_hz",
}


def piecewise_linear(x: float, points: list[tuple[float, float]]) -> float:
    pts = sorted(points)
    if x <= pts[0][0]:
        return pts[0][1]
    if x >= pts[-1][0]:
        return pts[-1][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            return y1 if x1 == x0 else y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return pts[-1][1]


@dataclass
class TableMap:
    name: str
    points: list[tuple[float, float]] = field(default_factory=list)
    out_min: float = float("-inf")
    out_max: float = float("inf")
    fault_low: int = DEFAULT_FAULT_LOW
    fault_high: int = DEFAULT_FAULT_HIGH
    alpha: float = 0.25
    _smooth: Optional[float] = None

    @property
    def calibrated(self) -> bool:
        return len(self.points) >= 2

    def faulted(self, raw: float) -> bool:
        return raw <= self.fault_low or raw >= self.fault_high

    def convert(self, raw: float) -> Optional[float]:
        """Value, or None when uncalibrated or the sender is open/shorted."""
        if not self.calibrated:
            return None
        if self.faulted(raw):
            self._smooth = None  # restart smoothing after a fault
            return None
        self._smooth = raw if self._smooth is None else self.alpha * raw + (1.0 - self.alpha) * self._smooth
        v = piecewise_linear(self._smooth, self.points)
        return max(self.out_min, min(self.out_max, v))


@dataclass
class SensorCalibration:
    fuel: TableMap
    coolant: TableMap
    speed_kph_per_hz: float = 0.0
    speed_max: float = 300.0
    rpm_per_hz: float = 0.0
    rpm_max: float = 9000.0
    fuel_low_pct: float = 10.0

    @property
    def enabled(self) -> bool:
        return self.fuel.calibrated or self.coolant.calibrated or self.speed_kph_per_hz > 0 or self.rpm_per_hz > 0

    def summary(self) -> dict[str, bool]:
        return {
            "fuel": self.fuel.calibrated,
            "coolant": self.coolant.calibrated,
            "speed": self.speed_kph_per_hz > 0,
            "rpm": self.rpm_per_hz > 0,
        }

    def extract_raw(self, payload: dict[str, Any]) -> dict[str, float]:
        raw: dict[str, float] = {}
        for key, value in payload.items():
            if value is None:
                continue
            norm = str(key).strip().lower().replace("-", "_").replace(" ", "_")
            target = RAW_ALIASES.get(norm)
            if target is None:
                continue
            try:
                raw[target] = float(value)
            except (TypeError, ValueError):
                continue
        return raw

    def apply(self, raw: dict[str, float], overlay: dict[str, Any]) -> list[str]:
        """Add calibrated values to ``overlay`` (never overriding supplied ones).

        Returns the list of sensor-fault codes seen on this line.
        """
        faults: list[str] = []
        if "a0" in raw:
            if self.fuel.calibrated and self.fuel.faulted(raw["a0"]):
                faults.append("fuel_sender_fault")
            v = self.fuel.convert(raw["a0"])
            if v is not None:
                overlay.setdefault("fuelPct", round(v, 1))
                if overlay["fuelPct"] <= self.fuel_low_pct:
                    overlay.setdefault("warnings", {}).setdefault("fuel_low", True)
        if "a1" in raw:
            if self.coolant.calibrated and self.coolant.faulted(raw["a1"]):
                faults.append("coolant_sender_fault")
            v = self.coolant.convert(raw["a1"])
            if v is not None:
                overlay.setdefault("coolantC", round(v, 1))
        if "speed_hz" in raw and self.speed_kph_per_hz > 0 and raw["speed_hz"] >= 0:
            overlay.setdefault("speedKph", round(min(raw["speed_hz"] * self.speed_kph_per_hz, self.speed_max), 1))
        if "rpm_hz" in raw and self.rpm_per_hz > 0 and raw["rpm_hz"] >= 0:
            overlay.setdefault("rpm", round(min(raw["rpm_hz"] * self.rpm_per_hz, self.rpm_max), 0))
        return faults


def _table(name: str, cfg: dict[str, Any], out_min: float, out_max: float) -> TableMap:
    return TableMap(
        name=name,
        points=[(float(p[0]), float(p[1])) for p in (cfg.get("points") or [])],
        out_min=out_min,
        out_max=out_max,
        fault_low=int(cfg.get("fault_low", DEFAULT_FAULT_LOW)),
        fault_high=int(cfg.get("fault_high", DEFAULT_FAULT_HIGH)),
        alpha=float(cfg.get("smoothing_alpha", 0.25)),
    )


def calibration_from_config(data: dict[str, Any]) -> SensorCalibration:
    fuel = data.get("fuel") or {}
    speed = data.get("speed") or {}
    rpm = data.get("rpm") or {}
    return SensorCalibration(
        fuel=_table("fuelPct", fuel, 0.0, 100.0),
        coolant=_table("coolantC", data.get("coolant") or {}, -40.0, 150.0),
        speed_kph_per_hz=float(speed.get("kph_per_hz", 0.0)),
        speed_max=float(speed.get("max", 300.0)),
        rpm_per_hz=float(rpm.get("rpm_per_hz", 0.0)),
        rpm_max=float(rpm.get("max", 9000.0)),
        fuel_low_pct=float(fuel.get("low_pct", 10.0)),
    )


def load_sensor_calibration(path: Optional[str] = None) -> tuple[SensorCalibration, Optional[str]]:
    """Load calibration. Never raises; returns (calibration, error-or-None)."""
    path = path or os.getenv("VEHICLE_SENSOR_CALIBRATION", "").strip() or DEFAULT_PATH
    try:
        return calibration_from_config(json.loads(Path(path).read_text(encoding="utf-8"))), None
    except FileNotFoundError:
        return calibration_from_config({}), f"calibration file not found: {path}"
    except Exception as exc:
        return calibration_from_config({}), f"calibration file unusable ({path}): {exc}"
