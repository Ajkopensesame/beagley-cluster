#!/usr/bin/env python3
"""Fake Arduino UNO vehicle-input module: writes UNO-format lines to a pty, a file/FIFO/tty, or stdout.

Local simulation only; it never talks to hardware. The line format is exactly what
firmware/uno_vehicle_input/uno_vehicle_input.ino prints (docs/serial_vehicle_input_protocol.md):

  left=0,right=0,high_beam=0,brake=0,oil=0,charge=0,door=0,a0=512,a1=430,speed_hz=48.2,rpm_hz=37.5

Manual run against a local hub (no BBB, no BeagleY):

  python3 tools/bbb_hub/fake_uno.py --link /tmp/fake_uno --sweep ramp --period 20 &
  VEHICLE_INPUT_SERIAL_DEVICE=/tmp/fake_uno VEHICLE_SENSOR_CALIBRATION=/path/to/cal.json \\
      BBB_HUB_HOST=127.0.0.1 BBB_HUB_PORT=8765 python3 tools/bbb_hub/vehicle_hub_prod.py
  python3 tools/bbb_hub/sample_sensor_raw.py ws://127.0.0.1:8765 10      # read-only client

Sweeps (--sweep): fixed (the --a0/--a1/--speed-hz/--rpm-hz values), ramp (triangle wave of the
--channels between --min/--max over --period s), steps (BENCH_SIM firmware table, --step-s per step),
fault (a0/a1 pinned at 1023 then 0, to exercise the open/shorted-sender path).
--stop-after S stops sending after S seconds but keeps the pty open (an unplugged/crashed UNO).
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import tty
from typing import Callable

CHANNELS = ("a0", "a1", "speed_hz", "rpm_hz")
LAMPS = ("left", "right", "high_beam", "brake", "oil", "charge", "door")
# Same table as the firmware's BENCH_SIM mode (a0 = round(V/5*1023) for 0, 1.25, 2.5, 3.75, 5 V).
BENCH_STEPS = [
    {"a0": 0, "a1": 1023, "speed_hz": 0.0, "rpm_hz": 200.0},
    {"a0": 256, "a1": 767, "speed_hz": 10.0, "rpm_hz": 100.0},
    {"a0": 512, "a1": 512, "speed_hz": 50.0, "rpm_hz": 50.0},
    {"a0": 767, "a1": 256, "speed_hz": 100.0, "rpm_hz": 10.0},
    {"a0": 1023, "a1": 0, "speed_hz": 200.0, "rpm_hz": 0.0},
]
DEFAULT_RANGES = {"a0": (120.0, 880.0), "a1": (250.0, 900.0), "speed_hz": (0.0, 200.0), "rpm_hz": (0.0, 200.0)}


def format_line(a0: float, a1: float, speed_hz: float, rpm_hz: float, lamps: dict[str, int] | None = None) -> str:
    """One UNO line (no newline), keys in the order the sketch prints them. a0/a1 are integer counts."""
    lamp_values = {name: 0 for name in LAMPS}
    lamp_values.update(lamps or {})
    parts = [f"{name}={int(bool(lamp_values[name]))}" for name in LAMPS]
    parts += [f"a0={int(round(a0))}", f"a1={int(round(a1))}", f"speed_hz={speed_hz:.1f}", f"rpm_hz={rpm_hz:.1f}"]
    return ",".join(parts)


def triangle(t: float, period: float) -> float:
    """0..1..0 triangle wave with the given period."""
    if period <= 0:
        return 0.0
    phase = (t % period) / period
    return 2 * phase if phase < 0.5 else 2 * (1 - phase)


def sample(sweep: str, t: float, fixed: dict[str, float], *, channels: tuple[str, ...] = CHANNELS,
           period: float = 20.0, step_s: float = 5.0,
           ranges: dict[str, tuple[float, float]] | None = None) -> dict[str, float]:
    """Channel values at time ``t`` seconds after start."""
    ranges = {**DEFAULT_RANGES, **(ranges or {})}
    if sweep == "fixed":
        return dict(fixed)
    if sweep == "steps":
        return dict(BENCH_STEPS[int(t // step_s) % len(BENCH_STEPS)])
    if sweep == "fault":
        stuck = 1023.0 if int(t // step_s) % 2 == 0 else 0.0
        return {**fixed, "a0": stuck, "a1": stuck}
    if sweep == "ramp":
        values = dict(fixed)
        for name in channels:
            lo, hi = ranges[name]
            values[name] = lo + (hi - lo) * triangle(t, period)
        return values
    raise ValueError(f"unknown sweep {sweep!r}")


class Output:
    """Where the lines go. ``write`` never blocks: a full pty buffer (nobody reading) drops the line."""

    def __init__(self, write: Callable[[bytes], None], description: str, close: Callable[[], None] = lambda: None):
        self.write = write
        self.description = description
        self.close = close


def open_pty(link: str | None = None) -> Output:
    master, slave = os.openpty()
    tty.setraw(slave)  # no echo/translation on the reader's side
    os.set_blocking(master, False)
    slave_path = os.ttyname(slave)
    if link:
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(slave_path, link)

    def write(data: bytes) -> None:
        try:
            os.write(master, data)
        except BlockingIOError:
            pass

    def close() -> None:
        if link and os.path.islink(link):
            os.remove(link)
        os.close(master)
        os.close(slave)

    return Output(write, f"pty {slave_path}" + (f" (link {link})" if link else ""), close)


def open_path(path: str) -> Output:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NONBLOCK | os.O_NOCTTY)

    def write(data: bytes) -> None:
        try:
            os.write(fd, data)
        except BlockingIOError:
            pass

    return Output(write, path, lambda: os.close(fd))


def _parse_range(text: str) -> tuple[str, tuple[float, float]]:
    name, _, span = text.partition("=")
    lo, _, hi = span.partition(":")
    if name not in CHANNELS or not lo or not hi:
        raise argparse.ArgumentTypeError("expected CHANNEL=LOW:HIGH, e.g. a0=120:880")
    return name, (float(lo), float(hi))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawTextHelpFormatter)
    dest = p.add_mutually_exclusive_group()
    dest.add_argument("--out", metavar="PATH", help="write to an existing tty/FIFO or a file instead of a new pty")
    dest.add_argument("--stdout", action="store_true", help="print lines to stdout")
    p.add_argument("--link", metavar="PATH", help="(pty mode) symlink to the pty slave, e.g. /tmp/fake_uno")
    p.add_argument("--sweep", choices=["fixed", "ramp", "steps", "fault"], default="fixed")
    p.add_argument("--channels", default=",".join(CHANNELS), help="(ramp) comma list of channels to sweep")
    p.add_argument("--range", dest="ranges", action="append", type=_parse_range, default=[],
                   metavar="CH=LO:HI", help="(ramp) override a channel range, e.g. a0=100:900")
    p.add_argument("--period", type=float, default=20.0, help="(ramp) seconds per up-and-down sweep")
    p.add_argument("--step-s", type=float, default=5.0, help="(steps, fault) seconds per step")
    p.add_argument("--a0", type=float, default=512.0)
    p.add_argument("--a1", type=float, default=430.0)
    p.add_argument("--speed-hz", type=float, default=0.0)
    p.add_argument("--rpm-hz", type=float, default=0.0)
    p.add_argument("--lamp", action="append", default=[], metavar="NAME=0|1",
                   help=f"set a lamp field ({', '.join(LAMPS)}); repeatable")
    p.add_argument("--rate", type=float, default=10.0, help="lines per second (firmware: 10)")
    p.add_argument("--duration", type=float, default=0.0, help="exit after this many seconds (0 = run until Ctrl-C)")
    p.add_argument("--stop-after", type=float, default=0.0,
                   help="stop sending after this many seconds but keep running (simulates an unplugged UNO)")
    return p


def run(args: argparse.Namespace, output: Output) -> int:
    lamps: dict[str, int] = {}
    for item in args.lamp:
        name, _, value = item.partition("=")
        if name not in LAMPS or value not in {"0", "1"}:
            raise SystemExit(f"--lamp expects one of {LAMPS} =0|1, got {item!r}")
        lamps[name] = int(value)
    fixed = {"a0": args.a0, "a1": args.a1, "speed_hz": args.speed_hz, "rpm_hz": args.rpm_hz}
    channels = tuple(c.strip() for c in args.channels.split(",") if c.strip())
    bad = [c for c in channels if c not in CHANNELS]
    if bad:
        raise SystemExit(f"unknown channel(s) {bad}; choose from {CHANNELS}")
    ranges = dict(args.ranges)
    period = 1.0 / args.rate
    start = time.monotonic()
    next_at = start
    while True:
        now = time.monotonic()
        elapsed = now - start
        if args.duration and elapsed >= args.duration:
            return 0
        if not (args.stop_after and elapsed >= args.stop_after):
            values = sample(args.sweep, elapsed, fixed, channels=channels, period=args.period,
                            step_s=args.step_s, ranges=ranges)
            line = format_line(values["a0"], values["a1"], values["speed_hz"], values["rpm_hz"], lamps)
            output.write(line.encode() + b"\n")
        next_at += period
        time.sleep(max(0.0, next_at - time.monotonic()))


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.stdout:
        output = Output(lambda data: sys.stdout.write(data.decode()) or sys.stdout.flush(), "stdout")
    elif args.out:
        output = open_path(args.out)
    else:
        output = open_pty(args.link)
    print(f"fake_uno: writing {args.sweep} lines to {output.description} at {args.rate:g} Hz", file=sys.stderr, flush=True)
    try:
        return run(args, output)
    except KeyboardInterrupt:
        return 0
    finally:
        output.close()


if __name__ == "__main__":
    raise SystemExit(main())
