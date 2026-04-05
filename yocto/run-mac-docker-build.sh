#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/mac-builder-common.sh"

EXTERNAL_VOLUME_NAME="${EXTERNAL_VOLUME_NAME:-$MAC_BUILDER_DEFAULT_VOLUME_NAME}"
EXTERNAL_VOLUME_MOUNT="${EXTERNAL_VOLUME_MOUNT:-$(mac_builder_volume_mount "$EXTERNAL_VOLUME_NAME")}"
CACHE_ROOT="${CACHE_ROOT:-${EXTERNAL_VOLUME_MOUNT}/beagley-cache}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-${CACHE_ROOT}/downloads}"
SSTATE_DIR="${SSTATE_DIR:-${CACHE_ROOT}/sstate-cache}"
RUN_ROOT="${RUN_ROOT:-${CACHE_ROOT}/logs}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-${EXTERNAL_VOLUME_MOUNT}/DockerDesktop}"
TI_WORKSPACE_VOLUME="${TI_WORKSPACE_VOLUME:-$MAC_BUILDER_DEFAULT_DOCKER_VOLUME}"
TI_WORKSPACE_MOUNT="${TI_WORKSPACE_MOUNT:-/work/ti-sdk-11.00}"
SDK_SEED_ROOT="${SDK_SEED_ROOT:-${REPO_ROOT}/.yocto-work/ti-sdk-11.00}"
IMAGE_TAG="${IMAGE_TAG:-$MAC_BUILDER_DEFAULT_IMAGE_TAG}"
CONTAINER_NAME="${CONTAINER_NAME:-$MAC_BUILDER_DEFAULT_CONTAINER_NAME}"
MACHINE_POLICY="${MACHINE_POLICY:-}"
MACHINE_NAME="${MACHINE:-}"
IMAGE_NAME="${IMAGE:-beagley-cluster-image}"
BUILD_DIR="${BUILD_DIR:-build-beagley-cluster}"
MIN_FREE_GIB="${MIN_FREE_GIB:-$MAC_BUILDER_DEFAULT_MIN_FREE_GIB}"
MIN_CAPACITY_GIB="${MIN_CAPACITY_GIB:-$MAC_BUILDER_DEFAULT_MIN_CAPACITY_GIB}"
SMOKE_TEST_GIB="${SMOKE_TEST_GIB:-$MAC_BUILDER_DEFAULT_SMOKE_TEST_GIB}"
EXPECT_CPUS="${EXPECT_CPUS:-$MAC_BUILDER_DEFAULT_CPUS}"
EXPECT_MEMORY_MIB="${EXPECT_MEMORY_MIB:-$MAC_BUILDER_DEFAULT_MEMORY_MIB}"
EXPECT_SWAP_MIB="${EXPECT_SWAP_MIB:-$MAC_BUILDER_DEFAULT_SWAP_MIB}"
EXPECT_DISK_SIZE_MIB="${EXPECT_DISK_SIZE_MIB:-$MAC_BUILDER_DEFAULT_DISK_SIZE_MIB}"
SMOKE_TEST_MODE="${SMOKE_TEST_MODE:-auto}"

sdk_seed_has_beagley_ai_machine() {
  [[ -f "${SDK_SEED_ROOT}/yocto-build/sources/meta-ti/meta-beagle/conf/machine/beagley-ai.conf" ]] \
    || [[ -f "${SDK_SEED_ROOT}/sources/meta-ti/meta-beagle/conf/machine/beagley-ai.conf" ]]
}

