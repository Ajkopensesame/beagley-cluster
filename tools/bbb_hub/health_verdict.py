from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Iterable

from tools.vehicle_analysis.context import operating_state
from tools.vehicle_analysis.findings import SEVERITY_ORDER, normalize_severity
from tools.vehicle_analysis.stats import clamp
from tools.vehicle_analysis.values import number_or_none


DIRECT_ANCHOR_NAMES = (
    "rpm",
    "speedKph",
    "coolantC",
    "mafGps",
    "throttlePct",
    "engineLoadPct",
    "intakeAirTempC",
    "mapKpa",
    "fuelPct",
    "controlModuleVoltage",
)

DEFAULT_EXPECTED_CONTEXTS = (
    "startup",
    "idle_stationary",
    "low_speed_drive",
    "road_speed_drive",
    "highway_speed_drive",
    "cold_start",
    "heavy_load",
)

ALLOWED_LANGUAGE = {
    "maySay": [
        "appears healthy",
        "probably healthy",
        "no strong anomalies were observed",
        "capture limited",
        "insufficient evidence",
        "anomaly likely",
        "anomaly detected in the captured conditions",
    ],
    "mustAvoid": [
        "guaranteed healthy",
        "fault free",
        "no problems exist",
        "definitely broken",
        "replace part X",
        "safe to operate",
    ],
    "mustIncludeLimitationsWhenPresent": True,
}


def build_vehicle_health_verdict(
    state: dict[str, Any],
    *,
    mode: str | None = None,
    vehicle_profile: str | None = None,
    capture_ref: dict[str, Any] | None = None,
    coverage: dict[str, Any] | None = None,
    baseline_snapshot: dict[str, Any] | None = None,
    direct_anchors: Iterable[str] | None = None,
    derived_anchors: Iterable[dict[str, Any]] | None = None,
    generated_at: str | None = None,
) -> dict[str, Any]:
    health = state.get("_health") if isinstance(state.get("_health"), dict) else {}
    diagnostic = state.get("_diagnostic") if isinstance(state.get("_diagnostic"), dict) else {}
    findings = [finding for finding in diagnostic.get("activeFindings", []) if isinstance(finding, dict)]
    worst_severity = _worst_severity(findings, fallback=diagnostic.get("severity"))
    capture_quality = _capture_quality_payload(state, diagnostic, health)
    coverage_payload = coverage or build_coverage_summary(
        observed_contexts=[operating_state(state)],
        source_coverage=summarize_source_coverage_series(
            {
                "gpsOk": [capture_quality.get("gpsOk")],
                "canOk": [capture_quality.get("canOk")],
                "serialOk": [capture_quality.get("serialOk")],
            }
        ),
        sample_counts={"frames": 1},
    )
    direct_anchor_list = sorted(set(direct_anchors or _direct_anchors_from_state(state)))
    derived_anchor_list = [dict(item) for item in (derived_anchors or []) if isinstance(item, dict)]
    baseline_health = _baseline_health(health, baseline_snapshot)

    source_health = _source_health(health)
    signal_health = _signal_health(health)
    transition_health = _transition_health(health)
    evidence_inputs = {
        "captureQuality": capture_quality,
        "findingSummary": {
            "worstSeverity": worst_severity,
            "activeFindingCount": len(findings),
            "codes": sorted({str(finding.get("code", "unknown")) for finding in findings}),
        },
        "sourceHealth": source_health,
        "signalHealth": signal_health,
        "transitionHealth": transition_health,
        "baselineHealth": baseline_health,
        "anchors": {
            "direct": direct_anchor_list,
            "derived": derived_anchor_list,
        },
    }

    source_trust, source_penalties = _source_trust(capture_quality)
    model_applicability, applicability_penalties = _model_applicability(
        vehicle_profile=vehicle_profile,
        baseline_health=baseline_health,
        transition_health=transition_health,
    )
    evidence_consistency = _evidence_consistency(worst_severity, findings, capture_quality)
    penalties = [
        *source_penalties,
        *applicability_penalties,
        *_coverage_penalties(coverage_payload),
    ]
    confidence_score = _confidence_score(
        source_trust=source_trust,
        coverage_confidence=number_or_none(coverage_payload.get("confidence")) or number_or_none(coverage_payload.get("score")) or 0.0,
        model_applicability=model_applicability,
        evidence_consistency=evidence_consistency,
        penalties=penalties,
    )
    abstain = _abstain(
        worst_severity=worst_severity,
        capture_quality=capture_quality,
        coverage=coverage_payload,
        confidence_score=confidence_score,
        model_applicability=model_applicability,
        baseline_health=baseline_health,
        transition_health=transition_health,
    )
    verdict = _verdict(
        worst_severity=worst_severity,
        capture_quality=capture_quality,
        coverage=coverage_payload,
        confidence_score=confidence_score,
        abstain=abstain,
    )
    limitations = _limitations(coverage_payload, penalties, capture_quality, baseline_health, transition_health)

    return {
        "version": 1,
        "kind": "vehicle_health_verdict",
        "generatedAt": generated_at or datetime.now(timezone.utc).isoformat(),
        "mode": str(mode or diagnostic.get("mode") or "normal").strip().lower(),
        "vehicleProfile": vehicle_profile,
        "captureRef": dict(capture_ref or {}),
        "verdict": verdict,
        "coverage": coverage_payload,
        "confidenceModel": {
            "score": confidence_score,
            "evidenceConsistency": round(evidence_consistency, 3),
            "sourceTrust": round(source_trust, 3),
            "modelApplicability": round(model_applicability, 3),
            "penalties": penalties,
        },
        "evidenceInputs": evidence_inputs,
        "abstain": abstain,
        "allowedLanguage": ALLOWED_LANGUAGE,
        "limitations": limitations,
    }


