#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROJECT="${FIREBASE_PROJECT:-pneumaion-prod}"
REGION="${FIREBASE_REGION:-australia-southeast1}"
FUNCTION_NAME="${FIREBASE_SPOTIFY_FUNCTION:-spotifyBroker}"
BROKER_URL="${BEAGLEY_SPOTIFY_BROKER_URL:-https://${REGION}-${PROJECT}.cloudfunctions.net/${FUNCTION_NAME}}"
REDIRECT_URI="${SPOTIFY_REDIRECT_URI:-${BROKER_URL%/}/spotify/callback}"
SCOPE="${SPOTIFY_SCOPE:-user-read-currently-playing user-library-read user-library-modify}"
CONFIGURE_BEAGLEY=0

usage() {
  cat <<'USAGE'
Usage: deploy_spotify_broker.sh [--configure-beagley]

Environment:
  FIREBASE_PROJECT             Firebase project, default pneumaion-prod
  BEAGLEY_SPOTIFY_CLIENT_ID    Spotify app client id
  BEAGLEY_SPOTIFY_BROKER_TOKEN Optional device token; generated locally if absent
  BEAGLEY_SPOTIFY_BROKER_URL   Broker base URL; defaults to the Firebase function URL

The generated device token is saved to tools/spotify_firebase/.device_token
with 0600 permissions and uploaded as the Firebase function secret.
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
      echo "[spotify-firebase] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "[spotify-firebase] missing $name" >&2
    exit 1
  fi
}

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
  echo "[spotify-firebase] generated device token at $DEVICE_TOKEN_FILE"
fi

cat > "$SCRIPT_DIR/functions/.env.$PROJECT" <<EOF
PUBLIC_BASE_URL=${BROKER_URL%/}
SPOTIFY_REDIRECT_URI=$REDIRECT_URI
SPOTIFY_SCOPE=$SCOPE
EOF

echo "[spotify-firebase] installing function dependencies"
npm --prefix "$SCRIPT_DIR/functions" install

echo "[spotify-firebase] uploading function secrets"
printf '%s' "$SPOTIFY_CLIENT_ID" \
  | firebase functions:secrets:set SPOTIFY_CLIENT_ID --project "$PROJECT" --data-file - --force
printf '%s' "$DEVICE_TOKEN" \
  | firebase functions:secrets:set BEAGLEY_SPOTIFY_BROKER_TOKEN --project "$PROJECT" --data-file - --force

echo "[spotify-firebase] deploying $FUNCTION_NAME to $PROJECT"
firebase deploy --project "$PROJECT" --config "$SCRIPT_DIR/firebase.json" --only functions --non-interactive

echo "[spotify-firebase] health check"
curl -fsS "${BROKER_URL%/}/healthz" | sed -E 's/"redirect_uri":"[^"]+"/"redirect_uri":"<set>"/'
printf '\n'

if [ "$CONFIGURE_BEAGLEY" -eq 1 ]; then
  echo "[spotify-firebase] configuring BeagleY"
  BEAGLEY_SPOTIFY_CLIENT_ID="$SPOTIFY_CLIENT_ID" \
  BEAGLEY_SPOTIFY_BROKER_TOKEN="$DEVICE_TOKEN" \
  "$ROOT_DIR/tools/spotify/configure_spotify_broker.py" --broker-url "${BROKER_URL%/}"
else
  echo "[spotify-firebase] deploy complete; run again with --configure-beagley to install board config"
fi
