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
        max_event_files: int = 500,
        max_total_bytes: int = 64 * 1024 * 1024,
    ) -> None:
        self.output_dir = Path(output_dir)
        self.enabled = enabled
        self.buffer_seconds = buffer_seconds
        self.max_buffer_frames = max_buffer_frames
        self.min_interval_seconds = min_interval_seconds
        self.max_event_files = max_event_files
        self.max_total_bytes = max_total_bytes
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
            "maxEventFiles": self.max_event_files,
            "maxTotalBytes": self.max_total_bytes,
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
            "kind": "bbb_fault_event",
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
        self._prune_events()
        event_id = str(event["eventId"]).replace("/", "_")
        fault_part = event["faultFingerprint"].replace(":", "-").replace("/", "_").replace("|", "_")
        path = self.output_dir / f"{event_id}_{fault_part}.json"
        tmp_path = path.with_suffix(".json.tmp")
        tmp_path.write_text(json.dumps(event, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(tmp_path, path)
        self._prune_events(keep_path=path)
        return path

    def _prune_events(self, *, keep_path: Path | None = None) -> None:
        max_event_files = int(self.max_event_files or 0)
        max_total_bytes = int(self.max_total_bytes or 0)
        if max_event_files <= 0 and max_total_bytes <= 0:
            return

        keep_path = keep_path.resolve() if keep_path is not None else None
        keep_size = 0
        keep_count = 0
        files: list[tuple[float, int, Path]] = []
        for pattern in ("*.json", "*.json.tmp"):
            for path in self.output_dir.glob(pattern):
                try:
                    resolved = path.resolve()
                    stat = path.stat()
                except OSError:
                    continue
                if keep_path is not None and resolved == keep_path:
                    keep_size = stat.st_size
                    keep_count = 1
                    continue
                files.append((stat.st_mtime, stat.st_size, path))

        files.sort(key=lambda item: item[0])
        total_bytes = keep_size + sum(size for _, size, _ in files)

        def remove_oldest() -> bool:
            nonlocal total_bytes
            if not files:
                return False
            _, size, path = files.pop(0)
            try:
                path.unlink()
                total_bytes -= size
            except OSError:
                return False
            return True

        if max_event_files > 0:
            while files and len(files) + keep_count > max_event_files:
                if not remove_oldest():
                    break

        if max_total_bytes > 0:
            while files and total_bytes > max_total_bytes:
                if not remove_oldest():
                    break


def _extract_faults(state: dict[str, Any]) -> list[dict[str, Any]]:
    """Collect persistable faults from deterministic health surfaces.

    Policy:
    - signalFaults: all dict entries are eligible (existing semantics).
    - vehicleBaseline.findings / transitionMonitor.findings: only when the
      parent monitor is enabled and severity is warning or error.
    - dedupe by (signal, code, severity) across all sources.
    """
    health = state.get("_health", {})
    if not isinstance(health, dict):
        return []
    faults: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()

    signal_faults = health.get("signalFaults", [])
    if isinstance(signal_faults, list):
        for fault in signal_faults:
            if isinstance(fault, dict):
                _append_fault(faults, seen, fault, require_actionable_severity=False)

    baseline = health.get("vehicleBaseline")
    if isinstance(baseline, dict) and baseline.get("enabled"):
        for finding in baseline.get("findings", []):
            if isinstance(finding, dict):
                _append_fault(
                    faults,
                    seen,
                    _health_finding_to_fault(finding, default_signal="vehicleBaseline"),
                )

    transition_monitor = health.get("transitionMonitor")
    if isinstance(transition_monitor, dict) and transition_monitor.get("enabled"):
        for finding in transition_monitor.get("findings", []):
            if isinstance(finding, dict):
                _append_fault(
                    faults,
                    seen,
                    _health_finding_to_fault(finding, default_signal="transitionMonitor"),
                )

    return faults


def _append_fault(
    faults: list[dict[str, Any]],
    seen: set[tuple[str, str, str]],
    fault: dict[str, Any],
    *,
    require_actionable_severity: bool = True,
) -> None:
    signal = str(fault.get("signal") or "unknown")
    code = str(fault.get("code") or "unknown")
    severity = str(fault.get("severity") or "unknown")
    if require_actionable_severity and severity not in {"warning", "error"}:
        return
    key = (signal, code, severity)
    if key in seen:
        return
    seen.add(key)
    faults.append(fault)


def _health_finding_to_fault(finding: dict[str, Any], *, default_signal: str) -> dict[str, Any]:
    details = finding.get("details") if isinstance(finding.get("details"), dict) else {}
    signal = str(
        finding.get("signal")
        or finding.get("subject")
        or finding.get("model")
        or default_signal
    )
    fault: dict[str, Any] = {
        "signal": signal,
        "code": str(finding.get("code") or "diagnostic_finding"),
        "severity": str(finding.get("severity") or "warning"),
        "message": str(finding.get("message") or "Diagnostic finding"),
    }
    merged_details = dict(details)
    for key in ("source", "model", "confidence"):
        if finding.get(key) is not None and key not in merged_details:
            merged_details[key] = finding.get(key)
    if merged_details:
        fault["details"] = merged_details
    return fault


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