def build_coverage_summary(
    *,
    observed_contexts: Iterable[str],
    source_coverage: dict[str, str],
    sample_counts: dict[str, int] | None = None,
    expected_contexts: Iterable[str] = DEFAULT_EXPECTED_CONTEXTS,
    duration_sec: float | None = None,
) -> dict[str, Any]:
    observed = sorted({str(context) for context in observed_contexts if str(context).strip()})
    expected = [str(context) for context in expected_contexts]
    missing = [context for context in expected if context not in observed]
    sample_counts = dict(sample_counts or {})

    context_score = clamp(len(observed) / max(len(expected), 1))
    frame_score = clamp((number_or_none(sample_counts.get("frames")) or 0.0) / 100.0)
    duration_score = clamp((duration_sec or 0.0) / 300.0) if duration_sec is not None else frame_score
    source_score = _source_coverage_score(source_coverage)
    score = clamp((context_score * 0.45) + (max(frame_score, duration_score) * 0.35) + (source_score * 0.20))
    confidence = clamp((score * 0.70) + (source_score * 0.30))
    payload = {
        "score": round(score, 3),
        "confidence": round(confidence, 3),
        "observedContexts": observed,
        "missingContexts": missing,
        "sourceCoverage": source_coverage,
        "sampleCounts": sample_counts,
    }
    if duration_sec is not None:
        payload["durationSec"] = round(duration_sec, 3)
    return payload


def summarize_source_coverage_series(source_series: dict[str, list[bool | None]]) -> dict[str, str]:
    return {
        "can": _source_series_status(source_series.get("canOk", [])),
        "gps": _source_series_status(source_series.get("gpsOk", [])),
        "serial": _source_series_status(source_series.get("serialOk", [])),
    }


def _capture_quality_payload(state: dict[str, Any], diagnostic: dict[str, Any], health: dict[str, Any]) -> dict[str, Any]:
    if isinstance(diagnostic.get("captureQuality"), dict):
        payload = dict(diagnostic["captureQuality"])
        if not isinstance(state.get("gps"), dict):
            payload["gpsOk"] = None
        if not any(
            isinstance(health.get(key), dict) and bool(health.get(key).get("enabled"))
            for key in ("canLive", "canReplay", "canLiveDiagnostics", "canReplayDiagnostics")
        ):
            payload["canOk"] = None
        if not (
            isinstance(health.get("serialVehicleInputs"), dict)
            and bool(health.get("serialVehicleInputs").get("enabled"))
        ):
            payload["serialOk"] = None
        return payload
    gps = state.get("gps") if isinstance(state.get("gps"), dict) else {}
    return {
        "gpsOk": bool(gps.get("fixValid", False)) and not bool(health.get("gpsStale", False)),
        "canOk": None,
        "serialOk": None,
        "linkStale": bool(health.get("stale", False)),
    }


