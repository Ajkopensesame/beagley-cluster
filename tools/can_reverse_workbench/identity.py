from __future__ import annotations

import json
import math
import os
import shlex
import subprocess
from collections import Counter
from dataclasses import asdict
from datetime import datetime, timezone
from typing import Any

from tools.vehicle_analysis.stats import clamp, stddev, value_range

from .discovery import (
    CandidateSpec,
    format_can_id,
    _anti_counter_score,
    _candidate_series,
    _correlation,
    _enumerate_specs,
    _group_frames,
    _interpolate_value,
    _refresh_score,
    _sample_rate,
    _smoothness_score,
)
from .labels import GuidedSession
from .parser import CanFrame, ParseStats


HYPOTHESIS_CLASSES = {
    "switch",
    "state_enum",
    "continuous_sensor",
    "speed_like",
    "rpm_like",
    "pressure_like",
    "temperature_like",
    "percentage_like",
    "voltage_like",
    "airflow_like",
    "gear_or_ratio",
    "warning_lamp",
    "counter",
    "checksum_or_crc",
    "unknown",
}
LOW_TRUST_ALLOWED_USES = ["diagnostic_low_trust"]
LOW_TRUST_BLOCKED_USES = ["cluster_display", "authoritative_health_verdict"]
AI_COMMAND_ENV = "SIGNAL_IDENTITY_AI_COMMAND"


def build_signal_identity_report(
    frames: list[CanFrame] | None = None,
    *,
    session: GuidedSession | None = None,
    decoded_rows: list[dict[str, Any]] | None = None,
    parse_stats: ParseStats | None = None,
    source: dict[str, Any] | None = None,
    max_candidates: int = 50,
    ai_command: str | None = None,
) -> dict[str, Any]:
    """Rank unknown raw CAN fields and suggest low-trust diagnostic identities."""
    frames = frames or []
    session = session or GuidedSession.empty()
    decoded_rows = decoded_rows or []
    decoded_series = _decoded_signal_series(decoded_rows)
    frame_groups = _group_frames(frames) if frames else {}
    hypotheses: list[dict[str, Any]] = []

    for can_id, group in sorted(frame_groups.items()):
        for spec in _enumerate_specs(can_id, group):
            raw_series = _candidate_series(group, spec)
            if not _passes_identity_candidate_filters(raw_series):
                continue
            evidence = _candidate_evidence(spec, raw_series, session, decoded_series, len(group))
            suggestion = _deterministic_suggestion(spec, evidence)
            safety = _safety_policy(suggestion["class"], suggestion["confidence"], evidence)
            hypotheses.append(
                {
                    "candidateId": spec.candidate_id,
                    "canId": format_can_id(spec.can_id),
                    "canIdInt": spec.can_id,
                    "startBit": spec.start_bit,
                    "byteIndex": spec.byte_index,
                    "length": spec.length,
                    "endian": spec.endian,
                    "signed": spec.signed,
                    "suggested": suggestion,
                    "evidence": evidence,
                    "safety": safety,
                }
            )

    hypotheses = _select_report_hypotheses(hypotheses, max_candidates)
    ai_result = _maybe_apply_ai_suggestions(hypotheses, ai_command or os.getenv(AI_COMMAND_ENV))
    return {
        "version": 1,
        "schema": "signal_identity_hypothesis_report_v1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": source or {},
        "inputs": {
            "rawCan": bool(frames),
            "guidedAnchors": bool(session.anchors),
            "guidedWindows": bool(session.windows),
            "decodedVehicleState": bool(decoded_rows),
        },
        "policy": {
            "canSignalsUnchanged": True,
            "verifiedReservedForCanSignalsExport": True,
            "autoPromotionStatus": "probable",
            "autoPromotionUse": "diagnostic_low_trust",
            "blockedUses": LOW_TRUST_BLOCKED_USES,
            "aiMayNameButNotPromote": True,
        },
        "frameStats": _frame_stats(frames, parse_stats),
        "anchorSummary": _anchor_summary(session),
        "decodedSignalSummary": _decoded_summary(decoded_series),
        "ai": ai_result,
        "summary": _report_summary(hypotheses),
        "hypotheses": hypotheses,
    }


