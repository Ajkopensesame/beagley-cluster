#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/mac-builder-common.sh"

EXTERNAL_VOLUME_NAME="${EXTERNAL_VOLUME_NAME:-$MAC_BUILDER_DEFAULT_VOLUME_NAME}"
EXTERNAL_VOLUME_MOUNT="${EXTERNAL_VOLUME_MOUNT:-$(mac_builder_volume_mount "$EXTERNAL_VOLUME_NAME")}"
CACHE_ROOT="${CACHE_ROOT:-${EXTERNAL_VOLUME_MOUNT}/beagley-cache}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-${CACHE_ROOT}/downloads}"
SSTATE_DIR="${SSTATE_DIR:-${CACHE_ROOT}/sstate-cache}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-${EXTERNAL_VOLUME_MOUNT}/DockerDesktop}"
MIN_FREE_GIB="${MIN_FREE_GIB:-$MAC_BUILDER_DEFAULT_MIN_FREE_GIB}"
MIN_CAPACITY_GIB="${MIN_CAPACITY_GIB:-$MAC_BUILDER_DEFAULT_MIN_CAPACITY_GIB}"
SMOKE_TEST_GIB="${SMOKE_TEST_GIB:-$MAC_BUILDER_DEFAULT_SMOKE_TEST_GIB}"
EXPECT_CPUS="${EXPECT_CPUS:-$MAC_BUILDER_DEFAULT_CPUS}"
EXPECT_MEMORY_MIB="${EXPECT_MEMORY_MIB:-$MAC_BUILDER_DEFAULT_MEMORY_MIB}"
EXPECT_SWAP_MIB="${EXPECT_SWAP_MIB:-$MAC_BUILDER_DEFAULT_SWAP_MIB}"
EXPECT_DISK_SIZE_MIB="${EXPECT_DISK_SIZE_MIB:-$MAC_BUILDER_DEFAULT_DISK_SIZE_MIB}"
RUN_SMOKE_TEST=0

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --volume-name NAME        External APFS volume name (default: ${EXTERNAL_VOLUME_NAME})
  --mount-point PATH        External APFS mount path
  --cache-root PATH         Cache root for downloads and sstate
  --docker-data-root PATH   Docker Desktop DataFolder on the external SSD
  --min-free-gib N          Minimum free space on the external SSD (default: ${MIN_FREE_GIB})
  --min-capacity-gib N      Minimum total SSD capacity in GiB (default: ${MIN_CAPACITY_GIB})
  --smoke-test              Run the SSD smoke test before returning success
  --smoke-test-gib N        Smoke-test size in GiB (default: ${SMOKE_TEST_GIB})
  --help                    Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --volume-name)
      EXTERNAL_VOLUME_NAME="$2"
      EXTERNAL_VOLUME_MOUNT="$(mac_builder_volume_mount "$EXTERNAL_VOLUME_NAME")"
      CACHE_ROOT="${EXTERNAL_VOLUME_MOUNT}/beagley-cache"
      DOWNLOADS_DIR="${CACHE_ROOT}/downloads"
      SSTATE_DIR="${CACHE_ROOT}/sstate-cache"
      DOCKER_DATA_ROOT="${EXTERNAL_VOLUME_MOUNT}/DockerDesktop"
      shift 2
      ;;
    --mount-point)
      EXTERNAL_VOLUME_MOUNT="$2"
      CACHE_ROOT="${EXTERNAL_VOLUME_MOUNT}/beagley-cache"
      DOWNLOADS_DIR="${CACHE_ROOT}/downloads"
      SSTATE_DIR="${CACHE_ROOT}/sstate-cache"
      DOCKER_DATA_ROOT="${EXTERNAL_VOLUME_MOUNT}/DockerDesktop"
      shift 2
      ;;
    --cache-root)
      CACHE_ROOT="$2"
      DOWNLOADS_DIR="${CACHE_ROOT}/downloads"
      SSTATE_DIR="${CACHE_ROOT}/sstate-cache"
      shift 2
      ;;
    --docker-data-root)
      DOCKER_DATA_ROOT="$2"
      shift 2
      ;;
    --min-free-gib)
      MIN_FREE_GIB="$2"
      shift 2
      ;;
    --min-capacity-gib)
      MIN_CAPACITY_GIB="$2"
      shift 2
      ;;
    --smoke-test)
      RUN_SMOKE_TEST=1
      shift
      ;;
    --smoke-test-gib)
      SMOKE_TEST_GIB="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      mac_builder_fail "unknown argument: $1"
      ;;
  esac
done

mac_builder_require_macos
mac_builder_require_cmd python3
mac_builder_require_cmd diskutil
DOCKER_BIN="$(mac_builder_docker_bin)"

mac_builder_assert_volume_mounted "$EXTERNAL_VOLUME_MOUNT"
mac_builder_assert_apfs "$EXTERNAL_VOLUME_MOUNT"
mkdir -p "$DOWNLOADS_DIR" "$SSTATE_DIR"

mac_builder_log "verifying ${EXTERNAL_VOLUME_MOUNT}"
mac_builder_verify_volume "$EXTERNAL_VOLUME_MOUNT" >/dev/null
mac_builder_check_total_capacity "$EXTERNAL_VOLUME_MOUNT" "$(mac_builder_gib_to_bytes "$MIN_CAPACITY_GIB")"
mac_builder_check_free_space "$EXTERNAL_VOLUME_MOUNT" "$(mac_builder_gib_to_bytes "$MIN_FREE_GIB")"
mac_builder_assert_docker_settings \
  "$DOCKER_DATA_ROOT" \
  "$EXPECT_CPUS" \
  "$EXPECT_MEMORY_MIB" \
  "$EXPECT_SWAP_MIB" \
  "$EXPECT_DISK_SIZE_MIB" \
  false \
  0

"$DOCKER_BIN" version >/dev/null 2>&1 || mac_builder_fail "Docker engine is not running"

if mac_builder_current_vm_storage_errors; then
  mac_builder_fail "current Docker VM session already contains storage errors; restart Docker Desktop before building"
fi

if (( RUN_SMOKE_TEST )); then
  mac_builder_run_smoke_test "$CACHE_ROOT" "$SMOKE_TEST_GIB"
fi

mac_builder_log "external volume: ${EXTERNAL_VOLUME_MOUNT}"
mac_builder_log "cache root: ${CACHE_ROOT}"
mac_builder_log "docker data root: ${DOCKER_DATA_ROOT}"
mac_builder_log "downloads dir: ${DOWNLOADS_DIR}"
mac_builder_log "sstate dir: ${SSTATE_DIR}"
mac_builder_log "docker settings validated"
