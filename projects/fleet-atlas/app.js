const DEFAULT_CONFIG = {
  dataMode: "demo",
  liveEndpoint: "",
  liveHeaders: {},
  plannerApiBase: "",
  autoDetectPlannerApi: true,
  defaultCenter: [20, 10],
  defaultZoom: 2.25
};

const APP_CONFIG = {
  ...DEFAULT_CONFIG,
  ...(window.FLEET_ATLAS_CONFIG || {})
};

const TYPE_COLORS = {
  Container: "#4ad1c8",
  Tanker: "#f0765e",
  LNG: "#86c9ff",
  "Bulk Carrier": "#f5be6a",
  "Ro-Ro": "#f0d878",
  Passenger: "#bddf62",
  Fishing: "#78e0bf",
  Research: "#8bc5ff"
};

const STATUS_CLASSNAMES = {
  "In transit": "isTransit",
  "Approaching port": "isApproach",
  Loading: "isApproach",
  "Survey operations": "isApproach",
  "At anchor": "isHold",
  "Weather hold": "isHold"
};

const TYPE_QUERY_ALIASES = {
  Container: ["container", "containers", "boxship", "boxships"],
  Tanker: ["tanker", "tankers", "oil tanker", "product tanker"],
  LNG: ["lng", "lng carrier", "lng carriers", "gas carrier", "gas carriers"],
  "Bulk Carrier": ["bulk", "bulk carrier", "bulk carriers", "ore carrier", "ore carriers"],
  "Ro-Ro": ["ro-ro", "ro ro", "roro", "vehicle carrier", "vehicle carriers"],
  Passenger: ["passenger", "cruise", "cruise ship", "ferry", "ferries"],
  Fishing: ["fishing", "trawler", "trawlers"],
  Research: ["research", "survey vessel", "survey", "science vessel"]
};

const STATUS_QUERY_ALIASES = {
  "In transit": ["in transit", "underway", "moving", "en route"],
  "Approaching port": ["approaching port", "arriving", "approach"],
  Loading: ["loading", "loading cargo", "at berth"],
  "Survey operations": ["survey operations", "research operations", "on survey"],
  "At anchor": ["at anchor", "anchored", "anchor"],
  "Weather hold": ["weather hold", "weather delayed", "delayed by weather"]
};

const REGION_QUERY_ALIASES = {
  "Asia-Pacific": ["asia pacific", "asia-pacific", "apac", "australia", "new zealand"],
  Europe: ["europe", "european", "eu"],
  "North America": ["north america", "north american", "usa", "united states", "canada"],
  "South America": ["south america", "south american", "brazil", "chile"],
  "Middle East": ["middle east", "gulf", "uae", "saudi", "qatar"],
  Africa: ["africa", "african", "liberia"]
};

const LAYER_QUERY_HINTS = {
  routes: {
    enable: ["route", "routes", "voyage", "voyages", "corridor", "corridors"],
    disable: ["hide routes", "no routes", "without routes"]
  },
  ports: {
    enable: ["port", "ports", "origin", "destination"],
    disable: ["hide ports", "no ports", "without ports"]
  },
  labels: {
    enable: ["label", "labels", "names"],
    disable: ["hide labels", "no labels", "without labels"]
  },
  owners: {
    enable: ["owner", "owners", "ownership"],
    disable: ["hide owners", "no owners", "without owners"]
  }
};

const STOPWORDS = new Set([
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
  "within"
]);

const PLAN_CACHE_STORAGE_KEY = "fleet-atlas-plan-cache-v2";
const PLANNER_MEMORY_STORAGE_KEY = "fleet-atlas-planner-memory-v1";
const PLAN_CACHE_TTL_MS = 5 * 60 * 1000;
const POSITION_TTL_MS = 2 * 60 * 1000;
const OWNERSHIP_TTL_MS = 24 * 60 * 60 * 1000;
const PORT_REFERENCE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

const SELECTORS = {
  dataModeLabel: document.getElementById("dataModeLabel"),
  visibleTotal: document.getElementById("visibleTotal"),
  inMotionTotal: document.getElementById("inMotionTotal"),
  ownerTotal: document.getElementById("ownerTotal"),
  avgSpeed: document.getElementById("avgSpeed"),
  queryForm: document.getElementById("queryForm"),
  queryInput: document.getElementById("queryInput"),
  clearQueryButton: document.getElementById("clearQueryButton"),
  useViewportInput: document.getElementById("useViewportInput"),
  runStatus: document.getElementById("runStatus"),
  planSummary: document.getElementById("planSummary"),
  planChips: document.getElementById("planChips"),
  planLearning: document.getElementById("planLearning"),
  planCacheBadge: document.getElementById("planCacheBadge"),
  rememberPlanButton: document.getElementById("rememberPlanButton"),
  plannerMode: document.getElementById("plannerMode"),
  sourceFreshness: document.getElementById("sourceFreshness"),
  workerModeBadge: document.getElementById("workerModeBadge"),
  workerRuntime: document.getElementById("workerRuntime"),
  workerTrace: document.getElementById("workerTrace"),
  sourceScoutStatus: document.getElementById("sourceScoutStatus"),
  sourceSuggestions: document.getElementById("sourceSuggestions"),
  viewportLabel: document.getElementById("viewportLabel"),
  typeFilters: document.getElementById("typeFilters"),
  statusFilters: document.getElementById("statusFilters"),
  regionFilters: document.getElementById("regionFilters"),
  toggleRoutes: document.getElementById("toggleRoutes"),
  togglePorts: document.getElementById("togglePorts"),
  toggleLabels: document.getElementById("toggleLabels"),
  toggleOwners: document.getElementById("toggleOwners"),
  feedCount: document.getElementById("feedCount"),
  vesselList: document.getElementById("vesselList"),
  detailCard: document.getElementById("detailCard"),
  resetViewButton: document.getElementById("resetViewButton"),
  exampleButtons: Array.from(document.querySelectorAll("[data-example-query]"))
};

const state = {
  vessels: [],
  catalog: {
    ports: [],
    owners: [],
    flags: [],
    shipNames: []
  },
  filterCatalog: {
    types: [],
    statuses: [],
    ownerRegions: []
  },
  selectedId: null,
  dataLabel: "Demo feed",
  dataLoadedAtMs: 0,
  hasBooted: false,
  plannerApiBase: "",
  plannerHealth: null,
  sourceSuggestions: [],
  sourceReviewState: {},
  nextQueryRunId: 0,
  skipNextViewportRun: false,
  viewport: {
    bounds: null,
    boundsKey: "world",
    label: "World view"
  },
  plan: null,
  planMeta: {
    hash: "",
    cacheStatus: "cold",
    cacheAgeMs: null,
    lastRunAtMs: 0,
    reason: "boot",
    plannerSource: "heuristic",
    plannerRuntime: "browser",
    memoryPrompt: "",
    memoryScore: null,
    memoryCount: 0,
    workerCount: 0,
    workers: [],
    confirmedJustNow: false
  },
  filters: {
    types: new Set(),
    statuses: new Set(),
    ownerRegions: new Set(),
    layers: {
      routes: true,
      ports: true,
      labels: true,
      owners: false
    }
  }
};

const dateFormatter = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit"
});

const map = L.map("map", {
  zoomSnap: 0.25,
  minZoom: 1.75,
  maxZoom: 7,
  worldCopyJump: true
}).setView(APP_CONFIG.defaultCenter, APP_CONFIG.defaultZoom);

L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
  attribution: "&copy; OpenStreetMap contributors &copy; CARTO"
}).addTo(map);

const routeLayer = L.layerGroup().addTo(map);
const portLayer = L.layerGroup().addTo(map);
const labelLayer = L.layerGroup().addTo(map);
const ownerLayer = L.layerGroup().addTo(map);
const vesselLayer = L.layerGroup().addTo(map);
const scopeLayer = L.layerGroup().addTo(map);

function uniqueLabels(values) {
  return Array.from(new Set(values.filter(Boolean)));
}

function sortLabels(values) {
  return [...values].sort((left, right) => left.localeCompare(right));
}

function getTypeColor(type) {
  return TYPE_COLORS[type] || "#9ec0cf";
}

function statusClass(status) {
  return STATUS_CLASSNAMES[status] || "isTransit";
}

