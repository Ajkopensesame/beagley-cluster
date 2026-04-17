from __future__ import annotations

import json
import os
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class FaultRecorder:
    def __init__(
        self,
        output_dir: str | Path = "/var/log/beagley-cluster/faults",
        *,
        enabled: bool = True,
        buffer_seconds: float = 20.0,
        max_buffer_frames: int = 300,
        min_interval_seconds: float = 10.0,
    ) -> None:
        self.output_dir = Path(output_dir)
        self.enabled = enabled
        self.buffer_seconds = buffer_seconds
        self.max_buffer_frames = max_buffer_frames
        self.min_interval_seconds = min_interval_seconds
        self._buffer: deque[dict[str, Any]] = deque(maxlen=max_buffer_frames)
        self._last_write_by_fingerprint: dict[str, float] = {}
        self._event_counter = 0
        self._last_error: str | None = None
        self._last_event_path: str | None = None
        self._writes = 0

    def observe(
        self,
        state: dict[str, Any],
        *,
        evidence: dict[str, Any] | None = None,
        wall_time: float | None = None,
        monotonic_time: float | None = None,
    ) -> dict[str, Any]:
        now_wall = time.time() if wall_time is None else wall_time
        now_monotonic = time.monotonic() if monotonic_time is None else monotonic_time
        self._append_snapshot(state, now_wall, now_monotonic)
        if not self.enabled:
            return self.health(enabled=False)

        faults = _extract_faults(state)
        if not faults:
            return self.health()

        fingerprint = _fault_fingerprint(faults)
        last_write = self._last_write_by_fingerprint.get(fingerprint)
        if last_write is not None and now_monotonic - last_write < self.min_interval_seconds:
            return self.health(suppressed=True, suppressedFingerprint=fingerprint)

        event = self._build_event(
            state=state,
            faults=faults,
            fingerprint=fingerprint,
            evidence=evidence or {},
            now_wall=now_wall,
            now_monotonic=now_monotonic,
        )
        try:
            path = self._write_event(event)
            self._last_write_by_fingerprint[fingerprint] = now_monotonic
            self._last_event_path = str(path)
            self._writes += 1
            self._last_error = None
            return self.health(lastEventPath=str(path), lastFingerprint=fingerprint)
        except OSError as exc:
            self._last_error = str(exc)
            return self.health(error=str(exc), lastFingerprint=fingerprint)

    def health(self, **extra: Any) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "outputDir": str(self.output_dir),
            "bufferSeconds": self.buffer_seconds,
            "bufferFrames": len(self._buffer),
            "writes": self._writes,
            "lastEventPath": self._last_event_path,
            "lastError": self._last_error,
            **extra,
        }

    def _append_snapshot(self, state: dict[str, Any], now_wall: float, now_monotonic: float) -> None:
        self._buffer.append(
            {
                "wallTime": _iso_time(now_wall),
                "wallTimestamp": now_wall,
                "monotonicTimestamp": now_monotonic,
                "state": _safe_json(state),
            }
        )
        cutoff = now_monotonic - self.buffer_seconds
        while self._buffer and self._buffer[0]["monotonicTimestamp"] < cutoff:
            self._buffer.popleft()

    def _build_event(
        self,
        *,
        state: dict[str, Any],
        faults: list[dict[str, Any]],
        fingerprint: str,
        evidence: dict[str, Any],
        now_wall: float,
        now_monotonic: float,
    ) -> dict[str, Any]:
        self._event_counter += 1
        return {
            "version": 1,
            "eventId": f"{int(now_wall * 1000)}-{self._event_counter:04d}",
            "generatedAt": _iso_time(now_wall),
            "faultFingerprint": fingerprint,
            "faults": _safe_json(faults),
            "sourceHealth": _safe_json(state.get("_health", {})),
            "triggerState": _safe_json(state),
            "rollingBuffer": {
                "seconds": self.buffer_seconds,
                "frames": [item for item in self._buffer],
            },
            "evidence": _safe_json(evidence),
            "recorder": {
                "outputDir": str(self.output_dir),
                "minIntervalSeconds": self.min_interval_seconds,
                "wallTimestamp": now_wall,
                "monotonicTimestamp": now_monotonic,
            },
        }

    def _write_event(self, event: dict[str, Any]) -> Path:
        self.output_dir.mkdir(parents=True, exist_ok=True)
        event_id = str(event["eventId"]).replace("/", "_")
        fault_part = event["faultFingerprint"].replace(":", "-").replace("/", "_").replace("|", "_")
        path = self.output_dir / f"{event_id}_{fault_part}.json"
        tmp_path = path.with_suffix(".json.tmp")
        tmp_path.write_text(json.dumps(event, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(tmp_path, path)
        return path


def _extract_faults(state: dict[str, Any]) -> list[dict[str, Any]]:
    health = state.get("_health", {})
    if not isinstance(health, dict):
        return []
    faults = health.get("signalFaults", [])
    if not isinstance(faults, list):
        return []
    return [fault for fault in faults if isinstance(fault, dict)]


def _fault_fingerprint(faults: list[dict[str, Any]]) -> str:
    keys = []
    for fault in faults:
        signal = str(fault.get("signal", "unknown"))
        code = str(fault.get("code", "unknown"))
        severity = str(fault.get("severity", "unknown"))
        keys.append(f"{signal}:{code}:{severity}")
    return "|".join(sorted(keys)) or "unknown"


def _safe_json(value: Any) -> Any:
    return json.loads(json.dumps(value, default=str, sort_keys=True))


def _iso_time(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()
