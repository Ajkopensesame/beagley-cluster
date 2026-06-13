---
name: spotify-pairing
description: Start or debug Spotify QR pairing for the BeagleY cluster, preferring the stable pairing broker and falling back to the legacy tunnel helper only for lab recovery.
---

# Spotify Pairing

Use this when the user wants to scan the cluster QR code and connect their real
Spotify account for now-playing display plus the optional add-to-Liked-Songs
button. This flow requests current-playback read and library-save scope, but it
does not request playback-control scope.

Preferred production path: configure a stable broker and set these BeagleY
local env keys. The current deployed fallback is the Firebase Functions broker
from `tools/spotify_firebase`:

```text
BEAGLEY_SPOTIFY_BROKER_URL=https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker
BEAGLEY_SPOTIFY_BROKER_TOKEN=...
BEAGLEY_SPOTIFY_CLIENT_ID=...
BEAGLEY_NOW_PLAYING_BACKEND=spotify-web
```

Register this Spotify Redirect URI once:

```text
https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker/spotify/callback
```

The cleaner custom-domain target is the Cloudflare Worker broker in
`tools/spotify_broker`, normally `https://spotify.pneumaion.com`, once
Cloudflare Worker/KV auth is available.

With broker mode enabled, the user only scans the cluster QR, signs in, and
approves Spotify. Use the legacy tunnel helper only when the broker is not
deployed or when recovering a lab board:

```bash
tools/spotify/pair_spotify.py --client-id YOUR_SPOTIFY_CLIENT_ID
```

The helper:

- resolves the BeagleY through `skills/beagley-common`
- starts a `cloudflared` quick tunnel to the BeagleY pairing server
- prints the exact Spotify Redirect URI to add in
  <https://developer.spotify.com/dashboard>
- opens the menu Spotify QR panel on the cluster
- waits for a fresh `BEAGLEY_SPOTIFY_REFRESH_TOKEN` on the BeagleY
- removes temporary tunnel/autostart/QML-dev/screenshot env keys after pairing

For a stable HTTPS tunnel/domain:

```bash
tools/spotify/pair_spotify.py \
  --client-id YOUR_SPOTIFY_CLIENT_ID \
  --public-url https://your-stable-domain.example
```

Spotify's current redirect rules require HTTPS for non-loopback redirects. A
phone-scanned QR cannot use a Mac or BeagleY `127.0.0.1` callback, because that
loopback address would point at the phone.