function parseCoordinate(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalisePort(port, fallbackName, fallbackLat, fallbackLng) {
  if (!port && !fallbackName && fallbackLat == null && fallbackLng == null) {
    return null;
  }

  const normalised = typeof port === "string" ? { name: port } : { ...(port || {}) };
  const lat = parseCoordinate(normalised.lat ?? normalised.latitude ?? fallbackLat);
  const lng = parseCoordinate(
    normalised.lng ?? normalised.lon ?? normalised.longitude ?? fallbackLng
  );

  return {
    name: normalised.name || fallbackName || "Unknown",
    lat,
    lng
  };
}

function normaliseVessel(rawVessel, index) {
  const lat = parseCoordinate(
    rawVessel.lat ?? rawVessel.latitude ?? rawVessel.position?.lat ?? rawVessel.location?.lat
  );
  const lng = parseCoordinate(
    rawVessel.lng ??
      rawVessel.lon ??
      rawVessel.longitude ??
      rawVessel.position?.lng ??
      rawVessel.position?.lon ??
      rawVessel.location?.lng
  );

  const origin = normalisePort(
    rawVessel.origin,
    rawVessel.originPort ?? rawVessel.from,
    rawVessel.originLat,
    rawVessel.originLng
  );
  const destination = normalisePort(
    rawVessel.destination,
    rawVessel.destinationPort ?? rawVessel.to,
    rawVessel.destinationLat,
    rawVessel.destinationLng
  );

  return {
    id: rawVessel.id || rawVessel.imo || rawVessel.mmsi || `vessel-${index + 1}`,
    name: rawVessel.name || rawVessel.vesselName || `Unnamed vessel ${index + 1}`,
    imo: rawVessel.imo || "Unknown IMO",
    mmsi: rawVessel.mmsi || "Unknown MMSI",
    lat,
    lng,
    type: rawVessel.type || rawVessel.shipType || rawVessel.vesselType || "Other",
    status: rawVessel.status || rawVessel.navStatus || rawVessel.navigationStatus || "Unknown",
    owner: rawVessel.owner || rawVessel.company || rawVessel.registeredOwner || "Unknown owner",
    ownerRegion:
      rawVessel.ownerRegion ||
      rawVessel.ownerCountry ||
      rawVessel.owner_country ||
      "Unspecified",
    flag: rawVessel.flag || rawVessel.flagCountry || "Unknown flag",
    origin,
    destination,
    speedKts: Number(rawVessel.speedKts ?? rawVessel.speed_knots ?? rawVessel.speed ?? 0),
    heading: Number(rawVessel.heading ?? rawVessel.courseOverGround ?? 0),
    eta: rawVessel.eta || rawVessel.estimatedArrival || "",
    lastUpdate: rawVessel.lastUpdate || rawVessel.last_seen || "",
    cargo: rawVessel.cargo || rawVessel.cargoType || "Mixed cargo",
    draftM:
      rawVessel.draftM == null && rawVessel.draft == null
        ? null
        : Number(rawVessel.draftM ?? rawVessel.draft),
    callSign: rawVessel.callSign || rawVessel.callsign || "",
    notes: rawVessel.notes || ""
  };
}

function extractCollection(payload) {
  if (Array.isArray(payload)) {
    return payload;
  }

  if (Array.isArray(payload?.vessels)) {
    return payload.vessels;
  }

  if (Array.isArray(payload?.data)) {
    return payload.data;
  }

  if (Array.isArray(payload?.results)) {
    return payload.results;
  }

  return [];
}

async function fetchJson(path, options = {}) {
  const response = await fetch(path, options);
  if (!response.ok) {
    throw new Error(`Request failed with ${response.status}`);
  }

  return response.json();
}

function hasCoordinates(vessel) {
  return vessel.lat != null && vessel.lng != null;
}

async function loadDemoVessels() {
  const payload = await fetchJson("./data/mock-vessels.json");
  return extractCollection(payload).map(normaliseVessel).filter(hasCoordinates);
}

async function loadLiveVessels() {
  if (!APP_CONFIG.liveEndpoint) {
    throw new Error("No live endpoint configured.");
  }

  const payload = await fetchJson(APP_CONFIG.liveEndpoint, {
    headers: APP_CONFIG.liveHeaders || {}
  });

  return extractCollection(payload).map(normaliseVessel).filter(hasCoordinates);
}

async function loadVessels() {
  const requestedMode = new URLSearchParams(window.location.search).get("mode") || APP_CONFIG.dataMode;

  if (requestedMode === "live") {
    try {
      const vessels = await loadLiveVessels();
      state.dataLabel = `Live endpoint · ${vessels.length} vessels`;
      return vessels;
    } catch (error) {
      console.warn("Live provider unavailable, falling back to demo data.", error);
      const vessels = await loadDemoVessels();
      state.dataLabel = "Demo fallback · live endpoint unavailable";
      return vessels;
    }
  }

  const vessels = await loadDemoVessels();
  state.dataLabel = `Demo fleet · ${vessels.length} vessels`;
  return vessels;
}

function buildQueryCatalog(vessels) {
  return {
    ports: sortLabels(
      uniqueLabels(
        vessels.flatMap((vessel) => [vessel.origin?.name, vessel.destination?.name])
      )
    ),
    owners: sortLabels(uniqueLabels(vessels.map((vessel) => vessel.owner))),
    flags: sortLabels(uniqueLabels(vessels.map((vessel) => vessel.flag))),
    shipNames: sortLabels(uniqueLabels(vessels.map((vessel) => vessel.name)))
  };
}

function getFilterLists(vessels) {
  return {
    types: sortLabels(uniqueLabels(vessels.map((item) => item.type))),
    statuses: sortLabels(uniqueLabels(vessels.map((item) => item.status))),
    ownerRegions: sortLabels(uniqueLabels(vessels.map((item) => item.ownerRegion)))
  };
}

function renderFilterGroup(container, labels, selectedSet, onToggle, vessels, getValue) {
  container.innerHTML = "";

  labels.forEach((label) => {
    const count = vessels.filter((item) => getValue(item) === label).length;
    const wrapper = document.createElement("label");
    wrapper.className = "filterToggle";
    wrapper.innerHTML = `
      <input type="checkbox" ${selectedSet.has(label) ? "checked" : ""} />
      <span>${label}</span>
      <small>${count}</small>
    `;

    const checkbox = wrapper.querySelector("input");
    checkbox.addEventListener("change", (event) => onToggle(label, event.target.checked));
    container.appendChild(wrapper);
  });
}

function updateSet(target, value, checked) {
  if (checked) {
    target.add(value);
  } else {
    target.delete(value);
  }
}

function primeFilterState(vessels) {
  const filterLists = getFilterLists(vessels);
  state.filterCatalog = filterLists;
  state.filters.types = new Set(filterLists.types);
  state.filters.statuses = new Set(filterLists.statuses);
  state.filters.ownerRegions = new Set(filterLists.ownerRegions);

  renderFilterGroup(
    SELECTORS.typeFilters,
    filterLists.types,
    state.filters.types,
    (value, checked) => {
      updateSet(state.filters.types, value, checked);
      markPlanConfirmationStale();
      render();
    },
    vessels,
    (item) => item.type
  );

  renderFilterGroup(
    SELECTORS.statusFilters,
    filterLists.statuses,
    state.filters.statuses,
    (value, checked) => {
      updateSet(state.filters.statuses, value, checked);
      markPlanConfirmationStale();
      render();
    },
    vessels,
    (item) => item.status
  );

  renderFilterGroup(
    SELECTORS.regionFilters,
    filterLists.ownerRegions,
    state.filters.ownerRegions,
    (value, checked) => {
      updateSet(state.filters.ownerRegions, value, checked);
      markPlanConfirmationStale();
      render();
    },
    vessels,
    (item) => item.ownerRegion
  );
}

function markPlanConfirmationStale() {
  if (state.planMeta.confirmedJustNow) {
    state.planMeta.confirmedJustNow = false;
  }
}

function getConstrainedSelection(selectedSet, allValues) {
  const selectedValues = allValues.filter((value) => selectedSet.has(value));

  if (!selectedValues.length || selectedValues.length === allValues.length) {
    return [];
  }

  return selectedValues;
}

function buildAcceptedPlanSnapshot(plan) {
  const nextPlan = cloneSerializable(plan);
  const constrainedTypes = getConstrainedSelection(
    state.filters.types,
    state.filterCatalog.types
  );
  const constrainedStatuses = getConstrainedSelection(
    state.filters.statuses,
    state.filterCatalog.statuses
  );
  const constrainedRegions = getConstrainedSelection(
    state.filters.ownerRegions,
    state.filterCatalog.ownerRegions
  );

  if (constrainedTypes.length) {
    nextPlan.filters.types = constrainedTypes;
  }

  if (constrainedStatuses.length) {
    nextPlan.filters.statuses = constrainedStatuses;
  }

  if (constrainedRegions.length) {
    nextPlan.filters.ownerRegions = constrainedRegions;
  }

  return nextPlan;
}

function buildManualConstraintSummary() {
  const parts = [];
  const constrainedTypes = getConstrainedSelection(
    state.filters.types,
    state.filterCatalog.types
  );
  const constrainedStatuses = getConstrainedSelection(
    state.filters.statuses,
    state.filterCatalog.statuses
  );
  const constrainedRegions = getConstrainedSelection(
    state.filters.ownerRegions,
    state.filterCatalog.ownerRegions
  );

  if (constrainedTypes.length) {
    parts.push(`class ${constrainedTypes.join(", ")}`);
  }

  if (constrainedStatuses.length) {
    parts.push(`status ${constrainedStatuses.join(", ")}`);
  }

  if (constrainedRegions.length) {
    parts.push(`region ${constrainedRegions.join(", ")}`);
  }

  return parts.length ? `Manual narrowing: ${parts.join(" · ")}.` : "";
}

function buildManualConstraintChips() {
  const chips = [];

  getConstrainedSelection(state.filters.types, state.filterCatalog.types).forEach((label) =>
    chips.push({ label: `Manual class: ${label}`, tone: "isManual" })
  );
  getConstrainedSelection(state.filters.statuses, state.filterCatalog.statuses).forEach((label) =>
    chips.push({ label: `Manual status: ${label}`, tone: "isManual" })
  );
  getConstrainedSelection(
    state.filters.ownerRegions,
    state.filterCatalog.ownerRegions
  ).forEach((label) => chips.push({ label: `Manual region: ${label}`, tone: "isManual" }));

  return chips;
}

function formatSpeed(value) {
  return `${Number(value || 0).toFixed(1)} kt`;
}

function formatCoordinate(value, positiveLabel, negativeLabel) {
  const magnitude = Math.abs(Number(value || 0)).toFixed(2);
  const suffix = Number(value) >= 0 ? positiveLabel : negativeLabel;
  return `${magnitude}° ${suffix}`;
}

function formatEta(value) {
  if (!value) {
    return "Unavailable";
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : dateFormatter.format(date);
}

function normalizeText(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9\s-]/g, " ")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function promptHasPhrase(prompt, phrase) {
  const normalizedPhrase = normalizeText(phrase);
  if (!normalizedPhrase) {
    return false;
  }

  const pattern = new RegExp(
    `(^|\\b)${escapeRegExp(normalizedPhrase).replace(/\s+/g, "\\s+")}(\\b|$)`
  );
  return pattern.test(prompt);
}

function matchAliasMap(prompt, aliasMap) {
  return Object.entries(aliasMap)
    .filter(([, aliases]) => aliases.some((alias) => promptHasPhrase(prompt, alias)))
    .map(([label]) => label);
}

function matchDynamicLabels(prompt, labels) {
  return labels.filter((label) => promptHasPhrase(prompt, label));
}

function hasOwnerFilterContext(prompt) {
  return (
    promptHasPhrase(prompt, "owner")
    || promptHasPhrase(prompt, "owned by")
    || promptHasPhrase(prompt, "operator")
    || promptHasPhrase(prompt, "company")
  );
}

function hasFlagFilterContext(prompt) {
  return (
    promptHasPhrase(prompt, "flag")
    || promptHasPhrase(prompt, "flagged")
    || promptHasPhrase(prompt, "registered under")
  );
}

function collectMatchedWords(collections) {
  const matchedWords = new Set();

  collections.forEach((collection) => {
    collection.forEach((label) => {
      normalizeText(label)
        .split(" ")
        .filter(Boolean)
        .forEach((token) => matchedWords.add(token));
    });
  });

  return matchedWords;
}

function singularize(token) {
  if (token.length <= 3) {
    return token;
  }

  if (token.endsWith("ies") && token.length > 4) {
    return `${token.slice(0, -3)}y`;
  }

  if (
    ["ches", "shes", "sses", "xes", "zes"].some((suffix) => token.endsWith(suffix))
    && token.length > 4
  ) {
    return token.slice(0, -2);
  }

  if (token.endsWith("s") && !token.endsWith("ss")) {
    return token.slice(0, -1);
  }

  return token;
}

function extractSearchTerms(prompt, matchedWords) {
  return uniqueLabels(
    prompt
      .split(" ")
      .map((token) => token.trim())
      .filter((token) => token.length > 2)
      .filter((token) => !STOPWORDS.has(token))
      .filter((token) => {
        const singularToken = singularize(token);
        return !matchedWords.has(token) && !matchedWords.has(singularToken);
      })
      .filter((token) => !/^\d+$/.test(token))
  );
}

function extractPromptTokens(prompt) {
  return uniqueLabels(
    prompt
      .split(" ")
      .map((token) => token.trim())
      .filter((token) => token.length > 2)
      .filter((token) => !STOPWORDS.has(token))
      .map((token) => singularize(token))
  );
}

function parseDistanceKm(prompt) {
  const match = prompt.match(/\bwithin\s+(\d{1,3})\s*(km|kilometers?|mi|miles|nm)\b/);
  if (!match) {
    return null;
  }

  const value = Number(match[1]);
  const unit = match[2];
  if (unit.startsWith("mi")) {
    return Math.round(value * 1.609);
  }

  if (unit === "nm") {
    return Math.round(value * 1.852);
  }

  return value;
}

function extractRelations(prompt) {
  const explicitDistanceKm = parseDistanceKm(prompt);
  if (explicitDistanceKm != null) {
    return [{ type: "near", distanceKm: explicitDistanceKm }];
  }

  if (
    promptHasPhrase(prompt, "near")
    || promptHasPhrase(prompt, "around")
    || promptHasPhrase(prompt, "close to")
  ) {
    return [{ type: "near", distanceKm: 25 }];
  }

  return [];
}

function deriveLayersFromPrompt(prompt, currentLayers) {
  const nextLayers = { ...currentLayers };

  Object.entries(LAYER_QUERY_HINTS).forEach(([layer, hints]) => {
    if (hints.disable.some((phrase) => promptHasPhrase(prompt, phrase))) {
      nextLayers[layer] = false;
      return;
    }

    if (hints.enable.some((phrase) => promptHasPhrase(prompt, phrase))) {
      nextLayers[layer] = true;
    }
  });

  return nextLayers;
}

function buildSemanticPlanFromPrompt(normalizedPrompt) {
  const types = matchAliasMap(normalizedPrompt, TYPE_QUERY_ALIASES);
  const statuses = matchAliasMap(normalizedPrompt, STATUS_QUERY_ALIASES);
  const ownerRegions = matchAliasMap(normalizedPrompt, REGION_QUERY_ALIASES);
  const ports = matchDynamicLabels(normalizedPrompt, state.catalog.ports);
  const owners = hasOwnerFilterContext(normalizedPrompt)
    ? matchDynamicLabels(normalizedPrompt, state.catalog.owners)
    : [];
  const flags = hasFlagFilterContext(normalizedPrompt)
    ? matchDynamicLabels(normalizedPrompt, state.catalog.flags)
    : [];
  const shipNames = matchDynamicLabels(normalizedPrompt, state.catalog.shipNames);
  const matchedWords = collectMatchedWords([
    types,
    statuses,
    ownerRegions,
    ports,
    owners,
    flags,
    shipNames
  ]);

  return {
    filters: {
      types,
      statuses,
      ownerRegions,
      ports,
      owners,
      flags,
      shipNames,
      textTerms: extractSearchTerms(normalizedPrompt, matchedWords)
    },
    relations: extractRelations(normalizedPrompt),
    layers: deriveLayersFromPrompt(normalizedPrompt, state.filters.layers)
  };
}

function getBoundsKey(bounds) {
  if (!bounds) {
    return "world";
  }

  return [
    bounds.getSouth(),
    bounds.getWest(),
    bounds.getNorth(),
    bounds.getEast()
  ]
    .map((value) => Number(value).toFixed(1))
    .join(":");
}

function formatViewportLabel(bounds, zoom) {
  if (!bounds) {
    return "World view";
  }

  if (zoom <= APP_CONFIG.defaultZoom + 0.2) {
    return "World view";
  }

  const center = bounds.getCenter();
  return `${formatCoordinate(center.lat, "N", "S")} · ${formatCoordinate(
    center.lng,
    "E",
    "W"
  )} · z${zoom.toFixed(1)}`;
}

function updateViewportState() {
  state.viewport.bounds = map.getBounds();
  state.viewport.boundsKey = getBoundsKey(state.viewport.bounds);
  state.viewport.label = formatViewportLabel(state.viewport.bounds, map.getZoom());
}

function buildLocationScope() {
  if (SELECTORS.useViewportInput.checked && state.viewport.bounds) {
    return {
      mode: "viewport",
      label: state.viewport.label,
      boundsKey: state.viewport.boundsKey
    };
  }

  return {
    mode: "world",
    label: "Global view",
    boundsKey: "world"
  };
}

function getPlannerApiBase() {
  return state.plannerApiBase || APP_CONFIG.plannerApiBase || "";
}

function hasPlannerSupervisor() {
  return Boolean(getPlannerApiBase());
}

async function detectPlannerApi() {
  async function fetchHealth(apiBase) {
    const response = await fetch(`${apiBase}/health`, {
      headers: {
        Accept: "application/json"
      }
    });

    if (!response.ok) {
      return null;
    }

    return response.json();
  }

  if (APP_CONFIG.plannerApiBase) {
    try {
      const health = await fetchHealth(APP_CONFIG.plannerApiBase);
      return {
        apiBase: APP_CONFIG.plannerApiBase,
        health
      };
    } catch (error) {
      return {
        apiBase: APP_CONFIG.plannerApiBase,
        health: null
      };
    }
  }

  if (!APP_CONFIG.autoDetectPlannerApi) {
    return {
      apiBase: "",
      health: null
    };
  }

  if (!window.location.protocol.startsWith("http")) {
    return {
      apiBase: "",
      health: null
    };
  }

  try {
    const health = await fetchHealth("/api");
    return {
      apiBase: health?.ok ? "/api" : "",
      health: health?.ok ? health : null
    };
  } catch (error) {
    return {
      apiBase: "",
      health: null
    };
  }
}

async function requestSupervisorJson(path, payload) {
  const response = await fetch(`${getPlannerApiBase()}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`Supervisor request failed with ${response.status}`);
  }

  return response.json();
}

async function requestSupervisorPlan(prompt) {
  return requestSupervisorJson("/query-plan", {
    prompt,
    currentLayers: { ...state.filters.layers },
    locationScope: buildLocationScope()
  });
}

async function confirmSupervisorPlan(prompt, plan) {
  return requestSupervisorJson("/confirm-plan", {
    prompt,
    plan
  });
}

async function reviewSupervisorSource(sourceId, action) {
  return requestSupervisorJson("/source-review", {
    sourceId,
    action,
    prompt: state.plan?.prompt || SELECTORS.queryInput.value || ""
  });
}

function createQueryPlan(prompt) {
  const normalizedPrompt = normalizeText(prompt);
  const heuristicPlan = buildSemanticPlanFromPrompt(normalizedPrompt);
  const promptTokens = extractPromptTokens(normalizedPrompt);
  const memoryMatch = findPlannerMemory(normalizedPrompt, promptTokens);

  let semanticPlan = heuristicPlan;
  let plannerSource = "heuristic";

  if (memoryMatch) {
    if (memoryMatch.mode === "exact") {
      semanticPlan = memoryMatch.semanticPlan;
      plannerSource = "memory-exact";
    } else {
      semanticPlan = mergeSemanticPlans(memoryMatch.semanticPlan, heuristicPlan);
      plannerSource = "memory-assisted";
    }
  }

  return {
    plan: {
      prompt: prompt.trim(),
      normalizedPrompt,
      locationScope: buildLocationScope(),
      filters: semanticPlan.filters,
      relations: semanticPlan.relations,
      layers: semanticPlan.layers
    },
    plannerSource,
    memoryMatch
  };
}

function buildCanonicalPlan(plan) {
  return {
    filters: {
      flags: [...plan.filters.flags].sort(),
      ownerRegions: [...plan.filters.ownerRegions].sort(),
      owners: [...plan.filters.owners].sort(),
      ports: [...plan.filters.ports].sort(),
      shipNames: [...plan.filters.shipNames].sort(),
      statuses: [...plan.filters.statuses].sort(),
      textTerms: [...plan.filters.textTerms].sort(),
      types: [...plan.filters.types].sort()
    },
    layers: {
      labels: Boolean(plan.layers.labels),
      owners: Boolean(plan.layers.owners),
      ports: Boolean(plan.layers.ports),
      routes: Boolean(plan.layers.routes)
    },
    locationScope: {
      boundsKey: plan.locationScope.boundsKey,
      mode: plan.locationScope.mode
    },
    relations: plan.relations.map((relation) => ({
      distanceKm: relation.distanceKm,
      type: relation.type
    }))
  };
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }

  if (value && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(",")}}`;
  }

  return JSON.stringify(value);
}

function hashString(value) {
  let hash = 5381;

  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 33) ^ value.charCodeAt(index);
  }

  return (hash >>> 0).toString(16).padStart(8, "0");
}

