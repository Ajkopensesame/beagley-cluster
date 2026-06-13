# Spotify Pairing

The cluster uses Spotify Authorization Code with PKCE because Spotify does not
offer a public device-code grant for the Web API. The app requests
`user-read-currently-playing` and `user-library-modify`, so it can show the
current track and save that track to Liked Songs. It still does not request
playback-control scope and does not control Spotify playback.

For a phone-scanned QR code, the redirect URI must be HTTPS and must exactly
match a URI registered on the Spotify app. The current deployed broker is the
Firebase Functions fallback in `tools/spotify_firebase`:

```text
https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker
```

Register this Spotify Redirect URI once:

```text
https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker/spotify/callback
```

The cleaner custom-domain target remains the Cloudflare Worker broker in
`tools/spotify_broker`, normally deployed at:

```text
https://spotify.pneumaion.com
```

Then configure the BeagleY local env:

```text
BEAGLEY_SPOTIFY_BROKER_URL=https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker
BEAGLEY_SPOTIFY_BROKER_TOKEN=...
BEAGLEY_SPOTIFY_CLIENT_ID=...
BEAGLEY_NOW_PLAYING_BACKEND=spotify-web
```

The helper for this is:

```bash
tools/spotify/configure_spotify_broker.py \
  --broker-url https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker \
  --client-id YOUR_SPOTIFY_CLIENT_ID \
  --broker-token YOUR_LONG_RANDOM_DEVICE_TOKEN
```

With those keys present, the QR shown on the cluster creates a short-lived
broker session. The user only scans, signs in, and approves Spotify. No
per-session dashboard edit is required.

The legacy helper below remains useful for lab recovery. It starts a Cloudflare
quick tunnel from this Mac to the BeagleY pairing server, but every quick tunnel
prints a new Redirect URI that must be added to the Spotify dashboard before the
phone scan can complete.

## One-time Pairing

1. Create a Spotify app at <https://developer.spotify.com/dashboard> and copy
   the app's Client ID.
2. Run:

   ```bash
   tools/spotify/pair_spotify.py --client-id YOUR_SPOTIFY_CLIENT_ID
   ```

3. The helper prints an exact Redirect URI like:

   ```text
   https://example.trycloudflare.com/spotify/callback
   ```

   Add that exact URI to the Spotify app in the dashboard and save it.
4. Press Enter in the helper.
5. Scan the QR in the BeagleY menu and approve Spotify.

The helper leaves the BeagleY with:

```text
BEAGLEY_NOW_PLAYING_BACKEND=spotify-web
BEAGLEY_NOW_PLAYING_SOURCE_LABEL=Spotify
BEAGLEY_SPOTIFY_CLIENT_ID=...
BEAGLEY_SPOTIFY_REFRESH_TOKEN=...
```

Temporary redirect, tunnel, QR autostart, and screenshot/QML-dev keys are
removed after pairing completes.

## Board Status

The cluster writes its current now-playing state to:

```text
/run/beagley-nowplaying/state.json
```

On the BeagleY, inspect the cached state with:

```bash
nowplayingctl status
```

Useful states:

- `playing`: Spotify returned a current track or episode and playback is active.
- `paused`: Spotify returned a current track or episode, but it is paused.
- `idle`: Spotify is paired, but Spotify returned no active playback.
- `auth_required`: the saved login is missing or expired.
- `permission_required`: Spotify rejected the current scope/account permissions.
- `offline`: network/API access failed or Spotify returned an unavailable state.

Use `nowplayingctl status --json` when a script needs the exact cached payload.

## Stable URL Fallback

Cloudflare quick tunnel URLs are temporary. For repeat pairing without changing
the Spotify dashboard each time, use a stable HTTPS tunnel/domain and run:

```bash
tools/spotify/pair_spotify.py \
  --client-id YOUR_SPOTIFY_CLIENT_ID \
  --public-url https://your-stable-domain.example
```

Register this Redirect URI once in Spotify:

```text
https://your-stable-domain.example/spotify/callback
```
