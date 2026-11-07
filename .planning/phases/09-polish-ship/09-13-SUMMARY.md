---
phase: 09-polish-ship
plan: 13
subsystem: updates
status: complete
tags: [updater, dmg, security-framework, sha256, quarantine, homebrew, settings, SHIP-04]
requires: [09-12]
provides:
  - DMGVerifier (SecStaticCodeCheckValidity, team S2K7P43927 + notarized; setxattr quarantine)
  - DMGDownloader (allow-listed download, <=5 redirects, .part 0600 in a 0700 dir, size + SHA-256, clean())
  - UpdateStatus downloading/verifying/opened; UpdateMachine .download; UpdateError downloadFailed/verifyFailed/openFailed
  - UpdateController.downloadAndOpen and installedWithHomebrew
  - InstallLocation.isHomebrew (Engine)
  - Settings > Updates download, verifying, opened and Homebrew states
affects: [09-14, 09-17, 09-22]
tech-stack:
  added: []
  patterns:
    - "Delegate-based URLSessionDownloadTask bridged to async with a checked continuation; size and hash checked on the session queue"
    - "Verification injected as @Sendable (URL) -> OSStatus and run in Task.detached; open injected as (URL) -> Bool"
    - "Env-gated real-artifact suite: @Suite(.enabled(if: env[UPDATE_REAL_DMG] != nil))"
key-files:
  created:
    - Sources/TransomMac/Updates/DMGDownloader.swift
    - Sources/TransomMac/Updates/DMGVerifier.swift
    - Sources/TransomEngine/InstallLocation.swift
    - Tests/TransomMacTests/UpdateDownloadTests.swift
    - Tests/TransomMacTests/UpdateRealDMGTests.swift
  modified:
    - Sources/TransomEngine/UpdateState.swift
    - Sources/TransomMac/Updates/UpdateController.swift
    - Sources/TransomMac/Updates/UpdateCopy.swift
    - Sources/TransomMac/Settings/UpdatesTab.swift
    - Tests/TransomEngineTests/UpdateStateTests.swift
decisions:
  - "UpdateError.downloadFailed carries the version, because its copy names it"
  - "A body larger than the asset size is cancelled mid-download and counts as a size failure (verifyFailed), like a short one"
  - "A failed open keeps the verified file (gifsmith); every failed size, digest, signature or quarantine check deletes it"
  - "Download and Open restores available on failure even when it started from opened"
metrics:
  duration: "~35 min"
  completed: 2026-11-07
estimate:
  tokens: 70000
  tasks: 3
actuals:
  tokens: 10900
  tasks: 3
  commits: 6
plan_head_before: 897268a13ebf07a5d03d5c210c0d3175d271b6ef
plan_head_after: 8e1984c6b22194356deae57526b8a5379ab3a480
---

# Phase 9 Plan 13: Download and Open with in-process DMG verification Summary

Download and Open fetches `Transom-{v}-universal.dmg` through an allow-listed, size- and SHA-256-checked download. It then verifies the Developer ID team S2K7P43927 and notarisation with `SecStaticCodeCheckValidity` (no subprocess). Only after that does it quarantine the file and open it. Every failed check deletes the file and opens nothing, and a Homebrew install is shown `brew upgrade --cask transom` instead.

## What was built

- **DMGVerifier**: `check(_:requirement:)` runs `SecStaticCodeCreateWithPath`, `SecRequirementCreateWithString` and `SecStaticCodeCheckValidity` with strict-validate and check-all-architectures, using the requirement `anchor apple generic and certificate leaf[subject.OU] = "S2K7P43927" and notarized`. `quarantine(_:)` writes `0081;<hex unix time>;Transom;` with `setxattr`.
- **DMGDownloader**: refuses a URL off `UpdateFeed.isAllowedDownload`. It creates the folder with 0700 and runs `clean()` first. The delegate allows at most 5 redirects, each on the allow-list, sends progress at most every 100 ms, and cancels a body larger than the asset size. The file is moved exclusively to `<asset>.part` with 0600, its byte count and chunked CryptoKit SHA-256 must equal the release's, and then it is renamed. On any failure the `.part` and final files are removed. `clean()` deletes only regular `Transom-*-universal.dmg[.part]` files. The production folder is `~/Library/Caches/com.eightabyte.transom/Updates`.
- **UpdateController.downloadAndOpen()**: the order is begin(.download), then download, then verifying, then `verify` (detached), then quarantine, then `open`, then opened. A size or digest failure gives `verifyFailed`, and so does a signature or quarantine failure, which also deletes the file. Any other download error gives `downloadFailed(version:)`, and `open` returning false gives `openFailed`. Logs (category `update`): "download {v} done", "verify failed: digest", "verify failed: team id (status)", "verify failed: quarantine", "opened {asset name}".
- **Updates tab**: available + DMG shows Download and Open (default, prominent), Release Notes and Check for Updates. Available + Homebrew shows the intro line and the selectable monospaced command, with Copy Command (default), Release Notes and Check for Updates. Downloading shows "Downloading Transom {v}… {p}%" and a linear bar (indeterminate without a fraction), with no buttons enabled. Verifying shows a spinner with no buttons enabled. Opened shows the UI-SPEC sentence, Quit Transom (default) and Check for Updates.
- **InstallLocation** (Engine): `caskroomPaths` and `isHomebrew(exists:)`. The controller reads it once at init through an injectable `fileExists`.

