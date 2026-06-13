# Spotify Firebase Broker

This is a Firebase Functions fallback for the stable Spotify scan-to-sign-in
flow. It implements the same broker contract as the Cloudflare Worker, so the
BeagleY uses the same `BEAGLEY_SPOTIFY_BROKER_URL`,
`BEAGLEY_SPOTIFY_BROKER_TOKEN`, and `BEAGLEY_SPOTIFY_CLIENT_ID` settings.

Default production URL:

```text
https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker
```

Register this Spotify Redirect URI:

```text
https://australia-southeast1-pneumaion-prod.cloudfunctions.net/spotifyBroker/spotify/callback
```

Deploy and configure the board:

```bash
cd tools/spotify_firebase
export BEAGLEY_SPOTIFY_CLIENT_ID=...
./deploy_spotify_broker.sh --configure-beagley
```

The deploy script installs dependencies, stores the Spotify client id and
device token as Firebase Function secrets, deploys the isolated
`spotify-broker` codebase, checks `/healthz`, and optionally configures the
BeagleY.
