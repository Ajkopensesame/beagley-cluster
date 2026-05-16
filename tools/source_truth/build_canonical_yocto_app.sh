#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_BRANCH="${BEAGLEY_CONTINUOUS_BRANCH:-codex/maplibre-native-yocto-build}"
SOURCE_REMOTE="${BEAGLEY_SOURCE_REMOTE:-https://github.com/Ajkopensesame/beagley-cluster.git}"
ELITEBOOK_KEY="${ELITEBOOK_SSH_KEY:-$HOME/.ssh/pneumaion_elitebook}"
ELITEBOOK_REPO="${ELITEBOOK_REPO:-/home/pneumaion/projects/beagley-cluster}"
ELITEBOOK_TARGETS="${ELITEBOOK_TARGETS:-${ELITEBOOK_HOST:-} pneumaion@192.168.0.149 pneumaion@172.20.10.9 elitebook-sandbox}"
YOCTO_BUILD_DIR="${YOCTO_BUILD_DIR:-/home/pneumaion/ti-sdk-11.00/yocto-build/build}"
NO_CLEAN=0

usage() {
  cat <<'EOF'
Usage:
  tools/source_truth/build_canonical_yocto_app.sh [options]

Builds the BeagleY app on the EliteBook from the canonical GitHub branch only.
This is the continuous-build path: no dirty rsync build and no private
EliteBook-only source.

Options:
  --branch NAME     Canonical branch. Default: BEAGLEY_CONTINUOUS_BRANCH or
                    codex/maplibre-native-yocto-build
  --remote REF      Git remote name or URL. Default: BEAGLEY_SOURCE_REMOTE or GitHub URL
  --no-clean        Skip Yocto bitbake -c clean
  -h, --help        Show this help
EOF
}

fail() {
  echo "[canonical-yocto-build] FAIL: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      SOURCE_BRANCH="${2:-}"
      shift 2
      ;;
    --remote)
      SOURCE_REMOTE="${2:-}"
      shift 2
      ;;
    --no-clean)
      NO_CLEAN=1
      shift
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

"$ROOT/tools/source_truth/cluster_source_truth.sh" \
  --strict \
  --no-beagley \
  --no-elitebook \
  --branch "$SOURCE_BRANCH" \
  --remote "$SOURCE_REMOTE"

canonical_commit="$(
  GIT_TERMINAL_PROMPT=0 git -C "$ROOT" ls-remote --heads "$SOURCE_REMOTE" "$SOURCE_BRANCH" \
    | awk -v ref="refs/heads/${SOURCE_BRANCH}" '$2 == ref { print $1; found=1 } END { exit !found }'
)" || fail "cannot resolve $SOURCE_REMOTE/$SOURCE_BRANCH"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
if [[ -f "$ELITEBOOK_KEY" ]]; then
  ssh_opts+=(-i "$ELITEBOOK_KEY")
fi

elitebook_target=""
for target in ${ELITEBOOK_TARGETS//,/ }; do
  [[ -n "$target" ]] || continue
  if ssh "${ssh_opts[@]}" "$target" true >/dev/null 2>&1; then
    elitebook_target="$target"
    break
  fi
done
[[ -n "$elitebook_target" ]] || fail "no reachable EliteBook target"

echo "[canonical-yocto-build] target=$elitebook_target"
echo "[canonical-yocto-build] branch=$SOURCE_BRANCH"
echo "[canonical-yocto-build] commit=$canonical_commit"

remote_build_args=()
if [[ "$NO_CLEAN" == 1 ]]; then
  remote_build_args+=(--no-clean)
fi

ssh "${ssh_opts[@]}" "$elitebook_target" bash -s -- \
  "$ELITEBOOK_REPO" \
  "$SOURCE_REMOTE" \
  "$SOURCE_BRANCH" \
  "$canonical_commit" \
  "$YOCTO_BUILD_DIR" \
  "${remote_build_args[@]}" <<'REMOTE'
set -euo pipefail

repo="$1"
source_remote="$2"
source_branch="$3"
canonical_commit="$4"
yocto_build_dir="$5"
shift 5

[[ -d "$repo/.git" ]] || {
  echo "[canonical-yocto-build] missing EliteBook repo: $repo" >&2
  exit 2
}

cd "$repo"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$source_remote"
else
  git remote add origin "$source_remote"
fi

dirty="$(git status --porcelain=v1 | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$dirty" != "0" ]]; then
  echo "[canonical-yocto-build] dirty EliteBook checkout; refusing build" >&2
  git status --short >&2
  exit 1
fi

git fetch origin "$source_branch"
current_branch="$(git branch --show-current 2>/dev/null || true)"
if [[ "$current_branch" != "$source_branch" ]]; then
  git checkout "$source_branch"
fi
git merge --ff-only "$canonical_commit"

if [[ "$(git rev-parse HEAD)" != "$canonical_commit" ]]; then
  echo "[canonical-yocto-build] EliteBook HEAD does not match canonical commit" >&2
  exit 1
fi

YOCTO_BUILD_DIR="$yocto_build_dir" \
BEAGLEY_SOURCE_REMOTE="$source_remote" \
tools/yocto/build_beagley_cluster_app.sh --require-remote-ref "$@"
REMOTE
