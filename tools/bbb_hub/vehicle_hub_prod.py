from __future__ import annotations

import asyncio
import contextlib
import json
import math
import os
import sys
import time
from pathlib import Path

import websockets

from gps_nmea import NmeaSerialGpsSource, build_hardware_gps_payload
import sd_notify


try:
    REPO_ROOT = Path(__file__).resolve().parents[2]
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))
    from tools.bbb_hub.input_adapters import (
        SerialVehicleInputSource,
        SocketCanSignalSource,
        merge_vehicle_overlay,
    )
    from tools.bbb_hub.diagnostic_status import build_diagnostic_status
    from tools.bbb_hub.fault_recorder import FaultRecorder
    from tools.bbb_hub.signal_health import SignalHealthMonitor
    from tools.bbb_hub.speed_source import SpeedSourceSelector, parse_mode as parse_speed_source_mode
    from tools.bbb_hub.transition_monitor import VehicleTransitionMonitor, default_transition_profiles
    from tools.bbb_hub.vehicle_baseline import VehicleBaselineMonitor, default_vehicle_baseline_profiles
    from tools.can_reverse_workbench.bbb_decoder import CanLogSignalReplay

    _CAN_DECODER_IMPORT_ERROR = None
except Exception as exc:
    build_diagnostic_status = None
    CanLogSignalReplay = None
    FaultRecorder = None
    SerialVehicleInputSource = None
    SignalHealthMonitor = None
    SpeedSourceSelector = None
    parse_speed_source_mode = None
    SocketCanSignalSource = None
    VehicleTransitionMonitor = None
    VehicleBaselineMonitor = None
    default_transition_profiles = None
    default_vehicle_baseline_profiles = None
    merge_vehicle_overlay = None
    _CAN_DECODER_IMPORT_ERROR = exc