def build_diagnostic_candidate_signals(report: dict[str, Any]) -> dict[str, Any]:
    """Export probable hypotheses as low-trust diagnostic experiment inputs only."""
    candidates: dict[str, dict[str, Any]] = {}
    used_names: set[str] = set()
    for hypothesis in _dedupe_probable_export_hypotheses(report.get("hypotheses", [])):
        suggested = hypothesis.get("suggested", {})
        safety = hypothesis.get("safety", {})
        name = _unique_name(str(suggested.get("name") or "can_signal_candidate"), used_names)
        candidates[name] = {
            "candidateId": hypothesis.get("candidateId"),
            "canId": hypothesis.get("canId"),
            "startBit": hypothesis.get("startBit"),
            "length": hypothesis.get("length"),
            "endian": hypothesis.get("endian"),
            "signed": hypothesis.get("signed"),
            "scale": 1.0,
            "offset": 0.0,
            "unit": "raw",
            "suggestedClass": suggested.get("class"),
            "confidence": suggested.get("confidence", 0.0),
            "promotionStatus": safety.get("promotionStatus"),
            "trust": "low",
            "allowedUses": safety.get("allowedUses", []),
            "blockedUses": safety.get("blockedUses", LOW_TRUST_BLOCKED_USES),
            "evidence": _export_evidence(hypothesis.get("evidence", {})),
        }
    return {
        "version": 1,
        "kind": "diagnostic_candidate_signals",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceReportGeneratedAt": report.get("generatedAt"),
        "source": report.get("source", {}),
        "exportPolicy": {
            "requiresPromotionStatus": "probable",
            "trust": "low",
            "allowedUses": LOW_TRUST_ALLOWED_USES,
            "blockedUses": LOW_TRUST_BLOCKED_USES,
            "mustNotMergeIntoCanSignals": True,
            "mustNotDriveClusterDisplay": True,
            "mustNotBeSoleHealthVerdictEvidence": True,
        },
        "candidates": candidates,
    }


def _dedupe_probable_export_hypotheses(hypotheses: list[Any]) -> list[dict[str, Any]]:
    probable = [
        item
        for item in hypotheses
        if isinstance(item, dict)
        and item.get("safety", {}).get("promotionStatus") == "probable"
        and item.get("safety", {}).get("safeToUse", False)
    ]
    probable.sort(key=_export_preference_key, reverse=True)
    selected: list[dict[str, Any]] = []
    for hypothesis in probable:
        if any(_same_export_identity(hypothesis, existing) for existing in selected):
            continue
        selected.append(hypothesis)
    return selected


def _export_preference_key(hypothesis: dict[str, Any]) -> tuple[int, int, int, float, float, int, float, float]:
    evidence = hypothesis.get("evidence", {})
    start_bit = int(hypothesis.get("startBit", 0))
    length = int(hypothesis.get("length", 0))
    byte_aligned = 1 if start_bit % 8 == 0 and length in {8, 16, 24, 32} else 0
    unsigned = 1 if not hypothesis.get("signed", False) else 0
    return (
        byte_aligned,
        unsigned,
        int(evidence.get("uniqueCount", 0)),
        float(evidence.get("bestCorrelationScore", 0.0)),
        float(hypothesis.get("suggested", {}).get("confidence", 0.0)),
        -length,
        _export_field_economy(hypothesis),
        float(evidence.get("range", 0.0)),
    )


def _export_field_economy(hypothesis: dict[str, Any]) -> float:
    evidence = hypothesis.get("evidence", {})
    raw_range = max(float(evidence.get("range", 0.0)), 0.0)
    length = max(int(hypothesis.get("length", 0)), 1)
    bits_needed = max(1, math.ceil(math.log2(raw_range + 1.0)))
    surplus = max(0, length - bits_needed - 2)
    return clamp(1.0 - surplus / length)


