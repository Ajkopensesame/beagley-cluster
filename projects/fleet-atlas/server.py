#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

PROJECT_ROOT = Path(__file__).resolve().parent
DATA_PATH = PROJECT_ROOT / "data" / "mock-vessels.json"
SOURCE_CATALOG_PATH = PROJECT_ROOT / "data" / "source-catalog.json"
RUNTIME_DIR = PROJECT_ROOT / "runtime"
MEMORY_PATH = RUNTIME_DIR / "planner-memory.json"
CACHE_PATH = RUNTIME_DIR / "plan-cache.json"
SOURCE_REGISTRY_PATH = RUNTIME_DIR / "source-registry.json"
PLAN_CACHE_TTL_MS = 5 * 60 * 1000
SOURCE_REVIEW_ACTIONS = {"add", "ignore", "sandbox"}

TYPE_QUERY_ALIASES = {
    "Container": ["container", "containers", "boxship", "boxships"],
    "Tanker": ["tanker", "tankers", "oil tanker", "product tanker"],
    "LNG": ["lng", "lng carrier", "lng carriers", "gas carrier", "gas carriers"],
    "Bulk Carrier": ["bulk", "bulk carrier", "bulk carriers", "ore carrier", "ore carriers"],
    "Ro-Ro": ["ro-ro", "ro ro", "roro", "vehicle carrier", "vehicle carriers"],
    "Passenger": ["passenger", "cruise", "cruise ship", "ferry", "ferries"],
    "Fishing": ["fishing", "trawler", "trawlers"],
    "Research": ["research", "survey vessel", "survey", "science vessel"],
}

STATUS_QUERY_ALIASES = {
    "In transit": ["in transit", "underway", "moving", "en route"],
    "Approaching port": ["approaching port", "arriving", "approach"],
    "Loading": ["loading", "loading cargo", "at berth"],
    "Survey operations": ["survey operations", "research operations", "on survey"],
    "At anchor": ["at anchor", "anchored", "anchor"],
    "Weather hold": ["weather hold", "weather delayed", "delayed by weather"],
}

REGION_QUERY_ALIASES = {
    "Asia-Pacific": ["asia pacific", "asia-pacific", "apac", "australia", "new zealand"],
    "Europe": ["europe", "european", "eu"],
    "North America": ["north america", "north american", "usa", "united states", "canada"],
    "South America": ["south america", "south american", "brazil", "chile"],
    "Middle East": ["middle east", "gulf", "uae", "saudi", "qatar"],
    "Africa": ["africa", "african", "liberia"],
}

LAYER_QUERY_HINTS = {
    "routes": {
        "enable": ["route", "routes", "voyage", "voyages", "corridor", "corridors"],
        "disable": ["hide routes", "no routes", "without routes"],
    },
    "ports": {
        "enable": ["port", "ports", "origin", "destination"],
        "disable": ["hide ports", "no ports", "without ports"],
    },
    "labels": {
        "enable": ["label", "labels", "names"],
        "disable": ["hide labels", "no labels", "without labels"],
    },
    "owners": {
        "enable": ["owner", "owners", "ownership"],
        "disable": ["hide owners", "no owners", "without owners"],
    },
}

STOPWORDS = {
    "a",
    "an",
    "and",
    "around",
    "ask",
    "bound",
    "current",
    "describe",
    "display",
    "focus",
    "for",
    "going",
    "heading",
    "highlight",
    "in",
    "into",
    "lane",
    "lanes",
    "location",
    "map",
    "me",
    "near",
    "of",
    "on",
    "or",
    "owner",
    "owners",
    "plot",
    "please",
    "port",
    "ports",
    "route",
    "routes",
    "scope",
    "ship",
    "ships",
    "show",
    "the",
    "this",
    "to",
    "traffic",
    "use",
    "view",
    "vessel",
    "vessels",
    "voyage",
    "voyages",
    "with",
    "within",
}

DEFAULT_LAYERS = {
    "routes": True,
    "ports": True,
    "labels": True,
    "owners": False,
}


def normalize_text(value: Any) -> str:
    return (
        str(value or "")
        .lower()
        .replace("&", " and ")
        .replace("_", " ")
        .replace("-", " ")
    )


def compact_text(value: Any) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9\s-]", " ", normalize_text(value))).strip()