WS_HOST = os.getenv("BBB_HUB_HOST", "0.0.0.0")
WS_PORT = int(os.getenv("BBB_HUB_PORT", "8765"))
GPS_DEVICE = os.getenv("BBB_GPS_DEVICE", "/dev/ttyS1")
GPS_BAUD = int(os.getenv("BBB_GPS_BAUD", "9600"))
GPS_READ_TIMEOUT_MS = int(os.getenv("BBB_GPS_READ_TIMEOUT_MS", "200"))
GPS_STALE_MS = int(os.getenv("BBB_GPS_STALE_MS", "2000"))
GPS_MIN_HEADING_SPEED_KPH = float(os.getenv("BBB_GPS_MIN_HEADING_SPEED_KPH", "7.0"))
GPS_SOURCE_POLICY = os.getenv("GPS_SOURCE_POLICY", "hardware_only").strip().lower()
CAN_SIGNAL_DICTIONARY = os.getenv("CAN_SIGNAL_DICTIONARY", "").strip()
CAN_RAW_LOG = os.getenv("CAN_RAW_LOG", "").strip()
CAN_REPLAY_REPEAT = os.getenv("CAN_REPLAY_REPEAT", "1").strip().lower() not in {"0", "false", "no"}
CAN_LIVE_INTERFACE = os.getenv("CAN_LIVE_INTERFACE", "").strip()
CAN_STALE_MS = int(os.getenv("CAN_STALE_MS", "1000"))
CAN_EXPERT_DIAGNOSTICS_ENABLED = os.getenv("CAN_EXPERT_DIAGNOSTICS_ENABLED", "1").strip().lower() not in {"0", "false", "no"}
VEHICLE_INPUT_SERIAL_DEVICE = os.getenv("VEHICLE_INPUT_SERIAL_DEVICE", "").strip()
VEHICLE_INPUT_SERIAL_BAUD = int(os.getenv("VEHICLE_INPUT_SERIAL_BAUD", "115200"))
VEHICLE_INPUT_STALE_MS = int(os.getenv("VEHICLE_INPUT_STALE_MS", "1000"))
# Speed source: gps_first (default) | pulse_only | gps_only. See tools/bbb_hub/speed_source.py.
VEHICLE_SPEED_SOURCE = os.getenv("VEHICLE_SPEED_SOURCE", "gps_first").strip().lower()
VEHICLE_SPEED_GPS_LOST_S = float(os.getenv("VEHICLE_SPEED_GPS_LOST_S", "2.0"))
VEHICLE_SPEED_GPS_REGAIN_S = float(os.getenv("VEHICLE_SPEED_GPS_REGAIN_S", "2.0"))
SIGNAL_HEALTH_ENABLED = os.getenv("SIGNAL_HEALTH_ENABLED", "1").strip().lower() not in {"0", "false", "no"}
GPS_SPEED_DISAGREEMENT_KPH = float(os.getenv("GPS_SPEED_DISAGREEMENT_KPH", "18.0"))
VEHICLE_BASELINE_ENABLED = os.getenv("VEHICLE_BASELINE_ENABLED", "1").strip().lower() not in {"0", "false", "no"}
VEHICLE_BASELINE_PATH = os.getenv(
    "VEHICLE_BASELINE_PATH",
    "/var/lib/beagley-cluster/baselines/vehicle_baseline.json",
).strip()
VEHICLE_BASELINE_SAVE_EVERY_SAMPLES = int(os.getenv("VEHICLE_BASELINE_SAVE_EVERY_SAMPLES", "25"))
VEHICLE_BASELINE_MIN_SAVE_INTERVAL_SECONDS = float(os.getenv("VEHICLE_BASELINE_MIN_SAVE_INTERVAL_SECONDS", "30.0"))
TRANSITION_MONITOR_ENABLED = os.getenv("TRANSITION_MONITOR_ENABLED", "1").strip().lower() not in {"0", "false", "no"}
TRANSITION_MONITOR_LEARN_ENABLED = os.getenv("TRANSITION_MONITOR_LEARN_ENABLED", "1").strip().lower() not in {"0", "false", "no"}
VEHICLE_TRANSITION_BASELINE_PATH = os.getenv(
    "VEHICLE_TRANSITION_BASELINE_PATH",
    "/var/lib/beagley-cluster/baselines/vehicle_transition_baseline.json",
).strip()
VEHICLE_TRANSITION_BASELINE_SAVE_EVERY_WINDOWS = int(os.getenv("VEHICLE_TRANSITION_BASELINE_SAVE_EVERY_WINDOWS", "5"))
VEHICLE_TRANSITION_BASELINE_MIN_SAVE_INTERVAL_SECONDS = float(
    os.getenv("VEHICLE_TRANSITION_BASELINE_MIN_SAVE_INTERVAL_SECONDS", "30.0")
)
FAULT_RECORDER_ENABLED = os.getenv("FAULT_RECORDER_ENABLED", "1").strip().lower() not in {"0", "false", "no"}
FAULT_RECORDER_DIR = os.getenv("FAULT_RECORDER_DIR", "/var/log/beagley-cluster/faults").strip()
FAULT_RECORDER_BUFFER_SECONDS = float(os.getenv("FAULT_RECORDER_BUFFER_SECONDS", "20.0"))
FAULT_RECORDER_MAX_BUFFER_FRAMES = int(os.getenv("FAULT_RECORDER_MAX_BUFFER_FRAMES", "300"))
FAULT_RECORDER_MIN_INTERVAL_SECONDS = float(os.getenv("FAULT_RECORDER_MIN_INTERVAL_SECONDS", "10.0"))
FAULT_RECORDER_MAX_EVENT_FILES = int(os.getenv("FAULT_RECORDER_MAX_EVENT_FILES", "500"))
FAULT_RECORDER_MAX_TOTAL_BYTES = int(os.getenv("FAULT_RECORDER_MAX_TOTAL_BYTES", str(64 * 1024 * 1024)))
DIAGNOSTIC_MODE = os.getenv("DIAGNOSTIC_MODE", "normal").strip().lower()
DIAGNOSTIC_STACK_STRICT = os.getenv("DIAGNOSTIC_STACK_STRICT", "0").strip().lower() not in {
    "0",
    "false",
    "off",
    "no",
}
VEHICLE_BENCH_SIM_ENABLED = os.getenv("BBB_VEHICLE_BENCH_SIM", "0").strip().lower() not in {
    "0",
    "false",
    "off",
    "no",
}
BENCH_PROFILE_ALIASES = {
    "busy": "busy-demo",
    "busy_demo": "busy-demo",
    "demo": "busy-demo",
    "park": "parked",
    "stationary": "parked",
    "steady": "cruise",
}
VALID_BENCH_PROFILES = {"parked", "cruise", "busy-demo"}
REQUESTED_BENCH_PROFILE = os.getenv("BBB_VEHICLE_BENCH_PROFILE", "busy-demo").strip().lower()
BENCH_PROFILE = BENCH_PROFILE_ALIASES.get(REQUESTED_BENCH_PROFILE, REQUESTED_BENCH_PROFILE)
if BENCH_PROFILE not in VALID_BENCH_PROFILES:
    print(f"[bbb_hub] unknown BBB_VEHICLE_BENCH_PROFILE={REQUESTED_BENCH_PROFILE!r}; using busy-demo")
    BENCH_PROFILE = "busy-demo"
BENCH_CRUISE_SPEED_KPH = float(os.getenv("BBB_BENCH_CRUISE_SPEED_KPH", "72.0"))
BENCH_CRUISE_RPM = float(os.getenv("BBB_BENCH_CRUISE_RPM", "2250.0"))
BENCH_CRUISE_ROUTE_RADIUS_M = float(os.getenv("BBB_BENCH_CRUISE_ROUTE_RADIUS_M", "420.0"))
BENCH_SIM_FALLBACK_LAT = float(os.getenv("BBB_BENCH_SIM_BASE_LAT", "-27.4698"))
BENCH_SIM_FALLBACK_LNG = float(os.getenv("BBB_BENCH_SIM_BASE_LNG", "153.0251"))

