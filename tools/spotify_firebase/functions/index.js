const crypto = require("crypto");
const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

admin.initializeApp();

const db = admin.firestore();
const spotifyClientIdSecret = defineSecret("SPOTIFY_CLIENT_ID");
const brokerTokenSecret = defineSecret("BEAGLEY_SPOTIFY_BROKER_TOKEN");

const DEFAULT_SCOPE = "user-read-currently-playing user-library-read user-library-modify";
const SESSION_TTL_SECONDS = 15 * 60;
const SESSION_COLLECTION = "spotifyPairingSessions";
const STATE_COLLECTION = "spotifyPairingStates";
const DEFAULT_PUBLIC_BASE_URL = "https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker";

function json(res, status, data) {
  res.status(status).set("content-type", "application/json; charset=utf-8").send(JSON.stringify(data));
}

function html(res, status, body) {
  res.status(status).set("content-type", "text/html; charset=utf-8").send(body);
}

function base64Url(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

function randomCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.randomBytes(8);
  let code = "";
  for (let i = 0; i < 6; i += 1) {
    code += alphabet[bytes[i] % alphabet.length];
  }
  return code;
}

function codeChallenge(verifier) {
  return crypto.createHash("sha256").update(verifier).digest("base64url");
}

function secretValue(secret) {
  try {
    return secret.value().trim();
  } catch (_) {
    return "";
  }
}

function spotifyClientId() {
  return secretValue(spotifyClientIdSecret);
}

function configuredDeviceToken() {
  return secretValue(brokerTokenSecret);
}

function bearerToken(req) {
  const header = req.get("authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

function authFailure(req) {
  const configured = configuredDeviceToken();
  if (!configured) {
    return { status: 500, payload: { error: "missing_device_token" } };
  }
  if (bearerToken(req) !== configured) {
    return { status: 401, payload: { error: "unauthorized" } };
  }
  return null;
}

function publicBaseUrl() {
  return (process.env.PUBLIC_BASE_URL || DEFAULT_PUBLIC_BASE_URL).replace(/\/+$/, "");
}

function redirectUri() {
  return process.env.SPOTIFY_REDIRECT_URI || `${publicBaseUrl()}/spotify/callback`;
}

function requestPath(req) {
  const url = new URL(req.originalUrl || req.url || "/", publicBaseUrl());
  let path = url.pathname.replace(/\/+$/, "") || "/";
  if (path === "/spotifyBroker") {
    return "/";
  }
  if (path.startsWith("/spotifyBroker/")) {
    path = path.slice("/spotifyBroker".length);
  }
  return path || "/";
}

function sessionRef(pairCode) {
  return db.collection(SESSION_COLLECTION).doc(pairCode);
}

function stateRef(state) {
  return db.collection(STATE_COLLECTION).doc(state);
}

async function writeSession(session) {
  const batch = db.batch();
  batch.set(sessionRef(session.pair_code), session, { merge: false });
  batch.set(stateRef(session.state), {
    pair_code: session.pair_code,
    expires_at_ms: session.expires_at_ms,
  }, { merge: false });
  await batch.commit();
}

async function deleteSession(session) {
  const batch = db.batch();
  batch.delete(sessionRef(session.pair_code));
  if (session.state) {
    batch.delete(stateRef(session.state));
  }
  await batch.commit();
}

async function readSession(pairCode) {
  const snap = await sessionRef(pairCode).get();
  if (!snap.exists) {
    return null;
  }
  const session = snap.data();
  if (!session || session.expires_at_ms <= Date.now()) {
    await deleteSession({ pair_code: pairCode, state: session ? session.state : "" });
    return null;
  }
  return session;
}

async function requestJson(req) {
  if (req.body && typeof req.body === "object") {
    return req.body;
  }
  if (Buffer.isBuffer(req.rawBody) && req.rawBody.length > 0) {
    try {
      return JSON.parse(req.rawBody.toString("utf8"));
    } catch (_) {
      return {};
    }
  }
  return {};
}

async function createSession(req, res) {
  const failure = authFailure(req);
  if (failure) {
    return json(res, failure.status, failure.payload);
  }

  const clientId = spotifyClientId();
  if (!clientId) {
    return json(res, 500, { error: "missing_spotify_client_id" });
  }

  const body = await requestJson(req);
  const pairCode = randomCode();
  const verifier = base64Url(crypto.randomBytes(64));
  const state = base64Url(crypto.randomBytes(24));
  const expiresAtMs = Date.now() + SESSION_TTL_SECONDS * 1000;
  const session = {
    pair_code: pairCode,
    state,
    code_verifier: verifier,
    code_challenge: codeChallenge(verifier),
    scope: body.scope || process.env.SPOTIFY_SCOPE || DEFAULT_SCOPE,
    status: "pending",
    created_at: new Date().toISOString(),
    expires_at: new Date(expiresAtMs).toISOString(),
    expires_at_ms: expiresAtMs,
  };

  await writeSession(session);
  return json(res, 200, {
    status: "pending",
    pair_code: pairCode,
    pair_url: `${publicBaseUrl()}/spotify/pair/${pairCode}`,
    expires_in: SESSION_TTL_SECONDS,
  });
}

async function startPairing(pairCode, res) {
  const session = await readSession(pairCode);
  if (!session) {
    return html(res, 404, "<html><body>Spotify pairing link expired.</body></html>");
  }

  const url = new URL("https://accounts.spotify.com/authorize");
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", spotifyClientId());
  url.searchParams.set("scope", session.scope || process.env.SPOTIFY_SCOPE || DEFAULT_SCOPE);
  url.searchParams.set("redirect_uri", redirectUri());
  url.searchParams.set("state", session.state);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("code_challenge", session.code_challenge);
  res.redirect(302, url.toString());
}

async function handleCallback(req, res) {
  const url = new URL(req.originalUrl || req.url || "/", publicBaseUrl());
  const state = url.searchParams.get("state") || "";
  const code = url.searchParams.get("code") || "";
  const denied = url.searchParams.get("error") || "";
  if (!state) {
    return json(res, 400, { error: "missing state" });
  }

  const stateSnap = await stateRef(state).get();
  if (!stateSnap.exists) {
    return html(res, 410, "<html><body>Spotify pairing expired. Start again from the cluster.</body></html>");
  }

  const pairCode = stateSnap.data().pair_code;
  const session = await readSession(pairCode);
  if (!session) {
    return html(res, 410, "<html><body>Spotify pairing expired. Start again from the cluster.</body></html>");
  }

  if (denied) {
    session.status = "denied";
    session.error = denied;
    await writeSession(session);
    return html(res, 400, "<html><body>Spotify pairing was cancelled.</body></html>");
  }
  if (!code) {
    session.status = "failed";
    session.error = "missing_code";
    await writeSession(session);
    return json(res, 400, { error: "missing code" });
  }

  const form = new URLSearchParams();
  form.set("grant_type", "authorization_code");
  form.set("code", code);
  form.set("redirect_uri", redirectUri());
  form.set("client_id", spotifyClientId());
  form.set("code_verifier", session.code_verifier);

  const tokenReply = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/x-www-form-urlencoded",
      "user-agent": "BeagleySpotifyFirebaseBroker/1.0",
    },
    body: form.toString(),
  });
  const payload = await tokenReply.json().catch(() => ({}));
  if (!tokenReply.ok || !payload.refresh_token || !payload.access_token) {
    session.status = "failed";
    session.error = "token_exchange_failed";
    session.spotify_status = tokenReply.status;
    await writeSession(session);
    return html(res, 502, "<html><body>Spotify token exchange failed. Start again from the cluster.</body></html>");
  }

  session.status = "ready";
  session.access_token = payload.access_token;
  session.refresh_token = payload.refresh_token;
  session.expires_in = payload.expires_in || 3600;
  session.completed_at = new Date().toISOString();
  await writeSession(session);

  return html(res, 200, "<html><body><h1>Spotify paired</h1><p>You can return to the cluster.</p></body></html>");
}

