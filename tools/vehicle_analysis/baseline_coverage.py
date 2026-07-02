from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable

from .stats import clamp
from .values import number_or_none


COVERAGE_STATUSES = ("strong", "weak", "missing")


@dataclass(frozen=True)
class CoverageScenario:
    key: str
    label: str
    category: str
    contexts: tuple[str, ...] = ()
    any_contexts: tuple[str, ...] = ()
    steady_models: tuple[str, ...] = ()
    transition_models: tuple[str, ...] = ()
    events: tuple[str, ...] = ()
    next_step: str = ""


DEFAULT_SCENARIOS = (
    CoverageScenario(
        key="startup_response",
        label="Startup response",
        category="transition",
        contexts=("startup",),
        transition_models=("startup_maf_response",),
        events=("first_fire",),
        next_step="Capture several clean starts from key-on through idle settle.",
    ),
    CoverageScenario(
        key="cold_start",
        label="Cold start",
        category="thermal_start",
        contexts=("cold_start",),
        transition_models=("startup_maf_response",),
        events=("first_fire",),
        next_step="Capture a clean start after the vehicle has fully cooled down.",
    ),
    CoverageScenario(
        key="hot_restart",
        label="Hot restart",
        category="thermal_start",
        contexts=("hot_start",),
        transition_models=("startup_maf_response",),
        events=("first_fire",),
        next_step="Capture a clean restart shortly after shutdown with warm coolant.",
    ),
    CoverageScenario(
        key="warm_idle",
        label="Warm idle",
        category="steady_state",
        contexts=("idle_stationary",),
        next_step="Let the vehicle idle warm for a few minutes with stable inputs.",
    ),
    CoverageScenario(
        key="intake_airflow",
        label="Intake airflow baseline",
        category="steady_state",
        steady_models=("intake_airflow",),
        next_step="Drive warm with varied RPM and throttle so MAF can learn comparable buckets.",
    ),
    CoverageScenario(
        key="map_pressure",
        label="MAP pressure baseline",
        category="steady_state",
        steady_models=("map_pressure",),
        next_step="Drive warm with varied RPM and throttle so MAP can learn comparable buckets.",
    ),
    CoverageScenario(
        key="road_cruise",
        label="Road cruise",
        category="drive_context",
        any_contexts=("road_speed_drive", "highway_speed_drive"),
        steady_models=("intake_airflow", "map_pressure"),
        next_step="Capture steady road or highway driving after the engine is warm.",
    ),
    CoverageScenario(
        key="heavy_load",
        label="Heavy load",
        category="drive_context",
        contexts=("heavy_load",),
        steady_models=("intake_airflow", "map_pressure"),
        next_step="Capture one safe, legal heavy-load acceleration or hill pull.",
    ),
    CoverageScenario(
        key="throttle_tip_in",
        label="Throttle tip-in response",
        category="transition",
        transition_models=("throttle_tip_in_maf_response",),
        events=("throttle_tip_in",),
        next_step="Capture several clean light-to-moderate throttle inputs.",
    ),
    CoverageScenario(
        key="shift_response",
        label="Shift response",
        category="transition",
        transition_models=("shift_rpm_response",),
        events=("shift",),
        next_step="Capture normal drive shifts under light and moderate load.",
    ),
    CoverageScenario(
        key="decel_behavior",
        label="Decel behavior",
        category="transition",
        events=("decel",),
        next_step="Capture normal lift-off and braking deceleration events.",
    ),
)


