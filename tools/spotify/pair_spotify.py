#!/usr/bin/env python3
"""Run a real Spotify QR pairing session for the BeagleY cluster."""

from __future__ import annotations

import argparse
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse


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
TRYCLOUDFLARE_RE = re.compile(r"https://[A-Za-z0-9.-]+\.trycloudflare\.com")


def die(message: str, code: int = 1) -> None:
    print(f"[spotify-pair] {message}", file=sys.stderr)
    raise SystemExit(code)


def run(cmd: list[str], *, cwd: Path | None = None, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd or ROOT),
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


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


def target_hostname(ssh_target: str) -> str:
    return ssh_target.rsplit("@", 1)[-1]


def ssh(ssh_target: str, remote_script: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    cmd = ["ssh", *SSH_OPTS, ssh_target, "bash", "-s", "--", *args]
    result = subprocess.run(
        cmd,
        text=True,
        input=remote_script,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        die(f"remote command failed: {detail}")
    return result


def configure_beagley(ssh_target: str, client_id: str, public_url: str, redirect_uri: str, port: int) -> None:
    remote_script = r"""
set -euo pipefail
client_id="$1"
public_url="$2"
redirect_uri="$3"
port="$4"
remote_env="/etc/default/beagley-cluster.local"
mkdir -p "$(dirname "$remote_env")"
if [ ! -f "$remote_env" ]; then
  : > "$remote_env"
fi

tmp="$(mktemp)"
DROP_KEYS="BEAGLEY_NOW_PLAYING_BACKEND BEAGLEY_NOW_PLAYING_SOURCE_LABEL BEAGLEY_NOW_PLAYING_REFRESH_MS BEAGLEY_SPOTIFY_CLIENT_ID BEAGLEY_SPOTIFY_REDIRECT_URI BEAGLEY_SPOTIFY_PAIRING_BASE_URL BEAGLEY_SPOTIFY_CALLBACK_HOST BEAGLEY_SPOTIFY_CALLBACK_PORT BEAGLEY_SPOTIFY_PAIRING_AUTOSTART BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE BEAGLEY_SCREENSHOT_PATH BEAGLEY_SCREENSHOT_DELAY_MS BEAGLEY_SCREENSHOT_EXIT BEAGLEY_QML_DEV_ROOT BEAGLEY_QML_DEV_FILE" \
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
  printf 'BEAGLEY_SPOTIFY_REDIRECT_URI=%s\n' "$redirect_uri"
  printf 'BEAGLEY_SPOTIFY_PAIRING_BASE_URL=%s\n' "$public_url"
  printf 'BEAGLEY_SPOTIFY_CALLBACK_PORT=%s\n' "$port"
  printf 'BEAGLEY_SPOTIFY_PAIRING_AUTOSTART=1\n'
  printf 'BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE=music\n'
} >> "$tmp"

cp "$tmp" "$remote_env"
chown root:root "$remote_env" 2>/dev/null || true
chmod 0600 "$remote_env" 2>/dev/null || true
rm -f "$tmp"
systemctl daemon-reload
systemctl reset-failed beagley_cluster
systemctl restart beagley_cluster
"""
    ssh(ssh_target, remote_script, client_id, public_url, redirect_uri, str(port))


def cleanup_pairing_env(ssh_target: str, *, restart: bool) -> None:
    remote_script = r"""
set -euo pipefail
restart="$1"
remote_env="/etc/default/beagley-cluster.local"
[ -f "$remote_env" ] || exit 0
tmp="$(mktemp)"
DROP_KEYS="BEAGLEY_SPOTIFY_REDIRECT_URI BEAGLEY_SPOTIFY_PAIRING_BASE_URL BEAGLEY_SPOTIFY_CALLBACK_HOST BEAGLEY_SPOTIFY_CALLBACK_PORT BEAGLEY_SPOTIFY_PAIRING_AUTOSTART BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE BEAGLEY_SCREENSHOT_PATH BEAGLEY_SCREENSHOT_DELAY_MS BEAGLEY_SCREENSHOT_EXIT BEAGLEY_QML_DEV_ROOT BEAGLEY_QML_DEV_FILE" \
awk -F= '
  BEGIN { split(ENVIRON["DROP_KEYS"], keys, " "); for (i in keys) drop[keys[i]]=1 }
  ($1 in drop) { next }
  { print }
' "$remote_env" > "$tmp"
cp "$tmp" "$remote_env"
chown root:root "$remote_env" 2>/dev/null || true
chmod 0600 "$remote_env" 2>/dev/null || true
rm -f "$tmp"
if [ "$restart" = "1" ]; then
  systemctl daemon-reload
  systemctl reset-failed beagley_cluster
  systemctl restart beagley_cluster
fi
"""
    ssh(ssh_target, remote_script, "1" if restart else "0", check=False)


def refresh_token_present(ssh_target: str) -> bool:
    remote_script = r"""
awk -F= '
  $1 == "BEAGLEY_SPOTIFY_REFRESH_TOKEN" && length($2) > 0 { found=1 }
  END { exit found ? 0 : 1 }
' /etc/default/beagley-cluster.local 2>/dev/null
"""
    return ssh(ssh_target, remote_script, check=False).returncode == 0


def start_cloudflared(origin_url: str) -> tuple[subprocess.Popen[str], str]:
    cloudflared = shutil.which("cloudflared")
    if not cloudflared:
        die("cloudflared is not installed; pass --public-url for an existing HTTPS tunnel")

    process = subprocess.Popen(
        [cloudflared, "tunnel", "--no-autoupdate", "--url", origin_url],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )
    lines: queue.Queue[str] = queue.Queue()

    def reader() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            lines.put(line.rstrip())

    threading.Thread(target=reader, daemon=True).start()

    deadline = time.monotonic() + 60
    public_url = ""
    while time.monotonic() < deadline:
        if process.poll() is not None:
            remaining = []
            while not lines.empty():
                remaining.append(lines.get_nowait())
            die("cloudflared exited before publishing a URL:\n" + "\n".join(remaining))
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            continue
        match = TRYCLOUDFLARE_RE.search(line)
        if match:
            public_url = match.group(0).rstrip("/")
            break

    if not public_url:
        process.terminate()
        die("timed out waiting for cloudflared public URL")
    return process, public_url


def stop_process(process: subprocess.Popen[str] | None) -> None:
    if not process or process.poll() is not None:
        return
    process.send_signal(signal.SIGTERM)
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def valid_https_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        die("--public-url must be an HTTPS URL reachable by the phone")
    return value.rstrip("/")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-id", default=os.environ.get("BEAGLEY_SPOTIFY_CLIENT_ID", "").strip(),
                        help="Spotify app client id. Defaults to BEAGLEY_SPOTIFY_CLIENT_ID.")
    parser.add_argument("--host", default=os.environ.get("BEAGLEY_HOST", "").strip(),
                        help="BeagleY SSH target, for example root@192.168.0.92.")
    parser.add_argument("--port", type=int, default=8787, help="BeagleY pairing server port.")
    parser.add_argument("--public-url", default="", help="Stable HTTPS public URL to use instead of a cloudflared quick tunnel.")
    parser.add_argument("--skip-dashboard-wait", action="store_true",
                        help="Do not wait for you to add the printed redirect URI to the Spotify app dashboard.")
    parser.add_argument("--timeout-seconds", type=int, default=900, help="How long to wait for pairing to complete.")
    parser.add_argument("--leave-active-on-timeout", action="store_true",
                        help="Leave temporary BeagleY pairing env active if the wait times out.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.client_id:
        die("missing Spotify client id; pass --client-id or set BEAGLEY_SPOTIFY_CLIENT_ID")
    if args.port < 1 or args.port > 65535:
        die("--port must be between 1 and 65535")

    ssh_target = resolve_beagley_target(args.host or None)
    origin_host = target_hostname(ssh_target)
    origin_url = f"http://{origin_host}:{args.port}"
    tunnel_process: subprocess.Popen[str] | None = None

    if args.public_url:
        public_url = valid_https_url(args.public_url)
    else:
        print(f"[spotify-pair] starting cloudflared quick tunnel to {origin_url}")
        tunnel_process, public_url = start_cloudflared(origin_url)

    redirect_uri = f"{public_url}/spotify/callback"
    print()
    print("[spotify-pair] Add this exact Redirect URI to your Spotify app:")
    print(f"  {redirect_uri}")
    print()
    print("[spotify-pair] Dashboard: https://developer.spotify.com/dashboard")
    print("[spotify-pair] The QR will not complete until that URI is saved on the Spotify app.")
    print()

    if not args.skip_dashboard_wait:
        if not sys.stdin.isatty():
            stop_process(tunnel_process)
            die("not running in a TTY; rerun with --skip-dashboard-wait after adding the redirect URI")
        input("Press Enter after the redirect URI is saved in Spotify Dashboard...")

    print(f"[spotify-pair] configuring BeagleY {ssh_target}")
    configure_beagley(ssh_target, args.client_id, public_url, redirect_uri, args.port)
    print("[spotify-pair] QR is active on the cluster. Scan it with your phone and approve Spotify.")

    deadline = time.monotonic() + args.timeout_seconds
    paired = False
    try:
        while time.monotonic() < deadline:
            if refresh_token_present(ssh_target):
                paired = True
                break
            time.sleep(3)
    except KeyboardInterrupt:
        print()
        print("[spotify-pair] interrupted")
    finally:
        if paired:
            print("[spotify-pair] refresh token detected; cleaning temporary pairing env")
            cleanup_pairing_env(ssh_target, restart=True)
        elif not args.leave_active_on_timeout:
            print("[spotify-pair] pairing did not complete; cleaning temporary pairing env")
            cleanup_pairing_env(ssh_target, restart=True)
        stop_process(tunnel_process)

    if not paired:
        die("Spotify pairing did not complete", code=2)
    print("[spotify-pair] Spotify pairing complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
