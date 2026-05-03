#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.bbb_hub.diagnostic_status import build_diagnostic_status  # noqa: E402
from tools.bbb_hub.fault_recorder import FaultRecorder  # noqa: E402
from tools.bbb_hub.health_verdict import (  # noqa: E402
    DIRECT_ANCHOR_NAMES,
    build_coverage_summary,
    build_vehicle_health_verdict,
    summarize_source_coverage_series,
)
from tools.bbb_hub.signal_health import SignalHealthMonitor  # noqa: E402
from tools.bbb_hub.transition_monitor import (  # noqa: E402
    VehicleTransitionMonitor,
    default_transition_profiles,
)
from tools.bbb_hub.vehicle_baseline import (  # noqa: E402
    VehicleBaselineMonitor,
    default_vehicle_baseline_profiles,
)
from tools.vehicle_analysis.context import operating_state  # noqa: E402
from tools.vehicle_analysis.baseline_coverage import build_baseline_coverage_report  # noqa: E402
from tools.vehicle_analysis.findings import SEVERITY_ORDER  # noqa: E402
from tools.vehicle_analysis.values import number_or_none  # noqa: E402


DEFAULT_FRAME_PERIOD_SECONDS = 0.1
DEFAULT_WALL_TIME = 1_700_000_000.0


