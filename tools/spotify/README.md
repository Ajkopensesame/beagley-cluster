# Spotify Pairing

The cluster uses Spotify Authorization Code with PKCE because Spotify does not
offer a public device-code grant for the Web API. The app requests only
`user-read-currently-playing`; it does not request playback-control scope and
does not control Spotify playback.

For a phone-scanned QR code, the redirect URI must be HTTPS and reachable by the
phone. The helper below starts a Cloudflare quick tunnel from this Mac to the
BeagleY pairing server, prints the exact Spotify Redirect URI, opens the menu
Spotify QR panel on the BeagleY, waits for the refresh token, then removes the temporary
tunnel settings from `/etc/default/beagley-cluster.local`.

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

## Stable URL

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
