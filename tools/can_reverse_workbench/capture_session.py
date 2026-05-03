from __future__ import annotations

import json
import sqlite3
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .labels import AnchorPoint
from .obd_anchors import STANDARD_MODE_01_PIDS, _parse_jsonl_item
from .parser import CanFrame, parse_can_log


SCHEMA_VERSION = 1


@dataclass(frozen=True)
class CaptureImportSummary:
    source: str
    rows: int
    warnings: tuple[str, ...] = ()


@dataclass(frozen=True)
class CaptureSessionSummary:
    session_id: str
    raw_can_frames: int
    anchor_samples: int
    supported_pids: int
    warnings: int
    exports: dict[str, str]


def build_capture_session_from_logs(
    *,
    db_path: str | Path,
    can_log: str | Path,
    obd_log: str | Path,
    out_dir: str | Path | None = None,
    session_id: str | None = None,
    vehicle_profile: str | None = None,
    purpose: str | None = None,
    notes: str | None = None,
    thermal_start_class: str | None = None,
    off_time_sec: float | None = None,
    session_labels: list[str] | tuple[str, ...] | None = None,
    decoder_version: str | None = None,
) -> CaptureSessionSummary:
    session = create_capture_session(
        db_path,
        session_id=session_id,
        vehicle_profile=vehicle_profile,
        purpose=purpose,
        notes=notes,
        source="log_import",
        thermal_start_class=thermal_start_class,
        off_time_sec=off_time_sec,
        session_labels=session_labels,
        decoder_version=decoder_version,
    )
    import_can_log(db_path, session, can_log)
    import_obd_anchor_log(db_path, session, obd_log)
    exports = export_capture_session(db_path, session, out_dir) if out_dir is not None else {}
    return summarize_capture_session(db_path, session, exports=exports)


