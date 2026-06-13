#!/usr/bin/env python3
"""Configure the BeagleY to use the stable Spotify pairing broker."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SSH_OPTS = [
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=8",
    "-o",
    "ConnectionAttempts=1",
    "-o",
    "ServerAliveInterval=5",
    "-o",
    "ServerAliveCountMax=1",
    "-o",
    "StrictHostKeyChecking=accept-new",
]


def die(message: str, code: int = 1) -> None:
    print(f"[spotify-broker] {message}", file=sys.stderr)
    raise SystemExit(code)


def resolve_beagley_target(host_override: str | None) -> str:
    env = os.environ.copy()
    if host_override:
        env["BEAGLEY_HOST"] = host_override
    command = (
        "source skills/beagley-common/scripts/ssh.sh; "
        "beagley_require_ssh_target; "
        "printf '%s\\n' \"$BEAGLEY_SSH_HOST\""
    )
    result = subprocess.run(
        ["bash", "-lc", command],
        cwd=str(ROOT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        detail = result.stderr.strip() or "target discovery failed"
        die(f"could not resolve BeagleY SSH target: {detail}")
    return result.stdout.strip().splitlines()[-1]


def ssh(ssh_target: str, remote_script: str, *args: str) -> None:
    result = subprocess.run(
        ["ssh", *SSH_OPTS, ssh_target, "bash", "-s", "--", *args],
        input=remote_script,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        die(f"remote command failed: {detail}")


def configure(ssh_target: str, broker_url: str, client_id: str, broker_token: str) -> None:
    remote_script = r"""
set -euo pipefail
broker_url="$1"
client_id="$2"
broker_token="$3"
remote_env="/etc/default/beagley-cluster.local"
mkdir -p "$(dirname "$remote_env")"
[ -f "$remote_env" ] || : > "$remote_env"

tmp="$(mktemp)"
DROP_KEYS="BEAGLEY_NOW_PLAYING_BACKEND BEAGLEY_NOW_PLAYING_SOURCE_LABEL BEAGLEY_NOW_PLAYING_REFRESH_MS BEAGLEY_SPOTIFY_CLIENT_ID BEAGLEY_SPOTIFY_BROKER_URL BEAGLEY_SPOTIFY_BROKER_TOKEN BEAGLEY_SPOTIFY_REDIRECT_URI BEAGLEY_SPOTIFY_PAIRING_BASE_URL BEAGLEY_SPOTIFY_CALLBACK_HOST BEAGLEY_SPOTIFY_CALLBACK_PORT BEAGLEY_SPOTIFY_PAIRING_AUTOSTART BEAGLEY_INITIAL_MAP_MENU_STAGE" \
awk -F= '
  BEGIN { split(ENVIRON["DROP_KEYS"], keys, " "); for (i in keys) drop[keys[i]]=1 }
  ($1 in drop) { next }
  { print }
' "$remote_env" > "$tmp"

{
  printf 'BEAGLEY_NOW_PLAYING_BACKEND=spotify-web\n'
  printf 'BEAGLEY_NOW_PLAYING_SOURCE_LABEL=Spotify\n'
  printf 'BEAGLEY_NOW_PLAYING_REFRESH_MS=5000\n'
  printf 'BEAGLEY_SPOTIFY_CLIENT_ID=%s\n' "$client_id"
  printf 'BEAGLEY_SPOTIFY_BROKER_URL=%s\n' "$broker_url"
  printf 'BEAGLEY_SPOTIFY_BROKER_TOKEN=%s\n' "$broker_token"
} >> "$tmp"

cp "$tmp" "$remote_env"
chown root:root "$remote_env" 2>/dev/null || true
chmod 0600 "$remote_env" 2>/dev/null || true
rm -f "$tmp"
systemctl daemon-reload
systemctl reset-failed beagley_cluster
systemctl restart beagley_cluster
"""
    ssh(ssh_target, remote_script, broker_url.rstrip("/"), client_id, broker_token)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--broker-url", default=os.environ.get("BEAGLEY_SPOTIFY_BROKER_URL", "https://spotify.pneumaion.com"))
    parser.add_argument("--client-id", default=os.environ.get("BEAGLEY_SPOTIFY_CLIENT_ID", "").strip())
    parser.add_argument("--broker-token", default=os.environ.get("BEAGLEY_SPOTIFY_BROKER_TOKEN", "").strip())
    parser.add_argument("--host", default=os.environ.get("BEAGLEY_HOST", "").strip())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.broker_url.startswith("https://"):
        die("--broker-url must be an HTTPS URL")
    if not args.client_id:
        die("missing Spotify client id; pass --client-id or set BEAGLEY_SPOTIFY_CLIENT_ID")
    if not args.broker_token:
        die("missing broker token; pass --broker-token or set BEAGLEY_SPOTIFY_BROKER_TOKEN")

    ssh_target = resolve_beagley_target(args.host or None)
    print(f"[spotify-broker] configuring {ssh_target} for {args.broker_url.rstrip('/')}")
    configure(ssh_target, args.broker_url, args.client_id, args.broker_token)
    print("[spotify-broker] BeagleY Spotify broker config installed; service restarted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
