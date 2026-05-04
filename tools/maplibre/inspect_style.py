#!/usr/bin/env python3
"""Validate a MapLibre style before trying it on the BeagleY display."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urljoin
from urllib.request import Request, urlopen


DEFAULT_USER_AGENT = "BeagleyCluster/1.0 (MapLibre probe)"


@dataclass
class FetchResult:
    url: str
    status: int
    content_type: str
    data: bytes
    error: str = ""


def fetch(url: str, user_agent: str, timeout: float, limit: int | None = None) -> FetchResult:
    headers = {
        "Accept": "application/json,*/*;q=0.8",
        "User-Agent": user_agent,
    }
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=timeout) as response:
            read_size = None if limit is None else limit + 1
            data = response.read(read_size)
            if limit is not None and len(data) > limit:
                data = data[:limit]
            return FetchResult(
                url=url,
                status=getattr(response, "status", 200),
                content_type=response.headers.get("content-type", ""),
                data=data,
            )
    except HTTPError as exc:
        body = exc.read(512)
        return FetchResult(
            url=url,
            status=exc.code,
            content_type=exc.headers.get("content-type", ""),
            data=body,
            error=str(exc),
        )
    except URLError as exc:
        return FetchResult(url=url, status=0, content_type="", data=b"", error=str(exc))


def fetch_json(url: str, user_agent: str, timeout: float, limit: int | None = None) -> tuple[Any | None, dict[str, Any]]:
    result = fetch(url, user_agent, timeout, limit)
    summary: dict[str, Any] = {
        "url": result.url,
        "status": result.status,
        "content_type": result.content_type,
    }
    if result.error:
        summary["error"] = result.error
    try:
        return json.loads(result.data.decode("utf-8")), summary
    except Exception as exc:  # noqa: BLE001 - validation tool reports exact parse error.
        summary["json_error"] = str(exc)
        summary["sample"] = result.data[:160].decode("utf-8", errors="replace")
        return None, summary


def sprite_bases(sprite_value: Any, style_url: str) -> list[str]:
    if isinstance(sprite_value, str):
        return [urljoin(style_url, sprite_value)]
    if isinstance(sprite_value, list):
        bases = []
        for item in sprite_value:
            if isinstance(item, dict) and isinstance(item.get("url"), str):
                bases.append(urljoin(style_url, item["url"]))
        return bases
    return []


def referenced_font_stacks(layers: list[Any]) -> list[str]:
    stacks: list[str] = []
    for layer in layers:
        if not isinstance(layer, dict) or layer.get("type") != "symbol":
            continue
        layout = layer.get("layout")
        if not isinstance(layout, dict) or "text-field" not in layout:
            continue
        fonts = layout.get("text-font")
        if isinstance(fonts, list):
            stack = ",".join(str(font) for font in fonts if str(font).strip())
        elif isinstance(fonts, str):
            stack = fonts
        else:
            continue
        if stack and stack not in stacks:
            stacks.append(stack)
    return stacks


def sample_glyph_url(template: str, font_stack: str) -> str:
    return (
        template.replace("{fontstack}", quote(font_stack, safe=","))
        .replace("{range}", "0-255")
    )


def inspect_style(args: argparse.Namespace) -> dict[str, Any]:
    failures: list[str] = []
    warnings: list[str] = []
    style, style_fetch = fetch_json(
        args.style_url,
        args.user_agent,
        args.timeout,
        limit=args.max_json_bytes,
    )
    summary: dict[str, Any] = {
        "style_url": args.style_url,
        "style_fetch": style_fetch,
        "checks": {},
        "warnings": warnings,
        "failures": failures,
    }

    if not isinstance(style, dict):
        failures.append("style did not fetch as JSON")
        summary["ok"] = False
        return summary

    version = style.get("version")
    layers = style.get("layers")
    sources = style.get("sources")
    summary["name"] = style.get("name")
    summary["version"] = version
    summary["layer_count"] = len(layers) if isinstance(layers, list) else 0
    summary["source_count"] = len(sources) if isinstance(sources, dict) else 0

    if version != 8:
        failures.append(f"style version is {version!r}, expected 8")
    if not isinstance(layers, list) or not layers:
        failures.append("style has no layers")
        layers = []
    if not isinstance(sources, dict) or not sources:
        failures.append("style has no sources")
        sources = {}

    sprite_checks = []
    for base in sprite_bases(style.get("sprite"), args.style_url):
        base_summary: dict[str, Any] = {"base": base}
        for suffix in (".json", ".png"):
            url = base if base.endswith(suffix) else f"{base}{suffix}"
            result = fetch(url, args.user_agent, args.timeout, limit=args.max_binary_bytes)
            base_summary[suffix.lstrip(".")] = {
                "url": url,
                "status": result.status,
                "content_type": result.content_type,
            }
            if result.status < 200 or result.status >= 300:
                failures.append(f"sprite {suffix} failed: {url} status={result.status}")
        sprite_checks.append(base_summary)
    if style.get("sprite") and not sprite_checks:
        failures.append("sprite is declared but no usable sprite URL was found")
    summary["checks"]["sprites"] = sprite_checks

    glyph_checks = []
    glyph_template = style.get("glyphs")
    font_stacks = referenced_font_stacks(layers)
    if isinstance(glyph_template, str) and font_stacks:
        glyph_url = sample_glyph_url(urljoin(args.style_url, glyph_template), font_stacks[0])
        result = fetch(glyph_url, args.user_agent, args.timeout, limit=args.max_binary_bytes)
        glyph_checks.append({
            "url": glyph_url,
            "font_stack": font_stacks[0],
            "status": result.status,
            "content_type": result.content_type,
        })
        if result.status < 200 or result.status >= 300:
            failures.append(f"glyph sample failed: {glyph_url} status={result.status}")
    elif font_stacks:
        failures.append("symbol text layers reference fonts but style has no glyphs URL")
    elif isinstance(glyph_template, str):
        warnings.append("style declares glyphs but no text font stack was found to sample")
    summary["checks"]["glyphs"] = glyph_checks

    source_checks = []
    for name, source in sources.items():
        if not isinstance(source, dict):
            failures.append(f"source {name!r} is not an object")
            continue
        source_summary: dict[str, Any] = {
            "name": name,
            "type": source.get("type"),
        }
        source_url = source.get("url")
        if isinstance(source_url, str):
            resolved_url = urljoin(args.style_url, source_url)
            fetched, fetch_summary = fetch_json(
                resolved_url,
                args.user_agent,
                args.timeout,
                limit=args.max_json_bytes,
            )
            source_summary["url"] = fetch_summary
            if not isinstance(fetched, dict):
                failures.append(f"source {name!r} URL did not fetch as JSON: {resolved_url}")
            else:
                source_summary["tilejson"] = {
                    "minzoom": fetched.get("minzoom"),
                    "maxzoom": fetched.get("maxzoom"),
                    "bounds": fetched.get("bounds"),
                    "tile_count": len(fetched.get("tiles", [])) if isinstance(fetched.get("tiles"), list) else 0,
                    "vector_layer_count": len(fetched.get("vector_layers", []))
                    if isinstance(fetched.get("vector_layers"), list)
                    else 0,
                }
        elif source.get("tiles"):
            source_summary["tiles_declared"] = True
            warnings.append(f"source {name!r} declares direct tiles; tile fetch not sampled")
        else:
            warnings.append(f"source {name!r} has no URL and no direct tiles")
        source_checks.append(source_summary)
    summary["checks"]["sources"] = source_checks

    summary["ok"] = len(failures) == 0
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("style_url", help="MapLibre style JSON URL to inspect")
    parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT)
    parser.add_argument("--timeout", type=float, default=12.0)
    parser.add_argument("--max-json-bytes", type=int, default=2_000_000)
    parser.add_argument("--max-binary-bytes", type=int, default=128_000)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    args = parser.parse_args()

    summary = inspect_style(args)
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        status = "OK" if summary.get("ok") else "FAIL"
        print(f"{status} {summary['style_url']}")
        print(f"name={summary.get('name')!r} layers={summary.get('layer_count')} sources={summary.get('source_count')}")
        for failure in summary.get("failures", []):
            print(f"failure: {failure}", file=sys.stderr)
        for warning in summary.get("warnings", []):
            print(f"warning: {warning}", file=sys.stderr)
    return 0 if summary.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
