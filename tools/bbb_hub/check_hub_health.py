#!/usr/bin/env python3
"""Read-only post-deploy health check for the BBB vehicle hub.

  python3 tools/bbb_hub/check_hub_health.py [ws://10.24.0.7:8765] [--require-serial] [--require-gps]

Connects, reads a few frames, prints a one-line verdict and exits:
  0 healthy, 1 hub up but a required source is stale/missing, 2 hub unreachable or malformed.
Never sends anything to the hub.
"""
from __future__ import annotations

import asyncio
import json
import sys

import websockets


async def check(url: str, require_serial: bool, require_gps: bool) -> int:
    try:
        async with websockets.connect(url, open_timeout=5) as ws:
            state = {}
            for _ in range(5):
                state = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
    except Exception as exc:  # noqa: BLE001 - any failure means unreachable
        print(f"FAIL unreachable {url}: {exc}")
        return 2
    health = state.get("_health") or {}
    if state.get("type") != "vehicle_state" or state.get("version") != 1 or not health:
        print(f"FAIL malformed frame (type={state.get('type')!r} version={state.get('version')!r})")
        return 2
    problems = []
    serial = health.get("serialVehicleInputs") or {}
    if require_serial and (not serial.get("enabled") or serial.get("stale")):
        problems.append(f"serial stale/disabled (frames={serial.get('frames')}, err={serial.get('lastError')})")
    if require_gps and health.get("gpsStale", True):
        problems.append(f"gps stale (device={health.get('gpsDevice')}, err={health.get('gpsLastError')})")
    if health.get("diagnosticStackDegraded"):
        problems.append(f"diagnostic stack degraded: {health.get('diagnosticStackReasons')}")
    summary = f"source={health.get('vehicleSource')} stale={health.get('stale')} gpsStale={health.get('gpsStale')}"
    if problems:
        print(f"WARN {summary}; " + "; ".join(problems))
        return 1
    print(f"OK {summary}")
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    sys.exit(
        asyncio.run(
            check(args[0] if args else "ws://127.0.0.1:8765", "--require-serial" in flags, "--require-gps" in flags)
        )
    )
