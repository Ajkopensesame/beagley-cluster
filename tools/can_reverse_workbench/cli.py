from __future__ import annotations

import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from .baseline import (
    DEFAULT_RETENTION_DAYS,
    build_consent_record,
    build_health_baseline,
    diagnose_against_baseline,
    load_consent_record,
    load_decoded_jsonl,
    render_customer_report,
)
from .bbb_decoder import CanSignalDictionary
from .capture_session import build_capture_session_from_logs, export_capture_session, summarize_capture_session
from .discovery import analyze_frames
from .elm327 import capture_elm327_obd_log, parse_pid_selection
from .export import DEFAULT_MIN_CONFIDENCE, build_signal_dictionary, validate_signal_dictionary, write_json
from .identity import build_diagnostic_candidate_signals, build_signal_identity_report
from .labels import load_guided_session
from .obd_anchors import build_guided_session_payload_from_obd_log
from .parser import parse_can_log
from tools.bbb_hub.diagnostic_replay import load_state_jsonl, run_diagnostic_replay


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Mac-first CAN reverse-engineering workbench")
    subparsers = parser.add_subparsers(dest="command", required=True)

    analyze = subparsers.add_parser("analyze", help="rank CAN signal candidates and export can_signals.json")
    analyze.add_argument("--log", required=True, help="candump or CSV CAN log")
    analyze.add_argument("--labels", help="guided session JSON")
    analyze.add_argument("--out", required=True, help="output directory")
    analyze.add_argument("--max-candidates", type=int, default=20)
    analyze.add_argument("--min-export-confidence", type=float, default=DEFAULT_MIN_CONFIDENCE)
    analyze.add_argument("--target", action="append", dest="targets", help="signal target to rank; repeat for multiple targets")
    analyze.set_defaults(func=_cmd_analyze)

    obd_anchors = subparsers.add_parser("obd-anchors", help="convert OBD Mode 01 PID responses into guided anchor JSON")
    obd_anchors.add_argument("--log", required=True, help="JSONL OBD anchor log")
    obd_anchors.add_argument("--out", required=True, help="guided session JSON output path")
    obd_anchors.add_argument("--vehicle-profile", help="exact make/model/year/engine/trim/ECU calibration label")
    obd_anchors.set_defaults(func=_cmd_obd_anchors)

    elm327_capture = subparsers.add_parser(
        "elm327-capture",
        help="poll a live ELM327 adapter for read-only OBD Mode 01 anchors",
    )
    elm327_capture.add_argument("--device", required=True, help="serial device, e.g. /dev/ttyUSB0 or /dev/rfcomm0")
    elm327_capture.add_argument("--out", required=True, help="output OBD anchor JSONL path")
    elm327_capture.add_argument("--guided-out", help="optional guided session JSON output path")
    elm327_capture.add_argument("--baud", type=int, default=38400)
    elm327_capture.add_argument("--duration-sec", type=float, default=60.0)
    elm327_capture.add_argument("--sample-interval-sec", type=float, default=0.25)
    elm327_capture.add_argument("--timeout-sec", type=float, default=2.0)
    elm327_capture.add_argument("--pid", action="append", dest="pids", help="PID/name to poll; repeat or comma-separate")
    elm327_capture.add_argument("--no-init", action="store_true", help="skip standard ELM327 AT initialization")
    elm327_capture.add_argument("--no-supported-filter", action="store_true", help="poll requested PIDs even if 0100 support query excludes them")
    elm327_capture.add_argument("--drop-errors", action="store_true", help="do not write NO DATA/error rows to JSONL")
    elm327_capture.add_argument("--print-jsonl", action="store_true", help="also print each captured JSONL row")
    elm327_capture.add_argument("--vehicle-profile", help="exact make/model/year/engine/trim/ECU calibration label")
    elm327_capture.add_argument("--purpose", required=True, help="recorded owner-authorized testing/capture purpose")
    elm327_capture.add_argument("--owner-consent", action="store_true", help="confirm owner authorization for this live vehicle capture")
    elm327_capture.set_defaults(func=_cmd_elm327_capture)

    capture_session = subparsers.add_parser(
        "capture-session",
        help="store synchronized raw CAN and OBD/GPS anchors in one SQLite session",
    )
    capture_session.add_argument("--db", required=True, help="SQLite capture database path")
    capture_session.add_argument("--can-log", required=True, help="candump or CSV raw CAN log")
    capture_session.add_argument("--obd-log", required=True, help="JSONL OBD/GPS anchor log")
    capture_session.add_argument("--out", help="optional export directory for analyzer-ready files")
    capture_session.add_argument("--session-id", help="stable session id; generated when omitted")
    capture_session.add_argument("--vehicle-profile", help="exact make/model/year/engine/trim/ECU calibration label")
    capture_session.add_argument("--purpose", help="allowed diagnostic/capture purpose")
    capture_session.add_argument("--notes", help="operator notes for this capture")
    capture_session.add_argument("--thermal-start-class", choices=("cold", "warm", "hot"), help="thermal state at session start")
    capture_session.add_argument("--off-time-sec", type=float, help="engine-off soak time before session when known")
    capture_session.add_argument("--session-label", action="append", dest="session_labels", help="context label; repeatable")
    capture_session.add_argument("--decoder-version", help="decoder/profile version used for this capture")
    capture_session.set_defaults(func=_cmd_capture_session)

    export_session = subparsers.add_parser(
        "export-session",
        help="export analyzer-ready files from an existing capture database session",
    )
    export_session.add_argument("--db", required=True, help="SQLite capture database path")
    export_session.add_argument("--session-id", required=True, help="session id to export")
    export_session.add_argument("--out", required=True, help="export directory")
    export_session.set_defaults(func=_cmd_export_session)

    serve = subparsers.add_parser("serve", help="serve the local browser workbench")
    serve.add_argument("--analysis", required=True, help="analysis.json generated by analyze")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8769)
    serve.set_defaults(func=_cmd_serve)

    decode = subparsers.add_parser("decode", help="decode a raw CAN log using can_signals.json")
    decode.add_argument("--signals", required=True, help="can_signals.json")
    decode.add_argument("--log", required=True, help="candump or CSV CAN log")
    decode.add_argument("--out", required=True, help="output JSONL replay path")
    decode.set_defaults(func=_cmd_decode)

    consent = subparsers.add_parser("consent", help="create a pseudonymous vehicle diagnostic consent record")
    consent.add_argument("--out", required=True, help="output consent JSON path")
    consent.add_argument("--owner-reference", required=True, help="pseudonymous owner or work-order reference")
    consent.add_argument("--vehicle-profile", required=True, help="exact make/model/year/engine/trim/ECU calibration label")
    consent.add_argument("--purpose", required=True, help="allowed diagnostic purpose")
    consent.add_argument("--retention-days", type=int, default=DEFAULT_RETENTION_DAYS)
    consent.add_argument("--data-category", action="append", dest="data_categories", help="data category covered by consent")
    consent.add_argument("--owner-consent", action="store_true", help="confirm owner authorization for this diagnostic use")
    consent.set_defaults(func=_cmd_consent)

    baseline = subparsers.add_parser("baseline", help="build a consent-tagged known-good vehicle health baseline")
    baseline.add_argument("--decoded-good", required=True, help="decoded JSONL from the decode command")
    baseline.add_argument("--out", required=True, help="output baseline JSON path")
    baseline.add_argument("--vehicle-profile", help="exact make/model/year/engine/trim/ECU calibration label")
    baseline.add_argument("--purpose", required=True, help="recorded diagnostic purpose")
    baseline.add_argument("--owner-consent", action="store_true", help="confirm owner authorization for this diagnostic use")
    baseline.add_argument("--consent-record", help="vehicle diagnostic consent JSON generated by the consent command")
    baseline.add_argument("--retention-days", type=int, default=DEFAULT_RETENTION_DAYS)
    baseline.set_defaults(func=_cmd_baseline)

    diagnose = subparsers.add_parser("diagnose", help="compare a suspect decoded log against a known-good baseline")
    diagnose.add_argument("--baseline", required=True, help="baseline JSON generated by the baseline command")
    diagnose.add_argument("--decoded-suspect", required=True, help="decoded JSONL from the suspect vehicle")
    diagnose.add_argument("--out", required=True, help="output diagnostic report JSON path")
    diagnose.add_argument("--vehicle-profile", help="suspect vehicle profile label")
    diagnose.add_argument("--purpose", required=True, help="recorded diagnostic purpose")
    diagnose.add_argument("--owner-consent", action="store_true", help="confirm owner authorization for this diagnostic use")
    diagnose.add_argument("--consent-record", help="vehicle diagnostic consent JSON generated by the consent command")
    diagnose.add_argument("--retention-days", type=int, default=DEFAULT_RETENTION_DAYS)
    diagnose.add_argument("--customer-report", help="optional Markdown report path for customer/mechanic review")
    diagnose.set_defaults(func=_cmd_diagnose)

    transition_replay = subparsers.add_parser(
        "transition-replay",
        help="run decoded vehicle_state JSONL through the shared transition anomaly monitor",
    )
    transition_replay.add_argument("--decoded", required=True, help="decoded vehicle_state JSONL")
    transition_replay.add_argument("--out", required=True, help="output transition replay report JSON")
    transition_replay.add_argument("--frame-period-sec", type=float, default=0.1)
    transition_replay.set_defaults(func=_cmd_transition_replay)

    identity_report = subparsers.add_parser(
        "identity-report",
        help="rank unknown CAN candidates and export low-trust diagnostic signal hypotheses",
    )
    identity_report.add_argument("--log", help="candump or CSV raw CAN log")
    identity_report.add_argument("--labels", help="guided OBD/GPS anchor JSON")
    identity_report.add_argument("--decoded", help="optional decoded vehicle_state JSONL")
    identity_report.add_argument("--out", required=True, help="output signal_identity_hypothesis_report.json path")
    identity_report.add_argument("--candidate-export", help="optional diagnostic_candidate_signals.json output path")
    identity_report.add_argument("--max-candidates", type=int, default=50)
    identity_report.add_argument(
        "--ai-command",
        help="optional external command that reads compact evidence JSON on stdin and returns JSON suggestions",
    )
    identity_report.set_defaults(func=_cmd_identity_report)

    args = parser.parse_args(argv)
    return args.func(args)


