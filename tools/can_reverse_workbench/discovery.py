from __future__ import annotations

import math
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Iterable

from tools.vehicle_analysis.stats import clamp, median, stddev, value_range

from .bitfield import extract_signal_value
from .labels import AnchorPoint, GuidedSession
from .parser import CanFrame, ParseStats


TARGETS = {
    "rpm": {
        "unit": "rpm",
        "min": 0.0,
        "max": 8500.0,
        "typical_max": 7000.0,
        "anchor_error": 150.0,
        "min_step": 0.01,
    },
    "speedKph": {
        "unit": "kph",
        "min": 0.0,
        "max": 240.0,
        "typical_max": 160.0,
        "anchor_error": 4.0,
        "min_step": 0.001,
    },
    "coolantC": {
        "unit": "C",
        "min": -40.0,
        "max": 140.0,
        "typical_max": 120.0,
        "anchor_error": 3.0,
        "min_step": 0.1,
    },
    "engineLoadPct": {
        "unit": "pct",
        "min": 0.0,
        "max": 100.0,
        "typical_max": 100.0,
        "anchor_error": 5.0,
        "min_step": 0.05,
    },
    "throttlePct": {
        "unit": "pct",
        "min": 0.0,
        "max": 100.0,
        "typical_max": 100.0,
        "anchor_error": 4.0,
        "min_step": 0.05,
    },
    "intakeAirTempC": {
        "unit": "C",
        "min": -40.0,
        "max": 120.0,
        "typical_max": 100.0,
        "anchor_error": 3.0,
        "min_step": 0.1,
    },
    "mapKpa": {
        "unit": "kPa",
        "min": 0.0,
        "max": 255.0,
        "typical_max": 200.0,
        "anchor_error": 5.0,
        "min_step": 0.05,
    },
    "mafGps": {
        "unit": "g/s",
        "min": 0.0,
        "max": 400.0,
        "typical_max": 180.0,
        "anchor_error": 5.0,
        "min_step": 0.01,
    },
    "fuelPct": {
        "unit": "pct",
        "min": 0.0,
        "max": 100.0,
        "typical_max": 100.0,
        "anchor_error": 4.0,
        "min_step": 0.05,
    },
    "controlModuleVoltage": {
        "unit": "V",
        "min": 0.0,
        "max": 20.0,
        "typical_max": 16.0,
        "anchor_error": 0.35,
        "min_step": 0.001,
    },
}
FIELD_LENGTHS = (4, 8, 10, 11, 12, 13, 14, 15, 16, 24, 32)
ENDIANS = ("big", "little")
MIN_CANDIDATE_SAMPLES = 8
DEFAULT_VERIFIED_CONFIDENCE = 0.70
MIN_LAGGED_ANCHORS = 6
LAG_SEARCH_RANGE_SEC = 2.0
LAG_SEARCH_STEP_SEC = 0.05


@dataclass(frozen=True)
class CandidateSpec:
    can_id: int
    start_bit: int
    length: int
    endian: str
    signed: bool

    @property
    def byte_index(self) -> int:
        return self.start_bit // 8

    @property
    def byte_length(self) -> int:
        return (self.start_bit % 8 + self.length + 7) // 8

    @property
    def candidate_id(self) -> str:
        return (
            f"{format_can_id(self.can_id)}:"
            f"b{self.start_bit}:l{self.length}:{self.endian}:{'s' if self.signed else 'u'}"
        )


def analyze_frames(
    frames: list[CanFrame],
    session: GuidedSession | None = None,
    parse_stats: ParseStats | None = None,
    source: dict | None = None,
    targets: Iterable[str] = ("rpm", "speedKph"),
    max_candidates: int = 20,
    verified_confidence: float = DEFAULT_VERIFIED_CONFIDENCE,
) -> dict:
    """Rank deterministic signal candidates for the requested target signals."""
    session = session or GuidedSession.empty()
    frame_groups = _group_frames(frames)
    requested_targets = [target for target in targets if target in TARGETS]
    rankings: dict[str, list[dict]] = {target: [] for target in requested_targets}

    for can_id, group in frame_groups.items():
        for spec in _enumerate_specs(can_id, group):
            raw_series = _candidate_series(group, spec)
            if not _passes_candidate_filters(raw_series):
                continue
            for signal in requested_targets:
                rankings[signal].append(_score_candidate(signal, spec, raw_series, session, len(group), verified_confidence))

    for signal in rankings:
        rankings[signal].sort(
            key=lambda item: (
                item["confidence"],
                item["evidence"]["scaleResolution"],
                item["evidence"]["fieldShape"],
                item["length"],
            ),
            reverse=True,
        )
        rankings[signal] = rankings[signal][:max_candidates]

    signal_decisions = _signal_decisions(rankings)
    return {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": source or {},
        "pipeline": _pipeline_summary(verified_confidence),
        "frameStats": _frame_stats(frames, parse_stats),
        "labelWindows": [asdict(window) for window in session.windows],
        "anchors": {
            signal: [asdict(point) for point in points]
            for signal, points in sorted(session.anchors.items())
        },
        "idSummary": [_summarize_id(can_id, group) for can_id, group in sorted(frame_groups.items())],
        "candidateRankings": rankings,
        "signalDecisions": signal_decisions,
        "packetDecisions": _packet_decisions(frame_groups, rankings),
        "topSignals": {signal: candidates[0] for signal, candidates in rankings.items() if candidates},
    }


