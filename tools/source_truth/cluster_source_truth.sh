#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BEAGLEY_COMMON="$ROOT/skills/beagley-common/scripts/ssh.sh"

SOURCE_REMOTE="${BEAGLEY_SOURCE_REMOTE:-https://github.com/Ajkopensesame/beagley-cluster.git}"
SOURCE_BRANCH="${BEAGLEY_CONTINUOUS_BRANCH:-codex/maplibre-native-yocto-build}"
ELITEBOOK_KEY="${ELITEBOOK_SSH_KEY:-$HOME/.ssh/pneumaion_elitebook}"
ELITEBOOK_REPO="${ELITEBOOK_REPO:-/home/pneumaion/projects/beagley-cluster}"
ELITEBOOK_TARGETS="${ELITEBOOK_TARGETS:-${ELITEBOOK_HOST:-} pneumaion@192.168.0.149 pneumaion@172.20.10.9 elitebook-sandbox}"
STRICT=0
FAIL_DIRTY=0
CHECK_BEAGLEY=1
CHECK_ELITEBOOK=1
FAILURES=0
WARNINGS=0

usage() {
  cat <<'EOF'
Usage:
  tools/source_truth/cluster_source_truth.sh [options]

Checks the BeagleY cluster source-of-truth chain:
  GitHub branch -> local branch ref -> EliteBook Yocto repo -> live BeagleY BUILD line.

Options:
  --branch NAME        Canonical continuous-build branch.
                       Default: BEAGLEY_CONTINUOUS_BRANCH or codex/maplibre-native-yocto-build
  --remote REMOTE      Git remote name or URL to treat as published truth.
                       Default: BEAGLEY_SOURCE_REMOTE or GitHub HTTPS URL
  --strict             Exit nonzero when GitHub/local/EliteBook/BeagleY are not aligned
  --fail-dirty         Treat any dirty local worktree as a failure instead of a warning
  --no-beagley         Skip live BeagleY runtime check
  --no-elitebook       Skip EliteBook builder check
  -h, --help           Show this help

Environment:
  ELITEBOOK_TARGETS, ELITEBOOK_HOST, ELITEBOOK_SSH_KEY, ELITEBOOK_REPO
  BEAGLEY_TARGETS, BEAGLEY_HOST, BEAGLEY_TARGET_ENV
EOF
}

section() {
  printf '\n=== %s ===\n' "$1"
}

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s\n' "$1"
}

short_commit() {
  printf '%s' "$1" | cut -c1-12
}

dirty_count_for() {
  git -C "$1" status --porcelain=v1 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' '
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
    --strict)
      STRICT=1
      shift
      ;;
    --fail-dirty)
      FAIL_DIRTY=1
      shift
      ;;
    --no-beagley)
      CHECK_BEAGLEY=0
      shift
      ;;
    --no-elitebook)
      CHECK_ELITEBOOK=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[source-truth] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$SOURCE_BRANCH" ]] || {
  echo "[source-truth] --branch cannot be empty" >&2
  exit 2
}
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "[source-truth] not a git checkout: $ROOT" >&2
  exit 2
}

section "canonical-source"
remote_output="$(
  GIT_TERMINAL_PROMPT=0 git -C "$ROOT" \
    -c http.lowSpeedLimit=1 \
    -c http.lowSpeedTime=8 \
    ls-remote --heads "$SOURCE_REMOTE" "$SOURCE_BRANCH" 2>&1
)"
remote_status=$?
if [[ "$remote_status" -ne 0 ]]; then
  printf '%s\n' "$remote_output"
  fail "cannot read source remote $SOURCE_REMOTE"
  canonical_commit=""
else
  canonical_commit="$(
    printf '%s\n' "$remote_output" \
      | awk -v ref="refs/heads/${SOURCE_BRANCH}" '$2 == ref { print $1; found=1 } END { exit !found }'
  )" || canonical_commit=""
  if [[ -z "$canonical_commit" ]]; then
    fail "remote has no branch $SOURCE_BRANCH"
  else
    printf 'source_remote=%s\n' "$SOURCE_REMOTE"
    printf 'source_branch=%s\n' "$SOURCE_BRANCH"
    printf 'source_commit=%s\n' "$canonical_commit"
    ok "canonical source is $(short_commit "$canonical_commit")"
  fi
fi

section "local-worktrees"
current_branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
current_head="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
local_source_commit="$(git -C "$ROOT" rev-parse "$SOURCE_BRANCH" 2>/dev/null || true)"
origin_source_commit="$(git -C "$ROOT" rev-parse "origin/$SOURCE_BRANCH" 2>/dev/null || true)"

