#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: set-beagley-boot-mode-linux.sh <disk-device> <dual|efi-only|extlinux-only>

Examples:
  sudo ./yocto/set-beagley-boot-mode-linux.sh /dev/mmcblk0 efi-only
  sudo ./yocto/set-beagley-boot-mode-linux.sh /dev/sdb dual
EOF
}

fail() {
  echo "[beagley-boot-mode] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[beagley-boot-mode] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "run as root"
}

disk_partition() {
  local disk="$1"
  local index="$2"

  case "$disk" in
    /dev/mmcblk*|/dev/nvme*n*)
      printf '%sp%s\n' "$disk" "$index"
      ;;
    *)
      printf '%s%s\n' "$disk" "$index"
      ;;
  esac
}

move_if_exists() {
  local src="$1"
  local dst="$2"

  if [[ -e "$src" ]]; then
    rm -rf "$dst"
    mv "$src" "$dst"
  fi
}

restore_if_exists() {
  local disabled="$1"
  local enabled="$2"

  if [[ -e "$disabled" ]]; then
    rm -rf "$enabled"
    mv "$disabled" "$enabled"
  fi
}

set_mode() {
  local boot_mount="$1"
  local mode="$2"
  local stamp_path="$boot_mount/beagley-boot-mode.txt"

  case "$mode" in
    dual)
      restore_if_exists "$boot_mount/EFI.disabled" "$boot_mount/EFI"
      restore_if_exists "$boot_mount/extlinux.disabled" "$boot_mount/extlinux"
      ;;
    efi-only)
      restore_if_exists "$boot_mount/EFI.disabled" "$boot_mount/EFI"
      move_if_exists "$boot_mount/extlinux" "$boot_mount/extlinux.disabled"
      ;;
    extlinux-only)
      restore_if_exists "$boot_mount/extlinux.disabled" "$boot_mount/extlinux"
      move_if_exists "$boot_mount/EFI" "$boot_mount/EFI.disabled"
      ;;
    *)
      fail "unsupported mode: $mode"
      ;;
  esac

  {
    printf 'mode=%s\n' "$mode"
    printf 'updated_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$stamp_path"
}

main() {
  local disk="${1:-}"
  local mode="${2:-}"
  local boot_part=""
  local root_part=""
  local mount_root=""
  local boot_mount=""
  local root_mount=""

  [[ -n "$disk" && -n "$mode" ]] || {
    usage
    exit 1
  }

  require_root
  require_cmd lsblk
  require_cmd mount
  require_cmd umount

  [[ -b "$disk" ]] || fail "disk device not found: $disk"

  boot_part="$(disk_partition "$disk" 1)"
  root_part="$(disk_partition "$disk" 2)"
  [[ -b "$boot_part" ]] || fail "boot partition not found: $boot_part"
  [[ -b "$root_part" ]] || fail "root partition not found: $root_part"

  mount_root="$(mktemp -d /tmp/beagley-boot-mode.XXXXXX)"
  boot_mount="$mount_root/boot"
  root_mount="$mount_root/root"
  mkdir -p "$boot_mount" "$root_mount"

  cleanup() {
    local cleanup_boot_mount="${1:-}"
    local cleanup_root_mount="${2:-}"
    local cleanup_mount_root="${3:-}"

    [[ -n "$cleanup_boot_mount" ]] && umount "$cleanup_boot_mount" >/dev/null 2>&1 || true
    [[ -n "$cleanup_root_mount" ]] && umount "$cleanup_root_mount" >/dev/null 2>&1 || true
    [[ -n "$cleanup_boot_mount" && -n "$cleanup_root_mount" && -n "$cleanup_mount_root" ]] && \
      rmdir "$cleanup_boot_mount" "$cleanup_root_mount" "$cleanup_mount_root" >/dev/null 2>&1 || true
  }
  trap "cleanup '$boot_mount' '$root_mount' '$mount_root'" EXIT

  if findmnt -rn -S "$boot_part" >/dev/null 2>&1; then
    log "unmounting existing boot partition mount(s)"
    while read -r target; do
      [[ -n "$target" ]] || continue
      umount "$target"
    done < <(findmnt -rn -S "$boot_part" -o TARGET)
  fi
  if findmnt -rn -S "$root_part" >/dev/null 2>&1; then
    log "unmounting existing root partition mount(s)"
    while read -r target; do
      [[ -n "$target" ]] || continue
      umount "$target"
    done < <(findmnt -rn -S "$root_part" -o TARGET)
  fi

  mount "$boot_part" "$boot_mount"
  mount "$root_part" "$root_mount"

  [[ -f "$boot_mount/Image" ]] || fail "boot partition does not look like a BeagleY appliance card"

  set_mode "$boot_mount" "$mode"

  log "set boot mode to ${mode}"
  log "boot partition contents:"
  find "$boot_mount" -maxdepth 3 | sed "s#^$boot_mount##" | sort
}

main "$@"
