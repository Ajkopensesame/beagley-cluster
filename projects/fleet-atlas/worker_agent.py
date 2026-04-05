#!/usr/bin/env python3
from __future__ import annotations

import json
import sys

from server import (
    DEFAULT_LAYERS,
    build_semantic_filters,
    compact_text,
    derive_layers_from_prompt,
    extract_relations,
    suggest_source_candidates,
)


def main() -> None:
    payload = json.load(sys.stdin)
    worker_name = str(payload.get("worker") or "")
    prompt = compact_text(payload.get("prompt") or "")

    if worker_name == "entity_parse":
        catalog = payload.get("catalog") if isinstance(payload.get("catalog"), dict) else {}
        catalog = {
            "ports": list(catalog.get("ports", [])),
            "owners": list(catalog.get("owners", [])),
            "flags": list(catalog.get("flags", [])),
            "shipNames": list(catalog.get("shipNames", [])),
        }
        data = build_semantic_filters(prompt, catalog)
        summary = f"Worker agent resolved {sum(1 for values in data.values() if values)} populated filter groups."
    elif worker_name == "relation_parse":
        data = extract_relations(prompt)
        summary = "Worker agent resolved spatial relations." if data else "Worker agent found no spatial relation."
    elif worker_name == "layer_inference":
        current_layers = payload.get("currentLayers") if isinstance(payload.get("currentLayers"), dict) else {}
        data = derive_layers_from_prompt(prompt, {**DEFAULT_LAYERS, **current_layers})
        summary = f"Worker agent left {sum(1 for enabled in data.values() if enabled)} layers enabled."
    elif worker_name == "source_scout":
        source_catalog = payload.get("sourceCatalog") if isinstance(payload.get("sourceCatalog"), list) else []
        source_registry = payload.get("sourceRegistry") if isinstance(payload.get("sourceRegistry"), dict) else {}
        data = suggest_source_candidates(prompt, source_catalog, source_registry)
        summary = (
            f"Worker agent suggested {len(data)} public sources for review."
            if data
            else "Worker agent found no relevant public sources."
        )
    else:
        raise SystemExit(f"Unsupported worker: {worker_name}")

    json.dump(
        {
            "summary": summary,
            "data": data,
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