## Tasks

| # | Task | Commits |
|---|------|---------|
| 1 | Tracer: Download and Open fetches, digests, verifies, quarantines and opens | 099e79e |
| 2 | Failed checks delete the file and open nothing; the real DMG passes (TDD) | b040617 (RED), a2bf12e (GREEN) |
| 3 | Download states in the Updates tab and the Homebrew branch (TDD) | 732f8a8 (RED), 8e1984c (GREEN) |

## Verification

- `.build/09-13-t1.log`: UpdateDownloadTests 1 passed (`aMatchingDownloadIsVerifiedQuarantinedAndOpened`) and UpdateStateTests 5 passed (including the new `aDownloadStartsOnlyFromAvailableOrOpened`). no-appkit: OK. The tracer gate re-ran `<verify>` end to end, and it passed before expanding.
- `.build/09-13-t2.log`: UpdateDownloadTests 7 passed.
- `.build/09-13-t2-real.log`: with `UPDATE_REAL_DMG=build/Transom-0.3.0.dmg`, UpdateRealDMGTests 3 passed (the real DMG passes, another team's OU fails, a byte-flipped copy fails). Without the variable the suite is skipped.
- `.build/09-13-t3.log`: UpdateDownloadTests 9 passed.
- `.build/09-13-full.log`: four passed "Test run with" lines (271, 544, 124, 1317 tests), no ✘. `scripts/check-no-appkit.sh` printed no-appkit: OK (68 files).
- Acceptance greps: `SecStaticCodeCheckValidity` 1, `Process(|codesign|spctl` 0, `UPDATE_REAL_DMG` 3, "Nothing was opened" 1, "brew upgrade --cask transom" 1, `InstallLocation.swift` present.

## TDD Gate Compliance

- Task 2: RED b040617 compiled (with a no-op `clean()` stub) and failed on assertions in the four target tests: files left behind after a wrong digest, a wrong size or a failed signature, and `clean()` removing nothing. `aRedirectOffTheAllowListIsRefused` and `aFailedOpenGoesBackToAvailable` already passed at RED, because the tracer's redirect delegate and open mapping covered them. GREEN a2bf12e made all 7 pass. The real-DMG suite was added in the RED commit and passed against the tracer's `DMGVerifier`.
- Task 3: RED 732f8a8 failed on assertions: `isHomebrew` stubbed to false, no percentage in the downloading line, and empty copy constants. GREEN 8e1984c made all 9 pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `downloadFailed` carries the version**
- **Found during:** Task 1
- **Issue:** The UI-SPEC copy "Couldn't download Transom {v}…" needs the version, but `UpdateCopy.errorLine` only receives the error.
- **Fix:** `UpdateError.downloadFailed(version: String)`.
- **Commit:** 099e79e

**2. [Rule 3 - Blocking] The error copy and the basic new status lines were added in Task 1**
- **Found during:** Task 1
- **Issue:** The new `UpdateStatus` and `UpdateError` cases made the `UpdateCopy` and `UpdatesTab` switches non-exhaustive, and the tracer needed its Download and Open button to be reachable from Settings.
- **Fix:** Task 1 added the three error strings, the verifying and opened lines, a downloading line without a percentage, and the button. Task 3 added the percentage, the bar, the Homebrew branch and Quit Transom.
- **Commit:** 099e79e

**3. [Rule 2 - Critical] An oversized body is cut off**
- **Found during:** Task 2
- **Issue:** A download task would otherwise write an endless body to disk. gifsmith uses `LimitReader(size + 1)`.
- **Fix:** `didWriteData` cancels once more bytes arrive than the asset size, and the result maps to `verifyFailed`, the same as a short body. `aShortDownloadDeletesTheFile` covers both one byte short and one byte over.
- **Commit:** a2bf12e

**4. DMGVerifier doc comment reworded**
- The comment named the CLI tools, which made the `spctl` acceptance grep print 1. It now says "no subprocess".

## Known Stubs

None. The Task 2 and Task 3 RED stubs (`clean()`, `isHomebrew`, empty copy constants) were all replaced in their GREEN commits.

## Notes for later plans

- The status-menu items "Update to Transom {v}…" and "Copy “brew upgrade --cask transom”" and the update dot are not part of this plan.
- A failed open keeps the verified DMG in the Updates folder (gifsmith). The next download's `clean()` removes it.
- `notarized` in the requirement may consult Apple (RESEARCH A11). The real-DMG run passed online, and it was not tested offline.

## Self-Check: PASSED

- Files: DMGDownloader.swift, DMGVerifier.swift, InstallLocation.swift, UpdateDownloadTests.swift and UpdateRealDMGTests.swift all exist.
- Commits: 099e79e, b040617, a2bf12e, 732f8a8 and 8e1984c are all ancestors of HEAD.
