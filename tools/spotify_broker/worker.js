const DEFAULT_SCOPE = "user-read-currently-playing user-library-read user-library-modify";
const SESSION_TTL_SECONDS = 15 * 60;

function json(data, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(data), { ...init, headers });
}

function html(body, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set("content-type", "text/html; charset=utf-8");
  return new Response(body, { ...init, headers });
}

function badRequest(message) {
  return json({ error: message }, { status: 400 });
}

function unauthorized() {
  return json({ error: "unauthorized" }, { status: 401 });
}

function notFound() {
  return json({ error: "not_found" }, { status: 404 });
}

function bearerToken(request) {
  const header = request.headers.get("authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

function configuredDeviceToken(env) {
  return (env.DEVICE_TOKEN || env.BEAGLEY_SPOTIFY_BROKER_TOKEN || "").trim();
}

function deviceAuthFailure(request, env) {
  const configured = configuredDeviceToken(env);
  if (!configured) {
    return json({ error: "missing_device_token" }, { status: 500 });
  }
  if (bearerToken(request) !== configured) {
    return unauthorized();
  }
  return null;
}

function randomBytes(length) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

function base64Url(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function randomCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(8);
  let code = "";
  for (let i = 0; i < 6; i += 1) {
    code += alphabet[bytes[i] % alphabet.length];
  }
  return code;
}

async function codeChallenge(verifier) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
}

function publicBaseUrl(request, env) {
  const configured = (env.PUBLIC_BASE_URL || "").replace(/\/+$/, "");
  if (configured) {
    return configured;
  }
  const url = new URL(request.url);
  return `${url.protocol}//${url.host}`;
}

function redirectUri(request, env) {
  const configured = env.SPOTIFY_REDIRECT_URI || "";
  if (configured) {
    return configured;
  }
  return `${publicBaseUrl(request, env)}/spotify/callback`;
}

function sessionKey(code) {
  return `spotify:pair:${code}`;
}

function stateKey(state) {
  return `spotify:state:${state}`;
}

async function readSession(env, code) {
  const raw = await env.SPOTIFY_SESSIONS.get(sessionKey(code));
  return raw ? JSON.parse(raw) : null;
}

async function writeSession(env, session) {
  await env.SPOTIFY_SESSIONS.put(sessionKey(session.pair_code), JSON.stringify(session), {
    expirationTtl: SESSION_TTL_SECONDS,
  });
  await env.SPOTIFY_SESSIONS.put(stateKey(session.state), session.pair_code, {
    expirationTtl: SESSION_TTL_SECONDS,
  });
}

async function deleteSession(env, session) {
  await env.SPOTIFY_SESSIONS.delete(sessionKey(session.pair_code));
  await env.SPOTIFY_SESSIONS.delete(stateKey(session.state));
}

async function createSession(request, env) {
  const authFailure = deviceAuthFailure(request, env);
  if (authFailure) {
    return authFailure;
  }
  if (!env.SPOTIFY_SESSIONS) {
    return json({ error: "missing_kv_binding" }, { status: 500 });
  }

  const clientId = env.SPOTIFY_CLIENT_ID || "";
  if (!clientId) {
    return json({ error: "missing_spotify_client_id" }, { status: 500 });
  }

  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }

  const pairCode = randomCode();
  const verifier = base64Url(randomBytes(64));
  const state = base64Url(randomBytes(24));
  const session = {
    pair_code: pairCode,
    state,
    code_verifier: verifier,
    code_challenge: await codeChallenge(verifier),
    scope: body.scope || env.SPOTIFY_SCOPE || DEFAULT_SCOPE,
    status: "pending",
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + SESSION_TTL_SECONDS * 1000).toISOString(),
  };

  await writeSession(env, session);
  return json({
    status: "pending",
    pair_code: pairCode,
    pair_url: `${publicBaseUrl(request, env)}/spotify/pair/${pairCode}`,
    expires_in: SESSION_TTL_SECONDS,
  });
}

