# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately using GitHub's
[private vulnerability reporting](https://github.com/Ajkopensesame/beagley-cluster/security/advisories/new)
(Security tab → "Report a vulnerability").

Include what you found, how to reproduce it, and the affected commit or tag. We aim to acknowledge reports
within a week; this is a small hobby/hardware project maintained on a best-effort basis.

## Scope and context

This project is an automotive instrument cluster HMI for BeagleY-AI plus a BeagleBone Black sensor hub,
developed and run on a **private LAN / in-vehicle network**. Keep that context in mind:

- The hub ↔ cluster WebSocket (`vehicle_state`) and the helper scripts under `skills/` and `tools/` assume a
  trusted network and are **not** hardened for exposure to the internet or untrusted Wi-Fi.
- Dev images may allow `root` SSH and passwordless access for bring-up. Do not expose a development board
  directly to the internet.
- Never commit real IPs, MAC addresses, Wi-Fi credentials, or SSH keys. Machine-local target config lives in
  the gitignored `config/beagley-target.env` (see `config/beagley-target.env.example`).

Reports about vehicle-safety behaviour (e.g. spoofed bus/sensor data causing misleading gauges) are welcome too.

## Supported versions

Only the default branch (`codex/maplibre-native-yocto-build`) and the latest tag, if any, receive fixes.