def build_baseline_coverage_report(
    *,
    coverage: dict[str, Any] | None = None,
    vehicle_baseline_snapshot: dict[str, Any] | None = None,
    transition_snapshot: dict[str, Any] | None = None,
    scenarios: Iterable[CoverageScenario] = DEFAULT_SCENARIOS,
) -> dict[str, Any]:
    observed_contexts = _observed_contexts(coverage)
    steady_models = _steady_models(vehicle_baseline_snapshot)
    transition_models = _transition_models(transition_snapshot)
    events_seen = _events_seen(transition_snapshot)
    scenario_reports = [
        _scenario_report(
            scenario,
            observed_contexts=observed_contexts,
            steady_models=steady_models,
            transition_models=transition_models,
            events_seen=events_seen,
        )
        for scenario in scenarios
    ]
    counts = {status: sum(1 for item in scenario_reports if item["status"] == status) for status in COVERAGE_STATUSES}
    total = max(len(scenario_reports), 1)
    score = clamp(sum(float(item["score"]) for item in scenario_reports) / total)
    next_steps = _next_steps(scenario_reports)
    return {
        "version": 1,
        "kind": "baseline_coverage_report",
        "summary": {
            "score": round(score, 3),
            "statusCounts": counts,
            "strongScenarios": counts["strong"],
            "weakScenarios": counts["weak"],
            "missingScenarios": counts["missing"],
            "ready": counts["missing"] == 0 and counts["weak"] <= max(1, total // 4),
            "nextSteps": next_steps,
        },
        "scenarios": scenario_reports,
        "operatingContexts": {
            "observed": sorted(observed_contexts),
            "missing": _missing_contexts(coverage),
        },
        "steadyState": {
            "models": sorted(steady_models.values(), key=lambda item: item["name"]),
            "readyModels": sorted(name for name, model in steady_models.items() if model["ready"]),
        },
        "transitions": {
            "eventsSeen": dict(sorted(events_seen.items())),
            "models": sorted(transition_models.values(), key=lambda item: item["name"]),
            "readyModels": sorted(name for name, model in transition_models.items() if model["ready"]),
        },
    }


def _scenario_report(
    scenario: CoverageScenario,
    *,
    observed_contexts: set[str],
    steady_models: dict[str, dict[str, Any]],
    transition_models: dict[str, dict[str, Any]],
    events_seen: dict[str, int],
) -> dict[str, Any]:
    context_score, missing_contexts = _context_score(scenario, observed_contexts)
    steady_score, missing_steady = _model_score(scenario.steady_models, steady_models, count_key="totalSamples")
    transition_score, missing_transition = _model_score(scenario.transition_models, transition_models, count_key="windows")
    event_score, missing_events = _event_score(scenario.events, events_seen)
    components = _active_components(
        context_score=context_score if scenario.contexts or scenario.any_contexts else None,
        steady_score=steady_score if scenario.steady_models else None,
        transition_score=transition_score if scenario.transition_models else None,
        event_score=event_score if scenario.events else None,
    )
    score = clamp(sum(components) / max(len(components), 1))
    if score >= 0.80 and not (missing_steady or missing_transition):
        status = "strong"
    elif score > 0.0:
        status = "weak"
    else:
        status = "missing"
    missing = {
        "contexts": missing_contexts,
        "steadyModels": missing_steady,
        "transitionModels": missing_transition,
        "events": missing_events,
    }
    return {
        "key": scenario.key,
        "label": scenario.label,
        "category": scenario.category,
        "status": status,
        "score": round(score, 3),
        "evidence": {
            "contexts": sorted(set(scenario.contexts + scenario.any_contexts) & observed_contexts),
            "steadyModels": _selected_models(scenario.steady_models, steady_models, "totalSamples"),
            "transitionModels": _selected_models(scenario.transition_models, transition_models, "windows"),
            "eventsSeen": {event: events_seen.get(event, 0) for event in scenario.events},
        },
        "missing": {key: value for key, value in missing.items() if value},
        "nextStep": scenario.next_step if status != "strong" else None,
    }


def _next_steps(scenario_reports: list[dict[str, Any]], *, limit: int = 5) -> list[dict[str, Any]]:
    candidates = [
        scenario
        for scenario in scenario_reports
        if scenario.get("status") != "strong" and scenario.get("nextStep")
    ]
    candidates.sort(
        key=lambda scenario: (
            _status_priority(str(scenario.get("status", "missing"))),
            float(scenario.get("score", 0.0)),
            str(scenario.get("key", "")),
        )
    )
    return [
        {
            "scenario": str(scenario.get("key", "")),
            "label": str(scenario.get("label", "")),
            "status": str(scenario.get("status", "")),
            "score": float(scenario.get("score", 0.0)),
            "nextStep": str(scenario.get("nextStep", "")),
            "missing": dict(scenario.get("missing", {})) if isinstance(scenario.get("missing"), dict) else {},
        }
        for scenario in candidates[: max(0, limit)]
    ]


def _status_priority(status: str) -> int:
    if status == "missing":
        return 0
    if status == "weak":
        return 1
    return 2


def _observed_contexts(coverage: dict[str, Any] | None) -> set[str]:
    if not isinstance(coverage, dict):
        return set()
    return {str(item) for item in coverage.get("observedContexts", []) if str(item).strip()}


def _missing_contexts(coverage: dict[str, Any] | None) -> list[str]:
    if not isinstance(coverage, dict):
        return []
    return [str(item) for item in coverage.get("missingContexts", []) if str(item).strip()]


def _steady_models(snapshot: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    models: dict[str, dict[str, Any]] = {}
    for model in _models(snapshot):
        name = str(model.get("name") or model.get("model") or "")
        if not name:
            continue
        models[name] = {
            "name": name,
            "ready": bool(model.get("ready")),
            "totalSamples": int(number_or_none(model.get("totalSamples")) or 0),
            "samples": int(number_or_none(model.get("totalSamples")) or 0),
            "bucketCount": int(number_or_none(model.get("bucketCount")) or 0),
            "status": str(model.get("status") or "unknown"),
        }
    return models


def _transition_models(snapshot: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    models: dict[str, dict[str, Any]] = {}
    for model in _models(snapshot):
        name = str(model.get("name") or model.get("model") or "")
        if not name:
            continue
        models[name] = {
            "name": name,
            "ready": bool(model.get("ready")),
            "windows": int(number_or_none(model.get("windows")) or 0),
            "eventType": str(model.get("eventType") or ""),
            "target": str(model.get("target") or ""),
        }
    return models


def _events_seen(snapshot: dict[str, Any] | None) -> dict[str, int]:
    if not isinstance(snapshot, dict):
        return {}
    coverage = snapshot.get("coverage") if isinstance(snapshot.get("coverage"), dict) else {}
    raw_events = coverage.get("eventsSeen") if isinstance(coverage.get("eventsSeen"), dict) else {}
    events = {str(key): int(number_or_none(value) or 0) for key, value in raw_events.items()}
    for model in _models(snapshot):
        event_counts = model.get("eventCounts") if isinstance(model.get("eventCounts"), dict) else {}
        for event, count in event_counts.items():
            events[str(event)] = max(events.get(str(event), 0), int(number_or_none(count) or 0))
    return events


def _models(snapshot: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not isinstance(snapshot, dict):
        return []
    models = snapshot.get("models", [])
    return [model for model in models if isinstance(model, dict)] if isinstance(models, list) else []


def _context_score(scenario: CoverageScenario, observed_contexts: set[str]) -> tuple[float, list[str]]:
    required = set(scenario.contexts)
    any_of = set(scenario.any_contexts)
    missing = sorted(required - observed_contexts)
    if any_of and not (any_of & observed_contexts):
        missing.extend(sorted(any_of))
    if not required and not any_of:
        return 1.0, []
    if missing:
        observed = len(required & observed_contexts) + (1 if any_of & observed_contexts else 0)
        needed = len(required) + (1 if any_of else 0)
        return clamp(observed / max(needed, 1)), missing
    return 1.0, []


def _model_score(
    model_names: tuple[str, ...],
    models: dict[str, dict[str, Any]],
    *,
    count_key: str,
) -> tuple[float, list[str]]:
    if not model_names:
        return 1.0, []
    scores: list[float] = []
    missing: list[str] = []
    for name in model_names:
        model = models.get(name)
        if model is None:
            scores.append(0.0)
            missing.append(name)
            continue
        if model.get("ready"):
            scores.append(1.0)
        elif int(model.get(count_key, 0)) > 0:
            scores.append(0.45)
            missing.append(name)
        else:
            scores.append(0.0)
            missing.append(name)
    return clamp(sum(scores) / len(scores)), missing


def _event_score(events: tuple[str, ...], events_seen: dict[str, int]) -> tuple[float, list[str]]:
    if not events:
        return 1.0, []
    scores: list[float] = []
    missing: list[str] = []
    for event in events:
        count = events_seen.get(event, 0)
        if count >= 5:
            scores.append(1.0)
        elif count > 0:
            scores.append(0.45)
            missing.append(event)
        else:
            scores.append(0.0)
            missing.append(event)
    return clamp(sum(scores) / len(scores)), missing


def _active_components(**components: float | None) -> list[float]:
    active = [float(value) for value in components.values() if value is not None]
    return active or [0.0]


def _selected_models(
    names: tuple[str, ...],
    models: dict[str, dict[str, Any]],
    count_key: str,
) -> list[dict[str, Any]]:
    selected = []
    for name in names:
        model = models.get(name)
        if model is None:
            selected.append({"name": name, "ready": False, count_key: 0})
        else:
            selected.append(dict(model))
    return selected