printf 'main_worktree=%s\n' "$ROOT"
printf 'current_branch=%s\n' "${current_branch:-detached}"
printf 'current_head=%s\n' "${current_head:-unknown}"
printf 'canonical_local_ref=%s\n' "${local_source_commit:-missing}"
printf 'canonical_origin_ref=%s\n' "${origin_source_commit:-missing}"

if [[ -n "$canonical_commit" ]]; then
  if [[ "$local_source_commit" == "$canonical_commit" ]]; then
    ok "local branch $SOURCE_BRANCH matches canonical source"
  else
    fail "local branch $SOURCE_BRANCH is not canonical"
  fi
  if [[ "$origin_source_commit" == "$canonical_commit" ]]; then
    ok "local origin/$SOURCE_BRANCH matches canonical source"
  else
    warn "local origin/$SOURCE_BRANCH is stale or missing; run git fetch"
    [[ "$STRICT" == 1 ]] && fail "origin/$SOURCE_BRANCH does not match canonical source"
  fi
fi

worktree_paths=()
while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    worktree_paths+=("${line#worktree }")
  fi
done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null)

for wt in "${worktree_paths[@]}"; do
  wt_branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
  wt_head="$(git -C "$wt" rev-parse --short=12 HEAD 2>/dev/null || true)"
  wt_dirty="$(dirty_count_for "$wt")"
  printf 'worktree=%s branch=%s head=%s dirty=%s\n' \
    "$wt" "${wt_branch:-detached}" "${wt_head:-unknown}" "${wt_dirty:-unknown}"
  if [[ "${wt_dirty:-0}" != "0" ]]; then
    if [[ "$FAIL_DIRTY" == 1 ]]; then
      fail "dirty worktree $wt has $wt_dirty uncommitted change(s)"
    else
      warn "dirty worktree $wt has $wt_dirty uncommitted change(s)"
    fi
  fi
done

resolve_elitebook() {
  local target
  local opts=(-o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o ServerAliveInterval=5 -o ServerAliveCountMax=1 -o StrictHostKeyChecking=accept-new)
  if [[ -f "$ELITEBOOK_KEY" ]]; then
    opts+=(-i "$ELITEBOOK_KEY")
  fi
  for target in ${ELITEBOOK_TARGETS//,/ }; do
    [[ -n "$target" ]] || continue
    if ssh "${opts[@]}" "$target" true >/dev/null 2>&1; then
      printf '%s\n' "$target"
      return 0
    fi
  done
  return 1
}

if [[ "$CHECK_ELITEBOOK" == 1 ]]; then
  section "elitebook-builder"
  elitebook_target="$(resolve_elitebook || true)"
  if [[ -z "$elitebook_target" ]]; then
    fail "no reachable EliteBook target"
  else
    ok "EliteBook reachable: $elitebook_target"
    elitebook_opts=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
    if [[ -f "$ELITEBOOK_KEY" ]]; then
      elitebook_opts+=(-i "$ELITEBOOK_KEY")
    fi
    elitebook_info="$(
      ssh "${elitebook_opts[@]}" "$elitebook_target" bash -s -- "$ELITEBOOK_REPO" <<'REMOTE'
set -uo pipefail
repo="$1"
if [[ ! -d "$repo/.git" ]]; then
  echo "repo_missing=$repo"
  exit 0
fi
echo "repo=$repo"
echo "branch=$(git -C "$repo" branch --show-current 2>/dev/null || true)"
echo "commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
echo "dirty=$(git -C "$repo" status --porcelain=v1 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
echo "remotes=$(git -C "$repo" remote 2>/dev/null | paste -sd, -)"
REMOTE
    )"
    printf '%s\n' "$elitebook_info"
    elite_commit="$(printf '%s\n' "$elitebook_info" | awk -F= '$1 == "commit" { print $2; exit }')"
    elite_branch="$(printf '%s\n' "$elitebook_info" | awk -F= '$1 == "branch" { print $2; exit }')"
    elite_dirty="$(printf '%s\n' "$elitebook_info" | awk -F= '$1 == "dirty" { print $2; exit }')"
    if [[ -n "$canonical_commit" && "$elite_commit" == "$canonical_commit" ]]; then
      ok "EliteBook commit matches canonical source"
    else
      fail "EliteBook commit does not match canonical source"
    fi
    if [[ "$elite_branch" == "$SOURCE_BRANCH" ]]; then
      ok "EliteBook branch is $SOURCE_BRANCH"
    else
      fail "EliteBook branch is ${elite_branch:-unknown}, expected $SOURCE_BRANCH"
    fi
    if [[ "${elite_dirty:-1}" == "0" ]]; then
      ok "EliteBook checkout clean"
    else
      fail "EliteBook checkout dirty=${elite_dirty:-unknown}"
    fi
  fi
