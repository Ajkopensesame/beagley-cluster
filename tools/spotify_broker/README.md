# Spotify Pairing Broker

This worker gives the cluster a permanent phone-scan Spotify login path.

The old pairing helper used a temporary Cloudflare quick tunnel, which forced a
new Spotify Redirect URI every run. Spotify requires the redirect URI in the
authorization request to exactly match a URI registered on the app, so that path
cannot be user-friendly.

The durable path is:

1. Register one Spotify Redirect URI:

   ```text
   https://spotify.pneumaion.com/spotify/callback
   ```

2. Deploy this broker at `https://spotify.pneumaion.com`.
3. Configure the BeagleY with:

   ```text
   BEAGLEY_SPOTIFY_BROKER_URL=https://spotify.pneumaion.com
   BEAGLEY_SPOTIFY_BROKER_TOKEN=<same value as worker DEVICE_TOKEN>
   BEAGLEY_SPOTIFY_CLIENT_ID=<spotify app client id>
   BEAGLEY_NOW_PLAYING_BACKEND=spotify-web
   ```

4. The cluster creates a short-lived broker session and renders a QR such as:

   ```text
   https://spotify.pneumaion.com/spotify/pair/ABC123
   ```

5. The phone signs in and approves Spotify.
6. The broker exchanges the OAuth code, the BeagleY claims the refresh token,
   and the broker deletes the session.

## Cloudflare Setup

```bash
cd tools/spotify_broker
export CLOUDFLARE_API_TOKEN=...
export BEAGLEY_SPOTIFY_CLIENT_ID=...
./deploy_spotify_broker.sh --configure-beagley
```

The deploy helper creates or reuses the `SPOTIFY_SESSIONS` KV namespace, writes
a local `wrangler.toml`, uploads Worker secrets, deploys the Worker, checks
`/healthz`, and optionally installs the matching broker config on the BeagleY.

Use a long random `DEVICE_TOKEN`; it protects the session-create and token-claim
endpoints from anything except the BeagleY. If
`BEAGLEY_SPOTIFY_BROKER_TOKEN` is not set, the helper generates one in
`.device_token` with `0600` permissions and uploads it as the Worker
`DEVICE_TOKEN` secret.

## Endpoints

- `POST /api/sessions`: BeagleY creates a pairing session. Requires
  `Authorization: Bearer <DEVICE_TOKEN>`.
- `GET /spotify/pair/<code>`: phone opens this from the QR.
- `GET /spotify/callback`: Spotify redirects here after approval.
- `GET /api/sessions/<code>`: BeagleY polls until the refresh token is ready.
  Requires the same bearer token.
- `GET /healthz`: deployment health check.
