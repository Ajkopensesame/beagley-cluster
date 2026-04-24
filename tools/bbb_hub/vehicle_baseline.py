from __future__ import annotations

import json
import math
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from tools.vehicle_analysis.values import number_or_none


@dataclass(frozen=True)
class BaselineFeature:
    signal: str
    bucket_size: float
    minimum: float | None = None
    maximum: float | None = None
    required: bool = True


@dataclass(frozen=True)
class BaselineCondition:
    signal: str
    minimum: float | None = None
    maximum: float | None = None


@dataclass(frozen=True)
class BaselineProfile:
    name: str
    target: str
    unit: str
    features: tuple[BaselineFeature, ...]
    conditions: tuple[BaselineCondition, ...] = ()
    direction: str = "both"
    target_minimum: float | None = None
    target_maximum: float | None = None
    min_bucket_samples: int = 30
    min_total_samples: int = 200
    min_anomaly_samples: int = 6
    min_anomaly_buckets: int = 2
    anomaly_window_seconds: float = 900.0
    drift_fraction: float = 0.20
    drift_abs: float = 2.0
    drift_stddev: float = 2.5
    low_code: str = "baseline_low"
    high_code: str = "baseline_high"
    low_message: str = "Signal is consistently below this vehicle's learned baseline"
    high_message: str = "Signal is consistently above this vehicle's learned baseline"
    suspected_causes: tuple[str, ...] = ()


@dataclass
class BaselineBucket:
    key: str
    features: dict[str, Any]
    count: int = 0
    mean: float = 0.0
    m2: float = 0.0
    minimum: float | None = None
    maximum: float | None = None
    first_seen: float | None = None
    last_seen: float | None = None

    @property
    def stddev(self) -> float:
        if self.count < 2:
            return 0.0
        return math.sqrt(max(0.0, self.m2 / (self.count - 1)))

    def update(self, value: float, timestamp: float) -> None:
        if self.count == 0:
            self.first_seen = timestamp
            self.minimum = value
            self.maximum = value
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        self.m2 += delta * (value - self.mean)
        self.minimum = value if self.minimum is None else min(self.minimum, value)
        self.maximum = value if self.maximum is None else max(self.maximum, value)
        self.last_seen = timestamp

    def to_json(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "features": self.features,
            "count": self.count,
            "mean": self.mean,
            "m2": self.m2,
            "minimum": self.minimum,
            "maximum": self.maximum,
            "firstSeen": self.first_seen,
            "lastSeen": self.last_seen,
        }

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> "BaselineBucket":
        return cls(
            key=str(payload["key"]),
            features=dict(payload.get("features", {})),
            count=int(payload.get("count", 0)),
            mean=float(payload.get("mean", 0.0)),
            m2=float(payload.get("m2", 0.0)),
            minimum=number_or_none(payload.get("minimum")),
            maximum=number_or_none(payload.get("maximum")),
            first_seen=number_or_none(payload.get("firstSeen")),
            last_seen=number_or_none(payload.get("lastSeen")),
        )


@dataclass
class _Sample:
    target_value: float
    bucket_key: str
    bucket_features: dict[str, Any]


@dataclass
class _Observation:
    status: str
    confidence: float
    learned: bool = False
    reason: str | None = None
    bucket: BaselineBucket | None = None
    findings: list[dict[str, Any]] = field(default_factory=list)


