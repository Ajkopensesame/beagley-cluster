# Beagley Wi-Fi Architecture (BBB + Maps)

## Recommended topology

- **Beagley (`10.24.0.46`)**
  - Runs UI cluster app
  - Keeps **USB recovery** on `usb0` (`192.168.7.2`)
  - Uses **Ethernet (`eth0`)** either for home-router/dev access or as the BBB gateway link
  - Uses **Wi-Fi (`wlan0`)** for internet/map tile access
  - Uses `VEHICLE_HUB_WS_URL` to read BBB state feed
- **BBB (`10.24.0.7`)**
  - Handles Arduino serial (`/dev/ttyACM0`)
  - Owns the production serial GPS receiver over direct NMEA on the BBB
  - Publishes `vehicle_state` WebSocket feed on `:8765`
  - Can stay on Ethernet for stable local telemetry link

This keeps map/network concerns on Beagley and IO/sensor concerns on BBB.

## Why this is the right split

- Beagley already has working onboard Wi-Fi (`wlan0`, TI `cc33xx`).
- BBB USB dongle support/power is less reliable.
- UI and maps run on Beagley anyway (`src/main.cpp`, MapLibre web view path).
- Vehicle data path is already separated via WebSocket (`src/data/VehicleStateClient.cpp`).

## Existing runtime hooks in code

- `VehicleStateClient` reads:
  - `VEHICLE_HUB_WS_URL` (default `ws://10.24.0.7:8765`)
- Map behavior reads:
  - `BEAGLEY_NO_MAP`
  - `BEAGLEY_FORCE_SNAPSHOT_MAP`
  - `BEAGLEY_MAP_STYLE_URL`
  - `BEAGLEY_MAP_USER_AGENT`

## One-time Wi-Fi setup on Beagley

On your dev machine:

```bash
# Preferred when Ethernet is up:
scp /Users/joshkomant/projects/beagley-cluster/tools/beagley_wifi/setup_wifi.sh debian@10.24.0.46:/tmp/
ssh debian@10.24.0.46

# Recovery path if Ethernet is broken:
# scp /Users/joshkomant/projects/beagley-cluster/tools/beagley_wifi/setup_wifi.sh debian@192.168.7.2:/tmp/
# ssh debian@192.168.7.2

sudo bash /tmp/setup_wifi.sh \
  --ssid "<YOUR_SSID>" \
  --psk "<YOUR_PASSWORD>" \
  --profile-id "primary-hotspot" \
  --priority 100 \
  --bbb-host 10.24.0.7 \
  --host-name beagley
```

The script configures:

- `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`
- `/etc/systemd/network/wlan0.network`
- `/etc/systemd/network/eth0.network`
- `/etc/systemd/system/beagley-hotspot-reconcile.{service,timer}`
- `/etc/systemd/system/beagley-hotspot-watchdog.{service,timer}`
- host name `beagley` so the board is reachable as `beagley.local`
- `/etc/hosts` so `sudo` and local services resolve `beagley` cleanly
- Avahi `_ssh._tcp` advertisement when `avahi-daemon` is installed
- `wpa_supplicant@wlan0.service` (enabled + restarted)
- `ssh.service` (enabled)
- hotspot-specific fallback IPs reconciled from the active saved hotspot profile
- persistent `wlan0` power-save policy (`off` by default for hotspot stability)
- gateway watchdog that auto-recovers `wlan0` if association, DHCP, or the TI
  CC33xx driver gets stuck after beacon loss
- optional BBB gateway mode on `eth0` with persistent IPv4 forwarding
- network state reloaded without bouncing the active Ethernet SSH session

For multiple saved hotspots, provide a TSV file:

```bash
sudo bash /tmp/setup_wifi.sh \
  --profiles-file /tmp/hotspot_profiles.tsv \
  --bbb-host 10.24.0.7 \
  --host-name beagley
```

TSV format:

```text
# id    ssid    psk    priority    fallback_address
iphone-primary	Josh’s iPhone	qwer1234	100	172.20.10.6/28
garage-backup	GarageWiFi	anotherpass	80
```