def create_capture_session(
    db_path: str | Path,
    *,
    session_id: str | None = None,
    vehicle_profile: str | None = None,
    purpose: str | None = None,
    notes: str | None = None,
    source: str = "manual",
    thermal_start_class: str | None = None,
    off_time_sec: float | None = None,
    session_labels: list[str] | tuple[str, ...] | None = None,
    decoder_version: str | None = None,
) -> str:
    session = session_id or _new_session_id()
    now = time.time()
    with _connect(db_path) as db:
        _ensure_schema(db)
        try:
            db.execute(
                """
                INSERT INTO sessions (
                    id, schema_version, vehicle_profile, purpose, notes,
                    source, created_at, started_at, ended_at,
                    thermal_start_class, off_time_sec, session_labels,
                    decoder_version
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session,
                    SCHEMA_VERSION,
                    vehicle_profile,
                    purpose,
                    notes,
                    source,
                    _iso_time(now),
                    None,
                    None,
                    _normalize_thermal_start_class(thermal_start_class),
                    off_time_sec,
                    json.dumps(list(session_labels or []), sort_keys=True),
                    decoder_version,
                ),
            )
        except sqlite3.IntegrityError as exc:
            raise ValueError(f"capture session already exists: {session}") from exc
    return session


def import_can_log(db_path: str | Path, session_id: str, can_log: str | Path) -> CaptureImportSummary:
    frames, stats = parse_can_log(can_log)
    with _connect(db_path) as db:
        _ensure_schema(db)
        _assert_session(db, session_id)
        db.executemany(
            """
            INSERT INTO raw_can_frames (
                session_id, timestamp, interface, arbitration_id, can_id_hex,
                extended, dlc, data_hex, source_line
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [_frame_row(session_id, frame) for frame in frames],
        )
        _insert_warnings(db, session_id, "can_log", stats.warnings)
        _update_session_bounds(db, session_id)
    return CaptureImportSummary("can_log", len(frames), tuple(stats.warnings))


def import_obd_anchor_log(db_path: str | Path, session_id: str, obd_log: str | Path) -> CaptureImportSummary:
    rows = 0
    warnings: list[str] = []
    with _connect(db_path) as db:
        _ensure_schema(db)
        _assert_session(db, session_id)
        with Path(obd_log).open("r", encoding="utf-8") as handle:
            for line_number, raw_line in enumerate(handle, start=1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    item = json.loads(line)
                    decoded = _parse_jsonl_item(item)
                except (TypeError, ValueError, json.JSONDecodeError) as exc:
                    warning = f"line {line_number}: {exc}"
                    warnings.append(warning)
                    _insert_warnings(db, session_id, "obd_log", [warning])
                    continue

                raw_payload = json.dumps(item, sort_keys=True)
                for result in decoded:
                    if result.pid >= 0:
                        db.execute(
                            """
                            INSERT OR IGNORE INTO obd_pids_seen (session_id, pid, source_line)
                            VALUES (?, ?, ?)
                            """,
                            (session_id, result.pid, line_number),
                        )
                    for pid in result.supported_pids:
                        db.execute(
                            """
                            INSERT OR IGNORE INTO obd_supported_pids (session_id, pid, source_line)
                            VALUES (?, ?, ?)
                            """,
                            (session_id, pid, line_number),
                        )
                    for signal, value in result.values.items():
                        db.execute(
                            """
                            INSERT INTO anchor_samples (
                                session_id, timestamp, source, signal, value, unit,
                                mode, pid, raw_payload, source_line
                            )
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                session_id,
                                result.timestamp,
                                _anchor_source(result.pid, signal),
                                signal,
                                float(value),
                                _obd_unit(result.pid, signal),
                                result.mode if result.pid >= 0 else None,
                                result.pid if result.pid >= 0 else None,
                                raw_payload,
                                line_number,
                            ),
                        )
                        rows += 1
        _update_session_bounds(db, session_id)
    return CaptureImportSummary("obd_log", rows, tuple(warnings))


def export_capture_session(
    db_path: str | Path,
    session_id: str,
    out_dir: str | Path,
) -> dict[str, str]:
    output_dir = Path(out_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    raw_can_path = output_dir / "raw_can.candump"
    guided_session_path = output_dir / "guided_session.json"
    obd_jsonl_path = output_dir / "obd_anchors.jsonl"
    manifest_path = output_dir / "capture_manifest.json"

    raw_can_path.write_text(_render_candump(db_path, session_id), encoding="utf-8")
    guided_payload = build_guided_session_payload_from_capture(db_path, session_id)
    guided_session_path.write_text(json.dumps(guided_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    obd_jsonl_path.write_text(_render_anchor_jsonl(db_path, session_id), encoding="utf-8")

    summary = summarize_capture_session(
        db_path,
        session_id,
        exports={
            "rawCanLog": str(raw_can_path),
            "guidedSession": str(guided_session_path),
            "obdAnchorJsonl": str(obd_jsonl_path),
        },
    )
    manifest = {
        "version": SCHEMA_VERSION,
        "kind": "obd_raw_can_capture_session_manifest",
        "database": str(Path(db_path)),
        "sessionId": session_id,
        "captureSession": guided_payload.get("captureSession", {}),
        "summary": {
            "rawCanFrames": summary.raw_can_frames,
            "anchorSamples": summary.anchor_samples,
            "supportedPids": summary.supported_pids,
            "warnings": summary.warnings,
        },
        "exports": summary.exports,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {**summary.exports, "manifest": str(manifest_path)}


def build_guided_session_payload_from_capture(db_path: str | Path, session_id: str) -> dict[str, Any]:
    with _connect(db_path) as db:
        db.row_factory = sqlite3.Row
        _ensure_schema(db)
        session = _session_row(db, session_id)
        anchors = _load_anchor_points(db, session_id)
        warnings = [
            str(row["message"])
            for row in db.execute(
                "SELECT message FROM import_warnings WHERE session_id = ? ORDER BY id",
                (session_id,),
            )
        ]
        pids_seen = [
            int(row["pid"])
            for row in db.execute(
                "SELECT pid FROM obd_pids_seen WHERE session_id = ? ORDER BY pid",
                (session_id,),
            )
        ]
        supported_pids = [
            int(row["pid"])
            for row in db.execute(
                "SELECT pid FROM obd_supported_pids WHERE session_id = ? ORDER BY pid",
                (session_id,),
            )
        ]
        raw_can_count = _count(db, "raw_can_frames", session_id)
        anchor_count = _count(db, "anchor_samples", session_id)

    payload: dict[str, Any] = {
        "version": SCHEMA_VERSION,
        "source": {
            "type": "obd_raw_can_capture_session",
            "database": str(Path(db_path)),
            "sessionId": session_id,
        },
        "windows": [],
        "anchors": {
            signal: [{"timestamp": point.timestamp, "value": point.value} for point in points]
            for signal, points in sorted(anchors.items())
        },
        "obd": {
            "mode": 1,
            "decodedSignals": sorted(anchors),
            "pidsSeen": [f"0x{pid:02X}" for pid in pids_seen],
            "supportedPids": [f"0x{pid:02X}" for pid in supported_pids],
            "warnings": warnings,
        },
        "captureSession": {
            "id": session_id,
            "vehicleProfile": session["vehicle_profile"],
            "purpose": session["purpose"],
            "createdAt": session["created_at"],
            "startedAt": session["started_at"],
            "endedAt": session["ended_at"],
            "thermalStartClass": session["thermal_start_class"],
            "offTimeSec": session["off_time_sec"],
            "sessionLabels": _decode_session_labels(session["session_labels"]),
            "decoderVersion": session["decoder_version"],
            "rawCanFrames": raw_can_count,
            "anchorSamples": anchor_count,
        },
    }
    if session["vehicle_profile"]:
        payload["vehicleProfile"] = session["vehicle_profile"]
    return payload


def summarize_capture_session(
    db_path: str | Path,
    session_id: str,
    *,
    exports: dict[str, str] | None = None,
) -> CaptureSessionSummary:
    with _connect(db_path) as db:
        _ensure_schema(db)
        _assert_session(db, session_id)
        return CaptureSessionSummary(
            session_id=session_id,
            raw_can_frames=_count(db, "raw_can_frames", session_id),
            anchor_samples=_count(db, "anchor_samples", session_id),
            supported_pids=_count(db, "obd_supported_pids", session_id),
            warnings=_count(db, "import_warnings", session_id),
            exports=exports or {},
        )


def _ensure_schema(db: sqlite3.Connection) -> None:
    db.executescript(
        """
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            schema_version INTEGER NOT NULL,
            vehicle_profile TEXT,
            purpose TEXT,
            notes TEXT,
            source TEXT NOT NULL,
            created_at TEXT NOT NULL,
            started_at REAL,
            ended_at REAL,
            thermal_start_class TEXT,
            off_time_sec REAL,
            session_labels TEXT,
            decoder_version TEXT
        );

        CREATE TABLE IF NOT EXISTS raw_can_frames (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            timestamp REAL NOT NULL,
            interface TEXT NOT NULL,
            arbitration_id INTEGER NOT NULL,
            can_id_hex TEXT NOT NULL,
            extended INTEGER NOT NULL,
            dlc INTEGER NOT NULL,
            data_hex TEXT NOT NULL,
            source_line INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_raw_can_session_time
            ON raw_can_frames(session_id, timestamp);
        CREATE INDEX IF NOT EXISTS idx_raw_can_session_id
            ON raw_can_frames(session_id, arbitration_id);

        CREATE TABLE IF NOT EXISTS anchor_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            timestamp REAL NOT NULL,
            source TEXT NOT NULL,
            signal TEXT NOT NULL,
            value REAL NOT NULL,
            unit TEXT,
            mode INTEGER,
            pid INTEGER,
            raw_payload TEXT,
            source_line INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_anchor_session_time
            ON anchor_samples(session_id, timestamp);
        CREATE INDEX IF NOT EXISTS idx_anchor_session_signal
            ON anchor_samples(session_id, signal, timestamp);

        CREATE TABLE IF NOT EXISTS obd_pids_seen (
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            pid INTEGER NOT NULL,
            source_line INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (session_id, pid)
        );

        CREATE TABLE IF NOT EXISTS obd_supported_pids (
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            pid INTEGER NOT NULL,
            source_line INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (session_id, pid)
        );

        CREATE TABLE IF NOT EXISTS import_warnings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            source TEXT NOT NULL,
            source_line INTEGER,
            message TEXT NOT NULL
        );
        """
    )
    _ensure_session_columns(db)
    db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")


def _ensure_session_columns(db: sqlite3.Connection) -> None:
    columns = {str(row[1]) for row in db.execute("PRAGMA table_info(sessions)")}
    migrations = {
        "thermal_start_class": "ALTER TABLE sessions ADD COLUMN thermal_start_class TEXT",
        "off_time_sec": "ALTER TABLE sessions ADD COLUMN off_time_sec REAL",
        "session_labels": "ALTER TABLE sessions ADD COLUMN session_labels TEXT",
        "decoder_version": "ALTER TABLE sessions ADD COLUMN decoder_version TEXT",
    }
    for column, statement in migrations.items():
        if column not in columns:
            db.execute(statement)


def _connect(db_path: str | Path) -> sqlite3.Connection:
    path = Path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    return sqlite3.connect(path)


def _frame_row(session_id: str, frame: CanFrame) -> tuple[Any, ...]:
    return (
        session_id,
        frame.timestamp,
        frame.interface,
        frame.arbitration_id,
        frame.id_hex,
        1 if frame.extended else 0,
        len(frame.data),
        frame.data_hex,
        frame.source_line,
    )


def _insert_warnings(db: sqlite3.Connection, session_id: str, source: str, warnings: list[str] | tuple[str, ...]) -> None:
    for warning in warnings:
        source_line = None
        message = warning
        if warning.startswith("line "):
            prefix, _, rest = warning.partition(":")
            try:
                source_line = int(prefix.split()[1])
                message = rest.strip() or warning
            except (IndexError, ValueError):
                pass
        db.execute(
            "INSERT INTO import_warnings (session_id, source, source_line, message) VALUES (?, ?, ?, ?)",
            (session_id, source, source_line, message),
        )


def _update_session_bounds(db: sqlite3.Connection, session_id: str) -> None:
    row = db.execute(
        """
        SELECT MIN(timestamp), MAX(timestamp)
        FROM (
            SELECT timestamp FROM raw_can_frames WHERE session_id = ?
            UNION ALL
            SELECT timestamp FROM anchor_samples WHERE session_id = ?
        )
        """,
        (session_id, session_id),
    ).fetchone()
    if row is None:
        return
    db.execute(
        "UPDATE sessions SET started_at = ?, ended_at = ? WHERE id = ?",
        (row[0], row[1], session_id),
    )


def _assert_session(db: sqlite3.Connection, session_id: str) -> None:
    if db.execute("SELECT 1 FROM sessions WHERE id = ?", (session_id,)).fetchone() is None:
        raise ValueError(f"capture session does not exist: {session_id}")


def _session_row(db: sqlite3.Connection, session_id: str) -> sqlite3.Row:
    row = db.execute("SELECT * FROM sessions WHERE id = ?", (session_id,)).fetchone()
    if row is None:
        raise ValueError(f"capture session does not exist: {session_id}")
    return row


def _count(db: sqlite3.Connection, table: str, session_id: str) -> int:
    return int(db.execute(f"SELECT COUNT(*) FROM {table} WHERE session_id = ?", (session_id,)).fetchone()[0])


def _load_anchor_points(db: sqlite3.Connection, session_id: str) -> dict[str, list[AnchorPoint]]:
    anchors: dict[str, list[AnchorPoint]] = {}
    rows = db.execute(
        """
        SELECT signal, timestamp, value
        FROM anchor_samples
        WHERE session_id = ?
        ORDER BY signal, timestamp, id
        """,
        (session_id,),
    )
    for row in rows:
        signal = str(row["signal"])
        anchors.setdefault(signal, []).append(
            AnchorPoint(signal=signal, timestamp=float(row["timestamp"]), value=float(row["value"]))
        )
    return anchors


def _render_candump(db_path: str | Path, session_id: str) -> str:
    with _connect(db_path) as db:
        db.row_factory = sqlite3.Row
        _ensure_schema(db)
        rows = db.execute(
            """
            SELECT timestamp, interface, arbitration_id, data_hex
            FROM raw_can_frames
            WHERE session_id = ?
            ORDER BY timestamp, id
            """,
            (session_id,),
        )
        lines = []
        for row in rows:
            can_id = _candump_id(int(row["arbitration_id"]))
            lines.append(f"({float(row['timestamp']):.6f}) {row['interface']} {can_id}#{row['data_hex']}")
        return "\n".join(lines) + ("\n" if lines else "")


def _render_anchor_jsonl(db_path: str | Path, session_id: str) -> str:
    with _connect(db_path) as db:
        db.row_factory = sqlite3.Row
        _ensure_schema(db)
        rows = db.execute(
            """
            SELECT timestamp, signal, value
            FROM anchor_samples
            WHERE session_id = ?
            ORDER BY timestamp, id
            """,
            (session_id,),
        )
        lines = [
            json.dumps({"timestamp": float(row["timestamp"]), "signal": row["signal"], "value": float(row["value"])}, sort_keys=True)
            for row in rows
        ]
        return "\n".join(lines) + ("\n" if lines else "")


def _candump_id(arbitration_id: int) -> str:
    width = 3 if arbitration_id <= 0x7FF else 8
    return f"{arbitration_id:0{width}X}"


def _anchor_source(pid: int, signal: str) -> str:
    if signal.lower().startswith("gps"):
        return "gps"
    return "obd_mode_01" if pid >= 0 else "manual_anchor"


def _obd_unit(pid: int, signal: str) -> str | None:
    definition = STANDARD_MODE_01_PIDS.get(pid)
    if definition is not None and definition.signal == signal:
        return definition.unit
    if signal.lower().startswith("gps") and "speed" in signal.lower():
        return "kph"
    return None


def _new_session_id() -> str:
    timestamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"capture-{timestamp}-{uuid.uuid4().hex[:8]}"


def _iso_time(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def _normalize_thermal_start_class(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if not normalized:
        return None
    if normalized not in {"cold", "warm", "hot"}:
        raise ValueError("thermal_start_class must be one of cold, warm, hot")
    return normalized


def _decode_session_labels(value: Any) -> list[str]:
    if not value:
        return []
    try:
        labels = json.loads(str(value))
    except json.JSONDecodeError:
        return []
    if not isinstance(labels, list):
        return []
    return [str(label) for label in labels if str(label).strip()]
