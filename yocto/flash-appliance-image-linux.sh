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
      \( -name '*.wic.xz' -o -name '*.wic' \) \
      | sort | tail -n 1
    return
  fi
  printf '%s\n' "$input"
}

target_partitions() {
  lsblk -nrpo NAME,TYPE "$TARGET_DISK" | awk '$2 == "part" { print $1 }'
}

unmount_target() {
  local part
  while read -r part; do
    [[ -n "$part" ]] || continue
    sudo umount "$part" 2>/dev/null || true
  done < <(target_partitions)
}

[[ "$(uname -s)" == "Linux" ]] || fail "this helper is for Linux hosts only"
[[ -n "$IMAGE_INPUT" && -n "$TARGET_DISK" ]] || fail "usage: $0 <release-dir-or-image> </dev/sdX>"

require_cmd lsblk
require_cmd sudo
require_cmd dd

IMAGE_PATH="$(resolve_image "$IMAGE_INPUT")"
[[ -n "$IMAGE_PATH" ]] || fail "unable to resolve image from ${IMAGE_INPUT}"
[[ -f "$IMAGE_PATH" ]] || fail "image not found: ${IMAGE_PATH}"
[[ "$TARGET_DISK" == /dev/* ]] || fail "target disk must be a block device path"
[[ -b "$TARGET_DISK" ]] || fail "target disk not found: ${TARGET_DISK}"
[[ "$(lsblk -ndo TYPE "$TARGET_DISK")" == "disk" ]] || fail "target is not a whole disk: ${TARGET_DISK}"

log "target image: ${IMAGE_PATH}"
log "target disk: ${TARGET_DISK}"
log "unmounting ${TARGET_DISK} partitions"
unmount_target

if [[ "$IMAGE_PATH" == *.xz ]]; then
  require_cmd xz
  log "flashing compressed image to ${TARGET_DISK}"
  xz -dc "$IMAGE_PATH" | sudo dd of="$TARGET_DISK" bs=16M status=progress conv=fsync
else
  log "flashing image to ${TARGET_DISK}"
  sudo dd if="$IMAGE_PATH" of="$TARGET_DISK" bs=16M status=progress conv=fsync
fi

sync
sudo blockdev --rereadpt "$TARGET_DISK" 2>/dev/null || true
sudo udevadm settle 2>/dev/null || true

echo
echo "=== lsblk ==="
lsblk -o NAME,SIZE,RM,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$TARGET_DISK"