function cloneSerializable(value) {
  return JSON.parse(JSON.stringify(value));
}

function readPlanCache() {
  try {
    return JSON.parse(window.localStorage.getItem(PLAN_CACHE_STORAGE_KEY) || "{}");
  } catch (error) {
    console.warn("Unable to read semantic plan cache.", error);
    return {};
  }
}

function readPlannerMemory() {
  try {
    return JSON.parse(window.localStorage.getItem(PLANNER_MEMORY_STORAGE_KEY) || "[]");
  } catch (error) {
    console.warn("Unable to read planner memory.", error);
    return [];
  }
}

function writePlannerMemory(entries) {
  try {
    window.localStorage.setItem(PLANNER_MEMORY_STORAGE_KEY, JSON.stringify(entries));
  } catch (error) {
    console.warn("Unable to write planner memory.", error);
  }
}

function prunePlannerMemory(entries) {
  return entries
    .slice()
    .sort((left, right) => (right.lastSeenAtMs || 0) - (left.lastSeenAtMs || 0))
    .slice(0, 80);
}

function buildMemorySemanticPlan(plan) {
  return {
    filters: {
      flags: [...plan.filters.flags].sort(),
      ownerRegions: [...plan.filters.ownerRegions].sort(),
      owners: [...plan.filters.owners].sort(),
      ports: [...plan.filters.ports].sort(),
      shipNames: [...plan.filters.shipNames].sort(),
      statuses: [...plan.filters.statuses].sort(),
      textTerms: [...plan.filters.textTerms].sort(),
      types: [...plan.filters.types].sort()
    },
    layers: {
      labels: Boolean(plan.layers.labels),
      owners: Boolean(plan.layers.owners),
      ports: Boolean(plan.layers.ports),
      routes: Boolean(plan.layers.routes)
    },
    relations: plan.relations.map((relation) => ({
      distanceKm: relation.distanceKm,
      type: relation.type
    }))
  };
}