def format_can_id(can_id: int) -> str:
    width = 3 if can_id <= 0x7FF else 8
    return f"0x{can_id:0{width}X}"


def _pipeline_summary(verified_confidence: float) -> dict:
    return {
        "version": 1,
        "principle": "never attach a human signal name unless the candidate is verified",
        "stages": [
            {"name": "bitAnalysis", "description": "enumerate common 4-32 bit numeric fields, endian variants, and signedness; reject counter-like data"},
            {"name": "correlation", "description": "score normalized lagged anchor correlation plus guided label trends"},
            {"name": "scaling", "description": "calibrate raw values to units with lag-aware least-squares anchors and holdout checks"},
            {"name": "validation", "description": "check physical range, smoothness, variation, update rate, and fitted scale sanity"},
        ],
        "verifiedConfidenceThreshold": verified_confidence,
        "requiresScaleVerification": True,
        "unknownPolicy": "CAN IDs without verified evidence stay unknown; they are not exported as rpm/speedKph",
    }


def _signal_decisions(rankings: dict[str, list[dict]]) -> dict[str, dict]:
    decisions: dict[str, dict] = {}
    for signal, candidates in rankings.items():
        if not candidates:
            decisions[signal] = {
                "status": "unknown",
                "confidence": 0.0,
                "reason": "no candidates survived filtering",
            }
            continue
        top = candidates[0]
        decisions[signal] = {
            "status": top["verificationStatus"],
            "confidence": top["confidence"],
            "verified": bool(top["verified"]),
            "candidateId": top["candidateId"],
            "canId": top["canId"],
            "reason": top["pipeline"]["decision"]["reason"],
        }
    return decisions


def _packet_decisions(frame_groups: dict[int, list[CanFrame]], rankings: dict[str, list[dict]]) -> list[dict]:
    candidates_by_can_id: dict[int, list[dict]] = defaultdict(list)
    for signal, candidates in rankings.items():
        for candidate in candidates:
            candidates_by_can_id[candidate["canIdInt"]].append(
                {
                    "signal": signal,
                    "candidateId": candidate["candidateId"],
                    "confidence": candidate["confidence"],
                    "verified": candidate["verified"],
                    "status": candidate["verificationStatus"],
                }
            )

    decisions = []
    for can_id, frames in sorted(frame_groups.items()):
        candidates = sorted(candidates_by_can_id.get(can_id, []), key=lambda item: item["confidence"], reverse=True)
        verified = [candidate for candidate in candidates if candidate["verified"]]
        best_confidence = candidates[0]["confidence"] if candidates else 0.0
        assigned_signals = sorted({candidate["signal"] for candidate in verified})
        decisions.append(
            {
                "canId": format_can_id(can_id),
                "canIdInt": can_id,
                "frameCount": len(frames),
                "status": "assigned" if verified else "unknown",
                "confidence": best_confidence,
                "assignedSignals": assigned_signals,
                "bestCandidates": candidates[:5],
                "reason": "verified signal assignment" if verified else "no verified human signal mapping",
            }
        )
    return decisions


def _group_frames(frames: list[CanFrame]) -> dict[int, list[CanFrame]]:
    groups: dict[int, list[CanFrame]] = defaultdict(list)
    for frame in frames:
        groups[frame.arbitration_id].append(frame)
    return groups