def _same_export_identity(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left.get("canId") != right.get("canId"):
        return False
    if left.get("suggested", {}).get("class") != right.get("suggested", {}).get("class"):
        return False
    if _primary_evidence_key(left) != _primary_evidence_key(right):
        return False
    return _bit_ranges_overlap(left, right)


def _primary_evidence_key(hypothesis: dict[str, Any]) -> tuple[str, str]:
    evidence = hypothesis.get("evidence", {})
    best = _best_correlation(evidence)
    if best:
        return ("correlation", str(best.get("signal", "")))
    responses = evidence.get("eventResponses", [])
    if responses:
        return ("event", str(responses[0].get("label", "")))
    return ("class", str(hypothesis.get("suggested", {}).get("class", "")))


def _bit_ranges_overlap(left: dict[str, Any], right: dict[str, Any]) -> bool:
    left_start = int(left.get("startBit", 0))
    left_end = left_start + int(left.get("length", 0))
    right_start = int(right.get("startBit", 0))
    right_end = right_start + int(right.get("length", 0))
    return max(left_start, right_start) < min(left_end, right_end)


def _passes_identity_candidate_filters(series: list[tuple[float, float]]) -> bool:
    if len(series) < 8:
        return False
    values = [value for _, value in series]
    return max(values) > min(values) and len(set(values)) >= 2


def _candidate_evidence(
    spec: CandidateSpec,
    raw_series: list[tuple[float, float]],
    session: GuidedSession,
    decoded_series: dict[str, list[tuple[float, float]]],
    id_frame_count: int,
) -> dict[str, Any]:
    values = [value for _, value in raw_series]
    unique_count = len(set(values))
    raw_range = value_range(values)
    counter_score = clamp(1.0 - _anti_counter_score(raw_series, spec.length))
    smoothness_score = _smoothness_score(raw_series)
    refresh_score = _refresh_score(raw_series)
    entropy = _normalized_entropy(values, spec.length)
    switch_score = _switch_score(values, raw_series)
    cardinality_ratio = unique_count / max(len(values), 1)
    monotonic_score = _monotonic_score(values, spec.length)
    correlations = _correlations(raw_series, session, decoded_series)
    event_responses = _event_responses(raw_series, session)
    best_correlation = max((abs(item["correlation"]) * item["coverage"] for item in correlations), default=0.0)
    best_event = max((item["score"] for item in event_responses), default=0.0)
    checksum_score = _checksum_score(
        length=spec.length,
        unique_count=unique_count,
        sample_count=len(values),
        entropy=entropy,
        smoothness_score=smoothness_score,
        best_correlation=best_correlation,
        counter_score=counter_score,
        switch_score=switch_score,
    )
    return {
        "frameCount": len(raw_series),
        "idFrameCount": id_frame_count,
        "sampleHz": round(_sample_rate(raw_series), 3),
        "rawMin": min(values),
        "rawMax": max(values),
        "range": raw_range,
        "uniqueCount": unique_count,
        "cardinalityRatio": round(cardinality_ratio, 4),
        "entropy": round(entropy, 4),
        "monotonicity": round(monotonic_score, 4),
        "switchScore": round(switch_score, 4),
        "smoothnessScore": round(smoothness_score, 4),
        "refreshScore": round(refresh_score, 4),
        "correlations": correlations[:8],
        "eventResponses": event_responses[:8],
        "decodedCorroboration": [item for item in correlations if item["source"] == "decoded_signal"][:6],
        "counterScore": round(counter_score, 4),
        "checksumScore": round(checksum_score, 4),
        "bestCorrelationScore": round(best_correlation, 4),
        "bestEventScore": round(best_event, 4),
        "seriesPreview": _series_preview(raw_series),
    }


def _deterministic_suggestion(spec: CandidateSpec, evidence: dict[str, Any]) -> dict[str, Any]:
    candidate_class, class_reason = _classify_candidate(evidence)
    confidence = _deterministic_confidence(candidate_class, evidence)
    return {
        "name": _suggested_name(candidate_class, evidence, spec),
        "class": candidate_class,
        "source": "deterministic",
        "confidence": round(confidence, 4),
        "rationale": class_reason,
    }


def _classify_candidate(evidence: dict[str, Any]) -> tuple[str, str]:
    if evidence["counterScore"] >= 0.76:
        return "counter", "field increments like a rolling counter"
    if evidence["checksumScore"] >= 0.66:
        return "checksum_or_crc", "high-entropy field without useful anchor or event behavior"

    best = _best_correlation(evidence)
    best_signal = str(best.get("signal", "")) if best else ""
    best_corr_score = abs(float(best.get("correlation", 0.0))) * float(best.get("coverage", 0.0)) if best else 0.0
    if best_corr_score >= 0.78:
        mapped = _class_for_signal_name(best_signal)
        if mapped:
            return mapped, f"tracks {best_signal} with lagged correlation"

    if evidence["switchScore"] >= 0.78:
        if _warning_lamp_like(evidence):
            return "warning_lamp", "two-state field changes during warning/indicator windows"
        return "switch", "two-state field with meaningful transitions"
    if evidence["uniqueCount"] <= 8 and evidence["cardinalityRatio"] <= 0.22:
        if _gear_like(evidence):
            return "gear_or_ratio", "small discrete set changes with speed/rpm/load context"
        return "state_enum", "small discrete value set"
    if evidence["smoothnessScore"] >= 0.48 and evidence["range"] > 0:
        return "continuous_sensor", "continuous field with plausible smoothness and variation"
    return "unknown", "insufficient deterministic evidence for a useful identity"


def _deterministic_confidence(candidate_class: str, evidence: dict[str, Any]) -> float:
    if candidate_class == "counter":
        return evidence["counterScore"]
    if candidate_class == "checksum_or_crc":
        return evidence["checksumScore"]
    best_corr = evidence["bestCorrelationScore"]
    best_event = evidence["bestEventScore"]
    sample_score = clamp(evidence["sampleHz"] / 10.0)
    anti_counter = 1.0 - evidence["counterScore"]
    anti_checksum = 1.0 - evidence["checksumScore"]
    variation_score = 1.0 if evidence["range"] > 0 else 0.0
    if candidate_class in {"switch", "warning_lamp"}:
        score = (
            0.30 * evidence["switchScore"]
            + 0.26 * best_event
            + 0.16 * sample_score
            + 0.14 * anti_counter
            + 0.14 * anti_checksum
        )
    elif candidate_class in {"speed_like", "rpm_like", "pressure_like", "temperature_like", "percentage_like", "voltage_like", "airflow_like"}:
        score = (
            0.46 * best_corr
            + 0.17 * evidence["smoothnessScore"]
            + 0.13 * sample_score
            + 0.11 * anti_counter
            + 0.08 * anti_checksum
            + 0.05 * variation_score
        )
    elif candidate_class in {"state_enum", "gear_or_ratio"}:
        score = (
            0.26 * (1.0 - evidence["cardinalityRatio"])
            + 0.22 * best_event
            + 0.18 * best_corr
            + 0.14 * sample_score
            + 0.10 * anti_counter
            + 0.10 * anti_checksum
        )
    elif candidate_class == "continuous_sensor":
        score = (
            0.28 * evidence["smoothnessScore"]
            + 0.24 * best_corr
            + 0.14 * best_event
            + 0.14 * sample_score
            + 0.10 * anti_counter
            + 0.10 * anti_checksum
        )
    else:
        score = 0.22 * best_corr + 0.18 * best_event + 0.10 * sample_score
    return clamp(score)


def _safety_policy(candidate_class: str, confidence: float, evidence: dict[str, Any]) -> dict[str, Any]:
    reasons: list[str] = []
    if candidate_class in {"counter", "checksum_or_crc"}:
        status = "rejected"
        reasons.append(f"{candidate_class} fields are not diagnostic sensor inputs")
    elif evidence["counterScore"] >= 0.70:
        status = "rejected"
        reasons.append("counter-like behavior overrides identity guess")
    elif evidence["checksumScore"] >= 0.78:
        status = "rejected"
        reasons.append("checksum/noise behavior overrides identity guess")
    elif candidate_class == "unknown":
        status = "unknown"
        reasons.append("no useful deterministic identity")
    elif confidence >= 0.78 and _has_promotable_evidence(evidence):
        status = "probable"
        reasons.append("strong deterministic evidence; low-trust diagnostic export allowed")
    elif confidence >= 0.42:
        status = "candidate"
        reasons.append("interesting signal, but not strong enough for auto-export")
    else:
        status = "unknown"
        reasons.append("confidence below candidate threshold")

    safe = status == "probable"
    return {
        "promotionStatus": status,
        "safeToUse": safe,
        "trust": "low" if safe else "none",
        "allowedUses": LOW_TRUST_ALLOWED_USES if safe else [],
        "blockedUses": LOW_TRUST_BLOCKED_USES,
        "rules": [
            "never merge hypotheses into can_signals.json",
            "never use a hypothesis for cluster display fields",
            "never use a hypothesis as sole evidence for a health verdict",
        ],
        "reason": "; ".join(reasons),
    }


def _has_promotable_evidence(evidence: dict[str, Any]) -> bool:
    return evidence["bestCorrelationScore"] >= 0.78 or evidence["bestEventScore"] >= 0.82


def _correlations(
    raw_series: list[tuple[float, float]],
    session: GuidedSession,
    decoded_series: dict[str, list[tuple[float, float]]],
) -> list[dict[str, Any]]:
    correlations: list[dict[str, Any]] = []
    for signal, anchors in sorted(session.anchors.items()):
        target_series = [(point.timestamp, point.value) for point in anchors]
        result = _best_lagged_correlation(raw_series, target_series)
        if result:
            correlations.append({"signal": signal, "source": "guided_anchor", **result})
    for signal, series in sorted(decoded_series.items()):
        result = _best_lagged_correlation(raw_series, series)
        if result:
            correlations.append({"signal": signal, "source": "decoded_signal", **result})
    correlations.sort(key=lambda item: abs(item["correlation"]) * item["coverage"], reverse=True)
    return correlations


def _best_lagged_correlation(
    raw_series: list[tuple[float, float]],
    target_series: list[tuple[float, float]],
) -> dict[str, Any] | None:
    if len(raw_series) < 3 or len(target_series) < 3:
        return None
    best: dict[str, Any] | None = None
    for lag in _correlation_lags(len(target_series)):
        pairs: list[tuple[float, float]] = []
        for timestamp, target_value in target_series:
            raw_value = _interpolate_value(raw_series, timestamp + lag)
            if raw_value is not None:
                pairs.append((raw_value, target_value))
        if len(pairs) < 3:
            continue
        corr = _correlation([raw for raw, _ in pairs], [value for _, value in pairs])
        result = {
            "correlation": round(corr, 4),
            "lagSec": lag,
            "samples": len(pairs),
            "coverage": round(clamp(len(pairs) / max(len(target_series), 1)), 4),
        }
        if best is None or abs(result["correlation"]) * result["coverage"] > abs(best["correlation"]) * best["coverage"]:
            best = result
    if best is None or abs(best["correlation"]) < 0.20:
        return None
    return best


def _correlation_lags(sample_count: int) -> list[float]:
    if sample_count < 6:
        return [0.0]
    return [round(index * 0.1, 6) for index in range(-10, 11)]


def _event_responses(raw_series: list[tuple[float, float]], session: GuidedSession) -> list[dict[str, Any]]:
    if not session.windows:
        return []
    values = [value for _, value in raw_series]
    raw_range = max(value_range(values), 1.0)
    responses: list[dict[str, Any]] = []
    for window in session.windows:
        subset = [(timestamp, value) for timestamp, value in raw_series if window.start <= timestamp <= window.end]
        if len(subset) < 2:
            continue
        outside = [
            value
            for timestamp, value in raw_series
            if window.start - 3.0 <= timestamp <= window.end + 3.0 and not window.start <= timestamp <= window.end
        ]
        subset_values = [value for _, value in subset]
        outside_mean = _mean(outside) if outside else _mean(values)
        inside_mean = _mean(subset_values)
        delta = inside_mean - outside_mean
        delta_score = clamp(abs(delta) / raw_range)
        trend_score = _trend_event_score(subset, window.trend)
        label_score = _label_event_score(window.label, subset_values, outside, raw_range)
        score = max(delta_score, trend_score, label_score)
        if score < 0.18:
            continue
        responses.append(
            {
                "label": window.label,
                "target": window.target,
                "trend": window.trend,
                "samples": len(subset),
                "mean": round(inside_mean, 4),
                "outsideMean": round(outside_mean, 4),
                "delta": round(delta, 4),
                "score": round(score, 4),
            }
        )
    responses.sort(key=lambda item: item["score"], reverse=True)
    return responses


def _trend_event_score(subset: list[tuple[float, float]], trend: str | None) -> float:
    if not trend:
        return 0.0
    corr = _correlation([timestamp for timestamp, _ in subset], [value for _, value in subset])
    trend_key = trend.lower()
    if trend_key in {"increasing", "up", "rise", "rising"}:
        return clamp((corr + 1.0) / 2.0)
    if trend_key in {"decreasing", "down", "fall", "falling"}:
        return clamp((1.0 - corr) / 2.0)
    if trend_key in {"stable", "flat"}:
        return clamp(1.0 - stddev([value for _, value in subset]) / max(value_range([value for _, value in subset]), 1.0))
    return 0.0


def _label_event_score(label: str, inside_values: list[float], outside_values: list[float], raw_range: float) -> float:
    label_key = label.strip().lower()
    if label_key not in {"brake", "decelerate", "deceleration", "throttle_tip_in", "shift", "fan_on", "warning", "lamp"}:
        return 0.0
    if not outside_values:
        return 0.0
    return clamp(abs(_mean(inside_values) - _mean(outside_values)) / max(raw_range, 1.0))


def _switch_score(values: list[float], series: list[tuple[float, float]]) -> float:
    unique_values = sorted(set(values))
    if len(unique_values) > 4:
        return 0.0
    transitions = sum(1 for current, previous in zip(values[1:], values[:-1]) if current != previous)
    if transitions == 0:
        return 0.0
    binary_score = 1.0 if len(unique_values) == 2 else 0.74
    active_balance = min(values.count(unique_values[0]), len(values) - values.count(unique_values[0])) / max(len(values), 1)
    balance_score = clamp(active_balance / 0.12)
    refresh = _refresh_score(series)
    return clamp(0.55 * binary_score + 0.25 * balance_score + 0.20 * refresh)


def _monotonic_score(values: list[float], length: int) -> float:
    if len(values) < 4:
        return 0.0
    modulo = 2 ** min(length, 16)
    diffs = [((int(values[index]) - int(values[index - 1])) % modulo) for index in range(1, len(values))]
    if not diffs:
        return 0.0
    diff, count = Counter(diffs).most_common(1)[0]
    if diff == 0:
        return 0.0
    return clamp(count / len(diffs))


def _checksum_score(
    *,
    length: int,
    unique_count: int,
    sample_count: int,
    entropy: float,
    smoothness_score: float,
    best_correlation: float,
    counter_score: float,
    switch_score: float,
) -> float:
    if switch_score >= 0.60 or counter_score >= 0.70:
        return 0.0
    unique_ratio = unique_count / max(sample_count, 1)
    byte_like = 1.0 if length in {8, 16, 24, 32} else 0.70
    entropy_score = clamp((entropy - 0.70) / 0.30)
    uniqueness_score = clamp((unique_ratio - 0.45) / 0.40)
    rough_score = 1.0 - smoothness_score
    no_anchor_score = 1.0 - clamp(best_correlation / 0.60)
    return clamp(byte_like * (0.34 * entropy_score + 0.28 * uniqueness_score + 0.20 * rough_score + 0.18 * no_anchor_score))


def _normalized_entropy(values: list[float], length: int) -> float:
    if not values:
        return 0.0
    counts = Counter(values)
    entropy = -sum((count / len(values)) * math.log2(count / len(values)) for count in counts.values())
    max_symbols = min(2 ** min(length, 12), len(values))
    if max_symbols <= 1:
        return 0.0
    return clamp(entropy / math.log2(max_symbols))


def _best_correlation(evidence: dict[str, Any]) -> dict[str, Any] | None:
    correlations = evidence.get("correlations", [])
    if not correlations:
        return None
    return max(correlations, key=lambda item: abs(float(item.get("correlation", 0.0))) * float(item.get("coverage", 0.0)))


def _class_for_signal_name(signal: str) -> str | None:
    key = signal.lower()
    if "rpm" in key:
        return "rpm_like"
    if "speed" in key or key in {"gpsspeedkph", "vehicle_speed"}:
        return "speed_like"
    if "map" in key or "pressure" in key or key.endswith("kpa"):
        return "pressure_like"
    if "temp" in key or key.endswith("c"):
        return "temperature_like"
    if "pct" in key or "percent" in key or "load" in key or "throttle" in key:
        return "percentage_like"
    if "volt" in key or "battery" in key:
        return "voltage_like"
    if "maf" in key or "airflow" in key or "air_flow" in key:
        return "airflow_like"
    if "gear" in key or "ratio" in key:
        return "gear_or_ratio"
    return None


def _suggested_name(candidate_class: str, evidence: dict[str, Any], spec: CandidateSpec) -> str:
    best = _best_correlation(evidence)
    if best:
        source_name = _safe_signal_name(str(best["signal"]))
        if candidate_class == "speed_like" and "speed" in source_name:
            return "speed_like_candidate"
        return f"{source_name}_candidate"
    event = evidence.get("eventResponses", [{}])[0] if evidence.get("eventResponses") else {}
    event_label = _safe_signal_name(str(event.get("label", "")))
    if candidate_class == "switch" and event_label:
        return f"{event_label}_switch_candidate"
    if candidate_class == "warning_lamp" and event_label:
        return f"{event_label}_lamp_candidate"
    if candidate_class == "counter":
        return f"can_{format_can_id(spec.can_id).lower().replace('0x', '')}_counter_rejected"
    if candidate_class == "checksum_or_crc":
        return f"can_{format_can_id(spec.can_id).lower().replace('0x', '')}_checksum_rejected"
    return f"can_{format_can_id(spec.can_id).lower().replace('0x', '')}_{candidate_class}_candidate"


def _safe_signal_name(value: str) -> str:
    result = []
    previous_underscore = False
    for char in value.strip():
        if char.isalnum():
            result.append(char.lower())
            previous_underscore = False
        elif not previous_underscore:
            result.append("_")
            previous_underscore = True
    cleaned = "".join(result).strip("_")
    return cleaned or "signal"


def _warning_lamp_like(evidence: dict[str, Any]) -> bool:
    for response in evidence.get("eventResponses", []):
        label = str(response.get("label", "")).lower()
        if any(word in label for word in ("warning", "lamp", "light", "oil", "battery", "fan")):
            return True
    return False


def _gear_like(evidence: dict[str, Any]) -> bool:
    for item in evidence.get("correlations", []):
        signal = str(item.get("signal", "")).lower()
        if "gear" in signal or "ratio" in signal:
            return True
    return False


def _select_report_hypotheses(hypotheses: list[dict[str, Any]], max_candidates: int) -> list[dict[str, Any]]:
    status_rank = {"probable": 5, "candidate": 4, "unknown": 3, "rejected": 2, "verified": 1}
    hypotheses.sort(
        key=lambda item: (
            status_rank.get(item.get("safety", {}).get("promotionStatus"), 0),
            max(
                item.get("evidence", {}).get("bestCorrelationScore", 0.0),
                item.get("evidence", {}).get("bestEventScore", 0.0),
            ),
            item.get("evidence", {}).get("uniqueCount", 0),
            _report_field_preference(item),
            item.get("suggested", {}).get("confidence", 0.0),
            item.get("evidence", {}).get("counterScore", 0.0),
            item.get("evidence", {}).get("checksumScore", 0.0),
        ),
        reverse=True,
    )
    if max_candidates <= 0 or len(hypotheses) <= max_candidates:
        return hypotheses
    selected: list[dict[str, Any]] = []
    selected_ids: set[str] = set()
    probable_or_candidate = [
        item
        for item in hypotheses
        if item.get("safety", {}).get("promotionStatus") in {"probable", "candidate"}
    ]
    rejected = sorted(
        [item for item in hypotheses if item.get("safety", {}).get("promotionStatus") == "rejected"],
        key=lambda item: max(
            item.get("evidence", {}).get("counterScore", 0.0),
            item.get("evidence", {}).get("checksumScore", 0.0),
            item.get("suggested", {}).get("confidence", 0.0),
        ),
        reverse=True,
    )
    unknown = [item for item in hypotheses if item.get("safety", {}).get("promotionStatus") == "unknown"]

    def add_items(items: list[dict[str, Any]], limit: int) -> None:
        for item in items:
            if len(selected) >= limit:
                return
            if item["candidateId"] in selected_ids:
                continue
            selected.append(item)
            selected_ids.add(item["candidateId"])

    useful_limit = max(1, int(max_candidates * 0.82))
    rejected_limit = max(useful_limit, int(max_candidates * 0.96))
    add_items(probable_or_candidate, useful_limit)
    add_items(rejected, rejected_limit)
    add_items(unknown, max_candidates)
    add_items(hypotheses, max_candidates)
    return selected[:max_candidates]


def _report_field_preference(hypothesis: dict[str, Any]) -> tuple[int, int, int]:
    start_bit = int(hypothesis.get("startBit", 0))
    length = int(hypothesis.get("length", 0))
    byte_aligned = 1 if start_bit % 8 == 0 and length in {8, 16, 24, 32} else 0
    unsigned = 1 if not hypothesis.get("signed", False) else 0
    return (byte_aligned, unsigned, -length)


def _maybe_apply_ai_suggestions(hypotheses: list[dict[str, Any]], command: str | None) -> dict[str, Any]:
    if not command:
        return {"enabled": False}
    payload = {
        "version": 1,
        "task": "signal_identity_hypothesis_suggestions",
        "rules": {
            "aiMaySuggestNameClassRationaleConfidence": True,
            "aiCannotPromote": True,
            "rawPayloadBytesOmitted": True,
        },
        "candidates": [_compact_ai_candidate(item) for item in _ai_candidate_selection(hypotheses, limit=80)],
    }
    try:
        completed = subprocess.run(
            shlex.split(command),
            input=json.dumps(payload, sort_keys=True),
            text=True,
            capture_output=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        return {"enabled": True, "command": command, "applied": 0, "error": str(exc)}
    if completed.returncode != 0:
        return {
            "enabled": True,
            "command": command,
            "applied": 0,
            "returnCode": completed.returncode,
            "stderr": completed.stderr[-1000:],
        }
    try:
        response = json.loads(completed.stdout or "{}")
    except json.JSONDecodeError as exc:
        return {"enabled": True, "command": command, "applied": 0, "error": f"invalid JSON: {exc}"}
    suggestions = response.get("suggestions", [])
    if not isinstance(suggestions, list):
        return {"enabled": True, "command": command, "applied": 0, "error": "suggestions must be a list"}
    by_id = {item["candidateId"]: item for item in hypotheses}
    applied = 0
    ignored = 0
    for suggestion in suggestions:
        if not isinstance(suggestion, dict):
            continue
        candidate_id = suggestion.get("candidateId")
        hypothesis = by_id.get(candidate_id)
        if hypothesis is None:
            ignored += 1
            continue
        hypothesis["aiSuggestion"] = _clean_ai_suggestion(suggestion)
        if hypothesis.get("safety", {}).get("promotionStatus") == "rejected":
            ignored += 1
            continue
        _merge_ai_suggestion(hypothesis, suggestion)
        applied += 1
    return {"enabled": True, "command": command, "applied": applied, "ignored": ignored}


def _ai_candidate_selection(hypotheses: list[dict[str, Any]], *, limit: int) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    selected_ids: set[str] = set()
    rejected = [
        item
        for item in hypotheses
        if item.get("safety", {}).get("promotionStatus") == "rejected"
    ]
    useful = [
        item
        for item in hypotheses
        if item.get("safety", {}).get("promotionStatus") in {"probable", "candidate"}
    ]

    def add_items(items: list[dict[str, Any]], cap: int) -> None:
        for item in items:
            if len(selected) >= cap:
                return
            if item["candidateId"] in selected_ids:
                continue
            selected.append(item)
            selected_ids.add(item["candidateId"])

    add_items(useful, max(1, int(limit * 0.75)))
    add_items(rejected, limit)
    add_items(hypotheses, limit)
    return selected


def _compact_ai_candidate(hypothesis: dict[str, Any]) -> dict[str, Any]:
    evidence = hypothesis.get("evidence", {})
    return {
        "candidateId": hypothesis.get("candidateId"),
        "canId": hypothesis.get("canId"),
        "startBit": hypothesis.get("startBit"),
        "length": hypothesis.get("length"),
        "endian": hypothesis.get("endian"),
        "signed": hypothesis.get("signed"),
        "suggested": hypothesis.get("suggested"),
        "safety": hypothesis.get("safety"),
        "evidence": {
            "sampleHz": evidence.get("sampleHz"),
            "range": evidence.get("range"),
            "uniqueCount": evidence.get("uniqueCount"),
            "switchScore": evidence.get("switchScore"),
            "smoothnessScore": evidence.get("smoothnessScore"),
            "correlations": evidence.get("correlations", [])[:4],
            "eventResponses": evidence.get("eventResponses", [])[:4],
            "counterScore": evidence.get("counterScore"),
            "checksumScore": evidence.get("checksumScore"),
        },
    }


def _clean_ai_suggestion(suggestion: dict[str, Any]) -> dict[str, Any]:
    confidence = suggestion.get("confidence")
    return {
        "name": suggestion.get("name"),
        "class": suggestion.get("class"),
        "rationale": suggestion.get("rationale"),
        "confidence": round(clamp(float(confidence)), 4) if isinstance(confidence, (int, float)) else None,
    }


def _merge_ai_suggestion(hypothesis: dict[str, Any], suggestion: dict[str, Any]) -> None:
    suggested = hypothesis["suggested"]
    ai_class = suggestion.get("class")
    if isinstance(ai_class, str) and ai_class in HYPOTHESIS_CLASSES and ai_class not in {"counter", "checksum_or_crc"}:
        suggested["class"] = ai_class
    ai_name = suggestion.get("name")
    if isinstance(ai_name, str) and ai_name.strip():
        suggested["name"] = _safe_signal_name(ai_name)
    ai_confidence = suggestion.get("confidence")
    if isinstance(ai_confidence, (int, float)):
        suggested["aiConfidence"] = round(clamp(float(ai_confidence)), 4)
    rationale = suggestion.get("rationale")
    if isinstance(rationale, str) and rationale.strip():
        suggested["aiRationale"] = rationale.strip()
    suggested["source"] = "deterministic_ai_assisted"


def _decoded_signal_series(rows: list[dict[str, Any]]) -> dict[str, list[tuple[float, float]]]:
    series: dict[str, list[tuple[float, float]]] = {}
    for index, row in enumerate(rows):
        timestamp = _row_timestamp(row, index)
        for name, value in _row_numeric_signals(row).items():
            series.setdefault(name, []).append((timestamp, value))
    return {name: sorted(values) for name, values in series.items() if len(values) >= 3 and value_range([value for _, value in values]) > 0}


def _row_timestamp(row: dict[str, Any], index: int) -> float:
    for key in ("timestamp", "time", "ts", "wallTime"):
        value = row.get(key)
        if isinstance(value, (int, float)):
            return float(value)
    return float(index)


def _row_numeric_signals(row: dict[str, Any]) -> dict[str, float]:
    signals: dict[str, float] = {}
    nested = row.get("signals")
    if isinstance(nested, dict):
        for name, value in nested.items():
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                signals[str(name)] = float(value)
    for name, value in row.items():
        if name.startswith("_") or name in {"timestamp", "time", "ts", "wallTime", "type", "signals", "canId", "canIdInt"}:
            continue
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            signals[str(name)] = float(value)
    return signals


def _anchor_summary(session: GuidedSession) -> dict[str, Any]:
    return {
        "anchorSignals": {signal: len(points) for signal, points in sorted(session.anchors.items())},
        "windows": [asdict(window) for window in session.windows],
        "metadata": session.metadata,
    }


def _decoded_summary(decoded_series: dict[str, list[tuple[float, float]]]) -> dict[str, Any]:
    return {
        "signalCount": len(decoded_series),
        "signals": [
            {
                "name": name,
                "samples": len(series),
                "min": min(value for _, value in series),
                "max": max(value for _, value in series),
                "sampleHz": round(_sample_rate(series), 3),
            }
            for name, series in sorted(decoded_series.items())
        ][:80],
    }


def _report_summary(hypotheses: list[dict[str, Any]]) -> dict[str, Any]:
    statuses = Counter(item.get("safety", {}).get("promotionStatus", "unknown") for item in hypotheses)
    classes = Counter(item.get("suggested", {}).get("class", "unknown") for item in hypotheses)
    return {
        "hypothesisCount": len(hypotheses),
        "promotionStatusCounts": dict(sorted(statuses.items())),
        "classCounts": dict(sorted(classes.items())),
        "probableCount": statuses.get("probable", 0),
        "candidateCount": statuses.get("candidate", 0),
        "rejectedCount": statuses.get("rejected", 0),
    }


def _frame_stats(frames: list[CanFrame], parse_stats: ParseStats | None) -> dict[str, Any]:
    if not frames:
        return {"frameCount": 0}
    return {
        "frameCount": len(frames),
        "firstTimestamp": frames[0].timestamp,
        "lastTimestamp": frames[-1].timestamp,
        "durationSec": round(max(frames[-1].timestamp - frames[0].timestamp, 0.0), 6),
        "parse": {
            "totalLines": parse_stats.total_lines if parse_stats else None,
            "parsed": parse_stats.parsed if parse_stats else len(frames),
            "skipped": parse_stats.skipped if parse_stats else None,
            "outOfOrder": parse_stats.out_of_order if parse_stats else None,
            "warnings": parse_stats.warnings if parse_stats else [],
        },
    }


def _series_preview(raw_series: list[tuple[float, float]], limit: int = 24) -> list[dict[str, float]]:
    if len(raw_series) <= limit:
        indexes = range(len(raw_series))
    else:
        step = len(raw_series) / limit
        indexes = sorted({min(int(index * step), len(raw_series) - 1) for index in range(limit)})
    return [{"timestamp": raw_series[index][0], "raw": raw_series[index][1]} for index in indexes]


def _export_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    return {
        "sampleHz": evidence.get("sampleHz"),
        "range": evidence.get("range"),
        "uniqueCount": evidence.get("uniqueCount"),
        "correlations": evidence.get("correlations", [])[:5],
        "eventResponses": evidence.get("eventResponses", [])[:5],
        "counterScore": evidence.get("counterScore"),
        "checksumScore": evidence.get("checksumScore"),
    }


def _unique_name(name: str, used_names: set[str]) -> str:
    base = _safe_signal_name(name)
    candidate = base
    suffix = 2
    while candidate in used_names:
        candidate = f"{base}_{suffix}"
        suffix += 1
    used_names.add(candidate)
    return candidate


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0
