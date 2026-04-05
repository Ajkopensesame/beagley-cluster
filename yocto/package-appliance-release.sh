#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-}"
SDK_ROOT="${2:-}"
IMAGE_NAME="${IMAGE:-beagley-cluster-image}"
MACHINE_NAME="${MACHINE:-}"
MACHINE_POLICY="${MACHINE_POLICY:-}"

fail() {
  echo "[yocto-release] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[yocto-release] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

resolve_machine() {
  local local_conf="$1/conf/local.conf"
  [[ -n "$MACHINE_NAME" ]] && return 0
  [[ -f "$local_conf" ]] || return 0
  MACHINE_NAME="$(
    awk -F'"' '
      /^[[:space:]]*MACHINE[[:space:]]*\?*=/ {
        if ($2 != "") {
          print $2;
          exit
        }
      }
    ' "$local_conf"
  )"
}

resolve_branch() {
  local local_conf="$1/conf/local.conf"
  [[ -f "$local_conf" ]] || return 0
  awk -F'"' '
    /^[[:space:]]*BEAGLEY_CLUSTER_GIT_BRANCH[[:space:]]*\?*=/ {
      if ($2 != "") {
        print $2;
        exit
      }
    }
  ' "$local_conf"
}

resolve_machine_policy() {
  local local_conf="$1/conf/local.conf"
  [[ -n "$MACHINE_POLICY" ]] && return 0
  [[ -f "$local_conf" ]] || return 0
  MACHINE_POLICY="$(
    awk -F'"' '
      /^[[:space:]]*BEAGLEY_MACHINE_POLICY[[:space:]]*\?*=/ {
        if ($2 != "") {
          print $2;
          exit
        }
      }
    ' "$local_conf"
  )"
}

manifest_version_for() {
  local manifest_path="$1"
  local pattern="$2"
  awk -v pattern="$pattern" '
    $1 ~ pattern {
      print $3;
      exit
    }
  ' "$manifest_path"
}

kernel_version_for() {
  local manifest_path="$1"
  local version
  version="$(manifest_version_for "$manifest_path" "^kernel(-image|-modules|-base)?$")"
  if [[ -n "$version" ]]; then
    printf '%s\n' "$version"
    return
  fi
  version="$(awk '/^kernel-/ { print $3; exit }' "$manifest_path")"
  printf '%s\n' "$version"
}