def _baseline_health(health: dict[str, Any], baseline_snapshot: dict[str, Any] | None) -> dict[str, Any]:
    current = health.get("vehicleBaseline") if isinstance(health.get("vehicleBaseline"), dict) else {}
    snapshot = baseline_snapshot if isinstance(baseline_snapshot, dict) else current
    models = snapshot.get("models", []) if isinstance(snapshot.get("models"), list) else []
    ready_models = [str(model.get("name")) for model in models if isinstance(model, dict) and model.get("ready")]
    return {
        "enabled": bool(snapshot.get("enabled", current.get("enabled", False))),
        "readyModels": ready_models,
        "anomalyCount": len(current.get("findings", [])) if isinstance(current.get("findings"), list) else 0,
        "modelCount": len(models),
    }


def _transition_health(health: dict[str, Any]) -> dict[str, Any]:
    current = health.get("transitionMonitor") if isinstance(health.get("transitionMonitor"), dict) else {}
    models = current.get("models", []) if isinstance(current.get("models"), list) else []
    ready_models = [str(model.get("name")) for model in models if isinstance(model, dict) and model.get("ready")]
    coverage = current.get("coverage") if isinstance(current.get("coverage"), dict) else {}
    return {
        "enabled": bool(current.get("enabled", False)),
        "readyModels": ready_models,
        "anomalyCount": len(current.get("findings", [])) if isinstance(current.get("findings"), list) else 0,
        "modelCount": len(models),
        "windowsScored": int(number_or_none(coverage.get("windowsScored")) or 0),
        "windowsLearned": int(number_or_none(coverage.get("windowsLearned")) or 0),
    }


def _source_health(health: dict[str, Any]) -> dict[str, Any]:
    diagnostics: list[dict[str, Any]] = []
    for key in ("canLiveDiagnostics", "canReplayDiagnostics"):
        payload = health.get(key)
        if isinstance(payload, dict):
            diagnostics.extend(item for item in payload.get("findings", []) if isinstance(item, dict))
    signal_faults = [item for item in health.get("signalFaults", []) if isinstance(item, dict)]
    codes = [str(item.get("code", "")) for item in diagnostics + signal_faults]
    return {
        "busSilenceSeen": "bus_silence" in codes,
        "canIdDropouts": codes.count("can_id_dropout"),
        "payloadStuckEvents": codes.count("payload_stuck"),
        "decodedSignalStuckEvents": codes.count("decoded_signal_stuck"),
    }


def _signal_health(health: dict[str, Any]) -> dict[str, Any]:
    faults = [item for item in health.get("signalFaults", []) if isinstance(item, dict)]
    codes = [str(item.get("code", "")) for item in faults]
    return {
        "outOfRangeEvents": codes.count("out_of_range"),
        "impossibleJumpEvents": codes.count("impossible_jump"),
        "sourceDisagreementEvents": codes.count("source_disagreement"),
        "noisyOrFlappingEvents": codes.count("noisy_or_flapping"),
        "sourceStaleEvents": codes.count("source_stale"),
    }


def _direct_anchors_from_state(state: dict[str, Any]) -> list[str]:
    anchors: list[str] = []
    for name in DIRECT_ANCHOR_NAMES:
        if number_or_none(state.get(name)) is not None:
            anchors.append(name)
    gps = state.get("gps") if isinstance(state.get("gps"), dict) else {}
    if number_or_none(gps.get("speedKph")) is not None:
        anchors.append("gpsSpeedKph")
    return anchors


def _source_trust(capture_quality: dict[str, Any]) -> tuple[float, list[dict[str, Any]]]:
    penalties: list[dict[str, Any]] = []
    scores: list[float] = []
    if capture_quality.get("linkStale"):
        penalties.append(
            {"code": "health_stale", "weight": 0.25, "message": "Vehicle link or upstream health was stale during the verdict"}
        )
        scores.append(0.0)
    else:
        scores.append(1.0)
    degraded = False
    for key in ("gpsOk", "canOk", "serialOk"):
        value = capture_quality.get(key)
        if value is None:
            continue
        scores.append(1.0 if value else 0.0)
        degraded = degraded or value is False
    if degraded:
        penalties.append(
            {"code": "capture_degraded", "weight": 0.12, "message": "One or more configured capture sources were degraded"}
        )
    return round(sum(scores) / len(scores), 3) if scores else 0.6, penalties


