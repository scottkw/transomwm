---
phase: 09-polish-ship
plan: 17
subsystem: shell-updates
status: complete
tags: [updater, menu-bar, report-a-problem, privacy]
requires: [09-16]
provides:
  - StatusItemController.showsDot(_:ready:), withUpdateDot(_:), updateItems(_:homebrew:) and the bottom-group update items
  - UpdateController.startAutomatic(sleep:), lastChecked, automaticTask; the automatic setter restarts or cancels the schedule
  - UpdateCopy.debugLine(status:lastChecked:) in the Debug submenu
  - ReportProblem (details, detailsBlock, body, issueURL) and the Report a Problem… menu item
affects: [09-18]
tech-stack:
  added: []
  patterns:
    - the menu reads the update status from a Combine sink on updates.$machine (fires before the change lands, like the permission sink)
    - the schedule takes an injected sleep, so tests never wait in real time
key-files:
  created:
    - Sources/TransomMac/Shell/ReportProblem.swift
    - Tests/TransomMacTests/UpdateMenuTests.swift
    - Tests/TransomMacTests/UpdateScheduleTests.swift
    - Tests/TransomMacTests/ReportProblemTests.swift
  modified:
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Updates/UpdateController.swift
    - Sources/TransomMac/Updates/UpdateCopy.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
decisions:
  - "The glyph subscribes to updates.$machine (mapped to .status), because UpdateController publishes the machine, not a status property"
  - "The report's Mission Control line is the Debug line verbatim (\"Mission Control takeover: …\"), per the UI-SPEC rule that every Details line is the Debug line where one exists"
  - "lastChecked is set after every finished check, manual or automatic, successful or not"
  - "Report a Problem reads Screen Recording with SnapshotCapture.isGranted() (a preflight, no prompt) because the user clicked, as Settings ▸ General already does"
metrics:
  duration: ~35 min
  completed: 2026-11-07
actuals:
  tokens: 8700
  tasks: 3
  commits: 6
plan_head_before: 717a24ec0e39a1538a1e15717aed26761fe9845c
plan_head_after: ce41048983e8612ee8815278286bb894dde17739
---

# Phase 9 Plan 17: Update dot, daily check and Report a Problem Summary

The menu-bar glyph gets a 6 pt template dot and an "Update to Transom {v}…" item when a newer release is known (or the brew line and copy item on a Homebrew install). Transom checks GitHub 10 s after launch and then every 24 h while automatic updates are on. Report a Problem… opens a prefilled GitHub issue built only from versions, counts and capability lines, and copies the same details.

## What was built

- **Task 1 (tracer), dot and update items.** `showsDot` is true for available, downloading, verifying and opened, and only when access is ready. `withUpdateDot` draws the RESEARCH composite on an 18 × 18 template canvas. `updateGlyph()` wraps the chosen image and appends ", update available" to the accessibility description and tooltip. The bottom group is now separator, update items, Settings…, Report a Problem…, Quit Transom. The DMG item opens Settings ▸ Updates and starts `downloadAndOpen()`. The Homebrew pair is a disabled "Transom {v} is available" line plus "Copy “brew upgrade --cask transom”" with the tooltip "Paste it in Terminal to update." No user notification is posted.
- **Task 2, schedule.** `startAutomatic(sleep:)` runs one loop: wait 10 s, `checkNow(manual: false)`, then wait 24 h and repeat. It runs only while `automatic` is on and the updater is enabled. The `automatic` setter cancels the loop or restarts it from the 10 s wait. `StatusItemController.init` calls it once. The ⌥ Debug submenu shows "Updates: {state}, last checked {HH:mm}" or "never".
- **Task 3, Report a Problem.** `ReportProblem.details(inventory:…)` reads only counts from the inventory: displays, open windows and distinct PIDs. The body is the exact UI-SPEC template. `issueURL` encodes with `.urlQueryAllowed` minus `+&=#`. The menu item writes `detailsBlock` to the pasteboard and opens the URL. There is no alert and no toast.

## Verification

- `.build/09-17-t1.log`: UpdateMenuTests, 5/5 passed.
- `.build/09-17-t2.log`: UpdateScheduleTests, 4/4 passed. The RED run (`.build/09-17-t2-red.log`) failed to compile because the members were missing.
- `.build/09-17-t3.log`: ReportProblemTests plus MenuCopyTests, 28 passed. The RED run (`.build/09-17-t3-red.log`) failed to compile because `ReportProblem` was missing.
- `.build/09-17-full.log`: three of the four "Test run with" lines passed. The fourth failed only on `FreezeTestTests.itResumesByItself`, the known 1 s wall-clock load flake (01-VERIFICATION, 07-12, 07-REVIEW-FIX). It failed in both full runs and in a run with this plan's suites skipped (`.build/09-17-skip.log`), and it passed 4/4 when run alone. `scripts/check-no-appkit.sh` printed `no-appkit: OK (68 files)`.
- Acceptance greps: `withUpdateDot` 2, `updateAvailableSuffix` 1, `startAutomatic` 1 in StatusItemController, `Updates: ` 1 in UpdateCopy, `issues/new` 1 and `titleHint` 0 in ReportProblem.swift.

## TDD Gate Compliance

- Task 2: RED `009af00` (test), then GREEN `367b9ea` (feat).
- Task 3: RED `4c580bf` (test), then GREEN `ce41048` (feat).
- Both RED runs failed to compile because the API under test did not exist yet (missing members), not because of a typo.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Subscription source is `updates.$machine`, not `updates.$status`**
- **Found during:** Task 1
- **Issue:** `UpdateController` publishes `machine`, and `status` is a computed property, so `updates.$status` does not exist. The plan's key_link pattern `updates.\$status` therefore will not match.
- **Fix:** `updates.$machine.map(\.status).removeDuplicates()`, with the emitted value cached in `updateStatus`, as the permission sink does.
- **Commit:** 203c1f2

**2. [Rule 1 - Spec conflict] Mission Control Details line**
- **Found during:** Task 3
- **Issue:** The UI-SPEC template writes "Mission Control keys: {takeoverLine value}", but the same section says each Details line is the Debug line verbatim, and `OverviewCopy.takeoverLine` already returns "Mission Control takeover: …".
- **Fix:** The report uses the Debug line verbatim, and `theBodyIsTheUISpecTemplate` pins it. When there is no takeover object the line reads `.unavailable`.
- **Commit:** ce41048

### Notes

- Commit `5273efd` (docs(09): D-22) landed on the branch during this plan from another session. It is not part of this plan, but `git rev-list` counts it, so the measured `commits: 6` includes it. This plan made 5 commits.
- `FreezeTestTests.itResumesByItself` is out of scope and was not changed (see Verification).

## Known Stubs

None.

## Threat Flags

None. The new surfaces (the issue URL and the pasteboard write) are T-09-36 and T-09-37 in the plan's register, and both are mitigated and tested.

## Backstop checks (not automatable here)

- Check on a real menu bar (light, dark, tinted and a 1x display) that the dot reads clearly and does not merge with the fanlight.
- Click Report a Problem… once in a VM and confirm that the browser opens the issue form with the body and the clipboard holds the Details block.

## Self-Check: PASSED

- Files: ReportProblem.swift, UpdateMenuTests.swift, UpdateScheduleTests.swift and ReportProblemTests.swift all exist.
- Commits: 203c1f2, 009af00, 367b9ea, 4c580bf and ce41048 are all ancestors of HEAD.
