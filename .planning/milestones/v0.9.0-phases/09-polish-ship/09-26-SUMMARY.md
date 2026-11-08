---
phase: 09-polish-ship
plan: 26
subsystem: release/docs
tags: [D-11, D-12, D-18, D-20, D-25, release, readme, private-api]
status: complete
requires: [09-29]
provides:
  - "MARKETING_VERSION 0.9.0 (CURRENT_PROJECT_VERSION 2) and docs/release-notes-0.9.0.md, so the tag gate passes for v0.9.0"
  - "A local --skip-notarize dry run of 0.9.0: build/Transom-0.9.0-universal.dmg with a verifying .sha256 (not notarised, not uploaded)"
  - "The phase-end README: Install, Settings/Updates/Menu bar controls rows, menu paragraph, settings URL, data keys, truthful Privacy"
  - "docs/macos-beta-checklist.md: every private symbol from the code, its capability and --disable-private name, the per-beta procedure"
  - "docs/releasing.md: the D-18 name check and the D-20 decision"
affects: [09-27, 09-28, 09-30]
tech-stack:
  added: []
  patterns: []
key-files:
  created:
    - docs/release-notes-0.9.0.md
    - docs/macos-beta-checklist.md
  modified:
    - xcode/project.yml
    - README.md
    - docs/releasing.md
decisions:
  - "Release notes Known issues: multi-display unverified, no macOS 14 test run, external Magic Trackpad untested. The macOS 27 native tab-group close gap is NOT listed: the user ruled it blocks 0.9.0 (D-25) and 09-30 fixes it"
  - "README's 'Planned features' section is removed outright: with Phase 9 complete it had no rows left"
  - "README Testing notes that GitHub Actions is paused until the repo is public (D-22), so it does not imply CI ran"
requirements: [SHIP-05, SHIP-04]
metrics:
  duration: ~12 min
  completed: 2026-11-07
estimate:
  tokens: 45000
  tasks: 3
actuals:
  tokens: 7900
  tasks: 3
  commits: 5
plan_head_before: ff6fe482db08aea0ebe8591383f0ab1298927e91
plan_head_after: b2389def042d9536f83a43d6211dde46b3fe9eec
---

# Phase 9 Plan 26: 0.9.0 version, release notes, phase-end README and beta checklist Summary

The version is now 0.9.0 and `scripts/release-version.sh v0.9.0` prints 0.9.0. A local `--skip-notarize` dry run built `build/Transom-0.9.0-universal.dmg` with a `.sha256` that verifies, and the built app reports 0.9.0. The README now covers installing with Homebrew and says plainly what Transom sends over the network. A per-beta private-API checklist lists every symbol in `TransomPrivate`, and the name check is on record.

## Tasks

| # | Task | Commit | Files |
|---|---|---|---|
| 1 | Version 0.9.0, release notes, gate and local dry run (tracer) | 9f81c27 | xcode/project.yml, docs/release-notes-0.9.0.md |
| 2 | Phase-end README | 572f825 | README.md |
| — | D-25: drop the tab-group close gap from Known issues | d65df87 | docs/release-notes-0.9.0.md |
| 3 | macOS-beta checklist, name-check record, full host suite | b2389de | docs/macos-beta-checklist.md, docs/releasing.md |

`7410000` (D-25 in CONTEXT) falls inside the measured range. The orchestrator committed it, not this plan, so `commits: 5` includes it and this plan made 4.

## Verification

- Task 1 (tracer gate, re-run end to end): `release-version.sh v0.9.0` printed `0.9.0`; `scripts/release.sh --skip-notarize` exited 0 (`.build/09-26-t1.log`, arm64 + x86_64, designated requirement satisfied); `shasum -a 256 -c Transom-0.9.0-universal.dmg.sha256` printed OK (`864a75f2…39cd`); `CFBundleShortVersionString` 0.9.0, `CFBundleVersion` 2. `⚡ Tracer verified end-to-end — expanding`.
- Task 2: the plan's grep verification passed. The stale "no network code", "Phase 9 is not in the code yet" and "Zoom ▸ Shortcuts…" are gone.
- Task 3: every symbol from `grep -rhoE '"(_AX|SLS|CGS|CoreDock|MT)[A-Za-z]+"' Sources/TransomPrivate` (25) appears in the checklist, and `--disable-private=` and D-20 are present. Full host suite (`.build/09-26-full.log`): 271, 602, 124 and 1336 tests passed (four "Test run with" lines); `no-appkit: OK (69 files)`.

## Deviations from Plan

### Orchestrator course correction

**1. [D-25] The macOS 27 native tab-group close gap is not a known issue**
- **Found during:** Task 2 (message from the orchestrator)
- **Change:** removed the bullet from `docs/release-notes-0.9.0.md` Known issues (it had been committed in Task 1). The README never listed it. The "no macOS 14 test run" item stays.
- **Commit:** d65df87

### Auto-fixed Issues

**1. [Rule 2 - Correctness] Other stale README text fixed beyond the plan's list**
- Status said "pre-release, no public download, 0.3.0". It now says 0.9.0 is the first public release.
- The `scripts/release.sh` row named `build/Transom-0.3.0.dmg`. It now names the versioned universal DMG, the designated-requirement check and the CI release job.
- The Debug paragraph now includes the new Updates and Login item lines.
- The `TransomMac` layout row named "the Shortcuts window". It now names Settings, onboarding and the update check.
- Testing now notes that CI is paused until the repo is public (D-22).
- The second "rebind them in Shortcuts" now says Settings ▸ Shortcuts.
- **Commit:** 572f825

**2. [Rule 1 - Accuracy] CoreDock check step**
- The first draft said to stop the overview opening by switching Accessibility off. The code (`ArrangeController.missionControlKey`) falls back to CoreDock when the overview refuses, and a full-screen Space is the reliable trigger. The step now says to press F3 in a native full-screen app and check the `missionControl` log line.
- **Commit:** b2389de

## Known Stubs

None. The checklist's Results table is empty on purpose; it is filled in on each beta.

## Notes for later plans

- The local DMG is not notarised and was never uploaded (T-09-56). Only the CI release job makes the published artefact.
- `docs/macos-beta-checklist.md` names `CloseIntegrationTests` and `FixtureTrackingTests` as the AXWindowID live suites, and says `MultitouchIntegrationTests` in the VM proves only that the shim loads (no trackpad).
- The 0.9.0 release notes list the D-23 close fix under Fixes. When 09-30 lands, add the D-25 tab-group fix there too.

## Self-Check: PASSED

- FOUND: docs/release-notes-0.9.0.md, docs/macos-beta-checklist.md, build/Transom-0.9.0-universal.dmg(.sha256)
- FOUND commits: 9f81c27, 572f825, d65df87, b2389de
