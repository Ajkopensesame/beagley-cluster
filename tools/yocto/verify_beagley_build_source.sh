#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${YOCTO_BUILD_DIR:-/home/pneumaion/ti-sdk-11.00/yocto-build/build}"
EXPECTED_REPO="${BEAGLEY_EXPECTED_REPO:-$ROOT}"
EXPECTED_BRANCH="${BEAGLEY_EXPECTED_BRANCH:-}"
EXPECTED_COMMIT="${BEAGLEY_EXPECTED_COMMIT:-}"
SOURCE_REMOTE="${BEAGLEY_SOURCE_REMOTE:-}"
REQUIRE_REMOTE_REF="${BEAGLEY_REQUIRE_REMOTE_REF:-0}"
FAIL_DIRTY=0
MANIFEST_PATH=""

usage() {
  cat <<'EOF'
Usage:
  tools/yocto/verify_beagley_build_source.sh [options]

Verifies the Yocto build is wired to the checkout, branch, and commit that we
intend to build. This prevents accidentally building a stale EliteBook checkout
or a different branch than the one being edited.

Options:
  --build-dir DIR          Yocto build dir. Default: YOCTO_BUILD_DIR or
                           /home/pneumaion/ti-sdk-11.00/yocto-build/build
  --expected-repo DIR      Repo that must own yocto/meta-beagley-cluster.
                           Default: this script's repo root.
  --expected-branch NAME   Branch that local.conf must build.
  --expected-commit SHA    Commit that must be at HEAD.
  --source-remote REMOTE   Remote name or URL to compare against when
                           --require-remote-ref is set. Default: origin.
  --require-remote-ref     Fail unless the configured branch's remote tip
                           exactly matches the build repo HEAD.
  --fail-dirty             Fail if the build source checkout has uncommitted
                           changes. Without this, dirty state is reported as a
                           warning because Yocto builds the committed git ref.
  --write-manifest PATH    Write key=value source manifest.
EOF
}

fail() {
  echo "[source-check] FAIL: $*" >&2
  exit 1
}

warn() {
  echo "[source-check] WARN: $*" >&2
}

clean_path() {
  local value="$1"
  value="${value%\\}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s\n' "$value"
}

conf_value() {
  local key="$1"
  local file="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*([?:+.]*)?=" {
      sub(/^[^=]*=/, "", $0)
      sub(/[[:space:]]*#.*/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/^["'\'']|["'\'']$/, "", $0)
      value = $0
    }
    END { if (value != "") print value }
  ' "$file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      BUILD_DIR="${2:-}"
      shift 2
      ;;
    --expected-repo)
      EXPECTED_REPO="${2:-}"
      shift 2
      ;;
    --expected-branch)
      EXPECTED_BRANCH="${2:-}"
      shift 2
      ;;
    --expected-commit)
      EXPECTED_COMMIT="${2:-}"
      shift 2
      ;;
    --source-remote)
      SOURCE_REMOTE="${2:-}"
      shift 2
      ;;
    --require-remote-ref)
      REQUIRE_REMOTE_REF=1
      shift
      ;;
    --fail-dirty)
      FAIL_DIRTY=1
      shift
      ;;
    --write-manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -d "$BUILD_DIR/conf" ]] || fail "Yocto build conf not found: $BUILD_DIR/conf"
LOCAL_CONF="$BUILD_DIR/conf/local.conf"
BBLAYERS_CONF="$BUILD_DIR/conf/bblayers.conf"
[[ -f "$LOCAL_CONF" ]] || fail "missing local.conf: $LOCAL_CONF"
[[ -f "$BBLAYERS_CONF" ]] || fail "missing bblayers.conf: $BBLAYERS_CONF"

LAYER_PATH="$(
  awk '
    /yocto\/meta-beagley-cluster/ {
      gsub(/[ "\\]/, "", $0)
      print $0
      exit
    }
  ' "$BBLAYERS_CONF"
)"
[[ -n "$LAYER_PATH" ]] || fail "yocto/meta-beagley-cluster is not in $BBLAYERS_CONF"
LAYER_PATH="$(clean_path "$LAYER_PATH")"
BUILD_REPO="${LAYER_PATH%/yocto/meta-beagley-cluster*}"
[[ -d "$BUILD_REPO/.git" ]] || fail "build layer does not resolve to a git repo: $BUILD_REPO"

CONFIG_BRANCH="$(conf_value BEAGLEY_CLUSTER_GIT_BRANCH "$LOCAL_CONF")"
CONFIG_BRANCH="${CONFIG_BRANCH:-main}"
[[ -n "$EXPECTED_BRANCH" ]] || EXPECTED_BRANCH="$(git -C "$EXPECTED_REPO" branch --show-current 2>/dev/null || true)"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-$CONFIG_BRANCH}"