def _enumerate_specs(can_id: int, frames: list[CanFrame]) -> list[CandidateSpec]:
    max_length = max((len(frame.data) for frame in frames), default=0)
    max_bits = max_length * 8
    specs: list[CandidateSpec] = []
    for field_length in FIELD_LENGTHS:
        if max_bits < field_length:
            continue
        for start_bit in _candidate_start_bits(max_bits, field_length):
            for endian in ENDIANS:
                for signed in (False, True):
                    specs.append(
                        CandidateSpec(
                            can_id=can_id,
                            start_bit=start_bit,
                            length=field_length,
                            endian=endian,
                            signed=signed,
                        )
                    )
    return specs


def _candidate_start_bits(max_bits: int, field_length: int) -> range:
    if field_length in {8, 16, 24, 32}:
        return range(0, max_bits - field_length + 1, 8)
    if field_length <= 7:
        return range(0, max_bits - field_length + 1)
    return range(0, max_bits - field_length + 1, 4)


def _candidate_series(frames: list[CanFrame], spec: CandidateSpec) -> list[tuple[float, float]]:
    values: list[tuple[float, float]] = []
    for frame in frames:
        if spec.start_bit + spec.length > len(frame.data) * 8:
            continue
        raw = extract_signal_value(frame.data, spec.start_bit, spec.length, spec.endian, spec.signed)
        values.append((frame.timestamp, float(raw)))
    return values


def _passes_candidate_filters(series: list[tuple[float, float]]) -> bool:
    if len(series) < MIN_CANDIDATE_SAMPLES:
        return False
    values = [value for _, value in series]
    if len(set(values)) < 3:
        return False
    raw_range = max(values) - min(values)
    return raw_range > 0


def _score_candidate(
    signal: str,
    spec: CandidateSpec,
    raw_series: list[tuple[float, float]],
    session: GuidedSession,
    id_frame_count: int,
    verified_confidence: float,
) -> dict:
    calibration = _calibrate(signal, raw_series, session.anchors.get(signal, []))
    scaled_series = [(timestamp, raw * calibration["scale"] + calibration["offset"]) for timestamp, raw in raw_series]
    aligned_scaled_series = [(timestamp - calibration.get("lagSec", 0.0), value) for timestamp, value in scaled_series]
    window_score = _score_windows(signal, aligned_scaled_series, session)
    correlation_score = _combined_correlation_score(
        anchor_score=calibration["correlationScore"],
        window_score=window_score,
        anchor_count=calibration["anchorCount"],
        has_windows=bool(session.windows),
    )
    physical_score = _physical_score(signal, scaled_series)
    smoothness_score = _smoothness_score(scaled_series)
    variation_score = _variation_score(signal, aligned_scaled_series, session)
    anti_counter_score = _anti_counter_score(raw_series, spec.length)
    field_shape_score = _field_shape_score(spec, raw_series)
    scale_resolution_score = _scale_resolution_score(signal, calibration["scale"])
    components = {
        "anchors": calibration["anchorScore"],
        "correlation": correlation_score,
        "physical": physical_score,
        "smoothness": smoothness_score,
        "refresh": _refresh_score(raw_series),
        "variation": variation_score,
        "antiCounter": anti_counter_score,
        "fieldShape": field_shape_score,
        "scaleResolution": scale_resolution_score,
    }
    weights = _component_weights(calibration["anchorCount"], bool(session.windows))
    weighted_score = sum(components[name] * weights[name] for name in components)
    confidence = clamp(weighted_score)
    stage_scores = _pipeline_stage_scores(
        calibration=calibration,
        correlation_score=correlation_score,
        physical_score=physical_score,
        smoothness_score=smoothness_score,
        variation_score=variation_score,
        anti_counter_score=anti_counter_score,
    )
    decision = _candidate_decision(confidence, stage_scores, calibration, verified_confidence)
    raw_values = [value for _, value in raw_series]
    scaled_values = [value for _, value in scaled_series]
    return {
        "candidateId": spec.candidate_id,
        "signal": signal,
        "canId": format_can_id(spec.can_id),
        "canIdInt": spec.can_id,
        "startBit": spec.start_bit,
        "byteIndex": spec.byte_index,
        "length": spec.length,
        "endian": spec.endian,
        "signed": spec.signed,
        "scale": calibration["scale"],
        "offset": calibration["offset"],
        "unit": TARGETS[signal]["unit"],
        "confidence": round(confidence, 4),
        "verified": decision["verified"],
        "verificationStatus": decision["status"],
        "score": round(weighted_score, 4),
        "pipeline": {
            "stages": stage_scores,
            "decision": decision,
        },
        "evidence": {
            "frameCount": len(raw_series),
            "idFrameCount": id_frame_count,
            "sampleHz": round(_sample_rate(raw_series), 3),
            "rawMin": min(raw_values),
            "rawMax": max(raw_values),
            "valueMin": min(scaled_values),
            "valueMax": max(scaled_values),
            "anchorCount": calibration["anchorCount"],
            "anchorMae": calibration["anchorMae"],
            "anchorR2": calibration["anchorR2"],
            "anchorCorrelation": calibration["correlation"],
            "anchorHoldoutMae": calibration["holdoutMae"],
            "anchorHoldoutR2": calibration["holdoutR2"],
            "lagSec": calibration["lagSec"],
            "fieldShape": round(field_shape_score, 4),
            "scaleResolution": round(scale_resolution_score, 4),
            "scaleVerified": calibration["scaleVerified"],
            "scaleMethod": calibration["method"],
            "components": {name: round(score, 4) for name, score in components.items()},
            "weights": weights,
            "windowScore": round(window_score, 4),
            "windowEvidence": _window_evidence(signal, aligned_scaled_series, session),
        },
        "seriesPreview": _series_preview(raw_series, scaled_series),
    }


