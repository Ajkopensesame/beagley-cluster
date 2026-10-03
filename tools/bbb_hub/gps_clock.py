#!/usr/bin/env python3
"""Set the BBB system clock from GPS time, using the vehicle hub's WebSocket output.

The BeagleBone Black has no battery RTC and no internet, so after every boot its clock is wrong. The hub
already owns the GPS serial port (it cannot be shared with gpsd), so this helper connects to the hub,
reads `vehicle_state` frames and uses `gps.utcMs` / `gps.utcValid` (RMC-derived UTC, see gps_nmea.py).

Rules (all enforced in the pure function `evaluate_frame`):
  * a frame only counts when gps.utcValid is true, gps.fixValid is true and satellites >= 4;
  * N=5 consecutive counting frames (that also advance consistently with the monotonic clock) are
    required before acting;
  * GPS dates before 2026-01-01 or after 2040-01-01 are rejected (week rollover / garbage);
  * the clock is stepped only if |GPS - system| > GPS_CLOCK_STEP_THRESHOLD_S (default 1.0 s);
  * after the first successful check, it re-checks at most every GPS_CLOCK_RECHECK_S (default 600 s);
  * the helper never exits on errors (reconnects forever with backoff) except in --once mode.

Environment:
  GPS_CLOCK_HUB_URL             default ws://127.0.0.1:8765
  GPS_CLOCK_STEP_THRESHOLD_S    default 1.0
  GPS_CLOCK_RECHECK_S           default 600
  GPS_CLOCK_DRY_RUN=1           log the would-be step, never call clock_settime

Needs CAP_SYS_TIME to actually set the clock (the systemd unit grants exactly that, no root).

CLI diagnostics:   gps_clock.py --once [--dry-run] [--timeout SECONDS]
  exit 0  clock already within threshold, or stepped successfully
  exit 10 clock is off by more than the threshold and was NOT changed (--dry-run)
  exit 2  no usable GPS time before the timeout (no fix, GGA-only GPS, out-of-range date, ...)
  exit 3  hub unreachable until the timeout, or clock_settime failed
"""
from __future__ import annotations

import argparse
import dataclasses
import asyncio
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable, Optional

try:
    import websockets
except ImportError:  # pragma: no cover - the board has python3-websockets for the hub itself
    websockets = None

DEFAULT_HUB_URL = "ws://127.0.0.1:8765"
DEFAULT_STEP_THRESHOLD_S = 1.0
DEFAULT_RECHECK_S = 600.0
REQUIRED_CONSECUTIVE_FRAMES = 5
MIN_SATELLITES = 4
# Between two consecutive counting frames, GPS UTC must advance like the monotonic clock (+-this).
MAX_FRAME_INCONSISTENCY_S = 1.0
# After a failed clock_settime, wait before trying again (avoid log spam).
SET_RETRY_COOLDOWN_S = 30.0
MIN_VALID_EPOCH = datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp()
MAX_VALID_EPOCH = datetime(2040, 1, 1, tzinfo=timezone.utc).timestamp()

EXIT_OK = 0
EXIT_WOULD_STEP = 10
EXIT_NO_GPS = 2
EXIT_ERROR = 3


def log(message: str) -> None:
    print(f"[gps_clock] {message}", flush=True)


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        return default
    return value if value == value and value >= 0.0 else default  # reject NaN / negatives


@dataclass(frozen=True)
class Config:
    hub_url: str = DEFAULT_HUB_URL
    step_threshold_s: float = DEFAULT_STEP_THRESHOLD_S
    recheck_s: float = DEFAULT_RECHECK_S
    dry_run: bool = False
    required_frames: int = REQUIRED_CONSECUTIVE_FRAMES
    min_satellites: int = MIN_SATELLITES

    @staticmethod
    def from_env() -> "Config":
        return Config(
            hub_url=os.getenv("GPS_CLOCK_HUB_URL", "").strip() or DEFAULT_HUB_URL,
            step_threshold_s=_env_float("GPS_CLOCK_STEP_THRESHOLD_S", DEFAULT_STEP_THRESHOLD_S),
            recheck_s=_env_float("GPS_CLOCK_RECHECK_S", DEFAULT_RECHECK_S),
            dry_run=os.getenv("GPS_CLOCK_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"},
        )


@dataclass(frozen=True)
class Tracker:
    """State carried between frames (immutable; evaluate_frame returns the next one)."""

    streak: int = 0
    last_utc_s: Optional[float] = None
    last_mono: Optional[float] = None
    # Monotonic time of the last completed check (step or within-threshold). None = never synced.
    last_check_mono: Optional[float] = None
    # Monotonic time before which a failed set must not be retried.
    retry_after_mono: Optional[float] = None


@dataclass(frozen=True)
class Decision:
    action: str  # "none" | "step" | "within"
    reason: str
    offset_s: Optional[float] = None
    target_utc_s: Optional[float] = None


