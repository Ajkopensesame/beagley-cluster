#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.bbb_hub.diagnostic_status import _collect_findings, build_diagnostic_status  # noqa: E402
from tools.bbb_hub.fault_recorder import FaultRecorder  # noqa: E402
from tools.bbb_hub.health_verdict import (  # noqa: E402
    DIRECT_ANCHOR_NAMES,
    build_coverage_summary,
    build_vehicle_health_verdict,
    summarize_source_coverage_series,
)
from tools.bbb_hub.signal_health import DEFAULT_RULES, SignalHealthMonitor  # noqa: E402
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
from tools.vehicle_analysis.fault_events import summarize_fault_event_file  # noqa: E402
from tools.vehicle_analysis.findings import SEVERITY_ORDER  # noqa: E402
from tools.vehicle_analysis.values import number_or_none  # noqa: E402


DEFAULT_FRAME_PERIOD_SECONDS = 0.1
DEFAULT_WALL_TIME = 1_700_000_000.0
TRANSITION_FINDINGS_REPORT_LIMIT = 50
LOW_TRUST_SHAPE_MIN_SAMPLES = 6
LOW_TRUST_FLAT_RANGE_EPSILON = 0.001
LOW_TRUST_NOISY_MIN_SAMPLES = 8
LOW_TRUST_NOISY_MIN_DIRECTION_CHANGES = 5
LOW_TRUST_NOISY_RANGE_EPSILON = 0.01
LOW_TRUST_NOISY_RELATIVE_RANGE = 0.02
LOW_TRUST_SHAPE_MISSING_CANDIDATE_ID_REASON = (
    "Low-trust shape evidence suppressed because trust metadata lacks stable candidateId provenance."
)
SENSOR_COVERAGE_STATUSES = ("covered", "low_trust", "unsupported")
SENSOR_COVERAGE_SURFACES = (
    "signal_health",
    "source_agreement_anchor",
    "learned_baseline_target",
    "learned_baseline_context",
    "transition_target",
    "transition_reference",
    "transition_event_input",
)


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
    diagnostic_candidate_signals: dict[str, Any] | None = None,
    baseline_profiles: Iterable[Any] | None = None,
    transition_profiles: Iterable[Any] | None = None,
) -> dict[str, Any]:
    signal_health = SignalHealthMonitor(enabled=signal_health_enabled)
    baseline_profiles = (
        list(baseline_profiles)
        if baseline_profiles is not None
        else default_vehicle_baseline_profiles()
    )
    transition_profiles = (
        list(transition_profiles)
        if transition_profiles is not None
        else default_transition_profiles()
    )
    vehicle_baseline = VehicleBaselineMonitor(
        baseline_profiles,
        storage_path=None,
        enabled=vehicle_baseline_enabled,
    )
    transition_monitor = VehicleTransitionMonitor(
        transition_profiles,
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
    synthetic_timestamp_frames = 0
    sensor_samples: Counter[str] = Counter()
    sensor_trust: dict[str, dict[str, Any]] = _candidate_signal_trust_metadata(
        diagnostic_candidate_signals,
        trust_metadata_source="diagnostic_candidate_signals_sidecar",
    )
    sensor_series: dict[str, list[tuple[float, float]]] = {}

    output_path: Path | None = None
    output_temp_path: Path | None = None
    output_handle = None
    replay_completed = False
    if enriched_jsonl is not None:
        output_path = Path(enriched_jsonl)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_temp_path = output_path.with_suffix(output_path.suffix + ".tmp")
        output_handle = output_temp_path.open("w", encoding="utf-8")

    try:
        for index, raw_state in enumerate(states):
            state = _json_clone(raw_state)
            state.setdefault("_health", {})
            if not isinstance(state["_health"], dict):
                state["_health"] = {}

            timestamp, used_synthetic_timestamp = _state_timestamp(
                state,
                index=index,
                frame_period_seconds=frame_period_seconds,
            )
            if used_synthetic_timestamp:
                synthetic_timestamp_frames += 1
            _observe_sensor_coverage(
                state,
                timestamp=timestamp,
                sensor_samples=sensor_samples,
                sensor_trust=sensor_trust,
                sensor_series=sensor_series,
            )

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
            for finding in _collect_findings(state.get("_health", {})):
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
        replay_completed = True
    finally:
        if output_handle is not None:
            output_handle.close()
        if output_path is not None and output_temp_path is not None:
            if replay_completed and output_temp_path.exists():
                os.replace(output_temp_path, output_path)
            elif output_temp_path.exists():
                output_temp_path.unlink(missing_ok=True)

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
    signal_monitor_snapshot = _signal_monitor_snapshot(last_state, enabled=signal_health_enabled)
    sensor_coverage = _build_sensor_coverage(
        sensor_samples=sensor_samples,
        sensor_trust=sensor_trust,
        sensor_series=sensor_series,
        signal_health_enabled=signal_health_enabled,
        vehicle_baseline_enabled=vehicle_baseline_enabled,
        transition_monitor_enabled=transition_monitor_enabled,
        baseline_profiles=baseline_profiles,
        transition_profiles=transition_profiles,
    )
    baseline_coverage = build_baseline_coverage_report(
        coverage=coverage,
        vehicle_baseline_snapshot=baseline_snapshot,
        transition_snapshot=transition_snapshot,
    )
    replay_generated_at = _iso_time(last_timestamp if last_timestamp is not None else DEFAULT_WALL_TIME)
    capture_ref: dict[str, Any] = {
        "sessionId": None,
        "source": "diagnostic_replay",
        "decoderVersion": "can_signals_v1",
        "durationSec": duration_sec,
    }
    if synthetic_timestamp_frames > 0:
        capture_ref["syntheticTimestamps"] = True
        capture_ref["syntheticTimestampFrames"] = synthetic_timestamp_frames
    health_verdict = build_vehicle_health_verdict(
        last_state or {"_health": {}, "_diagnostic": {}},
        mode=diagnostic_mode,
        capture_ref=capture_ref,
        coverage=coverage,
        baseline_snapshot=baseline_snapshot,
        direct_anchors=sorted(direct_anchors_seen),
        derived_anchors=[],
        generated_at=replay_generated_at,
    )
    fault_event_summaries = _summarize_fault_events(fault_event_paths)
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
        "faultEventSummaries": fault_event_summaries,
        "healthVerdict": health_verdict,
        "signalMonitor": signal_monitor_snapshot,
        "sensorCoverage": sensor_coverage,
        "baselineCoverage": baseline_coverage,
        "vehicleBaseline": baseline_snapshot,
        "transitionMonitor": transition_snapshot,
        "transitionCoverage": transition_snapshot.get("coverage", {}),
        "transitionFindings": transition_findings[:TRANSITION_FINDINGS_REPORT_LIMIT],
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


def load_diagnostic_candidate_signals(path: str | Path) -> dict[str, Any]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: diagnostic candidate signals file is not a JSON object")
    if payload.get("kind") != "diagnostic_candidate_signals":
        raise ValueError(f"{path}: expected kind diagnostic_candidate_signals")
    candidates = payload.get("candidates")
    if not isinstance(candidates, dict):
        raise ValueError(f"{path}: expected candidates object")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Replay vehicle_state JSONL through the BBB diagnostic/anomaly stack."
    )
    parser.add_argument("--state-jsonl", required=True, help="input vehicle_state JSONL")
    parser.add_argument("--report", help="write replay report JSON")
    parser.add_argument("--enriched-jsonl", help="write states after diagnostic monitors run")
    parser.add_argument("--fault-dir", help="directory for replay fault evidence events")
    parser.add_argument(
        "--diagnostic-candidate-signals",
        help="optional diagnostic_candidate_signals.json from the CAN identity workflow",
    )
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
            diagnostic_candidate_signals=(
                load_diagnostic_candidate_signals(args.diagnostic_candidate_signals)
                if args.diagnostic_candidate_signals
                else None
            ),
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