def _calibrate(signal: str, series: list[tuple[float, float]], anchors: list[AnchorPoint]) -> dict:
    target = TARGETS[signal]
    best: dict | None = None
    for lag in _calibration_lags(len(anchors)):
        pairs = _anchor_pairs(series, anchors, lag)
        if len(pairs) < 2 or max(raw for raw, _ in pairs) == min(raw for raw, _ in pairs):
            continue
        train_pairs, holdout_pairs = _split_anchor_pairs(pairs)
        fit_pairs = train_pairs if len(train_pairs) >= 2 and max(raw for raw, _ in train_pairs) != min(raw for raw, _ in train_pairs) else pairs
        scale, offset = _least_squares(fit_pairs)
        stats = _fit_stats(pairs, scale, offset, target["anchor_error"])
        holdout_stats = _fit_stats(holdout_pairs, scale, offset, target["anchor_error"]) if holdout_pairs else None
        sign_score = 1.0 if scale >= 0.0 else 0.15
        lag_score = 1.0 - min(abs(lag) / max(LAG_SEARCH_RANGE_SEC, 1e-9), 1.0) * 0.12
        holdout_score = holdout_stats["maeScore"] if holdout_stats else stats["maeScore"]
        anchor_score = clamp(
            (
                0.33 * stats["maeScore"]
                + 0.24 * stats["r2Score"]
                + 0.22 * stats["correlationScore"]
                + 0.13 * holdout_score
                + 0.08 * sign_score
            )
            * lag_score
        )
        result = {
            "scale": scale,
            "offset": offset,
            "anchorCount": len(pairs),
            "anchorMae": round(stats["mae"], 4),
            "anchorR2": round(stats["r2"], 4),
            "anchorScore": anchor_score,
            "correlation": round(stats["correlation"], 4),
            "correlationScore": stats["correlationScore"],
            "holdoutMae": round(holdout_stats["mae"], 4) if holdout_stats else None,
            "holdoutR2": round(holdout_stats["r2"], 4) if holdout_stats else None,
            "lagSec": lag,
            "scaleVerified": True,
            "method": "lagged_anchor_least_squares" if abs(lag) > 1e-9 else "anchor_least_squares",
        }
        if best is None or result["anchorScore"] > best["anchorScore"]:
            best = result
    if best is not None:
        return best

    pairs = _anchor_pairs(series, anchors, 0.0)
    raw_values = [value for _, value in series]
    raw_min = min(raw_values)
    raw_max = max(raw_values)
    if raw_max == raw_min:
        scale = 1.0
        offset = 0.0
    else:
        scale = target["typical_max"] / (raw_max - raw_min)
        offset = -raw_min * scale
    if len(pairs) == 1:
        raw, expected = pairs[0]
        offset = expected - raw * scale
        anchor_score = 0.5
        mae = 0.0
    else:
        anchor_score = 0.35
        mae = None
    return {
        "scale": scale,
        "offset": offset,
        "anchorCount": len(pairs),
        "anchorMae": mae,
        "anchorR2": None,
        "anchorScore": anchor_score,
        "correlation": None,
        "correlationScore": 0.5 if len(pairs) == 1 else 0.0,
        "holdoutMae": None,
        "holdoutR2": None,
        "lagSec": 0.0,
        "scaleVerified": False,
        "method": "single_anchor" if len(pairs) == 1 else "range_estimate_unverified",
    }