async function pollSession(req, pairCode, res) {
  const failure = authFailure(req);
  if (failure) {
    return json(res, failure.status, failure.payload);
  }

  const session = await readSession(pairCode);
  if (!session) {
    return json(res, 404, { error: "not_found" });
  }
  if (session.status !== "ready") {
    return json(res, session.status === "failed" || session.status === "denied" ? 409 : 202, {
      status: session.status || "pending",
      error: session.error || "",
      expires_at: session.expires_at,
    });
  }

  const response = {
    status: "ready",
    client_id: spotifyClientId(),
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in || 3600,
  };
  await deleteSession(session);
  return json(res, 200, response);
}

exports.spotifyBroker = onRequest({
  region: "australia-southeast1",
  timeoutSeconds: 60,
  memory: "256MiB",
  maxInstances: 5,
  cors: false,
  invoker: "public",
  secrets: [spotifyClientIdSecret, brokerTokenSecret],
}, async (req, res) => {
  try {
    const path = requestPath(req);
    if (req.method === "GET" && path === "/healthz") {
      return json(res, 200, {
        ok: true,
        firestore_configured: Boolean(db),
        spotify_client_id_configured: Boolean(spotifyClientId()),
        device_token_configured: Boolean(configuredDeviceToken()),
        redirect_uri: redirectUri(),
      });
    }
    if (req.method === "POST" && path === "/api/sessions") {
      return createSession(req, res);
    }
    if (req.method === "GET" && path.startsWith("/api/sessions/")) {
      return pollSession(req, decodeURIComponent(path.slice("/api/sessions/".length)), res);
    }
    if (req.method === "GET" && path.startsWith("/spotify/pair/")) {
      return startPairing(decodeURIComponent(path.slice("/spotify/pair/".length)), res);
    }
    if (req.method === "GET" && path === "/spotify/callback") {
      return handleCallback(req, res);
    }
    return json(res, 404, { error: "not_found" });
  } catch (error) {
    console.error("spotifyBroker failed", error);
    return json(res, 500, { error: "internal_error" });
  }
});
