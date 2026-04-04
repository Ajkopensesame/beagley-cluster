#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${1:-}"
BUILD_DIR="${2:-build-beagley-cluster}"
MACHINE_NAME="${MACHINE:-}"
IMAGE_NAME="${IMAGE:-beagley-cluster-image}"
MACHINE_POLICY="${MACHINE_POLICY:-}"
YOCTO_DL_DIR="${YOCTO_DL_DIR:-}"
YOCTO_SSTATE_DIR="${YOCTO_SSTATE_DIR:-}"
YOCTO_RESOURCE_PROFILE="${YOCTO_RESOURCE_PROFILE:-auto}"
YOCTO_BB_NUMBER_THREADS="${YOCTO_BB_NUMBER_THREADS:-}"
YOCTO_BB_NUMBER_PARSE_THREADS="${YOCTO_BB_NUMBER_PARSE_THREADS:-}"
YOCTO_PARALLEL_MAKE="${YOCTO_PARALLEL_MAKE:-}"
YOCTO_PARALLEL_MAKEINST="${YOCTO_PARALLEL_MAKEINST:-}"
YOCTO_NINJAJOBS="${YOCTO_NINJAJOBS:-}"
YOCTO_BITBAKE_RETRIES="${YOCTO_BITBAKE_RETRIES:-3}"
YOCTO_GIT_FETCH_RETRIES="${YOCTO_GIT_FETCH_RETRIES:-6}"
YOCTO_BITBAKE_REPLY_WAIT_SEC="${YOCTO_BITBAKE_REPLY_WAIT_SEC:-300}"

fail() {
  echo "[yocto-build] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[yocto-build] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

replace_managed_block() {
  local file="$1"
  local marker="$2"
  local tmp
  local content

  tmp="$(mktemp)"
  content="$(cat)"

  awk -v begin="# BEGIN ${marker}" -v end="# END ${marker}" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"

  {
    printf "\n# BEGIN %s\n" "$marker"
    printf "%s\n" "$content"
    printf "# END %s\n" "$marker"
  } >> "$file"
}

remove_legacy_comment_block() {
  local file="$1"
  local header="$2"
  local tmp

  tmp="$(mktemp)"
  awk -v header="$header" '
    skip {
      if ($0 ~ /^[[:space:]]*$/) {
        skip = 0
      }
      next
    }

    $0 == header {
      skip = 1
      next
    }

    { print }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

cleanup_legacy_beagley_local_conf() {
  local file="$1"

  [[ -f "$file" ]] || fail "missing local.conf: $file"
  remove_legacy_comment_block "$file" "# beagley-cluster appliance defaults"
  remove_legacy_comment_block "$file" "# beagley-cluster download cache"
  remove_legacy_comment_block "$file" "# beagley-cluster sstate cache"
}

resolve_resource_profile() {
  local detected_limit_bytes=""
  local resolved_profile="$YOCTO_RESOURCE_PROFILE"

  if [[ "$resolved_profile" == "auto" ]]; then
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
      detected_limit_bytes="$(< /sys/fs/cgroup/memory.max)"
      if [[ "$detected_limit_bytes" == "max" ]]; then
        detected_limit_bytes=""
      fi
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
      detected_limit_bytes="$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    fi

    if [[ -n "$detected_limit_bytes" && "$detected_limit_bytes" -le 6442450944 ]]; then
      resolved_profile="low-memory"
    else
      resolved_profile="balanced"
    fi
  fi

  case "$resolved_profile" in
    balanced)
      : "${YOCTO_BB_NUMBER_THREADS:=4}"
      : "${YOCTO_BB_NUMBER_PARSE_THREADS:=4}"
      : "${YOCTO_PARALLEL_MAKE:=-j 4}"
      : "${YOCTO_PARALLEL_MAKEINST:=-j 4}"
      : "${YOCTO_NINJAJOBS:=-j 4}"
      ;;
    moderate-memory)
      : "${YOCTO_BB_NUMBER_THREADS:=2}"
      : "${YOCTO_BB_NUMBER_PARSE_THREADS:=2}"
      : "${YOCTO_PARALLEL_MAKE:=-j 2}"
      : "${YOCTO_PARALLEL_MAKEINST:=-j 2}"
      : "${YOCTO_NINJAJOBS:=-j 2}"
      ;;
    low-memory)
      : "${YOCTO_BB_NUMBER_THREADS:=1}"
      : "${YOCTO_BB_NUMBER_PARSE_THREADS:=1}"
      : "${YOCTO_PARALLEL_MAKE:=-j 1}"
      : "${YOCTO_PARALLEL_MAKEINST:=-j 1}"
      : "${YOCTO_NINJAJOBS:=-j 1}"
      ;;
    *)
      fail "unsupported YOCTO_RESOURCE_PROFILE=${resolved_profile}; expected auto, balanced, moderate-memory, or low-memory"
      ;;
  esac

  log "using ${resolved_profile} resource profile"
}