function scoreTokenOverlap(leftTokens, rightTokens) {
  if (!leftTokens.length || !rightTokens.length) {
    return 0;
  }

  const rightSet = new Set(rightTokens);
  const intersectionCount = leftTokens.filter((token) => rightSet.has(token)).length;
  return intersectionCount / Math.max(leftTokens.length, rightTokens.length);
}

function findPlannerMemory(normalizedPrompt, promptTokens) {
  const entries = readPlannerMemory();
  const exactEntry = entries.find(
    (entry) => entry.normalizedPrompt === normalizedPrompt && (entry.confirmedCount || 0) > 0
  );
  if (exactEntry) {
    return {
      mode: "exact",
      score: 1,
      entry: exactEntry,
      semanticPlan: cloneSerializable(exactEntry.semanticPlan)
    };
  }

  const similarEntry = entries
    .filter((entry) => (entry.confirmedCount || 0) > 0)
    .map((entry) => ({
      entry,
      score: scoreTokenOverlap(promptTokens, entry.tokens || [])
    }))
    .filter((item) => item.score >= 0.6)
    .sort((left, right) => right.score - left.score)[0];

  if (!similarEntry) {
    return null;
  }

  return {
    mode: "similar",
    score: similarEntry.score,
    entry: similarEntry.entry,
    semanticPlan: cloneSerializable(similarEntry.entry.semanticPlan)
  };
}

function mergeSemanticPlans(memoryPlan, heuristicPlan) {
  const pickFilterValues = (memoryValues, heuristicValues) =>
    heuristicValues.length ? uniqueLabels(heuristicValues) : uniqueLabels(memoryValues);

  return {
    filters: {
      flags: pickFilterValues(memoryPlan.filters.flags, heuristicPlan.filters.flags),
      ownerRegions: pickFilterValues(
        memoryPlan.filters.ownerRegions,
        heuristicPlan.filters.ownerRegions
      ),
      owners: pickFilterValues(memoryPlan.filters.owners, heuristicPlan.filters.owners),
      ports: pickFilterValues(memoryPlan.filters.ports, heuristicPlan.filters.ports),
      shipNames: pickFilterValues(memoryPlan.filters.shipNames, heuristicPlan.filters.shipNames),
      statuses: pickFilterValues(memoryPlan.filters.statuses, heuristicPlan.filters.statuses),
      textTerms: pickFilterValues(memoryPlan.filters.textTerms, heuristicPlan.filters.textTerms),
      types: pickFilterValues(memoryPlan.filters.types, heuristicPlan.filters.types)
    },
    layers: { ...heuristicPlan.layers },
    relations: heuristicPlan.relations.length ? heuristicPlan.relations : memoryPlan.relations
  };
}

function rememberPlannerOutcome(prompt, plan, options = {}) {
  const normalizedPrompt = normalizeText(prompt);
  if (!normalizedPrompt) {
    return null;
  }

  const promptTokens = extractPromptTokens(normalizedPrompt);
  const now = Date.now();
  const entries = readPlannerMemory();
  const existingIndex = entries.findIndex((entry) => entry.normalizedPrompt === normalizedPrompt);
  const semanticPlan = buildMemorySemanticPlan(plan);
  const existingEntry = existingIndex >= 0 ? entries[existingIndex] : null;

  const nextEntry = {
    normalizedPrompt,
    tokens: promptTokens,
    semanticPlan,
    observedCount: (existingEntry?.observedCount || 0) + 1,
    confirmedCount: (existingEntry?.confirmedCount || 0) + (options.confirmed ? 1 : 0),
    lastSeenAtMs: now,
    lastConfirmedAtMs: options.confirmed ? now : existingEntry?.lastConfirmedAtMs || 0
  };

  if (existingIndex >= 0) {
    entries.splice(existingIndex, 1, nextEntry);
  } else {
    entries.push(nextEntry);
  }

  writePlannerMemory(prunePlannerMemory(entries));
  return nextEntry;
}

function writePlanCache(cache) {
  try {
    window.localStorage.setItem(PLAN_CACHE_STORAGE_KEY, JSON.stringify(cache));
  } catch (error) {
    console.warn("Unable to write semantic plan cache.", error);
  }
}

function prunePlanCache(cache) {
  const entries = Object.entries(cache).sort(
    (left, right) => (right[1]?.lastRunAtMs || 0) - (left[1]?.lastRunAtMs || 0)
  );

  return Object.fromEntries(entries.slice(0, 50));
}

function registerPlanExecution(plan, reason) {
  const canonicalPlan = buildCanonicalPlan(plan);
  const serializedPlan = stableStringify(canonicalPlan);
  const hash = hashString(serializedPlan);
  const now = Date.now();
  const cache = readPlanCache();
  const existing = cache[hash];
  const cacheAgeMs = existing ? now - existing.lastRunAtMs : null;
  const cacheStatus = existing
    ? cacheAgeMs <= PLAN_CACHE_TTL_MS
      ? "warm"
      : "stale"
    : "cold";

  cache[hash] = {
    canonicalPlan,
    lastPrompt: plan.prompt,
    lastRunAtMs: now,
    reason
  };

  writePlanCache(prunePlanCache(cache));

  return {
    hash,
    cacheStatus,
    cacheAgeMs,
    lastRunAtMs: now,
    reason
  };
}