class VehicleBaselineModel:
    """Learns one target signal against automatically bucketed operating conditions."""

    def __init__(self, profile: BaselineProfile) -> None:
        self.profile = profile
        self._buckets: dict[str, BaselineBucket] = {}
        self._anomalies: deque[dict[str, Any]] = deque(maxlen=500)
        self._last_status = "waiting"
        self._last_reason: str | None = None
        self._last_bucket_key: str | None = None

    @property
    def total_samples(self) -> int:
        return sum(bucket.count for bucket in self._buckets.values())

    def observe(self, state: dict[str, Any], timestamp: float | None = None) -> dict[str, Any]:
        now = time.time() if timestamp is None else timestamp
        self._prune_anomalies(now)
        sample, reason = self._extract_sample(state)
        if sample is None:
            observation = _Observation("skipped", confidence=0.0, reason=reason)
            return self._summary(observation)

        bucket = self._buckets.get(sample.bucket_key)
        if bucket is None:
            bucket = BaselineBucket(sample.bucket_key, sample.bucket_features)
            self._buckets[sample.bucket_key] = bucket

        self._last_bucket_key = sample.bucket_key
        ready = self._is_ready(bucket)
        if ready:
            anomaly = self._classify(bucket, sample.target_value)
            if anomaly is not None:
                self._record_anomaly(now, bucket, sample.target_value, anomaly)
                findings = self._promoted_findings(now, anomaly["direction"])
                observation = _Observation(
                    "anomaly" if findings else "watching_anomaly",
                    confidence=self._model_confidence(bucket),
                    bucket=bucket,
                    findings=findings,
                )
                return self._summary(observation)

        bucket.update(sample.target_value, now)
        status = "normal" if ready else "learning"
        observation = _Observation(status, confidence=self._model_confidence(bucket), learned=True, bucket=bucket)
        return self._summary(observation)

    def snapshot(self) -> dict[str, Any]:
        return {
            "name": self.profile.name,
            "target": self.profile.target,
            "unit": self.profile.unit,
            "status": self._last_status,
            "reason": self._last_reason,
            "confidence": self._overall_confidence(),
            "ready": self._overall_ready(),
            "bucketCount": len(self._buckets),
            "totalSamples": self.total_samples,
            "lastBucket": self._last_bucket_key,
            "activeAnomalies": len(self._anomalies),
        }

    def to_json(self) -> dict[str, Any]:
        return {
            "name": self.profile.name,
            "target": self.profile.target,
            "unit": self.profile.unit,
            "buckets": {key: bucket.to_json() for key, bucket in self._buckets.items()},
        }

    def load_json(self, payload: dict[str, Any]) -> None:
        buckets = payload.get("buckets", {})
        if not isinstance(buckets, dict):
            return
        self._buckets = {}
        for key, bucket_payload in buckets.items():
            if isinstance(bucket_payload, dict):
                self._buckets[str(key)] = BaselineBucket.from_json(bucket_payload)

    def _extract_sample(self, state: dict[str, Any]) -> tuple[_Sample | None, str | None]:
        target_value = _read_numeric(state, self.profile.target)
        if target_value is None:
            return None, f"missing target {self.profile.target}"
        if self.profile.target_minimum is not None and target_value < self.profile.target_minimum:
            return None, f"{self.profile.target} below learning range"
        if self.profile.target_maximum is not None and target_value > self.profile.target_maximum:
            return None, f"{self.profile.target} above learning range"

        for condition in self.profile.conditions:
            value = _read_numeric(state, condition.signal)
            if value is None:
                return None, f"missing condition {condition.signal}"
            if condition.minimum is not None and value < condition.minimum:
                return None, f"{condition.signal} below required range"
            if condition.maximum is not None and value > condition.maximum:
                return None, f"{condition.signal} above required range"

        key_parts: list[str] = []
        bucket_features: dict[str, Any] = {}
        for feature in self.profile.features:
            value = _read_numeric(state, feature.signal)
            if value is None:
                if feature.required:
                    return None, f"missing feature {feature.signal}"
                continue
            if feature.minimum is not None and value < feature.minimum:
                if feature.required:
                    return None, f"{feature.signal} below learning range"
                continue
            if feature.maximum is not None and value > feature.maximum:
                if feature.required:
                    return None, f"{feature.signal} above learning range"
                continue
            if feature.bucket_size <= 0:
                return None, f"{feature.signal} bucket size must be positive"
            bucket_index = math.floor(value / feature.bucket_size)
            key_parts.append(f"{feature.signal}:{bucket_index}")
            bucket_features[feature.signal] = {
                "bucketIndex": bucket_index,
                "bucketSize": feature.bucket_size,
                "low": bucket_index * feature.bucket_size,
                "high": (bucket_index + 1) * feature.bucket_size,
            }
        if not key_parts:
            return None, "no usable baseline features"
        return _Sample(target_value, "|".join(key_parts), bucket_features), None

    def _is_ready(self, bucket: BaselineBucket) -> bool:
        return bucket.count >= self.profile.min_bucket_samples and self.total_samples >= self.profile.min_total_samples

    def _overall_ready(self) -> bool:
        return any(bucket.count >= self.profile.min_bucket_samples for bucket in self._buckets.values()) and (
            self.total_samples >= self.profile.min_total_samples
        )

    def _classify(self, bucket: BaselineBucket, value: float) -> dict[str, Any] | None:
        threshold = max(
            self.profile.drift_abs,
            abs(bucket.mean) * self.profile.drift_fraction,
            bucket.stddev * self.profile.drift_stddev,
        )
        low_limit = bucket.mean - threshold
        high_limit = bucket.mean + threshold
        if self.profile.direction in {"low", "both"} and value < low_limit:
            return {
                "direction": "low",
                "code": self.profile.low_code,
                "message": self.profile.low_message,
                "expected": bucket.mean,
                "normalLow": low_limit,
                "normalHigh": high_limit,
                "deviation": value - bucket.mean,
                "threshold": threshold,
            }
        if self.profile.direction in {"high", "both"} and value > high_limit:
            return {
                "direction": "high",
                "code": self.profile.high_code,
                "message": self.profile.high_message,
                "expected": bucket.mean,
                "normalLow": low_limit,
                "normalHigh": high_limit,
                "deviation": value - bucket.mean,
                "threshold": threshold,
            }
        return None

    def _record_anomaly(self, now: float, bucket: BaselineBucket, value: float, anomaly: dict[str, Any]) -> None:
        self._anomalies.append(
            {
                "timestamp": now,
                "model": self.profile.name,
                "signal": self.profile.target,
                "direction": anomaly["direction"],
                "code": anomaly["code"],
                "bucketKey": bucket.key,
                "bucketSamples": bucket.count,
                "value": value,
                "expected": anomaly["expected"],
                "normalLow": anomaly["normalLow"],
                "normalHigh": anomaly["normalHigh"],
                "deviation": anomaly["deviation"],
            }
        )

    def _promoted_findings(self, now: float, direction: str) -> list[dict[str, Any]]:
        recent = self._recent_anomalies(now, direction)
        bucket_count = len({event["bucketKey"] for event in recent})
        if len(recent) < self.profile.min_anomaly_samples or bucket_count < self.profile.min_anomaly_buckets:
            return []
        latest = recent[-1]
        confidence = self._finding_confidence(recent)
        code = self.profile.low_code if direction == "low" else self.profile.high_code
        message = self.profile.low_message if direction == "low" else self.profile.high_message
        return [
            {
                "source": "vehicleBaseline",
                "model": self.profile.name,
                "signal": self.profile.target,
                "code": code,
                "severity": "warning",
                "message": message,
                "confidence": confidence,
                "details": {
                    "unit": self.profile.unit,
                    "direction": direction,
                    "sampleCount": len(recent),
                    "bucketCount": bucket_count,
                    "windowSeconds": self.profile.anomaly_window_seconds,
                    "latestValue": round(latest["value"], 3),
                    "expectedValue": round(latest["expected"], 3),
                    "normalLow": round(latest["normalLow"], 3),
                    "normalHigh": round(latest["normalHigh"], 3),
                    "deviation": round(latest["deviation"], 3),
                    "suspectedCauses": list(self.profile.suspected_causes),
                    "recentEvidence": [_round_event(event) for event in recent[-8:]],
                },
            }
        ]

    def _recent_anomalies(self, now: float, direction: str) -> list[dict[str, Any]]:
        cutoff = now - self.profile.anomaly_window_seconds
        return [
            event
            for event in self._anomalies
            if event["timestamp"] >= cutoff and event["direction"] == direction and event["model"] == self.profile.name
        ]

    def _prune_anomalies(self, now: float) -> None:
        cutoff = now - self.profile.anomaly_window_seconds
        while self._anomalies and self._anomalies[0]["timestamp"] < cutoff:
            self._anomalies.popleft()

    def _finding_confidence(self, recent: list[dict[str, Any]]) -> float:
        sample_score = min(1.0, len(recent) / max(1, self.profile.min_anomaly_samples * 2))
        bucket_score = min(1.0, len({event["bucketKey"] for event in recent}) / max(1, self.profile.min_anomaly_buckets))
        baseline_score = min(1.0, max(event["bucketSamples"] for event in recent) / max(1, self.profile.min_bucket_samples * 4))
        return round(min(0.95, 0.35 + sample_score * 0.25 + bucket_score * 0.20 + baseline_score * 0.20), 3)

    def _model_confidence(self, bucket: BaselineBucket) -> float:
        bucket_score = min(1.0, bucket.count / max(1, self.profile.min_bucket_samples))
        total_score = min(1.0, self.total_samples / max(1, self.profile.min_total_samples))
        return round((bucket_score * 0.65) + (total_score * 0.35), 3)

    def _overall_confidence(self) -> float:
        if not self._buckets:
            return 0.0
        return round(
            min(
                1.0,
                max(min(1.0, bucket.count / max(1, self.profile.min_bucket_samples)) for bucket in self._buckets.values())
                * 0.65
                + min(1.0, self.total_samples / max(1, self.profile.min_total_samples)) * 0.35,
            ),
            3,
        )

    def _summary(self, observation: _Observation) -> dict[str, Any]:
        self._last_status = observation.status
        self._last_reason = observation.reason
        bucket_summary = None
        if observation.bucket is not None:
            bucket_summary = {
                "key": observation.bucket.key,
                "samples": observation.bucket.count,
                "mean": round(observation.bucket.mean, 3),
                "stddev": round(observation.bucket.stddev, 3),
            }
        return {
            **self.snapshot(),
            "status": observation.status,
            "reason": observation.reason,
            "confidence": observation.confidence,
            "learned": observation.learned,
            "bucket": bucket_summary,
            "findings": observation.findings,
        }