resolve_machine_defaults() {
  if [[ -z "$MACHINE_NAME" ]]; then
    if [[ "$MACHINE_POLICY" == "board-bsp" ]]; then
      MACHINE_NAME="beagley-ai"
    elif sdk_seed_has_beagley_ai_machine && [[ -z "$MACHINE_POLICY" ]]; then
      MACHINE_NAME="beagley-ai"
      MACHINE_POLICY="board-bsp"
    else
      MACHINE_NAME="j722s-evm"
    fi
  fi

  if [[ -z "$MACHINE_POLICY" ]]; then
    if [[ "$MACHINE_NAME" == "beagley-ai" ]]; then
      MACHINE_POLICY="board-bsp"
    else
      MACHINE_POLICY="ti-sdk"
    fi
  fi
}

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --volume-name NAME        External APFS volume name (default: ${EXTERNAL_VOLUME_NAME})
  --mount-point PATH        External APFS mount path
  --cache-root PATH         Cache root on the external SSD
  --docker-data-root PATH   Docker Desktop DataFolder on the external SSD
  --workspace-volume NAME   Docker volume used for the TI workspace
  --sdk-seed-root PATH      Host-side TI SDK checkout used to seed the Docker volume
  --container-name NAME     Docker container name for the Yocto build
  --image-tag TAG           Builder image tag (default: ${IMAGE_TAG})
  --machine NAME            Yocto MACHINE value (default: ${MACHINE_NAME})
  --machine-policy NAME     Yocto MACHINE_POLICY value (default: ${MACHINE_POLICY})
  --image NAME              Yocto image target (default: ${IMAGE_NAME})
  --build-dir NAME          Build directory label passed to the helper
  --min-capacity-gib N      Minimum total SSD capacity in GiB (default: ${MIN_CAPACITY_GIB})
  --min-free-gib N          Minimum free space in GiB (default: ${MIN_FREE_GIB})
  --smoke-test              Force the SSD smoke test before building
  --no-smoke-test           Skip the SSD smoke test even if no prior stamp exists
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
      RUN_ROOT="${CACHE_ROOT}/logs"
      DOCKER_DATA_ROOT="${EXTERNAL_VOLUME_MOUNT}/DockerDesktop"
      shift 2
      ;;
    --mount-point)
      EXTERNAL_VOLUME_MOUNT="$2"
      CACHE_ROOT="${EXTERNAL_VOLUME_MOUNT}/beagley-cache"
      DOWNLOADS_DIR="${CACHE_ROOT}/downloads"
      SSTATE_DIR="${CACHE_ROOT}/sstate-cache"
      RUN_ROOT="${CACHE_ROOT}/logs"
      DOCKER_DATA_ROOT="${EXTERNAL_VOLUME_MOUNT}/DockerDesktop"
      shift 2
      ;;
    --cache-root)
      CACHE_ROOT="$2"
      DOWNLOADS_DIR="${CACHE_ROOT}/downloads"
      SSTATE_DIR="${CACHE_ROOT}/sstate-cache"
      RUN_ROOT="${CACHE_ROOT}/logs"
      shift 2
      ;;
    --docker-data-root)
      DOCKER_DATA_ROOT="$2"
      shift 2
      ;;
    --workspace-volume)
      TI_WORKSPACE_VOLUME="$2"
      shift 2
      ;;
    --sdk-seed-root)
      SDK_SEED_ROOT="$2"
      shift 2
      ;;
    --container-name)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --machine)
      MACHINE_NAME="$2"
      shift 2
      ;;
    --machine-policy)
      MACHINE_POLICY="$2"
      shift 2
      ;;
    --image)
      IMAGE_NAME="$2"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --min-capacity-gib)
      MIN_CAPACITY_GIB="$2"
      shift 2
      ;;
    --min-free-gib)
      MIN_FREE_GIB="$2"
      shift 2
      ;;
    --smoke-test)
      SMOKE_TEST_MODE="always"
      shift
      ;;
    --no-smoke-test)
      SMOKE_TEST_MODE="never"
      shift
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

resolve_machine_defaults
if [[ "$MACHINE_POLICY" == "board-bsp" ]] && ! sdk_seed_has_beagley_ai_machine; then
  mac_builder_fail "MACHINE_POLICY=board-bsp requires a BeagleY BSP in ${SDK_SEED_ROOT}"
fi
if [[ "$MACHINE_POLICY" == "board-bsp" && "$MACHINE_NAME" != "beagley-ai" ]]; then
  mac_builder_fail "MACHINE_POLICY=board-bsp requires --machine beagley-ai"
fi