def _calibration_lags(anchor_count: int) -> list[float]:
    if anchor_count < MIN_LAGGED_ANCHORS:
        return [0.0]
    steps = int(round(LAG_SEARCH_RANGE_SEC / LAG_SEARCH_STEP_SEC))
    lags = [round(step * LAG_SEARCH_STEP_SEC, 6) for step in range(-steps, steps + 1)]
    return sorted(set(lags), key=lambda value: (abs(value), value))


def _anchor_pairs(
    series: list[tuple[float, float]],
    anchors: list[AnchorPoint],
    lag: float,
) -> list[tuple[float, float]]:
    pairs: list[tuple[float, float]] = []
    for anchor in anchors:
        raw = _interpolate_value(series, anchor.timestamp + lag)
        if raw is not None:
            pairs.append((raw, anchor.value))
    return pairs


def _split_anchor_pairs(pairs: list[tuple[float, float]]) -> tuple[list[tuple[float, float]], list[tuple[float, float]]]:
    if len(pairs) < MIN_LAGGED_ANCHORS:
        return pairs, []
    holdout = [pair for index, pair in enumerate(pairs) if index % 4 == 3]
    train = [pair for index, pair in enumerate(pairs) if index % 4 != 3]
    if len(holdout) < 2 or len(train) < 2:
        return pairs, []
    return train, holdout


def _fit_stats(pairs: list[tuple[float, float]], scale: float, offset: float, anchor_error: float) -> dict[str, float]:
    if not pairs:
        return {
            "mae": 0.0,
            "maeScore": 0.0,
            "r2": 0.0,
            "r2Score": 0.0,
            "correlation": 0.0,
            "correlationScore": 0.0,
        }
    predictions = [raw * scale + offset for raw, _ in pairs]
    expected = [value for _, value in pairs]
    errors = [abs(predicted - actual) for predicted, actual in zip(predictions, expected)]
    mae = sum(errors) / len(errors)
    r2 = _r2_score(expected, predictions, anchor_error)
    correlation = _correlation([raw for raw, _ in pairs], expected)
    return {
        "mae": mae,
        "maeScore": clamp(1.0 - min(mae / max(anchor_error, 1e-9), 1.0)),
        "r2": r2,
        "r2Score": clamp(r2),
        "correlation": correlation,
        "correlationScore": clamp(abs(correlation)),
    }


def _r2_score(actual: list[float], predicted: list[float], anchor_error: float) -> float:
    if len(actual) != len(predicted) or not actual:
        return 0.0
    mean_actual = _mean(actual)
    ss_total = sum((value - mean_actual) ** 2 for value in actual)
    ss_residual = sum((actual_value - predicted_value) ** 2 for actual_value, predicted_value in zip(actual, predicted))
    if ss_total <= 1e-9:
        rmse = math.sqrt(ss_residual / len(actual))
        return 1.0 if rmse <= anchor_error else 0.0
    return 1.0 - ss_residual / ss_total


def _combined_correlation_score(
    *,
    anchor_score: float,
    window_score: float,
    anchor_count: int,
    has_windows: bool,
) -> float:
    if anchor_count >= 3 and has_windows:
        return clamp(0.72 * anchor_score + 0.28 * window_score)
    if anchor_count >= 3:
        return clamp(anchor_score)
    if has_windows and anchor_count:
        return clamp(0.82 * window_score + 0.18 * anchor_score)
    if has_windows:
        return clamp(window_score)
    return 0.5


def _least_squares(pairs: list[tuple[float, float]]) -> tuple[float, float]:
    n = len(pairs)
    mean_x = sum(raw for raw, _ in pairs) / n
    mean_y = sum(expected for _, expected in pairs) / n
    denom = sum((raw - mean_x) ** 2 for raw, _ in pairs)
    if denom == 0:
        return 1.0, mean_y - mean_x
    scale = sum((raw - mean_x) * (expected - mean_y) for raw, expected in pairs) / denom
    offset = mean_y - scale * mean_x
    return scale, offset


def _interpolate_value(series: list[tuple[float, float]], timestamp: float) -> float | None:
    if not series:
        return None
    if timestamp <= series[0][0]:
        return series[0][1]
    if timestamp >= series[-1][0]:
        return series[-1][1]
    previous_t, previous_v = series[0]
    for current_t, current_v in series[1:]:
        if current_t >= timestamp:
            if current_t == previous_t:
                return current_v
            ratio = (timestamp - previous_t) / (current_t - previous_t)
            return previous_v + ratio * (current_v - previous_v)
        previous_t, previous_v = current_t, current_v
    return series[-1][1]


