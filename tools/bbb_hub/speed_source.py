"""Speed source selection for the BBB vehicle hub (GPS first, pulse fallback).

``VEHICLE_SPEED_SOURCE``:
  gps_first  (default) GPS speed while there is a live fix; otherwise the pulse (speed_hz) speed
             from the serial/UNO input; otherwise 0.
  pulse_only           previous behaviour: the serial/UNO speed, GPS never overrides it.
  gps_only             GPS speed only; 0 when there is no live fix.

"pulse" means the speed the serial input produced (calibrated ``speed_hz`` or a pre-converted
``speed`` key). It is only a candidate while the serial source is fresh, so a stale UNO can never
leave a frozen speed. Hysteresis (gps_first) avoids flapping:
  * fall back from GPS only after the fix has been lost for ``lost_s`` seconds (the last GPS speed is
    held for at most that long, then replaced by the pulse speed or 0);
  * switch back to GPS only after the fix has been continuously valid for ``regain_s`` seconds
    (when no pulse speed exists there is nothing to flap against, so GPS is used at once).
RPM is not handled here (rpm source is still undecided).
"""
from __future__ import annotations

from typing import Any, Optional

MODES = ("gps_first", "pulse_only", "gps_only")
DEFAULT_MODE = "gps_first"


def parse_mode(value: Optional[str]) -> tuple[str, Optional[str]]:
    """Return (mode, warning-or-None); an unknown value falls back to the default."""
    text = (value or "").strip().lower()
    if not text:
        return DEFAULT_MODE, None
    if text in MODES:
        return text, None
    return DEFAULT_MODE, f"unknown VEHICLE_SPEED_SOURCE={value!r}; using {DEFAULT_MODE}"


class SpeedSourceSelector:
    def __init__(self, mode: str = DEFAULT_MODE, lost_s: float = 2.0, regain_s: float = 2.0) -> None:
        self.mode = mode if mode in MODES else DEFAULT_MODE
        self.lost_s = max(0.0, lost_s)
        self.regain_s = max(0.0, regain_s)
        self._active = "none"
        self._good_since: Optional[float] = None
        self._bad_since: Optional[float] = None
        self._last_gps_speed = 0.0

    def select(
        self,
        now: float,
        *,
        gps_valid: bool,
        gps_speed_kph: float,
        gps_age_s: Optional[float],
        pulse_speed_kph: Optional[float],
        pulse_age_s: Optional[float],
    ) -> tuple[Optional[float], dict[str, Any]]:
        """Pick the speed. Returns (speed_kph or None for 'no valid source', health dict)."""
        pulse_ok = pulse_speed_kph is not None
        if gps_valid:
            self._bad_since = None
            if self._good_since is None:
                self._good_since = now
            self._last_gps_speed = gps_speed_kph
        else:
            self._good_since = None
            if self._bad_since is None:
                self._bad_since = now

        active, reason = self._decide(now, gps_valid, pulse_ok)
        self._active = active
        if active == "gps":
            speed, age = (gps_speed_kph if gps_valid else self._last_gps_speed), gps_age_s
        elif active == "pulse":
            speed, age = pulse_speed_kph, pulse_age_s
        else:
            speed, age = None, None
        health = {
            "policy": self.mode,
            "active": active,
            "reason": reason,
            "gpsFix": bool(gps_valid),
            "ageS": None if age is None else round(age, 2),
        }
        return speed, health

    def _decide(self, now: float, gps_valid: bool, pulse_ok: bool) -> tuple[str, str]:
        if self.mode == "pulse_only":
            return ("pulse", "pulse_only") if pulse_ok else ("none", "pulse_only_no_pulse")
        if self.mode == "gps_only":
            return ("gps", "gps_only") if gps_valid else ("none", "gps_only_no_fix")
        # gps_first
        prev = self._active
        if prev == "gps":
            if gps_valid:
                return "gps", "gps_fix"
            if now - (self._bad_since if self._bad_since is not None else now) < self.lost_s:
                return "gps", "gps_lost_holding"
            return ("pulse", "gps_lost_pulse_fallback") if pulse_ok else ("none", "gps_lost_no_pulse")
        if prev == "pulse":
            if gps_valid and now - (self._good_since if self._good_since is not None else now) >= self.regain_s:
                return "gps", "gps_regained"
            if pulse_ok:
                return "pulse", "gps_regain_wait" if gps_valid else "no_gps_fix_pulse"
            if gps_valid:
                return "gps", "pulse_unavailable"
            return "none", "no_valid_source"
        # prev == "none": nothing to flap against, take GPS at once if valid
        if gps_valid:
            return "gps", "gps_fix"
        if pulse_ok:
            return "pulse", "no_gps_fix_pulse"
        return "none", "no_valid_source"
