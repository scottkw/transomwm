---
phase: 09-polish-ship
plan: 14
subsystem: release
status: complete
tags: [release, codesign, designated-requirement, dmg, notarisation, sha256, SHIP-05]
requires: [09-13]
provides:
  - scripts/release.sh reads the version from xcode/project.yml MARKETING_VERSION
  - Exact designated-requirement compare against the committed xcode/designated-requirement.txt
  - build/Transom-<version>-universal.dmg and its shasum-format .sha256 (written after stapling)
  - TRANSOM_NOTARY_PROFILE (default pane-notary) and staple_retry (5 attempts, 20 s apart)
  - scripts/release-version.sh tag and version gate
affects: [09-15, 09-17, 09-22, 09-26]
tech-stack:
  added: []
  patterns:
    - "Version read once from project.yml with sed, MAJOR.MINOR.PATCH enforced (release.sh and release-version.sh)"
    - "DR pinned in a committed one-line file; the release fails on any byte of difference"
key-files:
  created:
    - xcode/designated-requirement.txt
    - scripts/release-version.sh
  modified:
    - scripts/release.sh
decisions:
  - "The committed DR is the RESEARCH-verified Release DR; a fresh --build-only build matched it byte for byte, so no DR change was needed"
  - "The .sha256 holds the bare file name (written from inside build/), so `shasum -c` works in build/ and in the release job"
  - "release-version.sh checks the release notes before the argument count (gifsmith order), so a missing notes file is reported first"
  - "Kept --skip-jenkins as the plan says; it makes the create-dmg layout flags inert (documented with a shortcut: comment)"
metrics:
  duration: "~20 min"
  completed: 2026-11-07
estimate:
  tokens: 40000
  tasks: 2
actuals:
  tokens: 2200
  tasks: 2
  commits: 2
plan_head_before: 0bd569143896a79b87496594b0f3c91eba581ba0
plan_head_after: a78932bcefd6815cd8dea47b100fce0fea119c3d
---

# Phase 9 Plan 14: Release script version, designated requirement, universal DMG and tag gate Summary

`scripts/release.sh` now takes the version from `xcode/project.yml`. It refuses any app whose designated requirement differs from the committed `xcode/designated-requirement.txt`. It builds `build/Transom-<version>-universal.dmg` with a `shasum -c`-ready `.sha256` beside it, reads the notary profile from `TRANSOM_NOTARY_PROFILE`, and retries every staple and validate. The new `scripts/release-version.sh` gates a tag against MARKETING_VERSION and the release notes.

## What was built

- **Version from project.yml** (Task 1): `sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' xcode/project.yml`, failing unless MAJOR.MINOR.PATCH. The hard-coded `version=0.3.0` and the unused `identifier` variable are gone.
- **Exact DR compare** (Task 1): the text after `designated => ` from `codesign -d -r-` must equal `xcode/designated-requirement.txt`. On a mismatch the script prints both strings and fails, because a changed DR would cost every user the Accessibility grant on update.
- **`xcode/designated-requirement.txt`**: the Release DR from RESEARCH, on one line. A fresh `release.sh --build-only` produced exactly this DR.
- **Universal DMG and .sha256** (Task 2): `build/Transom-$version-universal.dmg`; after verify, `(cd build && shasum -a 256 "Transom-$version-universal.dmg") > "$dmg.sha256"`, printed last. The old DMG and `.sha256` are removed before each build.
- **Notary profile**: `profile="${TRANSOM_NOTARY_PROFILE:-pane-notary}"`. Only the name is used; no credentials are printed.
- **`staple_retry staple|validate <path>`**: 5 attempts, 20 s apart, with gifsmith's message. It covers staple of the app, staple of the DMG (hdiutil path) and validate of the DMG.
- **create-dmg layout**: `--window-size 540 380 --icon-size 128 --icon "Transom.app" 140 180 --hide-extension "Transom.app" --app-drop-link 400 180 --skip-jenkins`, with the codesign and notarize arguments unchanged. The hdiutil branch is unchanged and remains the CI path (D-11).
- **`scripts/release-version.sh`** (gifsmith shape): prints MARKETING_VERSION after checking that it is MAJOR.MINOR.PATCH, that `docs/release-notes-$v.md` exists, and, when a tag is given, that it equals `v$v`. More than one argument is a usage error. Every failure exits 1 with a `release-version:` message.

## Verification

- Task 1: `scripts/release.sh --build-only` exited 0. Its last log line is the app path, and the built app's DR equals the committed file (`.build/09-14-t1.log`).
- Task 2: `scripts/release.sh --skip-notarize` exited 0 (`.build/09-14-t2.log`, create-dmg branch). `shasum -c` in `build/` reported `Transom-0.3.0-universal.dmg: OK`, `hdiutil verify` reported VALID, and `codesign --verify --strict` passed on the DMG. sha256 `5a37d9c2…52c7`.
- Gate: `release-version.sh v9.9.9` and a bare run both exit 1 and name `docs/release-notes-0.3.0.md is missing` (no `docs/` yet). In a scratch copy with the notes file present: a bare run and `v0.3.0` print `0.3.0`, `v0.3.1` exits 1 with the mismatch message, and two arguments exit 1 with the usage message.
- Acceptance greps: `version=0.3.0` 0; `designated-requirement.txt` 2; `identifier "com.eightabyte.transom"` 1; `TRANSOM_NOTARY_PROFILE` 2; `universal.dmg` 4; `staple_retry` 4; `release-version.sh` is executable.
- Nothing was notarised, uploaded, tagged or pushed. `build/` artefacts are local only.

## Deviations from Plan

**1. [Rule 2 - Correctness] The create-dmg layout flags have no effect while `--skip-jenkins` is set**
- **Found during:** Task 2
- **Issue:** create-dmg applies the window size, icon size, icon positions and hidden extension only through its Finder AppleScript. `--skip-jenkins` skips that AppleScript, and create-dmg's source says so ("This will result in a DMG without any custom background or icons positioning"). So the UI-SPEC Surface 8 layout truth is not met on the create-dmg path.
- **Fix:** I kept the plan's exact flags, since dropping `--skip-jenkins` would raise a Finder Automation prompt during an unattended run. I added a `shortcut:` comment in `release.sh` saying the flags are inert and when to drop `--skip-jenkins`. CI uses the hdiutil branch, which has no layout either way (D-11), so released DMGs are unaffected.
- **Files modified:** scripts/release.sh
- **Commit:** a78932b

Also removed the now-unused `identifier=` variable from `release.sh` (Task 1). Only the substring check used it.

## Known Stubs

None.

## Deferred Issues

- `staple_retry` only runs on the notarise path, which this plan may not exercise (no notarisation allowed). Its first real run will be the 09-15 release job or a manual notarised release.
- The DMG window layout needs a decision: run create-dmg without `--skip-jenkins` on a Mac that allows Finder automation, or accept the default Finder window.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 3ad17bf | release.sh reads the version from project.yml and matches the committed designated requirement exactly |
| 2 | a78932b | universal DMG name with .sha256, notary profile variable, stapler retries, DMG layout and the tag gate |

## Self-Check: PASSED

- FOUND: xcode/designated-requirement.txt, scripts/release-version.sh, scripts/release.sh
- FOUND: 3ad17bf, a78932b (ancestors of HEAD)
