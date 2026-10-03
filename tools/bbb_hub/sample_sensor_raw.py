#!/usr/bin/env python3
"""Print raw A0/A1 (and speed/rpm pulse Hz) the hub is receiving, for calibration.

Read-only WebSocket client. Usage:
  python3 tools/bbb_hub/sample_sensor_raw.py [ws://10.24.0.7:8765] [seconds]
Hold the tank / engine at a known level or temperature, run it, and use the mean
counts as the raw side of a point in config/sensor_calibration.json.
"""
from __future__ import annotations

import asyncio
import json
import statistics
import sys

import websockets


async def main(url: str, seconds: float) -> None:
    samples: dict[str, list[float]] = {"a0": [], "a1": [], "speed_hz": [], "rpm_hz": []}
    loop = asyncio.get_running_loop()
    end = loop.time() + seconds
    async with websockets.connect(url) as ws:
        while loop.time() < end:
            state = json.loads(await ws.recv())
            serial = (state.get("_health") or {}).get("serialVehicleInputs") or {}
            raw = serial.get("raw") or {}
            for key in samples:
                if key in raw:
                    samples[key].append(float(raw[key]))
            print(
                f"raw={raw} stale={serial.get('stale')} faults={serial.get('sensorFaults')} "
                f"fuelPct={state.get('fuelPct')} coolantC={state.get('coolantC')} "
                f"speedKph={state.get('speedKph')} rpm={state.get('rpm')} "
                f"speedSource={((state.get('_health') or {}).get('speedSource') or {}).get('active')}"
            )
    for key, values in samples.items():
        if values:
            print(f"{key}: n={len(values)} mean={statistics.mean(values):.1f} min={min(values)} max={max(values)}")
    if not any(samples.values()):
        print("no raw readings seen: serial module not sending a0/a1/speed_hz/rpm_hz (check wiring/firmware)")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "ws://10.24.0.7:8765",
                     float(sys.argv[2]) if len(sys.argv) > 2 else 10.0))