write_flash_instructions() {
  local output_path="$1"
  local image_file="$2"
  local bmap_file="$3"
  cat >"$output_path" <<EOF
# Flash Instructions

1. Insert the production boot media into the host machine.
2. Identify the correct device node, for example \`/dev/sdX\`.
3. Unmount any mounted partitions from that device.
4. Preferred flash path:
   \`\`\`bash
   sudo bmaptool copy ${image_file} /dev/sdX
   \`\`\`
5. If \`bmaptool\` is unavailable, use a raw write path:
   \`\`\`bash
   sudo dd if=${image_file} of=/dev/sdX bs=16M status=progress conv=fsync
   \`\`\`
6. After flashing, place optional provisioning overrides on the boot partition:
   - \`beagley-cluster.env\`
   - \`beagley-cluster.hostname\`
7. On macOS hosts, use the repo helper:
   \`\`\`bash
   ./yocto/flash-appliance-image-macos.sh ${image_file} /dev/diskN
   \`\`\`

Associated BMAP file: ${bmap_file}
EOF
}

[[ -n "$BUILD_DIR" ]] || fail "usage: $0 <yocto-build-dir> [ti-sdk-root]"
[[ -d "$BUILD_DIR" ]] || fail "build dir not found: $BUILD_DIR"
require_cmd git
require_cmd sha256sum

resolve_machine "$BUILD_DIR"
resolve_machine_policy "$BUILD_DIR"
[[ -n "$MACHINE_NAME" ]] || fail "unable to resolve MACHINE from ${BUILD_DIR}/conf/local.conf"

DEPLOY_DIR="${BUILD_DIR}/tmp/deploy/images/${MACHINE_NAME}"
if [[ ! -d "$DEPLOY_DIR" ]]; then
  for candidate in \
    "${BUILD_DIR}/deploy-ti/images/${MACHINE_NAME}" \
    "${BUILD_DIR}/deploy/images/${MACHINE_NAME}"
  do
    if [[ -d "$candidate" ]]; then
      DEPLOY_DIR="$candidate"
      break
    fi
  done
fi
[[ -d "$DEPLOY_DIR" ]] || fail "deploy dir not found: $DEPLOY_DIR"

IMAGE_PATH="$(
  find "$DEPLOY_DIR" -maxdepth 1 \
    \( -name "${IMAGE_NAME}-${MACHINE_NAME}*.wic" -o -name "${IMAGE_NAME}-${MACHINE_NAME}*.wic.xz" \) \
    | sort \
    | tail -n 1
)"
[[ -n "$IMAGE_PATH" ]] || fail "unable to find built wic image in $DEPLOY_DIR"

BMAP_PATH="$(
  find "$DEPLOY_DIR" -maxdepth 1 -name "${IMAGE_NAME}-${MACHINE_NAME}*.wic.bmap" \
    | sort \
    | tail -n 1
)"
[[ -n "$BMAP_PATH" ]] || fail "unable to find built wic.bmap in $DEPLOY_DIR"

ROOTFS_MANIFEST="$(
  find "$DEPLOY_DIR" -maxdepth 1 -name "*.rootfs.manifest" \
    | sort \
    | tail -n 1
)"
[[ -n "$ROOTFS_MANIFEST" ]] || fail "unable to find rootfs manifest in $DEPLOY_DIR"

VALIDATION_REPORT="${BUILD_DIR}/beagley-cluster-image-validation.txt"
VALIDATION_REPORT_BASENAME=""

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RELEASE_DIR="${BUILD_DIR}/release/${IMAGE_NAME}-${MACHINE_NAME}-${STAMP}"
mkdir -p "$RELEASE_DIR"

cp "$IMAGE_PATH" "$RELEASE_DIR/"
cp "$BMAP_PATH" "$RELEASE_DIR/"
cp "$ROOTFS_MANIFEST" "$RELEASE_DIR/"
if [[ -f "$VALIDATION_REPORT" ]]; then
  cp "$VALIDATION_REPORT" "$RELEASE_DIR/"
  VALIDATION_REPORT_BASENAME="$(basename "$VALIDATION_REPORT")"
fi

APP_BRANCH="$(resolve_branch "$BUILD_DIR")"
APP_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
IMAGE_BASENAME="$(basename "$IMAGE_PATH")"
BMAP_BASENAME="$(basename "$BMAP_PATH")"
MANIFEST_OUTPUT="${RELEASE_DIR}/image-manifest.txt"

cat >"$MANIFEST_OUTPUT" <<EOF
generated_at_utc=${STAMP}
ti_sdk_root=${SDK_ROOT:-unknown}
machine=${MACHINE_NAME}
machine_policy=${MACHINE_POLICY:-unknown}
image=${IMAGE_NAME}
app_branch=${APP_BRANCH:-unknown}
app_commit=${APP_COMMIT}
kernel_version=$(kernel_version_for "$ROOTFS_MANIFEST")
sgx_userspace_version=$(manifest_version_for "$ROOTFS_MANIFEST" "^ti-sgx")
mesa_version=$(manifest_version_for "$ROOTFS_MANIFEST" "^(mesa|libegl-mesa|libgbm|libgl1-mesa-dri)")
image_file=${IMAGE_BASENAME}
bmap_file=${BMAP_BASENAME}
rootfs_manifest=$(basename "$ROOTFS_MANIFEST")
EOF

if [[ -n "$VALIDATION_REPORT_BASENAME" ]]; then
  echo "validation_report=${VALIDATION_REPORT_BASENAME}" >>"$MANIFEST_OUTPUT"
fi

CHECKSUM_INPUTS=(
  "$IMAGE_BASENAME"
  "$BMAP_BASENAME"
  "$(basename "$ROOTFS_MANIFEST")"
  "$(basename "$MANIFEST_OUTPUT")"
)
if [[ -n "$VALIDATION_REPORT_BASENAME" ]]; then
  CHECKSUM_INPUTS+=("$VALIDATION_REPORT_BASENAME")
fi

(cd "$RELEASE_DIR" && sha256sum "${CHECKSUM_INPUTS[@]}" >SHA256SUMS)
write_flash_instructions "${RELEASE_DIR}/flash-instructions.md" "$IMAGE_BASENAME" "$BMAP_BASENAME"

log "packaged release at $RELEASE_DIR"
