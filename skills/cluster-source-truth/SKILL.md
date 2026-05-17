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
- BeagleY must report `qml_source=compiled-binary` for production visual
  verification. If it reports `qml_source=qml-dev`, disable the active
  `/etc/systemd/system/beagley_cluster.service.d/ui-dev.conf` drop-in and
  restart before trusting the display.
- Dirty Mac worktrees are allowed only as visible development queues; they are
  not the production source until committed and published.

New-conversation checklist:

1. Work from the canonical worktree/branch, not an older dirty Mac checkout:
   `codex/maplibre-native-yocto-build`.
2. Run `skills/cluster-source-truth/scripts/check.sh --strict` before changing
   or judging the live display.
3. If the check shows a dirty `/Users/joshkomant/projects/beagley-cluster`
   worktree, treat it as a development queue only. Do not deploy from it.
4. If the check shows `qml_source=qml-dev`, run the live profile from the
   canonical checkout to return the board to compiled-binary mode:

```bash
tools/ui/beagley_live_cluster_profile.sh --host root@192.168.0.92 --simulation --effect-level off --gauge-detail rich
```

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