fi

if [[ "$CHECK_BEAGLEY" == 1 ]]; then
  section "beagley-runtime"
  if [[ ! -f "$BEAGLEY_COMMON" ]]; then
    fail "missing BeagleY SSH helper: $BEAGLEY_COMMON"
  else
    # shellcheck source=/dev/null
    source "$BEAGLEY_COMMON"
    if ! beagley_require_ssh_target; then
      fail "no reachable BeagleY target"
    else
      ok "BeagleY reachable: $BEAGLEY_SSH_HOST"
      beagley_info="$(beagley_ssh "bash -s" <<'REMOTE'
set -uo pipefail
pid="$(systemctl show beagley_cluster -p MainPID --value 2>/dev/null || true)"
echo "main_pid=${pid:-unknown}"
echo "active_state=$(systemctl show beagley_cluster -p ActiveState --value 2>/dev/null || true)"
echo "n_restarts=$(systemctl show beagley_cluster -p NRestarts --value 2>/dev/null || true)"
if [[ -n "${pid:-}" && "$pid" != "0" && -r "/proc/$pid/environ" ]]; then
  env="$(tr '\0' '\n' <"/proc/$pid/environ")"
  printf '%s\n' "$env" \
    | grep -E '^(BEAGLEY_UI_VARIANT|BEAGLEY_RENDER_PROFILE|BEAGLEY_EFFECT_LEVEL|BEAGLEY_GAUGE_DETAIL|BEAGLEY_GAUGE_DEMO|BEAGLEY_MAP_RENDERER|BEAGLEY_QML_DEV_ROOT|QSG_RENDER_LOOP)=' \
    | sort || true
  qml_root="$(printf '%s\n' "$env" | sed -n 's/^BEAGLEY_QML_DEV_ROOT=//p' | tail -n 1)"
  if [[ -n "${qml_root:-}" ]]; then
    echo "qml_source=qml-dev"
  else
    echo "qml_source=compiled-binary"
  fi
else
  echo "process_env=unavailable"
fi
build_line="$(journalctl -b -u beagley_cluster --no-pager 2>/dev/null | grep '\[BUILD\]' | tail -n 1 || true)"
echo "build_line=$build_line"
printf '%s\n' "$build_line" | sed -n 's/.* branch=\([^ ]*\) commit=\([^ ]*\) .*/build_branch=\1\nbuild_commit=\2/p'
REMOTE
      )"
      printf '%s\n' "$beagley_info"
      beagley_commit="$(printf '%s\n' "$beagley_info" | awk -F= '$1 == "build_commit" { print $2; exit }')"
      beagley_branch="$(printf '%s\n' "$beagley_info" | awk -F= '$1 == "build_branch" { print $2; exit }')"
      qml_source="$(printf '%s\n' "$beagley_info" | awk -F= '$1 == "qml_source" { print $2; exit }')"
      if [[ -n "$canonical_commit" && "$beagley_commit" == "$(short_commit "$canonical_commit")"* ]]; then
        ok "BeagleY BUILD commit matches canonical source"
      else
        fail "BeagleY BUILD commit ${beagley_commit:-unknown} does not match canonical source"
      fi
      if [[ "$beagley_branch" == "$SOURCE_BRANCH" ]]; then
        ok "BeagleY BUILD branch is $SOURCE_BRANCH"
      else
        fail "BeagleY BUILD branch is ${beagley_branch:-unknown}, expected $SOURCE_BRANCH"
      fi
      if [[ "$qml_source" == "compiled-binary" ]]; then
        ok "BeagleY is running compiled binary"
      else
        warn "BeagleY display source is ${qml_source:-unknown}"
      fi
    fi
  fi
fi

section "verdict"
printf 'warnings=%s\n' "$WARNINGS"
printf 'failures=%s\n' "$FAILURES"
if [[ "$FAILURES" -eq 0 ]]; then
  ok "continuous build source is aligned"
  exit 0
fi

if [[ "$STRICT" == 1 ]]; then
  fail "continuous build source is not aligned"
  exit 1
fi

warn "continuous build source has drift; rerun with --strict to fail builds on this state"
exit 0