def _score_windows(signal: str, series: list[tuple[float, float]], session: GuidedSession) -> float:
    if not session.windows:
        return 0.5
    scores: list[float] = []
    for window in session.windows:
        best = 0.0
        for lag in (-0.25, 0.0, 0.25):
            subset = [(t, v) for t, v in series if window.start + lag <= t <= window.end + lag]
            if len(subset) >= 3:
                best = max(best, _score_window(signal, window.label, window.target, window.trend, subset))
        scores.append(best * window.weight)
    weight_sum = sum(window.weight for window in session.windows) or 1.0
    return clamp(sum(scores) / weight_sum)


def _score_window(
    signal: str,
    label: str,
    target: str | None,
    trend: str | None,
    subset: list[tuple[float, float]],
) -> float:
    values = [value for _, value in subset]
    label_key = label.strip().lower()
    active_target = (target or "").strip()
    if active_target and active_target != signal:
        return _negative_control_score(signal, values)
    if trend:
        return _trend_score(subset, trend)
    if label_key in {"idle", "stationary", "parked"}:
        if signal == "rpm":
            return 0.55 * _stable_score(values, 300.0) + 0.45 * _range_center_score(_mean(values), 500.0, 1200.0)
        return 0.7 * _near_zero_score(values, 7.0) + 0.3 * _stable_score(values, 3.0)
    if label_key in {"stationary_rev", "rev", "revving"}:
        if signal == "rpm":
            return 0.75 * _range_score(values, 2500.0) + 0.25 * _stable_score(values, 5000.0)
        return 0.8 * _near_zero_score(values, 10.0) + 0.2 * _stable_score(values, 4.0)
    if label_key in {"accelerate", "acceleration"}:
        if signal == "speedKph":
            return 0.7 * _trend_score(subset, "increasing") + 0.3 * _range_score(values, 45.0)
        return 0.55
    if label_key in {"decelerate", "deceleration", "brake"}:
        if signal == "speedKph":
            return 0.7 * _trend_score(subset, "decreasing") + 0.3 * _range_score(values, 35.0)
        return 0.55
    return 0.5


def _negative_control_score(signal: str, values: list[float]) -> float:
    if signal == "speedKph":
        return _near_zero_score(values, 12.0)
    if signal == "rpm":
        return _stable_score(values, 600.0)
    return 0.5


def _trend_score(subset: list[tuple[float, float]], trend: str) -> float:
    times = [timestamp for timestamp, _ in subset]
    values = [value for _, value in subset]
    corr = _correlation(times, values)
    normalized = (corr + 1.0) / 2.0
    trend_key = trend.strip().lower()
    if trend_key in {"increasing", "up", "rise", "rising"}:
        return clamp(normalized)
    if trend_key in {"decreasing", "down", "fall", "falling"}:
        return clamp(1.0 - normalized)
    if trend_key in {"stable", "flat"}:
        return _stable_score(values, max(value_range(values), 1.0))
    return 0.5


def _physical_score(signal: str, series: list[tuple[float, float]]) -> float:
    target = TARGETS[signal]
    values = [value for _, value in series]
    if not values:
        return 0.0
    in_range = sum(target["min"] <= value <= target["max"] for value in values) / len(values)
    return clamp(in_range)


def _smoothness_score(series: list[tuple[float, float]]) -> float:
    values = [value for _, value in series]
    if len(values) < 4:
        return 0.5
    observed_range = max(value_range(values), 1.0)
    diffs = [abs(values[i] - values[i - 1]) for i in range(1, len(values))]
    second_diffs = [abs(diffs[i] - diffs[i - 1]) for i in range(1, len(diffs))]
    median_step = median(diffs)
    median_second = median(second_diffs) if second_diffs else 0.0
    step_penalty = min(median_step / (observed_range * 0.25 + 1.0), 1.0)
    jerk_penalty = min(median_second / (observed_range * 0.35 + 1.0), 1.0)
    return clamp(1.0 - 0.55 * step_penalty - 0.45 * jerk_penalty)


def _refresh_score(series: list[tuple[float, float]]) -> float:
    return clamp(_sample_rate(series) / 5.0)


def _variation_score(signal: str, series: list[tuple[float, float]], session: GuidedSession) -> float:
    values = [value for _, value in series]
    if not values:
        return 0.0
    overall_range = value_range(values)
    if signal == "rpm":
        base = _range_score(values, 2500.0)
    else:
        base = _range_score(values, 60.0)
    if any(window.label.lower() == "idle" for window in session.windows):
        return clamp(base)
    return clamp(0.35 + 0.65 * base if overall_range else 0.0)