def run_diagnostic_replay(
    states: Iterable[dict[str, Any]],
    *,
    frame_period_seconds: float = DEFAULT_FRAME_PERIOD_SECONDS,
    diagnostic_mode: str = "replay",
    signal_health_enabled: bool = True,
    vehicle_baseline_enabled: bool = True,
    transition_monitor_enabled: bool = True,
    fault_recorder_enabled: bool = True,
    fault_recorder_dir: str | Path | None = None,
    enriched_jsonl: str | Path | None = None,
) -> dict[str, Any]:
    signal_health = SignalHealthMonitor(enabled=signal_health_enabled)
    vehicle_baseline = VehicleBaselineMonitor(
        default_vehicle_baseline_profiles(),
        storage_path=None,
        enabled=vehicle_baseline_enabled,
    )
    transition_monitor = VehicleTransitionMonitor(
        default_transition_profiles(),
        storage_path=None,
        enabled=transition_monitor_enabled,
        min_save_interval_seconds=0.0,
    )
    fault_recorder = FaultRecorder(
        fault_recorder_dir or "/tmp/beagley-diagnostic-replay-faults",
        enabled=fault_recorder_enabled,
    )

    state_count = 0
    diagnostic_counts: Counter[str] = Counter()
    severity_counts: Counter[str] = Counter()
    finding_counts: Counter[str] = Counter()
    last_diagnostic: dict[str, Any] | None = None
    last_state: dict[str, Any] | None = None
    first_anomaly: dict[str, Any] | None = None
    fault_event_paths: list[str] = []
    observed_contexts: set[str] = set()
    direct_anchors_seen: set[str] = set()
    source_series: dict[str, list[bool | None]] = {
        "gpsOk": [],
        "canOk": [],
        "serialOk": [],
    }
    signal_samples = 0
    first_timestamp: float | None = None
    last_timestamp: float | None = None
    previous_rpm: float | None = None
    transition_findings: list[dict[str, Any]] = []

    output_handle = None
    if enriched_jsonl is not None:
        output_path = Path(enriched_jsonl)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_handle = output_path.open("w", encoding="utf-8")

    try:
        for index, raw_state in enumerate(states):
            state = _json_clone(raw_state)
            state.setdefault("_health", {})
            if not isinstance(state["_health"], dict):
                state["_health"] = {}

            timestamp = _state_timestamp(state, index=index, frame_period_seconds=frame_period_seconds)
            monotonic_time = timestamp - DEFAULT_WALL_TIME
            if first_timestamp is None:
                first_timestamp = timestamp
            last_timestamp = timestamp

            state["_health"]["vehicleBaseline"] = vehicle_baseline.observe(state, timestamp=timestamp)
            signal_report = signal_health.observe(state, now_monotonic=monotonic_time)
            state["_health"]["signalMonitor"] = {
                "enabled": signal_report.get("enabled", False),
                "ok": signal_report.get("ok", True),
                "watching": signal_report.get("watching", []),
            }
            if signal_report.get("faults"):
                state["_health"]["signalFaults"] = signal_report["faults"]
            else:
                state["_health"].pop("signalFaults", None)
            transition_report = transition_monitor.observe(state, timestamp=timestamp)
            state["_health"]["transitionMonitor"] = transition_report
            for finding in transition_report.get("findings", []):
                if isinstance(finding, dict):
                    transition_findings.append(finding)

            state["_diagnostic"] = build_diagnostic_status(state, mode=diagnostic_mode)
            recorder_health = fault_recorder.observe(
                state,
                evidence={
                    "vehicleBaseline": vehicle_baseline.snapshot(),
                    "transitionMonitor": transition_monitor.snapshot(),
                },
                wall_time=timestamp,
                monotonic_time=monotonic_time,
            )
            state["_health"]["faultRecorder"] = recorder_health

            diagnostic = state["_diagnostic"]
            state_count += 1
            last_state = state
            status = str(diagnostic.get("status", "unknown"))
            severity = str(diagnostic.get("severity", "info"))
            diagnostic_counts[status] += 1
            severity_counts[severity] += 1
            last_diagnostic = diagnostic
            if diagnostic.get("status") == "anomaly_detected" and first_anomaly is None:
                first_anomaly = {
                    "frame": index,
                    "timestamp": timestamp,
                    "diagnostic": diagnostic,
                }
            for finding in diagnostic.get("activeFindings", []):
                if isinstance(finding, dict):
                    finding_counts[str(finding.get("code", "unknown"))] += 1
            event_path = recorder_health.get("lastEventPath")
            if isinstance(event_path, str) and event_path and event_path not in fault_event_paths:
                fault_event_paths.append(event_path)

            _observe_replay_coverage(
                state,
                observed_contexts=observed_contexts,
                direct_anchors_seen=direct_anchors_seen,
                source_series=source_series,
            )
            signal_samples += _count_direct_anchor_samples(state)
            current_rpm = number_or_none(state.get("rpm"))
            current_speed = number_or_none(state.get("speedKph"))
            if _startup_transition(previous_rpm, current_rpm, current_speed):
                observed_contexts.add("startup")
                if _cold_start_like(state):
                    observed_contexts.add("cold_start")
                elif _hot_start_like(state):
                    observed_contexts.add("hot_start")
            if _heavy_load_like(state):
                observed_contexts.add("heavy_load")
            previous_rpm = current_rpm if current_rpm is not None else previous_rpm

            if output_handle is not None:
                output_handle.write(json.dumps(state, sort_keys=True) + "\n")
    finally:
        if output_handle is not None:
            output_handle.close()

    worst_severity = _worst_seen_severity(severity_counts)
    duration_sec = None
    if first_timestamp is not None and last_timestamp is not None:
        duration_sec = max(0.0, last_timestamp - first_timestamp)
    coverage = build_coverage_summary(
        observed_contexts=observed_contexts,
        source_coverage=summarize_source_coverage_series(source_series),
        sample_counts={
            "frames": state_count,
            "signalSamples": signal_samples,
            "baselineComparisons": _baseline_comparison_count(vehicle_baseline.snapshot()),
        },
        duration_sec=duration_sec,
    )
    baseline_snapshot = vehicle_baseline.snapshot()
    transition_snapshot = transition_monitor.snapshot()
    baseline_coverage = build_baseline_coverage_report(
        coverage=coverage,
        vehicle_baseline_snapshot=baseline_snapshot,
        transition_snapshot=transition_snapshot,
    )
    health_verdict = build_vehicle_health_verdict(
        last_state or {"_health": {}, "_diagnostic": {}},
        mode=diagnostic_mode,
        capture_ref={
            "sessionId": None,
            "source": "diagnostic_replay",
            "decoderVersion": "can_signals_v1",
            "durationSec": duration_sec,
        },
        coverage=coverage,
        baseline_snapshot=baseline_snapshot,
        direct_anchors=sorted(direct_anchors_seen),
        derived_anchors=[],
    )
    return {
        "version": 1,
        "kind": "bbb_diagnostic_replay_report",
        "summary": {
            "frames": state_count,
            "anomalyFrames": diagnostic_counts.get("anomaly_detected", 0),
            "limitedFrames": diagnostic_counts.get("limited", 0),
            "staleFrames": diagnostic_counts.get("data_stale", 0),
            "worstSeverity": worst_severity,
            "findingCounts": dict(sorted(finding_counts.items())),
            "faultEvents": len(fault_event_paths),
        },
        "diagnosticStatusCounts": dict(sorted(diagnostic_counts.items())),
        "severityCounts": dict(sorted(severity_counts.items())),
        "firstAnomaly": first_anomaly,
        "lastDiagnostic": last_diagnostic,
        "faultEventPaths": fault_event_paths,
        "healthVerdict": health_verdict,
        "baselineCoverage": baseline_coverage,
        "vehicleBaseline": baseline_snapshot,
        "transitionMonitor": transition_snapshot,
        "transitionCoverage": transition_snapshot.get("coverage", {}),
        "transitionFindings": transition_findings[:50],
        "transitionBaselineReady": any(
            model.get("ready")
            for model in transition_snapshot.get("models", [])
            if isinstance(model, dict)
        ),
        "faultRecorder": fault_recorder.health(),
    }