function buildBrowserPlanMeta(planResult, reason) {
  return {
    ...registerPlanExecution(planResult.plan, reason),
    plannerSource: planResult.plannerSource,
    plannerRuntime: "browser",
    memoryPrompt: planResult.memoryMatch?.entry?.normalizedPrompt || "",
    memoryScore: planResult.memoryMatch?.score || null,
    memoryCount: readPlannerMemory().length,
    workerCount: 0,
    workers: [],
    confirmedJustNow: false
  };
}

function buildSupervisorPlanMeta(payload, reason) {
  return {
    hash: payload.cache?.hash || "",
    cacheStatus: payload.cache?.status || "cold",
    cacheAgeMs: payload.cache?.ageMs ?? null,
    lastRunAtMs: payload.cache?.lastRunAtMs || Date.now(),
    reason,
    plannerSource: payload.plannerSource || "heuristic",
    plannerRuntime: "supervisor",
    memoryPrompt: payload.memoryMatch?.prompt || "",
    memoryScore: payload.memoryMatch?.score || null,
    memoryCount: payload.memory?.count || 0,
    workerCount: payload.workers?.length || 0,
    workers: payload.workers || [],
    confirmedJustNow: false
  };
}

async function resolveQueryPlan(prompt, reason) {
  if (hasPlannerSupervisor()) {
    try {
      const payload = await requestSupervisorPlan(prompt);
      return {
        plan: payload.plan,
        meta: buildSupervisorPlanMeta(payload, reason),
        sourceSuggestions: payload.sourceSuggestions || [],
        sourceRegistry: payload.sourceRegistry || null
      };
    } catch (error) {
      console.warn("Supervisor planner unavailable, falling back to browser planner.", error);
    }
  }

  const planResult = createQueryPlan(prompt);
  rememberPlannerOutcome(prompt, planResult.plan, { confirmed: false });
  return {
    plan: planResult.plan,
    meta: buildBrowserPlanMeta(planResult, reason),
    sourceSuggestions: [],
    sourceRegistry: null
  };
}

function formatAge(ageMs) {
  if (ageMs == null) {
    return "just now";
  }

  if (ageMs < 30 * 1000) {
    return "just now";
  }

  if (ageMs < 60 * 60 * 1000) {
    return `${Math.round(ageMs / (60 * 1000))}m old`;
  }

  if (ageMs < 24 * 60 * 60 * 1000) {
    return `${Math.round(ageMs / (60 * 60 * 1000))}h old`;
  }

  return `${Math.round(ageMs / (24 * 60 * 60 * 1000))}d old`;
}

function getFreshnessLabel(ageMs, ttlMs) {
  if (ageMs <= ttlMs * 0.5) {
    return `fresh · ${formatAge(ageMs)}`;
  }

  if (ageMs <= ttlMs) {
    return `aging · ${formatAge(ageMs)}`;
  }

  return `stale · ${formatAge(ageMs)}`;
}

function getCacheStatusLabel(meta) {
  if (meta.cacheStatus === "warm") {
    return `Warm · ${formatAge(meta.cacheAgeMs)}`;
  }

  if (meta.cacheStatus === "stale") {
    return "Revalidated";
  }

  return "Cold";
}

function getRunReasonLabel(reason) {
  switch (reason) {
    case "viewport move":
      return "Viewport refresh";
    case "scope toggle":
      return "Scope changed";
    case "example":
      return "Example prompt";
    case "clear":
      return "Prompt cleared";
    case "boot":
      return "Initial run";
    default:
      return "Prompt executed";
  }
}

function describePlannerLearning(meta) {
  const plannerLabel = meta.plannerRuntime === "supervisor" ? "Local supervisor" : "Planner";

  if (meta.confirmedJustNow) {
    return "Current meaning saved as a confirmed planner memory.";
  }

  if (meta.plannerSource === "memory-exact") {
    return `${plannerLabel} reused a remembered meaning for this exact prompt.`;
  }

  if (meta.plannerSource === "memory-assisted") {
    return `${plannerLabel} blended heuristic parsing with a confirmed similar prompt (${Math.round(
      (meta.memoryScore || 0) * 100
    )}% match).`;
  }

  return `${plannerLabel} used heuristic bootstrap because no remembered meaning matched this prompt yet.`;
}

function setBadgeState(element, label, tone) {
  element.textContent = label;
  element.classList.remove("isWarm", "isStale", "isCold");

  if (tone === "warm") {
    element.classList.add("isWarm");
    return;
  }

  if (tone === "stale") {
    element.classList.add("isStale");
    return;
  }

  element.classList.add("isCold");
}

function describePlan(plan) {
  const parts = [];

  parts.push(
    plan.locationScope.mode === "viewport"
      ? "Location scope is the current map focus."
      : "Location scope is global."
  );

  if (plan.filters.types.length) {
    parts.push(`Types: ${plan.filters.types.join(", ")}.`);
  }

  if (plan.filters.statuses.length) {
    parts.push(`Statuses: ${plan.filters.statuses.join(", ")}.`);
  }

  if (plan.filters.ownerRegions.length) {
    parts.push(`Owner regions: ${plan.filters.ownerRegions.join(", ")}.`);
  }

  if (plan.filters.ports.length) {
    parts.push(`Ports: ${plan.filters.ports.join(", ")}.`);
  }

  if (plan.filters.textTerms.length) {
    parts.push(`Free terms: ${plan.filters.textTerms.join(", ")}.`);
  }

  if (plan.relations.length) {
    parts.push(`Spatial rule: within ${plan.relations[0].distanceKm} km.`);
  }

  const manualConstraintSummary = buildManualConstraintSummary();
  if (manualConstraintSummary) {
    parts.push(manualConstraintSummary);
  }

  if (parts.length === 1 && !plan.prompt) {
    return `${parts[0]} The map is using manual toggles only until a prompt adds more structure.`;
  }

  return parts.join(" ");
}

function renderPlanChips(plan) {
  const chips = [];

  chips.push({
    label: plan.locationScope.mode === "viewport" ? "Viewport scope" : "Global scope",
    tone: "isLocation"
  });

  plan.filters.types.forEach((label) => chips.push({ label: `Type: ${label}`, tone: "isFilter" }));
  plan.filters.statuses.forEach((label) =>
    chips.push({ label: `Status: ${label}`, tone: "isFilter" })
  );
  plan.filters.ownerRegions.forEach((label) =>
    chips.push({ label: `Region: ${label}`, tone: "isFilter" })
  );
  plan.filters.ports.forEach((label) => chips.push({ label: `Port: ${label}`, tone: "isFilter" }));
  plan.filters.owners.forEach((label) => chips.push({ label: `Owner: ${label}`, tone: "isFilter" }));
  plan.filters.flags.forEach((label) => chips.push({ label: `Flag: ${label}`, tone: "isFilter" }));
  plan.filters.shipNames.forEach((label) =>
    chips.push({ label: `Ship: ${label}`, tone: "isFilter" })
  );
  plan.filters.textTerms.forEach((label) =>
    chips.push({ label: `Text: ${label}`, tone: "isText" })
  );
  plan.relations.forEach((relation) =>
    chips.push({
      label: `${relation.type} ${relation.distanceKm} km`,
      tone: "isRelation"
    })
  );
  chips.push(...buildManualConstraintChips());

  if (!chips.length) {
    chips.push({ label: "All vessels", tone: "isFilter" });
  }

  SELECTORS.planChips.innerHTML = chips
    .map((chip) => `<span class="planChip ${chip.tone}">${chip.label}</span>`)
    .join("");
}

function buildSourceRows() {
  const now = Date.now();
  const isDemoFeed = state.dataLabel.toLowerCase().includes("demo");
  const plannerMemoryCount = state.planMeta.memoryCount || readPlannerMemory().length;
  const workerSummary = state.planMeta.workerCount
    ? ` · ${state.planMeta.workerCount} worker tasks`
    : "";

  return [
    {
      label: "Semantic plan",
      status:
        state.planMeta.cacheStatus === "warm"
          ? `cache hit · ${formatAge(state.planMeta.cacheAgeMs)}`
          : state.planMeta.cacheStatus === "stale"
          ? "stale plan revalidated"
          : "new semantic plan",
      meta: state.planMeta.hash
        ? `hash ${state.planMeta.hash.slice(0, 8)} · ${plannerMemoryCount} remembered prompts${workerSummary}`
        : `${plannerMemoryCount} remembered prompts${workerSummary}`
    },
    {
      label: "Vessel positions",
      status: isDemoFeed
        ? `session fresh · ${formatAge(now - state.dataLoadedAtMs)}`
        : getFreshnessLabel(now - state.dataLoadedAtMs, POSITION_TTL_MS),
      meta: isDemoFeed ? "sample feed rerendered live in-browser" : "provider result refreshed on query"
    },
    {
      label: "Ownership / flag registry",
      status: getFreshnessLabel(now - state.dataLoadedAtMs, OWNERSHIP_TTL_MS),
      meta: `${new Set(state.vessels.map((vessel) => vessel.owner)).size} owners indexed locally`
    },
    {
      label: "Port / viewport reference",
      status:
        state.plan?.locationScope.mode === "viewport"
          ? "live viewport"
          : getFreshnessLabel(now - state.dataLoadedAtMs, PORT_REFERENCE_TTL_MS),
      meta: state.viewport.label
    }
  ];
}