def _anti_counter_score(series: list[tuple[float, float]], length: int) -> float:
    values = [int(value) for _, value in series]
    if len(values) < 6:
        return 0.5
    modulo = 2 ** min(length, 16)
    diffs = [((values[i] - values[i - 1]) % modulo) for i in range(1, len(values))]
    if not diffs:
        return 0.5
    diff, count = Counter(diffs).most_common(1)[0]
    repeat_ratio = count / len(diffs)
    if diff != 0 and repeat_ratio > 0.82 and abs(diff) <= 4:
        return 0.05
    unique_ratio = len(set(values)) / len(values)
    if length == 8 and unique_ratio > 0.85 and repeat_ratio < 0.2:
        return 0.35
    return 0.9


def _field_shape_score(spec: CandidateSpec, series: list[tuple[float, float]]) -> float:
    if spec.start_bit % 8 == 0 and spec.length in {8, 16, 24, 32}:
        alignment_score = 1.0
        allowed_surplus_bits = 3
    elif spec.start_bit % 4 == 0 and spec.length in {4, 8, 12, 16, 24, 32}:
        alignment_score = 0.9
        allowed_surplus_bits = 2
    else:
        alignment_score = 0.78
        allowed_surplus_bits = 1

    values = [value for _, value in series]
    raw_range = max(values) - min(values) if values else 0.0
    bits_needed = max(1, math.ceil(math.log2(raw_range + 1.0)))
    if spec.signed:
        bits_needed += 1
    surplus_bits = max(0, spec.length - bits_needed - allowed_surplus_bits)
    economy_score = 1.0 - min(surplus_bits / max(spec.length, 1), 0.55)
    return clamp(alignment_score * economy_score)


def _scale_resolution_score(signal: str, scale: float) -> float:
    min_step = TARGETS[signal]["min_step"]
    return clamp(abs(scale) / max(min_step, 1e-12))


def _pipeline_stage_scores(
    *,
    calibration: dict,
    correlation_score: float,
    physical_score: float,
    smoothness_score: float,
    variation_score: float,
    anti_counter_score: float,
) -> dict[str, dict]:
    scaling_confidence = calibration["anchorScore"] if calibration.get("scaleVerified") else min(calibration["anchorScore"], 0.49)
    validation_confidence = clamp((physical_score * 0.45) + (smoothness_score * 0.30) + (variation_score * 0.25))
    return {
        "bitAnalysis": {
            "confidence": round(anti_counter_score, 4),
            "verified": anti_counter_score >= 0.50,
            "reason": "not counter-like/noisy one-off" if anti_counter_score >= 0.50 else "looks counter-like or too noisy",
        },
        "correlation": {
            "confidence": round(correlation_score, 4),
            "verified": correlation_score >= 0.60,
            "reason": "matches guided windows/trends" if correlation_score >= 0.60 else "does not match guided windows strongly enough",
        },
        "scaling": {
            "confidence": round(scaling_confidence, 4),
            "verified": bool(calibration.get("scaleVerified")),
            "method": calibration.get("method", "unknown"),
            "anchorCount": calibration["anchorCount"],
            "anchorMae": calibration["anchorMae"],
            "reason": "scale anchored by manual values" if calibration.get("scaleVerified") else "scale is estimated and must not be exported",
        },
        "validation": {
            "confidence": round(validation_confidence, 4),
            "verified": validation_confidence >= 0.60,
            "reason": "physically plausible and smooth" if validation_confidence >= 0.60 else "failed physical/smoothness validation",
        },
    }


def _candidate_decision(
    confidence: float,
    stage_scores: dict[str, dict],
    calibration: dict,
    verified_confidence: float,
) -> dict:
    failed = [name for name, stage in stage_scores.items() if not stage["verified"]]
    if confidence < verified_confidence:
        failed.append("confidence")
    verified = not failed and bool(calibration.get("scaleVerified"))
    if verified:
        status = "verified"
        reason = "bit analysis, correlation, scaling, validation, and confidence passed"
    else:
        status = "unverified"
        reason = "not exported: " + ", ".join(dict.fromkeys(failed or ["scale"]))
    return {
        "verified": verified,
        "status": status,
        "confidence": round(confidence, 4),
        "threshold": verified_confidence,
        "failedStages": list(dict.fromkeys(failed)),
        "reason": reason,
    }