VIC_SEQUENCE = [
    {"warning": "brake"},
    {"warning": "charge"},
    {"warning": "check_engine"},
    {"warning": "at"},
    {"warning": "fuel_low"},
    {"warning": "oil"},
    {"warning": "door"},
    {"drivetrain_mode": "2wd", "transfer_lock": False},
    {"drivetrain_mode": "4wd", "transfer_lock": False},
    {"drivetrain_mode": "4wd", "transfer_lock": True},
]
VIC_HOLD_S = 2.0
FRAME_PERIOD_SEC = 0.1


class VehicleHub:
    def __init__(self) -> None:
        self.clients: set[websockets.WebSocketServerProtocol] = set()
        self._started_at = time.monotonic()  # monotonic: bench waveform must not jump when bbb-gps-clock steps the wall clock
        self.last_loop_monotonic = time.monotonic()
        self._gps = NmeaSerialGpsSource(
            device=GPS_DEVICE,
            baud=GPS_BAUD,
            read_timeout_ms=GPS_READ_TIMEOUT_MS,
            stale_ms=GPS_STALE_MS,
            min_heading_speed_kph=GPS_MIN_HEADING_SPEED_KPH,
        )
        self._can_replay = self._build_can_replay()
        self._can_live = self._build_can_live()
        self._serial_inputs = self._build_serial_inputs()
        self._serial_speed_kph: float | None = None
        self._serial_speed_age_s: float | None = None
        self._can_speed_present = False
        self._speed_selector = self._build_speed_selector()
        self._signal_health = self._build_signal_health()
        self._vehicle_baseline = self._build_vehicle_baseline()
        self._transition_monitor = self._build_transition_monitor()
        self._fault_recorder = self._build_fault_recorder()
        self._diagnostic_stack_status = self._build_diagnostic_stack_status()

    def _build_diagnostic_stack_status(self) -> dict[str, object]:
        degraded = False
        reasons: list[str] = []
        if build_diagnostic_status is None:
            degraded = True
            reasons.append("diagnostic_status_unavailable")
        if SIGNAL_HEALTH_ENABLED and self._signal_health is None:
            degraded = True
            reasons.append("signal_health_unavailable")
        if VEHICLE_BASELINE_ENABLED and self._vehicle_baseline is None:
            degraded = True
            reasons.append("vehicle_baseline_unavailable")
        if TRANSITION_MONITOR_ENABLED and self._transition_monitor is None:
            degraded = True
            reasons.append("transition_monitor_unavailable")
        if FAULT_RECORDER_ENABLED and self._fault_recorder is None:
            degraded = True
            reasons.append("fault_recorder_unavailable")
        if _CAN_DECODER_IMPORT_ERROR is not None and (
            CAN_SIGNAL_DICTIONARY or CAN_RAW_LOG or CAN_LIVE_INTERFACE or VEHICLE_INPUT_SERIAL_DEVICE
        ):
            degraded = True
            reasons.append("vehicle_input_stack_unavailable")
        return {"degraded": degraded, "reasons": reasons}

    def _apply_diagnostic_stack_status(self, state: dict) -> None:
        health = state.setdefault("_health", {})
        if not isinstance(health, dict):
            health = {}
            state["_health"] = health
        health["diagnosticStackDegraded"] = bool(self._diagnostic_stack_status.get("degraded"))
        reasons = self._diagnostic_stack_status.get("reasons")
        if isinstance(reasons, list) and reasons:
            health["diagnosticStackReasons"] = list(reasons)
        elif "diagnosticStackReasons" in health:
            health.pop("diagnosticStackReasons", None)

    async def add_client(self, ws: websockets.WebSocketServerProtocol) -> None:
        self.clients.add(ws)
        print(f"[bbb_hub] client connected ({len(self.clients)} total)")

    async def remove_client(self, ws: websockets.WebSocketServerProtocol) -> None:
        self.clients.discard(ws)
        print(f"[bbb_hub] client disconnected ({len(self.clients)} total)")

    async def gps_loop(self) -> None:
        await self._gps.run()

    async def can_live_loop(self) -> None:
        if self._can_live is not None:
            await self._can_live.run()

    async def serial_input_loop(self) -> None:
        if self._serial_inputs is not None:
            await self._serial_inputs.run()

    def _build_empty_vehicle_state(self) -> dict:
        return {
            "type": "vehicle_state",
            "version": 1,
            "speedKph": 0.0,
            "rpm": 0.0,
            "fuelPct": 0.0,
            "coolantC": 0.0,
            "gear": "P",
            "overdrive": False,
            "drivetrain": {
                "mode": "2wd",
                "transfer_lock": False,
            },
            "indicators": {
                "left": False,
                "right": False,
                "high_beam": False,
            },
            "warnings": {
                "brake": False,
                "oil": False,
                "charge": False,
                "door": False,
                "check_engine": False,
                "at": False,
                "fuel_low": False,
            },
            "_health": {
                "stale": True,
                "vehicleSource": "none",
                "benchVehicleSim": False,
            },
        }

    def _build_base_bench_vehicle_state(self) -> dict:
        return {
            "type": "vehicle_state",
            "version": 1,
            "speedKph": 0.0,
            "rpm": 0.0,
            "fuelPct": 72.0,
            "coolantC": 84.0,
            "gear": "P",
            "overdrive": False,
            "drivetrain": {
                "mode": "2wd",
                "transfer_lock": False,
            },
            "indicators": {
                "left": False,
                "right": False,
                "high_beam": False,
            },
            "warnings": {
                "brake": False,
                "oil": False,
                "charge": False,
                "door": False,
                "check_engine": False,
                "at": False,
                "fuel_low": False,
            },
            "_health": {
                "stale": False,
                "vehicleSource": "bench_sim",
                "benchVehicleSim": True,
                "benchProfile": BENCH_PROFILE,
            },
        }

    def _build_parked_vehicle_state(self, t: float) -> dict:
        state = self._build_base_bench_vehicle_state()
        state.update({
            "rpm": 760.0 + 12.0 * math.sin(t * 0.18),
            "fuelPct": 74.0,
            "coolantC": 82.0 + 0.4 * math.sin(t * 0.035),
            "gear": "P",
        })
        return state

    def _build_cruise_vehicle_state(self, t: float) -> dict:
        state = self._build_base_bench_vehicle_state()
        speed = max(0.0, BENCH_CRUISE_SPEED_KPH)
        rpm = max(0.0, BENCH_CRUISE_RPM)
        state.update({
            "speedKph": speed,
            "rpm": rpm + 18.0 * math.sin(t * 0.16),
            "fuelPct": 68.0 + 0.8 * math.sin(t * 0.025),
            "coolantC": 86.0 + 0.5 * math.sin(t * 0.040),
            "gear": "D",
            "overdrive": True,
        })
        return state

    def _build_busy_demo_vehicle_state(self, t: float) -> dict:
        speed = max(0.0, min(130.0, 65.0 + 65.0 * math.sin(t * 0.22)))
        left = (t % 2.0) < 1.0
        right = ((t + 1.0) % 2.0) < 1.0
        high_beam = (t % 6.0) < 0.5
        gear_cycle = ["P", "R", "N", "D", "2", "1"]
        gear = gear_cycle[int(t / 5.0) % len(gear_cycle)]
        overdrive = gear == "D" and speed > 45.0 and ((t % 8.0) < 4.0)
        rpm_phase = 0.5 + 0.5 * math.sin(t * 0.62 - 1.0)
        rpm = 850.0 + (rpm_phase ** 1.18) * 6650.0 + 180.0 * math.sin(t * 2.4)
        rpm = max(0.0, min(7800.0, rpm))
        vic_state = VIC_SEQUENCE[int(t / VIC_HOLD_S) % len(VIC_SEQUENCE)]
        warning_key = vic_state.get("warning")
        fuel_phase = 0.5 + 0.5 * math.sin(t * 0.12 + math.pi / 2.0)
        fuel_pct = max(0.0, min(100.0, fuel_phase * 100.0))
        coolant_phase = 0.5 + 0.5 * math.sin(t * 0.10 - math.pi / 2.0)
        coolant_c = 40.0 + coolant_phase * 80.0
        drivetrain_mode = vic_state.get("drivetrain_mode", "2wd")
        transfer_lock = bool(vic_state.get("transfer_lock", False))

        return {
            "type": "vehicle_state",
            "version": 1,
            "speedKph": float(speed),
            "rpm": float(rpm),
            "fuelPct": fuel_pct,
            "coolantC": float(coolant_c),
            "gear": gear,
            "overdrive": bool(overdrive),
            "drivetrain": {
                "mode": drivetrain_mode,
                "transfer_lock": bool(transfer_lock),
            },
            "indicators": {
                "left": bool(left),
                "right": bool(right),
                "high_beam": bool(high_beam),
            },
            "warnings": {
                "brake": warning_key == "brake",
                "oil": warning_key == "oil",
                "charge": warning_key == "charge",
                "door": warning_key == "door",
                "check_engine": warning_key == "check_engine",
                "at": warning_key == "at",
                "fuel_low": warning_key == "fuel_low",
            },
            "_health": {
                "stale": False,
                "vehicleSource": "bench_sim",
                "benchVehicleSim": True,
                "benchProfile": BENCH_PROFILE,
            },
        }

    def _build_bench_vehicle_state(self, t: float) -> dict:
        if BENCH_PROFILE == "parked":
            return self._build_parked_vehicle_state(t)
        if BENCH_PROFILE == "cruise":
            return self._build_cruise_vehicle_state(t)
        return self._build_busy_demo_vehicle_state(t)

    def _build_cruise_gps_payload(self, t: float, hardware_gps: dict) -> dict:
        base_lat = hardware_gps.get("lat", BENCH_SIM_FALLBACK_LAT)
        base_lng = hardware_gps.get("lng", BENCH_SIM_FALLBACK_LNG)
        try:
            base_lat = float(base_lat)
            base_lng = float(base_lng)
        except (TypeError, ValueError):
            base_lat = BENCH_SIM_FALLBACK_LAT
            base_lng = BENCH_SIM_FALLBACK_LNG

        radius_m = max(25.0, BENCH_CRUISE_ROUTE_RADIUS_M)
        speed_mps = max(0.0, BENCH_CRUISE_SPEED_KPH) / 3.6
        phase = (t * speed_mps / radius_m) % (math.pi * 2.0)
        lat_m = math.sin(phase) * radius_m
        lng_m = math.cos(phase) * radius_m
        meters_per_lng_degree = max(1.0, 111111.0 * math.cos(math.radians(base_lat)))
        lat = base_lat + lat_m / 111111.0
        lng = base_lng + lng_m / meters_per_lng_degree
        bearing = (math.degrees(phase) + 90.0) % 360.0

        return {
            "lat": float(lat),
            "lng": float(lng),
            "bearing": float(bearing),
            "accuracyM": 3.0,
            "timestampMs": int(time.time() * 1000),
            "fixValid": True,
            "satellites": int(max(8, hardware_gps.get("satellites", 10) or 10)),
            "speedKph": float(max(0.0, BENCH_CRUISE_SPEED_KPH)),
            "headingReliable": True,
            # Simulated position must never discipline the system clock (see gps_clock.py).
            "utcMs": 0,
            "utcValid": False,
        }

    def _build_can_replay(self):
        if not CAN_RAW_LOG:
            return None
        if not CAN_SIGNAL_DICTIONARY or not CAN_RAW_LOG:
            print("[bbb_hub] CAN decoder disabled: set both CAN_SIGNAL_DICTIONARY and CAN_RAW_LOG")
            return None
        if CanLogSignalReplay is None:
            print(f"[bbb_hub] CAN decoder unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        try:
            replay = CanLogSignalReplay(
                CAN_SIGNAL_DICTIONARY,
                CAN_RAW_LOG,
                repeat=CAN_REPLAY_REPEAT,
                diagnostics_enabled=CAN_EXPERT_DIAGNOSTICS_ENABLED,
            )
            print(f"[bbb_hub] CAN decoder replay enabled: {CAN_RAW_LOG}")
            print(f"[bbb_hub] CAN signal dictionary: {CAN_SIGNAL_DICTIONARY}")
            return replay
        except Exception as exc:
            print(f"[bbb_hub] CAN decoder disabled: {exc}")
            return None

    def _build_can_live(self):
        if not CAN_LIVE_INTERFACE:
            return None
        if not CAN_SIGNAL_DICTIONARY:
            print("[bbb_hub] live CAN disabled: set CAN_SIGNAL_DICTIONARY with CAN_LIVE_INTERFACE")
            return None
        if SocketCanSignalSource is None:
            print(f"[bbb_hub] live CAN unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        try:
            source = SocketCanSignalSource(
                CAN_LIVE_INTERFACE,
                CAN_SIGNAL_DICTIONARY,
                stale_ms=CAN_STALE_MS,
                diagnostics_enabled=CAN_EXPERT_DIAGNOSTICS_ENABLED,
            )
            print(f"[bbb_hub] live CAN enabled on {CAN_LIVE_INTERFACE}")
            print(f"[bbb_hub] CAN signal dictionary: {CAN_SIGNAL_DICTIONARY}")
            return source
        except Exception as exc:
            print(f"[bbb_hub] live CAN disabled: {exc}")
            return None

    def _build_serial_inputs(self):
        if not VEHICLE_INPUT_SERIAL_DEVICE:
            return None
        if SerialVehicleInputSource is None:
            print(f"[bbb_hub] serial vehicle inputs unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        try:
            source = SerialVehicleInputSource(
                VEHICLE_INPUT_SERIAL_DEVICE,
                baud=VEHICLE_INPUT_SERIAL_BAUD,
                stale_ms=VEHICLE_INPUT_STALE_MS,
            )
            print(f"[bbb_hub] serial vehicle inputs enabled: {VEHICLE_INPUT_SERIAL_DEVICE} @ {VEHICLE_INPUT_SERIAL_BAUD}")
            return source
        except Exception as exc:
            print(f"[bbb_hub] serial vehicle inputs disabled: {exc}")
            return None

    def _build_speed_selector(self):
        if SpeedSourceSelector is None:
            print(f"[bbb_hub] speed source selector unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        mode, warning = parse_speed_source_mode(VEHICLE_SPEED_SOURCE)
        if warning:
            print(f"[bbb_hub] {warning}")
        print(
            f"[bbb_hub] speed source: {mode} "
            f"(gps lost {VEHICLE_SPEED_GPS_LOST_S}s, gps regain {VEHICLE_SPEED_GPS_REGAIN_S}s)"
        )
        return SpeedSourceSelector(mode, VEHICLE_SPEED_GPS_LOST_S, VEHICLE_SPEED_GPS_REGAIN_S)

    def _apply_speed_source(self, state: dict, sample, gps_health) -> None:
        """GPS-first speed with pulse (serial speed_hz) fallback; additive ``_health.speedSource``.

        CAN-supplied speed and the bench simulator are left untouched. RPM is not handled here.
        """
        if self._speed_selector is None:
            return
        can_speed = self._can_speed_present and self._serial_speed_kph is None  # serial overwrites CAN
        if VEHICLE_BENCH_SIM_ENABLED or can_speed:
            state["_health"]["speedSource"] = {
                "policy": self._speed_selector.mode,
                "active": "other",
                "reason": "bench_sim" if VEHICLE_BENCH_SIM_ENABLED else "can_speed",
                "gpsFix": bool(state["gps"].get("fixValid")),
                "ageS": None,
            }
            return
        gps_valid = bool(
            sample is not None and sample.fix_valid and not getattr(sample, "held", False) and not gps_health.stale
        )
        speed, info = self._speed_selector.select(
            time.monotonic(),
            gps_valid=gps_valid,
            gps_speed_kph=float(sample.speed_kph) if sample is not None else 0.0,
            gps_age_s=gps_health.age_ms / 1000.0 if gps_health.age_ms >= 0 else None,
            pulse_speed_kph=self._serial_speed_kph,
            pulse_age_s=self._serial_speed_age_s,
        )
        if self._speed_selector.mode != "pulse_only":
            state["speedKph"] = 0.0 if speed is None else round(float(speed), 1)
        state["_health"]["speedSource"] = info

    def _build_signal_health(self):
        if SignalHealthMonitor is None:
            print(f"[bbb_hub] signal health monitor unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        return SignalHealthMonitor(
            enabled=SIGNAL_HEALTH_ENABLED,
            gps_speed_disagreement_kph=GPS_SPEED_DISAGREEMENT_KPH,
        )

    def _build_vehicle_baseline(self):
        if VehicleBaselineMonitor is None or default_vehicle_baseline_profiles is None:
            print(f"[bbb_hub] vehicle baseline monitor unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        return VehicleBaselineMonitor(
            default_vehicle_baseline_profiles(),
            storage_path=VEHICLE_BASELINE_PATH,
            enabled=VEHICLE_BASELINE_ENABLED,
            save_every_samples=VEHICLE_BASELINE_SAVE_EVERY_SAMPLES,
            min_save_interval_seconds=VEHICLE_BASELINE_MIN_SAVE_INTERVAL_SECONDS,
        )

    def _build_transition_monitor(self):
        if VehicleTransitionMonitor is None or default_transition_profiles is None:
            print(f"[bbb_hub] transition monitor unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        return VehicleTransitionMonitor(
            default_transition_profiles(),
            storage_path=VEHICLE_TRANSITION_BASELINE_PATH,
            enabled=TRANSITION_MONITOR_ENABLED,
            learn_enabled=TRANSITION_MONITOR_LEARN_ENABLED,
            save_every_windows=VEHICLE_TRANSITION_BASELINE_SAVE_EVERY_WINDOWS,
            min_save_interval_seconds=VEHICLE_TRANSITION_BASELINE_MIN_SAVE_INTERVAL_SECONDS,
        )

    def _build_fault_recorder(self):
        if FaultRecorder is None:
            print(f"[bbb_hub] fault recorder unavailable: {_CAN_DECODER_IMPORT_ERROR}")
            return None
        return FaultRecorder(
            FAULT_RECORDER_DIR,
            enabled=FAULT_RECORDER_ENABLED,
            buffer_seconds=FAULT_RECORDER_BUFFER_SECONDS,
            max_buffer_frames=FAULT_RECORDER_MAX_BUFFER_FRAMES,
            min_interval_seconds=FAULT_RECORDER_MIN_INTERVAL_SECONDS,
            max_event_files=FAULT_RECORDER_MAX_EVENT_FILES,
            max_total_bytes=FAULT_RECORDER_MAX_TOTAL_BYTES,
        )

    def _apply_can_overlay(self, state: dict) -> None:
        decoded_signals = set()
        if self._can_replay is not None:
            health = self._can_replay.health()
            # Fail-safe: a stale source must not keep showing its last values as live.
            decoded = {} if health.get("stale", True) else self._can_replay.snapshot()
            merge_vehicle_overlay(state, decoded)
            decoded_signals.update(decoded)
            state["_health"]["canReplay"] = health
            state["_health"]["canReplayDiagnostics"] = self._can_replay.diagnostics()
            if decoded and not health.get("stale", True):
                state["_health"]["stale"] = False
                state["_health"]["vehicleSource"] = "can_replay"
        if self._can_live is not None:
            health = self._can_live.health()
            # Fail-safe: a stale source must not keep showing its last values as live.
            decoded = {} if health.get("stale", True) else self._can_live.snapshot()
            merge_vehicle_overlay(state, decoded)
            decoded_signals.update(decoded)
            state["_health"]["canLive"] = health
            state["_health"]["canLiveDiagnostics"] = self._can_live.diagnostics()
            if decoded and not health.get("stale", True):
                state["_health"]["stale"] = False
                state["_health"]["vehicleSource"] = "can_live"
        self._can_speed_present = "speedKph" in decoded_signals
        if decoded_signals:
            state["_health"]["canDecodedSignals"] = sorted(decoded_signals)
        elif (CAN_RAW_LOG or CAN_LIVE_INTERFACE) and self._can_replay is None and self._can_live is None:
            if CAN_SIGNAL_DICTIONARY or CAN_RAW_LOG or CAN_LIVE_INTERFACE:
                state["_health"]["canDecoder"] = {
                    "enabled": False,
                    "reason": "not configured or failed to initialize",
                }

    def _apply_serial_overlay(self, state: dict) -> None:
        self._serial_speed_kph = None
        self._serial_speed_age_s = None
        if self._serial_inputs is None:
            if VEHICLE_INPUT_SERIAL_DEVICE:
                state["_health"]["serialVehicleInputs"] = {
                    "enabled": False,
                    "reason": "not configured or failed to initialize",
                }
            return
        health = self._serial_inputs.health()
        # Fail-safe: a stale source (UNO unplugged/silent) must not keep showing its last values as live.
        overlay = {} if health.get("stale", True) else self._serial_inputs.snapshot()
        merge_vehicle_overlay(state, overlay)
        if "speedKph" in overlay:
            self._serial_speed_kph = float(overlay["speedKph"])
            age_ms = health.get("ageMs")
            self._serial_speed_age_s = None if age_ms is None else age_ms / 1000.0
        state["_health"]["serialVehicleInputs"] = health
        if overlay and not health.get("stale", True):
            state["_health"]["stale"] = False
            state["_health"]["vehicleSource"] = "serial"

    def _apply_fault_recording(self, state: dict) -> None:
        if self._fault_recorder is None:
            if FAULT_RECORDER_ENABLED:
                state["_health"]["faultRecorder"] = {
                    "enabled": False,
                    "reason": "failed to initialize",
                }
            return
        state["_health"]["faultRecorder"] = self._fault_recorder.observe(
            state,
            evidence=self._fault_evidence(),
        )

    def _apply_diagnostic_status(self, state: dict) -> None:
        if build_diagnostic_status is None:
            state["_diagnostic"] = {
                "version": 1,
                "mode": DIAGNOSTIC_MODE,
                "ok": False,
                "severity": "warning",
                "status": "limited",
                "summary": "DIAGNOSTIC STATUS UNAVAILABLE",
                "findingCount": 0,
                "activeFindings": [],
                "captureQuality": {},
            }
            return
        state["_diagnostic"] = build_diagnostic_status(state, mode=DIAGNOSTIC_MODE)

    def _apply_vehicle_baseline(self, state: dict) -> None:
        if self._vehicle_baseline is None:
            if VEHICLE_BASELINE_ENABLED:
                state["_health"]["vehicleBaseline"] = {
                    "enabled": False,
                    "ok": False,
                    "reason": "failed to initialize",
                }
            return
        state["_health"]["vehicleBaseline"] = self._vehicle_baseline.observe(state)

    def _apply_transition_monitor(self, state: dict) -> None:
        if self._transition_monitor is None:
            if TRANSITION_MONITOR_ENABLED:
                state["_health"]["transitionMonitor"] = {
                    "enabled": False,
                    "ok": False,
                    "reason": "failed to initialize",
                }
            return
        state["_health"]["transitionMonitor"] = self._transition_monitor.observe(state)

    def _fault_evidence(self) -> dict:
        evidence = {}
        if self._can_replay is not None:
            evidence["canReplayRecentFrames"] = self._can_replay.recent_frames()
            evidence["canReplayDiagnostics"] = self._can_replay.diagnostics()
        if self._can_live is not None:
            evidence["canLiveRecentFrames"] = self._can_live.recent_frames()
            evidence["canLiveDiagnostics"] = self._can_live.diagnostics()
        if self._serial_inputs is not None:
            evidence["serialVehicleInputsLatest"] = self._serial_inputs.snapshot()
        if self._vehicle_baseline is not None:
            evidence["vehicleBaseline"] = self._vehicle_baseline.snapshot()
        if self._transition_monitor is not None:
            evidence["transitionMonitor"] = self._transition_monitor.snapshot()
        return evidence

    async def next_state(self) -> dict:
        t = time.monotonic() - self._started_at
        state = (
            self._build_bench_vehicle_state(t)
            if VEHICLE_BENCH_SIM_ENABLED
            else self._build_empty_vehicle_state()
        )
        self._apply_can_overlay(state)
        self._apply_serial_overlay(state)
        sample, health = self._gps.snapshot()
        state["gps"] = build_hardware_gps_payload(sample, stale=health.stale)
        state["gpsSource"] = "hardware"
        if VEHICLE_BENCH_SIM_ENABLED and BENCH_PROFILE == "cruise":
            state["gps"] = self._build_cruise_gps_payload(t, state["gps"])
            state["gpsSource"] = "bench_cruise"
        state["_health"]["gpsSourcePolicy"] = "hardware_only"
        self._apply_speed_source(state, sample, health)
        if VEHICLE_BENCH_SIM_ENABLED:
            state["_health"]["benchProfile"] = BENCH_PROFILE
        state["_health"]["gpsStale"] = health.stale
        state["_health"]["gpsSerialOk"] = health.serial_ok
        state["_health"]["gpsAgeMs"] = health.age_ms
        state["_health"]["gpsParseErrors"] = health.parse_errors
        state["_health"]["gpsDevice"] = health.device
        if health.last_error:
            state["_health"]["gpsLastError"] = health.last_error
        self._apply_vehicle_baseline(state)
        if self._signal_health is not None:
            signal_health = self._signal_health.observe(state)
            state["_health"]["signalMonitor"] = {
                "enabled": signal_health["enabled"],
                "ok": signal_health["ok"],
                "watching": signal_health.get("watching", []),
            }
            if signal_health["faults"]:
                state["_health"]["signalFaults"] = signal_health["faults"]
        elif SIGNAL_HEALTH_ENABLED:
            state["_health"]["signalMonitor"] = {
                "enabled": False,
                "ok": False,
                "reason": "failed to initialize",
            }
        self._apply_transition_monitor(state)
        self._apply_diagnostic_status(state)
        self._apply_diagnostic_stack_status(state)
        self._apply_fault_recording(state)
        return state

    async def broadcast_loop(self) -> None:
        while True:
            self.last_loop_monotonic = time.monotonic()
            if self.clients:
                frame = json.dumps(await self.next_state())
                disconnected = []
                for ws in self.clients:
                    try:
                        await ws.send(frame)
                    except Exception:
                        disconnected.append(ws)
                for ws in disconnected:
                    await self.remove_client(ws)
            await asyncio.sleep(FRAME_PERIOD_SEC)


WATCHDOG_MAX_LOOP_LAG_SEC = float(os.getenv("BBB_WATCHDOG_MAX_LOOP_LAG_SEC", "5"))


async def watchdog_loop(hub: VehicleHub, tasks: list) -> None:
    """Pet the systemd watchdog only while the hub is demonstrably making progress.

    Stops petting when the broadcast loop has stalled or any background task has died,
    so systemd restarts a hung (not just crashed) hub. No-op outside systemd.
    """
    interval = sd_notify.watchdog_interval_sec()
    if interval is None:
        return
    while True:
        lag = time.monotonic() - hub.last_loop_monotonic
        if lag <= WATCHDOG_MAX_LOOP_LAG_SEC and not any(task.done() for task in tasks):
            sd_notify.notify("WATCHDOG=1")
        else:
            print(f"[bbb_hub] watchdog: not petting (loop lag {lag:.1f}s, dead tasks: {[t for t in tasks if t.done()]})")
        await asyncio.sleep(interval)


async def ws_handler(ws: websockets.WebSocketServerProtocol, hub: VehicleHub) -> None:
    await hub.add_client(ws)
    try:
        await ws.wait_closed()
    finally:
        await hub.remove_client(ws)


async def main() -> None:
    if GPS_SOURCE_POLICY != "hardware_only":
        print(f"[bbb_hub] forcing GPS_SOURCE_POLICY=hardware_only (got {GPS_SOURCE_POLICY})")

    hub = VehicleHub()
    if hub._diagnostic_stack_status.get("degraded"):
        reasons = hub._diagnostic_stack_status.get("reasons", [])
        reason_text = ",".join(str(reason) for reason in reasons) if isinstance(reasons, list) else "unknown"
        print(f"[bbb_hub] diagnostic stack degraded: {reason_text}")
        if DIAGNOSTIC_STACK_STRICT:
            raise SystemExit(1)

    ws_server = await websockets.serve(lambda ws: ws_handler(ws, hub), WS_HOST, WS_PORT)

    print(f"[bbb_hub] vehicle_state ws://{WS_HOST}:{WS_PORT}")
    print(f"[bbb_hub] gps source policy: hardware_only")
    print(f"[bbb_hub] bench vehicle sim: {'enabled' if VEHICLE_BENCH_SIM_ENABLED else 'disabled'}")
    if VEHICLE_BENCH_SIM_ENABLED:
        print(f"[bbb_hub] bench profile: {BENCH_PROFILE}")
    print(f"[bbb_hub] speed source policy: {VEHICLE_SPEED_SOURCE}")
    print(f"[bbb_hub] GPS device: {GPS_DEVICE} @ {GPS_BAUD}")
    print(f"[bbb_hub] GPS read timeout: {GPS_READ_TIMEOUT_MS} ms | stale: {GPS_STALE_MS} ms")

    background_tasks = [
        asyncio.create_task(hub.gps_loop()),
        asyncio.create_task(hub.broadcast_loop()),
    ]
    if hub._can_live is not None:
        background_tasks.append(asyncio.create_task(hub.can_live_loop()))
    if hub._serial_inputs is not None:
        background_tasks.append(asyncio.create_task(hub.serial_input_loop()))
    sd_notify.notify("READY=1")
    watchdog_task = asyncio.create_task(watchdog_loop(hub, background_tasks))
    background_tasks.append(watchdog_task)
    try:
        await asyncio.gather(ws_server.wait_closed(), *background_tasks)
    finally:
        for task in background_tasks:
            task.cancel()
        for task in background_tasks:
            with contextlib.suppress(asyncio.CancelledError):
                await task


if __name__ == "__main__":
    asyncio.run(main())
