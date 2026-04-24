from __future__ import annotations

from typing import Any

from .stats import clamp
from .values import number_or_none


SEVERITY_ORDER = {
    "ok": 0,
    "info": 1,
    "warning": 2,
    "error": 3,
}

PUBLIC_DETAIL_KEYS = {
    "ageMs",
    "ageSeconds",
    "deltaKph",
    "gpsSpeedKph",
    "limitKph",
    "model",
    "ratePerSec",
    "suspectedCauses",
    "value",
}


def normalize_severity(value: Any) -> str:
    severity = str(value or "info").strip().lower()
    return severity if severity in SEVERITY_ORDER else "info"


def make_signal_fault(signal: str, code: str, severity: str, message: str, **details: Any) -> dict[str, Any]:
    return {
        "signal": signal,
        "code": code,
        "severity": normalize_severity(severity),
        "message": message,
        "details": details,
    }


def make_diagnostic_finding(
    *,
    source: str,
    subject: str,
    code: str,
    severity: str,
    message: str,
    confidence: float,
    **details: Any,
) -> dict[str, Any]:
    return {
        "source": source,
        "subject": subject,
        "code": code,
        "severity": normalize_severity(severity),
        "message": message,
        "confidence": round(clamp(confidence), 4),
        "details": details,
    }


def normalize_signal_fault(fault: dict[str, Any]) -> dict[str, Any]:
    details = fault.get("details") if isinstance(fault.get("details"), dict) else {}
    source = str(details.get("source") or details.get("diagnostics") or "signalMonitor")
    subject = str(fault.get("signal") or fault.get("subject") or "vehicle")
    return clean_display_finding(
        {
            "source": source,
            "subject": subject,
            "code": str(fault.get("code") or "signal_fault"),
            "severity": normalize_severity(fault.get("severity")),
            "message": str(fault.get("message") or "Vehicle signal fault"),
            "confidence": number_or_none(details.get("confidence")),
            "details": public_details(details),
        }
    )


def normalize_diagnostic_finding(finding: dict[str, Any], *, default_source: str) -> dict[str, Any]:
    details = finding.get("details") if isinstance(finding.get("details"), dict) else {}
    subject = finding.get("subject", finding.get("signal", finding.get("model", "vehicle")))
    return clean_display_finding(
        {
            "source": str(finding.get("source") or default_source),
            "subject": str(subject),
            "code": str(finding.get("code") or "diagnostic_finding"),
            "severity": normalize_severity(finding.get("severity")),
            "message": str(finding.get("message") or "Diagnostic finding"),
            "confidence": number_or_none(finding.get("confidence")),
            "details": public_details(details),
        }
    )


def public_details(details: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in details.items() if key in PUBLIC_DETAIL_KEYS}


def clean_display_finding(finding: dict[str, Any]) -> dict[str, Any]:
    if finding.get("confidence") is None:
        finding.pop("confidence", None)
    if not finding.get("details"):
        finding.pop("details", None)
    return finding