def unique_labels(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.add(value)
            result.append(value)
    return result


def sort_labels(values: list[str]) -> list[str]:
    return sorted(values, key=lambda item: item.lower())


def prompt_has_phrase(prompt: str, phrase: str) -> bool:
    normalized_phrase = compact_text(phrase)
    if not normalized_phrase:
        return False
    normalized_pattern = re.escape(normalized_phrase).replace(r"\ ", r"\s+")
    pattern = re.compile(rf"(^|\b){normalized_pattern}(\b|$)")
    return bool(pattern.search(prompt))


def match_alias_map(prompt: str, alias_map: dict[str, list[str]]) -> list[str]:
    matches: list[str] = []
    for label, aliases in alias_map.items():
        if any(prompt_has_phrase(prompt, alias) for alias in aliases):
            matches.append(label)
    return matches


def match_dynamic_labels(prompt: str, labels: list[str]) -> list[str]:
    return [label for label in labels if prompt_has_phrase(prompt, label)]


def has_owner_filter_context(prompt: str) -> bool:
    return (
        prompt_has_phrase(prompt, "owner")
        or prompt_has_phrase(prompt, "owned by")
        or prompt_has_phrase(prompt, "operator")
        or prompt_has_phrase(prompt, "company")
    )


def has_flag_filter_context(prompt: str) -> bool:
    return (
        prompt_has_phrase(prompt, "flag")
        or prompt_has_phrase(prompt, "flagged")
        or prompt_has_phrase(prompt, "registered under")
    )


def collect_matched_words(collections: list[list[str]]) -> set[str]:
    matched_words: set[str] = set()
    for collection in collections:
        for label in collection:
            for token in compact_text(label).split():
                if token:
                    matched_words.add(token)
    return matched_words


def singularize(token: str) -> str:
    if len(token) <= 3:
        return token
    if token.endswith("ies") and len(token) > 4:
        return f"{token[:-3]}y"
    if token.endswith(("ches", "shes", "sses", "xes", "zes")) and len(token) > 4:
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def extract_search_terms(prompt: str, matched_words: set[str]) -> list[str]:
    terms: list[str] = []
    for token in prompt.split():
        candidate = token.strip()
        if len(candidate) <= 2:
            continue
        if candidate in STOPWORDS:
            continue
        if candidate.isdigit():
            continue
        singular = singularize(candidate)
        if candidate in matched_words or singular in matched_words:
            continue
        terms.append(candidate)
    return unique_labels(terms)


def extract_prompt_tokens(prompt: str) -> list[str]:
    tokens: list[str] = []
    for token in prompt.split():
        candidate = token.strip()
        if len(candidate) <= 2:
            continue
        if candidate in STOPWORDS:
            continue
        tokens.append(singularize(candidate))
    return unique_labels(tokens)


def parse_distance_km(prompt: str) -> int | None:
    match = re.search(r"\bwithin\s+(\d{1,3})\s*(km|kilometers?|mi|miles|nm)\b", prompt)
    if not match:
        return None
    value = int(match.group(1))
    unit = match.group(2)
    if unit.startswith("mi"):
        return round(value * 1.609)
    if unit == "nm":
        return round(value * 1.852)
    return value


def extract_relations(prompt: str) -> list[dict[str, Any]]:
    explicit_distance_km = parse_distance_km(prompt)
    if explicit_distance_km is not None:
        return [{"type": "near", "distanceKm": explicit_distance_km}]
    if (
        prompt_has_phrase(prompt, "near")
        or prompt_has_phrase(prompt, "around")
        or prompt_has_phrase(prompt, "close to")
    ):
        return [{"type": "near", "distanceKm": 25}]
    return []


def derive_layers_from_prompt(prompt: str, current_layers: dict[str, bool]) -> dict[str, bool]:
    next_layers = {**DEFAULT_LAYERS, **(current_layers or {})}
    for layer, hints in LAYER_QUERY_HINTS.items():
        if any(prompt_has_phrase(prompt, phrase) for phrase in hints["disable"]):
            next_layers[layer] = False
            continue
        if any(prompt_has_phrase(prompt, phrase) for phrase in hints["enable"]):
            next_layers[layer] = True
    return next_layers


def extract_collection(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("vessels", "data", "results"):
            if isinstance(payload.get(key), list):
                return payload[key]
    return []


def stable_dumps(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def hash_string(value: str) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]


def clone_json(value: Any) -> Any:
    return json.loads(json.dumps(value))


def normalize_source_action(value: Any) -> str:
    action = compact_text(value)
    if action not in SOURCE_REVIEW_ACTIONS:
        raise ValueError(f"Unsupported source review action: {value}")
    return action


class WorkerAdapter:
    def __init__(self, command: str = "", timeout_s: float = 30.0) -> None:
        self.command = command.strip()
        self.timeout_s = timeout_s

    @property
    def mode(self) -> str:
        return "subprocess" if self.command else "inline"

    def run(self, worker_name: str, payload: dict[str, Any]) -> tuple[str, Any]:
        if not self.command:
            raise RuntimeError("No worker command configured")

        completed = subprocess.run(
            shlex.split(self.command),
            input=json.dumps(
                {
                    "worker": worker_name,
                    **payload,
                }
            ),
            capture_output=True,
            text=True,
            timeout=self.timeout_s,
            check=False,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr.strip() or f"Worker exited with {completed.returncode}")

        try:
            response = json.loads(completed.stdout or "{}")
        except json.JSONDecodeError as error:
            raise RuntimeError("Worker returned invalid JSON") from error

        return str(response.get("summary") or "Worker completed."), response.get("data")


class CatalogProvider:
    def __init__(self, data_path: Path) -> None:
        self.data_path = data_path
        self.lock = threading.Lock()
        self.cached_catalog: dict[str, list[str]] | None = None
        self.cached_mtime_ns = 0

    def get_catalog(self) -> dict[str, list[str]]:
        mtime_ns = self.data_path.stat().st_mtime_ns
        with self.lock:
            if self.cached_catalog and mtime_ns == self.cached_mtime_ns:
                return clone_json(self.cached_catalog)

            payload = json.loads(self.data_path.read_text())
            vessels = extract_collection(payload)
            ports = unique_labels(
                [
                    vessel.get("origin", {}).get("name")
                    if isinstance(vessel.get("origin"), dict)
                    else vessel.get("origin")
                    for vessel in vessels
                ]
                + [
                    vessel.get("originPort")
                    for vessel in vessels
                ]
                + [
                    vessel.get("destination", {}).get("name")
                    if isinstance(vessel.get("destination"), dict)
                    else vessel.get("destination")
                    for vessel in vessels
                ]
                + [
                    vessel.get("destinationPort")
                    for vessel in vessels
                ]
            )
            owners = unique_labels(
                [
                    vessel.get("owner") or vessel.get("company") or vessel.get("registeredOwner")
                    for vessel in vessels
                ]
            )
            flags = unique_labels([vessel.get("flag") or vessel.get("flagCountry") for vessel in vessels])
            ship_names = unique_labels(
                [vessel.get("name") or vessel.get("vesselName") for vessel in vessels]
            )
            self.cached_catalog = {
                "types": sort_labels(
                    unique_labels(
                        [
                            vessel.get("type") or vessel.get("shipType") or vessel.get("vesselType")
                            for vessel in vessels
                        ]
                    )
                ),
                "statuses": sort_labels(
                    unique_labels(
                        [
                            vessel.get("status")
                            or vessel.get("navStatus")
                            or vessel.get("navigationStatus")
                            for vessel in vessels
                        ]
                    )
                ),
                "ownerRegions": sort_labels(
                    unique_labels(
                        [
                            vessel.get("ownerRegion")
                            or vessel.get("ownerCountry")
                            or vessel.get("owner_country")
                            for vessel in vessels
                        ]
                    )
                ),
                "ports": sort_labels([value for value in ports if value]),
                "owners": sort_labels([value for value in owners if value]),
                "flags": sort_labels([value for value in flags if value]),
                "shipNames": sort_labels([value for value in ship_names if value]),
            }
            self.cached_mtime_ns = mtime_ns
            return clone_json(self.cached_catalog)


class SourceCatalogProvider:
    def __init__(self, data_path: Path) -> None:
        self.data_path = data_path
        self.lock = threading.Lock()
        self.cached_catalog: list[dict[str, Any]] | None = None
        self.cached_mtime_ns = 0

    def get_catalog(self) -> list[dict[str, Any]]:
        if not self.data_path.exists():
            return []

        mtime_ns = self.data_path.stat().st_mtime_ns
        with self.lock:
            if self.cached_catalog is not None and mtime_ns == self.cached_mtime_ns:
                return clone_json(self.cached_catalog)

            try:
                payload = json.loads(self.data_path.read_text())
            except (json.JSONDecodeError, OSError):
                payload = []

            catalog: list[dict[str, Any]] = []
            if isinstance(payload, list):
                for raw_source in payload:
                    if not isinstance(raw_source, dict):
                        continue
                    source_id = str(raw_source.get("id") or "").strip()
                    if not source_id:
                        continue
                    catalog.append(
                        {
                            "id": source_id,
                            "name": str(raw_source.get("name") or source_id),
                            "url": str(raw_source.get("url") or ""),
                            "category": str(raw_source.get("category") or "general"),
                            "license": str(raw_source.get("license") or "Unknown"),
                            "scope": str(raw_source.get("scope") or "Unknown"),
                            "freshness": str(raw_source.get("freshness") or "Unknown"),
                            "summary": str(raw_source.get("summary") or ""),
                            "tags": unique_labels([str(tag) for tag in raw_source.get("tags", [])]),
                        }
                    )

            self.cached_catalog = catalog
            self.cached_mtime_ns = mtime_ns
            return clone_json(self.cached_catalog)


class PlannerStore:
    def __init__(self, runtime_dir: Path) -> None:
        self.runtime_dir = runtime_dir
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()

    def _read_json(self, path: Path, fallback: Any) -> Any:
        if not path.exists():
            return clone_json(fallback)
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            return clone_json(fallback)

    def _write_json(self, path: Path, payload: Any) -> None:
        path.write_text(json.dumps(payload, indent=2, sort_keys=True))

    def read_memory(self) -> list[dict[str, Any]]:
        with self.lock:
            return self._read_json(MEMORY_PATH, [])

    def write_memory(self, entries: list[dict[str, Any]]) -> None:
        with self.lock:
            self._write_json(MEMORY_PATH, entries)

    def read_plan_cache(self) -> dict[str, Any]:
        with self.lock:
            return self._read_json(CACHE_PATH, {})

    def write_plan_cache(self, payload: dict[str, Any]) -> None:
        with self.lock:
            self._write_json(CACHE_PATH, payload)

    def read_source_registry(self) -> dict[str, Any]:
        with self.lock:
            return self._read_json(SOURCE_REGISTRY_PATH, {})

    def write_source_registry(self, payload: dict[str, Any]) -> None:
        with self.lock:
            self._write_json(SOURCE_REGISTRY_PATH, payload)

    def prune_memory(self, entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return sorted(entries, key=lambda item: item.get("lastSeenAtMs", 0), reverse=True)[:80]

    def prune_cache(self, payload: dict[str, Any]) -> dict[str, Any]:
        sorted_items = sorted(
            payload.items(),
            key=lambda item: item[1].get("lastRunAtMs", 0),
            reverse=True,
        )
        return dict(sorted_items[:50])

    def get_memory_stats(self) -> dict[str, int]:
        entries = self.read_memory()
        return {
            "count": len(entries),
            "confirmedCount": sum(1 for entry in entries if entry.get("confirmedCount", 0) > 0),
        }

    def get_source_registry_stats(self) -> dict[str, int]:
        registry = self.read_source_registry()
        entries = list(registry.values())
        return {
            "count": len(entries),
            "addedCount": sum(1 for entry in entries if entry.get("decision") == "add"),
            "sandboxCount": sum(1 for entry in entries if entry.get("decision") == "sandbox"),
            "ignoredCount": sum(1 for entry in entries if entry.get("decision") == "ignore"),
        }

    def score_token_overlap(self, left_tokens: list[str], right_tokens: list[str]) -> float:
        if not left_tokens or not right_tokens:
            return 0
        right_set = set(right_tokens)
        intersection_count = sum(1 for token in left_tokens if token in right_set)
        return intersection_count / max(len(left_tokens), len(right_tokens))

    def find_memory(self, normalized_prompt: str, prompt_tokens: list[str]) -> dict[str, Any] | None:
        entries = self.read_memory()
        exact_entry = next(
            (
                entry
                for entry in entries
                if entry.get("normalizedPrompt") == normalized_prompt
                and entry.get("confirmedCount", 0) > 0
            ),
            None,
        )
        if exact_entry:
            return {
                "mode": "exact",
                "score": 1,
                "entry": exact_entry,
                "semanticPlan": clone_json(exact_entry["semanticPlan"]),
            }

        similar_candidates = []
        for entry in entries:
            if entry.get("confirmedCount", 0) <= 0:
                continue
            score = self.score_token_overlap(prompt_tokens, entry.get("tokens", []))
            if score >= 0.6:
                similar_candidates.append((score, entry))

        if not similar_candidates:
            return None

        score, entry = sorted(similar_candidates, key=lambda item: item[0], reverse=True)[0]
        return {
            "mode": "similar",
            "score": score,
            "entry": entry,
            "semanticPlan": clone_json(entry["semanticPlan"]),
        }

    def review_source(
        self,
        source_id: str,
        action: str,
        prompt: str,
        source_name: str,
    ) -> dict[str, Any]:
        registry = self.read_source_registry()
        now_ms = int(time.time() * 1000)
        existing_entry = registry.get(source_id, {})
        entry = {
            "sourceId": source_id,
            "name": source_name,
            "decision": action,
            "normalizedPrompt": compact_text(prompt),
            "lastReviewedAtMs": now_ms,
            "reviewCount": int(existing_entry.get("reviewCount", 0)) + 1,
        }
        registry[source_id] = entry
        self.write_source_registry(registry)
        return entry

    def remember_outcome(self, prompt: str, plan: dict[str, Any], confirmed: bool) -> dict[str, Any] | None:
        normalized_prompt = compact_text(prompt)
        if not normalized_prompt:
            return None

        prompt_tokens = extract_prompt_tokens(normalized_prompt)
        entries = self.read_memory()
        now_ms = int(time.time() * 1000)
        existing_index = next(
            (
                index
                for index, entry in enumerate(entries)
                if entry.get("normalizedPrompt") == normalized_prompt
            ),
            -1,
        )
        existing_entry = entries[existing_index] if existing_index >= 0 else None
        next_entry = {
            "normalizedPrompt": normalized_prompt,
            "tokens": prompt_tokens,
            "semanticPlan": build_memory_semantic_plan(plan),
            "observedCount": (existing_entry or {}).get("observedCount", 0) + 1,
            "confirmedCount": (existing_entry or {}).get("confirmedCount", 0) + (1 if confirmed else 0),
            "lastSeenAtMs": now_ms,
            "lastConfirmedAtMs": now_ms if confirmed else (existing_entry or {}).get("lastConfirmedAtMs", 0),
        }

        if existing_index >= 0:
            entries[existing_index] = next_entry
        else:
            entries.append(next_entry)

        self.write_memory(self.prune_memory(entries))
        return next_entry

    def register_plan_execution(self, plan: dict[str, Any], reason: str) -> dict[str, Any]:
        canonical_plan = build_canonical_plan(plan)
        serialized_plan = stable_dumps(canonical_plan)
        plan_hash = hash_string(serialized_plan)
        now_ms = int(time.time() * 1000)
        cache = self.read_plan_cache()
        existing = cache.get(plan_hash)
        cache_age_ms = None if not existing else now_ms - existing.get("lastRunAtMs", now_ms)
        if existing and cache_age_ms is not None and cache_age_ms <= PLAN_CACHE_TTL_MS:
            status = "warm"
        elif existing:
            status = "stale"
        else:
            status = "cold"

        cache[plan_hash] = {
            "canonicalPlan": canonical_plan,
            "lastPrompt": plan.get("prompt", ""),
            "lastRunAtMs": now_ms,
            "reason": reason,
        }
        self.write_plan_cache(self.prune_cache(cache))
        return {
            "hash": plan_hash,
            "status": status,
            "ageMs": cache_age_ms,
            "lastRunAtMs": now_ms,
        }


def build_memory_semantic_plan(plan: dict[str, Any]) -> dict[str, Any]:
    filters = plan.get("filters", {})
    return {
        "filters": {
            "flags": sort_labels(list(filters.get("flags", []))),
            "ownerRegions": sort_labels(list(filters.get("ownerRegions", []))),
            "owners": sort_labels(list(filters.get("owners", []))),
            "ports": sort_labels(list(filters.get("ports", []))),
            "shipNames": sort_labels(list(filters.get("shipNames", []))),
            "statuses": sort_labels(list(filters.get("statuses", []))),
            "textTerms": sort_labels(list(filters.get("textTerms", []))),
            "types": sort_labels(list(filters.get("types", []))),
        },
        "layers": {
            "labels": bool(plan.get("layers", {}).get("labels")),
            "owners": bool(plan.get("layers", {}).get("owners")),
            "ports": bool(plan.get("layers", {}).get("ports")),
            "routes": bool(plan.get("layers", {}).get("routes")),
        },
        "relations": [
            {
                "distanceKm": relation.get("distanceKm"),
                "type": relation.get("type"),
            }
            for relation in plan.get("relations", [])
        ],
    }


def build_canonical_plan(plan: dict[str, Any]) -> dict[str, Any]:
    filters = plan.get("filters", {})
    return {
        "filters": {
            "flags": sort_labels(list(filters.get("flags", []))),
            "ownerRegions": sort_labels(list(filters.get("ownerRegions", []))),
            "owners": sort_labels(list(filters.get("owners", []))),
            "ports": sort_labels(list(filters.get("ports", []))),
            "shipNames": sort_labels(list(filters.get("shipNames", []))),
            "statuses": sort_labels(list(filters.get("statuses", []))),
            "textTerms": sort_labels(list(filters.get("textTerms", []))),
            "types": sort_labels(list(filters.get("types", []))),
        },
        "layers": {
            "labels": bool(plan.get("layers", {}).get("labels")),
            "owners": bool(plan.get("layers", {}).get("owners")),
            "ports": bool(plan.get("layers", {}).get("ports")),
            "routes": bool(plan.get("layers", {}).get("routes")),
        },
        "locationScope": {
            "boundsKey": plan.get("locationScope", {}).get("boundsKey", "world"),
            "mode": plan.get("locationScope", {}).get("mode", "world"),
        },
        "relations": [
            {
                "distanceKm": relation.get("distanceKm"),
                "type": relation.get("type"),
            }
            for relation in plan.get("relations", [])
        ],
    }


def merge_semantic_plans(memory_plan: dict[str, Any], heuristic_plan: dict[str, Any]) -> dict[str, Any]:
    def pick_values(memory_values: list[str], heuristic_values: list[str]) -> list[str]:
        return unique_labels(heuristic_values) if heuristic_values else unique_labels(memory_values)

    return {
        "filters": {
            "flags": pick_values(memory_plan["filters"]["flags"], heuristic_plan["filters"]["flags"]),
            "ownerRegions": pick_values(
                memory_plan["filters"]["ownerRegions"],
                heuristic_plan["filters"]["ownerRegions"],
            ),
            "owners": pick_values(memory_plan["filters"]["owners"], heuristic_plan["filters"]["owners"]),
            "ports": pick_values(memory_plan["filters"]["ports"], heuristic_plan["filters"]["ports"]),
            "shipNames": pick_values(
                memory_plan["filters"]["shipNames"],
                heuristic_plan["filters"]["shipNames"],
            ),
            "statuses": pick_values(
                memory_plan["filters"]["statuses"],
                heuristic_plan["filters"]["statuses"],
            ),
            "textTerms": pick_values(
                memory_plan["filters"]["textTerms"],
                heuristic_plan["filters"]["textTerms"],
            ),
            "types": pick_values(memory_plan["filters"]["types"], heuristic_plan["filters"]["types"]),
        },
        "layers": dict(heuristic_plan["layers"]),
        "relations": heuristic_plan["relations"] or memory_plan["relations"],
    }


def normalize_location_scope(payload: Any) -> dict[str, str]:
    if not isinstance(payload, dict):
        return {"mode": "world", "label": "Global view", "boundsKey": "world"}
    mode = "viewport" if payload.get("mode") == "viewport" else "world"
    return {
        "mode": mode,
        "label": str(payload.get("label") or ("Current view" if mode == "viewport" else "Global view")),
        "boundsKey": str(payload.get("boundsKey") or ("world" if mode != "viewport" else "viewport")),
    }


def normalize_layers(payload: Any) -> dict[str, bool]:
    result = dict(DEFAULT_LAYERS)
    if not isinstance(payload, dict):
        return result
    for key in DEFAULT_LAYERS:
        if key in payload:
            result[key] = bool(payload[key])
    return result


def build_semantic_filters(prompt: str, catalog: dict[str, list[str]]) -> dict[str, list[str]]:
    types = match_alias_map(prompt, TYPE_QUERY_ALIASES)
    statuses = match_alias_map(prompt, STATUS_QUERY_ALIASES)
    owner_regions = match_alias_map(prompt, REGION_QUERY_ALIASES)
    ports = match_dynamic_labels(prompt, catalog["ports"])
    owners = match_dynamic_labels(prompt, catalog["owners"]) if has_owner_filter_context(prompt) else []
    flags = match_dynamic_labels(prompt, catalog["flags"]) if has_flag_filter_context(prompt) else []
    ship_names = match_dynamic_labels(prompt, catalog["shipNames"])
    matched_words = collect_matched_words(
        [types, statuses, owner_regions, ports, owners, flags, ship_names]
    )
    return {
        "types": types,
        "statuses": statuses,
        "ownerRegions": owner_regions,
        "ports": ports,
        "owners": owners,
        "flags": flags,
        "shipNames": ship_names,
        "textTerms": extract_search_terms(prompt, matched_words),
    }


def build_source_search_document(source: dict[str, Any]) -> str:
    return " ".join(
        [
            str(source.get("name") or ""),
            str(source.get("category") or ""),
            str(source.get("summary") or ""),
            str(source.get("scope") or ""),
            " ".join(str(tag) for tag in source.get("tags", [])),
        ]
    )


def score_source_candidate(prompt: str, prompt_tokens: list[str], source: dict[str, Any]) -> tuple[float, list[str]]:
    source_tokens = set(extract_prompt_tokens(compact_text(build_source_search_document(source))))
    matched_terms = sort_labels([token for token in set(prompt_tokens) if token in source_tokens])
    score = float(len(matched_terms))

    if prompt_has_phrase(prompt, source.get("name", "")):
        score += 3.0

    if prompt_has_phrase(prompt, source.get("category", "")):
        score += 1.5

    for tag in source.get("tags", []):
        if prompt_has_phrase(prompt, tag):
            score += 2.0

    category = compact_text(source.get("category", ""))
    if category == "geocoding" and prompt_tokens:
        score += 0.5
    if category == "places" and any(
        prompt_has_phrase(prompt, phrase)
        for phrase in ("restaurant", "store", "church", "churches", "near", "school", "hospital")
    ):
        score += 1.0
    if category == "entities" and (
        has_owner_filter_context(prompt)
        or any(
            prompt_has_phrase(prompt, phrase)
            for phrase in ("church", "company", "companies", "landmark", "entity")
        )
    ):
        score += 0.75

    return score, matched_terms


def build_source_reason(source: dict[str, Any], matched_terms: list[str]) -> str:
    if matched_terms:
        return f"Matched {', '.join(matched_terms[:3])} against {source.get('category', 'general')} coverage."
    return f"Useful {source.get('category', 'general')} source for {source.get('scope', 'broad')} map lookups."


def decorate_source_suggestion(
    source: dict[str, Any],
    registry_entry: dict[str, Any],
    reason: str,
    score: float,
) -> dict[str, Any]:
    return {
        **clone_json(source),
        "reason": reason or build_source_reason(source, []),
        "score": score,
        "decision": str(registry_entry.get("decision") or ""),
        "reviewCount": int(registry_entry.get("reviewCount", 0)),
        "reviewedAtMs": int(registry_entry.get("lastReviewedAtMs", 0) or 0),
    }


def suggest_source_candidates(
    prompt: str,
    source_catalog: list[dict[str, Any]],
    source_registry: dict[str, Any],
    limit: int = 3,
) -> list[dict[str, Any]]:
    if not prompt:
        return []

    prompt_tokens = extract_prompt_tokens(prompt)
    candidates: list[dict[str, Any]] = []
    for source in source_catalog:
        source_id = str(source.get("id") or "")
        if not source_id:
            continue
        registry_entry = source_registry.get(source_id, {})
        decision = registry_entry.get("decision")
        if decision == "ignore":
            continue

        score, matched_terms = score_source_candidate(prompt, prompt_tokens, source)
        if decision == "add":
            score += 0.3
        elif decision == "sandbox":
            score += 0.15

        if score <= 0:
            continue

        candidates.append(
            {
                "sourceId": source_id,
                "score": round(score, 2),
                "reason": build_source_reason(source, matched_terms),
                "matchedTerms": matched_terms[:5],
            }
        )

    candidates.sort(key=lambda item: (-item["score"], item["sourceId"]))
    return candidates[:limit]


def hydrate_source_suggestions(
    raw_suggestions: Any,
    source_catalog: list[dict[str, Any]],
    source_registry: dict[str, Any],
    limit: int = 3,
) -> list[dict[str, Any]]:
    catalog_by_id = {
        str(source.get("id") or ""): clone_json(source)
        for source in source_catalog
        if str(source.get("id") or "")
    }
    suggestions_payload = raw_suggestions
    if isinstance(raw_suggestions, dict):
        suggestions_payload = raw_suggestions.get("suggestions", [])

    hydrated: list[dict[str, Any]] = []
    seen: set[str] = set()
    if not isinstance(suggestions_payload, list):
        return hydrated

    for raw_suggestion in suggestions_payload:
        if not isinstance(raw_suggestion, dict):
            continue
        source_id = str(raw_suggestion.get("sourceId") or raw_suggestion.get("id") or "").strip()
        if not source_id or source_id in seen or source_id not in catalog_by_id:
            continue
        registry_entry = source_registry.get(source_id, {})
        if registry_entry.get("decision") == "ignore":
            continue

        source = catalog_by_id[source_id]
        try:
            score = float(raw_suggestion.get("score") or 0)
        except (TypeError, ValueError):
            score = 0
        hydrated.append(
            decorate_source_suggestion(
                source,
                registry_entry,
                str(raw_suggestion.get("reason") or build_source_reason(source, [])),
                score,
            )
        )
        seen.add(source_id)
        if len(hydrated) >= limit:
            break

    return hydrated


class FleetAtlasSupervisor:
    def __init__(self, worker_command: str = "", worker_timeout_s: float = 30.0) -> None:
        self.catalog_provider = CatalogProvider(DATA_PATH)
        self.source_catalog_provider = SourceCatalogProvider(SOURCE_CATALOG_PATH)
        self.store = PlannerStore(RUNTIME_DIR)
        self.worker_adapter = WorkerAdapter(worker_command, worker_timeout_s)

    def _run_worker(self, name: str, callback, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        started_at = time.perf_counter()
        source = "inline"
        fallback_error = ""

        if payload and self.worker_adapter.mode == "subprocess":
            try:
                summary, data = self.worker_adapter.run(name, payload)
                source = "subprocess"
            except Exception as error:  # noqa: BLE001
                summary, data = callback()
                source = "fallback-inline"
                fallback_error = str(error)
        else:
            summary, data = callback()

        if fallback_error:
            summary = f"{summary} Fallback after worker error: {fallback_error}"

        return {
            "worker": name,
            "status": "completed",
            "source": source,
            "durationMs": round((time.perf_counter() - started_at) * 1000, 2),
            "summary": summary,
            "data": data,
        }

    def health(self) -> dict[str, Any]:
        return {
            "ok": True,
            "planner": "local-supervisor",
            "workerMode": self.worker_adapter.mode,
            "workerCommand": self.worker_adapter.command,
            "memory": self.store.get_memory_stats(),
            "sourceRegistry": self.store.get_source_registry_stats(),
            "dataSource": str(DATA_PATH.relative_to(PROJECT_ROOT)),
            "sourceCatalog": str(SOURCE_CATALOG_PATH.relative_to(PROJECT_ROOT)),
        }

    def plan_query(self, payload: dict[str, Any]) -> dict[str, Any]:
        prompt = str(payload.get("prompt") or "").strip()
        normalized_prompt = compact_text(prompt)
        prompt_tokens = extract_prompt_tokens(normalized_prompt)
        catalog = self.catalog_provider.get_catalog()
        source_catalog = self.source_catalog_provider.get_catalog()
        source_registry = self.store.read_source_registry()
        location_scope = normalize_location_scope(payload.get("locationScope"))
        current_layers = normalize_layers(payload.get("currentLayers"))

        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                "memory_lookup": executor.submit(
                    self._run_worker,
                    "memory_lookup",
                    lambda: self._memory_worker(normalized_prompt, prompt_tokens),
                ),
                "entity_parse": executor.submit(
                    self._run_worker,
                    "entity_parse",
                    lambda: self._entity_worker(normalized_prompt, catalog),
                    {
                        "prompt": normalized_prompt,
                        "catalog": catalog,
                    },
                ),
                "relation_parse": executor.submit(
                    self._run_worker,
                    "relation_parse",
                    lambda: self._relation_worker(normalized_prompt),
                    {
                        "prompt": normalized_prompt,
                    },
                ),
                "layer_inference": executor.submit(
                    self._run_worker,
                    "layer_inference",
                    lambda: self._layer_worker(normalized_prompt, current_layers),
                    {
                        "prompt": normalized_prompt,
                        "currentLayers": current_layers,
                    },
                ),
                "source_scout": executor.submit(
                    self._run_worker,
                    "source_scout",
                    lambda: self._source_scout_worker(normalized_prompt, source_catalog, source_registry),
                    {
                        "prompt": normalized_prompt,
                        "sourceCatalog": source_catalog,
                        "sourceRegistry": source_registry,
                    },
                ),
            }
            worker_results = {name: future.result() for name, future in futures.items()}

        memory_match = worker_results["memory_lookup"]["data"]
        heuristic_plan = {
            "filters": worker_results["entity_parse"]["data"],
            "relations": worker_results["relation_parse"]["data"],
            "layers": worker_results["layer_inference"]["data"],
        }

        semantic_plan = heuristic_plan
        planner_source = "heuristic"
        if memory_match:
            if memory_match["mode"] == "exact":
                semantic_plan = memory_match["semanticPlan"]
                planner_source = "memory-exact"
            else:
                semantic_plan = merge_semantic_plans(memory_match["semanticPlan"], heuristic_plan)
                planner_source = "memory-assisted"

        plan = {
            "prompt": prompt,
            "normalizedPrompt": normalized_prompt,
            "locationScope": location_scope,
            "filters": semantic_plan["filters"],
            "relations": semantic_plan["relations"],
            "layers": semantic_plan["layers"],
        }

        cache_meta = self.store.register_plan_execution(plan, "supervisor")
        self.store.remember_outcome(prompt, plan, confirmed=False)
        memory_stats = self.store.get_memory_stats()
        source_suggestions = hydrate_source_suggestions(
            worker_results["source_scout"]["data"],
            source_catalog,
            source_registry,
        )
        safe_memory_match = None
        if memory_match:
            safe_memory_match = {
                "mode": memory_match["mode"],
                "score": memory_match["score"],
                "prompt": memory_match["entry"]["normalizedPrompt"],
            }

        return {
            "plan": plan,
            "plannerSource": planner_source,
            "memoryMatch": safe_memory_match,
            "cache": cache_meta,
            "memory": memory_stats,
            "sourceRegistry": self.store.get_source_registry_stats(),
            "sourceSuggestions": source_suggestions,
            "workers": [
                {
                    "worker": result["worker"],
                    "status": result["status"],
                    "source": result["source"],
                    "durationMs": result["durationMs"],
                    "summary": result["summary"],
                }
                for result in worker_results.values()
            ],
        }

    def confirm_plan(self, payload: dict[str, Any]) -> dict[str, Any]:
        prompt = str(payload.get("prompt") or "").strip()
        plan = self._normalize_confirm_plan(payload.get("plan"), prompt)
        entry = self.store.remember_outcome(prompt, plan, confirmed=True)
        return {
            "ok": True,
            "memory": self.store.get_memory_stats(),
            "entry": None if not entry else {
                "normalizedPrompt": entry["normalizedPrompt"],
                "confirmedCount": entry["confirmedCount"],
                "observedCount": entry["observedCount"],
            },
        }

    def review_source(self, payload: dict[str, Any]) -> dict[str, Any]:
        source_id = str(payload.get("sourceId") or "").strip()
        action = normalize_source_action(payload.get("action"))
        prompt = str(payload.get("prompt") or "").strip()
        source_catalog = self.source_catalog_provider.get_catalog()
        source = next((item for item in source_catalog if item.get("id") == source_id), None)
        if not source:
            raise ValueError(f"Unknown sourceId: {source_id}")

        entry = self.store.review_source(source_id, action, prompt, str(source.get("name") or source_id))
        registry_entry = self.store.read_source_registry().get(source_id, {})
        return {
            "ok": True,
            "entry": entry,
            "registry": self.store.get_source_registry_stats(),
            "source": decorate_source_suggestion(
                source,
                registry_entry,
                str(source.get("summary") or ""),
                0,
            ),
        }

    def _normalize_confirm_plan(self, payload: Any, prompt: str) -> dict[str, Any]:
        plan = payload if isinstance(payload, dict) else {}
        filters = plan.get("filters", {})
        return {
            "prompt": prompt,
            "normalizedPrompt": compact_text(prompt),
            "locationScope": normalize_location_scope(plan.get("locationScope")),
            "filters": {
                "types": unique_labels(list(filters.get("types", []))),
                "statuses": unique_labels(list(filters.get("statuses", []))),
                "ownerRegions": unique_labels(list(filters.get("ownerRegions", []))),
                "ports": unique_labels(list(filters.get("ports", []))),
                "owners": unique_labels(list(filters.get("owners", []))),
                "flags": unique_labels(list(filters.get("flags", []))),
                "shipNames": unique_labels(list(filters.get("shipNames", []))),
                "textTerms": unique_labels(list(filters.get("textTerms", []))),
            },
            "relations": [
                {
                    "type": relation.get("type"),
                    "distanceKm": relation.get("distanceKm"),
                }
                for relation in plan.get("relations", [])
                if isinstance(relation, dict)
            ],
            "layers": normalize_layers(plan.get("layers")),
        }

    def _memory_worker(self, normalized_prompt: str, prompt_tokens: list[str]) -> tuple[str, Any]:
        memory_match = self.store.find_memory(normalized_prompt, prompt_tokens)
        if not memory_match:
            return ("No remembered prompt matched this query.", None)
        if memory_match["mode"] == "exact":
            return (
                f"Exact remembered prompt matched '{memory_match['entry']['normalizedPrompt']}'.",
                memory_match,
            )
        return (
            f"Confirmed similar prompt matched '{memory_match['entry']['normalizedPrompt']}'.",
            memory_match,
        )

    def _entity_worker(self, normalized_prompt: str, catalog: dict[str, list[str]]) -> tuple[str, Any]:
        filters = build_semantic_filters(normalized_prompt, catalog)
        populated_groups = sum(1 for values in filters.values() if values)
        return (f"Resolved {populated_groups} populated filter groups.", filters)

    def _relation_worker(self, normalized_prompt: str) -> tuple[str, Any]:
        relations = extract_relations(normalized_prompt)
        if not relations:
            return ("No spatial relation inferred.", [])
        return (f"Resolved {len(relations)} spatial relation.", relations)

    def _layer_worker(self, normalized_prompt: str, current_layers: dict[str, bool]) -> tuple[str, Any]:
        layers = derive_layers_from_prompt(normalized_prompt, current_layers)
        enabled_count = sum(1 for enabled in layers.values() if enabled)
        return (f"{enabled_count} layers enabled after prompt inference.", layers)

    def _source_scout_worker(
        self,
        normalized_prompt: str,
        source_catalog: list[dict[str, Any]],
        source_registry: dict[str, Any],
    ) -> tuple[str, Any]:
        suggestions = suggest_source_candidates(normalized_prompt, source_catalog, source_registry)
        if not suggestions:
            return ("No relevant public source suggestions for this prompt.", [])
        return (f"Suggested {len(suggestions)} source candidates for user review.", suggestions)


class FleetAtlasHandler(SimpleHTTPRequestHandler):
    supervisor = FleetAtlasSupervisor()

    def __init__(self, *args, directory: str | None = None, **kwargs) -> None:
        super().__init__(*args, directory=str(PROJECT_ROOT), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        super().end_headers()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/health":
            self._send_json(self.supervisor.health())
            return
        self.path = parsed.path
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path not in {"/api/query-plan", "/api/confirm-plan", "/api/source-review"}:
            self.send_error(404, "Unknown API endpoint")
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400, "Invalid Content-Length header")
            return

        try:
            raw_body = self.rfile.read(content_length) if content_length else b"{}"
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_error(400, "Request body must be valid JSON")
            return

        try:
            if parsed.path == "/api/query-plan":
                response = self.supervisor.plan_query(payload)
            elif parsed.path == "/api/source-review":
                response = self.supervisor.review_source(payload)
            else:
                response = self.supervisor.confirm_plan(payload)
        except Exception as error:  # noqa: BLE001
            self._send_json(
                {
                    "ok": False,
                    "error": str(error),
                },
                status=500,
            )
            return

        self._send_json(response)

    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Fleet Atlas with a local supervisor API.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=4173, type=int)
    parser.add_argument(
        "--worker-command",
        default=os.environ.get("FLEET_ATLAS_WORKER_COMMAND", ""),
        help="Command used to spawn terminal workers for entity_parse/relation_parse/layer_inference.",
    )
    parser.add_argument(
        "--worker-timeout-s",
        default=30.0,
        type=float,
        help="Timeout for spawned worker commands.",
    )
    args = parser.parse_args()

    FleetAtlasHandler.supervisor = FleetAtlasSupervisor(
        worker_command=args.worker_command,
        worker_timeout_s=args.worker_timeout_s,
    )
    handler = partial(FleetAtlasHandler, directory=str(PROJECT_ROOT))
    with ThreadingHTTPServer((args.host, args.port), handler) as server:
        print(f"Fleet Atlas serving on http://{args.host}:{args.port}")
        server.serve_forever()


if __name__ == "__main__":
    main()
