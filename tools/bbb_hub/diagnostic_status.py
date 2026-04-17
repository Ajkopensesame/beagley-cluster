from __future__ import annotations

from typing import Any

from tools.vehicle_analysis.findings import (
    SEVERITY_ORDER,
    normalize_diagnostic_finding,
    normalize_severity,
    normalize_signal_fault,
)


def build_diagnostic_status(
    state: dict[str, Any],
    *,
    mode: str = "normal",
    max_active_findings: int = 6,
) -> dict[str, Any]:
    health = state.get("_health") if isinstance(state.get("_health"), dict) else {}
    findings = _collect_findings(health)
    worst_severity = _worst_severity(findings)
    stale = bool(health.get("stale", False))
    capture_quality = _capture_quality(state, health)

    if stale:
        ok = False
        severity = "warning" if worst_severity in {"ok", "info"} else worst_severity
        status = "data_stale"
        summary = "VEHICLE DATA STALE"
    elif findings:
        ok = worst_severity not in {"warning", "error"}
        severity = worst_severity
        status = "anomaly_detected" if not ok else "limited"
        summary = _summary_for_findings(findings)
    elif _capture_limited(capture_quality):
        ok = True
        severity = "info"
        status = "limited"
        summary = "CAPTURE LIMITED"
    else:
        ok = True
        severity = "ok"
        status = "nominal"
        summary = "SYSTEMS NOMINAL"

    return {
        "version": 1,
        "mode": (mode or "normal").strip().lower(),
        "ok": ok,
        "severity": severity,
        "status": status,
        "summary": summary,
        "findingCount": len(findings),
        "activeFindings": findings[:max(0, max_active_findings)],
        "captureQuality": capture_quality,
    }


def _collect_findings(health: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str, str]] = set()

    for fault in health.get("signalFaults", []):
        if isinstance(fault, dict):
            _append_unique(findings, seen, normalize_signal_fault(fault))

    for diagnostics_key in ("canLiveDiagnostics", "canReplayDiagnostics"):
        diagnostics = health.get(diagnostics_key)
        if not isinstance(diagnostics, dict):
            continue
        for finding in diagnostics.get("findings", []):
            if isinstance(finding, dict):
                _append_unique(findings, seen, normalize_diagnostic_finding(finding, default_source=diagnostics_key))

    baseline = health.get("vehicleBaseline")
    if isinstance(baseline, dict):
        for finding in baseline.get("findings", []):
            if isinstance(finding, dict):
                _append_unique(findings, seen, normalize_diagnostic_finding(finding, default_source="vehicleBaseline"))

    findings.sort(key=lambda item: (-SEVERITY_ORDER.get(item["severity"], 1), -float(item.get("confidence", 0.0))))
    return findings


def _append_unique(
    findings: list[dict[str, Any]],
    seen: set[tuple[str, str, str, str]],
    finding: dict[str, Any],
) -> None:
    key = (
        finding.get("source", ""),
        finding.get("subject", ""),
        finding.get("code", ""),
        finding.get("message", ""),
    )
    if key in seen:
        return
    seen.add(key)
    findings.append(finding)


def _capture_quality(state: dict[str, Any], health: dict[str, Any]) -> dict[str, Any]:
    can_sources = [
        source for source in (health.get("canLive"), health.get("canReplay"))
        if isinstance(source, dict) and source.get("enabled")
    ]
    can_diagnostics = [
        source for source in (health.get("canLiveDiagnostics"), health.get("canReplayDiagnostics"))
        if isinstance(source, dict) and source.get("enabled")
    ]
    serial = health.get("serialVehicleInputs")
    gps = state.get("gps") if isinstance(state.get("gps"), dict) else {}

    can_ok: bool | None
    if can_sources or can_diagnostics:
        can_ok = not any(source.get("stale") for source in can_sources)
        can_ok = can_ok and all(source.get("ok", True) for source in can_diagnostics)
    else:
        can_ok = None

    serial_ok: bool | None
    if isinstance(serial, dict) and serial.get("enabled"):
        serial_ok = not bool(serial.get("stale", False))
    else:
        serial_ok = None

    return {
        "gpsOk": bool(gps.get("fixValid", False)) and not bool(health.get("gpsStale", False)),
        "canOk": can_ok,
        "serialOk": serial_ok,
        "linkStale": bool(health.get("stale", False)),
    }


def _capture_limited(capture_quality: dict[str, Any]) -> bool:
    return any(capture_quality.get(key) is False for key in ("canOk", "serialOk"))


def _summary_for_findings(findings: list[dict[str, Any]]) -> str:
    if not findings:
        return "SYSTEMS NOMINAL"
    primary = findings[0]
    message = str(primary.get("message") or primary.get("code") or "Diagnostic finding").strip()
    if len(findings) == 1:
        return message.upper()
    return f"{message.upper()} + {len(findings) - 1} MORE"


def _worst_severity(findings: list[dict[str, Any]]) -> str:
    worst = "ok"
    for finding in findings:
        severity = normalize_severity(finding.get("severity"))
        if SEVERITY_ORDER[severity] > SEVERITY_ORDER[worst]:
            worst = severity
    return worst
