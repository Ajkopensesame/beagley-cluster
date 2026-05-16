---
name: beagley-screenshot
description: Capture screenshots from the real BeagleY cluster display, including the Wi-Fi signup/setup overlay, using the on-device Qt screenshot hook and restoring the service afterward. Use when the user asks to see the current BeagleY UI, take a screenshot, capture the actual display, or screenshot the Wi-Fi signup page.
---

# BeagleY Screenshot

Use this skill when the user wants a real BeagleY display screenshot. Prefer the
script over ad hoc SSH/service/env commands.

## Quick Commands

Capture the normal UI after a restart:

```bash
skills/beagley-screenshot/scripts/capture.sh
```

Capture the Wi-Fi signup/setup page:

```bash
skills/beagley-screenshot/scripts/capture.sh --wifi-signup
```

Capture the Wi-Fi page with available networks open:

```bash
skills/beagley-screenshot/scripts/capture.sh --wifi-networks
```

Capture the selected-network/password-keyboard step:

```bash
skills/beagley-screenshot/scripts/capture.sh --wifi-password
```

Use a known target:

```bash
skills/beagley-screenshot/scripts/capture.sh --host root@192.168.0.92 --wifi-signup
```

## Workflow

The script:

- resolves the BeagleY through `skills/beagley-common`
- for `--wifi-signup`, syncs current QML to `/opt/beagley-cluster/qml-dev`
- writes a temporary QML entry that opens `wifiOverlay`
- for `--wifi-networks`, opens the network picker before capture
- for `--wifi-password`, selects the scanned network, types a dummy preview
  password, and focuses the password keyboard without submitting it
- seeds the picker from the board's real `wpa_cli` scan when capturing networks
- sets `BEAGLEY_SCREENSHOT_PATH`, `BEAGLEY_SCREENSHOT_DELAY_MS`, and
  `BEAGLEY_SCREENSHOT_EXIT=0`
- restarts `beagley_cluster`, waits for the PNG, and copies it into `build/`
- runs screenshot analysis when `tools/maplibre/analyze_screenshot.py` exists
- restores `/etc/default/beagley-cluster.local`, removes temporary QML, restarts
  the service, and runs the health check

Report the output PNG path and whether the final health check passed. Do not
leave temporary screenshot env vars on the device.
