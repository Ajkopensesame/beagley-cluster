---
name: beagley-network-status
description: Diagnose BeagleY network reachability, Wi-Fi autoconnect, saved hotspot profiles, and the home Telstra router plus TP-Link VX220-G2v access-point setup. Use when checking whether BeagleY, MacBook, EliteBook, Telstra, or TP-Link can see each other over Ethernet or Wi-Fi.
---

# BeagleY Network Status

Use this skill when diagnosing BeagleY reachability, Wi-Fi autoconnect, or the
home Telstra plus TP-Link access-point setup.

Run:

```bash
skills/beagley-network-status/scripts/status.sh
```

Expected home topology:

- Telstra modem/router owns internet, routing, DNS, and DHCP at `192.168.0.1`.
- TP-Link VX220-G2v is AP-only: Telstra LAN port to TP-Link yellow LAN port.
- TP-Link management IP is `192.168.0.2`.
- TP-Link DHCP is disabled.
- TP-Link 2.4 GHz SSID `VX220-9869` is the preferred BeagleY 2.4 GHz network.
- BeagleY saved Wi-Fi profile should use `id_str="tplink-vx220-2g"` and higher
  priority than the iPhone hotspot.

Diagnostics rules:

- Keep the MacBook on Telstra Wi-Fi during diagnosis unless the user explicitly
  asks to switch networks.
- Do not use the TP-Link WAN/blue port for this AP setup.
- Use BeagleY Ethernet or a temporary tunnel only for setup access. Remove
  temporary aliases and local tunnels after the TP-Link is reachable at
  `192.168.0.2`.
- Verify real state with `wpa_cli -i wlan0 status`, BeagleY IP leases, route
  ownership, ping/SSH from the Mac, and Telstra internet reachability.
- Do not store Wi-Fi passwords in this skill. Use the router label or the
  already saved credential on the device.

Useful known-good addresses:

- MacBook on Telstra Wi-Fi: `192.168.0.31`
- BeagleY Ethernet: `192.168.0.46`
- BeagleY TP-Link 2.4 GHz Wi-Fi: `192.168.0.92`
- EliteBook on Telstra Wi-Fi: `192.168.0.149`

These addresses can drift under DHCP. Treat them as current defaults to verify,
not as proof if a device is absent.
