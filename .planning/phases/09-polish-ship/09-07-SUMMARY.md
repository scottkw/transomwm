---
phase: 09-polish-ship
plan: 07
subsystem: settings
status: complete
tags: [settings, mission-control, takeover, status-menu]
requires: [09-06]
provides:
  - "Settings ▸ Zoom & Gestures ▸ Mission Control section (\"Use the Mission Control keys for the overview\")"
  - "@Observable MissionControlTakeover (state tracked; closures, backend, store, canary, logger, keyTasks ignored)"
  - "ZoomGesturesTab.takeoverBinding / takeoverUsable / takeoverFooter; SettingsCopy.takeoverFooter(_:)"
  - "StatusItemController.chooseTakeover() handed to the tab"
affects: [StatusItemController.settingsTabs, CommandMenu.zoomSection, ArrangingTab Restore button, README]
tech-stack:
  added: []
  patterns:
    - "A Settings toggle whose write always runs the existing flow and whose value is read back from observable state"
key-files:
  created: []
  modified:
    - Sources/TransomMac/MissionControlTakeover.swift
    - Sources/TransomMac/Settings/ZoomGesturesTab.swift
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Shell/CommandMenu.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Tests/TransomMacTests/TakeoverMenuTests.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
    - README.md
decisions:
  - "The footer checks availability before zoom: with the private symbols missing it reads \"Not available on this version of macOS.\" even with zoom off"
  - "The binding ignores the requested value and always calls chooseTakeover; choose(explain:) decides on/off, so the toggle can never show on before the alert is confirmed"
metrics:
  duration: "~15 min"
  completed: 2026-11-07
actuals:
  tokens: 6200
  tasks: 2
  commits: 2
plan_head_before: d399b411426445465240fd6b01dba67176ec7d42
plan_head_after: acfcdd5dd71a7df7fcaadc81d23c80b770019930
---

# Phase 9 Plan 07: Mission Control replacement moves to Settings Summary

Replace Mission Control is now the "Use the Mission Control keys for the overview" toggle in Settings ▸ Zoom & Gestures, driven by the unchanged `choose(explain:)` + `TakeoverAlert` flow through an `@Observable` takeover; the status menu item and its "(unavailable)" form are gone.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Tracer: Settings toggle turns the takeover on only after confirming | 43ecd41 | MissionControlTakeover.swift, ZoomGesturesTab.swift, SettingsCopy.swift, StatusItemController.swift, TakeoverMenuTests.swift |
| 2 | Replace Mission Control leaves the status menu | acfcdd5 | StatusItemController.swift, CommandMenu.swift, OverviewCopy.swift, MissionControlTakeover.swift (comments), OverviewCopyTests.swift, TakeoverMenuTests.swift, README.md |

## What changed

- `MissionControlTakeover` is `@Observable`; `state` (so `isOn`) is tracked. The safety path (stored originals, read-back, canary, launch restore, T-09-11) is untouched; only the entry point moved.
- `StatusItemController.toggleTakeover()` became `private func chooseTakeover()` with the same body (still guarded by `takeoverAlert == nil`), passed to `ZoomGesturesTab` as a `[weak self]` closure along with `arrange.takeover`.
- `ZoomGesturesTab` Mission Control section: disabled when the takeover is nil or unavailable ("Not available on this version of macOS.") or zoom is off (`ZoomCopy.doubleClickFooterZoomOff`); otherwise the footer is "{OverviewCopy.takeoverAlertKeys(currentChord)} show Transom's overview instead of Mission Control. Swiping up with four fingers still opens Mission Control."
- `CommandMenu.zoomSection` lost its `takeover:` parameter; `OverviewCopy.replaceMissionControlUnavailable` and its assertion are deleted; `OverviewCopy.replaceMissionControl` stays (TakeoverAlert's button).
- Tests: `theSettingsToggleTurnsTheTakeoverOnOnlyAfterConfirming`, `theSettingsFooterNamesTheRealChord`, and `theZoomSectionHasNoMissionControlItem` (replaces `o2SitsAfterFrameFocusedWindowBeforeAllowWindowPreviews`).

## Orchestrator note (09-04 stale Restore button)

Resolved as a side effect: `ConflictController.canRestore` reads `takeover?.isOn`, and with the takeover now `@Observable`, the Arranging tab's body tracks `takeover.state`, so "Restore macOS Window Settings" refreshes when only the takeover changes. Residual: the `storedOriginals` term reads UserDefaults and is not tracked; it changes alongside `state` in apply/lift, and its retry path runs inside `conflicts.restore()`, so no stale case is known. No dedicated test was added for the Arranging button.

## Verification

- `.build/09-07-t1.log`: TakeoverMenuTests, 13 tests passed, both named tests passed.
- `.build/09-07-t2.log`: TakeoverMenuTests|OverviewCopyTests|CommandMenuTests, 51 tests passed, `theZoomSectionHasNoMissionControlItem` passed.
- `.build/09-07-full.log`: four passed "Test run with" lines (271, 503, 124, 1303), no ✘; `scripts/check-no-appkit.sh` → no-appkit: OK (65 files).
- Acceptance greps: `@Observable` in takeover = 1; `chooseTakeover` in StatusItemController = 4 after Task 1; `replaceMissionControlUnavailable` = 0; `takeoverMenuItem` = 0; `replaceMissionControl` in TakeoverAlert.swift = 1.

## Deviations from Plan

**1. [Rule 2 - Correctness] README still said to turn it on "from the menu"**
- **Found during:** Task 2
- **Fix:** README line 59 now points to Settings ▸ Zoom & Gestures.
- **Commit:** acfcdd5

**2. [Rule 1 - Stale docs] Doc comments in MissionControlTakeover referred to the O2 menu item**
- **Fix:** Five comments now name the Settings toggle. No code change.
- **Commit:** acfcdd5

Test detail: observation callbacks arrive in a `@Sendable` closure, so the test file has its own `private final class Count` (the same pattern as SettingsModelTests).

## Known Stubs

None.

## Self-Check: PASSED

- Commits 43ecd41 and acfcdd5 are ancestors of HEAD; all modified files exist.
