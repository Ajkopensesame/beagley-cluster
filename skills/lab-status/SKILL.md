---
name: lab-status
description: Check the current status of the BeagleY, EliteBook builder/sandbox, local repo, and optionally GitHub source alignment for the beagley-cluster lab. Use when the user asks whether the lab, EliteBook, BeagleY, Wi-Fi, services, build host, Yocto tree, or GitHub sync are healthy or reachable.
---

# Lab Status

Use this skill to answer "what is up right now?" for the BeagleY + EliteBook
lab.

Run:

```bash
skills/lab-status/scripts/status.sh
```

Default behavior:

- prints local repo branch/commit/dirty count
- resolves and checks BeagleY SSH, app service, Wi-Fi, route, and watchdog
- prints live BeagleY display source: compiled binary vs QML-dev, gauge/map
  runtime knobs, and QML sync manifest when present
- resolves and checks EliteBook SSH, repo path, Yocto build dir, disk, and
  Codex executable presence
- reports pass/fail per section without requiring GitHub

Useful options:

```bash
skills/lab-status/scripts/status.sh --github
skills/lab-status/scripts/status.sh --full-beagley
skills/lab-status/scripts/status.sh --source-guard
skills/lab-status/scripts/status.sh --beagley-only
skills/lab-status/scripts/status.sh --elitebook-only
```

GitHub guidance:

- Do not make GitHub a hard dependency for normal lab status. Hardware
  reachability and service health should still be diagnosable when GitHub auth
  or internet is unavailable.
- Use `--github` when the user asks if the local branch is published/aligned.
- Use `--source-guard` before production Yocto/app builds; it delegates to the
  existing build-source guard and may fail dirty or unsynced source by design.

Default targets can be overridden with:

- `BEAGLEY_TARGETS`, `BEAGLEY_HOST`, `BEAGLEY_HOST_NAME`
- `ELITEBOOK_TARGETS`, `ELITEBOOK_HOST`, `ELITEBOOK_SSH_KEY`
- `ELITEBOOK_REPO`, `ELITEBOOK_YOCTO_BUILD_DIR`
- `BEAGLEY_SOURCE_REMOTE`
