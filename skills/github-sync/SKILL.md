---
name: github-sync
description: Keep a local repository aligned with GitHub safely. Use when the user asks to check GitHub sync, keep GitHub up to date, publish work, avoid remote drift, inspect branch/remote/ahead-behind state, or recover when local work gets out of contact with GitHub.
---

# GitHub Sync

Use this skill before and after substantial repo work, before production builds,
and whenever the user asks whether GitHub is current.

## Default Workflow

1. Run the status helper first:

```bash
skills/github-sync/scripts/check.sh --fetch
```

2. Read the verdict before mutating anything:

- `up_to_date`: no GitHub action needed.
- `dirty`: local uncommitted work exists. Do not hide it or overwrite it.
- `ahead`: local commits are not on GitHub. Push only if the user asked to publish.
- `behind`: GitHub has commits not local. Use `--pull-ff-only` only when the worktree is clean.
- `diverged`: stop and inspect; do not merge, rebase, or force-push without explicit direction.
- `no_upstream`: set/push upstream only after confirming the intended remote branch.

3. If the user explicitly asks to sync from GitHub and the tree is clean:

```bash
skills/github-sync/scripts/check.sh --fetch --pull-ff-only
```

4. If the user explicitly asks to publish current commits:

```bash
skills/github-sync/scripts/check.sh --fetch --push
```

## Guardrails

- Never run `git reset --hard`, `git checkout --`, `git clean`, force-push, or
  history rewrites from this skill unless the user explicitly names that action.
- Never commit broad dirty work automatically. First group the change set,
  separate unrelated changes, and ask for or infer a focused commit message.
- If the worktree has unrelated user changes, leave them alone.
- Prefer `git pull --ff-only` over merge pulls.
- Prefer pushing the current branch to its configured upstream. If no upstream
  exists, report the exact command to create it unless the user already asked to
  publish this branch.
- For BeagleY production work, remember GitHub may not be the build source.
  Pair this skill with `beagley-build-source-guard` before Yocto production
  builds.

## Useful Commands

Check only, no network:

```bash
skills/github-sync/scripts/check.sh
```

Refresh remote refs:

```bash
skills/github-sync/scripts/check.sh --fetch
```

Pull only if fast-forward and clean:

```bash
skills/github-sync/scripts/check.sh --fetch --pull-ff-only
```

Push current branch to the configured upstream:

```bash
skills/github-sync/scripts/check.sh --fetch --push
```

Allow pushing existing commits even when the worktree is dirty:

```bash
skills/github-sync/scripts/check.sh --fetch --push --allow-dirty-push
```