def _cmd_analyze(args: argparse.Namespace) -> int:
    frames, stats = parse_can_log(args.log)
    session = load_guided_session(args.labels)
    analysis = analyze_frames(
        frames,
        session=session,
        parse_stats=stats,
        source={"log": args.log, "labels": args.labels},
        targets=args.targets or ("rpm", "speedKph"),
        max_candidates=args.max_candidates,
    )
    signal_dictionary = build_signal_dictionary(
        analysis,
        source_log=args.log,
        source_labels=args.labels,
        min_confidence=args.min_export_confidence,
    )
    errors = validate_signal_dictionary(signal_dictionary)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    write_json(out_dir / "analysis.json", analysis)
    write_json(out_dir / "can_signals.json", signal_dictionary)
    if errors:
        write_json(out_dir / "can_signals_errors.json", {"errors": errors})
        print(f"[can-workbench] wrote {out_dir / 'analysis.json'}")
        print(f"[can-workbench] wrote invalid export diagnostics: {out_dir / 'can_signals_errors.json'}")
        return 2
    print(f"[can-workbench] frames parsed: {stats.parsed} (skipped {stats.skipped})")
    print(f"[can-workbench] wrote {out_dir / 'analysis.json'}")
    print(f"[can-workbench] wrote {out_dir / 'can_signals.json'}")
    return 0


