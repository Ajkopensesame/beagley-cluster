#!/usr/bin/env bash
set -euo pipefail

BOOT_ENV_PATH=""
BOOT_HOSTNAME_PATH=""
LOCAL_ENV_PATH="/etc/default/beagley-cluster.local"
STAMP_DIR="/var/lib/beagley-cluster"
STAMP_PATH="${STAMP_DIR}/provisioned"

find_first_existing() {
  local candidate
  for candidate in "$@"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

extract_hostname_from_env() {
  local env_file="$1"
  awk -F= '
    $1 == "BEAGLEY_CLUSTER_HOSTNAME" {
      print $2;
      exit
    }
  ' "$env_file"
}

update_hostname() {
  local target_hostname="$1"
  [[ -n "$target_hostname" ]] || return 0

  mkdir -p /etc
  if [[ ! -f /etc/hostname || "$(cat /etc/hostname)" != "$target_hostname" ]]; then
    printf '%s\n' "$target_hostname" >/etc/hostname
    if command -v hostname >/dev/null 2>&1; then
      hostname "$target_hostname" || true
    fi
  fi
}

mkdir -p "$STAMP_DIR" /etc/default

BOOT_ENV_PATH="$(find_first_existing /boot/firmware/beagley-cluster.env /boot/beagley-cluster.env || true)"
BOOT_HOSTNAME_PATH="$(find_first_existing /boot/firmware/beagley-cluster.hostname /boot/beagley-cluster.hostname || true)"

if [[ -n "$BOOT_ENV_PATH" ]]; then
  install -m 0644 "$BOOT_ENV_PATH" "$LOCAL_ENV_PATH"
fi

PROVISIONED_HOSTNAME=""
if [[ -n "$BOOT_ENV_PATH" ]]; then
  PROVISIONED_HOSTNAME="$(extract_hostname_from_env "$BOOT_ENV_PATH")"
fi
if [[ -z "$PROVISIONED_HOSTNAME" && -n "$BOOT_HOSTNAME_PATH" ]]; then
  PROVISIONED_HOSTNAME="$(tr -d '\r\n' <"$BOOT_HOSTNAME_PATH")"
fi
update_hostname "$PROVISIONED_HOSTNAME"

{
  echo "provisioned_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "boot_env=${BOOT_ENV_PATH:-none}"
  echo "boot_hostname=${BOOT_HOSTNAME_PATH:-none}"
  echo "hostname=${PROVISIONED_HOSTNAME:-unchanged}"
} >"$STAMP_PATH"
