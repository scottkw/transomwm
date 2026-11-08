---
phase: 09-polish-ship
plan: 12
subsystem: updates
status: complete
tags: [updater, github-releases, etag, state-machine, settings, SHIP-04]
requires: [09-11]
provides:
  - UpdateFeedTests (gifsmith update_test.go ported)
  - UpdateMachine + UpdateError (Engine, gifsmith UpdateService busy/prev rules)
  - GitHubReleaseClient ETag cache (If-None-Match, 304 reuse, 1 MiB capped read)
  - UpdateController.automatic (UserDefaults updates.automatic, default on)
  - Settings ▸ Updates error line and automatic-check toggle
affects: [09-13, 09-17]
tech-stack:
  added: []
  patterns:
    - "Pure UpdateMachine in Engine; the MainActor controller publishes it and exposes status/error as computed views"
    - "Stub URLProtocol answers an empty 304 when If-None-Match matches its etag (gifsmith serve())"
key-files:
  created:
    - Tests/TransomEngineTests/UpdateFeedTests.swift
    - Tests/TransomEngineTests/UpdateStateTests.swift
  modified:
    - Sources/TransomEngine/UpdateRelease.swift
    - Sources/TransomEngine/UpdateState.swift
    - Sources/TransomMac/Updates/GitHubReleaseClient.swift
    - Sources/TransomMac/Updates/UpdateController.swift
    - Sources/TransomMac/Updates/UpdateCopy.swift
    - Sources/TransomMac/Settings/UpdatesTab.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Tests/TransomMacTests/UpdateCheckTests.swift
decisions:
  - "UpdateFeed.parse reads absent draft/prerelease/assets as false/empty (Go zero values), so gifsmith's bare test bodies are not-installable rather than a decode failure"
  - "UpdateMachine.begin clears a shown error: a new check replaces the error line with the spinner"
  - "GitHubReleaseClient is a final class (MainActor by module default) holding etag/body; they are stored only after a 200 parses, so bad JSON is never replayed on a 304"
  - "The 200 body is read through session.bytes with a maxJSONBytes + 1 cap, so an endless response is cut off instead of buffered whole"
  - "UpdateController takes defaults: UserDefaults explicitly (the app passes .standard), so tests can never write the user's domain by default"
metrics:
  duration: ~35 min
  completed: 2026-11-07
estimate:
  tokens: 60000
  tasks: 3
actuals:
  tokens: 9000
  tasks: 3
  commits: 5
plan_head_before: dd6d725b55dc1b20aaa5b225a7fb6bce697fc93a
plan_head_after: 0b8d2ce6eb58b5d2601e09d09b853e635f46fbbf
---

# Phase 9 Plan 12: Update check hardened to gifsmith's standard Summary

The update check now follows every gifsmith release rule, pinned by ported tests. It never offers a draft, a prerelease, a bad tag, an asset that is missing, not uploaded, outside the size bounds or without a digest, or a download on a host outside the allow-list. One check runs at a time and a failure restores the previous status. Only a failed manual check is shown, as "Couldn't check for updates. Check your connection, then try again." The client also sends `If-None-Match` and reuses the stored body on a 304. Settings ▸ Updates gained "Check for updates automatically" (`updates.automatic`, default on).

## What was built

- **Feed rules (`UpdateFeedTests`, 9 tests)**: the TestCompare, TestParseVersion, TestDMGAssetName, TestLatestFound, TestLatestNotOffered, TestLatestNotInstallable and TestGitHubAllow rows, ported. They add suffix-match traps (`evil-github.com`, `github.com.evil.com`, `objects.githubusercontent.com.evil`), a percent-encoded `..`, an explicit port, user:password, `file://`, and the 1 MiB cap tested at the boundary.
- **State (`UpdateMachine`)**: `begin(.check)` returns false and changes nothing while busy. `succeed` sets the status and clears the error. `fail(_:manual:)` restores the status from before the operation and keeps the error only when the check was manual.
- **Controller and tab**: `UpdateController` publishes `machine`, and `status` and `error` read from it. `checkNow(manual: Bool = true)` runs the check. `UpdatesTab` shows a red `xmark.octagon.fill` (accessibility label "Error") with `UpdateCopy.errorLine`. Its buttons stay those of the restored status, and Check for Updates is disabled while `machine.isBusy`.
- **Client**: after a parsed 200, the ETag and body are stored. 304 reuses the stored body. A 304 with nothing stored, 403, 429 and 5xx all throw. 404 returns `.none`. The 200 body is read through a 1 MiB + 1 cap.
- **Automatic switch**: `UpdateController.automaticKey = "updates.automatic"` is read with a true default from the injected `UserDefaults`, and the setter sends `objectWillChange`. The tab has a second Section with the toggle and the UI-SPEC footer. The daily schedule that reads it is 09-17's.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | Tracer: an uninstallable release is never offered | e117daf |
| 2 | UpdateMachine: one operation at a time, failures restore, manual errors shown (TDD) | 15b22af (RED), 164254d (GREEN) |
| 3 | ETag caching, rate-limit answers, automatic-check toggle (TDD) | 27cefb3 (RED), 0b8d2ce (GREEN) |