function renderFreshnessPanel() {
  const plannerModeLabel = state.plan?.locationScope.mode === "viewport" ? "Viewport scope" : "Global scope";
  setBadgeState(
    SELECTORS.plannerMode,
    plannerModeLabel,
    state.plan?.locationScope.mode === "viewport" ? "warm" : "cold"
  );

  SELECTORS.sourceFreshness.innerHTML = buildSourceRows()
    .map(
      (row) => `
        <article class="sourceRow">
          <div class="sourceLabel">${row.label}</div>
          <div class="sourceStatus">${row.status}</div>
          <div class="sourceMeta">${row.meta}</div>
        </article>
      `
    )
    .join("");
}

function formatWorkerDuration(durationMs) {
  if (!Number.isFinite(durationMs)) {
    return "";
  }

  return `${Math.round(durationMs)} ms`;
}

function renderWorkerPanel() {
  const workerMode = state.plannerHealth?.workerMode
    || (state.planMeta.plannerRuntime === "supervisor" ? "inline" : "browser");
  const workerModeLabel = workerMode === "subprocess"
    ? "Subprocess"
    : workerMode === "inline"
      ? "Supervisor"
      : "Browser";
  const workerTone = workerMode === "subprocess" ? "warm" : "cold";

  setBadgeState(SELECTORS.workerModeBadge, workerModeLabel, workerTone);

  if (!state.plannerHealth && state.planMeta.plannerRuntime !== "supervisor") {
    SELECTORS.workerRuntime.textContent = "Browser heuristic planner only.";
  } else {
    const workerCommand = state.plannerHealth?.workerCommand
      ? ` Command: ${state.plannerHealth.workerCommand}.`
      : "";
    SELECTORS.workerRuntime.textContent = `${
      state.plannerHealth?.planner === "local-supervisor"
        ? "Local supervisor connected."
        : "Supervisor metadata unavailable."
    }${workerCommand}`;
  }

  const workers = state.planMeta.workers || [];
  if (!workers.length) {
    SELECTORS.workerTrace.innerHTML = `
      <article class="sourceRow">
        <div class="sourceLabel">No worker run yet</div>
        <div class="sourceStatus">Awaiting query</div>
        <div class="sourceMeta">Submit a prompt to see the planner worker graph.</div>
      </article>
    `;
    return;
  }

  SELECTORS.workerTrace.innerHTML = workers
    .map(
      (worker) => `
        <article class="sourceRow">
          <div class="sourceLabel">${worker.worker}</div>
          <div class="sourceStatus">${worker.source} · ${formatWorkerDuration(worker.durationMs)}</div>
          <div class="sourceMeta">${worker.summary}</div>
        </article>
      `
    )
    .join("");
}

function getSourceDecisionLabel(decision) {
  switch (decision) {
    case "add":
      return "Added";
    case "sandbox":
      return "Sandbox";
    case "ignore":
      return "Ignored";
    default:
      return "Suggested";
  }
}

function getSourceDecisionTone(decision) {
  switch (decision) {
    case "add":
      return "warm";
    case "sandbox":
      return "stale";
    case "ignore":
      return "cold";
    default:
      return "cold";
  }
}

function buildSourceRegistrySummary() {
  const registry = state.plannerHealth?.sourceRegistry;
  if (!registry) {
    return "";
  }

  return `${registry.addedCount || 0} added · ${registry.sandboxCount || 0} sandboxed · ${registry.ignoredCount || 0} ignored`;
}

function renderSourceSuggestionsPanel() {
  if (!hasPlannerSupervisor() && state.planMeta.plannerRuntime !== "supervisor") {
    SELECTORS.sourceScoutStatus.textContent = "Source scouting needs the local supervisor. Browser-only mode cannot review sources.";
    SELECTORS.sourceSuggestions.innerHTML = `
      <article class="sourceRow">
        <div class="sourceLabel">Supervisor unavailable</div>
        <div class="sourceStatus">Browser planner only</div>
        <div class="sourceMeta">Start server.py to let local workers scout public sources for approval.</div>
      </article>
    `;
    return;
  }

  if (!state.plan?.prompt) {
    SELECTORS.sourceScoutStatus.textContent = "Run a prompt to scout relevant public datasets and APIs.";
    SELECTORS.sourceSuggestions.innerHTML = `
      <article class="sourceRow">
        <div class="sourceLabel">Awaiting prompt</div>
        <div class="sourceStatus">No source scouting yet</div>
        <div class="sourceMeta">The local workers will suggest public sources after the next query.</div>
      </article>
    `;
    return;
  }

  const registrySummary = buildSourceRegistrySummary();
  if (!state.sourceSuggestions.length) {
    SELECTORS.sourceScoutStatus.textContent = registrySummary
      ? `No new source suggestions for this prompt. Registry: ${registrySummary}.`
      : "No new source suggestions for this prompt.";
    SELECTORS.sourceSuggestions.innerHTML = `
      <article class="sourceRow">
        <div class="sourceLabel">No queued sources</div>
        <div class="sourceStatus">Nothing to review</div>
        <div class="sourceMeta">Try a broader prompt if you want the scout workers to look for more public data sources.</div>
      </article>
    `;
    return;
  }

  SELECTORS.sourceScoutStatus.textContent = registrySummary
    ? `${state.sourceSuggestions.length} source suggestions are ready for review. Registry: ${registrySummary}.`
    : `${state.sourceSuggestions.length} source suggestions are ready for review.`;

  SELECTORS.sourceSuggestions.innerHTML = state.sourceSuggestions
    .map((source) => {
      const pendingAction = state.sourceReviewState[source.id] || "";
      const badgeLabel = pendingAction ? `${pendingAction}...` : getSourceDecisionLabel(source.decision);
      const badgeTone = pendingAction ? "warm" : getSourceDecisionTone(source.decision);
      const reviewMeta = source.reviewedAtMs
        ? ` · reviewed ${formatAge(Date.now() - source.reviewedAtMs)}`
        : "";
      const actions = [
        { action: "add", label: source.decision === "add" ? "Added" : "Add" },
        { action: "sandbox", label: source.decision === "sandbox" ? "Sandboxed" : "Sandbox" },
        { action: "ignore", label: source.decision === "ignore" ? "Ignored" : "Ignore" }
      ]
        .map(
          ({ action, label }) => `
            <button
              class="ghostButton smallButton sourceActionButton ${source.decision === action ? "isActive" : ""}"
              type="button"
              data-source-id="${source.id}"
              data-source-action="${action}"
              ${pendingAction || source.decision === action ? "disabled" : ""}
            >
              ${pendingAction === action ? "Saving..." : label}
            </button>
          `
        )
        .join("");

      return `
        <article class="sourceRow sourceSuggestion">
          <div class="sourceHeaderLine">
            <div class="sourceLabel">${source.name}</div>
            <span class="tinyBadge is${badgeTone === "warm" ? "Warm" : badgeTone === "stale" ? "Stale" : "Cold"}">${badgeLabel}</span>
          </div>
          <div class="sourceStatus">${source.category} · ${source.scope} · ${source.license}</div>
          <div class="sourceMeta">${source.reason}</div>
          <div class="sourceMeta">${source.summary}${reviewMeta}</div>
          ${source.url ? `<a class="sourceLink" href="${source.url}" target="_blank" rel="noreferrer noopener">${source.url}</a>` : ""}
          <div class="sourceActions">${actions}</div>
        </article>
      `;
    })
    .join("");
}

function applyPlanLayers(plan) {
  state.filters.layers = { ...plan.layers };
  SELECTORS.toggleRoutes.checked = state.filters.layers.routes;
  SELECTORS.togglePorts.checked = state.filters.layers.ports;
  SELECTORS.toggleLabels.checked = state.filters.layers.labels;
  SELECTORS.toggleOwners.checked = state.filters.layers.owners;
}

function syncPlanPanels() {
  const plan = state.plan || createQueryPlan("").plan;

  SELECTORS.planSummary.textContent = describePlan(plan);
  SELECTORS.planLearning.textContent = describePlannerLearning(state.planMeta);
  SELECTORS.rememberPlanButton.disabled = !plan.prompt;
  renderPlanChips(plan);
  setBadgeState(
    SELECTORS.planCacheBadge,
    getCacheStatusLabel(state.planMeta),
    state.planMeta.cacheStatus
  );
  setBadgeState(
    SELECTORS.runStatus,
    getRunReasonLabel(state.planMeta.reason),
    state.planMeta.cacheStatus
  );
  setBadgeState(
    SELECTORS.viewportLabel,
    state.viewport.label,
    plan.locationScope.mode === "viewport" ? "warm" : "cold"
  );
  renderFreshnessPanel();
  renderWorkerPanel();
  renderSourceSuggestionsPanel();
}

