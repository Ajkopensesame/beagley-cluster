# BeagleY Build Source Guard

Use this helper before a production Yocto app or appliance build. It verifies
that the source being built is clean, published to the configured Git remote,
and aligned with the EliteBook Yocto build tree.

Run:

```bash
skills/beagley-build-source-guard/scripts/check.sh
```

Defaults:

- local repo: this checkout
- EliteBook: `pneumaion@172.20.10.9`
- EliteBook repo: `/home/pneumaion/projects/beagley-cluster`
- EliteBook Yocto build dir: `/home/pneumaion/ti-sdk-11.00/yocto-build/build`
- source remote: `https://github.com/Ajkopensesame/beagley-cluster.git`

Useful overrides:

- `ELITEBOOK_HOST`
- `ELITEBOOK_REPO`
- `ELITEBOOK_YOCTO_BUILD_DIR`
- `BEAGLEY_SOURCE_REMOTE`

The helper intentionally fails dirty checkouts by default. Use `--allow-dirty`
only for an explicit local experiment, never for production deploy provenance.
