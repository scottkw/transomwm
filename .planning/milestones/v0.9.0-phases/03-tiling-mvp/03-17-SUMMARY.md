---
phase: 03-tiling-mvp
plan: 17
subsystem: release
status: complete
tags: [tile-10, d-30, release, notarisation, codesign, dmg, gatekeeper]
requires:
  - "03-16: the conflict alert, seen on the clean-Mac install check"
  - "scripts/build-debug.sh --release: generate, build, signature and designated-requirement checks"
provides:
  - "scripts/release.sh: --build-only, --skip-notarize and the full local run (build, verify, notarise and staple the app, DMG, sign, notarise and staple the DMG, spctl and stapler checks, sha256 last)"
  - "xcode/project.yml: MARKETING_VERSION 0.3.0, Release OTHER_CODE_SIGN_FLAGS --timestamp"
  - "build/ ignored"
  - "A local notarised, stapled build/Pane-0.3.0.dmg (sha256 ee940af0c6badf8f16e2a4124f4083507d6c775dc45eeee2c9fa4028a0dc5761)"
affects:
  - "Phase 9 (CI notarisation, Homebrew cask): release.sh is the local model"
  - "Transom rename: the public 0.3.0 pre-release is held until then"
tech-stack:
  added: []
  patterns:
    - "release.sh builds through build-debug.sh --release and takes its last stdout line as the app path"
    - "Each signing property is checked separately, with its own failure message (Timestamp=, --verify --strict --deep, forbidden entitlements, lipo archs, version, URL scheme)"
key-files:
  created:
    - scripts/release.sh
  modified:
    - xcode/project.yml
    - .gitignore
key-decisions:
  - "The clean-Mac install check ran in a fresh Tart VM (macOS 15.7.7, Gatekeeper on, DMG quarantined as a Safari download) instead of over the host's 0.2.0, by user choice"
  - "The hdiutil-fallback DMG steps were finished by hand after release.sh failed at them. The defect is logged in deferred-items.md, not fixed here"
  - "Nothing published: no GitHub release, upload or tag for 0.3.0 (held until the Transom rename)"
requirements-completed: [TILE-10]
duration: about 13 h wall clock (Task 1 01:38 local to checkpoint close), mostly waiting on the human checkpoint
completed: 2026-10-26
actuals:
  tokens: 1750
  tasks: 3
  commits: 2
plan_head_before: 1124363331ab37a189dd1024db86b157a2a9da85
plan_head_after: f33ca805955fa122e5d6e59ca39d3579d64450b3
---

# Phase 3 Plan 17: Local 0.3.0 Release (D-30, TILE-10) Summary

`scripts/release.sh` builds a universal, Developer ID-signed, hardened and securely timestamped Pane 0.3.0, then notarises and staples it. It turned out that a hardened build that dlopens SkyLight does notarise (D-30 proof). The DMG was notarised, stapled and verified. A fresh macOS 15.7.7 VM with Gatekeeper on accepted it as Notarized Developer ID. Pane launched there and docked TextEdit windows with Screen Recording never granted and zoom absent (TILE-10). The script's hdiutil fallback failed partway through the DMG steps, so those steps were finished by hand. Nothing was published.

## What was built

- **`scripts/release.sh`** (Tasks 1-2). It follows build-debug.sh's pattern: `set -euo pipefail`, repo-root `cd`, a `fail()` helper, and exit 2 on a bad flag.
  - `--build-only` builds through `build-debug.sh --release`. It then refuses to continue if any of these checks fails: no `Timestamp=`, `--verify --strict --deep` fails, get-task-allow / disable-library-validation / apple-events entitlements are present, the archs are not both x86_64 and arm64, the version is not 0.3.0, or the URL scheme is not `pane`.
  - The full run zips the app with ditto, then runs `notarytool submit --wait` (on rejection it prints the log command) and `stapler staple`. It stages `build/dmg-staging` and builds the DMG with create-dmg when installed, otherwise with `hdiutil create`. The DMG is then signed, notarised and stapled. The run finishes with `hdiutil verify`, a check that `spctl` reports "Notarized Developer ID", and `stapler validate`, and prints the sha256 last.
  - `--skip-notarize` runs everything except the notary and Gatekeeper steps.
- **`xcode/project.yml`**: `MARKETING_VERSION: "0.3.0"` and `OTHER_CODE_SIGN_FLAGS: "--timestamp"` in Release only.
- **`.gitignore`**: `build/`.

