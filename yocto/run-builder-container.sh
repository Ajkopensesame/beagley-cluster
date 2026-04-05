#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-beagley-yocto-builder:11.00}"
CONTAINER_NAME="${CONTAINER_NAME:-beagley-yocto-builder}"
WORK_ROOT="${WORK_ROOT:-$REPO_ROOT/.yocto-work}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-$WORK_ROOT/downloads}"
SSTATE_DIR="${SSTATE_DIR:-$WORK_ROOT/sstate-cache}"
TI_WORKSPACE_VOLUME="${TI_WORKSPACE_VOLUME:-beagley-ti-sdk-11-workspace}"
TI_WORKSPACE_MOUNT="${TI_WORKSPACE_MOUNT:-/work/ti-sdk-11.00}"

fail() {
  echo "[yocto-docker] FAIL: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd docker

mkdir -p "$DOWNLOADS_DIR" "$SSTATE_DIR"

if ! docker volume inspect "$TI_WORKSPACE_VOLUME" >/dev/null 2>&1; then
  echo "[yocto-docker] creating workspace volume ${TI_WORKSPACE_VOLUME}"
  docker volume create "$TI_WORKSPACE_VOLUME" >/dev/null
fi

docker run --rm \
  -v "$TI_WORKSPACE_VOLUME:$TI_WORKSPACE_MOUNT" \
  alpine:3.20 \
  sh -lc "chown -R $(id -u):$(id -g) '$TI_WORKSPACE_MOUNT'"

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "[yocto-docker] building ${IMAGE_TAG}"
  docker build -t "$IMAGE_TAG" -f "$REPO_ROOT/yocto/Dockerfile.builder" "$REPO_ROOT"
fi

docker run --rm -it \
  --name "$CONTAINER_NAME" \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/beagley-builder-home \
  -e USER=builder \
  -e DL_DIR=/work/downloads \
  -e SSTATE_DIR=/work/sstate-cache \
  -e YOCTO_DL_DIR=/work/downloads \
  -e YOCTO_SSTATE_DIR=/work/sstate-cache \
  -v "$REPO_ROOT:/workspace/beagley-cluster" \
  -v "$DOWNLOADS_DIR:/work/downloads" \
  -v "$SSTATE_DIR:/work/sstate-cache" \
  -v "$TI_WORKSPACE_VOLUME:$TI_WORKSPACE_MOUNT" \
  "$IMAGE_TAG" \
  bash