def _window_evidence(signal: str, series: list[tuple[float, float]], session: GuidedSession) -> list[dict]:
    evidence = []
    for window in session.windows:
        subset = [(t, v) for t, v in series if window.start <= t <= window.end]
        if not subset:
            continue
        values = [value for _, value in subset]
        evidence.append(
            {
                "label": window.label,
                "target": window.target,
                "trend": window.trend,
                "samples": len(values),
                "mean": round(_mean(values), 3),
                "min": round(min(values), 3),
                "max": round(max(values), 3),
                "score": round(_score_window(signal, window.label, window.target, window.trend, subset), 4),
            }
        )
    return evidence


def _component_weights(anchor_count: int, has_windows: bool) -> dict[str, float]:
    weights = {
        "anchors": 0.45 if anchor_count >= 2 else 0.18,
        "correlation": 0.25 if has_windows else 0.16,
        "physical": 0.12,
        "smoothness": 0.10,
        "refresh": 0.08,
        "variation": 0.10,
        "antiCounter": 0.08,
        "fieldShape": 0.04,
        "scaleResolution": 0.10,
    }
    total = sum(weights.values())
    return {name: round(weight / total, 4) for name, weight in weights.items()}


def _series_preview(
    raw_series: list[tuple[float, float]],
    scaled_series: list[tuple[float, float]],
    limit: int = 300,
) -> list[dict]:
    if len(raw_series) <= limit:
        indexes = range(len(raw_series))
    else:
        step = len(raw_series) / limit
        indexes = sorted({int(i * step) for i in range(limit)})
    return [
        {
            "timestamp": raw_series[index][0],
            "raw": raw_series[index][1],
            "value": round(scaled_series[index][1], 4),
        }
        for index in indexes
    ]


def _frame_stats(frames: list[CanFrame], parse_stats: ParseStats | None) -> dict:
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


def _summarize_id(can_id: int, frames: list[CanFrame]) -> dict:
    lengths = Counter(len(frame.data) for frame in frames)
    byte_stats = []
    bit_stats = []
    max_length = max(lengths, default=0)
    for index in range(max_length):
        values = [frame.data[index] for frame in frames if len(frame.data) > index]
        if not values:
            continue
        byte_stats.append(
            {
                "byte": index,
                "min": min(values),
                "max": max(values),
                "unique": len(set(values)),
            }
        )
        for bit in range(8):
            bits = [(value >> bit) & 1 for value in values]
            transitions = sum(1 for current, previous in zip(bits[1:], bits[:-1]) if current != previous)
            bit_stats.append(
                {
                    "byte": index,
                    "bit": bit,
                    "ones": sum(bits),
                    "density": round(sum(bits) / len(bits), 4),
                    "transitions": transitions,
                }
            )
    return {
        "canId": format_can_id(can_id),
        "canIdInt": can_id,
        "frameCount": len(frames),
        "firstTimestamp": frames[0].timestamp,
        "lastTimestamp": frames[-1].timestamp,
        "sampleHz": round(_sample_rate([(frame.timestamp, 0.0) for frame in frames]), 3),
        "lengths": {str(length): count for length, count in sorted(lengths.items())},
        "byteStats": byte_stats,
        "bitStats": bit_stats,
    }


def _sample_rate(series: list[tuple[float, float]]) -> float:
    if len(series) < 2:
        return 0.0
    duration = max(series[-1][0] - series[0][0], 1e-9)
    return (len(series) - 1) / duration


def _correlation(xs: list[float], ys: list[float]) -> float:
    if len(xs) != len(ys) or len(xs) < 2:
        return 0.0
    mean_x = _mean(xs)
    mean_y = _mean(ys)
    denom_x = math.sqrt(sum((x - mean_x) ** 2 for x in xs))
    denom_y = math.sqrt(sum((y - mean_y) ** 2 for y in ys))
    if denom_x == 0 or denom_y == 0:
        return 0.0
    return sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / (denom_x * denom_y)


def _range_score(values: list[float], expected_range: float) -> float:
    return clamp(value_range(values) / expected_range)


def _stable_score(values: list[float], tolerance: float) -> float:
    return clamp(1.0 - min(stddev(values) / max(tolerance, 1e-9), 1.0))


def _near_zero_score(values: list[float], tolerance: float) -> float:
    return clamp(1.0 - min(max(abs(value) for value in values) / max(tolerance, 1e-9), 1.0))


def _range_center_score(value: float, low: float, high: float) -> float:
    if low <= value <= high:
        return 1.0
    if value < low:
        return clamp(1.0 - (low - value) / max(low, 1.0))
    return clamp(1.0 - (value - high) / max(high, 1.0))


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0
