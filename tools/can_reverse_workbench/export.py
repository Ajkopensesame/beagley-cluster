from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_MIN_CONFIDENCE = 0.70
REQUIRED_SIGNAL_FIELDS = {
    "canId",
    "startBit",
    "length",
    "endian",
    "signed",
    "scale",
    "offset",
    "unit",
    "confidence",
    "evidence",
}


def build_signal_dictionary(
    analysis: dict[str, Any],
    *,
    source_log: str | None = None,
    source_labels: str | None = None,
    min_confidence: float = DEFAULT_MIN_CONFIDENCE,
) -> dict[str, Any]:
    signals: dict[str, Any] = {}
    rejected: dict[str, Any] = {}
    for signal, candidate in analysis.get("topSignals", {}).items():
        if candidate.get("confidence", 0.0) < min_confidence:
            rejected[signal] = _rejected_signal(candidate, f"confidence below export threshold {min_confidence:.2f}")
            continue
        if not candidate.get("verified", False):
            rejected[signal] = _rejected_signal(candidate, candidate.get("pipeline", {}).get("decision", {}).get("reason", "not verified"))
            continue
        signals[signal] = {
            "canId": candidate["canId"],
            "startBit": candidate["startBit"],
            "length": candidate["length"],
            "endian": candidate["endian"],
            "signed": candidate["signed"],
            "scale": candidate["scale"],
            "offset": candidate["offset"],
            "unit": candidate["unit"],
            "confidence": candidate["confidence"],
            "verified": True,
            "pipeline": candidate["pipeline"],
            "evidence": candidate["evidence"],
        }
    return {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": {
            "log": source_log,
            "labels": source_labels,
            "analysisGeneratedAt": analysis.get("generatedAt"),
        },
        "exportPolicy": {
            "minConfidence": min_confidence,
            "requiresVerified": True,
            "unknownPolicy": "unverified candidates are not attached to human signal names",
        },
        "signals": signals,
        "rejectedSignals": rejected,
    }


def validate_signal_dictionary(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if payload.get("version") != 1:
        errors.append("version must be 1")
    signals = payload.get("signals")
    if not isinstance(signals, dict) or not signals:
        errors.append("signals must be a non-empty object")
        return errors
    for signal_name, signal in signals.items():
        if not isinstance(signal, dict):
            errors.append(f"{signal_name}: signal entry must be an object")
            continue
        missing = REQUIRED_SIGNAL_FIELDS - set(signal)
        if missing:
            errors.append(f"{signal_name}: missing fields {sorted(missing)}")
        if not isinstance(signal.get("length"), int) or not 1 <= signal.get("length", 0) <= 32:
            errors.append(f"{signal_name}: length must be an integer in [1, 32]")
        if signal.get("endian") not in {"big", "little"}:
            errors.append(f"{signal_name}: endian must be big or little")
        if not isinstance(signal.get("signed"), bool):
            errors.append(f"{signal_name}: signed must be boolean")
        if not isinstance(signal.get("startBit"), int) or signal.get("startBit", 0) < 0:
            errors.append(f"{signal_name}: startBit must be a non-negative integer")
        confidence = signal.get("confidence")
        if not isinstance(confidence, (float, int)) or not 0.0 <= float(confidence) <= 1.0:
            errors.append(f"{signal_name}: confidence must be in [0, 1]")
    return errors


def write_json(path: str | Path, payload: dict[str, Any]) -> None:
    Path(path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _rejected_signal(candidate: dict[str, Any], reason: str) -> dict[str, Any]:
    return {
        "candidateId": candidate.get("candidateId"),
        "canId": candidate.get("canId"),
        "confidence": candidate.get("confidence", 0.0),
        "verified": candidate.get("verified", False),
        "reason": reason,
        "pipeline": candidate.get("pipeline", {}),
    }