The saved hotspot set is written as annotated `network={}` blocks in `wpa_supplicant`, each with:

- `id_str`
- `priority`
- optional `fallback` metadata used by the reconcile timer

To make the Beagley the BBB's hotspot gateway:

```bash
sudo bash /tmp/setup_wifi.sh \
  --ssid "<YOUR_SSID>" \
  --psk "<YOUR_PASSWORD>" \
  --profile-id "primary-hotspot" \
  --priority 100 \
  --fallback-address 172.20.10.6/28 \
  --bbb-gateway-enable \
  --bbb-gateway-address 10.24.0.46/24 \
  --bbb-host 10.24.0.7 \
  --host-name beagley
```

Hotspot hardening flags (recommended):

```bash
sudo bash /tmp/setup_wifi.sh \
  --ssid "<YOUR_SSID>" \
  --psk "<YOUR_PASSWORD>" \
  --profile-id "primary-hotspot" \
  --priority 100 \
  --wifi-power-save off \
  --gateway-watchdog-enable \
  --gateway-watchdog-interval-sec 15 \
  --gateway-watchdog-failures 3 \
  --gateway-watchdog-cooldown-sec 45 \
  --gateway-watchdog-target auto \
  --bbb-host 10.24.0.7 \
  --host-name beagley
```

Gateway-mode contract:

- Beagley `eth0` is static on `10.24.0.46/24`
- BBB stays on `10.24.0.7/24`
- BBB default gateway must be `10.24.0.46`
- `wlan0` keeps hotspot DHCP and enables IPv4 masquerade for BBB egress

## Production profile contract

- Treat hotspot credentials as **OS-preprovisioned**, not app-managed.
- Maintain an **ordered known list** of saved hotspots instead of one active hotspot at a time.
- Standardize on an **ASCII SSID/password** for the deployed hotspot profile to avoid punctuation/unicode edge cases.
- In BBB gateway mode, treat `eth0` as the local static BBB link instead of a DHCP dev uplink.
- Keep `RouteMetric=200` on `wlan0` so the BBB/local telemetry path stays preferred.
- Keep the USB gadget path on `192.168.7.2` untouched as the last-resort recovery channel.
- Keep the host name stable as `beagley` so SSH works as `debian@beagley.local` when mDNS is available.
- Only assign hotspot-side SSH fallback addresses for explicitly configured known hotspots.
- Leave `fallback_address` empty for normal DHCP-first operation; only set it for hotspot profiles where you explicitly want a deterministic SSH alias.
- The in-app Wi-Fi overlay is **diagnostics-only by default**.
  - To allow bench provisioning from the UI, set `BEAGLEY_WIFI_ALLOW_UI_CONFIG=1`.

## Run the cluster against BBB feed

From this repo on Beagley:

```bash
VEHICLE_HUB_WS_URL=ws://10.24.0.7:8765 BEAGLEY_UI_VARIANT=v3 ./run_1920x720.sh
```

Optional overrides:

```bash
BEAGLEY_WIFI_INTERFACE=wlan0 \
BEAGLEY_INTERNET_CHECK_URL=https://connectivitycheck.gstatic.com/generate_204 \
VEHICLE_HUB_WS_URL=ws://10.24.0.7:8765 \
BEAGLEY_UI_VARIANT=v3 \
./run_1920x720.sh
```

## Verification checklist

On Beagley:

```bash
ip -br a
networkctl status eth0
iw dev wlan0 link
ping -c 2 10.24.0.7
ping -c 2 8.8.8.8
```

Expected shape:

- `usb0` remains reachable at `192.168.7.2/24`
- `eth0` is either a DHCP dev uplink or the static BBB gateway link (`10.24.0.46/24`)
- `wlan0` uses DHCP with the hotspot route metric of `200`
- `wpa_supplicant@wlan0.service` is `enabled` and `active`
- `beagley-hotspot-watchdog.timer` is `enabled` and `active`
- the highest-priority saved hotspot in range is selected automatically
- when Wi-Fi loses carrier, stale DHCP addresses are cleared from `wlan0` so
  the Ethernet MAC does not appear to own the Wi-Fi reservation
