# Releasing

## Versioning scheme

- [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.
  While `MAJOR` is `0`, minor bumps may include breaking changes (UI behaviour, hub wire protocol usage,
  config/env names).
- Git tags are `vX.Y.Z` (e.g. `v0.2.0`), annotated, created on the default branch
  `codex/maplibre-native-yocto-build`.
- The single source of truth for the version is `project(beagley_cluster VERSION X.Y.Z ...)` in
  `CMakeLists.txt`. Keep it equal to the latest tag when releasing.
- The pre-existing tags (`v0.1-gauges-working`, `speedo-labels-working`, `maplibre-v1`,
  `live-gps-source-of-truth-20260426`) are informal milestones from older history and don't follow this scheme.
- Wire-protocol compatibility with `vehicle-hub` is documented in `CHANGELOG.md` for each release.

## Release checklist

1. All intended PRs are merged; default branch CI (`Configure + build (WITH_WEBENGINE=OFF)`) is green.
2. Move the `[Unreleased]` entries in `CHANGELOG.md` to a new `## [X.Y.Z] - YYYY-MM-DD` section and update the
   compare links at the bottom.
3. Bump `VERSION` in `CMakeLists.txt` and merge via a normal PR (no direct pushes, no force-push).
4. Check `THIRD_PARTY_NOTICES.md` is current (new assets, fonts, services; no unresolved TO CONFIRM items for
   anything newly shipped).
5. Board verification on BeagleY-AI with the Yocto appliance image built from the release commit (record the
   image/build id in the release notes). Deployment to a board is a manual, owner-approved step.
6. Create an annotated tag on the merge commit: `git tag -a vX.Y.Z -m "vX.Y.Z" <sha>` and
   `git push origin vX.Y.Z`.
7. Create the GitHub release from the tag using the changelog section as the notes.
