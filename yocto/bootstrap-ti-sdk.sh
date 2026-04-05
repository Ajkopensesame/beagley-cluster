#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${1:-$PWD/ti-sdk-11.00}"
WORKSPACE_NAME="${WORKSPACE_NAME:-yocto-build}"
OE_LAYERSETUP_REPO="${OE_LAYERSETUP_REPO:-https://git.ti.com/git/arago-project/oe-layersetup.git}"
OE_LAYERSETUP_REF="${OE_LAYERSETUP_REF:-master}"
TI_SDK_CONFIG_DIR="${TI_SDK_CONFIG_DIR:-configs/processor-sdk-analytics}"
TI_SDK_CONFIG_FILE="${TI_SDK_CONFIG_FILE:-processor-sdk-analytics-11.00.00-config.txt}"

fail() {
  echo "[yocto-bootstrap] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[yocto-bootstrap] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

remote_has_branch() {
  local repo="$1"
  local branch="$2"
  git ls-remote --exit-code --heads "$repo" "$branch" >/dev/null 2>&1
}

workspace_ready() {
  local root="$1"
  [[ -f "$root/build/conf/setenv" ]] || [[ -f "$root/oe-init-build-env" ]]
}

[[ "$(uname -s)" == "Linux" ]] || fail "run this bootstrap inside a Linux build host or VM"
require_cmd git

mkdir -p "$WORKSPACE_ROOT"
cd "$WORKSPACE_ROOT"

if [[ ! -d "$WORKSPACE_NAME/.git" ]]; then
  log "cloning oe-layersetup into ${WORKSPACE_NAME}"
  remote_has_branch "$OE_LAYERSETUP_REPO" "$OE_LAYERSETUP_REF" \
    || fail "branch ${OE_LAYERSETUP_REF} not found in ${OE_LAYERSETUP_REPO}"
  git clone --branch "$OE_LAYERSETUP_REF" "$OE_LAYERSETUP_REPO" "$WORKSPACE_NAME"
else
  log "reusing existing workspace ${WORKSPACE_NAME}"
fi

cd "$WORKSPACE_NAME"

if [[ -n "$OE_LAYERSETUP_REF" ]]; then
  remote_has_branch "$OE_LAYERSETUP_REPO" "$OE_LAYERSETUP_REF" \
    || fail "branch ${OE_LAYERSETUP_REF} not found in ${OE_LAYERSETUP_REPO}"
  git fetch origin "$OE_LAYERSETUP_REF" --tags
  git checkout "$OE_LAYERSETUP_REF"
fi

CONFIG_PATH="${TI_SDK_CONFIG_DIR}/${TI_SDK_CONFIG_FILE}"
[[ -f "$CONFIG_PATH" ]] || fail "missing TI config file: ${CONFIG_PATH}"

log "configuring TI SDK workspace from ${CONFIG_PATH}"
./oe-layertool-setup.sh -f "$CONFIG_PATH"

workspace_ready "$PWD" || fail "workspace setup completed without a usable TI environment entrypoint"

cat <<EOF
[yocto-bootstrap] workspace ready:
  root=${WORKSPACE_ROOT}/${WORKSPACE_NAME}
  config=${CONFIG_PATH}
  next:
    MACHINE_POLICY=board-bsp MACHINE=beagley-ai \\
      ./yocto/build-appliance-image.sh \\
      ${WORKSPACE_ROOT}/${WORKSPACE_NAME} build-beagley
EOF