def _state_timestamp(
    state: dict[str, Any],
    *,
    index: int,
    frame_period_seconds: float,
) -> tuple[float, bool]:
    for key in ("wallTimestamp", "timestamp", "time", "t"):
        value = number_or_none(state.get(key))
        if value is not None:
            return value, False
    return DEFAULT_WALL_TIME + index * max(frame_period_seconds, 0.001), True


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


def _summarize_fault_events(paths: list[str]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for path in paths:
        try:
            summary = summarize_fault_event_file(path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            summaries.append(
                {
                    "version": 1,
                    "kind": "bbb_fault_event_summary_error",
                    "eventRef": {"path": path},
                    "error": str(exc),
                }
            )
            continue
        summary.setdefault("eventRef", {})
        if isinstance(summary["eventRef"], dict):
            summary["eventRef"]["path"] = path
        summaries.append(summary)
    return summaries


def _signal_monitor_snapshot(last_state: dict[str, Any] | None, *, enabled: bool) -> dict[str, Any]:
    health = last_state.get("_health", {}) if isinstance(last_state, dict) else {}
    if not isinstance(health, dict):
        health = {}
    monitor = health.get("signalMonitor") if isinstance(health.get("signalMonitor"), dict) else {}
    faults = health.get("signalFaults", [])
    if not isinstance(faults, list):
        faults = []
    watching = monitor.get("watching", [])
    if not isinstance(watching, list):
        watching = []
    return {
        "enabled": bool(monitor.get("enabled", enabled)),
        "ok": bool(monitor.get("ok", not faults)),
        "watching": sorted(str(signal) for signal in watching if str(signal).strip()),
        "faultCount": len([fault for fault in faults if isinstance(fault, dict)]),
    }


def _print_summary(report: dict[str, Any]) -> None:
    summary = report["summary"]
    health_verdict = report.get("healthVerdict", {})
    capture_ref = health_verdict.get("captureRef", {}) if isinstance(health_verdict, dict) else {}
    if isinstance(capture_ref, dict) and capture_ref.get("syntheticTimestamps"):
        synthetic_frames = int(number_or_none(capture_ref.get("syntheticTimestampFrames")) or 0)
        print(
            "[diagnostic-replay] "
            f"synthetic_timestamps=true frames={synthetic_frames} "
            "(replay used fallback wall time; duration and transition timing may be approximate)"
        )
    verdict = health_verdict.get("verdict", {}) if isinstance(health_verdict, dict) else {}
    vehicle_baseline = report.get("vehicleBaseline", {})
    vehicle_baseline_enabled = not (
        isinstance(vehicle_baseline, dict) and vehicle_baseline.get("enabled") is False
    )
    print(
        "[diagnostic-replay] "
        f"frames={summary['frames']} "
        f"anomaly_frames={summary['anomalyFrames']} "
        f"worst={summary['worstSeverity']} "
        f"fault_events={summary['faultEvents']} "
        f"verdict={verdict.get('label', 'unknown')}"
    )
    fault_recorder = report.get("faultRecorder", {})
    if isinstance(fault_recorder, dict):
        recorder_enabled = bool(fault_recorder.get("enabled", False))
        recorder_writes = int(number_or_none(fault_recorder.get("writes")) or 0)
        last_event_path = fault_recorder.get("lastEventPath")
        last_event_text = "present" if isinstance(last_event_path, str) and last_event_path else "none"
        print(
            "[diagnostic-replay] "
            f"fault_recorder enabled={str(recorder_enabled).lower()} "
            f"writes={recorder_writes} "
            f"last_event={last_event_text}"
        )
        if not recorder_enabled:
            print(
                "[diagnostic-replay] fault recorder guidance: fault recorder disabled for this replay; "
                "deterministic findings may still be present."
            )
    signal_monitor = report.get("signalMonitor", {})
    if isinstance(signal_monitor, dict):
        signal_enabled = bool(signal_monitor.get("enabled", False))
        signal_ok = bool(signal_monitor.get("ok", True))
        signal_fault_count = int(number_or_none(signal_monitor.get("faultCount")) or 0)
        watching = signal_monitor.get("watching", [])
        if not isinstance(watching, list):
            watching = []
        watching_names = [str(signal) for signal in watching if str(signal).strip()]
        watching_text = ",".join(watching_names[:5]) if watching_names else "none"
        if len(watching_names) > 5:
            watching_text = f"{watching_text},+{len(watching_names) - 5}"
        print(
            "[diagnostic-replay] "
            f"signal_health enabled={str(signal_enabled).lower()} "
            f"ok={str(signal_ok).lower()} "
            f"faults={signal_fault_count} "
            f"watching={watching_text}"
        )
        if not signal_enabled:
            print("[diagnostic-replay] signal health guidance: signal health monitor disabled for this replay.")
    sensor_coverage = report.get("sensorCoverage", {})
    if isinstance(sensor_coverage, dict):
        coverage_summary = sensor_coverage.get("summary", {})
        if isinstance(coverage_summary, dict):
            observed = int(number_or_none(coverage_summary.get("observedSensors")) or 0)
            covered = int(number_or_none(coverage_summary.get("coveredSensors")) or 0)
            low_trust = int(number_or_none(coverage_summary.get("lowTrustSensors")) or 0)
            unsupported = int(number_or_none(coverage_summary.get("unsupportedSensors")) or 0)
            shape_findings = int(number_or_none(coverage_summary.get("lowTrustShapeFindings")) or 0)
            coverage_ratio = float(number_or_none(coverage_summary.get("coverageRatio")) or 0.0)
            gap_ratio = float(number_or_none(coverage_summary.get("gapRatio")) or 0.0)
            print(
                "[diagnostic-replay] "
                f"sensor_coverage observed={observed} "
                f"covered={covered} "
                f"low_trust={low_trust} "
                f"unsupported={unsupported} "
                f"shape_findings={shape_findings} "
                f"coverage_ratio={coverage_ratio:.3f} "
                f"gap_ratio={gap_ratio:.3f}"
            )
            surface_summary = sensor_coverage.get("surfaceSummary", {})
            if isinstance(surface_summary, dict):
                surface_counts = surface_summary.get("surfaceCounts", {})
                gap_sensors = surface_summary.get("gapSensors", [])
                if isinstance(surface_counts, dict) and isinstance(gap_sensors, list):
                    counts_text = " ".join(
                        f"{surface}={int(number_or_none(surface_counts.get(surface)) or 0)}"
                        for surface in SENSOR_COVERAGE_SURFACES
                    )
                    print(
                        "[diagnostic-replay] "
                        f"sensor_surfaces {counts_text} gaps={len(gap_sensors)}"
                    )
            if low_trust or unsupported or shape_findings:
                print(
                    "[diagnostic-replay] sensor coverage guidance: inspect sensorCoverage; "
                    "low-trust or unsupported sensors need promotion, rules, or learned fixtures."
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
            steady_state = baseline_coverage.get("steadyState", {})
            ready_models = steady_state.get("readyModels", []) if isinstance(steady_state, dict) else []
            if not isinstance(ready_models, list):
                ready_models = []
            ready_model_names = [str(model) for model in ready_models if str(model).strip()]
            ready_models_text = ",".join(ready_model_names[:5]) if ready_model_names else "none"
            if len(ready_model_names) > 5:
                ready_models_text = f"{ready_models_text},+{len(ready_model_names) - 5}"
            print(
                "[diagnostic-replay] "
                f"vehicle_baseline enabled={str(vehicle_baseline_enabled).lower()} "
                f"ready_models={ready_models_text}"
            )
            if not vehicle_baseline_enabled:
                print("[diagnostic-replay] vehicle baseline guidance: vehicle baseline disabled for this replay.")
            else:
                next_steps = coverage_summary.get("nextSteps", [])
                if isinstance(next_steps, list) and next_steps:
                    print("[diagnostic-replay] next baseline steps:")
                    for step in next_steps[:5]:
                        if not isinstance(step, dict):
                            continue
                        scenario = str(step.get("scenario") or "unknown")
                        status = str(step.get("status") or "unknown")
                        next_step = str(step.get("nextStep") or "").strip()
                        if next_step:
                            print(f"  {scenario} ({status}): {next_step}")
    transition_coverage = report.get("transitionCoverage", {})
    transition_findings = report.get("transitionFindings", [])
    if isinstance(transition_coverage, dict):
        transition_monitor = report.get("transitionMonitor", {})
        transition_enabled = bool(transition_monitor.get("enabled", False)) if isinstance(transition_monitor, dict) else False
        ready_models = transition_coverage.get("readyModels", [])
        if not isinstance(ready_models, list):
            ready_models = []
        ready_model_names = [str(model) for model in ready_models if str(model).strip()]
        ready_models_text = ",".join(ready_model_names[:5]) if ready_model_names else "none"
        if len(ready_model_names) > 5:
            ready_models_text = f"{ready_models_text},+{len(ready_model_names) - 5}"
        transition_finding_count = len(transition_findings) if isinstance(transition_findings, list) else 0
        baseline_ready = bool(report.get("transitionBaselineReady", False))
        print(
            "[diagnostic-replay] "
            f"transitions enabled={str(transition_enabled).lower()} "
            f"baseline_ready={str(baseline_ready).lower()} "
            f"findings={transition_finding_count} "
            f"ready_models={ready_models_text}"
        )
        if not transition_enabled:
            print("[diagnostic-replay] transition guidance: transition monitor disabled for this replay.")
        elif transition_finding_count:
            print(
                "[diagnostic-replay] transition guidance: inspect transitionFindings; "
                "transition anomalies may also appear in faultEventSummaries when the fault recorder is enabled."
            )
        elif not baseline_ready:
            print("[diagnostic-replay] transition guidance: capture repeated known-good transition events.")
    finding_counts = summary.get("findingCounts", {})
    if finding_counts:
        print("[diagnostic-replay] findings:")
        for code, count in sorted(finding_counts.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {code}: {count}")


def _observe_sensor_coverage(
    state: dict[str, Any],
    *,
    timestamp: float,
    sensor_samples: Counter[str],
    sensor_trust: dict[str, dict[str, Any]],
    sensor_series: dict[str, list[tuple[float, float]]],
) -> None:
    for name in _iter_observed_sensor_names(state):
        sensor_samples[name] += 1
        value = number_or_none(_read_sensor_path(state, name))
        if value is not None:
            sensor_series.setdefault(name, []).append((timestamp, value))
    for name, trust in _sensor_trust_metadata(state).items():
        if name:
            sensor_trust[name] = trust


def _iter_observed_sensor_names(state: dict[str, Any]) -> list[str]:
    names: list[str] = []
    for key, value in state.items():
        if key in {"type", "version", "wallTimestamp", "timestamp", "time", "t", "_health", "_diagnostic"}:
            continue
        if _is_observable_sensor_value(key, value):
            names.append(key)
    gps = state.get("gps")
    if isinstance(gps, dict):
        for key, value in gps.items():
            path = f"gps.{key}"
            if _is_observable_sensor_value(path, value):
                names.append(path)
    for container_name in ("drivetrain", "transmission"):
        container = state.get(container_name)
        if isinstance(container, dict):
            gear = container.get("gear")
            path = f"{container_name}.gear"
            if _is_observable_sensor_value(path, gear):
                names.append(path)
    return sorted(set(names))


def _is_observable_sensor_value(path: str, value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if number_or_none(value) is not None:
        return True
    return path in {"gear", "drivetrain.gear", "transmission.gear"} and isinstance(value, str) and bool(value.strip())


def _read_sensor_path(state: dict[str, Any], path: str) -> Any:
    current: Any = state
    for part in path.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return current


def _sensor_trust_metadata(state: dict[str, Any]) -> dict[str, dict[str, Any]]:
    metadata: dict[str, dict[str, Any]] = {}
    health = state.get("_health")
    health = health if isinstance(health, dict) else {}
    for container, trust_metadata_source in (
        (state.get("sensorTrust"), "sensorTrust"),
        (health.get("sensorTrust"), "_health.sensorTrust"),
    ):
        if not isinstance(container, dict):
            continue
        for name, value in container.items():
            if isinstance(value, dict):
                trust_metadata = dict(value)
            else:
                trust_metadata = {"trust": str(value)}
            trust_metadata["trustMetadataSource"] = trust_metadata_source
            trust_metadata.setdefault("source", trust_metadata_source)
            metadata[str(name)] = trust_metadata
    for container, trust_metadata_source in (
        (state.get("diagnosticCandidateSignals"), "diagnosticCandidateSignals"),
        (health.get("diagnosticCandidateSignals"), "_health.diagnosticCandidateSignals"),
    ):
        if not isinstance(container, dict):
            continue
        metadata.update(_candidate_signal_trust_metadata(container, trust_metadata_source=trust_metadata_source))
    return metadata


def _candidate_signal_trust_metadata(
    payload: dict[str, Any] | None,
    *,
    trust_metadata_source: str = "diagnostic_candidate_signals",
) -> dict[str, dict[str, Any]]:
    if not isinstance(payload, dict):
        return {}
    candidates = payload.get("candidates")
    if not isinstance(candidates, dict):
        return {}
    metadata: dict[str, dict[str, Any]] = {}
    for name, value in candidates.items():
        if isinstance(value, dict):
            metadata[str(name)] = {
                **value,
                "trust": value.get("trust", "low"),
                "source": "diagnostic_candidate_signals",
                "trustMetadataSource": trust_metadata_source,
            }
    return metadata


def _build_sensor_coverage(
    *,
    sensor_samples: Counter[str],
    sensor_trust: dict[str, dict[str, Any]],
    sensor_series: dict[str, list[tuple[float, float]]],
    signal_health_enabled: bool,
    vehicle_baseline_enabled: bool,
    transition_monitor_enabled: bool,
    baseline_profiles: Iterable[Any],
    transition_profiles: Iterable[Any],
) -> dict[str, Any]:
    baseline_targets = {profile.target for profile in baseline_profiles}
    baseline_context = {
        feature.signal
        for profile in baseline_profiles
        for feature in profile.features
    } | {
        condition.signal
        for profile in baseline_profiles
        for condition in profile.conditions
    }
    transition_targets = {profile.target for profile in transition_profiles}
    transition_refs = {
        signal
        for profile in transition_profiles
        for signal in profile.reference_signals
    }
    sensors: list[dict[str, Any]] = []
    all_shape_findings: list[dict[str, Any]] = []
    for name in sorted(sensor_samples):
        trust_metadata = sensor_trust.get(name, {})
        trust_tier = _sensor_trust_tier(name, trust_metadata)
        surfaces = _sensor_coverage_surfaces(
            name,
            signal_health_enabled=signal_health_enabled,
            vehicle_baseline_enabled=vehicle_baseline_enabled,
            transition_monitor_enabled=transition_monitor_enabled,
            baseline_targets=baseline_targets,
            baseline_context=baseline_context,
            transition_targets=transition_targets,
            transition_refs=transition_refs,
        )
        status = _sensor_coverage_status(trust_tier=trust_tier, surfaces=surfaces)
        shape_findings = _low_trust_shape_findings(
            name,
            sensor_series.get(name, []),
            trust_metadata=trust_metadata,
            trust_tier=trust_tier,
        )
        all_shape_findings.extend(shape_findings)
        sensor = {
            "name": name,
            "sampleCount": sensor_samples[name],
            "trustTier": trust_tier,
            "status": status,
            "surfaces": surfaces,
            "shapeFindings": shape_findings,
            "reason": _sensor_coverage_reason(status),
        }
        shape_suppressed_reason = _low_trust_shape_suppressed_reason(
            sensor_series.get(name, []),
            trust_metadata=trust_metadata,
            trust_tier=trust_tier,
        )
        if shape_suppressed_reason:
            sensor["shapeFindingSuppressedReason"] = shape_suppressed_reason
        sensors.append(sensor)
    status_counts = Counter(sensor["status"] for sensor in sensors)
    observed_sensor_count = len(sensors)
    covered_sensor_count = status_counts.get("covered", 0)
    gap_sensor_count = status_counts.get("low_trust", 0) + status_counts.get("unsupported", 0)
    surface_summary = _sensor_surface_summary(sensors)
    _validate_sensor_surface_summary(sensors, surface_summary)
    return {
        "version": 1,
        "kind": "bbb_sensor_coverage_report",
        "summary": {
            "observedSensors": observed_sensor_count,
            "coveredSensors": covered_sensor_count,
            "lowTrustSensors": status_counts.get("low_trust", 0),
            "unsupportedSensors": status_counts.get("unsupported", 0),
            "lowTrustShapeFindings": len(all_shape_findings),
            "coverageRatio": _coverage_ratio(covered_sensor_count, observed_sensor_count),
            "gapRatio": _coverage_ratio(gap_sensor_count, observed_sensor_count),
        },
        "surfaceSummary": surface_summary,
        "sensors": sensors,
        "shapeFindings": all_shape_findings,
    }


def _coverage_ratio(covered: int, observed: int) -> float:
    if observed <= 0:
        return 0.0
    return round(covered / observed, 6)


def _sensor_surface_summary(sensors: list[dict[str, Any]]) -> dict[str, Any]:
    status_sensors = {status: [] for status in SENSOR_COVERAGE_STATUSES}
    surface_sensors = {surface: [] for surface in SENSOR_COVERAGE_SURFACES}
    for sensor in sensors:
        name = str(sensor.get("name", "")).strip()
        if not name:
            continue
        status = str(sensor.get("status", "")).strip()
        if status in status_sensors:
            status_sensors[status].append(name)
        surfaces = sensor.get("surfaces", [])
        if not isinstance(surfaces, list):
            continue
        for surface_value in surfaces:
            surface = str(surface_value).strip()
            if surface not in surface_sensors:
                surface_sensors[surface] = []
            surface_sensors[surface].append(name)
    ordered_surface_sensors = {
        surface: sorted(names)
        for surface, names in sorted(surface_sensors.items())
    }
    ordered_status_sensors = {
        status: sorted(names)
        for status, names in status_sensors.items()
    }
    gap_sensors = sorted(
        ordered_status_sensors.get("low_trust", [])
        + ordered_status_sensors.get("unsupported", [])
    )
    return {
        "statusSensors": ordered_status_sensors,
        "surfaceSensors": ordered_surface_sensors,
        "surfaceCounts": {
            surface: len(names)
            for surface, names in ordered_surface_sensors.items()
        },
        "gapSensors": gap_sensors,
    }


def _validate_sensor_surface_summary(
    sensors: list[dict[str, Any]],
    surface_summary: dict[str, Any],
) -> None:
    status_sensors = surface_summary.get("statusSensors")
    if not isinstance(status_sensors, dict):
        raise ValueError("sensorCoverage.surfaceSummary.statusSensors must be an object")
    surface_sensors = surface_summary.get("surfaceSensors")
    if not isinstance(surface_sensors, dict):
        raise ValueError("sensorCoverage.surfaceSummary.surfaceSensors must be an object")
    surface_counts = surface_summary.get("surfaceCounts")
    if not isinstance(surface_counts, dict):
        raise ValueError("sensorCoverage.surfaceSummary.surfaceCounts must be an object")
    gap_sensors = surface_summary.get("gapSensors")
    if not isinstance(gap_sensors, list):
        raise ValueError("sensorCoverage.surfaceSummary.gapSensors must be a list")
    expected_surface_sensors: dict[str, list[str]] = {
        surface: []
        for surface in SENSOR_COVERAGE_SURFACES
    }
    for sensor in sensors:
        name = str(sensor.get("name", "")).strip()
        if not name:
            continue
        surfaces = sensor.get("surfaces", [])
        if not isinstance(surfaces, list):
            raise ValueError("sensorCoverage.sensors[].surfaces must be a list")
        for surface_value in surfaces:
            surface = str(surface_value).strip()
            if not surface:
                continue
            expected_surface_sensors.setdefault(surface, []).append(name)
    expected_surface_sensors = {
        surface: sorted(names)
        for surface, names in sorted(expected_surface_sensors.items())
    }
    if surface_sensors != expected_surface_sensors:
        raise ValueError(
            "sensorCoverage.surfaceSummary.surfaceSensors must exactly match "
            "sensorCoverage.sensors surfaces entries"
        )
    expected_surface_counts = {
        surface: len(names)
        for surface, names in expected_surface_sensors.items()
    }
    if surface_counts != expected_surface_counts:
        raise ValueError(
            "sensorCoverage.surfaceSummary.surfaceCounts must exactly match "
            "surfaceSensors list lengths"
        )
    expected_status_sensors: dict[str, list[str]] = {
        status: []
        for status in SENSOR_COVERAGE_STATUSES
    }
    for sensor in sensors:
        name = str(sensor.get("name", "")).strip()
        status = str(sensor.get("status", "")).strip()
        if name and status in expected_status_sensors:
            expected_status_sensors[status].append(name)
    expected_status_sensors = {
        status: sorted(names)
        for status, names in expected_status_sensors.items()
    }
    if status_sensors != expected_status_sensors:
        raise ValueError(
            "sensorCoverage.surfaceSummary.statusSensors must exactly match "
            "sensorCoverage.sensors status entries"
        )
    expected_gap_sensors = sorted(
        str(sensor.get("name", "")).strip()
        for sensor in sensors
        if str(sensor.get("status", "")).strip() in {"low_trust", "unsupported"}
        and str(sensor.get("name", "")).strip()
    )
    if gap_sensors != expected_gap_sensors:
        raise ValueError(
            "sensorCoverage.surfaceSummary.gapSensors must exactly match "
            "low_trust and unsupported sensorCoverage.sensors entries"
        )


def _sensor_trust_tier(name: str, metadata: dict[str, Any]) -> str:
    trust = str(metadata.get("trust") or metadata.get("trustTier") or "").strip().lower()
    if trust in {"low", "low_trust", "candidate", "probable"}:
        return "low_trust_candidate"
    if trust in {"verified", "verified_decoded"} or metadata.get("verified") is True:
        return "verified_decoded"
    if name.startswith("gps."):
        return "direct_anchor"
    if name in DEFAULT_RULES or name in DIRECT_ANCHOR_NAMES or name in {"gear", "drivetrain.gear", "transmission.gear"}:
        return "verified_decoded"
    return "unknown"


def _sensor_coverage_surfaces(
    name: str,
    *,
    signal_health_enabled: bool,
    vehicle_baseline_enabled: bool,
    transition_monitor_enabled: bool,
    baseline_targets: set[str],
    baseline_context: set[str],
    transition_targets: set[str],
    transition_refs: set[str],
) -> list[str]:
    surfaces: set[str] = set()
    if signal_health_enabled and name in DEFAULT_RULES:
        surfaces.add("signal_health")
    if signal_health_enabled and name == "gps.speedKph":
        surfaces.add("source_agreement_anchor")
    if vehicle_baseline_enabled:
        if name in baseline_targets:
            surfaces.add("learned_baseline_target")
        if name in baseline_context:
            surfaces.add("learned_baseline_context")
    if transition_monitor_enabled:
        if name in transition_targets:
            surfaces.add("transition_target")
        if name in transition_refs:
            surfaces.add("transition_reference")
        if name in {"gear", "drivetrain.gear", "transmission.gear"}:
            surfaces.add("transition_event_input")
    return sorted(surfaces)


def _sensor_coverage_status(*, trust_tier: str, surfaces: list[str]) -> str:
    if trust_tier == "low_trust_candidate":
        return "low_trust"
    if surfaces:
        return "covered"
    return "unsupported"


def _sensor_coverage_reason(status: str) -> str:
    if status == "covered":
        return "Observed with deterministic signal-health, baseline, transition, or source-agreement coverage."
    if status == "low_trust":
        return "Observed as low-trust diagnostic evidence only; needs promotion, rules, or known-good baseline support."
    return "Observed but no deterministic rule, learned model, transition profile, or low-trust policy covers it yet."


def _trust_candidate_id(metadata: dict[str, Any]) -> str:
    candidate_id = metadata.get("candidateId")
    if candidate_id is None:
        return ""
    return str(candidate_id).strip()


def _low_trust_shape_suppressed_reason(
    series: list[tuple[float, float]],
    *,
    trust_metadata: dict[str, Any],
    trust_tier: str,
) -> str | None:
    if trust_tier != "low_trust_candidate" or len(series) < LOW_TRUST_SHAPE_MIN_SAMPLES:
        return None
    if _trust_candidate_id(trust_metadata):
        return None
    return LOW_TRUST_SHAPE_MISSING_CANDIDATE_ID_REASON


def _low_trust_shape_findings(
    name: str,
    series: list[tuple[float, float]],
    *,
    trust_metadata: dict[str, Any],
    trust_tier: str,
) -> list[dict[str, Any]]:
    if trust_tier != "low_trust_candidate" or len(series) < LOW_TRUST_SHAPE_MIN_SAMPLES:
        return []
    candidate_id = _trust_candidate_id(trust_metadata)
    if not candidate_id:
        return []
    values = [value for _, value in series]
    value_min = min(values)
    value_max = max(values)
    value_range = value_max - value_min
    mean_abs = abs(sum(values) / len(values))
    flat_limit = max(LOW_TRUST_FLAT_RANGE_EPSILON, mean_abs * 0.00001)
    first_ts = series[0][0]
    last_ts = series[-1][0]
    base_details = {
        "sampleCount": len(series),
        "durationSec": round(max(0.0, last_ts - first_ts), 3),
        "valueRange": round(value_range, 6),
        "trustTier": trust_tier,
        "candidateId": candidate_id,
    }
    if trust_metadata.get("trustMetadataSource"):
        base_details["trustMetadataSource"] = str(trust_metadata.get("trustMetadataSource"))
    if value_range <= flat_limit:
        return [
            {
                "source": "sensorCoverage",
                "subject": name,
                "code": "low_trust_candidate_stuck_flat",
                "severity": "info",
                "message": (
                    f"Low-trust candidate {name} stayed flat across replay; "
                    "use as capture guidance only until the signal is promoted."
                ),
                "confidence": 0.5,
                "details": {
                    **base_details,
                    "shape": "stuck_flat",
                    "flatLimit": round(flat_limit, 6),
                },
            }
        ]
    if len(series) < LOW_TRUST_NOISY_MIN_SAMPLES:
        return []
    noisy_range_limit = max(LOW_TRUST_NOISY_RANGE_EPSILON, mean_abs * LOW_TRUST_NOISY_RELATIVE_RANGE)
    step_epsilon = max(LOW_TRUST_FLAT_RANGE_EPSILON, value_range * 0.05)
    direction_changes, significant_steps = _direction_change_summary(values, step_epsilon=step_epsilon)
    if value_range < noisy_range_limit or direction_changes < LOW_TRUST_NOISY_MIN_DIRECTION_CHANGES:
        return []
    return [
        {
            "source": "sensorCoverage",
            "subject": name,
            "code": "low_trust_candidate_noisy_or_flapping",
            "severity": "info",
            "message": (
                f"Low-trust candidate {name} oscillated across replay; "
                "use as capture guidance only until the signal is promoted."
            ),
            "confidence": 0.5,
            "details": {
                **base_details,
                "shape": "noisy_or_flapping",
                "directionChanges": direction_changes,
                "significantSteps": significant_steps,
                "stepEpsilon": round(step_epsilon, 6),
                "noisyRangeLimit": round(noisy_range_limit, 6),
            },
        }
    ]


def _direction_change_summary(values: list[float], *, step_epsilon: float) -> tuple[int, int]:
    directions: list[int] = []
    for before, after in zip(values, values[1:]):
        delta = after - before
        if abs(delta) <= step_epsilon:
            continue
        directions.append(1 if delta > 0.0 else -1)
    direction_changes = sum(1 for before, after in zip(directions, directions[1:]) if before != after)
    return direction_changes, len(directions)


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


def _iso_time(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def _baseline_comparison_count(snapshot: dict[str, Any]) -> int:
    if not isinstance(snapshot, dict):
        return 0
    models = snapshot.get("models", [])
    if not isinstance(models, list):
        return 0
    return sum(int(number_or_none(model.get("totalSamples")) or 0) for model in models if isinstance(model, dict))


if __name__ == "__main__":
    raise SystemExit(main())
