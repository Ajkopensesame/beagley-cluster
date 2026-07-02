from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .context import operating_state
from .findings import SEVERITY_ORDER, normalize_severity, normalize_signal_fault
from .values import number_or_none


FAULT_EVENT_KIND = "bbb_fault_event"
FAULT_EVENT_SUMMARY_KIND = "bbb_fault_event_summary"

SAFE_SIGNAL_KEYS = (
    "speedKph",
    "rpm",
    "fuelPct",
    "coolantC",
    "mafGps",
    "throttlePct",
    "engineLoadPct",
    "intakeAirTempC",
    "mapKpa",
)

REPAIR_CLAIMS_TO_AVOID = (
    "guaranteed healthy",
    "fault free",
    "definitely broken",
    "replace [component]",
    "safe to operate",
)


def load_fault_event(path: str | Path) -> dict[str, Any]:
    event_path = Path(path)
    payload = json.loads(event_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{event_path}: fault event must be a JSON object")
    if payload.get("kind") != FAULT_EVENT_KIND:
        raise ValueError(f"{event_path}: expected kind {FAULT_EVENT_KIND!r}")
    if payload.get("version") != 1:
        raise ValueError(f"{event_path}: expected version 1")
    return payload


def summarize_fault_event_file(path: str | Path) -> dict[str, Any]:
    return build_fault_event_summary(load_fault_event(path))


def build_fault_event_summary(event: dict[str, Any]) -> dict[str, Any]:
    _validate_fault_event(event)
    trigger_state = event.get("triggerState") if isinstance(event.get("triggerState"), dict) else {}
    source_health = event.get("sourceHealth") if isinstance(event.get("sourceHealth"), dict) else {}
    rolling_buffer = event.get("rollingBuffer") if isinstance(event.get("rollingBuffer"), dict) else {}
    evidence = event.get("evidence") if isinstance(event.get("evidence"), dict) else {}
    findings = _normalized_findings(event)
    severity = _worst_severity(findings)
    primary = findings[0] if findings else None
    diagnostic = trigger_state.get("_diagnostic") if isinstance(trigger_state.get("_diagnostic"), dict) else {}
    capture_quality = diagnostic.get("captureQuality") if isinstance(diagnostic.get("captureQuality"), dict) else {}
    return {
        "version": 1,
        "kind": FAULT_EVENT_SUMMARY_KIND,
        "eventRef": {
            "eventId": str(event.get("eventId", "")),
            "generatedAt": str(event.get("generatedAt", "")),
            "faultFingerprint": str(event.get("faultFingerprint", "")),
            "sourceKind": FAULT_EVENT_KIND,
        },
        "status": "anomaly_recorded" if severity in {"warning", "error"} else "evidence_recorded",
        "severity": severity,
        "customerSummary": _customer_summary(primary, severity),
        "primaryFinding": primary,
        "findings": findings,
        "triggerContext": {
            "operatingState": operating_state(trigger_state),
            "diagnosticStatus": str(diagnostic.get("status", "unknown")),
            "diagnosticSummary": str(diagnostic.get("summary", "")),
            "captureQuality": dict(capture_quality),
            "signals": _safe_signals(trigger_state),
        },
        "evidenceSummary": {
            "rollingFrames": _rolling_frame_count(rolling_buffer),
            "bufferSeconds": number_or_none(rolling_buffer.get("seconds")),
            "evidenceKeys": sorted(str(key) for key in evidence),
            "sourceHealthKeys": sorted(str(key) for key in source_health),
        },
        "responsibleUse": {
            "notRepairDirective": True,
            "requiresCorroboration": True,
            "allowedUse": "Summarize recorded deterministic evidence and guide further inspection.",
            "mustAvoid": list(REPAIR_CLAIMS_TO_AVOID),
        },
    }


def _validate_fault_event(event: dict[str, Any]) -> None:
    if event.get("kind") != FAULT_EVENT_KIND:
        raise ValueError(f"expected kind {FAULT_EVENT_KIND!r}")
    if event.get("version") != 1:
        raise ValueError("expected bbb_fault_event version 1")
    faults = event.get("faults")
    if faults is not None and not isinstance(faults, list):
        raise ValueError("bbb_fault_event faults must be a list")


def _normalized_findings(event: dict[str, Any]) -> list[dict[str, Any]]:
    faults = event.get("faults") if isinstance(event.get("faults"), list) else []
    findings = [normalize_signal_fault(fault) for fault in faults if isinstance(fault, dict)]
    findings.sort(key=lambda item: (-SEVERITY_ORDER.get(item["severity"], 1), str(item.get("subject", ""))))
    return findings


def _worst_severity(findings: list[dict[str, Any]]) -> str:
    worst = "info"
    for finding in findings:
        severity = normalize_severity(finding.get("severity"))
        if SEVERITY_ORDER[severity] > SEVERITY_ORDER[worst]:
            worst = severity
    return worst


def _customer_summary(primary: dict[str, Any] | None, severity: str) -> str:
    if primary is None:
        return "A diagnostic evidence packet was recorded, but no deterministic fault entries were present."
    subject = str(primary.get("subject") or "vehicle signal")
    message = str(primary.get("message") or primary.get("code") or "Diagnostic evidence was recorded").strip()
    return f"A {severity}-level anomaly was recorded for {subject}. Evidence: {message}."


def _rolling_frame_count(rolling_buffer: dict[str, Any]) -> int:
    frames = rolling_buffer.get("frames")
    return len(frames) if isinstance(frames, list) else 0


def _safe_signals(state: dict[str, Any]) -> dict[str, float]:
    signals: dict[str, float] = {}
    for key in SAFE_SIGNAL_KEYS:
        value = number_or_none(state.get(key))
        if value is not None:
            signals[key] = value
    gps = state.get("gps") if isinstance(state.get("gps"), dict) else {}
    gps_speed = number_or_none(gps.get("speedKph"))
    if gps_speed is not None:
        signals["gpsSpeedKph"] = gps_speed
    return signals
