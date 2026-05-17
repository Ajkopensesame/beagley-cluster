#!/bin/bash
set -euo pipefail

REMOTE_TMP="/var/volatile/beagley_cluster.new"
REMOTE_ROLLBACK="/var/volatile/beagley_cluster.rollback"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${BEAGLEY_CLUSTER_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
source "$SCRIPT_DIR/../../beagley-common/scripts/ssh.sh"

echo "[DEPLOY] Step 1: Build Linux aarch64 target..."
cd "$BASE"

if [[ -n "${BEAGLEY_DEPLOY_BIN:-}" ]]; then
  BIN="$BEAGLEY_DEPLOY_BIN"
else
  branch="$(git -C "$BASE" branch --show-current 2>/dev/null || true)"
  dirty_count="$(git -C "$BASE" status --porcelain=v1 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$branch" != "codex/maplibre-native-yocto-build" || "${dirty_count:-1}" != "0" ]]; then
    echo "[DEPLOY] Refusing to build/deploy from non-canonical or dirty checkout." >&2
    echo "[DEPLOY] repo=$BASE branch=${branch:-detached} dirty=${dirty_count:-unknown}" >&2
    echo "[DEPLOY] Use tools/source_truth/build_canonical_yocto_app.sh, then set BEAGLEY_DEPLOY_BIN to the Yocto aarch64 binary." >&2
    exit 2
  fi
  "$BASE/tools/beagley_gpu/build_aarch64.sh"
  BUILD_DIR="${BEAGLEY_AARCH64_BUILD_DIR:-$BASE/build-beagley-aarch64}"
  BIN=$(find "$BUILD_DIR" -type f -name beagley_cluster | head -n 1)
fi

if [[ -z "${BIN:-}" || ! -f "$BIN" ]]; then
  echo "[DEPLOY] Built binary not found" >&2
  exit 2
fi

BIN_DESC=$(file "$BIN")

echo "[DEPLOY] Built binary: $BIN_DESC"

if [[ "$BIN_DESC" != *"ELF 64-bit"* || "$BIN_DESC" != *"aarch64"* ]]; then
  echo "[DEPLOY] Refusing to deploy non-Linux-aarch64 binary to BeagleY" >&2
  echo "[DEPLOY] Configure a Linux aarch64 cross-build or build on a BeagleY image before deploying." >&2
  exit 2
fi

echo "[DEPLOY] Step 2: Resolve BeagleY endpoint..."
if ! beagley_require_ssh_target; then
  echo "[DEPLOY] No reachable SSH endpoint resolved from $BEAGLEY_HOST_NAME" >&2
  exit 2
fi
echo "[DEPLOY] Using SSH target: $BEAGLEY_SSH_TARGET"

echo "[DEPLOY] Step 3: Transfer binary..."
beagley_ssh "mkdir -p /var/volatile && rm -f '$REMOTE_TMP' '$REMOTE_ROLLBACK' /tmp/beagley_cluster.new"
beagley_scp_to "$BIN" "$REMOTE_TMP"

echo "[DEPLOY] Step 4: Free old generated deploy backups..."
beagley_ssh "for path in /usr/bin/beagley_cluster.bak /usr/bin/beagley_cluster.bak.* /usr/bin/beagley_cluster.backup-* /usr/bin/beagley_cluster.compare.*; do [ -e \"\$path\" ] && rm -f \"\$path\"; done; true"

echo "[DEPLOY] Step 5: Install new version..."
beagley_ssh "bash -s" <<REMOTE
set -euo pipefail
restore_on_error() {
  echo "[DEPLOY] Install failed; attempting rollback" >&2
  if [ -s "$REMOTE_ROLLBACK" ]; then
    cp "$REMOTE_ROLLBACK" /usr/bin/beagley_cluster || true
    chmod 0755 /usr/bin/beagley_cluster || true
  fi
  systemctl start beagley_cluster || true
}
trap restore_on_error ERR
systemctl stop beagley_cluster || true
if [ -x /usr/bin/beagley_cluster ]; then
  cp /usr/bin/beagley_cluster "$REMOTE_ROLLBACK" || true
fi
cp "$REMOTE_TMP" /usr/bin/beagley_cluster
chmod 0755 /usr/bin/beagley_cluster
rm -f "$REMOTE_TMP"
sync
trap - ERR
REMOTE

echo "[DEPLOY] Step 6: Restart service..."
beagley_ssh "systemctl reset-failed beagley_cluster"
beagley_ssh "systemctl restart beagley_cluster"

echo "[DEPLOY] Step 7: Verify service..."
beagley_ssh "systemctl status beagley_cluster --no-pager"

echo "[DEPLOY] Step 8: Health check..."
if ! "$BASE/skills/beagley-health-check/scripts/check.sh"; then
  echo "[DEPLOY] Health check failed; collecting diagnostics..."
  "$BASE/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[DEPLOY] Complete"
