#!/usr/bin/env bash
set -euo pipefail

IMAGE_INPUT="${1:-}"
TARGET_DISK="${2:-}"

fail() {
  echo "[yocto-flash] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[yocto-flash] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

resolve_image() {
  local input="$1"
  if [[ -d "$input" ]]; then
    find "$input" -maxdepth 1 -type f \
      \( -name '*.wic' -o -name '*.wic.xz' \) \
      | sort | tail -n 1
    return
  fi
  printf '%s\n' "$input"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "this helper is for macOS hosts only"
[[ -n "$IMAGE_INPUT" && -n "$TARGET_DISK" ]] || fail "usage: $0 <release-dir-or-image> </dev/diskN>"

require_cmd diskutil
require_cmd sudo
require_cmd dd

IMAGE_PATH="$(resolve_image "$IMAGE_INPUT")"
[[ -n "$IMAGE_PATH" ]] || fail "unable to resolve image from ${IMAGE_INPUT}"
[[ -f "$IMAGE_PATH" ]] || fail "image not found: ${IMAGE_PATH}"
[[ "$TARGET_DISK" == /dev/disk* ]] || fail "target disk must look like /dev/diskN"

RAW_DISK="/dev/r${TARGET_DISK#/dev/disk}"

log "target image: ${IMAGE_PATH}"
log "target disk: ${TARGET_DISK}"
log "unmounting ${TARGET_DISK}"
diskutil unmountDisk "$TARGET_DISK"

if [[ "$IMAGE_PATH" == *.xz ]]; then
  require_cmd xz
  log "flashing compressed image to ${RAW_DISK}"
  xz -dc "$IMAGE_PATH" | sudo dd of="$RAW_DISK" bs=16m status=progress conv=sync
else
  log "flashing image to ${RAW_DISK}"
  sudo dd if="$IMAGE_PATH" of="$RAW_DISK" bs=16m status=progress conv=sync
fi

sync
diskutil eject "$TARGET_DISK"
log "flash complete"