def load_state_jsonl(path: str | Path) -> list[dict[str, Any]]:
    states: list[dict[str, Any]] = []
    with Path(path).open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            text = line.strip()
            if not text:
                continue
            payload = json.loads(text)
            if not isinstance(payload, dict):
                raise ValueError(f"{path}: line {line_number} is not a JSON object")
            states.append(payload)
    return states


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Replay vehicle_state JSONL through the BBB diagnostic/anomaly stack."
    )
    parser.add_argument("--state-jsonl", required=True, help="input vehicle_state JSONL")
    parser.add_argument("--report", help="write replay report JSON")
    parser.add_argument("--enriched-jsonl", help="write states after diagnostic monitors run")
    parser.add_argument("--fault-dir", help="directory for replay fault evidence events")
    parser.add_argument("--frame-period-sec", type=float, default=DEFAULT_FRAME_PERIOD_SECONDS)
    parser.add_argument("--mode", default="replay", help="diagnostic mode label")
    parser.add_argument("--disable-signal-health", action="store_true")
    parser.add_argument("--disable-vehicle-baseline", action="store_true")
    parser.add_argument("--disable-transition-monitor", action="store_true")
    parser.add_argument("--disable-fault-recorder", action="store_true")
    args = parser.parse_args(argv)

    try:
        report = run_diagnostic_replay(
            load_state_jsonl(args.state_jsonl),
            frame_period_seconds=args.frame_period_sec,
            diagnostic_mode=args.mode,
            signal_health_enabled=not args.disable_signal_health,
            vehicle_baseline_enabled=not args.disable_vehicle_baseline,
            transition_monitor_enabled=not args.disable_transition_monitor,
            fault_recorder_enabled=not args.disable_fault_recorder,
            fault_recorder_dir=args.fault_dir,
            enriched_jsonl=args.enriched_jsonl,
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[diagnostic-replay] failed: {exc}", file=sys.stderr)
        return 2

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"[diagnostic-replay] wrote {report_path}")

    _print_summary(report)
    return 0


def _state_timestamp(state: dict[str, Any], *, index: int, frame_period_seconds: float) -> float:
    for key in ("wallTimestamp", "timestamp", "time", "t"):
        value = number_or_none(state.get(key))
        if value is not None:
            return value
    return DEFAULT_WALL_TIME + index * max(frame_period_seconds, 0.001)


def _json_clone(value: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(value, default=str, sort_keys=True))


def _worst_seen_severity(counts: Counter[str]) -> str:
    worst = "ok"
    for severity, count in counts.items():
        if count <= 0:
            continue
        normalized = severity if severity in SEVERITY_ORDER else "info"
        if SEVERITY_ORDER[normalized] > SEVERITY_ORDER[worst]:
            worst = normalized
    return worst