mac_builder_require_macos
mac_builder_require_cmd python3
mac_builder_require_cmd diskutil
mac_builder_require_cmd open
DOCKER_BIN="$(mac_builder_docker_bin)"

mac_builder_assert_volume_mounted "$EXTERNAL_VOLUME_MOUNT"
mac_builder_assert_apfs "$EXTERNAL_VOLUME_MOUNT"
mkdir -p "$DOWNLOADS_DIR" "$SSTATE_DIR" "$RUN_ROOT" "$DOCKER_DATA_ROOT"

smoke_test_stamp="${CACHE_ROOT}/.mac-builder-smoke-test.ok"
should_run_smoke_test=0
case "$SMOKE_TEST_MODE" in
  always)
    should_run_smoke_test=1
    ;;
  never)
    should_run_smoke_test=0
    ;;
  auto)
    [[ -f "$smoke_test_stamp" ]] || should_run_smoke_test=1
    ;;
  *)
    mac_builder_fail "unsupported SMOKE_TEST_MODE=${SMOKE_TEST_MODE}"
    ;;
esac

if (( should_run_smoke_test )); then
  mac_builder_run_smoke_test "$CACHE_ROOT" "$SMOKE_TEST_GIB"
fi

settings_update_output="$(mac_builder_apply_docker_settings \
  "$DOCKER_DATA_ROOT" \
  "$EXPECT_CPUS" \
  "$EXPECT_MEMORY_MIB" \
  "$EXPECT_SWAP_MIB" \
  "$EXPECT_DISK_SIZE_MIB" \
  false \
  0)"
printf '%s\n' "$settings_update_output"

restart_required=0
if printf '%s\n' "$settings_update_output" | grep -Fq 'changed=1'; then
  restart_required=1
fi

if ! "$DOCKER_BIN" version >/dev/null 2>&1; then
  mac_builder_log "starting Docker Desktop"
  "$DOCKER_BIN" desktop start >/dev/null 2>&1 || open -ga Docker
elif (( restart_required )); then
  mac_builder_log "restarting Docker Desktop to apply settings"
  "$DOCKER_BIN" desktop restart --timeout 180 >/dev/null 2>&1
fi

mac_builder_wait_for_docker "$DOCKER_BIN"

"$SCRIPT_DIR/check-mac-builder.sh" \
  --mount-point "$EXTERNAL_VOLUME_MOUNT" \
  --cache-root "$CACHE_ROOT" \
  --docker-data-root "$DOCKER_DATA_ROOT" \
  --min-capacity-gib "$MIN_CAPACITY_GIB" \
  --min-free-gib "$MIN_FREE_GIB"

if ! "$DOCKER_BIN" image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  mac_builder_log "building ${IMAGE_TAG}"
  "$DOCKER_BIN" build -t "$IMAGE_TAG" -f "$REPO_ROOT/yocto/Dockerfile.builder" "$REPO_ROOT"
fi

if ! "$DOCKER_BIN" volume inspect "$TI_WORKSPACE_VOLUME" >/dev/null 2>&1; then
  mac_builder_log "creating Docker volume ${TI_WORKSPACE_VOLUME}"
  "$DOCKER_BIN" volume create "$TI_WORKSPACE_VOLUME" >/dev/null
fi

volume_probe="$("$DOCKER_BIN" run --rm -v "${TI_WORKSPACE_VOLUME}:${TI_WORKSPACE_MOUNT}" "$IMAGE_TAG" bash -lc "find '${TI_WORKSPACE_MOUNT}' -mindepth 1 -maxdepth 1 | head -n 1")"
if [[ -z "$volume_probe" ]]; then
  [[ -d "$SDK_SEED_ROOT" ]] || mac_builder_fail "missing TI SDK seed root at ${SDK_SEED_ROOT}"
  mac_builder_log "seeding ${TI_WORKSPACE_VOLUME} from ${SDK_SEED_ROOT}"
  "$DOCKER_BIN" run --rm --user 0:0 \
    -v "${SDK_SEED_ROOT}:/src:ro" \
    -v "${TI_WORKSPACE_VOLUME}:${TI_WORKSPACE_MOUNT}" \
    "$IMAGE_TAG" \
    bash -lc "cd /src && tar cf - . | tar xf - -C '${TI_WORKSPACE_MOUNT}'"
