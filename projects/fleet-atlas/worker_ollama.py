#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from typing import Any

from server import (
    DEFAULT_LAYERS,
    LAYER_QUERY_HINTS,
    build_semantic_filters,
    compact_text,
    derive_layers_from_prompt,
    extract_relations,
    has_flag_filter_context,
    has_owner_filter_context,
    prompt_has_phrase,
    suggest_source_candidates,
)

DEFAULT_MODEL = "qwen2.5-coder:7b-instruct"
DEFAULT_HOST = "http://127.0.0.1:11434"
DEFAULT_KEEPALIVE = "10m"


def post_generate(host: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{host.rstrip('/')}/api/generate",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response)


def normalize_allowed_list(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    return [str(value) for value in values if str(value).strip()]


def sanitize_label_values(values: Any, allowed_values: list[str]) -> list[str]:
    if not isinstance(values, list):
        return []
    allowed_by_key = {compact_text(value): value for value in allowed_values}
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        key = compact_text(value)
        canonical = allowed_by_key.get(key)
        if not canonical or canonical in seen:
            continue
        result.append(canonical)
        seen.add(canonical)
    return result


def sanitize_text_terms(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        term = compact_text(value)
        if len(term) <= 2 or term in seen:
            continue
        result.append(term)
        seen.add(term)
    return result


def merge_entity_filters(prompt: str, heuristic: dict[str, list[str]], llm: dict[str, list[str]]) -> dict[str, list[str]]:
    text_terms = heuristic["textTerms"] or llm["textTerms"]
    return {
        "types": heuristic["types"] or llm["types"],
        "statuses": heuristic["statuses"],
        "ownerRegions": heuristic["ownerRegions"],
        "ports": heuristic["ports"] or llm["ports"],
        "owners": heuristic["owners"] or (llm["owners"] if has_owner_filter_context(prompt) else []),
        "flags": heuristic["flags"] or (llm["flags"] if has_flag_filter_context(prompt) else []),
        "shipNames": heuristic["shipNames"],
        "textTerms": text_terms,
    }


def sanitize_entity_parse(raw: dict[str, Any], catalog: dict[str, list[str]]) -> dict[str, list[str]]:
    return {
        "types": sanitize_label_values(raw.get("types"), normalize_allowed_list(catalog.get("types", []))),
        "statuses": sanitize_label_values(raw.get("statuses"), normalize_allowed_list(catalog.get("statuses", []))),
        "ownerRegions": sanitize_label_values(
            raw.get("ownerRegions"),
            normalize_allowed_list(catalog.get("ownerRegions", [])),
        ),
        "ports": sanitize_label_values(raw.get("ports"), normalize_allowed_list(catalog.get("ports", []))),
        "owners": sanitize_label_values(raw.get("owners"), normalize_allowed_list(catalog.get("owners", []))),
        "flags": sanitize_label_values(raw.get("flags"), normalize_allowed_list(catalog.get("flags", []))),
        "shipNames": sanitize_label_values(
            raw.get("shipNames"),
            normalize_allowed_list(catalog.get("shipNames", [])),
        ),
        "textTerms": sanitize_text_terms(raw.get("textTerms")),
    }


def sanitize_relations(raw: dict[str, Any]) -> list[dict[str, Any]]:
    relations = raw.get("relations")
    if not isinstance(relations, list):
        return []
    result: list[dict[str, Any]] = []
    for relation in relations:
        if not isinstance(relation, dict):
            continue
        if relation.get("type") != "near":
            continue
        try:
            distance_km = int(relation.get("distanceKm"))
        except (TypeError, ValueError):
            continue
        if distance_km <= 0:
            continue
        result.append({"type": "near", "distanceKm": distance_km})
    return result[:1]


def sanitize_layers(raw: dict[str, Any], current_layers: dict[str, bool]) -> dict[str, bool]:
    result = {**DEFAULT_LAYERS, **current_layers}
    for key in DEFAULT_LAYERS:
        if isinstance(raw.get(key), bool):
            result[key] = raw[key]
    return result


def sanitize_source_suggestions(
    raw: dict[str, Any],
    source_catalog: list[dict[str, Any]],
    source_registry: dict[str, Any],
) -> list[dict[str, Any]]:
    suggestions = raw.get("suggestions")
    if not isinstance(suggestions, list):
        return []

    catalog_by_id = {
        str(source.get("id") or ""): source
        for source in source_catalog
        if str(source.get("id") or "")
    }
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for suggestion in suggestions:
        if not isinstance(suggestion, dict):
            continue
        source_id = str(suggestion.get("sourceId") or suggestion.get("id") or "").strip()
        if not source_id or source_id in seen or source_id not in catalog_by_id:
            continue
        if source_registry.get(source_id, {}).get("decision") == "ignore":
            continue
        reason = str(suggestion.get("reason") or "").strip()
        result.append(
            {
                "sourceId": source_id,
                "reason": reason or f"Relevant {catalog_by_id[source_id].get('category', 'general')} source.",
                "score": 0,
            }
        )
        seen.add(source_id)
        if len(result) >= 3:
            break

    return result


def merge_source_suggestions(
    primary: list[dict[str, Any]],
    fallback: list[dict[str, Any]],
    limit: int = 3,
) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    for collection in (primary, fallback):
        for suggestion in collection:
            source_id = str(suggestion.get("sourceId") or suggestion.get("id") or "").strip()
            if not source_id or source_id in seen:
                continue
            merged.append(suggestion)
            seen.add(source_id)
            if len(merged) >= limit:
                return merged
    return merged


def build_entity_prompt(prompt: str, catalog: dict[str, list[str]]) -> str:
    return f"""
You extract structured map filters from a geospatial query.
Return JSON only with keys:
types, statuses, ownerRegions, ports, owners, flags, shipNames, textTerms.

Rules:
- Select label values only from the allowed lists below.
- If no values apply for a key, return [].
- Prefer ports over flags when a place name like Singapore appears without explicit flag wording.
- Only use owners when the prompt clearly names or targets a company/operator.
- Do not invent labels.

Prompt:
{prompt}

Allowed types:
{json.dumps(catalog.get("types", []))}

Allowed statuses:
{json.dumps(catalog.get("statuses", []))}

Allowed owner regions:
{json.dumps(catalog.get("ownerRegions", []))}

Allowed ports:
{json.dumps(catalog.get("ports", []))}

Allowed owners:
{json.dumps(catalog.get("owners", []))}

Allowed flags:
{json.dumps(catalog.get("flags", []))}

Allowed ship names:
{json.dumps(catalog.get("shipNames", []))}
""".strip()


def build_relation_prompt(prompt: str) -> str:
    return f"""
You extract spatial relations from a map query.
Return JSON only with this shape:
{{"relations":[{{"type":"near","distanceKm":25}}]}}

Rules:
- Only use relation type "near".
- If the prompt gives an explicit distance, convert it to an integer number of kilometers.
- If no spatial relation exists, return {{"relations":[]}}.

Prompt:
{prompt}
""".strip()


def build_layer_prompt(prompt: str, current_layers: dict[str, bool]) -> str:
    return f"""
You infer map layer toggles from a prompt.
Return JSON only with keys:
routes, ports, labels, owners

Rules:
- Start from the provided current layers.
- Only change a layer if the prompt clearly implies it should be shown or hidden.
- Keep the booleans explicit.

Prompt:
{prompt}

Current layers:
{json.dumps(current_layers)}
""".strip()


def has_layer_prompt_context(prompt: str) -> bool:
    return any(
        prompt_has_phrase(prompt, phrase)
        for hints in LAYER_QUERY_HINTS.values()
        for phrase in [*hints["enable"], *hints["disable"]]
    )


def build_source_scout_prompt(
    prompt: str,
    source_catalog: list[dict[str, Any]],
    source_registry: dict[str, Any],
) -> str:
    allowed_sources = [
        {
            "id": source.get("id"),
            "name": source.get("name"),
            "category": source.get("category"),
            "summary": source.get("summary"),
            "tags": source.get("tags", []),
            "decision": source_registry.get(str(source.get("id") or ""), {}).get("decision", ""),
        }
        for source in source_catalog
        if source_registry.get(str(source.get("id") or ""), {}).get("decision") != "ignore"
    ]

    return f"""
You select relevant public data sources for a geospatial query.
Return JSON only with this shape:
{{"suggestions":[{{"sourceId":"osm-overpass","reason":"short reason"}}]}}

Rules:
- Choose at most 3 sources.
- Use only sourceId values from the allowed list.
- Keep each reason short and concrete.
- Prefer sources that directly match the query intent.
- Do not include ignored sources.

Prompt:
{prompt}

Allowed sources:
{json.dumps(allowed_sources)}
""".strip()


def call_ollama(model: str, host: str, prompt: str) -> dict[str, Any]:
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "keep_alive": DEFAULT_KEEPALIVE,
        "options": {
            "temperature": 0,
            "num_predict": 256,
        },
    }
    response = post_generate(host, payload)
    raw_response = response.get("response") or "{}"
    return json.loads(raw_response)


def fallback_entity_parse(prompt: str, catalog: dict[str, list[str]]) -> dict[str, list[str]]:
    return build_semantic_filters(prompt, catalog)


def fallback_relation_parse(prompt: str) -> list[dict[str, Any]]:
    return extract_relations(prompt)


def fallback_layer_inference(prompt: str, current_layers: dict[str, bool]) -> dict[str, bool]:
    return derive_layers_from_prompt(prompt, {**DEFAULT_LAYERS, **current_layers})


def fallback_source_scout(
    prompt: str,
    source_catalog: list[dict[str, Any]],
    source_registry: dict[str, Any],
) -> list[dict[str, Any]]:
    return suggest_source_candidates(prompt, source_catalog, source_registry)


def run_task(model: str, host: str, worker_name: str, prompt: str, payload: dict[str, Any]) -> tuple[str, Any]:
    if worker_name == "entity_parse":
        catalog = payload.get("catalog") if isinstance(payload.get("catalog"), dict) else {}
        normalized_catalog = {
            "types": normalize_allowed_list(catalog.get("types", [])),
            "statuses": normalize_allowed_list(catalog.get("statuses", [])),
            "ownerRegions": normalize_allowed_list(catalog.get("ownerRegions", [])),
            "ports": normalize_allowed_list(catalog.get("ports", [])),
            "owners": normalize_allowed_list(catalog.get("owners", [])),
            "flags": normalize_allowed_list(catalog.get("flags", [])),
            "shipNames": normalize_allowed_list(catalog.get("shipNames", [])),
        }
        heuristic = build_semantic_filters(prompt, normalized_catalog)
        raw = call_ollama(model, host, build_entity_prompt(prompt, normalized_catalog))
        data = merge_entity_filters(prompt, heuristic, sanitize_entity_parse(raw, normalized_catalog))
        return (
            f"Ollama worker resolved {sum(1 for values in data.values() if values)} populated filter groups with {model}.",
            data,
        )

    if worker_name == "relation_parse":
        heuristic = extract_relations(prompt)
        if heuristic:
            return (
                "Guarded Ollama worker kept the heuristic spatial relation.",
                heuristic,
            )
        raw = call_ollama(model, host, build_relation_prompt(prompt))
        data = sanitize_relations(raw)
        return (
            f"Ollama worker returned {len(data)} spatial relations with {model}.",
            data,
        )

    if worker_name == "layer_inference":
        current_layers = payload.get("currentLayers") if isinstance(payload.get("currentLayers"), dict) else {}
        heuristic = derive_layers_from_prompt(prompt, {**DEFAULT_LAYERS, **current_layers})
        if heuristic != {**DEFAULT_LAYERS, **current_layers}:
            return (
                "Guarded Ollama worker kept the heuristic layer inference.",
                heuristic,
            )
        if not has_layer_prompt_context(prompt):
            return (
                "Guarded Ollama worker kept current layers because the prompt did not mention layer controls.",
                {**DEFAULT_LAYERS, **current_layers},
            )
        raw = call_ollama(model, host, build_layer_prompt(prompt, {**DEFAULT_LAYERS, **current_layers}))
        data = sanitize_layers(raw, current_layers)
        return (
            f"Ollama worker inferred {sum(1 for enabled in data.values() if enabled)} enabled layers with {model}.",
            data,
        )

    if worker_name == "source_scout":
        source_catalog = payload.get("sourceCatalog") if isinstance(payload.get("sourceCatalog"), list) else []
        source_registry = payload.get("sourceRegistry") if isinstance(payload.get("sourceRegistry"), dict) else {}
        heuristic = suggest_source_candidates(prompt, source_catalog, source_registry)
        raw = call_ollama(model, host, build_source_scout_prompt(prompt, source_catalog, source_registry))
        data = merge_source_suggestions(
            sanitize_source_suggestions(raw, source_catalog, source_registry),
            heuristic,
        )
        return (
            f"Ollama worker suggested {len(data)} public sources with {model}.",
            data,
        )

    raise SystemExit(f"Unsupported worker: {worker_name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ollama-backed Fleet Atlas worker.")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--host", default=DEFAULT_HOST)
    args = parser.parse_args()

    payload = json.load(sys.stdin)
    worker_name = str(payload.get("worker") or "")
    prompt = compact_text(payload.get("prompt") or "")

    try:
        summary, data = run_task(args.model, args.host, worker_name, prompt, payload)
    except Exception:
        if worker_name == "entity_parse":
            catalog = payload.get("catalog") if isinstance(payload.get("catalog"), dict) else {}
            data = fallback_entity_parse(prompt, catalog)
            summary = f"Fallback heuristic worker resolved {sum(1 for values in data.values() if values)} populated filter groups."
        elif worker_name == "relation_parse":
            data = fallback_relation_parse(prompt)
            summary = "Fallback heuristic worker resolved spatial relations." if data else "Fallback heuristic worker found no spatial relation."
        elif worker_name == "layer_inference":
            current_layers = payload.get("currentLayers") if isinstance(payload.get("currentLayers"), dict) else {}
            data = fallback_layer_inference(prompt, current_layers)
            summary = f"Fallback heuristic worker left {sum(1 for enabled in data.values() if enabled)} layers enabled."
        elif worker_name == "source_scout":
            source_catalog = payload.get("sourceCatalog") if isinstance(payload.get("sourceCatalog"), list) else []
            source_registry = payload.get("sourceRegistry") if isinstance(payload.get("sourceRegistry"), dict) else {}
            data = fallback_source_scout(prompt, source_catalog, source_registry)
            summary = (
                f"Fallback heuristic worker suggested {len(data)} public sources."
                if data
                else "Fallback heuristic worker found no relevant public sources."
            )
        else:
            raise

    json.dump(
        {
            "summary": summary,
            "data": data,
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