def extract_utc_s(frame: Any, min_satellites: int = MIN_SATELLITES) -> tuple[Optional[float], str]:
    """GPS UTC (epoch seconds) from a vehicle_state frame, or (None, reason) if it must not be used."""
    if not isinstance(frame, dict):
        return None, "not an object"
    gps = frame.get("gps")
    if not isinstance(gps, dict):
        return None, "no gps block"
    if gps.get("utcValid") is not True:
        return None, "utcValid is not true"
    if gps.get("fixValid") is not True:
        return None, "no valid fix"
    sats = gps.get("satellites")
    if isinstance(sats, bool) or not isinstance(sats, (int, float)) or sats < min_satellites:
        return None, f"satellites < {min_satellites}"
    utc_ms = gps.get("utcMs")
    if isinstance(utc_ms, bool) or not isinstance(utc_ms, (int, float)) or utc_ms != utc_ms:
        return None, "utcMs missing"
    utc_s = float(utc_ms) / 1000.0
    if not (MIN_VALID_EPOCH <= utc_s < MAX_VALID_EPOCH):
        return None, "GPS date outside 2026-01-01..2040-01-01"
    return utc_s, "ok"


def evaluate_frame(
    tracker: Tracker,
    frame: Any,
    wall_now: float,
    mono_now: float,
    config: Config,
) -> tuple[Tracker, Decision]:
    """Pure decision step: no I/O, no clock reads. Returns the next tracker and what to do."""
    # Rate limit: after a completed check, ignore frames until the recheck interval has passed.
    if tracker.last_check_mono is not None and mono_now - tracker.last_check_mono < config.recheck_s:
        return Tracker(last_check_mono=tracker.last_check_mono, retry_after_mono=tracker.retry_after_mono), Decision(
            "none", "waiting for recheck interval"
        )
    if tracker.retry_after_mono is not None and mono_now < tracker.retry_after_mono:
        return Tracker(last_check_mono=tracker.last_check_mono, retry_after_mono=tracker.retry_after_mono), Decision(
            "none", "waiting after failed set"
        )

    utc_s, reason = extract_utc_s(frame, config.min_satellites)
    if utc_s is None:
        return replace_streak(tracker, 0), Decision("none", reason)

    streak = tracker.streak + 1
    if tracker.last_utc_s is not None and tracker.last_mono is not None and tracker.streak > 0:
        gps_delta = utc_s - tracker.last_utc_s
        mono_delta = mono_now - tracker.last_mono
        if abs(gps_delta - mono_delta) > MAX_FRAME_INCONSISTENCY_S:
            # GPS time jumped relative to our own steady clock: start counting again from this frame.
            streak = 1
    nxt = Tracker(
        streak=streak,
        last_utc_s=utc_s,
        last_mono=mono_now,
        last_check_mono=tracker.last_check_mono,
        retry_after_mono=tracker.retry_after_mono,
    )
    if streak < config.required_frames:
        return nxt, Decision("none", f"{streak}/{config.required_frames} consecutive valid frames")

    offset = utc_s - wall_now
    if abs(offset) > config.step_threshold_s:
        return nxt, Decision("step", "clock off", offset_s=offset, target_utc_s=utc_s)
    return nxt, Decision("within", "clock within threshold", offset_s=offset, target_utc_s=utc_s)


def replace_streak(tracker: Tracker, streak: int) -> Tracker:
    return Tracker(
        streak=streak,
        last_utc_s=None if streak == 0 else tracker.last_utc_s,
        last_mono=None if streak == 0 else tracker.last_mono,
        last_check_mono=tracker.last_check_mono,
        retry_after_mono=tracker.retry_after_mono,
    )