def _cmd_obd_anchors(args: argparse.Namespace) -> int:
    payload = build_guided_session_payload_from_obd_log(
        args.log,
        vehicle_profile=args.vehicle_profile,
    )
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json(output, payload)
    decoded = ", ".join(payload["obd"]["decodedSignals"]) or "none"
    supported_count = len(payload["obd"]["supportedPids"])
    warning_count = len(payload["obd"]["warnings"])
    print(f"[can-workbench] OBD decoded signals: {decoded}")
    print(f"[can-workbench] OBD supported PID count: {supported_count}")
    if warning_count:
        print(f"[can-workbench] OBD parse warnings: {warning_count}")
    print(f"[can-workbench] wrote {output}")
    return 0


def _cmd_elm327_capture(args: argparse.Namespace) -> int:
    if not args.owner_consent:
        print("[can-workbench] elm327 capture refused: --owner-consent is required for live vehicle polling")
        return 2
    if not args.purpose.strip():
        print("[can-workbench] elm327 capture refused: --purpose must describe the authorized capture")
        return 2
    try:
        summary = capture_elm327_obd_log(
            device=args.device,
            out_path=args.out,
            baud=args.baud,
            pids=parse_pid_selection(args.pids),
            duration_sec=args.duration_sec,
            sample_interval_sec=args.sample_interval_sec,
            timeout_sec=args.timeout_sec,
            initialize=not args.no_init,
            supported_filter=not args.no_supported_filter,
            include_errors=not args.drop_errors,
            print_rows=args.print_jsonl,
        )
        if args.guided_out:
            guided_payload = build_guided_session_payload_from_obd_log(
                args.out,
                vehicle_profile=args.vehicle_profile,
            )
            guided_payload["source"]["purpose"] = args.purpose
            guided_payload["source"]["ownerConsentConfirmed"] = True
            guided_payload["source"]["elm327Device"] = args.device
            guided_path = Path(args.guided_out)
            guided_path.parent.mkdir(parents=True, exist_ok=True)
            write_json(guided_path, guided_payload)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[can-workbench] elm327 capture failed: {exc}")
        return 2
    except KeyboardInterrupt:
        print("\n[can-workbench] elm327 capture stopped")
        return 130

    print(f"[can-workbench] ELM327 rows: {summary['rows']} (errors {summary['errors']})")
    print(f"[can-workbench] decoded signals: {', '.join(summary['decodedSignals']) or 'none'}")
    print(f"[can-workbench] wrote {args.out}")
    if args.guided_out:
        print(f"[can-workbench] wrote guided session: {args.guided_out}")
    return 0


