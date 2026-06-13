#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

BROKER_URL="${BEAGLEY_SPOTIFY_BROKER_URL:-https://spotify.pneumaion.com}"
REDIRECT_URI="${SPOTIFY_REDIRECT_URI:-$BROKER_URL/spotify/callback}"
SCOPE="${SPOTIFY_SCOPE:-user-read-currently-playing user-library-read user-library-modify}"
CF_ENV_FILE="${CLOUDFLARE_ENV_FILE:-$HOME/.config/jarvis/cloudflare.env}"
CONFIGURE_BEAGLEY=0

usage() {
  cat <<'USAGE'
Usage: deploy_spotify_broker.sh [--configure-beagley]

Environment:
  CLOUDFLARE_API_TOKEN       Cloudflare API token with Workers, KV, and route access
  CLOUDFLARE_ACCOUNT_ID      Optional Cloudflare account id
  BEAGLEY_SPOTIFY_CLIENT_ID  Spotify app client id
  BEAGLEY_SPOTIFY_BROKER_URL Broker URL, default https://spotify.pneumaion.com
  BEAGLEY_SPOTIFY_BROKER_TOKEN Optional device token; generated locally if absent

The generated device token is saved to tools/spotify_broker/.device_token with
0600 permissions and is uploaded as the Worker DEVICE_TOKEN secret.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configure-beagley)
      CONFIGURE_BEAGLEY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[spotify-broker] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

load_env_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  set -a
  # shellcheck source=/dev/null
  . "$file"
  set +a
}

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "[spotify-broker] missing $name" >&2
    exit 1
  fi
}

wrangler() {
  CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" npx --yes wrangler "$@"
}

load_env_file "$CF_ENV_FILE"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CF_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"
fi
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

if [ "${#CLOUDFLARE_API_TOKEN}" -lt 20 ]; then
  cat >&2 <<EOF
[spotify-broker] Cloudflare API token is missing or empty.
[spotify-broker] Set CLOUDFLARE_API_TOKEN or update:
[spotify-broker]   $CF_ENV_FILE
EOF
  exit 1
fi

SPOTIFY_CLIENT_ID="${BEAGLEY_SPOTIFY_CLIENT_ID:-${SPOTIFY_CLIENT_ID:-}}"
require_value "BEAGLEY_SPOTIFY_CLIENT_ID" "$SPOTIFY_CLIENT_ID"

DEVICE_TOKEN="${BEAGLEY_SPOTIFY_BROKER_TOKEN:-${DEVICE_TOKEN:-}}"
DEVICE_TOKEN_FILE="$SCRIPT_DIR/.device_token"
if [ -z "$DEVICE_TOKEN" ] && [ -f "$DEVICE_TOKEN_FILE" ]; then
  DEVICE_TOKEN="$(tr -d '\r\n' < "$DEVICE_TOKEN_FILE")"
fi
if [ -z "$DEVICE_TOKEN" ]; then
  DEVICE_TOKEN="$(node -e 'console.log(require("crypto").randomBytes(32).toString("base64url"))')"
  umask 077
  printf '%s\n' "$DEVICE_TOKEN" > "$DEVICE_TOKEN_FILE"
  chmod 0600 "$DEVICE_TOKEN_FILE"
  echo "[spotify-broker] generated device token at $DEVICE_TOKEN_FILE"
fi

NAMESPACE_TITLE="${SPOTIFY_KV_NAMESPACE_TITLE:-beagley-spotify-broker-SPOTIFY_SESSIONS}"
echo "[spotify-broker] checking Cloudflare KV namespace"
KV_LIST="$(wrangler kv namespace list --json)"
KV_ID="$(
  NAMESPACE_TITLE="$NAMESPACE_TITLE" node -e '
const fs = require("fs");
const title = process.env.NAMESPACE_TITLE;
const namespaces = JSON.parse(fs.readFileSync(0, "utf8"));
const found = namespaces.find((item) =>
  item.title === title ||
  item.title === "SPOTIFY_SESSIONS" ||
  item.title.endsWith("-SPOTIFY_SESSIONS")
);
if (found) process.stdout.write(found.id);
'
  <<< "$KV_LIST"
)"

if [ -z "$KV_ID" ]; then
  echo "[spotify-broker] creating Cloudflare KV namespace"
  CREATE_OUTPUT="$(wrangler kv namespace create SPOTIFY_SESSIONS 2>&1)"
  printf '%s\n' "$CREATE_OUTPUT"
  KV_ID="$(printf '%s\n' "$CREATE_OUTPUT" | sed -nE 's/.*id = "([^"]+)".*/\1/p' | head -1)"
fi
require_value "Cloudflare KV namespace id" "$KV_ID"

{
  printf 'name = "beagley-spotify-broker"\n'
  printf 'main = "worker.js"\n'
  printf 'compatibility_date = "2026-06-13"\n'
  if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    printf 'account_id = "%s"\n' "$CLOUDFLARE_ACCOUNT_ID"
  fi
  printf '\n'
  printf 'routes = [\n'
  printf '  { pattern = "spotify.pneumaion.com/*", zone_name = "pneumaion.com" }\n'
  printf ']\n\n'
  printf '[[kv_namespaces]]\n'
  printf 'binding = "SPOTIFY_SESSIONS"\n'
  printf 'id = "%s"\n\n' "$KV_ID"
  printf '[vars]\n'
  printf 'PUBLIC_BASE_URL = "%s"\n' "${BROKER_URL%/}"
  printf 'SPOTIFY_REDIRECT_URI = "%s"\n' "$REDIRECT_URI"
  printf 'SPOTIFY_SCOPE = "%s"\n' "$SCOPE"
} > "$SCRIPT_DIR/wrangler.toml"

echo "[spotify-broker] uploading Worker secrets"
printf '%s' "$SPOTIFY_CLIENT_ID" | wrangler secret put SPOTIFY_CLIENT_ID
printf '%s' "$DEVICE_TOKEN" | wrangler secret put DEVICE_TOKEN

echo "[spotify-broker] deploying Worker"
wrangler deploy

echo "[spotify-broker] health check"
curl -fsS "${BROKER_URL%/}/healthz" | sed -E 's/"redirect_uri":"[^"]+"/"redirect_uri":"<set>"/'
printf '\n'

if [ "$CONFIGURE_BEAGLEY" -eq 1 ]; then
  echo "[spotify-broker] configuring BeagleY"
  BEAGLEY_SPOTIFY_CLIENT_ID="$SPOTIFY_CLIENT_ID" \
  BEAGLEY_SPOTIFY_BROKER_TOKEN="$DEVICE_TOKEN" \
  "$ROOT_DIR/tools/spotify/configure_spotify_broker.py" --broker-url "${BROKER_URL%/}"
else
  echo "[spotify-broker] deploy complete; run again with --configure-beagley to install board config"
fi