def _model_applicability(
    *,
    vehicle_profile: str | None,
    baseline_health: dict[str, Any],
    transition_health: dict[str, Any],
) -> tuple[float, list[dict[str, Any]]]:
    penalties: list[dict[str, Any]] = []
    score = 0.70
    if vehicle_profile:
        score += 0.10
    else:
        penalties.append(
            {"code": "vehicle_profile_unknown", "weight": 0.06, "message": "Vehicle profile or decoder context was not recorded"}
        )
    if baseline_health.get("enabled"):
        model_count = max(int(baseline_health.get("modelCount", 0)), 1)
        ready_count = len(baseline_health.get("readyModels", []))
        ready_ratio = ready_count / model_count
        score += ready_ratio * 0.12
        if ready_count == 0:
            penalties.append(
                {"code": "baseline_not_ready", "weight": 0.08, "message": "Learned baseline models were not ready for this verdict"}
            )
    if transition_health.get("enabled"):
        model_count = max(int(transition_health.get("modelCount", 0)), 1)
        ready_count = len(transition_health.get("readyModels", []))
        score += (ready_count / model_count) * 0.08
        if ready_count == 0:
            penalties.append(
                {"code": "transition_baseline_not_ready", "weight": 0.06, "message": "Transition baseline models were not ready for this verdict"}
            )
    return round(clamp(score), 3), penalties


def _evidence_consistency(worst_severity: str, findings: list[dict[str, Any]], capture_quality: dict[str, Any]) -> float:
    if capture_quality.get("linkStale"):
        return 0.35
    finding_count = len(findings)
    if worst_severity == "error":
        return 0.90 if finding_count > 1 else 0.84
    if worst_severity == "warning":
        return 0.88 if finding_count > 1 else 0.80
    if worst_severity == "info":
        return 0.70
    return 0.92


def _coverage_penalties(coverage: dict[str, Any]) -> list[dict[str, Any]]:
    penalties: list[dict[str, Any]] = []
    score = number_or_none(coverage.get("score")) or 0.0
    missing = {str(item) for item in coverage.get("missingContexts", [])}
    if score < 0.45:
        penalties.append({"code": "coverage_too_low", "weight": 0.18, "message": "Observed operating coverage was too narrow for a strong health claim"})
    elif score < 0.70:
        penalties.append({"code": "coverage_partial", "weight": 0.08, "message": "Observed operating coverage was only partial"})
    if "cold_start" in missing:
        penalties.append({"code": "missing_cold_start", "weight": 0.05, "message": "No cold-start evidence was captured"})
    if "heavy_load" in missing:
        penalties.append({"code": "missing_heavy_load", "weight": 0.04, "message": "No heavy-load evidence was captured"})
    return penalties


def _confidence_score(
    *,
    source_trust: float,
    coverage_confidence: float,
    model_applicability: float,
    evidence_consistency: float,
    penalties: list[dict[str, Any]],
) -> float:
    base = (
        source_trust * 0.40
        + coverage_confidence * 0.25
        + model_applicability * 0.20
        + evidence_consistency * 0.15
    )
    penalty_total = sum(number_or_none(item.get("weight")) or 0.0 for item in penalties)
    return round(clamp(base - penalty_total), 3)


def _abstain(
    *,
    worst_severity: str,
    capture_quality: dict[str, Any],
    coverage: dict[str, Any],
    confidence_score: float,
    model_applicability: float,
    baseline_health: dict[str, Any],
    transition_health: dict[str, Any],
) -> dict[str, Any]:
    reasons: list[str] = []
    strong_anomaly = worst_severity in {"warning", "error"}
    if capture_quality.get("linkStale"):
        reasons.append("health_stale")
    configured_source_values = [capture_quality.get(key) for key in ("gpsOk", "canOk", "serialOk") if capture_quality.get(key) is not None]
    if any(value is False for value in configured_source_values):
        reasons.append("capture_degraded")
    if not strong_anomaly:
        if (number_or_none(coverage.get("score")) or 0.0) < 0.45:
            reasons.append("coverage_too_low")
        if confidence_score < 0.55:
            reasons.append("confidence_too_low")
        if model_applicability < 0.45:
            reasons.append("vehicle_profile_unknown")
        if baseline_health.get("enabled") and not baseline_health.get("readyModels"):
            reasons.append("baseline_not_ready")
        if transition_health.get("enabled") and not transition_health.get("readyModels"):
            reasons.append("transition_baseline_not_ready")
    required = bool(reasons)
    if not required:
        return {"required": False, "reasons": [], "recommendedLabel": None}
    recommended = "capture_limited" if {"health_stale", "capture_degraded"} & set(reasons) else "insufficient_evidence"
    return {
        "required": True,
        "reasons": reasons,
        "recommendedLabel": recommended,
    }