async function startPairing(request, env, pairCode) {
  const session = await readSession(env, pairCode);
  if (!session) {
    return html("<html><body>Spotify pairing link expired.</body></html>", { status: 404 });
  }

  const url = new URL("https://accounts.spotify.com/authorize");
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", env.SPOTIFY_CLIENT_ID || "");
  url.searchParams.set("scope", session.scope || env.SPOTIFY_SCOPE || DEFAULT_SCOPE);
  url.searchParams.set("redirect_uri", redirectUri(request, env));
  url.searchParams.set("state", session.state);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("code_challenge", session.code_challenge);
  return Response.redirect(url.toString(), 302);
}

async function handleCallback(request, env) {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") || "";
  const code = url.searchParams.get("code") || "";
  const denied = url.searchParams.get("error") || "";
  if (!state) {
    return badRequest("missing state");
  }

  const pairCode = await env.SPOTIFY_SESSIONS.get(stateKey(state));
  if (!pairCode) {
    return html("<html><body>Spotify pairing expired. Start again from the cluster.</body></html>", { status: 410 });
  }

  const session = await readSession(env, pairCode);
  if (!session) {
    return html("<html><body>Spotify pairing expired. Start again from the cluster.</body></html>", { status: 410 });
  }

  if (denied) {
    session.status = "denied";
    session.error = denied;
    await writeSession(env, session);
    return html("<html><body>Spotify pairing was cancelled.</body></html>", { status: 400 });
  }
  if (!code) {
    session.status = "failed";
    session.error = "missing_code";
    await writeSession(env, session);
    return badRequest("missing code");
  }

  const form = new URLSearchParams();
  form.set("grant_type", "authorization_code");
  form.set("code", code);
  form.set("redirect_uri", redirectUri(request, env));
  form.set("client_id", env.SPOTIFY_CLIENT_ID || "");
  form.set("code_verifier", session.code_verifier);

  const tokenReply = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/x-www-form-urlencoded",
      "user-agent": "BeagleySpotifyBroker/1.0",
    },
    body: form.toString(),
  });
  const payload = await tokenReply.json().catch(() => ({}));
  if (!tokenReply.ok || !payload.refresh_token || !payload.access_token) {
    session.status = "failed";
    session.error = "token_exchange_failed";
    session.spotify_status = tokenReply.status;
    await writeSession(env, session);
    return html("<html><body>Spotify token exchange failed. Start again from the cluster.</body></html>", { status: 502 });
  }

  session.status = "ready";
  session.access_token = payload.access_token;
  session.refresh_token = payload.refresh_token;
  session.expires_in = payload.expires_in || 3600;
  session.completed_at = new Date().toISOString();
  await writeSession(env, session);

  return html("<html><body><h1>Spotify paired</h1><p>You can return to the cluster.</p></body></html>");
}

async function pollSession(request, env, pairCode) {
  const authFailure = deviceAuthFailure(request, env);
  if (authFailure) {
    return authFailure;
  }
  const session = await readSession(env, pairCode);
  if (!session) {
    return notFound();
  }
  if (session.status !== "ready") {
    return json({
      status: session.status || "pending",
      error: session.error || "",
      expires_at: session.expires_at,
    }, { status: session.status === "failed" || session.status === "denied" ? 409 : 202 });
  }

  const response = json({
    status: "ready",
    client_id: env.SPOTIFY_CLIENT_ID || "",
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in || 3600,
  });
  await deleteSession(env, session);
  return response;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/healthz") {
      return json({
        ok: true,
        kv_configured: Boolean(env.SPOTIFY_SESSIONS),
        spotify_client_id_configured: Boolean(env.SPOTIFY_CLIENT_ID),
        device_token_configured: Boolean(configuredDeviceToken(env)),
        redirect_uri: redirectUri(request, env),
      });
    }
    if (request.method === "POST" && path === "/api/sessions") {
      return createSession(request, env);
    }
    if (request.method === "GET" && path.startsWith("/api/sessions/")) {
      return pollSession(request, env, decodeURIComponent(path.slice("/api/sessions/".length)));
    }
    if (request.method === "GET" && path.startsWith("/spotify/pair/")) {
      return startPairing(request, env, decodeURIComponent(path.slice("/spotify/pair/".length)));
    }
    if (request.method === "GET" && path === "/spotify/callback") {
      return handleCallback(request, env);
    }

    return notFound();
  },
};