fi

"$DOCKER_BIN" run --rm --user 0:0 \
  -v "${TI_WORKSPACE_VOLUME}:${TI_WORKSPACE_MOUNT}" \
  "$IMAGE_TAG" \
  bash -lc "chown -R $(id -u):$(id -g) '${TI_WORKSPACE_MOUNT}'"

if "$DOCKER_BIN" ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  mac_builder_log "removing stale container ${CONTAINER_NAME}"
  "$DOCKER_BIN" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

run_id="$(date +%Y%m%d-%H%M%S)"
run_dir="${RUN_ROOT}/${CONTAINER_NAME}-${run_id}"
mkdir -p "$run_dir"
watch_log="${run_dir}/watch.log"
caffeinate_log="${run_dir}/caffeinate.log"

container_id="$("$DOCKER_BIN" run -d \
  --name "$CONTAINER_NAME" \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/beagley-builder-home \
  -e USER=builder \
  -e DL_DIR=/work/downloads \
  -e SSTATE_DIR=/work/sstate-cache \
  -e YOCTO_DL_DIR=/work/downloads \
  -e YOCTO_SSTATE_DIR=/work/sstate-cache \
  -e YOCTO_RESOURCE_PROFILE=moderate-memory \
  -e YOCTO_BITBAKE_RETRIES=6 \
  -e YOCTO_BITBAKE_REPLY_WAIT_SEC=600 \
  -e MACHINE_POLICY="$MACHINE_POLICY" \
  -e MACHINE="$MACHINE_NAME" \
  -e IMAGE="$IMAGE_NAME" \
  -v "${REPO_ROOT}:/workspace/beagley-cluster" \
  -v "${DOWNLOADS_DIR}:/work/downloads" \
  -v "${SSTATE_DIR}:/work/sstate-cache" \
  -v "${TI_WORKSPACE_VOLUME}:${TI_WORKSPACE_MOUNT}" \
  "$IMAGE_TAG" \
  bash -lc "cd /workspace/beagley-cluster && ./yocto/build-appliance-image.sh '${TI_WORKSPACE_MOUNT}/yocto-build' '${BUILD_DIR}'")"

nohup "$SCRIPT_DIR/watch-mac-build.sh" \
  --container "$CONTAINER_NAME" \
  --watch-log "$watch_log" \
  >"${run_dir}/watch.stdout.log" 2>&1 &
watch_pid="$!"

read -r -d '' caffeinate_cmd <<EOF || true
while "$(mac_builder_docker_bin)" ps --format '{{.Names}}' | grep -Fxq '${CONTAINER_NAME}'; do
  sleep 30
done
EOF

nohup caffeinate -dimsu /bin/bash -lc \
  "$caffeinate_cmd" \
  >"$caffeinate_log" 2>&1 &
caffeinate_pid="$!"

mac_builder_log "started ${CONTAINER_NAME} (${container_id})"
mac_builder_log "watchdog pid: ${watch_pid}"
mac_builder_log "caffeinate pid: ${caffeinate_pid}"
mac_builder_log "run directory: ${run_dir}"
mac_builder_log "follow progress with: $(mac_builder_docker_bin) logs -f ${CONTAINER_NAME}"
mac_builder_log "watchdog log: ${watch_log}"

for _ in {1..30}; do
  log_snippet="$("$DOCKER_BIN" logs --tail 40 "$CONTAINER_NAME" 2>&1 || true)"
  if printf '%s\n' "$log_snippet" | grep -Eq 'Running (noexec )?task [0-9]+ of [0-9]+|Parsing started'; then
    printf '%s\n' "$log_snippet"
    exit 0
  fi
  sleep 2
done

printf '%s\n' "$("$DOCKER_BIN" logs --tail 40 "$CONTAINER_NAME" 2>&1 || true)"