def _cmd_capture_session(args: argparse.Namespace) -> int:
    try:
        summary = build_capture_session_from_logs(
            db_path=args.db,
            can_log=args.can_log,
            obd_log=args.obd_log,
            out_dir=args.out,
            session_id=args.session_id,
            vehicle_profile=args.vehicle_profile,
            purpose=args.purpose,
            notes=args.notes,
            thermal_start_class=args.thermal_start_class,
            off_time_sec=args.off_time_sec,
            session_labels=args.session_labels,
            decoder_version=args.decoder_version,
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[can-workbench] capture session failed: {exc}")
        return 2

    print(f"[can-workbench] capture session: {summary.session_id}")
    print(f"[can-workbench] raw CAN frames: {summary.raw_can_frames}")
    print(f"[can-workbench] anchor samples: {summary.anchor_samples}")
    print(f"[can-workbench] supported OBD PIDs: {summary.supported_pids}")
    if summary.warnings:
        print(f"[can-workbench] import warnings: {summary.warnings}")
    for label, path in sorted(summary.exports.items()):
        print(f"[can-workbench] wrote {label}: {path}")
    return 0


def _cmd_export_session(args: argparse.Namespace) -> int:
    try:
        exports = export_capture_session(args.db, args.session_id, args.out)
        summary = summarize_capture_session(args.db, args.session_id, exports=exports)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[can-workbench] export session failed: {exc}")
        return 2
    print(f"[can-workbench] capture session: {summary.session_id}")
    print(f"[can-workbench] raw CAN frames: {summary.raw_can_frames}")
    print(f"[can-workbench] anchor samples: {summary.anchor_samples}")
    for label, path in sorted(summary.exports.items()):
        print(f"[can-workbench] wrote {label}: {path}")
    return 0


def _cmd_serve(args: argparse.Namespace) -> int:
    analysis_path = Path(args.analysis).resolve()
    static_dir = Path(__file__).resolve().parent / "static"
    handler = partial(_WorkbenchHandler, analysis_path=analysis_path, directory=str(static_dir))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[can-workbench] serving http://{args.host}:{args.port}")
    print(f"[can-workbench] analysis: {analysis_path}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[can-workbench] stopped")
    return 0


def _cmd_decode(args: argparse.Namespace) -> int:
    dictionary = CanSignalDictionary.from_path(args.signals)
    frames, stats = parse_can_log(args.log)
    rows = dictionary.decode_frames(frames)
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")
    print(f"[can-workbench] frames parsed: {stats.parsed} (skipped {stats.skipped})")
    print(f"[can-workbench] decoded rows: {len(rows)}")
    print(f"[can-workbench] wrote {output}")
    return 0


def _cmd_consent(args: argparse.Namespace) -> int:
    try:
        consent = build_consent_record(
            owner_reference=args.owner_reference,
            vehicle_profile=args.vehicle_profile,
            purpose=args.purpose,
            owner_consent=args.owner_consent,
            retention_days=args.retention_days,
            data_categories=args.data_categories,
        )
    except ValueError as exc:
        print(f"[can-workbench] consent refused: {exc}")
        return 2
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json(output, consent)
    print(f"[can-workbench] wrote consent record: {output}")
    return 0


def _cmd_baseline(args: argparse.Namespace) -> int:
    try:
        rows = load_decoded_jsonl(args.decoded_good)
        consent_record = load_consent_record(args.consent_record)
        baseline = build_health_baseline(
            rows,
            source=args.decoded_good,
            vehicle_profile=args.vehicle_profile,
            purpose=args.purpose,
            owner_consent=args.owner_consent,
            consent_record=consent_record,
            retention_days=args.retention_days,
        )
    except ValueError as exc:
        print(f"[can-workbench] baseline refused: {exc}")
        return 2
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json(output, baseline)
    state_count = len(baseline.get("states", {}))
    print(f"[can-workbench] baseline states: {state_count}")
    print(f"[can-workbench] wrote {output}")
    return 0


def _cmd_diagnose(args: argparse.Namespace) -> int:
    try:
        baseline = json.loads(Path(args.baseline).read_text(encoding="utf-8"))
        consent_record = load_consent_record(args.consent_record)
        rows = load_decoded_jsonl(args.decoded_suspect)
        report = diagnose_against_baseline(
            baseline,
            rows,
            source=args.decoded_suspect,
            vehicle_profile=args.vehicle_profile,
            purpose=args.purpose,
            owner_consent=args.owner_consent,
            consent_record=consent_record,
            retention_days=args.retention_days,
        )
    except ValueError as exc:
        print(f"[can-workbench] diagnose refused: {exc}")
        return 2
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json(output, report)
    if args.customer_report:
        customer_report = Path(args.customer_report)
        customer_report.parent.mkdir(parents=True, exist_ok=True)
        customer_report.write_text(render_customer_report(report), encoding="utf-8")
        print(f"[can-workbench] wrote customer report: {customer_report}")
    print(f"[can-workbench] diagnostic status: {report['summary']['status']}")
    print(f"[can-workbench] findings: {report['summary']['findingCount']}")
    print(f"[can-workbench] wrote {output}")
    return 0


def _cmd_transition_replay(args: argparse.Namespace) -> int:
    try:
        report = run_diagnostic_replay(
            load_state_jsonl(args.decoded),
            frame_period_seconds=args.frame_period_sec,
            diagnostic_mode="workbench_transition_replay",
            vehicle_baseline_enabled=False,
            fault_recorder_enabled=False,
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[can-workbench] transition replay failed: {exc}")
        return 2
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json(output, report)
    print(f"[can-workbench] transition baseline ready: {report.get('transitionBaselineReady')}")
    print(f"[can-workbench] transition findings: {len(report.get('transitionFindings', []))}")
    print(f"[can-workbench] wrote {output}")
    return 0


def _cmd_identity_report(args: argparse.Namespace) -> int:
    if not args.log and not args.decoded:
        print("[can-workbench] identity-report needs --log, --decoded, or both")
        return 2
    try:
        frames = []
        stats = None
        if args.log:
            frames, stats = parse_can_log(args.log)
        session = load_guided_session(args.labels)
        decoded_rows = load_state_jsonl(args.decoded) if args.decoded else []
        report = build_signal_identity_report(
            frames,
            session=session,
            decoded_rows=decoded_rows,
            parse_stats=stats,
            source={"log": args.log, "labels": args.labels, "decoded": args.decoded},
            max_candidates=args.max_candidates,
            ai_command=args.ai_command,
        )
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[can-workbench] identity report failed: {exc}")
        return 2

    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_json(output, report)
    print(f"[can-workbench] hypotheses: {report['summary']['hypothesisCount']}")
    print(f"[can-workbench] probable low-trust candidates: {report['summary']['probableCount']}")
    print(f"[can-workbench] wrote {output}")
    if args.candidate_export:
        candidate_export = build_diagnostic_candidate_signals(report)
        export_path = Path(args.candidate_export)
        export_path.parent.mkdir(parents=True, exist_ok=True)
        write_json(export_path, candidate_export)
        print(f"[can-workbench] exported low-trust candidates: {len(candidate_export['candidates'])}")
        print(f"[can-workbench] wrote {export_path}")
    return 0


class _WorkbenchHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, analysis_path: Path, **kwargs: Any) -> None:
        self.analysis_path = analysis_path
        super().__init__(*args, **kwargs)

    def do_GET(self) -> None:
        if self.path in {"/analysis.json", "/api/analysis"}:
            self._send_analysis()
            return
        if self.path == "/":
            self.path = "/index.html"
        super().do_GET()

    def _send_analysis(self) -> None:
        payload = self.analysis_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