EXPECTED_REPO_REAL="$(cd "$EXPECTED_REPO" && pwd -P)"
BUILD_REPO_REAL="$(cd "$BUILD_REPO" && pwd -P)"
CURRENT_BRANCH="$(git -C "$BUILD_REPO" branch --show-current)"
CURRENT_COMMIT="$(git -C "$BUILD_REPO" rev-parse --short=12 HEAD)"
CURRENT_COMMIT_FULL="$(git -C "$BUILD_REPO" rev-parse HEAD)"
REMOTE_STATE="not_checked"
REMOTE_COMMIT=""
DIRTY_STATUS="$(git -C "$BUILD_REPO" status --porcelain)"
if [[ -n "$DIRTY_STATUS" ]]; then
  DIRTY_STATE=dirty
  DIRTY_COUNT="$(printf '%s\n' "$DIRTY_STATUS" | sed '/^$/d' | wc -l | tr -d ' ')"
else
  DIRTY_STATE=clean
  DIRTY_COUNT=0
fi

if [[ "$BUILD_REPO_REAL" != "$EXPECTED_REPO_REAL" ]]; then
  fail "Yocto is wired to $BUILD_REPO_REAL, but this command expected $EXPECTED_REPO_REAL"
fi
if [[ "$CONFIG_BRANCH" != "$EXPECTED_BRANCH" ]]; then
  fail "Yocto local.conf builds branch $CONFIG_BRANCH, but expected $EXPECTED_BRANCH"
fi
if [[ "$CURRENT_BRANCH" != "$CONFIG_BRANCH" ]]; then
  fail "build repo is checked out on $CURRENT_BRANCH, but Yocto is configured for $CONFIG_BRANCH"
fi
if [[ -n "$EXPECTED_COMMIT" && "$CURRENT_COMMIT_FULL" != "$EXPECTED_COMMIT" && "$CURRENT_COMMIT" != "$EXPECTED_COMMIT" ]]; then
  fail "build repo HEAD is $CURRENT_COMMIT_FULL, but expected $EXPECTED_COMMIT"
fi
if [[ "$DIRTY_STATE" == dirty ]]; then
  if [[ "$FAIL_DIRTY" == 1 ]]; then
    printf '%s\n' "$DIRTY_STATUS" >&2
    fail "build source has $DIRTY_COUNT uncommitted change(s); Yocto will not include them"
  fi
  warn "build source has $DIRTY_COUNT uncommitted change(s); Yocto builds committed HEAD only"
fi
if [[ "$REQUIRE_REMOTE_REF" == 1 ]]; then
  SOURCE_REMOTE="${SOURCE_REMOTE:-origin}"
  REMOTE_STATE="missing"
  REMOTE_OUTPUT="$(git -C "$BUILD_REPO" ls-remote --heads "$SOURCE_REMOTE" "$CONFIG_BRANCH" 2>&1)" || {
    printf '%s\n' "$REMOTE_OUTPUT" >&2
    fail "could not read remote branch ${CONFIG_BRANCH} from ${SOURCE_REMOTE}"
  }
  REMOTE_COMMIT="$(
    printf '%s\n' "$REMOTE_OUTPUT" \
      | awk -v ref="refs/heads/${CONFIG_BRANCH}" '$2 == ref { print $1; found=1 } END { exit !found }'
  )" || fail "remote ${SOURCE_REMOTE} has no branch ${CONFIG_BRANCH}"
  if [[ "$REMOTE_COMMIT" != "$CURRENT_COMMIT_FULL" ]]; then
    fail "build repo HEAD is ${CURRENT_COMMIT_FULL}, but ${SOURCE_REMOTE}/${CONFIG_BRANCH} is ${REMOTE_COMMIT}; push or sync the source before building"
  fi
  REMOTE_STATE="matched"
fi

MANIFEST="$(
  cat <<EOF
repo=$BUILD_REPO_REAL
branch=$CURRENT_BRANCH
configured_branch=$CONFIG_BRANCH
commit=$CURRENT_COMMIT_FULL
commit_short=$CURRENT_COMMIT
dirty=$DIRTY_STATE
dirty_count=$DIRTY_COUNT
remote_check=$REMOTE_STATE
remote_source=${SOURCE_REMOTE:-}
remote_branch=$CONFIG_BRANCH
remote_commit=$REMOTE_COMMIT
build_dir=$(cd "$BUILD_DIR" && pwd -P)
local_conf=$LOCAL_CONF
bblayers_conf=$BBLAYERS_CONF
checked_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
)"

if [[ -n "$MANIFEST_PATH" ]]; then
  mkdir -p "$(dirname "$MANIFEST_PATH")"
  printf '%s\n' "$MANIFEST" > "$MANIFEST_PATH"
fi

printf '%s\n' "$MANIFEST" | sed 's/^/[source-check] /'
echo "[source-check] PASS repo=$BUILD_REPO_REAL branch=$CURRENT_BRANCH commit=$CURRENT_COMMIT dirty=$DIRTY_STATE"