## Tasks

1. **Task 1 (tracer): `release.sh --build-only`.** `695fcde` (feat). The tracer gate re-ran the automated verify after commit, and it passed.
2. **Task 2: DMG, notarisation and stapling steps.** `f33ca80` (feat). Proven through `--skip-notarize`.
3. **Task 3 (checkpoint:human-action): credentials, the real run and the install check.** No commit. The evidence is below.

## Release evidence (checkpoint, 2026-10-26)

- The app was notarised (Accepted) and stapled by `scripts/release.sh`. So the Release build declares no new entitlements and still loads SkyLight at runtime through dlopen.
- DMG (hand-finished, see Deviations):
  - `codesign --timestamp` done.
  - `notarytool submit`: id `150effae-5f0a-495f-8a6a-230ed6d9eca4`, Accepted. `stapler staple` done.
  - `hdiutil verify`: VALID. `codesign --verify --strict`: OK. `stapler validate`: OK.
  - `spctl` accepts both the DMG and the app as `source=Notarized Developer ID`, `origin=Developer ID Application: Ken Scott (S2K7P43927)`.
- **sha256 `build/Pane-0.3.0.dmg` = `ee940af0c6badf8f16e2a4124f4083507d6c775dc45eeee2c9fa4028a0dc5761`.** I re-checked it with `shasum -a 256` when writing this summary, and it matches.
- Designated requirement of `build/dmg-staging/Pane.app`: `identifier "com.eightabyte.pane"` and `certificate leaf[subject.OU] = S2K7P43927`. This is the same as 0.2.0, so an existing Accessibility grant should survive the update.
- Clean-Mac install check, in a Tart VM (macOS 15.7.7, Gatekeeper re-enabled, DMG quarantined as a Safari download):
  - Gatekeeper accepted the app and Pane launched.
  - The 03-16 conflict alert appeared. "Turn Off" set `EnableTilingByEdgeDrag=0` and `EnableTopTilingByEdgeDrag=0` live (supports A11).
  - Accessibility was granted at 13:57:44. Dragging TextEdit windows docked them into split and stacked tiles, and layout.json confirms the layout.
  - Screen Recording was never granted and zoom is absent, so tiling works without either (TILE-10).
- Nothing published: `git tag -l '*0.3*'` is empty, and no release or upload was made. The host's `/Applications/Pane.app` is still 0.2.0.

## Deviations from Plan

**1. Install check in a VM, not on the host (user choice).** Plan step 4 installs over the host's 0.2.0 and checks that the existing Accessibility grant is kept. The check ran in a fresh VM instead. As a result:
- Gatekeeper, launch and tiling were proven on a clean Mac.
- Grant survival across the update was not exercised live. It rests on the unchanged designated requirement, which release.sh checks and which is shown above.
- The plan's `spctl -a -vv /Applications/Pane.app` verification ran against the VM's installed copy, not the host's.

**2. DMG steps finished by hand.** create-dmg is not installed, so release.sh took the hdiutil fallback. `hdiutil create` printed "created: …/build/Pane-0.3.0.dmg", but the file was not there and the DMG `codesign` failed (exit 1). The orchestrator re-ran the same hdiutil command by hand, which produced the file, then ran the script's remaining DMG steps by hand (results above). The root cause is unknown. The defect is logged in deferred-items.md and not fixed here.

## Known Issues

- **The release.sh hdiutil fallback is unreliable.** Until it is diagnosed, a release run without create-dmg can fail after the app is notarised. The release itself is unaffected: the DMG on disk is the verified one.
- Four more findings from the VM check are in deferred-items.md under "Found in 03-17":
  - An Accessibility grant made while Pane is running is not noticed until relaunch.
  - Safari does not dock when dragged by its unified toolbar.
  - The alert icon is a blank placeholder (AppIcon possibly missing from the Release build).
  - A floating Safari window was placed at the bottom of the desktop region.

## Known Stubs

None.

## Threat Flags

None. T-03-48 to T-03-51 are mitigated as planned:
- Signature, timestamp, notarisation and stapling are in place, and Gatekeeper was re-checked on the installed copy.
- The entitlement checks are in release.sh.
- The notary profile is referenced by name only.
- The designated-requirement check is in release.sh.

## Self-Check: PASSED

- `scripts/release.sh`, `xcode/project.yml`, `.gitignore` and `build/Pane-0.3.0.dmg` exist.
- Commits 695fcde and f33ca80 are ancestors of HEAD.
