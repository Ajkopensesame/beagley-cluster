#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"
REMOTE_ROOT="${BEAGLEY_QML_DEV_ROOT:-/opt/beagley-cluster/qml-dev}"
RESTART=1
HEALTH=1

usage() {
  cat <<'EOF'
Usage:
  ./tools/ui/beagley_sync_qml.sh [options]

Options:
  --host HOST          SSH target. Default: root@beagley-ai.local
  --remote-root PATH   Remote QML dev root. Default: /opt/beagley-cluster/qml-dev
                       Must be a plain absolute path with >= 3 components.
                       REFUSED: anything at/under /data/beagley-cluster, any path
                       segment named runtime-*, and any root (or parent directory of
                       it) on the target that holds a live-runtime marker
                       (launch.sh, bin/beagley_cluster, .live, ...). The board's live
                       QML root is such a tree: use /opt/beagley-cluster/qml-dev.
                       WARNING: it is deleted (rm -rf) and replaced on every sync,
                       so anything else in it (e.g. SkinShowOverride.qml) is wiped.
  --no-restart         Sync files without restarting beagley_cluster.
  --no-health          Skip post-restart health check.
  -h, --help           Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="$2"
      shift 2
      ;;
    --no-restart)
      RESTART=0
      shift
      ;;
    --no-health)
      HEALTH=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[beagley-ui] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# The sync runs `rm -rf` on REMOTE_ROOT (and on "${REMOTE_ROOT}.tmp") on the
