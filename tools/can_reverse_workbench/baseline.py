from __future__ import annotations

import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from tools.vehicle_analysis.context import operating_state, state_rules_description
from tools.vehicle_analysis.stats import clamp, summary_stats
from tools.vehicle_analysis.values import numeric_signals


MIN_BASELINE_SAMPLES = 6
MIN_COMPARE_SAMPLES = 4
ANOMALY_THRESHOLD = 0.38
DEFAULT_RETENTION_DAYS = 30
MAX_RETENTION_DAYS = 3650
DEFAULT_DATA_CATEGORIES = ("decoded vehicle signals", "timestamps", "diagnostic findings")


def load_decoded_jsonl(path: str | Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with Path(path).open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            payload = json.loads(stripped)
            signals = payload.get("signals")
            if not isinstance(signals, dict):
                raise ValueError(f"{path}: line {line_no} is missing signals object")
            rows.append({"timestamp": float(payload.get("timestamp", line_no)), "signals": numeric_signals(signals)})
    return rows


def build_health_baseline(
    rows: list[dict[str, Any]],
    *,
    source: str | None = None,
    vehicle_profile: str | None = None,
    purpose: str,
    owner_consent: bool,
    consent_record: dict[str, Any] | None = None,
    retention_days: int = DEFAULT_RETENTION_DAYS,
) -> dict[str, Any]:
    _require_responsible_use(
        purpose=purpose,
        owner_consent=owner_consent,
        consent_record=consent_record,
        retention_days=retention_days,
    )
    by_state_signal = _bucket_values(rows)
    states: dict[str, Any] = {}
    for state, signals in sorted(by_state_signal.items()):
        state_signals = {}
        for signal, values in sorted(signals.items()):
            if len(values) >= MIN_BASELINE_SAMPLES:
                state_signals[signal] = summary_stats(values)
        if state_signals:
            states[state] = {"signals": state_signals}
    return {
        "version": 1,
        "kind": "can_health_baseline",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": {"decodedLog": source},
        "vehicleProfile": vehicle_profile,
        "responsibleUse": _responsible_use_payload(
            purpose=purpose,
            owner_consent=owner_consent,
            consent_record=consent_record,
            retention_days=retention_days,
        ),
        "stateRules": state_rules_description(),
        "minSamples": MIN_BASELINE_SAMPLES,
        "states": states,
    }


def diagnose_against_baseline(
    baseline: dict[str, Any],
    suspect_rows: list[dict[str, Any]],
    *,
    source: str | None = None,
    vehicle_profile: str | None = None,
    purpose: str,
    owner_consent: bool,
    consent_record: dict[str, Any] | None = None,
    retention_days: int = DEFAULT_RETENTION_DAYS,
) -> dict[str, Any]:
    _require_responsible_use(
        purpose=purpose,
        owner_consent=owner_consent,
        consent_record=consent_record,
        retention_days=retention_days,
    )
    if baseline.get("version") != 1 or baseline.get("kind") != "can_health_baseline":
        raise ValueError("baseline must be a can_health_baseline v1 document")
    by_state_signal = _bucket_values(suspect_rows)
    findings = []
    compared = 0
    for state, baseline_state in sorted(baseline.get("states", {}).items()):
        suspect_signals = by_state_signal.get(state, {})
        for signal, baseline_stats in sorted(baseline_state.get("signals", {}).items()):
            values = suspect_signals.get(signal, [])
            if len(values) < MIN_COMPARE_SAMPLES:
                continue
            compared += 1
            suspect_stats = summary_stats(values)
            finding = _compare_signal_state(signal, state, baseline_stats, suspect_stats, values)
            if finding and finding["severity"] >= ANOMALY_THRESHOLD:
                findings.append(finding)
    findings.sort(key=lambda item: (item["severity"], item["confidence"]), reverse=True)
    return {
        "version": 1,
        "kind": "can_health_diagnostic_report",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": {"decodedLog": source, "baselineGeneratedAt": baseline.get("generatedAt")},
        "vehicleProfile": vehicle_profile or baseline.get("vehicleProfile"),
        "responsibleUse": _responsible_use_payload(
            purpose=purpose,
            owner_consent=owner_consent,
            consent_record=consent_record,
            retention_days=retention_days,
        ),
        "summary": {
            "status": "anomalies_detected" if findings else "no_strong_anomalies",
            "comparedSignalStates": compared,
            "findingCount": len(findings),
            "topFinding": findings[0]["title"] if findings else None,
            "limitations": "This report ranks evidence for mechanic review; it is not a repair directive or safety certification.",
        },
        "findings": findings,
    }


def build_consent_record(
    *,
    owner_reference: str,
    vehicle_profile: str,
    purpose: str,
    owner_consent: bool,
    retention_days: int = DEFAULT_RETENTION_DAYS,
    data_categories: list[str] | None = None,
) -> dict[str, Any]:
    _require_responsible_use(
        purpose=purpose,
        owner_consent=owner_consent,
        consent_record=None,
        retention_days=retention_days,
    )
    if not owner_reference.strip():
        raise ValueError("owner reference must be a non-empty pseudonymous identifier")
    if not vehicle_profile.strip():
        raise ValueError("vehicle profile must be recorded")
    categories = data_categories or list(DEFAULT_DATA_CATEGORIES)
    return {
        "version": 1,
        "kind": "vehicle_diagnostic_consent",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "ownerReference": owner_reference,
        "vehicleProfile": vehicle_profile,
        "allowedPurposes": [purpose],
        "ownerConsentConfirmed": True,
        "readOnlyCaptureRequired": True,
        "dataCategories": categories,
        "retentionPolicy": _retention_policy(retention_days),
        "limitationsAcknowledged": [
            "The report is diagnostic evidence for mechanic review, not a repair directive.",
            "Vehicle data may include sensitive timestamps, driving behavior, and derived operating states.",
            "Data must not be reused or sold outside the allowed purpose without separate consent.",
        ],
    }


def load_consent_record(path: str | Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    return json.loads(Path(path).read_text(encoding="utf-8"))


def render_customer_report(report: dict[str, Any]) -> str:
    summary = report.get("summary", {})
    responsible_use = report.get("responsibleUse", {})
    lines = [
        "# Vehicle Diagnostic Evidence Report",
        "",
        f"Generated: {report.get('generatedAt', 'unknown')}",
        f"Vehicle profile: {report.get('vehicleProfile') or 'not recorded'}",
        f"Purpose: {responsible_use.get('purpose') or 'not recorded'}",
        f"Status: {summary.get('status', 'unknown')}",
        "",
        "This report ranks evidence for mechanic review. It is not a repair directive, safety certification, or substitute for service information, DTCs, freeze-frame data, and physical tests.",
        "",
        "## Responsible Use",
        "",
        f"- Owner consent confirmed: {bool(responsible_use.get('ownerConsentConfirmed'))}",
        f"- Read-only capture required: {bool(responsible_use.get('readOnlyCaptureRequired'))}",
        f"- Retention delete-after: {responsible_use.get('retentionPolicy', {}).get('deleteAfter', 'not recorded')}",
        "",
        "## Findings",
        "",
    ]
    findings = report.get("findings", [])
    if not findings:
        lines.extend(["No strong anomalies were detected in the compared signal states.", ""])
    for index, finding in enumerate(findings, start=1):
        evidence = finding.get("evidence", {})
        lines.extend(
            [
                f"### {index}. {finding.get('title', 'Finding')}",
                "",
                f"- Signal: {finding.get('signal')}",
                f"- Operating state: {finding.get('state')}",
                f"- Severity: {finding.get('severity')}",
                f"- Confidence: {finding.get('confidence')}",
                f"- Mean delta: {evidence.get('meanDelta')}",
                f"- Baseline envelope outside ratio: {evidence.get('outsideBaselineEnvelopeRatio')}",
                f"- Interpretation: {finding.get('interpretation')}",
                "- Next checks:",
            ]
        )
        for check in finding.get("nextChecks", []):
            lines.append(f"  - {check}")
        lines.extend(["", "Not a repair directive: true", ""])
    return "\n".join(lines).rstrip() + "\n"


def _bucket_values(rows: list[dict[str, Any]]) -> dict[str, dict[str, list[float]]]:
    buckets: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for row in rows:
        signals = row.get("signals", {})
        if not isinstance(signals, dict):
            continue
        state = operating_state(signals)
        for signal, value in numeric_signals(signals).items():
            buckets[state][signal].append(value)
    return buckets


def _compare_signal_state(
    signal: str,
    state: str,
    baseline_stats: dict[str, Any],
    suspect_stats: dict[str, Any],
    suspect_values: list[float],
) -> dict[str, Any] | None:
    baseline_stdev = max(float(baseline_stats.get("stdev", 0.0)), _signal_floor(signal))
    mean_delta = float(suspect_stats["mean"]) - float(baseline_stats["mean"])
    z_score = mean_delta / baseline_stdev
    tolerance = max(baseline_stdev * 3.0, _signal_floor(signal))
    low = float(baseline_stats["p05"]) - tolerance
    high = float(baseline_stats["p95"]) + tolerance
    outside_ratio = sum(value < low or value > high for value in suspect_values) / len(suspect_values)
    severity = clamp(max(abs(z_score) / 5.0, outside_ratio))
    sample_confidence = clamp(min(int(baseline_stats["count"]), int(suspect_stats["count"])) / 30.0)
    if severity < ANOMALY_THRESHOLD:
        return None
    direction = "high" if mean_delta > 0 else "low"
    return {
        "title": f"{signal} is {direction} in {state}",
        "signal": signal,
        "state": state,
        "severity": round(severity, 4),
        "confidence": round(sample_confidence, 4),
        "evidence": {
            "baseline": baseline_stats,
            "suspect": suspect_stats,
            "meanDelta": round(mean_delta, 6),
            "zScore": round(z_score, 4),
            "outsideBaselineEnvelopeRatio": round(outside_ratio, 4),
            "baselineEnvelope": {"low": round(low, 6), "high": round(high, 6)},
        },
        "interpretation": _interpretation(signal, direction, state),
        "nextChecks": _next_checks(signal, direction, state),
        "notRepairDirective": True,
    }


def _signal_floor(signal: str) -> float:
    floors = {
        "rpm": 75.0,
        "speedKph": 3.0,
        "coolantTempC": 3.0,
        "batteryVoltage": 0.25,
        "throttlePercent": 3.0,
        "fuelLevelPercent": 2.0,
    }
    return floors.get(signal, 1.0)


def _interpretation(signal: str, direction: str, state: str) -> str:
    if signal == "rpm" and state == "idle_stationary":
        return "Idle speed differs from the healthy baseline under a matched stationary condition."
    if signal == "rpm":
        return "Engine speed behavior differs from the healthy baseline for this operating state."
    if signal == "speedKph":
        return "Vehicle speed estimate differs from the healthy baseline; confirm the drive segment and speed source before diagnosing hardware."
    return "Signal behavior differs from the healthy baseline for this operating state."


def _next_checks(signal: str, direction: str, state: str) -> list[str]:
    if signal == "rpm" and state == "idle_stationary":
        if direction == "high":
            return ["Check for idle control, intake/vacuum leak, throttle adaptation, and relevant DTC/freeze-frame evidence."]
        return ["Check for misfire, fueling, air metering, compression, and relevant DTC/freeze-frame evidence."]
    if signal == "rpm":
        return ["Review DTCs/freeze-frame data and compare RPM/load/throttle relationships before recommending a repair."]
    if signal == "speedKph":
        return ["Confirm the test route and inspect wheel-speed/GPS/vehicle-speed source consistency."]
    return ["Review this signal with service data, DTCs, freeze-frame data, and direct physical tests."]


def _require_responsible_use(
    *,
    purpose: str,
    owner_consent: bool,
    consent_record: dict[str, Any] | None,
    retention_days: int,
) -> None:
    if not owner_consent:
        raise ValueError("owner consent must be confirmed before creating or comparing vehicle diagnostics")
    if not purpose.strip():
        raise ValueError("diagnostic purpose must be recorded")
    if not 1 <= int(retention_days) <= MAX_RETENTION_DAYS:
        raise ValueError(f"retention days must be between 1 and {MAX_RETENTION_DAYS}")
    if consent_record is not None:
        _validate_consent_record(consent_record, purpose=purpose)


def _responsible_use_payload(
    *,
    purpose: str,
    owner_consent: bool,
    consent_record: dict[str, Any] | None,
    retention_days: int,
) -> dict[str, Any]:
    return {
        "purpose": purpose,
        "ownerConsentConfirmed": owner_consent,
        "readOnlyCaptureRequired": True,
        "consentRecord": _consent_record_summary(consent_record),
        "retentionPolicy": _retention_policy(retention_days),
        "privacy": [
            "Minimize collection to diagnostic signals needed for the report.",
            "Treat VIN, location traces, timestamps, and driving behavior as sensitive owner data.",
            "Do not sell or reuse vehicle data outside the recorded purpose without separate consent.",
        ],
        "limitations": [
            "Baseline comparison ranks evidence; it does not identify a guaranteed root cause.",
            "Repair recommendations require DTCs, service information, and mechanic validation.",
            "Healthy baselines should match make, model, year, engine, trim, ECU calibration, and test conditions.",
        ],
    }


def _validate_consent_record(consent_record: dict[str, Any], *, purpose: str) -> None:
    if consent_record.get("version") != 1 or consent_record.get("kind") != "vehicle_diagnostic_consent":
        raise ValueError("consent record must be a vehicle_diagnostic_consent v1 document")
    if not consent_record.get("ownerConsentConfirmed"):
        raise ValueError("consent record does not confirm owner consent")
    allowed = consent_record.get("allowedPurposes", [])
    if purpose not in allowed:
        raise ValueError("diagnostic purpose is not allowed by the consent record")


def _consent_record_summary(consent_record: dict[str, Any] | None) -> dict[str, Any] | None:
    if consent_record is None:
        return None
    return {
        "version": consent_record.get("version"),
        "kind": consent_record.get("kind"),
        "generatedAt": consent_record.get("generatedAt"),
        "ownerReference": consent_record.get("ownerReference"),
        "vehicleProfile": consent_record.get("vehicleProfile"),
        "allowedPurposes": consent_record.get("allowedPurposes", []),
        "retentionPolicy": consent_record.get("retentionPolicy", {}),
    }


def _retention_policy(retention_days: int) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    delete_after = now + timedelta(days=int(retention_days))
    return {
        "retentionDays": int(retention_days),
        "deleteAfter": delete_after.isoformat(),
        "deleteOrReconfirmRequired": True,
    }