def _verdict(
    *,
    worst_severity: str,
    capture_quality: dict[str, Any],
    coverage: dict[str, Any],
    confidence_score: float,
    abstain: dict[str, Any],
) -> dict[str, Any]:
    if abstain.get("required"):
        label = str(abstain.get("recommendedLabel") or "insufficient_evidence")
    elif worst_severity == "error":
        label = "anomaly_detected"
    elif worst_severity == "warning":
        label = "anomaly_likely"
    elif confidence_score >= 0.90 and (number_or_none(coverage.get("score")) or 0.0) >= 0.90:
        label = "healthy"
    else:
        label = "probably_healthy"

    if label == "healthy":
        summary = "No strong anomalies were observed in the captured conditions"
        ok: bool | None = True
    elif label == "probably_healthy":
        summary = "Vehicle appears healthy in the captured conditions"
        ok = True
    elif label == "capture_limited":
        summary = "Capture quality was limited; health judgment is restricted"
        ok = None
    elif label == "insufficient_evidence":
        summary = "Not enough evidence was captured to judge vehicle health"
        ok = None
    elif label == "anomaly_likely":
        summary = "Observed evidence suggests abnormal vehicle behavior"
        ok = False
    else:
        summary = "Strong anomaly evidence was observed in the captured conditions"
        ok = False

    if capture_quality.get("linkStale") and label not in {"capture_limited", "insufficient_evidence"}:
        label = "capture_limited"
        summary = "Capture quality was limited; health judgment is restricted"
        ok = None
    return {"label": label, "summary": summary, "ok": ok}


def _limitations(
    coverage: dict[str, Any],
    penalties: list[dict[str, Any]],
    capture_quality: dict[str, Any],
    baseline_health: dict[str, Any],
    transition_health: dict[str, Any],
) -> list[str]:
    limitations: list[str] = []
    seen: set[str] = set()
    for penalty in penalties:
        message = str(penalty.get("message") or "").strip()
        if message and message not in seen:
            seen.add(message)
            limitations.append(message)
    if capture_quality.get("linkStale"):
        limitations.append("Vehicle link or upstream source was stale during part of the capture")
    if baseline_health.get("enabled") and not baseline_health.get("readyModels"):
        limitations.append("Learned baseline models were not fully ready")
    if transition_health.get("enabled") and not transition_health.get("readyModels"):
        limitations.append("Transition baseline models were not fully ready")
    if not limitations and (number_or_none(coverage.get("score")) or 0.0) < 0.90:
        limitations.append("Observed conditions were narrower than a full health assessment")
    return limitations[:6]


def _source_series_status(values: list[bool | None]) -> str:
    known = [value for value in values if value is not None]
    if not known:
        return "not_used"
    if all(value is True for value in known):
        return "good"
    if all(value is False for value in known):
        return "degraded"
    return "partial"


def _source_coverage_score(source_coverage: dict[str, str]) -> float:
    mapped = {
        "good": 1.0,
        "partial": 0.6,
        "degraded": 0.2,
        "not_used": 0.5,
    }
    values = [mapped.get(str(status), 0.5) for status in source_coverage.values()]
    return round(sum(values) / len(values), 3) if values else 0.5


def _worst_severity(findings: list[dict[str, Any]], *, fallback: Any = None) -> str:
    worst = normalize_severity(fallback)
    for finding in findings:
        severity = normalize_severity(finding.get("severity"))
        if SEVERITY_ORDER[severity] > SEVERITY_ORDER[worst]:
            worst = severity
    return worst
