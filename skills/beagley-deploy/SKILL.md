---
name: beagley-deploy
description: Deploy a known Linux aarch64 BeagleY cluster binary to the real BeagleY and verify service health. Use only after the binary source has been proven by cluster-source-truth or the canonical Yocto build.
---

# BeagleY Deploy

This deploy skill installs a prebuilt Linux aarch64 `beagley_cluster` binary on
the real BeagleY. It is not the source of truth for production builds.

Production UI deploy rule:

1. Work from `codex/maplibre-native-yocto-build`.
2. Build with the canonical wrapper:

```bash
tools/source_truth/build_canonical_yocto_app.sh
```

3. Pull the Yocto aarch64 binary from the EliteBook.
4. Deploy with `BEAGLEY_DEPLOY_BIN` set:

```bash
BEAGLEY_HOST=192.168.0.92 \
BEAGLEY_DEPLOY_BIN=/path/to/beagley_cluster-aarch64 \
skills/beagley-deploy/scripts/deploy.sh
```

Do not run a production deploy directly from
`/Users/joshkomant/projects/beagley-cluster` when it is dirty or on an older
branch. That worktree is a development queue unless it is clean and on the
canonical branch.

After deploy, run:

```bash
skills/cluster-source-truth/scripts/check.sh --strict
```

The check must show the BeagleY `[BUILD]` commit matching the canonical branch
and `qml_source=compiled-binary`.