def _iso(epoch_s: float) -> str:
    return datetime.fromtimestamp(epoch_s, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def real_clock_setter(epoch_s: float) -> None:
    time.clock_settime(time.CLOCK_REALTIME, epoch_s)


class ClockDiscipline:
    """Stateful wrapper: feeds frames through evaluate_frame and performs the (injected) clock set."""

    def __init__(
        self,
        config: Config,
        *,
        setter: Callable[[float], None] = real_clock_setter,
        wall_clock: Callable[[], float] = time.time,
        monotonic: Callable[[], float] = time.monotonic,
        emit: Callable[[str], None] = log,
    ) -> None:
        self.config = config
        self._setter = setter
        self._wall = wall_clock
        self._mono = monotonic
        self._emit = emit
        self.tracker = Tracker()
        self.steps = 0
        self.last_decision: Optional[Decision] = None
        self.last_error: Optional[str] = None

    def handle_frame(self, frame: Any) -> Decision:
        wall_now = self._wall()
        mono_now = self._mono()
        self.tracker, decision = evaluate_frame(self.tracker, frame, wall_now, mono_now, self.config)
        if decision.action == "step":
            decision = self._do_step(decision, mono_now)
        elif decision.action == "within":
            self._emit(
                f"clock already within {self.config.step_threshold_s:g} s of GPS "
                f"(offset {decision.offset_s:+.3f} s); no step"
            )
            self.tracker = Tracker(last_check_mono=mono_now)
        self.last_decision = decision
        return decision

    def _do_step(self, decision: Decision, mono_now: float) -> Decision:
        assert decision.offset_s is not None and decision.target_utc_s is not None
        # Re-read the wall clock and advance the target by the time spent deciding (microseconds, but exact).
        target = decision.target_utc_s + (self._mono() - mono_now)
        iso = _iso(target)
        if self.config.dry_run:
            self._emit(f"DRY RUN would step clock by {decision.offset_s:+.3f} s to {iso}")
            self.tracker = Tracker(last_check_mono=mono_now)
            return decision
        try:
            self._setter(target)
        except Exception as exc:  # noqa: BLE001 - must never exit; typically PermissionError without CAP_SYS_TIME
            self.last_error = f"{type(exc).__name__}: {exc}"
            self._emit(f"ERROR could not set clock ({self.last_error}); will retry in {SET_RETRY_COOLDOWN_S:g} s")
            self.tracker = Tracker(last_check_mono=self.tracker.last_check_mono, retry_after_mono=mono_now + SET_RETRY_COOLDOWN_S)
            return Decision("error", self.last_error, decision.offset_s, decision.target_utc_s)
        self.steps += 1
        self.last_error = None
        self._emit(f"stepped clock by {decision.offset_s:+.3f} s to {iso}")
        self.tracker = Tracker(last_check_mono=self._mono())
        return decision


async def run_forever(config: Config, discipline: Optional[ClockDiscipline] = None) -> None:
    discipline = discipline or ClockDiscipline(config)
    backoff = 1.0
    last_error_logged = ""
    while True:
        try:
            async with websockets.connect(config.hub_url, open_timeout=10, ping_interval=20, ping_timeout=20) as ws:
                log(f"connected to {config.hub_url}")
                backoff = 1.0
                last_error_logged = ""
                while True:
                    raw = await asyncio.wait_for(ws.recv(), timeout=15)
                    try:
                        frame = json.loads(raw)
                    except (TypeError, ValueError):
                        continue
                    if isinstance(frame, dict) and frame.get("type") == "vehicle_state":
                        discipline.handle_frame(frame)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - never exit; reconnect forever
            message = f"{type(exc).__name__}: {exc}"
            if message != last_error_logged:  # one line per distinct error, not one per retry
                log(f"hub connection problem ({message}); retrying in {backoff:g} s")
                last_error_logged = message
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2.0, 30.0)


async def run_once(config: Config, timeout_s: float, discipline: Optional[ClockDiscipline] = None) -> int:
    """Diagnostic mode: act on the first decision, then return an exit code."""
    discipline = discipline or ClockDiscipline(config)
    deadline = time.monotonic() + timeout_s
    connected_once = False
    while time.monotonic() < deadline:
        try:
            async with websockets.connect(config.hub_url, open_timeout=5) as ws:
                connected_once = True
                while time.monotonic() < deadline:
                    remaining = max(0.1, deadline - time.monotonic())
                    raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
                    frame = json.loads(raw)
                    if not (isinstance(frame, dict) and frame.get("type") == "vehicle_state"):
                        continue
                    decision = discipline.handle_frame(frame)
                    if decision.action == "within":
                        return EXIT_OK
                    if decision.action == "step":
                        return EXIT_WOULD_STEP if config.dry_run else EXIT_OK
                    if decision.action == "error":
                        return EXIT_ERROR
        except asyncio.TimeoutError:
            break
        except Exception as exc:  # noqa: BLE001
            log(f"hub connection problem ({type(exc).__name__}: {exc})")
            await asyncio.sleep(0.5)
    if not connected_once:
        log(f"hub not reachable at {config.hub_url}")
        return EXIT_ERROR
    reason = discipline.last_decision.reason if discipline.last_decision else "no frames"
    log(f"no usable GPS time within {timeout_s:g} s ({reason})")
    return EXIT_NO_GPS


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Set the system clock from GPS time via the vehicle hub.")
    parser.add_argument("--once", action="store_true", help="act on the first decision and exit with a diagnostic code")
    parser.add_argument("--dry-run", action="store_true", help="never call clock_settime (same as GPS_CLOCK_DRY_RUN=1)")
    parser.add_argument("--timeout", type=float, default=30.0, help="--once: seconds to wait for usable GPS time")
    args = parser.parse_args(argv)

    if websockets is None:
        log("python3 websockets is not installed")
        return EXIT_ERROR
    config = Config.from_env()
    if args.dry_run:
        config = dataclasses.replace(config, dry_run=True)
    log(
        f"starting hub={config.hub_url} threshold={config.step_threshold_s:g}s "
        f"recheck={config.recheck_s:g}s dry_run={config.dry_run}"
    )
    if args.once:
        return asyncio.run(run_once(config, args.timeout))
    try:
        asyncio.run(run_forever(config))
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
