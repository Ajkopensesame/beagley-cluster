#!/usr/bin/env python3
"""Detect whether the BeagleY MapLibre screenshot is blank or unusably flat."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except Exception as exc:  # noqa: BLE001 - command line tool reports import failures.
    print(f"failed to import Pillow: {exc}", file=sys.stderr)
    raise SystemExit(2)


def analyze(path: Path, crop: tuple[float, float, float, float]) -> dict[str, object]:
    with Image.open(path) as image:
        rgb = image.convert("RGB")
        width, height = rgb.size
        left = max(0, min(width - 1, int(width * crop[0])))
        top = max(0, min(height - 1, int(height * crop[1])))
        right = max(left + 1, min(width, int(width * crop[2])))
        bottom = max(top + 1, min(height, int(height * crop[3])))
        sample = rgb.crop((left, top, right, bottom))
        sample.thumbnail((360, 180))
        pixels = list(sample.getdata())

    if not pixels:
        return {"ok": False, "failure": "no pixels in screenshot crop"}

    brightness = [(r + g + b) / 3.0 for r, g, b in pixels]
    mean = sum(brightness) / len(brightness)
    variance = sum((value - mean) ** 2 for value in brightness) / len(brightness)
    stddev = math.sqrt(variance)
    dark_fraction = sum(1 for value in brightness if value < 14.0) / len(brightness)
    bright_fraction = sum(1 for value in brightness if value > 242.0) / len(brightness)
    unique_colors = len(set(pixels))
    nonblack_fraction = sum(1 for value in brightness if value > 8.0) / len(brightness)

    failures: list[str] = []
    if mean < 12.0:
        failures.append("center map crop is too dark")
    if nonblack_fraction < 0.03:
        failures.append("center map crop is nearly black")
    if unique_colors < 48 and stddev < 5.0:
        failures.append("center map crop is too flat")
    if dark_fraction > 0.96:
        failures.append("center map crop is mostly black")
    if bright_fraction > 0.985 and stddev < 3.0:
        failures.append("center map crop is mostly blank white")

    return {
        "ok": not failures,
        "path": str(path),
        "crop": crop,
        "sample_pixels": len(pixels),
        "mean_brightness": round(mean, 2),
        "stddev_brightness": round(stddev, 2),
        "dark_fraction": round(dark_fraction, 4),
        "bright_fraction": round(bright_fraction, 4),
        "nonblack_fraction": round(nonblack_fraction, 4),
        "unique_colors": unique_colors,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("screenshot", type=Path)
    parser.add_argument("--crop", default="0.34,0.16,0.66,0.86",
                        help="left,top,right,bottom fractions for the center map crop")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    parts = [float(part.strip()) for part in args.crop.split(",")]
    if len(parts) != 4:
        raise SystemExit("--crop must have four comma-separated numbers")

    summary = analyze(args.screenshot, tuple(parts))  # type: ignore[arg-type]
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        status = "OK" if summary["ok"] else "FAIL"
        print(
            f"{status} mean={summary['mean_brightness']} stddev={summary['stddev_brightness']} "
            f"unique={summary['unique_colors']} dark={summary['dark_fraction']}"
        )
        for failure in summary.get("failures", []):
            print(f"failure: {failure}", file=sys.stderr)
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
