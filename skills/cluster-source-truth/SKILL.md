---
name: cluster-source-truth
description: Check and enforce the BeagleY cluster source of truth across GitHub, local Mac worktrees, the EliteBook Yocto builder, and the live BeagleY display. Use when the user asks why the board UI does not match expected code, mentions dirty/uncommitted work, wants a continuous build, or asks which source is actually running.
---

# Cluster Source Truth

Use this before any production aarch64/Yocto deploy, and whenever the visible
BeagleY display does not match the expected source.

Run:

```bash
skills/cluster-source-truth/scripts/check.sh --strict
```

The canonical continuous-build branch is:

```text
codex/maplibre-native-yocto-build
```

The helper checks:

- GitHub branch head for the canonical source commit
- local branch and all Mac worktrees, including dirty/uncommitted counts
- EliteBook builder repo branch, commit, and dirty state
- live BeagleY `[BUILD]` journal line and display source (`compiled-binary` vs QML-dev)

Rules:

- Do not run a production Yocto deploy from unidentified dirty work.
- A clean commit on GitHub is the continuous-build source.
- EliteBook must build that exact commit.
- BeagleY must report that exact commit in its `[BUILD]` line after deploy.
- Dirty Mac worktrees are allowed only as visible development queues; they are
  not the production source until committed and published.

Useful commands:

```bash
skills/cluster-source-truth/scripts/check.sh
skills/cluster-source-truth/scripts/check.sh --strict --fail-dirty
skills/cluster-source-truth/scripts/check.sh --branch codex/maplibre-native-yocto-build
```

Canonical Yocto app build:

```bash
tools/source_truth/build_canonical_yocto_app.sh
```

That wrapper verifies the source-truth chain, updates the EliteBook from the
canonical GitHub branch by fast-forward only, then runs the Yocto app build with
remote-ref enforcement enabled.
