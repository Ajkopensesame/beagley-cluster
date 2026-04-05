# Fleet Atlas

Fleet Atlas is a standalone static prototype for a map-first vessel intelligence product. It is built around the interaction you described:

- use the search bar as the creator,
- let the current map focus become the location scope,
- show a canonical query plan instead of relying on raw prompt text,
- keep ownership, origin, destination, and voyage status visible without cluttering the map.

## What is in this prototype

- Map-first search composer over the live viewport
- Canonical query planner that converts prompts into structured filters
- Viewport-as-location mode that reruns the query when the map focus changes
- Semantic plan cache stored in local storage so repeated prompts reuse meaning, not wording
- Planner memory that records prompts automatically but only reuses confirmed meanings
- Suggested public-source queue with `add`, `ignore`, and `sandbox` review actions
- Filters for vessel class, status, and owner region as secondary controls
- Confirmed memory captures active manual narrowing so the system can remember the accepted meaning
- Toggleable route lines, ports, ship labels, and owner tags
- Selectable vessel detail panel with owner, flag, speed, ETA, coordinates, and voyage lane
- Freshness panel that separates planner cache from data freshness
- Demo dataset in `data/mock-vessels.json`
- Curated public-source catalog in `data/source-catalog.json`
- A live-provider hook through `config.js`

## Query model

The browser planner currently builds a canonical plan shaped like this:

```json
{
  "locationScope": {
    "mode": "viewport",
    "boundsKey": "-14.4:111.2:8.8:155.6"
  },
  "filters": {
    "types": ["Tanker"],
    "statuses": ["Approaching port"],
    "ownerRegions": [],
    "ports": ["Singapore"],
    "owners": [],
    "flags": [],
    "shipNames": [],
    "textTerms": []
  },
  "relations": [],
  "layers": {
    "routes": true,
    "ports": true,
    "labels": true,
    "owners": true
  }
}
```

That plan is what gets cached. The raw prompt is not the cache key.

## Freshness model

The prototype demonstrates the hybrid model we discussed:

- semantic plan cache: short TTL, keyed by normalized query meaning
- vessel positions: short TTL
- ownership / registry facts: longer TTL
- port / viewport reference: longest TTL unless the viewport is live

This lets repeated prompts reuse the planning work while still re-evaluating the data against the current map focus.

## Planner memory

The frontend now has two memory tiers:

- observed memory: every non-empty prompt is recorded so the system can track repeated queries without trusting them yet
- confirmed memory: pressing `Remember meaning` promotes the current accepted plan, including active manual narrowing, and only confirmed memory is reused for future planning

Similar prompt reuse is conservative: prompt-specific filters win, and confirmed memory fills gaps instead of broadening the meaning by unioning unrelated filters.

That means the system can improve with use without treating every raw query as trustworthy training data.

## Source discovery loop

The supervisor now scouts relevant public datasets and APIs per query, then leaves approval to the user.

- `source_scout` suggests up to 3 sources from `data/source-catalog.json`
- the sidebar exposes `Add`, `Sandbox`, and `Ignore`
- reviews are persisted in `runtime/source-registry.json`
- ignored sources stop being suggested on later queries

This keeps source discovery adaptive without auto-trusting whatever a model finds.

## Local preview

From the repo root:

```bash
python3 projects/fleet-atlas/server.py --port 4173
```

Then open `http://localhost:4173`.

That server does two things at once:

- serves the static frontend
- exposes a local supervisor API at `/api`

If `/api/health` is available, the frontend auto-detects it and sends prompt planning plus confirmation there. If not, the app falls back to the browser-only planner.

To force terminal-spawned worker subprocesses instead of inline workers:

```bash
python3 projects/fleet-atlas/server.py --port 4173 \
  --worker-command "python3 projects/fleet-atlas/worker_agent.py"
```

To use the Ollama-backed worker on this machine:

```bash
python3 projects/fleet-atlas/server.py --port 4173 \
  --worker-command "python3 projects/fleet-atlas/worker_ollama.py --model qwen2.5-coder:7b-instruct"
```

## Live AIS / vessel data hook

`config.js` exposes the runtime settings:

```js
window.FLEET_ATLAS_CONFIG = {
  dataMode: "demo",
  liveEndpoint: "",
  liveHeaders: {},
  plannerApiBase: "",
  autoDetectPlannerApi: true,
  defaultCenter: [20, 10],
  defaultZoom: 2.25
};
```

Set `dataMode` to `"live"` and provide `liveEndpoint` if you want the app to fetch a real vessel feed.

`plannerApiBase` can stay empty if you use `server.py`, because the frontend will auto-detect `/api`. Set it explicitly only if you want to point the frontend at a different supervisor host.

The frontend accepts any of these payload shapes from the live endpoint:

- `[{ ...vessel }]`
- `{ "vessels": [{ ...vessel }] }`
- `{ "data": [{ ...vessel }] }`
- `{ "results": [{ ...vessel }] }`

The normalizer already understands common field aliases such as:

- `lat` / `latitude`
- `lng` / `lon` / `longitude`
- `type` / `shipType`
- `status` / `navStatus`
- `owner` / `registeredOwner`
- `originPort` / `destinationPort`

For best results, keep the live payload close to the demo shape in `data/mock-vessels.json`.

If you later move this into a real backend, the next step is to keep the same canonical plan shape and resolve it server-side against fresh source caches rather than changing the frontend contract.

## Supervisor API

The local Python supervisor in [server.py](/Users/joshkomant/projects/beagley-cluster/projects/fleet-atlas/server.py) currently exposes:

- `GET /api/health`
- `POST /api/query-plan`
- `POST /api/confirm-plan`
- `POST /api/source-review`

`/api/query-plan` runs a small worker graph in parallel:

- `memory_lookup`
- `entity_parse`
- `relation_parse`
- `layer_inference`
- `source_scout`

`memory_lookup` stays in-process because it owns the runtime memory store. The other workers can run inline or as spawned subprocesses through `--worker-command`.

[worker_agent.py](/Users/joshkomant/projects/beagley-cluster/projects/fleet-atlas/worker_agent.py) is the reference subprocess worker. It speaks a simple stdin/stdout JSON protocol, so you can replace it later with a local LLM CLI wrapper without changing the supervisor API.

[worker_ollama.py](/Users/joshkomant/projects/beagley-cluster/projects/fleet-atlas/worker_ollama.py) is the Ollama-backed version of that same worker protocol. It uses `qwen2.5-coder:7b-instruct` by default and keeps deterministic guardrails around the model output so the planner does not over-select labels from the catalog.

`/api/source-review` accepts:

```json
{
  "sourceId": "osm-overpass",
  "action": "add",
  "prompt": "show kfc near churches in brisbane"
}
```

Valid actions are `add`, `sandbox`, and `ignore`.

That gives you both paths:

- `worker_agent.py` for deterministic subprocess testing
- `worker_ollama.py` for local LLM-backed subprocess workers

## Deployment

A GitHub Pages workflow is included at `.github/workflows/deploy-fleet-atlas-pages.yml`.

It publishes the contents of `projects/fleet-atlas/` whenever that folder changes on the default branch, or when the workflow is triggered manually.
