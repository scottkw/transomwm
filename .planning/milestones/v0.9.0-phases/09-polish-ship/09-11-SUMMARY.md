---
phase: 09-polish-ship
plan: 11
subsystem: updates
status: complete
tags: [updater, github-releases, settings, SHIP-04]
requires: [09-10]
provides:
  - UpdateVersion / UpdateFeed / UpdateRelease / UpdateCheck (Engine, gifsmith update.go port)
  - UpdateStatus (idle, checking, current, available)
  - GitHubReleaseClient (ephemeral, no URLCache, unauthenticated)
  - UpdateController (MainActor status owner, checkNow, isEnabled)
  - UpdateCopy + Settings ▸ Updates tab
affects: [09-12, 09-13, 09-17, 09-27]
tech-stack:
  added: []
  patterns:
    - "Pure feed rules in TransomEngine, a thin URLSession shell in TransomMac"
    - "Stub URLProtocol in the session configuration; .serialized suite with nonisolated(unsafe) statics"
key-files:
  created:
    - Sources/TransomEngine/UpdateRelease.swift
    - Sources/TransomEngine/UpdateState.swift
    - Sources/TransomMac/Updates/GitHubReleaseClient.swift
    - Sources/TransomMac/Updates/UpdateController.swift
    - Sources/TransomMac/Updates/UpdateCopy.swift
    - Sources/TransomMac/Settings/UpdatesTab.swift
    - Tests/TransomMacTests/UpdateCheckTests.swift
  modified:
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/TransomMacApp.swift
decisions:
  - "UpdateFeed.parse enforces the 1 MiB JSON cap itself (throws UpdateFeedError.bodyTooLarge), so the cap is testable in Engine"
  - "isAllowedDownload also rejects an explicit port, mirroring Go's u.Host (which includes the port) exact match"
  - "checkNow() is a no-op when the controller is disabled, so a Debug/swift-run build never sends a request even if called"
  - "Without an Info.plist (swift run) the version line shows 'dev' and build '?', the Capabilities.swift convention"
metrics:
  duration: ~22 min
  completed: 2026-11-07
estimate:
  tokens: 60000
  tasks: 2
actuals:
  tokens: 6100
  tasks: 2
  commits: 3
plan_head_before: a17c299f7e921f667b170637a5b83fe3898e161b
plan_head_after: fc443f3b44e5a22f1969620868c0b2011e3f1d47
---

# Phase 9 Plan 11: Check for Updates tracer Summary

Settings ▸ Updates now asks GitHub's `releases/latest` for scottkw/transomwm over an ephemeral, cache-less, unauthenticated URLSession. It validates the JSON with the gifsmith rules ported to Engine and reports "Transom {v} is available. You have {c}." or "Transom {c} is up to date." This is proven against a stub URLProtocol only.

## What was built

- **Engine (`UpdateRelease.swift`, `UpdateState.swift`)**: `UpdateVersion.parse/compare` (gifsmith regex as a whole-match Swift regex), `UpdateRelease` (asset name and notes URL built from the validated version), `UpdateCheck`, `UpdateFeed` (repo, team ID, size caps, `latestURL`, `assetName`, exact-host `isAllowedDownload`, `parse`), `UpdateStatus`.
- **Mac**: `GitHubReleaseClient` sends GET with `Accept: application/vnd.github+json` and `User-Agent: Transom/<version>` only. 200 is parsed, 404 is `.none`, any other status throws `HTTPStatusError`. `UpdateController` handles one check at a time: checking, then available or current. `.none` and `.notInstallable` read as current and are logged. A thrown error restores the previous status. Logs use category `update`, with only versions and status codes `.public`. `isEnabled(bundleID:version:)` returns true only for `com.eightabyte.transom` with a version, and hits a `precondition` on a malformed Release version.
- **UI**: `UpdateCopy` and `UpdatesTab`. The tab shows the version line and a status line with a spinner or green check, carrying the `.updatesFrequently` live-region trait. A Release Notes link appears when an update is available. Check for Updates is disabled while a check runs or when the updater is off. `TransomMacApp` builds one controller from `Bundle.main`, and `StatusItemController` takes `updates:` and registers the `.updates` tab.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | Tracer: checkNow() against a stub releases/latest | 523d9b0 |
| 2 | Updates tab wired to the app's one UpdateController (TDD) | cf5a4bd (RED), fc443f3 (GREEN) |

## Verification

- `.build/09-11-t1.log`: the 3 tracer tests passed. `scripts/check-no-appkit.sh`: OK. The tracer gate re-ran `<verify>` end to end and it passed before expansion.
- `.build/09-11-t2.log`: 5 tests in UpdateCheckTests passed, including `theVersionLineAndStatusLinesAreTheUISpecCopy` and `theUpdaterIsOffOutsideAReleaseBundle`.
- `.build/09-11-full.log`: four passed "Test run with" lines (271 / 526 / 124 / 1303) with no ✘. no-appkit: OK (67 files).
- Acceptance greps: `universal.dmg` 1, `urlCache = nil` 1, `Authorization` in the client 0, `.updates:` 1, `UpdateController(` 1.

## TDD Gate Compliance

Task 2: RED commit cf5a4bd. The tests failed to compile because `UpdateCopy` was missing and `isEnabled(bundleID:version:)` was undefined. GREEN commit fc443f3 made all 5 pass. No refactor was needed.

## Deviations from Plan

None that change behaviour. These small additions are within the plan's intent:
- **[Rule 2] Disabled controller sends nothing.** `checkNow()` returns early when `isEnabled` is false (T-09-19), and `theUpdaterIsOffOutsideAReleaseBundle` asserts that no request is made.
- **[Rule 2] Port rejected in the allow-list.** This mirrors gifsmith, where `u.Host` includes the port, so `github.com:443` never matched.

## Known Stubs

None. 09-12 to 09-17 add the automatic toggle, error copy, ETag, Download and Open, and the menu dot, as planned.

## Threat Flags

None beyond the plan's register: one outbound unauthenticated GET to api.github.com, which T-09-18 covers.

## Self-Check: PASSED

- All 7 created files exist. Commits 523d9b0, cf5a4bd and fc443f3 are ancestors of HEAD.