function matchesManualFilters(vessel) {
  return (
    state.filters.types.has(vessel.type)
    && state.filters.statuses.has(vessel.status)
    && state.filters.ownerRegions.has(vessel.ownerRegion)
  );
}

function matchesTextTerms(vessel, terms) {
  if (!terms.length) {
    return true;
  }

  const haystack = normalizeText(
    [
      vessel.name,
      vessel.imo,
      vessel.mmsi,
      vessel.owner,
      vessel.ownerRegion,
      vessel.flag,
      vessel.type,
      vessel.status,
      vessel.origin?.name,
      vessel.destination?.name,
      vessel.cargo,
      vessel.notes
    ]
      .filter(Boolean)
      .join(" ")
  );

  return terms.every((term) => haystack.includes(term));
}

function matchesPlanFilters(vessel, plan) {
  if (!plan) {
    return true;
  }

  if (plan.locationScope.mode === "viewport" && state.viewport.bounds) {
    if (!state.viewport.bounds.contains([vessel.lat, vessel.lng])) {
      return false;
    }
  }

  if (plan.filters.types.length && !plan.filters.types.includes(vessel.type)) {
    return false;
  }

  if (plan.filters.statuses.length && !plan.filters.statuses.includes(vessel.status)) {
    return false;
  }

  if (plan.filters.ownerRegions.length && !plan.filters.ownerRegions.includes(vessel.ownerRegion)) {
    return false;
  }

  if (plan.filters.flags.length && !plan.filters.flags.includes(vessel.flag)) {
    return false;
  }

  if (plan.filters.shipNames.length && !plan.filters.shipNames.includes(vessel.name)) {
    return false;
  }

  if (plan.filters.owners.length && !plan.filters.owners.includes(vessel.owner)) {
    return false;
  }

  if (plan.filters.ports.length) {
    const routePorts = [vessel.origin?.name, vessel.destination?.name].filter(Boolean);
    if (!plan.filters.ports.some((port) => routePorts.includes(port))) {
      return false;
    }
  }

  return matchesTextTerms(vessel, plan.filters.textTerms);
}

function getVisibleVessels() {
  return state.vessels.filter(
    (vessel) => matchesManualFilters(vessel) && matchesPlanFilters(vessel, state.plan)
  );
}

function buildPopupHtml(vessel) {
  return `
    <strong>${vessel.name}</strong><br />
    ${vessel.type} · ${vessel.status}<br />
    ${vessel.origin?.name || "Unknown"} → ${vessel.destination?.name || "Unknown"}<br />
    Owner: ${vessel.owner}
  `;
}

function buildLabelMarker(vessel, className, text, verticalShiftPx = 0) {
  return L.marker([vessel.lat, vessel.lng], {
    interactive: false,
    icon: L.divIcon({
      className: "fleetTagIcon",
      html: `<span class="${className}" style="transform: translate(-50%, ${verticalShiftPx}px);">${text}</span>`,
      iconSize: [0, 0],
      iconAnchor: [0, 0]
    })
  });
}

function buildRoutePoints(vessel) {
  const sourcePoints = [
    [vessel.origin.lat, vessel.origin.lng],
    [vessel.lat, vessel.lng],
    [vessel.destination.lat, vessel.destination.lng]
  ];

  return sourcePoints.reduce((points, [lat, lng], index) => {
    if (index === 0) {
      points.push([lat, lng]);
      return points;
    }

    let adjustedLng = lng;
    const previousLng = points[index - 1][1];

    while (adjustedLng - previousLng > 180) {
      adjustedLng -= 360;
    }

    while (adjustedLng - previousLng < -180) {
      adjustedLng += 360;
    }

    points.push([lat, adjustedLng]);
    return points;
  }, []);
}

function addPortMarker(port, label, color) {
  if (!port || port.lat == null || port.lng == null) {
    return;
  }

  const marker = L.circleMarker([port.lat, port.lng], {
    radius: 5,
    color,
    weight: 1,
    fillColor: color,
    fillOpacity: 0.72
  });

  marker.bindTooltip(`${label}: ${port.name}`, {
    direction: "top"
  });
  portLayer.addLayer(marker);
}

function renderMap(vessels) {
  routeLayer.clearLayers();
  portLayer.clearLayers();
  labelLayer.clearLayers();
  ownerLayer.clearLayers();
  vesselLayer.clearLayers();
  scopeLayer.clearLayers();

  if (state.plan?.locationScope.mode === "viewport" && state.viewport.bounds) {
    L.rectangle(state.viewport.bounds, {
      color: "#86c9ff",
      weight: 1,
      opacity: 0.7,
      fillOpacity: 0.03,
      dashArray: "10 10"
    }).addTo(scopeLayer);
  }

  vessels.forEach((vessel) => {
    const color = getTypeColor(vessel.type);
    const isSelected = vessel.id === state.selectedId;

    if (
      state.filters.layers.routes
      && vessel.origin?.lat != null
      && vessel.origin?.lng != null
      && vessel.destination?.lat != null
      && vessel.destination?.lng != null
    ) {
      const route = L.polyline(buildRoutePoints(vessel), {
        color,
        weight: isSelected ? 3 : 2,
        opacity: isSelected ? 0.86 : 0.38,
        dashArray: isSelected ? "10 10" : "8 12",
        noClip: true
      });
      routeLayer.addLayer(route);
    }

    if (state.filters.layers.ports) {
      addPortMarker(vessel.origin, "Origin", color);
      addPortMarker(vessel.destination, "Destination", "#cbd4d6");
    }

    const marker = L.circleMarker([vessel.lat, vessel.lng], {
      radius: isSelected ? 10 : 8,
      color: isSelected ? "#ffffff" : color,
      weight: isSelected ? 2.5 : 1.5,
      fillColor: color,
      fillOpacity: 0.92
    });

    marker.bindPopup(buildPopupHtml(vessel), {
      closeButton: false,
      autoPan: false
    });
    marker.on("click", () => selectVessel(vessel.id, true));
    vesselLayer.addLayer(marker);

    if (state.filters.layers.labels) {
      labelLayer.addLayer(buildLabelMarker(vessel, "mapLabel", vessel.name, -30));
    }

    if (state.filters.layers.owners) {
      ownerLayer.addLayer(buildLabelMarker(vessel, "ownerBadge", vessel.owner, 14));
    }
  });
}

function renderFleetList(vessels) {
  SELECTORS.feedCount.textContent = `${vessels.length}`;
  SELECTORS.vesselList.innerHTML = "";

  if (!vessels.length) {
    SELECTORS.vesselList.innerHTML = `
      <article class="vesselCard">
        <div class="feedTopline">
          <h3 class="feedTitle">No vessels match this plan</h3>
        </div>
        <p class="feedRoute">Try clearing the prompt, widening the map focus, or loosening a secondary filter.</p>
      </article>
    `;
    return;
  }

  vessels
    .slice()
    .sort((left, right) => left.name.localeCompare(right.name))
    .forEach((vessel) => {
      const card = document.createElement("button");
      card.type = "button";
      card.className = `vesselCard ${vessel.id === state.selectedId ? "isSelected" : ""}`;
      card.innerHTML = `
        <div class="feedTopline">
          <h3 class="feedTitle">${vessel.name}</h3>
          <span class="feedType">${vessel.type}</span>
        </div>
        <div class="feedRoute">
          <span>${vessel.origin?.name || "Unknown origin"}</span>
          <span>→</span>
          <span>${vessel.destination?.name || "Unknown destination"}</span>
        </div>
        <div class="feedMeta">
          <span class="statusBadge ${statusClass(vessel.status)}">${vessel.status}</span>
          <span>${vessel.owner}</span>
          <span>${vessel.flag}</span>
          <span>${formatSpeed(vessel.speedKts)}</span>
        </div>
      `;
      card.addEventListener("click", () => selectVessel(vessel.id, true));
      SELECTORS.vesselList.appendChild(card);
    });
}

function getSelectedVessel() {
  return state.vessels.find((item) => item.id === state.selectedId) || null;
}