# target as the ssh user (root by default), so refuse anything that is not a
# clearly scoped, plain absolute path. Returns non-zero and prints the reason
# to stderr when the path is unsafe.
validate_remote_root() {
  local root="$1"
  local rest first

  if [[ -z "$root" ]]; then
    echo "[beagley-ui] refusing empty remote root" >&2
    return 1
  fi
  if [[ "$root" == *"'"* ]]; then
    echo "[beagley-ui] remote root may not contain single quotes: $root" >&2
    return 1
  fi
  if [[ "$root" != /* ]]; then
    echo "[beagley-ui] remote root must be an absolute path: $root" >&2
    return 1
  fi
  # Whitelist: letters, digits, '.', '_', '-' and '/'. This rejects whitespace,
  # glob characters (* ? [ ]), quotes, '$', backticks, ';', '~', etc.
  if [[ ! "$root" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "[beagley-ui] remote root contains unsupported characters (allowed: A-Za-z0-9 . _ - /): $root" >&2
    return 1
  fi
  if [[ "$root" == *//* || "$root" == */ ]]; then
    echo "[beagley-ui] remote root may not contain '//' or a trailing '/': $root" >&2
    return 1
  fi
  if [[ "$root" == */./* || "$root" == */. || "$root" == */../* || "$root" == */.. ]]; then
    echo "[beagley-ui] remote root may not contain '.' or '..' path segments: $root" >&2
    return 1
  fi

  # The live board runs from /data/beagley-cluster/runtime-*/ (launch.sh, binary and an
  # isolated QML snapshot). This script rm -rf's its target, which would delete the live UI
  # (docs/BOARD_RUNBOOK.md 3.1). Never allowed, no override.
  if [[ "$root" == /data/beagley-cluster || "$root" == /data/beagley-cluster/* ]]; then
    echo "[beagley-ui] refusing live runtime location (/data/beagley-cluster/...): $root" >&2
    return 1
  fi
  if [[ "$root" == */runtime-* ]]; then
    echo "[beagley-ui] refusing a path with a runtime-* segment (live runtime layout): $root" >&2
    return 1
  fi

  rest="${root#/}"
  first="${rest%%/*}"
  # Require at least /<top>/<x>/<y> (e.g. /opt/beagley-cluster/qml-dev).
  if [[ "$rest" != */*/* ]]; then
    echo "[beagley-ui] remote root must have at least 3 path components (e.g. /opt/<x>/<y>): $root" >&2
    return 1
  fi
  case "$first" in
    bin|boot|dev|etc|lib|lib32|lib64|proc|root|run|sbin|sys|usr)
      echo "[beagley-ui] remote root may not be under system directory /$first: $root" >&2
      return 1
      ;;
  esac
  return 0
}

# Remote half of the live-runtime guard: walks REMOTE_ROOT and each of its ancestors
# (excluding /) on the target and reports the first live-runtime marker. Exit 3 = marker
# found (printed), 0 = none. Runs before anything is deleted. Markers: a launch script,
# the capture-once hook, the app binary, or an explicit .live / .beagley-live-runtime file.
live_runtime_probe_cmd() {
  cat <<EOF
# BEAGLEY_LIVE_PROBE
d='$1'
while [ -n "\$d" ] && [ "\$d" != / ]; do
  for m in launch.sh beagley-cluster-launch.sh capture-once.env bin/beagley_cluster beagley_cluster .live .beagley-live-runtime; do
    if [ -e "\$d/\$m" ]; then echo "\$d/\$m"; exit 3; fi
  done
  d=\$(dirname "\$d")
done
exit 0
EOF
}

validate_remote_root "$REMOTE_ROOT" || exit 2

MANIFEST="$(mktemp -t beagley-qml-manifest.XXXXXX)"
cleanup() {
  rm -f "$MANIFEST"
}
trap cleanup EXIT

{
  printf 'synced_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'source_path=%s\n' "$ROOT"
  printf 'git_branch=%s\n' "$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || printf unknown)"
  printf 'git_commit=%s\n' "$(cd "$ROOT" && git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
  printf 'git_dirty_count=%s\n' "$(cd "$ROOT" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  printf 'remote_root=%s\n' "$REMOTE_ROOT"
} >"$MANIFEST"

echo "[beagley-ui] Step 1: Verify SSH..."
ssh -o ConnectTimeout=5 "$HOST" "true"

echo "[beagley-ui] Step 1b: Check target is not a live runtime..."
set +e
marker="$(ssh "$HOST" "$(live_runtime_probe_cmd "$REMOTE_ROOT")")"
probe_rc=$?
set -e
if [[ "$probe_rc" -eq 3 ]]; then
  echo "[beagley-ui] refusing: $REMOTE_ROOT is (inside) a live runtime on $HOST - found marker: $marker" >&2
  echo "[beagley-ui] Nothing was deleted. Use a dedicated dev root such as /opt/beagley-cluster/qml-dev." >&2
  exit 2
elif [[ "$probe_rc" -ne 0 ]]; then
  echo "[beagley-ui] live-runtime check failed (ssh/probe exit $probe_rc); refusing to continue" >&2
  exit 1
fi

echo "[beagley-ui] Step 2: Sync QML to $HOST:$REMOTE_ROOT..."
# NOTE: this is a replace, not a merge. The remote dir is rebuilt from a tar of
# src/ui, so anything else in $REMOTE_ROOT (e.g. a hand-made SkinShowOverride.qml)
# is deleted and must be re-created after each sync.
echo "[beagley-ui] WARNING: will rm -rf on $HOST: '$REMOTE_ROOT' and '${REMOTE_ROOT}.tmp' (all other files there are lost, e.g. SkinShowOverride.qml)"
(
  cd "$ROOT"
  find src/ui -type f \( -name '*.qml' -o -name '*.js' -o -name 'qmldir' -o -path 'src/ui/assets/*' \) | sort | COPYFILE_DISABLE=1 tar -czf - -T -
) | ssh "$HOST" "set -e;
  tmp='${REMOTE_ROOT}.tmp';
  rm -rf \"\$tmp\";
  mkdir -p \"\$tmp\";
  tar -xzf - -C \"\$tmp\";
  rm -rf '$REMOTE_ROOT';
  mv \"\$tmp\" '$REMOTE_ROOT';
  chown -R root:root '$REMOTE_ROOT' 2>/dev/null || true;
  find '$REMOTE_ROOT/src/ui' -type f \( -name '*.qml' -o -name '*.js' -o -name 'qmldir' -o -path '*/assets/*' \) | wc -l"

echo "[beagley-ui] Step 2b: Write QML source manifest..."
ssh "$HOST" "cat > '$REMOTE_ROOT/.beagley-qml-manifest'" <"$MANIFEST"

if [[ "$RESTART" != "1" ]]; then
  echo "[beagley-ui] Sync complete; restart skipped"
  exit 0
fi

echo "[beagley-ui] Step 3: Restart beagley_cluster..."
ssh "$HOST" "systemctl reset-failed beagley_cluster && systemctl restart beagley_cluster"

if [[ "$HEALTH" != "1" ]]; then
  echo "[beagley-ui] Restart complete; health check skipped"
  exit 0
fi

echo "[beagley-ui] Step 4: Health check..."
if ! "$ROOT/skills/beagley-health-check/scripts/check.sh"; then
  echo "[beagley-ui] Health check failed; collecting debug output..."
  "$ROOT/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[beagley-ui] Complete"
