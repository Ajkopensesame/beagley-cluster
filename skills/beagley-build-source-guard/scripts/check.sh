#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SOURCE_REMOTE="${BEAGLEY_SOURCE_REMOTE:-https://github.com/Ajkopensesame/beagley-cluster.git}"
ELITEBOOK_HOST="${ELITEBOOK_HOST:-pneumaion@172.20.10.9}"
ELITEBOOK_KEY="${ELITEBOOK_SSH_KEY:-$HOME/.ssh/pneumaion_elitebook}"
ELITEBOOK_REPO="${ELITEBOOK_REPO:-/home/pneumaion/projects/beagley-cluster}"
ELITEBOOK_YOCTO_BUILD_DIR="${ELITEBOOK_YOCTO_BUILD_DIR:-/home/pneumaion/ti-sdk-11.00/yocto-build/build}"
CHECK_LOCAL=1
CHECK_ELITEBOOK=1
FAIL_DIRTY=1

usage() {
  cat <<'EOF'
Usage:
  skills/beagley-build-source-guard/scripts/check.sh [options]

Verifies that the production build source is clean, published, and aligned with
the EliteBook Yocto build tree.

Options:
  --local-only          Check only this Mac checkout.
  --elitebook-only      Check only the EliteBook Yocto source path, using this
                        checkout's current branch and commit as expectations.
  --allow-dirty         Report dirty source without failing. Do not use for
                        production builds.
  --source-remote REF   Git remote name or URL whose branch tip must match HEAD.
  --elitebook-host SSH  SSH target. Default: ELITEBOOK_HOST or
                        pneumaion@172.20.10.9.
  --elitebook-repo DIR  Remote repo path.
  --yocto-build-dir DIR Remote Yocto build dir.
EOF
}

fail() {
  echo "[build-source-guard] FAIL: $*" >&2
  exit 1
}

log() {
  echo "[build-source-guard] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      CHECK_ELITEBOOK=0
      shift
      ;;
    --elitebook-only)
      CHECK_LOCAL=0
      shift
      ;;
    --allow-dirty)
      FAIL_DIRTY=0
      shift
      ;;
    --source-remote)
      SOURCE_REMOTE="${2:-}"
      shift 2
      ;;
    --elitebook-host)
      ELITEBOOK_HOST="${2:-}"
      shift 2
      ;;
    --elitebook-repo)
      ELITEBOOK_REPO="${2:-}"
      shift 2
      ;;
    --yocto-build-dir)
      ELITEBOOK_YOCTO_BUILD_DIR="${2:-}"
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

[[ -d "$BASE/.git" ]] || fail "not a Git repo: $BASE"
[[ -n "$SOURCE_REMOTE" ]] || fail "--source-remote cannot be empty"

branch="$(git -C "$BASE" branch --show-current)"
[[ -n "$branch" ]] || fail "local checkout is detached; production builds must use a named branch"
commit="$(git -C "$BASE" rev-parse HEAD)"
short_commit="$(git -C "$BASE" rev-parse --short=12 HEAD)"

remote_branch_commit() {
  local repo="$1"
  local branch_name="$2"
  local output=""
  local remote_commit=""

  output="$(git -C "$repo" ls-remote --heads "$SOURCE_REMOTE" "$branch_name" 2>&1)" || {
    printf '%s\n' "$output" >&2
    fail "could not read ${SOURCE_REMOTE}/${branch_name}"
  }
  remote_commit="$(
    printf '%s\n' "$output" \
      | awk -v ref="refs/heads/${branch_name}" '$2 == ref { print $1; found=1 } END { exit !found }'
  )" || fail "remote ${SOURCE_REMOTE} has no branch ${branch_name}"
  printf '%s\n' "$remote_commit"
}

if [[ "$CHECK_LOCAL" == 1 ]]; then
  dirty_status="$(git -C "$BASE" status --porcelain)"
  if [[ -n "$dirty_status" ]]; then
    dirty_count="$(printf '%s\n' "$dirty_status" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$FAIL_DIRTY" == 1 ]]; then
      git -C "$BASE" status --short >&2
      fail "local checkout has ${dirty_count} uncommitted change(s); commit or intentionally separate them before production build"
    fi
    log "WARN local checkout has ${dirty_count} uncommitted change(s)"
  fi

  remote_commit="$(remote_branch_commit "$BASE" "$branch")"
  if [[ "$remote_commit" != "$commit" ]]; then
    fail "local HEAD ${commit} does not match ${SOURCE_REMOTE}/${branch} ${remote_commit}"
  fi
  log "PASS local repo branch=${branch} commit=${short_commit} remote=${SOURCE_REMOTE}"
fi

if [[ "$CHECK_ELITEBOOK" == 1 ]]; then
  ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)
  if [[ -f "$ELITEBOOK_KEY" ]]; then
    ssh_opts+=(-i "$ELITEBOOK_KEY")
  fi

  log "checking EliteBook ${ELITEBOOK_HOST}:${ELITEBOOK_REPO}"
  ssh "${ssh_opts[@]}" "$ELITEBOOK_HOST" bash -s -- \
    "$ELITEBOOK_REPO" \
    "$ELITEBOOK_YOCTO_BUILD_DIR" \
    "$branch" \
    "$commit" \
    "$SOURCE_REMOTE" \
    "$FAIL_DIRTY" <<'REMOTE'
set -euo pipefail

repo="$1"
build_dir="$2"
expected_branch="$3"
expected_commit="$4"
source_remote="$5"
fail_dirty="$6"
verify="$repo/tools/yocto/verify_beagley_build_source.sh"
manifest="$repo/build/yocto/beagley-cluster-source-manifest.env"

if [[ ! -x "$verify" ]]; then
  echo "[build-source-guard] FAIL: missing executable verifier on EliteBook: $verify" >&2
  exit 2
fi
if ! "$verify" --help | grep -q -- '--source-remote'; then
  echo "[build-source-guard] FAIL: EliteBook verifier is too old; sync this repo before production builds" >&2
  exit 2
fi

args=(
  --build-dir "$build_dir"
  --expected-repo "$repo"
  --expected-branch "$expected_branch"
  --expected-commit "$expected_commit"
  --source-remote "$source_remote"
  --require-remote-ref
  --write-manifest "$manifest"
)
if [[ "$fail_dirty" == 1 ]]; then
  args+=(--fail-dirty)
fi

"$verify" "${args[@]}"
REMOTE
fi

log "PASS build source guard"