## Verification

- `.build/09-12-t1.log`: UpdateFeedTests 9 passed and UpdateCheckTests 6 passed, including `anUninstallableReleaseIsNeverOffered`. no-appkit: OK. The tracer gate re-ran `<verify>` end to end (passed) before expanding.
- `.build/09-12-t2.log`: UpdateStateTests 4 passed and UpdateCheckTests 6 passed.
- `.build/09-12-t3.log`: UpdateCheckTests 11 passed (`aSecondCheckSendsTheETagAndReusesTheBodyOn304`, `a304WithNoStoredBodyIsAFailedCheck`, `rateLimitAnswersAreFailedChecks`, `anOversizedBodyIsAFailedCheck`, `theAutomaticSwitchDefaultsOnAndPersists`).
- `.build/09-12-full.log`: four passed "Test run with" lines (271 / 532 / 124 / 1316) and no ✘. no-appkit: OK (67 files). After the full run, two doc comments were reworded (comments only) and `swift build` passed.
- Acceptance greps: `evil-github.com` 1, `struct UpdateMachine` 1, `Couldn't check for updates` 1, `If-None-Match` in the client 1, `updates.automatic` in the controller 1.

## TDD Gate Compliance

- Task 2: the RED commit 15b22af failed to compile because `UpdateMachine` was undefined. The GREEN commit 164254d made all 4 pass. That commit also hoisted mutating `begin` calls out of `#expect`, which cannot take a mutating operand.
- Task 3: the RED commit 27cefb3 failed to compile because `defaults:`, `automaticKey`, `automaticToggle` and `automaticFooter` were missing. The GREEN commit 0b8d2ce made all 11 pass. It also made the test's `withDefaults` helper synchronous, because sending `UserDefaults` into an async closure is a Swift 6 region error.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Absent draft/prerelease/assets keys broke decoding**
- **Found during:** Task 1
- **Issue:** gifsmith's own not-installable bodies leave out `draft` and `prerelease`. The Swift `Raw` struct required both, so such a release threw a DecodingError instead of reading as not installable.
- **Fix:** made the three fields optional, with absent read as false or empty (Go zero values).
- **Files modified:** Sources/TransomEngine/UpdateRelease.swift
- **Commit:** e117daf

**2. [Rule 2 - Missing critical] Capped read instead of `data(for:)`**
- **Found during:** Task 3
- **Issue:** `session.data(for:)` buffers the whole response before the 1 MiB check, so an endless body (T-09-21) would grow memory without bound.
- **Fix:** read through `session.bytes(for:)` and throw `bodyTooLarge` once maxJSONBytes + 1 bytes are read, as gifsmith's `LimitReader` does.
- **Files modified:** Sources/TransomMac/Updates/GitHubReleaseClient.swift
- **Commit:** 0b8d2ce

**3. [Rule 3 - Blocking] `UpdateController` init needs `defaults:`**
- The app call site in `TransomMacApp.swift` (not in the plan's file list) now passes `defaults: .standard`. Commit 0b8d2ce.

Extra tests beyond the plan: `aPublishedReleaseWithAValidDMGIsInstallable` (TestLatestFound) and `anOversizedBodyIsAFailedCheck` (the client-side cap).

## Notes

- `anOversizedBodyIsAFailedCheck` takes about 5 s in a debug build, because `AsyncBytes` iterates one byte at a time over the 1 MiB. Swapping `Data` for `[UInt8]` made no difference. Real release JSON is a few KB, so production checks are unaffected.
- The `updates.automatic` value is stored and shown but nothing reads it yet. The launch and daily check are 09-17's.

## Known Stubs

None that block this plan's goal. The automatic switch has no scheduler yet, by plan (09-17).

## Self-Check: PASSED

- FOUND: Tests/TransomEngineTests/UpdateFeedTests.swift, Tests/TransomEngineTests/UpdateStateTests.swift, Sources/TransomEngine/UpdateState.swift
- FOUND commits: e117daf, 15b22af, 164254d, 27cefb3, 0b8d2ce
