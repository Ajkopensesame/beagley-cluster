from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class LabelWindow:
    label: str
    start: float
    end: float
    target: str | None = None
    trend: str | None = None
    weight: float = 1.0

    def contains(self, timestamp: float) -> bool:
        return self.start <= timestamp <= self.end


@dataclass(frozen=True)
class AnchorPoint:
    signal: str
    timestamp: float
    value: float


@dataclass
class GuidedSession:
    windows: list[LabelWindow] = field(default_factory=list)
    anchors: dict[str, list[AnchorPoint]] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def empty(cls) -> "GuidedSession":
        return cls()


def load_guided_session(path: str | Path | None) -> GuidedSession:
    if path is None:
        return GuidedSession.empty()
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    windows = [_parse_window(item) for item in payload.get("windows", [])]
    anchors = _parse_anchors(payload.get("anchors", {}))
    metadata = {key: value for key, value in payload.items() if key not in {"windows", "anchors"}}
    return GuidedSession(windows=windows, anchors=anchors, metadata=metadata)


def _parse_window(item: dict[str, Any]) -> LabelWindow:
    label = str(item.get("label") or item.get("name") or "")
    if not label:
        raise ValueError("guided-session window is missing label/name")
    start = float(item["start"])
    end = float(item["end"])
    if end < start:
        raise ValueError(f"window {label!r} has end before start")
    return LabelWindow(
        label=label,
        start=start,
        end=end,
        target=item.get("target") or item.get("signal"),
        trend=item.get("trend"),
        weight=float(item.get("weight", 1.0)),
    )


def _parse_anchors(raw: Any) -> dict[str, list[AnchorPoint]]:
    anchors: dict[str, list[AnchorPoint]] = {}
    if isinstance(raw, list):
        for item in raw:
            point = _parse_anchor_item(item, item.get("signal"))
            anchors.setdefault(point.signal, []).append(point)
    elif isinstance(raw, dict):
        for signal, items in raw.items():
            for item in items:
                point = _parse_anchor_item(item, signal)
                anchors.setdefault(point.signal, []).append(point)
    else:
        raise ValueError("anchors must be a dict or list")
    for signal in anchors:
        anchors[signal].sort(key=lambda point: point.timestamp)
    return anchors


def _parse_anchor_item(item: dict[str, Any], signal: str | None) -> AnchorPoint:
    if not signal:
        raise ValueError("anchor is missing signal")
    return AnchorPoint(signal=str(signal), timestamp=float(item["timestamp"]), value=float(item["value"]))