def _print_summary(report: dict[str, Any]) -> None:
    summary = report["summary"]
    verdict = report.get("healthVerdict", {}).get("verdict", {}) if isinstance(report.get("healthVerdict"), dict) else {}
    print(
        "[diagnostic-replay] "
        f"frames={summary['frames']} "
        f"anomaly_frames={summary['anomalyFrames']} "
        f"worst={summary['worstSeverity']} "
        f"fault_events={summary['faultEvents']} "
        f"verdict={verdict.get('label', 'unknown')}"
    )
    baseline_coverage = report.get("baselineCoverage", {})
    if isinstance(baseline_coverage, dict):
        coverage_summary = baseline_coverage.get("summary", {})
        if isinstance(coverage_summary, dict):
            print(
                "[diagnostic-replay] "
                f"baseline_coverage={coverage_summary.get('score', 0)} "
                f"strong={coverage_summary.get('strongScenarios', 0)} "
                f"weak={coverage_summary.get('weakScenarios', 0)} "
                f"missing={coverage_summary.get('missingScenarios', 0)}"
            )
    finding_counts = summary.get("findingCounts", {})
    if finding_counts:
        print("[diagnostic-replay] findings:")
        for code, count in sorted(finding_counts.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {code}: {count}")


def _observe_replay_coverage(
    state: dict[str, Any],
    *,
    observed_contexts: set[str],
    direct_anchors_seen: set[str],
    source_series: dict[str, list[bool | None]],
) -> None:
    observed_contexts.add(operating_state(state))
    for name in DIRECT_ANCHOR_NAMES:
        if number_or_none(state.get(name)) is not None:
            direct_anchors_seen.add(name)
    gps = state.get("gps") if isinstance(state.get("gps"), dict) else {}
    if number_or_none(gps.get("speedKph")) is not None:
        direct_anchors_seen.add("gpsSpeedKph")
    capture_quality = state.get("_diagnostic", {}).get("captureQuality", {}) if isinstance(state.get("_diagnostic"), dict) else {}
    for key in source_series:
        source_series[key].append(capture_quality.get(key))


def _count_direct_anchor_samples(state: dict[str, Any]) -> int:
    count = sum(1 for name in DIRECT_ANCHOR_NAMES if number_or_none(state.get(name)) is not None)
    gps = state.get("gps") if isinstance(state.get("gps"), dict) else {}
    if number_or_none(gps.get("speedKph")) is not None:
        count += 1
    return count


def _startup_transition(previous_rpm: float | None, current_rpm: float | None, current_speed: float | None) -> bool:
    if previous_rpm is None or current_rpm is None:
        return False
    if previous_rpm >= 450.0 or current_rpm < 450.0:
        return False
    return current_speed is None or current_speed <= 3.0


def _cold_start_like(state: dict[str, Any]) -> bool:
    coolant = number_or_none(state.get("coolantC"))
    intake = number_or_none(state.get("intakeAirTempC"))
    if coolant is None or intake is None:
        return False
    return abs(coolant - intake) <= 20.0


def _hot_start_like(state: dict[str, Any]) -> bool:
    coolant = number_or_none(state.get("coolantC"))
    return coolant is not None and coolant >= 70.0


def _heavy_load_like(state: dict[str, Any]) -> bool:
    throttle = number_or_none(state.get("throttlePct"))
    load = number_or_none(state.get("engineLoadPct"))
    map_kpa = number_or_none(state.get("mapKpa"))
    maf = number_or_none(state.get("mafGps"))
    return any(
        (
            throttle is not None and throttle >= 70.0,
            load is not None and load >= 70.0,
            map_kpa is not None and map_kpa >= 140.0,
            maf is not None and maf >= 100.0,
        )
    )


def _baseline_comparison_count(snapshot: dict[str, Any]) -> int:
    if not isinstance(snapshot, dict):
        return 0
    models = snapshot.get("models", [])
    if not isinstance(models, list):
        return 0
    return sum(int(number_or_none(model.get("totalSamples")) or 0) for model in models if isinstance(model, dict))


if __name__ == "__main__":
    raise SystemExit(main())
