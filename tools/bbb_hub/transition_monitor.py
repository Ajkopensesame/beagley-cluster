from __future__ import annotations

import json
import math
import time
from collections import Counter, deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from tools.vehicle_analysis.findings import make_diagnostic_finding, normalize_severity
from tools.vehicle_analysis.stats import RunningStats, clamp
from tools.vehicle_analysis.transitions import (
    ANOMALY_CLASSES,
    EventSegmenter,
    SIGNAL_TIERS,
    TransitionEvent,
    transition_window_metrics,
)
from tools.vehicle_analysis.values import number_or_none


SCHEMA_VERSION = 1


@dataclass(frozen=True)
class TransitionProfile:
    name: str
    event_type: str
    target: str
    unit: str
    reference_signals: tuple[str, ...] = ()
    before_seconds: float = 1.5
    after_seconds: float = 2.5
    min_window_samples: int = 4
    min_baseline_windows: int = 5
    min_expected_abs_delta: float = 0.5
    min_observed_abs_delta: float = 0.05
    low_delta_ratio: float = 0.35
    high_delta_ratio: float = 2.75
    flat_range_ratio: float = 0.30
    lag_tolerance_seconds: float = 0.75
    noise_ratio: float = 3.0
    noise_abs: float = 0.5
    correlation_drop: float = 0.45
    signal_tier: int = 0
    severity: str = "warning"
    message: str = "Signal response differs from this vehicle's learned transition baseline"
    suspected_causes: tuple[str, ...] = ()


@dataclass
class _PendingWindow:
    profile: TransitionProfile
    event: TransitionEvent