- ARP flux protection is enabled so `eth0` and `wlan0` do not answer ARP for
  each other's home-router leases
- hotspot SSH can use the configured fallback address for that known hotspot if `.local` resolution is unavailable
- in BBB gateway mode, `net.ipv4.ip_forward=1` and BBB traffic egresses through `wlan0`

Recovery contract:

- `wpa_supplicant@wlan0` failures with `Could not set interface wlan0 flags (UP): Device or resource busy`
  are treated as CC33xx driver-stuck states.
- The watchdog first tries DHCP/networkd refresh for lease-only failures.
- For not-associated/scanning states, the watchdog clears stale Wi-Fi DHCP
  state, waits through a grace threshold, then does a bounded CC33xx radio
  reset instead of either resetting constantly or waiting forever.
- For supplicant/driver failures it stops supplicant, unloads/reloads
  `cc33xx_sdio cc33xx`, restarts `systemd-networkd`, resets the failed
  supplicant state, and starts `wpa_supplicant@wlan0` again.
- Internet probe failure alone does not force a radio reset unless
  `REQUIRE_INTERNET=1` is set in `/etc/default/beagley-hotspot-watchdog`.

In app logs:

- `VehicleStateClient connecting to ws://10.24.0.7:8765`
- map panel loads tiles (no dead center pod)

## BBB hardware GPS production path

On the BBB, use the production hub entrypoint instead of the sim runner:

```bash
cd /home/debian/projects/beagley-cluster/tools/bbb_hub
BBB_GPS_DEVICE=/dev/ttyS4 \
BBB_GPS_BAUD=9600 \
BBB_GPS_READ_TIMEOUT_MS=200 \
BBB_GPS_STALE_MS=2000 \
BBB_GPS_MIN_HEADING_SPEED_KPH=7.0 \
GPS_SOURCE_POLICY=hardware_only \
bash ./run_prod.sh
```

Production defaults:

- `gpsSource` is always `hardware`
- no phone-web fallback is selected in production
- `vehicle_state` stays on `ws://0.0.0.0:8765`
- `_health` may include `gpsStale`, `gpsSerialOk`, `gpsAgeMs`, `gpsParseErrors`, `gpsDevice`, and `gpsLastError`

Systemd install:

```bash
sudo cp /home/debian/projects/beagley-cluster/tools/bbb_hub/bbb-hardware-gps.service /etc/systemd/system/
sudo cp /home/debian/projects/beagley-cluster/tools/bbb_hub/bbb-hardware-gps.env.example /etc/default/bbb-hardware-gps
sudo systemctl daemon-reload
sudo systemctl enable --now bbb-hardware-gps.service
```

Verification on the BBB:

```bash
sudo systemctl status bbb-hardware-gps.service
journalctl -u bbb-hardware-gps.service -n 50 --no-pager
```

Verification from Beagley:

```bash
/home/debian/projects/beagley-cluster/tools/bbb_hub/.venv/bin/python - <<'PY'
import asyncio, json, websockets
async def main():
    async with websockets.connect("ws://10.24.0.7:8765") as ws:
        msg = json.loads(await ws.recv())
        print(json.dumps({
            "gpsSource": msg.get("gpsSource"),
            "gps": msg.get("gps"),
            "_health": msg.get("_health"),
        }, indent=2))
asyncio.run(main())
PY
```

Expected production behavior:

- `gpsSource` is `hardware`
- `gps.fixValid` is `true` only with a real receiver fix
- `gps.fixValid=false` or `_health.gpsStale=true` keeps Beagley navigation in `no_gps` / degraded mode without switching to phone GPS

## Control-path diagnostic (ASCII vs Unicode SSID)

If Wi-Fi setup reports config saved but association is not completed:

1. Try connecting to a simple ASCII SSID (letters/numbers only) with known-good password.
2. Then try the target hotspot SSID with punctuation/unicode (for example `Josh’s iPhone`).

Interpretation:

- ASCII works, Unicode fails: likely SSID encoding/normalization issue.
- Both fail: likely RF/signal, password, or driver/supplicant/runtime issue.