ensure_beagley_layer() {
  local layer_path="$1"
  local bblayers_conf="conf/bblayers.conf"

  [[ -f "$bblayers_conf" ]] || fail "missing bblayers.conf in $PWD"
  if grep -Fq "$layer_path" "$bblayers_conf"; then
    return
  fi

  log "adding layer: $layer_path"
  bitbake-layers add-layer "$layer_path"
}

beagley_ai_bsp_available() {
  local sdk_root="$1"
  [[ -f "$sdk_root/sources/meta-ti/meta-beagle/conf/machine/beagley-ai.conf" ]]
}

resolve_machine_defaults() {
  local sdk_root="$1"

  if [[ -z "$MACHINE_NAME" && -z "$MACHINE_POLICY" ]] && beagley_ai_bsp_available "$sdk_root"; then
    MACHINE_NAME="beagley-ai"
    MACHINE_POLICY="board-bsp"
    log "detected BeagleY AI BSP support; defaulting to MACHINE=${MACHINE_NAME} (policy=${MACHINE_POLICY})"
    return
  fi

  if [[ -z "$MACHINE_NAME" ]]; then
    if [[ "$MACHINE_POLICY" == "board-bsp" ]]; then
      beagley_ai_bsp_available "$sdk_root" || fail "MACHINE_POLICY=board-bsp requires BeagleY BSP support in ${sdk_root}/sources/meta-ti/meta-beagle"
      MACHINE_NAME="beagley-ai"
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

cleanup_stale_bitbake_state() {
  local build_root="$PWD"
  local bitbake_sock="$build_root/bitbake.sock"
  local bitbake_lock="$build_root/bitbake.lock"
  local -a active_client_pids=()
  local -a server_pids=()

  mapfile -t active_client_pids < <(
    ps -eo pid=,comm=,args= | awk -v build_root="$build_root" '
      $2 == "python3" && index($0, "/sources/bitbake/bin/bitbake ") && index($0, build_root) { print $1 }
    '
  )
  if [[ ${#active_client_pids[@]} -gt 0 ]]; then
    fail "active bitbake client already running for $build_root: ${active_client_pids[*]}"
  fi

  mapfile -t server_pids < <(
    ps -eo pid=,comm=,args= | awk -v bitbake_sock="$bitbake_sock" '
      $2 == "python3" && index($0, "/sources/bitbake/bin/bitbake-server") && index($0, bitbake_sock) { print $1 }
    '
  )

  if [[ ${#server_pids[@]} -gt 0 ]]; then
    log "clearing stale bitbake server state for $build_root"
    kill "${server_pids[@]}" 2>/dev/null || true
    sleep 1
    kill -9 "${server_pids[@]}" 2>/dev/null || true
  fi

  rm -f "$bitbake_sock" "$bitbake_lock"
}

recent_fetch_failure_detected() {
  local work_root="$PWD/arago-tmp-default-glibc/work"

  [[ -d "$work_root" ]] || return 1

  find "$work_root" -path '*/temp/log.do_*' -type f -mmin -90 -print0 2>/dev/null \
    | xargs -0 grep -El 'Fetcher failure|Bitbake Fetcher Error|Unable to fetch URL from any source' 2>/dev/null \
    | grep -q .
}

recent_bitbake_timeout_detected() {
  local cooker_log="$PWD/bitbake-cookerdaemon.log"
  local server_timeout_pattern='Timeout while waiting for a reply from the bitbake server|No reply from server in [0-9]+s|Idle loop didn'\''t finish queued commands after 30s'

  [[ -f "$cooker_log" ]] || return 1
  grep -Eq "$server_timeout_pattern" "$cooker_log"
}

patch_bitbake_reply_timeout() {
  local sdk_root="$1"
  local process_py="$sdk_root/sources/bitbake/lib/bb/server/process.py"
  local reply_wait="$YOCTO_BITBAKE_REPLY_WAIT_SEC"
  local total_wait=$((reply_wait * 2))

  [[ -f "$process_py" ]] || return 0

  if grep -Fq 'No reply from server in 30s' "$process_py"; then
    log "patching BitBake reply timeout to ${reply_wait}s/${total_wait}s for this constrained builder"
    sed -i "s/self.recv.poll(30)/self.recv.poll(${reply_wait})/g" "$process_py"
    sed -i "s/No reply from server in 30s/No reply from server in ${reply_wait}s/g" "$process_py"
    sed -i "s/bitbake server (60s at %s)/bitbake server (${total_wait}s at %s)/g" "$process_py"
  fi

  return 0
}

run_bitbake_with_retries() {
  local attempt=1
  local delay_seconds=20
  local status=0

  while true; do
    if bitbake "$IMAGE_NAME"; then
      return 0
    else
      status=$?
    fi

    if (( attempt >= YOCTO_BITBAKE_RETRIES )); then
      return "$status"
    fi

    if ! recent_fetch_failure_detected && ! recent_bitbake_timeout_detected; then
      return "$status"
    fi

    log "bitbake hit a retryable failure; retrying attempt $((attempt + 1))/${YOCTO_BITBAKE_RETRIES} after ${delay_seconds}s"
    cleanup_stale_bitbake_state
    sleep "$delay_seconds"
    attempt=$((attempt + 1))
    delay_seconds=$((delay_seconds * 2))
  done
}

source_ti_environment() {
  local sdk_root="$1"
  local build_dir="$2"

  if [[ -d "$sdk_root/sources/bitbake/bin" ]]; then
    PATH="$sdk_root/sources/bitbake/bin:$PATH"
    while IFS= read -r -d '' scripts_dir; do
      PATH="$scripts_dir:$PATH"
    done < <(find "$sdk_root/sources" -maxdepth 2 -name scripts -type d -print0)
    export PATH
    export BUILDDIR="$sdk_root/build"
    cd "$BUILDDIR"
    return
  fi

  if [[ -f "$sdk_root/oe-init-build-env" ]]; then
    # shellcheck disable=SC1091
    source "$sdk_root/oe-init-build-env" "$build_dir" >/dev/null
    return
  fi

  if [[ -f "$sdk_root/build/conf/setenv" ]]; then
    # shellcheck disable=SC1091
    source "$sdk_root/build/conf/setenv"
    cd "${BUILDDIR:-$sdk_root/build}"
    return
  fi

  fail "missing TI build environment entrypoint in $sdk_root"
}

resolve_deploy_dir() {
  local build_dir="$1"
  local deploy_dir="${build_dir}/tmp/deploy/images/${MACHINE_NAME}"

  if [[ ! -d "$deploy_dir" ]]; then
    for candidate in \
      "${build_dir}/deploy-ti/images/${MACHINE_NAME}" \
      "${build_dir}/deploy/images/${MACHINE_NAME}"
    do
      if [[ -d "$candidate" ]]; then
        deploy_dir="$candidate"
        break
      fi
    done
  fi

  [[ -d "$deploy_dir" ]] || fail "deploy dir not found: $deploy_dir"
  printf '%s\n' "$deploy_dir"
}

latest_wic_image_path() {
  local deploy_dir="$1"
  find "$deploy_dir" -maxdepth 1 \
    \( -name "${IMAGE_NAME}-${MACHINE_NAME}*.wic" -o -name "${IMAGE_NAME}-${MACHINE_NAME}*.wic.xz" \) \
    | sort \
    | tail -n 1
}

latest_bmap_path() {
  local deploy_dir="$1"
  find "$deploy_dir" -maxdepth 1 -name "${IMAGE_NAME}-${MACHINE_NAME}*.wic.bmap" \
    | sort \
    | tail -n 1
}

latest_rootfs_manifest_path() {
  local deploy_dir="$1"
  find "$deploy_dir" -maxdepth 1 -name "*.rootfs.manifest" \
    | sort \
    | tail -n 1
}

latest_rootfs_tar_path() {
  local deploy_dir="$1"
  find "$deploy_dir" -maxdepth 1 -name "*.rootfs.tar.xz" \
    | sort \
    | tail -n 1
}

manifest_contains_package() {
  local manifest_path="$1"
  local pattern="$2"
  awk -v pattern="$pattern" '
    $1 ~ pattern {
      found = 1
      exit
    }
    END {
      exit !found
    }
  ' "$manifest_path"
}

require_manifest_package() {
  local manifest_path="$1"
  local pattern="$2"
  local description="$3"
  manifest_contains_package "$manifest_path" "$pattern" || fail "rootfs manifest missing ${description} (pattern: ${pattern})"
}

package_file_listing() {
  local package_name="$1"
  oe-pkgdata-util list-pkg-files "$package_name" 2>/dev/null || true
}

require_package_path_regex() {
  local package_name="$1"
  local regex="$2"
  local description="$3"
  local files

  files="$(package_file_listing "$package_name")"
  [[ -n "$files" ]] || fail "unable to inspect package payload for ${package_name} via oe-pkgdata-util"
  printf '%s\n' "$files" | grep -Eq "$regex" || fail "package ${package_name} missing ${description}"
}

require_deploy_artifact() {
  local deploy_dir="$1"
  local description="$2"
  local pattern="$3"

  find "$deploy_dir" -maxdepth 1 -name "$pattern" | grep -q . || fail "deploy dir missing ${description} (${pattern})"
}

latest_wks_export_path() {
  local deploy_dir="$1"
  find "$deploy_dir" -maxdepth 1 -name "${IMAGE_NAME}-*.wks" -printf '%T@ %p\n' \
    | sort -n \
    | tail -n 1 \
    | awk '{print $2}'
}

require_file_contains_regex() {
  local file_path="$1"
  local description="$2"
  local regex="$3"

  [[ -f "$file_path" ]] || fail "missing ${description}: ${file_path}"
  grep -Eq "$regex" "$file_path" || fail "${description} missing expected content (${regex})"
}

require_tar_contains_path() {
  local tar_path="$1"
  local description="$2"
  local expected_path="$3"
  local listing

  [[ -f "$tar_path" ]] || fail "missing ${description} archive: ${tar_path}"
  listing="$(tar -tf "$tar_path")"
  grep -Fqx -- "$expected_path" <<<"$listing" || fail "${description} missing expected path (${expected_path})"
}

validate_release_image() {
  local build_dir="$1"
  local deploy_dir image_path bmap_path rootfs_manifest rootfs_tar validation_report
  local image_env_path wks_export_path extlinux_path uenv_path

  require_cmd oe-pkgdata-util

  deploy_dir="$(resolve_deploy_dir "$build_dir")"
  image_path="$(latest_wic_image_path "$deploy_dir")"
  bmap_path="$(latest_bmap_path "$deploy_dir")"
  rootfs_manifest="$(latest_rootfs_manifest_path "$deploy_dir")"
  rootfs_tar="$(latest_rootfs_tar_path "$deploy_dir")"
  image_env_path="${deploy_dir}/${IMAGE_NAME}.env"
  wks_export_path="$(latest_wks_export_path "$deploy_dir")"
  extlinux_path="${deploy_dir}/extlinux.conf"
  uenv_path="${deploy_dir}/uEnv.txt"

  [[ -n "$image_path" ]] || fail "unable to find built wic image in $deploy_dir"
  [[ -n "$bmap_path" ]] || fail "unable to find built wic.bmap in $deploy_dir"
  [[ -n "$rootfs_manifest" ]] || fail "unable to find rootfs manifest in $deploy_dir"
  [[ -n "$rootfs_tar" ]] || fail "unable to find rootfs tarball in $deploy_dir"

  validation_report="${build_dir}/beagley-cluster-image-validation.txt"
  {
    echo "generated_at_utc=$(date -u +%Y%m%dT%H%M%SZ)"
    echo "machine=${MACHINE_NAME}"
    echo "machine_policy=${MACHINE_POLICY}"
    echo "deploy_dir=${deploy_dir}"
    echo "image_path=${image_path}"
    echo "bmap_path=${bmap_path}"
    echo "rootfs_manifest=${rootfs_manifest}"
    echo "rootfs_tar=${rootfs_tar}"
    echo "image_env_path=${image_env_path}"
    echo "wks_export_path=${wks_export_path:-missing}"
  } >"$validation_report"

  if [[ "$MACHINE_POLICY" == "board-bsp" || "$MACHINE_NAME" == "beagley-ai" ]]; then
    [[ "$MACHINE_NAME" == "beagley-ai" ]] || fail "board-bsp validation expects MACHINE=beagley-ai, got ${MACHINE_NAME}"
    require_deploy_artifact "$deploy_dir" "BeagleY tiboot3" "tiboot3*.bin"
    require_deploy_artifact "$deploy_dir" "BeagleY tispl" "tispl*.bin"
    require_deploy_artifact "$deploy_dir" "BeagleY U-Boot image" "u-boot*.img"
    require_deploy_artifact "$deploy_dir" "BeagleY kernel image" "Image*"
    require_deploy_artifact "$deploy_dir" "BeagleY device tree" "k3-am67a-beagley-ai*.dtb"
    if [[ -n "$wks_export_path" ]]; then
      require_file_contains_regex "$wks_export_path" "BeagleY board-bsp WKS export" 'bootimg-efi'
    fi
    require_file_contains_regex "$image_env_path" "BeagleY image boot payload contract" '^IMAGE_BOOT_FILES=.*Image'
    require_file_contains_regex "$image_env_path" "BeagleY image EFI boot payload contract" '^IMAGE_EFI_BOOT_FILES=.*Image'
    require_file_contains_regex "$image_env_path" "BeagleY image DTB payload contract" 'k3-am67a-beagley-ai\.dtb;dtb/ti/k3-am67a-beagley-ai\.dtb'
    require_file_contains_regex "$uenv_path" "BeagleY uEnv DTB fallback" 'k3-am67a-beagley-ai\.dtb'
    echo "boot_artifacts=beagley-ai-ok" >>"$validation_report"
    echo "boot_layout=efi-grub" >>"$validation_report"
  else
    echo "boot_artifacts=ti-sdk-policy" >>"$validation_report"
  fi

  require_manifest_package "$rootfs_manifest" '^beagley-cluster$' "beagley-cluster package"
  require_manifest_package "$rootfs_manifest" '^packagegroup-beagley-cluster$' "runtime packagegroup"
  require_manifest_package "$rootfs_manifest" '^openssh($|-.*)' "OpenSSH runtime"
  require_manifest_package "$rootfs_manifest" '^kmod$' "kmod for lsmod"
  require_manifest_package "$rootfs_manifest" '^(kmscube|mesa-demos($|-.*)|mesa-demos-eglinfo$)$' "GPU probe prerequisite (kmscube or eglinfo provider)"
  require_tar_contains_path "$rootfs_tar" "rootfs networkd runtime" './usr/lib/systemd/system/systemd-networkd.service'
  echo "rootfs_contract=ok" >>"$validation_report"

  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/usr/bin/beagley_cluster$' "/usr/bin/beagley_cluster"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/usr/bin/beagley-cluster-launch\.sh$' "launch wrapper"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/usr/bin/beagley-gpu-gate$' "GPU gate helper"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/(usr/)?lib/systemd/system/beagley-cluster\.service$' "cluster systemd unit"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/(usr/)?lib/systemd/system/beagley-cluster-gpu-probe\.service$' "GPU probe systemd unit"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/(usr/)?lib/systemd/system/beagley-cluster-provision\.service$' "provisioning systemd unit"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/usr/libexec/beagley-cluster/beagley-cluster-gpu-probe\.sh$' "GPU probe script"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/usr/libexec/beagley-cluster/beagley-cluster-provision\.sh$' "provisioning script"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/etc/default/beagley-cluster$' "default environment file"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/etc/systemd/network/05-beagley-eth-debug\.network$' "deterministic wired debug network file"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/etc/systemd/network/55-beagley-usb-recovery\.network$' "deterministic USB recovery network file"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/etc/systemd/network/12-en\.network$' "Ethernet DHCP networkd override for en* interfaces"
  require_package_path_regex "beagley-cluster" '(^|[[:space:]])/etc/systemd/journald\.conf\.d/persistent\.conf$' "persistent journald config"
  echo "package_payload=ok" >>"$validation_report"
  echo "result=pass" >>"$validation_report"

  log "validated flashable image contents; report at $validation_report"
}

[[ -n "$SDK_ROOT" ]] || fail "usage: $0 <ti-sdk-root> [build-dir]"
[[ -d "$SDK_ROOT" ]] || fail "sdk root not found: $SDK_ROOT"
resolve_machine_defaults "$SDK_ROOT"
case "$MACHINE_POLICY" in
  ti-sdk)
    if [[ "$MACHINE_NAME" != "j722s-evm" ]]; then
      log "MACHINE_POLICY=ti-sdk with custom MACHINE=${MACHINE_NAME}"
    fi
    ;;
  board-bsp)
    if [[ "$MACHINE_NAME" == "j722s-evm" ]]; then
      fail "MACHINE_POLICY=board-bsp requires a board-specific MACHINE, not j722s-evm"
    fi
    ;;
  *)
    fail "unsupported MACHINE_POLICY=${MACHINE_POLICY}; expected ti-sdk or board-bsp"
    ;;
esac

cd "$SDK_ROOT"
patch_bitbake_reply_timeout "$SDK_ROOT"
source_ti_environment "$SDK_ROOT" "$BUILD_DIR"

cleanup_stale_bitbake_state
resolve_resource_profile
if [[ "$MACHINE_POLICY" == "board-bsp" ]]; then
  ensure_beagley_layer "$SDK_ROOT/sources/meta-ti/meta-beagle"
fi
ensure_beagley_layer "$REPO_ROOT/yocto/meta-beagley-cluster"

cleanup_legacy_beagley_local_conf conf/local.conf

replace_managed_block conf/local.conf "beagley-cluster appliance defaults" <<EOF
MACHINE ?= "${MACHINE_NAME}"
IMAGE_FSTYPES += "wic wic.bmap"
BEAGLEY_MACHINE_POLICY ?= "${MACHINE_POLICY}"
BEAGLEY_CLUSTER_GIT_BRANCH ?= "main"
EOF

if [[ -n "$YOCTO_DL_DIR" ]]; then
  replace_managed_block conf/local.conf "beagley-cluster download cache" <<EOF
DL_DIR = "${YOCTO_DL_DIR}"
EOF
fi

if [[ -n "$YOCTO_SSTATE_DIR" ]]; then
  replace_managed_block conf/local.conf "beagley-cluster sstate cache" <<EOF
SSTATE_DIR = "${YOCTO_SSTATE_DIR}"
EOF
fi

replace_managed_block conf/local.conf "beagley-cluster builder resource defaults" <<EOF
BB_NUMBER_THREADS = "${YOCTO_BB_NUMBER_THREADS}"
BB_NUMBER_PARSE_THREADS = "${YOCTO_BB_NUMBER_PARSE_THREADS}"
PARALLEL_MAKE = "${YOCTO_PARALLEL_MAKE}"
PARALLEL_MAKEINST = "${YOCTO_PARALLEL_MAKEINST}"
NINJAJOBS = "${YOCTO_NINJAJOBS}"
BB_SIGNATURE_HANDLER = "OEBasicHash"
BB_HASHSERVE = ""
FETCHCMD_git = "${REPO_ROOT}/yocto/git-retry-wrapper.sh"
YOCTO_GIT_FETCH_RETRIES = "${YOCTO_GIT_FETCH_RETRIES}"
# Appliance releases do not ship TI source side-packages, and disabling them
# avoids huge git repacks that are not needed for the runtime image.
CREATE_SRCIPK:pn-linux-ti-staging = "0"
CREATE_SRCIPK:pn-linux-ti-staging-rt = "0"
CREATE_SRCIPK:pn-u-boot-ti-staging = "0"
EOF

log "building $IMAGE_NAME for MACHINE=${MACHINE_NAME} (policy=${MACHINE_POLICY})"
if ! run_bitbake_with_retries; then
  fail "bitbake failed for ${IMAGE_NAME}"
fi

validate_release_image "$PWD"

log "packaging flashable release artifact"
"$REPO_ROOT/yocto/package-appliance-release.sh" "$PWD" "$SDK_ROOT"

log "done"
