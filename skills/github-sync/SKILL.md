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
- `ahead`: local commits are not on GitHub. Push focused commits when they are part of the current task.
- `behind`: GitHub has commits not local. Use `--pull-ff-only` only when the worktree is clean.
- `diverged`: stop and inspect; do not merge, rebase, or force-push without explicit direction.
- `no_upstream`: set/push upstream when the current branch is clearly the task branch; otherwise report the exact push command.

3. If the user explicitly asks to sync from GitHub and the tree is clean:

```bash
skills/github-sync/scripts/check.sh --fetch --pull-ff-only
```

4. To publish current commits:

```bash
skills/github-sync/scripts/check.sh --fetch --push
```

## Autonomous Commit Policy

For this `beagley-cluster` workflow, the standing user preference is:

- Make focused commits and push them as needed while implementing, verifying,
  or deploying repo work.
- Do not stop only to ask for commit or push permission when the intended scope
  is clear from the task and the changed files are yours.
- Choose a terse commit message that describes the actual change.
- If the current task touches only a subset of a dirty worktree, stage explicit
  paths for that subset and leave unrelated files alone.
- If dirty state makes scope ambiguous, inspect `git status` and the relevant
  diffs first. Ask only when you cannot confidently separate task changes from
  unrelated user work.

## Guardrails

- Never run `git reset --hard`, `git checkout --`, `git clean`, force-push, or
  history rewrites from this skill unless the user explicitly names that action.
- Never commit broad dirty work automatically. First group the change set and
  separate unrelated changes. Infer a focused commit message when scope is
  clear.
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