@dataclass
class TransitionTemplate:
    profile: TransitionProfile
    count: int = 0
    metrics: dict[str, RunningStats] = field(default_factory=dict)
    correlations: dict[str, RunningStats] = field(default_factory=dict)
    event_counts: Counter[str] = field(default_factory=Counter)
    first_seen: float | None = None
    last_seen: float | None = None

    @property
    def ready(self) -> bool:
        return self.count >= self.profile.min_baseline_windows

    def update(self, metrics: dict[str, Any], event: TransitionEvent) -> None:
        timestamp = event.timestamp
        if self.count == 0:
            self.first_seen = timestamp
        self.count += 1
        self.last_seen = timestamp
        self.event_counts[event.name] += 1
        for key in (
            "beforeMean",
            "afterMean",
            "delta",
            "absDelta",
            "valueRange",
            "beforeRange",
            "afterRange",
            "responseLagSeconds",
            "slopeBefore",
            "slopeAfter",
            "noiseScore",
        ):
            value = number_or_none(metrics.get(key))
            if value is not None:
                self.metrics.setdefault(key, RunningStats()).update(value, timestamp)
        for signal, value in (metrics.get("correlations") or {}).items():
            numeric = number_or_none(value)
            if numeric is not None:
                self.correlations.setdefault(str(signal), RunningStats()).update(numeric, timestamp)

    def score(self, metrics: dict[str, Any], event: TransitionEvent) -> list[dict[str, Any]]:
        if not self.ready:
            return []
        reasons = self._anomaly_reasons(metrics)
        if not reasons:
            return []
        findings: list[dict[str, Any]] = []
        for reason in reasons:
            anomaly_class = reason["class"]
            code = f"{self.profile.name}_{anomaly_class}"
            confidence = self._confidence(reason)
            findings.append(
                make_diagnostic_finding(
                    source="transitionMonitor",
                    subject=self.profile.target,
                    code=code,
                    severity=self.profile.severity,
                    message=self.profile.message,
                    confidence=confidence,
                    eventType=event.name,
                    anomalyClass=anomaly_class,
                    observedDelta=_rounded(metrics.get("absDelta")),
                    expectedDelta=_rounded(self._mean("absDelta")),
                    observedRange=_rounded(metrics.get("valueRange")),
                    expectedRange=_rounded(self._mean("valueRange")),
                    observedLagSeconds=_rounded(metrics.get("responseLagSeconds")),
                    expectedLagSeconds=_rounded(self._mean("responseLagSeconds")),
                    baselineWindows=self.count,
                    signalTier=self.profile.signal_tier,
                    suspectedCauses=list(self.profile.suspected_causes),
                )
            )
        return findings

    def snapshot(self) -> dict[str, Any]:
        return {
            "name": self.profile.name,
            "eventType": self.profile.event_type,
            "target": self.profile.target,
            "unit": self.profile.unit,
            "signalTier": self.profile.signal_tier,
            "signalTierName": SIGNAL_TIERS.get(self.profile.signal_tier, "unknown"),
            "ready": self.ready,
            "windows": self.count,
            "firstSeen": self.first_seen,
            "lastSeen": self.last_seen,
            "eventCounts": dict(sorted(self.event_counts.items())),
            "metrics": {
                key: _stats_snapshot(stats)
                for key, stats in sorted(self.metrics.items())
            },
        }

    def to_json(self) -> dict[str, Any]:
        return {
            "profile": self.profile.name,
            "count": self.count,
            "metrics": {
                key: _running_stats_to_json(stats)
                for key, stats in self.metrics.items()
            },
            "correlations": {
                key: _running_stats_to_json(stats)
                for key, stats in self.correlations.items()
            },
            "eventCounts": dict(self.event_counts),
            "firstSeen": self.first_seen,
            "lastSeen": self.last_seen,
        }

    def load_json(self, payload: dict[str, Any]) -> None:
        self.count = int(number_or_none(payload.get("count")) or 0)
        self.metrics = {
            str(key): _running_stats_from_json(value)
            for key, value in (payload.get("metrics") or {}).items()
            if isinstance(value, dict)
        }
        self.correlations = {
            str(key): _running_stats_from_json(value)
            for key, value in (payload.get("correlations") or {}).items()
            if isinstance(value, dict)
        }
        self.event_counts = Counter({str(key): int(value) for key, value in (payload.get("eventCounts") or {}).items()})
        self.first_seen = number_or_none(payload.get("firstSeen"))
        self.last_seen = number_or_none(payload.get("lastSeen"))

    def _anomaly_reasons(self, metrics: dict[str, Any]) -> list[dict[str, Any]]:
        reasons: list[dict[str, Any]] = []
        expected_abs_delta = self._mean("absDelta")
        observed_abs_delta = number_or_none(metrics.get("absDelta"))
        expected_range = self._mean("valueRange")
        observed_range = number_or_none(metrics.get("valueRange"))
        expected_delta = self._mean("delta")
        observed_delta = number_or_none(metrics.get("delta"))
        expected_lag = self._mean("responseLagSeconds")
        observed_lag = number_or_none(metrics.get("responseLagSeconds"))
        expected_noise = self._mean("noiseScore")
        observed_noise = number_or_none(metrics.get("noiseScore"))

        if expected_abs_delta is not None and expected_abs_delta >= self.profile.min_expected_abs_delta:
            low_limit = max(self.profile.min_observed_abs_delta, expected_abs_delta * self.profile.low_delta_ratio)
            if observed_abs_delta is None or observed_abs_delta <= self.profile.min_observed_abs_delta:
                reasons.append({"class": "no_response", "severity": observed_abs_delta or 0.0, "expected": expected_abs_delta})
            elif observed_abs_delta < low_limit:
                reasons.append({"class": "too_small_delta", "severity": low_limit - observed_abs_delta, "expected": expected_abs_delta})

            high_limit = max(expected_abs_delta + self.profile.min_expected_abs_delta, expected_abs_delta * self.profile.high_delta_ratio)
            if observed_abs_delta is not None and observed_abs_delta > high_limit:
                reasons.append({"class": "too_large_delta", "severity": observed_abs_delta - high_limit, "expected": expected_abs_delta})

        if expected_range is not None and expected_range >= self.profile.min_expected_abs_delta:
            flat_limit = max(self.profile.min_observed_abs_delta, expected_range * self.profile.flat_range_ratio)
            if observed_range is not None and observed_range <= flat_limit:
                reasons.append({"class": "stuck_flat", "severity": flat_limit - observed_range, "expected": expected_range})

        if expected_delta is not None and observed_delta is not None and abs(expected_delta) >= self.profile.min_expected_abs_delta:
            if math.copysign(1.0, expected_delta) != math.copysign(1.0, observed_delta) and abs(observed_delta) >= self.profile.min_observed_abs_delta:
                reasons.append({"class": "wrong_sequence", "severity": abs(expected_delta - observed_delta), "expected": abs(expected_delta)})

        if expected_lag is not None and observed_lag is not None:
            lag_limit = expected_lag + self.profile.lag_tolerance_seconds
            if observed_lag > lag_limit:
                reasons.append({"class": "delayed_response", "severity": observed_lag - lag_limit, "expected": expected_lag})

        if expected_noise is not None and observed_noise is not None:
            noise_limit = max(expected_noise + self.profile.noise_abs, expected_noise * self.profile.noise_ratio)
            if observed_noise > noise_limit:
                reasons.append({"class": "unexpected_noise", "severity": observed_noise - noise_limit, "expected": expected_noise})

        for signal, expected_corr_stats in self.correlations.items():
            expected_corr = expected_corr_stats.mean
            observed_corr = number_or_none((metrics.get("correlations") or {}).get(signal))
            if observed_corr is None:
                continue
            if abs(expected_corr) >= self.profile.correlation_drop and abs(observed_corr) < max(0.10, abs(expected_corr) * 0.35):
                reasons.append({"class": "wrong_correlation", "severity": abs(expected_corr) - abs(observed_corr), "expected": abs(expected_corr)})

        before_mean = number_or_none(metrics.get("beforeMean"))
        expected_before = self._mean("beforeMean")
        before_std = self._stddev("beforeMean")
        if before_mean is not None and expected_before is not None and self.count >= self.profile.min_baseline_windows:
            offset_limit = max(self.profile.min_expected_abs_delta, before_std * 3.0)
            if abs(before_mean - expected_before) > offset_limit:
                reasons.append({"class": "persistent_offset", "severity": abs(before_mean - expected_before) - offset_limit, "expected": offset_limit})

        return _dedupe_reasons(reasons)

    def _confidence(self, reason: dict[str, Any]) -> float:
        baseline_strength = clamp(self.count / max(self.profile.min_baseline_windows * 3.0, 1.0), high=0.35)
        severity = number_or_none(reason.get("severity")) or 0.0
        expected = max(number_or_none(reason.get("expected")) or 1.0, 1.0)
        deviation_strength = clamp(severity / expected, high=0.45)
        return clamp(0.45 + baseline_strength + deviation_strength)

    def _mean(self, key: str) -> float | None:
        stats = self.metrics.get(key)
        return stats.mean if stats is not None and stats.count else None

    def _stddev(self, key: str) -> float:
        stats = self.metrics.get(key)
        return stats.stddev if stats is not None else 0.0


