# Phone Web GPS Fallback (POC)

This remains a dev/bench fallback. Production BBB GPS should use the serial/NMEA hardware path in `tools/bbb_hub/vehicle_hub_prod.py` with `GPS_SOURCE_POLICY=hardware_only`.

This POC lets a phone webpage push GPS into the BBB hub when dedicated GPS is unavailable.

## What it does

- BBB hub still publishes `vehicle_state` on `ws://<bbb>:8765`.
- A new ingest endpoint accepts phone GPS:
  - `POST http://<bbb>:8787/phone-gps`
- The hub applies TTL failover and source-priority policy:
  - default: `hardware_first`
  - optional: `phone_first`

When phone GPS is fresh and selected by policy, emitted payload includes:

- `gpsSource: "phone_web"`
- `_health.phoneGpsFresh`
- `_health.phoneGpsAgeMs`
- `_health.gpsSourcePolicy`

## Run BBB hub

From this repo:

```bash
tools/bbb_hub/run_sim.sh
```

Optional env:

```bash
PHONE_GPS_TOKEN=change-me \
GPS_SOURCE_POLICY=hardware_first \
PHONE_GPS_TTL_SEC=3.0 \
SIM_DISABLE_GPS=1 \
tools/bbb_hub/run_sim.sh
```

Notes:

- `SIM_DISABLE_GPS=1` is useful to force fallback testing.
- `PHONE_GPS_TOKEN` enables auth (`Authorization: Bearer <token>` or `X-Phone-Gps-Token`).

## Send phone GPS (web page)

Open:

- `tools/bbb_hub/phone_gps_sender.html`

Set:

- Ingest URL: `http://<bbb-ip>:8787/phone-gps`
- Token: same as `PHONE_GPS_TOKEN` (if configured)

Keep page open and foregrounded for reliable updates on iPhone Safari.

Hosted-page note:

- If your page is served over `https://`, browsers may block posting to `http://<bbb-ip>`.
- For internet-hosted pages, use an `https://` relay endpoint (or HTTPS reverse proxy in front of BBB ingest).

## Quick ingest test (curl)

```bash
curl -sS -X POST "http://127.0.0.1:8787/phone-gps" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer change-me" \
  -d '{
    "lat": -27.4698,
    "lng": 153.0251,
    "bearing": 180.0,
    "speedKph": 42.0,
    "accuracyM": 6.0,
    "timestampMs": 1730000000000,
    "fixValid": true,
    "headingReliable": true
  }'
```

## Safety behavior

- If phone updates stop for longer than `PHONE_GPS_TTL_SEC`, phone GPS is considered stale.
- Under `hardware_first`, hub reverts to hardware/sim GPS immediately.
- Under `phone_first`, stale phone GPS still drops out (never uses expired samples).