function renderDetailCard(vessel) {
  if (!vessel) {
    SELECTORS.detailCard.innerHTML = `
      <div class="detailEmpty">
        <p class="eyebrow">Vessel focus</p>
        <h2>Select a vessel</h2>
        <p>
          Pick a ship from the map or the visible fleet to inspect owner, route,
          status, flag, and freshness context.
        </p>
      </div>
    `;
    return;
  }

  SELECTORS.detailCard.innerHTML = `
    <div class="detailContent">
      <div class="detailHeader">
        <div>
          <p class="eyebrow">Vessel focus</p>
          <h2 class="detailTitle">${vessel.name}</h2>
        </div>
        <span class="statusBadge ${statusClass(vessel.status)}">${vessel.status}</span>
      </div>
      <div class="detailMeta">
        <span class="metricPill">${vessel.type}</span>
        <span class="metricPill">${vessel.flag}</span>
        <span class="metricPill">${vessel.ownerRegion}</span>
      </div>
      <div class="routeBand">
        <span class="routeTitle">Voyage lane</span>
        <div class="routeChain">
          <span>${vessel.origin?.name || "Unknown origin"}</span>
          <span class="routeArrow">→</span>
          <span>${vessel.destination?.name || "Unknown destination"}</span>
        </div>
        <p class="routeCopy">${vessel.owner} · ${vessel.cargo}</p>
      </div>
      <div class="detailMetrics">
        <article class="detailMetric">
          <span class="detailMetricLabel">IMO / MMSI</span>
          <span class="detailMetricValue">${vessel.imo} / ${vessel.mmsi}</span>
        </article>
        <article class="detailMetric">
          <span class="detailMetricLabel">Speed / heading</span>
          <span class="detailMetricValue">${formatSpeed(vessel.speedKts)} · ${Math.round(
            vessel.heading
          )}&deg;</span>
        </article>
        <article class="detailMetric">
          <span class="detailMetricLabel">Coordinates</span>
          <span class="detailMetricValue">${formatCoordinate(
            vessel.lat,
            "N",
            "S"
          )} / ${formatCoordinate(vessel.lng, "E", "W")}</span>
        </article>
        <article class="detailMetric">
          <span class="detailMetricLabel">ETA</span>
          <span class="detailMetricValue">${formatEta(vessel.eta)}</span>
        </article>
        <article class="detailMetric">
          <span class="detailMetricLabel">Last update</span>
          <span class="detailMetricValue">${formatEta(vessel.lastUpdate)}</span>
        </article>
        <article class="detailMetric">
          <span class="detailMetricLabel">Draft / call sign</span>
          <span class="detailMetricValue">${vessel.draftM == null ? "N/A" : `${vessel.draftM.toFixed(
            1
          )} m`} · ${vessel.callSign || "Unknown"}</span>
        </article>
      </div>
      ${vessel.notes ? `<p class="detailMeta">${vessel.notes}</p>` : ""}
    </div>
  `;
}

function updateStats(vessels) {
  const inMotion = vessels.filter((item) =>
    ["In transit", "Approaching port", "Survey operations"].includes(item.status)
  ).length;
  const owners = new Set(vessels.map((item) => item.owner)).size;
  const avgSpeed =
    vessels.reduce((total, item) => total + Number(item.speedKts || 0), 0) /
    (vessels.length || 1);

  SELECTORS.visibleTotal.textContent = String(vessels.length);
  SELECTORS.inMotionTotal.textContent = String(inMotion);
  SELECTORS.ownerTotal.textContent = String(owners);
  SELECTORS.avgSpeed.textContent = `${avgSpeed.toFixed(1)} kt`;
  SELECTORS.dataModeLabel.textContent = state.dataLabel;
}

function selectVessel(id, shouldFocus) {
  state.selectedId = id;
  render();

  const vessel = getSelectedVessel();
  if (shouldFocus && vessel) {
    state.skipNextViewportRun = state.plan?.locationScope.mode === "viewport";
    map.flyTo([vessel.lat, vessel.lng], Math.max(map.getZoom(), 4), {
      animate: true,
      duration: 1.2
    });
  }
}

function render() {
  syncPlanPanels();

  const visibleVessels = getVisibleVessels();
  const selectedStillVisible = visibleVessels.some((item) => item.id === state.selectedId);

  if (!selectedStillVisible) {
    state.selectedId = visibleVessels[0]?.id || null;
  }

  renderMap(visibleVessels);
  renderFleetList(visibleVessels);
  renderDetailCard(getSelectedVessel());
  updateStats(visibleVessels);
}

async function runActiveQuery(reason) {
  const prompt = SELECTORS.queryInput.value || "";
  const runId = state.nextQueryRunId + 1;
  state.nextQueryRunId = runId;
  SELECTORS.runStatus.textContent = "Planning";

  const result = await resolveQueryPlan(prompt, reason);
  if (runId !== state.nextQueryRunId) {
    return;
  }

  applyPlanLayers(result.plan);
  state.plan = result.plan;
  state.planMeta = result.meta;
  state.sourceSuggestions = result.sourceSuggestions || [];
  state.sourceReviewState = {};
  if (result.sourceRegistry) {
    state.plannerHealth = {
      ...(state.plannerHealth || {}),
      sourceRegistry: result.sourceRegistry
    };
  }
  render();
}

function attachEventHandlers() {
  SELECTORS.queryForm.addEventListener("submit", (event) => {
    event.preventDefault();
    runActiveQuery("prompt");
  });

  SELECTORS.clearQueryButton.addEventListener("click", () => {
    SELECTORS.queryInput.value = "";
    runActiveQuery("clear");
  });

  SELECTORS.rememberPlanButton.addEventListener("click", async () => {
    if (!state.plan?.prompt) {
      return;
    }

    const acceptedPlan = buildAcceptedPlanSnapshot(state.plan);

    if (hasPlannerSupervisor()) {
      try {
        const payload = await confirmSupervisorPlan(state.plan.prompt, acceptedPlan);
        state.planMeta.memoryCount = payload.memory?.count || state.planMeta.memoryCount;
      } catch (error) {
        console.warn("Supervisor confirm failed, falling back to browser memory.", error);
        rememberPlannerOutcome(state.plan.prompt, acceptedPlan, {
          confirmed: true
        });
        state.planMeta.memoryCount = readPlannerMemory().length;
      }
    } else {
      rememberPlannerOutcome(state.plan.prompt, acceptedPlan, {
        confirmed: true
      });
      state.planMeta.memoryCount = readPlannerMemory().length;
    }

    state.planMeta.confirmedJustNow = true;
    render();
  });

  SELECTORS.sourceSuggestions.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-source-action]");
    if (!button || !hasPlannerSupervisor()) {
      return;
    }

    const sourceId = button.dataset.sourceId || "";
    const action = button.dataset.sourceAction || "";
    if (!sourceId || !action || state.sourceReviewState[sourceId]) {
      return;
    }

    state.sourceReviewState = {
      ...state.sourceReviewState,
      [sourceId]: action
    };
    renderSourceSuggestionsPanel();

    try {
      const payload = await reviewSupervisorSource(sourceId, action);
      state.sourceSuggestions = state.sourceSuggestions.map((source) =>
        source.id === sourceId ? { ...source, ...(payload.source || {}) } : source
      );
      state.plannerHealth = {
        ...(state.plannerHealth || {}),
        sourceRegistry: payload.registry || state.plannerHealth?.sourceRegistry
      };
    } catch (error) {
      console.warn("Supervisor source review failed.", error);
    } finally {
      const nextReviewState = { ...state.sourceReviewState };
      delete nextReviewState[sourceId];
      state.sourceReviewState = nextReviewState;
      syncPlanPanels();
    }
  });

  SELECTORS.useViewportInput.addEventListener("change", () => {
    runActiveQuery("scope toggle");
  });

  SELECTORS.toggleRoutes.addEventListener("change", (event) => {
    state.filters.layers.routes = event.target.checked;
    if (state.plan) {
      state.plan.layers.routes = event.target.checked;
    }
    markPlanConfirmationStale();
    render();
  });

  SELECTORS.togglePorts.addEventListener("change", (event) => {
    state.filters.layers.ports = event.target.checked;
    if (state.plan) {
      state.plan.layers.ports = event.target.checked;
    }
    markPlanConfirmationStale();
    render();
  });

  SELECTORS.toggleLabels.addEventListener("change", (event) => {
    state.filters.layers.labels = event.target.checked;
    if (state.plan) {
      state.plan.layers.labels = event.target.checked;
    }
    markPlanConfirmationStale();
    render();
  });

  SELECTORS.toggleOwners.addEventListener("change", (event) => {
    state.filters.layers.owners = event.target.checked;
    if (state.plan) {
      state.plan.layers.owners = event.target.checked;
    }
    markPlanConfirmationStale();
    render();
  });

  SELECTORS.resetViewButton.addEventListener("click", () => {
    map.flyTo(APP_CONFIG.defaultCenter, APP_CONFIG.defaultZoom, {
      animate: true,
      duration: 1.1
    });
  });

  SELECTORS.exampleButtons.forEach((button) => {
    button.addEventListener("click", () => {
      SELECTORS.queryInput.value = button.dataset.exampleQuery || "";
      runActiveQuery("example");
    });
  });

  map.on("moveend", () => {
    updateViewportState();

    if (!state.hasBooted) {
      return;
    }

    if (state.skipNextViewportRun) {
      state.skipNextViewportRun = false;
      render();
      return;
    }

    if (state.plan?.locationScope.mode === "viewport") {
      runActiveQuery("viewport move");
      return;
    }

    render();
  });
}

async function boot() {
  attachEventHandlers();
  updateViewportState();
  const plannerConnection = await detectPlannerApi();
  state.plannerApiBase = plannerConnection.apiBase;
  state.plannerHealth = plannerConnection.health;

  state.vessels = await loadVessels();
  state.dataLoadedAtMs = Date.now();
  state.catalog = buildQueryCatalog(state.vessels);
  primeFilterState(state.vessels);
  state.selectedId = state.vessels[0]?.id || null;
  state.hasBooted = true;
  runActiveQuery("boot");
}

boot().catch((error) => {
  console.error("Fleet Atlas failed to start.", error);
  SELECTORS.dataModeLabel.textContent = "Feed unavailable";
  SELECTORS.planSummary.textContent = "The planner could not initialize because the vessel feed failed to load.";
  SELECTORS.vesselList.innerHTML = `
    <article class="vesselCard">
      <div class="feedTopline">
        <h3 class="feedTitle">Unable to load vessel data</h3>
      </div>
      <p class="feedRoute">${error.message}</p>
    </article>
  `;
});