class VehicleTransitionMonitor:
    def __init__(
        self,
        profiles: list[TransitionProfile],
        *,
        storage_path: str | Path | None = None,
        enabled: bool = True,
        learn_enabled: bool = True,
        save_every_windows: int = 5,
        min_save_interval_seconds: float = 30.0,
        lineage: dict[str, Any] | None = None,
    ) -> None:
        self.profiles = profiles
        self.storage_path = Path(storage_path) if storage_path else None
        self.enabled = enabled
        self.learn_enabled = learn_enabled
        self.save_every_windows = max(1, save_every_windows)
        self.min_save_interval_seconds = max(0.0, min_save_interval_seconds)
        self._segmenter = EventSegmenter()
        self._history: deque[tuple[float, dict[str, Any]]] = deque(maxlen=1000)
        self._pending: list[_PendingWindow] = []
        self._templates = {profile.name: TransitionTemplate(profile) for profile in profiles}
        self._events_seen: Counter[str] = Counter()
        self._windows_scored = 0
        self._windows_learned = 0
        self._last_event: dict[str, Any] | None = None
        self._last_error: str | None = None
        self._last_save_at = 0.0
        self._learned_since_save = 0
        self._lineage = dict(lineage or {})
        self._load()

    def observe(self, state: dict[str, Any], *, timestamp: float | None = None, learn_allowed: bool | None = None) -> dict[str, Any]:
        now = time.time() if timestamp is None else timestamp
        if not self.enabled:
            return self._summary(findings=[])

        self._history.append((now, state))
        self._prune_history(now)
        findings: list[dict[str, Any]] = []

        for event in self._segmenter.observe(state, now):
            self._events_seen[event.name] += 1
            self._last_event = event.to_json()
            for profile in self.profiles:
                if profile.event_type == event.name:
                    self._pending.append(_PendingWindow(profile=profile, event=event))

        pending: list[_PendingWindow] = []
        for window in self._pending:
            if now < window.event.timestamp + window.profile.after_seconds:
                pending.append(window)
                continue
            findings.extend(self._finalize(window, learn_allowed=learn_allowed, state=state))
        self._pending = pending
        self._save_if_due(now)
        return self._summary(findings=findings)

    def snapshot(self) -> dict[str, Any]:
        return self._summary(findings=[])

    def to_json(self) -> dict[str, Any]:
        return {
            "version": SCHEMA_VERSION,
            "kind": "vehicle_transition_baseline",
            "generatedAt": time.time(),
            "models": {
                name: template.to_json()
                for name, template in sorted(self._templates.items())
            },
            "lineage": {
                "truthSource": "per_vehicle_known_good",
                "eventsSeen": dict(self._events_seen),
                "vehicleProfile": self._lineage.get("vehicleProfile"),
                "sessionIds": _lineage_list(self._lineage.get("sessionIds")),
                "thermalStartClasses": _lineage_list(self._lineage.get("thermalStartClasses")),
                "observedContexts": _lineage_list(self._lineage.get("observedContexts")),
                "decoderVersions": _lineage_list(self._lineage.get("decoderVersions")),
            },
        }

    def _finalize(self, window: _PendingWindow, *, learn_allowed: bool | None, state: dict[str, Any]) -> list[dict[str, Any]]:
        profile = window.profile
        samples = [
            sample
            for sample in self._history
            if window.event.timestamp - profile.before_seconds <= sample[0] <= window.event.timestamp + profile.after_seconds
        ]
        metrics = transition_window_metrics(
            samples,
            event_timestamp=window.event.timestamp,
            target=profile.target,
            reference_signals=profile.reference_signals,
            before_seconds=profile.before_seconds,
            after_seconds=profile.after_seconds,
        )
        if int(metrics.get("totalCount", 0)) < profile.min_window_samples:
            return []
        template = self._templates[profile.name]
        self._windows_scored += 1
        findings = template.score(metrics, window.event)
        should_learn = self.learn_enabled if learn_allowed is None else bool(learn_allowed)
        should_learn = should_learn and _state_allows_learning(state)
        if should_learn and not findings:
            template.update(metrics, window.event)
            self._windows_learned += 1
            self._learned_since_save += 1
        return [finding for finding in findings if _runtime_promotable(finding)]

    def _summary(self, *, findings: list[dict[str, Any]]) -> dict[str, Any]:
        models = [template.snapshot() for template in self._templates.values()]
        ready_models = [model["name"] for model in models if model.get("ready")]
        return {
            "enabled": self.enabled,
            "ok": not any(normalize_severity(finding.get("severity")) in {"warning", "error"} for finding in findings),
            "storagePath": str(self.storage_path) if self.storage_path else None,
            "activeEvent": self._last_event,
            "coverage": {
                "eventsSeen": dict(sorted(self._events_seen.items())),
                "windowsScored": self._windows_scored,
                "windowsLearned": self._windows_learned,
                "pendingWindows": len(self._pending),
                "readyModels": ready_models,
            },
            "models": models,
            "findings": findings,
            "lastError": self._last_error,
        }

    def _prune_history(self, now: float) -> None:
        max_before = max((profile.before_seconds for profile in self.profiles), default=2.0)
        max_after = max((profile.after_seconds for profile in self.profiles), default=3.0)
        keep_seconds = max_before + max_after + 2.0
        while self._history and now - self._history[0][0] > keep_seconds:
            self._history.popleft()

    def _load(self) -> None:
        if self.storage_path is None or not self.storage_path.exists():
            return
        try:
            payload = json.loads(self.storage_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            self._last_error = str(exc)
            return
        model_payloads = payload.get("models", {}) if isinstance(payload, dict) else {}
        if not isinstance(model_payloads, dict):
            return
        for name, model_payload in model_payloads.items():
            template = self._templates.get(str(name))
            if template is not None and isinstance(model_payload, dict):
                template.load_json(model_payload)
        lineage = payload.get("lineage", {}) if isinstance(payload, dict) else {}
        if isinstance(lineage, dict) and isinstance(lineage.get("eventsSeen"), dict):
            self._events_seen.update({str(key): int(value) for key, value in lineage["eventsSeen"].items()})
        if isinstance(lineage, dict):
            self._lineage.update({key: value for key, value in lineage.items() if key != "eventsSeen"})

    def _save_if_due(self, now: float) -> None:
        if self.storage_path is None or self._learned_since_save < self.save_every_windows:
            return
        if now - self._last_save_at < self.min_save_interval_seconds:
            return
        try:
            self.storage_path.parent.mkdir(parents=True, exist_ok=True)
            self.storage_path.write_text(json.dumps(self.to_json(), indent=2, sort_keys=True) + "\n", encoding="utf-8")
            self._last_save_at = now
            self._learned_since_save = 0
            self._last_error = None
        except OSError as exc:
            self._last_error = str(exc)


def default_transition_profiles() -> list[TransitionProfile]:
    return [
        TransitionProfile(
            name="startup_maf_response",
            event_type="first_fire",
            target="mafGps",
            unit="g/s",
            reference_signals=("rpm", "mapKpa", "engineLoadPct"),
            before_seconds=1.2,
            after_seconds=2.5,
            min_window_samples=4,
            min_baseline_windows=4,
            min_expected_abs_delta=1.0,
            min_observed_abs_delta=0.20,
            low_delta_ratio=0.35,
            flat_range_ratio=0.30,
            signal_tier=0,
            message="MAF response during startup differs from this vehicle's learned start behavior",
            suspected_causes=(
                "MAF signal, power, ground, or connector fault",
                "intake airflow path issue",
                "decoder or source mapping mismatch",
            ),
        ),
        TransitionProfile(
            name="startup_map_response",
            event_type="first_fire",
            target="mapKpa",
            unit="kPa",
            reference_signals=("rpm", "mafGps", "engineLoadPct"),
            before_seconds=1.2,
            after_seconds=2.5,
            min_window_samples=4,
            min_baseline_windows=4,
            min_expected_abs_delta=3.0,
            min_observed_abs_delta=1.0,
            low_delta_ratio=0.35,
            flat_range_ratio=0.35,
            signal_tier=0,
            message="MAP response during startup differs from this vehicle's learned start behavior",
            suspected_causes=(
                "MAP signal, power, ground, or connector fault",
                "intake pressure path issue",
                "load/airflow signal mismatch",
            ),
        ),
        TransitionProfile(
            name="throttle_tip_in_maf_response",
            event_type="throttle_tip_in",
            target="mafGps",
            unit="g/s",
            reference_signals=("throttlePct", "rpm", "mapKpa"),
            before_seconds=1.0,
            after_seconds=2.5,
            min_window_samples=4,
            min_baseline_windows=5,
            min_expected_abs_delta=1.0,
            min_observed_abs_delta=0.20,
            low_delta_ratio=0.35,
            flat_range_ratio=0.30,
            signal_tier=0,
            message="MAF response during throttle input differs from this vehicle's learned behavior",
            suspected_causes=(
                "airflow sensor response fault",
                "intake restriction",
                "throttle/load signal mismatch",
            ),
        ),
        TransitionProfile(
            name="shift_rpm_response",
            event_type="shift",
            target="rpm",
            unit="rpm",
            reference_signals=("speedKph",),
            before_seconds=1.0,
            after_seconds=2.0,
            min_window_samples=4,
            min_baseline_windows=5,
            min_expected_abs_delta=150.0,
            min_observed_abs_delta=50.0,
            low_delta_ratio=0.30,
            flat_range_ratio=0.35,
            signal_tier=0,
            message="RPM response during shift differs from this vehicle's learned behavior",
            suspected_causes=(
                "transmission slip or shift timing issue",
                "RPM/speed signal mismatch",
            ),
        ),
    ]


def _state_allows_learning(state: dict[str, Any]) -> bool:
    health = state.get("_health") if isinstance(state.get("_health"), dict) else {}
    if health.get("stale"):
        return False
    if health.get("signalFaults"):
        return False
    baseline = health.get("vehicleBaseline") if isinstance(health.get("vehicleBaseline"), dict) else {}
    if baseline.get("findings"):
        return False
    return True


def _runtime_promotable(finding: dict[str, Any]) -> bool:
    details = finding.get("details") if isinstance(finding.get("details"), dict) else {}
    tier = int(number_or_none(details.get("signalTier")) or 0)
    return tier <= 2


def _dedupe_reasons(reasons: list[dict[str, Any]]) -> list[dict[str, Any]]:
    ordered_classes = {name: index for index, name in enumerate(ANOMALY_CLASSES)}
    by_class: dict[str, dict[str, Any]] = {}
    for reason in reasons:
        class_name = str(reason.get("class"))
        existing = by_class.get(class_name)
        if existing is None or (number_or_none(reason.get("severity")) or 0.0) > (number_or_none(existing.get("severity")) or 0.0):
            by_class[class_name] = reason
    return sorted(by_class.values(), key=lambda item: ordered_classes.get(str(item.get("class")), 999))


def _rounded(value: Any) -> float | None:
    numeric = number_or_none(value)
    return round(numeric, 4) if numeric is not None else None


def _stats_snapshot(stats: RunningStats) -> dict[str, Any]:
    return {
        "count": stats.count,
        "mean": round(stats.mean, 6),
        "stddev": round(stats.stddev, 6),
        "min": _rounded(stats.minimum),
        "max": _rounded(stats.maximum),
    }


def _running_stats_to_json(stats: RunningStats) -> dict[str, Any]:
    return {
        "count": stats.count,
        "mean": stats.mean,
        "m2": stats.m2,
        "minimum": stats.minimum,
        "maximum": stats.maximum,
        "firstSeen": stats.first_seen,
        "lastSeen": stats.last_seen,
    }


def _running_stats_from_json(payload: dict[str, Any]) -> RunningStats:
    return RunningStats(
        count=int(number_or_none(payload.get("count")) or 0),
        mean=float(number_or_none(payload.get("mean")) or 0.0),
        m2=float(number_or_none(payload.get("m2")) or 0.0),
        minimum=number_or_none(payload.get("minimum")),
        maximum=number_or_none(payload.get("maximum")),
        first_seen=number_or_none(payload.get("firstSeen")),
        last_seen=number_or_none(payload.get("lastSeen")),
    )


def _lineage_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        return [str(item) for item in value if str(item).strip()]
    return [str(value)]
