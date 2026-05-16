#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: skills/github-sync/scripts/check.sh [options]

Report GitHub sync state for the current repository.

Options:
  --fetch             Run git fetch --prune before reporting.
  --pull-ff-only      Run git pull --ff-only after fetch/status checks.
  --push              Push the current branch to its configured upstream.
  --allow-dirty-push  Permit --push even with uncommitted work.
  --remote NAME       Remote to inspect. Default: origin.
  --help              Show this help.

This helper never stages, commits, resets, cleans, rebases, force-pushes, or
creates merge commits.
EOF
}

do_fetch=0
do_pull=0
do_push=0
allow_dirty_push=0
remote="${GITHUB_SYNC_REMOTE:-origin}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch)
      do_fetch=1
      shift
      ;;
    --pull-ff-only)
      do_pull=1
      do_fetch=1
      shift
      ;;
    --push)
      do_push=1
      shift
      ;;
    --allow-dirty-push)
      allow_dirty_push=1
      shift
      ;;
    --remote)
      remote="${2:-}"
      if [[ -z "$remote" ]]; then
        echo "[GITHUB-SYNC] --remote requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[GITHUB-SYNC] Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "[GITHUB-SYNC] Not inside a git repository" >&2
  exit 2
fi

cd "$repo_root"

section() {
  printf '\n=== %s ===\n' "$1"
}

git_remote_exists() {
  git remote get-url "$remote" >/dev/null 2>&1
}

current_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

upstream_ref() {
  git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true
}

worktree_porcelain() {
  git status --porcelain=v1
}

is_dirty() {
  [[ -n "$(worktree_porcelain)" ]]
}

print_dirty_summary() {
  local porcelain
  porcelain="$(worktree_porcelain)"
  if [[ -z "$porcelain" ]]; then
    echo "dirty=no"
    return
  fi

  echo "dirty=yes"
  echo "dirty_counts:"
  printf '%s\n' "$porcelain" | awk '
    substr($0,1,2) == "??" { untracked++; next }
    substr($0,1,1) != " " { staged++ }
    substr($0,2,1) != " " { unstaged++ }
    END {
      printf "  staged=%d\n", staged + 0
      printf "  unstaged=%d\n", unstaged + 0
      printf "  untracked=%d\n", untracked + 0
    }'
  echo "dirty_files:"
  printf '%s\n' "$porcelain" | sed -n '1,80p'
  local total
  total="$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')"
  if [[ "$total" -gt 80 ]]; then
    echo "... ($((total - 80)) more dirty entries omitted)"
  fi
}

branch="$(current_branch)"

section repository
echo "repo=$repo_root"
echo "branch=${branch:-DETACHED}"
if git_remote_exists; then
  echo "remote=$remote"
  echo "remote_url=$(git remote get-url "$remote")"
else
  echo "remote=$remote"
  echo "remote_missing=yes"
  exit 2
fi

section local-state
echo "head=$(git rev-parse --short HEAD)"
echo "head_subject=$(git log -1 --pretty=%s)"
print_dirty_summary

if [[ "$do_fetch" -eq 1 ]]; then
  section fetch
  git fetch --prune "$remote"
fi

upstream="$(upstream_ref)"

section upstream
if [[ -z "$upstream" ]]; then
  echo "upstream=none"
  if [[ -n "$branch" ]] && git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    echo "matching_remote_branch=$remote/$branch"
    echo "suggested_upstream_command=git branch --set-upstream-to=$remote/$branch $branch"
  elif [[ -n "$branch" ]]; then
    echo "matching_remote_branch=none"
    echo "suggested_publish_command=git push -u $remote $branch"
  fi
else
  echo "upstream=$upstream"
  echo "upstream_head=$(git rev-parse --short "$upstream" 2>/dev/null || echo missing)"
fi

ahead=0
behind=0
verdict="no_upstream"
if [[ -n "$upstream" ]] && git rev-parse --verify "$upstream" >/dev/null 2>&1; then
  read -r ahead behind < <(git rev-list --left-right --count "HEAD...$upstream")
  echo "ahead=$ahead"
  echo "behind=$behind"
  if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
    verdict="diverged"
  elif [[ "$ahead" -gt 0 ]]; then
    verdict="ahead"
  elif [[ "$behind" -gt 0 ]]; then
    verdict="behind"
  else
    verdict="up_to_date"
  fi
fi

if is_dirty; then
  if [[ "$verdict" == "up_to_date" ]]; then
    verdict="dirty"
  else
    verdict="${verdict}+dirty"
  fi
fi

section verdict
echo "verdict=$verdict"

if command -v gh >/dev/null 2>&1; then
  section github-cli
  gh auth status -h github.com >/dev/null 2>&1 \
    && echo "gh_auth=ok" \
    || echo "gh_auth=not-authenticated"
  gh repo view --json nameWithOwner,defaultBranchRef \
    --jq '"repo=\(.nameWithOwner)\ndefault_branch=\(.defaultBranchRef.name)"' 2>/dev/null || true
fi

if [[ "$do_pull" -eq 1 ]]; then
  section pull-ff-only
  if is_dirty; then
    echo "refusing_pull=dirty_worktree"
    exit 1
  fi
  if [[ -z "$upstream" ]]; then
    echo "refusing_pull=no_upstream"
    exit 1
  fi
  if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
    echo "refusing_pull=diverged"
    exit 1
  fi
  git pull --ff-only
fi

if [[ "$do_push" -eq 1 ]]; then
  section push
  if is_dirty && [[ "$allow_dirty_push" -ne 1 ]]; then
    echo "refusing_push=dirty_worktree"
    echo "hint=use --allow-dirty-push only when intentionally pushing existing commits without committing current work"
    exit 1
  fi
  if [[ -z "$branch" ]]; then
    echo "refusing_push=detached_head"
    exit 1
  fi
  if [[ -z "$upstream" ]]; then
    echo "refusing_push=no_upstream"
    echo "suggested_publish_command=git push -u $remote $branch"
    exit 1
  fi
  if [[ "$behind" -gt 0 ]]; then
    echo "refusing_push=remote_has_unmerged_commits"
    exit 1
  fi
  git push
fi