class VehicleBaselineMonitor:
    def __init__(
        self,
        profiles: list[BaselineProfile],
        *,
        storage_path: str | Path | None = None,
        enabled: bool = True,
        save_every_samples: int = 25,
        min_save_interval_seconds: float = 30.0,
    ) -> None:
        self.enabled = enabled
        self.storage_path = Path(storage_path) if storage_path else None
        self.save_every_samples = max(1, save_every_samples)
        self.min_save_interval_seconds = max(0.0, min_save_interval_seconds)
        self.models = [VehicleBaselineModel(profile) for profile in profiles]
        self._learned_since_save = 0
        self._last_save_time = 0.0
        self._writes = 0
        self._last_error: str | None = None
        self._load()

    def observe(self, state: dict[str, Any], timestamp: float | None = None) -> dict[str, Any]:
        now = time.time() if timestamp is None else timestamp
        if not self.enabled:
            return {"enabled": False, "ok": True, "findings": []}
        findings: list[dict[str, Any]] = []
        model_results: list[dict[str, Any]] = []
        learned = 0
        for model in self.models:
            result = model.observe(state, timestamp=now)
            model_results.append(result)
            findings.extend(result.get("findings", []))
            if result.get("learned"):
                learned += 1
        if learned:
            self._learned_since_save += learned
            self._maybe_save(now)
        return {
            "enabled": True,
            "ok": not findings,
            "storagePath": str(self.storage_path) if self.storage_path else None,
            "writes": self._writes,
            "lastError": self._last_error,
            "findings": findings,
            "models": model_results,
        }

    def snapshot(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "storagePath": str(self.storage_path) if self.storage_path else None,
            "writes": self._writes,
            "lastError": self._last_error,
            "models": [model.snapshot() for model in self.models],
        }

    def save(self) -> None:
        if self.storage_path is None:
            return
        payload = {
            "version": 1,
            "updatedAt": time.time(),
            "models": {model.profile.name: model.to_json() for model in self.models},
        }
        try:
            self.storage_path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = self.storage_path.with_suffix(self.storage_path.suffix + ".tmp")
            tmp_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
            tmp_path.replace(self.storage_path)
            self._learned_since_save = 0
            self._last_save_time = time.time()
            self._writes += 1
            self._last_error = None
        except OSError as exc:
            self._last_error = str(exc)

    def _maybe_save(self, now: float) -> None:
        if self.storage_path is None:
            return
        if self._learned_since_save < self.save_every_samples:
            return
        if now - self._last_save_time < self.min_save_interval_seconds:
            return
        self.save()

    def _load(self) -> None:
        if self.storage_path is None or not self.storage_path.exists():
            return
        try:
            payload = json.loads(self.storage_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            self._last_error = str(exc)
            return
        model_payloads = payload.get("models", {})
        if not isinstance(model_payloads, dict):
            return
        by_name = {model.profile.name: model for model in self.models}
        for name, model_payload in model_payloads.items():
            model = by_name.get(str(name))
            if model is not None and isinstance(model_payload, dict):
                model.load_json(model_payload)


def default_vehicle_baseline_profiles() -> list[BaselineProfile]:
    return [
        BaselineProfile(
            name="intake_airflow",
            target="mafGps",
            unit="g/s",
            features=(
                BaselineFeature("rpm", 250.0, minimum=800.0, maximum=7000.0),
                BaselineFeature("throttlePct", 10.0, minimum=5.0, maximum=100.0),
                BaselineFeature("intakeAirTempC", 10.0, minimum=-20.0, maximum=90.0),
                BaselineFeature("engineLoadPct", 10.0, minimum=0.0, maximum=100.0, required=False),
                BaselineFeature("mapKpa", 10.0, minimum=10.0, maximum=250.0, required=False),
            ),
            conditions=(
                BaselineCondition("coolantC", minimum=70.0, maximum=115.0),
            ),
            direction="low",
            target_minimum=0.0,
            target_maximum=400.0,
            min_bucket_samples=30,
            min_total_samples=150,
            min_anomaly_samples=6,
            min_anomaly_buckets=2,
            anomaly_window_seconds=900.0,
            drift_fraction=0.18,
            drift_abs=3.0,
            drift_stddev=2.0,
            low_code="intake_airflow_low",
            low_message="MAF airflow is consistently below this vehicle's learned baseline; inspect intake airflow path",
            suspected_causes=(
                "dirty air filter",
                "blocked intake snorkel",
                "contaminated or failing MAF sensor",
                "unmetered air or throttle/load signal mismatch",
            ),
        )
    ]


def _read_numeric(state: dict[str, Any], path: str) -> float | None:
    current: Any = state
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return number_or_none(current)


def _round_event(event: dict[str, Any]) -> dict[str, Any]:
    rounded = dict(event)
    for key in ("value", "expected", "normalLow", "normalHigh", "deviation"):
        if isinstance(rounded.get(key), (float, int)):
            rounded[key] = round(float(rounded[key]), 3)
    return rounded
