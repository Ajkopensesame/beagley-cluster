# Branch archive, 2026-10-03

Recorded **before** deleting remote branches in the 2026-10 cleanup (approved by ThatGuy). Deleted branches stay recoverable by SHA:

```bash
git fetch origin <sha>
git branch <name> <sha>      # or: gh api repos/Ajkopensesame/beagley-cluster/git/refs -f ref=refs/heads/<name> -f sha=<sha>
```

Default branch at recording time: `codex/maplibre-native-yocto-build` @ `d63a7552a3f6`. Never deleted: the default branch, `main`, `legacy-main-2026-10-03`, and any branch with an open PR. Tags are untouched.

| Branch | Tip SHA | Last commit | Status | Action |
|---|---|---|---|---|
| `wip/maps-mac-debug` | `f2a0d7bb2d090bcd529cf74a0feacc21cefaae5c` | 2026-01-04 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `chore/theme-qtobject` | `0870330a95d70d8b5dfcd1f1269922336baf0db1` | 2026-01-05 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `rescue/pre-run-origin-main-20260111-1506` | `493bd5103deade1c5a417fc37b94f390f07177e6` | 2026-01-11 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `running-latest` | `a19a72485f6aab1b8ce32ed225a7a19728cf58cd` | 2026-01-18 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `chore/bundle-fonts` | `aef61221251eeda4e81655099407db74a648567a` | 2026-01-21 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `integrate/mapcenter-no-webengine` | `65e20520083e4394aeb02d2aa8b95fa4698bab56` | 2026-01-21 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `feat/bbb-hub-v1` | `93869142e7cc85f30bfb07455f7666db3d2330bf` | 2026-04-18 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `codex/live-gps-source-of-truth-20260426` | `031d5e4e9c87f096ce39ef72231e8e678f358caa` | 2026-04-26 | tip NOT merged, no PR | delete (recoverable by SHA) |
| `feat/diagnostic-replay-contract-v1` | `e73ca2d14904820c43bfdb3b2c6cf5c43f67063a` | 2026-07-02 | tip merged into default | delete |
| `chore/community-files` | `a6a49d8d5509b7313e16e3461a0285e581d37669` | 2026-10-03 | PR #14 merged, tip not an ancestor | delete |
| `chore/real-orbitron-fonts` | `c0df16fa0c7275bf127bba50c0326e85dfea3108` | 2026-10-03 | tip merged into default | delete |
| `chore/repo-hygiene-untrack-junk` | `1b8ea882f9b7821d701b415560333d0c81ffe3c8` | 2026-10-03 | tip merged into default | delete |
| `chore/sync-script-safety-docs` | `bcf21800728cf4020cfe382cb8f54a23dcca65bb` | 2026-10-03 | tip merged into default | delete |
| `ci-fix/skin-v2-qt-resources` | `9751ab346f3ddb9ef771c00b9ca9d6a477a9dbbf` | 2026-10-03 | tip merged into default | delete |
| `ci/real-checks` | `c9412d9c44f85e398af77f81ce3a098b944a93cc` | 2026-10-03 | tip merged into default | delete |
| `ci/webengine-off-gate` | `edf62f45d11b395aba5a30535ab709749a5d9283` | 2026-10-03 | tip merged into default | delete |
| `docs/board-runbook` | `4bad207c1b8f1fb3e4ef5f69b308155538395ded` | 2026-10-03 | tip merged into default | delete |
| `docs/third-party-version-changelog` | `4e5c54aec0305419de62b30ec349afa519f771a2` | 2026-10-03 | tip merged into default | delete |
| `feat/central-hub-config` | `b1888dfc4efe967cffa4609efa2ce1e85825ec61` | 2026-10-03 | tip merged into default | delete |
| `feat/harden-frame-decoder` | `1d8a1b653569a488b82219ec0da7ec6c92d7c810` | 2026-10-03 | tip merged into default | delete |
| `feat/hub-watchdog-integration-test` | `34af4cddcf4b13831cd818a243081f42c9e356b7` | 2026-10-03 | tip merged into default | delete |
| `feat/link-lost-failsafe` | `94e98c6797745acc886e3901729d2c85c4ed16f3` | 2026-10-03 | tip merged into default | delete |
| `feat/phase4-serial-sensor-calibration` | `1c6159f32035fd880b7ec515e64db8eb16ee49f8` | 2026-10-03 | tip merged into default | delete |
| `fix/yocto-default-branch` | `805731fde5b272d35767c134e4e4306ddc7e5dbb` | 2026-10-03 | tip merged into default | delete |
| `port/phase1-vehicle-state` | `23f7eb9df909d687bf1077f749be47e6f0c687e9` | 2026-10-03 | tip merged into default | delete |
| `test/qttest-suite-ctest-ci` | `83774effc9cada66f5f7b4755520ddd9ed04ef3d` | 2026-10-03 | tip merged into default | delete |
| `ui/slice1-map-hierarchy-quiet-chrome` | `1e795eaca495e091fec8188201167417a9d648b4` | 2026-10-03 | tip merged into default | delete |
| `legacy-main-2026-10-03` | `039dc726a61f8ac8ff65b52553d543395c9817e2` | 2026-09-06 | protected / default | KEEP |
| `main` | `039dc726a61f8ac8ff65b52553d543395c9817e2` | 2026-09-06 | protected / default | KEEP |
| `build/aarch64-workflow` | `d8af4a5b646aa987d150e505bb5d87dde2291874` | 2026-10-03 | tip not merged, no PR; active work (last push 2026-10-03 16:31, 3 commits ahead) | KEEP (active) |
| `codex/maplibre-native-yocto-build` | `d63a7552a3f6dc1764864c5e0bd14b1d582844aa` | 2026-10-03 | protected / default | KEEP |
| `dependabot/github_actions/codex/maplibre-native-yocto-build/actions/deploy-pages-5` | `43a98f6a15829213aa2c9d791dc935554f296e25` | 2026-10-03 | open PR #28 | KEEP (open PR) |
| `dependabot/github_actions/codex/maplibre-native-yocto-build/actions/upload-pages-artifact-5` | `4323c1de5d12177ba801292ddd32813202a0401f` | 2026-10-03 | open PR #25 | KEEP (open PR) |
| `test/qml-smoke-qmllint` | `71385991d5673a87bfdf05b18d0361d35ce20af1` | 2026-10-03 | open PR #36 | KEEP (open PR) |
