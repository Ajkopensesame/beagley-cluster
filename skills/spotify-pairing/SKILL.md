---
name: spotify-pairing
description: Start a real Spotify QR pairing session for the BeagleY cluster by tunneling the BeagleY pairing server over HTTPS, guiding the Spotify redirect URI setup, and saving the refresh token on the board.
---

# Spotify Pairing

Use this when the user wants to scan the cluster QR code and connect their real
Spotify account for now-playing display plus the optional add-to-Liked-Songs
button. This flow requests current-playback read and library-save scope, but it
does not request playback-control scope.

Run from the canonical production checkout:

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
