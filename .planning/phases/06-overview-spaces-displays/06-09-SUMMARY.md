---
phase: 06-overview-spaces-displays
plan: 09
subsystem: overview
status: complete
tags: [overview, camera, interruptions, live-updates, reduce-motion, voiceover, debug, over-01]
requires:
  - phase: 06-08
    provides: "OverviewSelection, key panel, same-Space picks, windowClosed reselect, dispatchAppKitEvents"
  - phase: 04-zoom-camera
    provides: "zoomTo(target, displayUUID:, focus:), offerExplainer, postAnnouncement"
provides:
  - "Parked or collapsed window pick: the overview closes, then the camera frames its leaf and focuses it at settle; paused, focus only"
  - "Arranger.isParked(_:) (engine, public)"
  - "OverviewController.interrupt(reason: OverviewCopy.Interruption), logged \"interrupted: {reason}\""
  - "OverviewController.windowsChanged(): tiles fade in and out (120 ms) while open; StagePanel.fadeTiles; OverviewLayout(laidOut:)"
  - "GestureTapState.DisarmReason.overviewOpen, logged \"overview open\""
  - "Overview announcements (opened, selection with a 150 ms rate limit, closed) and OverviewCopy announcement strings"
  - "ZoomController.offerExplainerAfterOverview()"
  - "ArrangeController.lastOverview and the Debug S6 line"
affects: [06-10, 06-11, 06-12]
tech-stack:
  added: []
  patterns:
    - "Throttle, not debounce, for VoiceOver: the first item in a burst starts a 150 ms slot, and only the latest text is posted when the slot ends"
    - "A camera move after an overview pick waits out the overview's close (reverse + fade) so the two stage panels never overlap"
key-files:
  created: []
  modified:
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/OverviewLayout.swift
    - Sources/TransomMac/Overview/OverviewController.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/GestureController.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Input/GestureTapRules.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/transom-gesture-spike/main.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
    - Tests/TransomMacTests/GestureControllerTests.swift
    - Tests/TransomMacIntegrationTests/OverviewIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/OverviewKeyboardIntegrationTests.swift
key-decisions:
  - "App-switch interruption moved from .windowFocused to NSWorkspace didActivateApplication. ⌘-Tab sends no focused-window change (G-04-12), and a focus change inside the frontmost app (a window opening while the overview is open) must fade a tile in, not close the overview"
  - "A parked pick frames leafNode(of:) via Navigator.target, so a parked Desktop floater frames the Desktop tile. Frame Focused Window's toggle-back is not used"
  - "Live updates rebuild the layout from the Arranger and diff tiles per display. The strip and the empty capsule are not rebuilt (a shortcut: comment in windowsChanged)"
  - "Live updates also run on .liveWindowsChanged, so a window that wasn't in the CG on-screen list yet at .windowCreated still gets its tile"
  - "The initial selection is not announced (\"Overview, {n} windows\" is). Picks say nothing extra (dismiss(announce: false))"
  - "lastOverview is kept on ArrangeController so Debug S6 survives zoom off, which drops the OverviewController"
requirements-completed: [OVER-01]
duration: ~14min
completed: 2026-10-31
metrics:
  duration: "~14 min"
  started: 2026-10-31T20:45:34Z
  completed: 2026-10-31T20:59:00Z
actuals:
  tokens: 13600
  tasks: 3
  commits: 5
plan_head_before: 0a79c9c5ef16ad1f0e4b66cdb1fe0538e4508a53
plan_head_after: c81e2e30e17a5afd57a3b8cb298a3bb5cfa82864
---

# Phase 6 Plan 09: Finishing the Overview Summary

The overview is now finished. Picking a parked or collapsed window brings it into view with the Phase 4 camera and focuses it. The overview gets out of the way at once for commands, the status menu, Space and display changes, sleep and app switches. While open it adds and removes tiles as windows open and close, and it disarms gestures. It honours Reduce Motion, speaks to VoiceOver without building a backlog, offers the Screen Recording explainer only after it closes, and reports its last open in Debug S6.

## What was built

- **Parked picks (Task 1, tracer).** On a zoomed-in display, picking a tile whose window is collapsed or camera-parked (`Arranger.isParked`) logs `pick window {id} on space {sid} (camera move)`. The overview closes the same way as a same-Space pick. After the close (370 ms, or 250 ms with Reduce Motion), `frameWindow` zooms to `Navigator.target(leaf)` with focus at settle. While arranging is paused, the pick only focuses.
- **Refusals.** Not ready: a beep plus "Transom needs Accessibility access" (`OverviewCopy.refusedNotReady`). Every display full screen: a beep plus `refusedFullScreen` (renamed from `fullScreenRefusal`). Zoom off logs `refused overview: zoom off`. A URL gets log lines only.
- **Interruptions.** `interrupt(reason:)` takes an `OverviewCopy.Interruption`: command, menu, space change, display change, sleep or app switch. The stage fades out over 120 ms with no reverse animation. Each source and where it is wired:
  - command: ArrangeController's `dispatch`
  - menu: StatusItemController's `menuWillOpen`
  - space change: the `.spaceChanged` event
  - display change: `onDisplaysSettling` and `displaysChanged`
  - sleep: `.sessionPaused(true)`
  - app switch: NSWorkspace app activation

  The pick's switch-away fade logs `dismiss: pick`.
- **While open.** `.windowCreated`, `.liveWindowsChanged` and `.windowDestroyed` call `windowsChanged()`. It rebuilds the layout and fades new tiles in and gone tiles out over 120 ms (`StagePanel.fadeTiles`), keeping `shown` in layout order for `markSelection`. Opening the overview now calls `zoomInput.reset`, which ends pick mode and any rubber band. Gestures disarm with `.overviewOpen` ("overview open") and are re-published on open and close.
- **Reduce Motion.** Read at each open and passed to `animate(crossfade:)`. Dismiss and same-Space picks fade over 250 ms. Interruptions and switch-away picks fade over 120 ms in both modes (UI-SPEC "Same").
- **Announcements.** On open: "Overview, {n} windows" / "1 window" / "no windows", plus " on {d} displays" with several displays. Selection moves are announced in the UI-SPEC wording for tiles, mini tiles, thumbnails and full-screen thumbnails, with the display name in front when Tab changes display. Only the latest one per 150 ms is posted. Dismiss announces "Overview closed".
- **Explainer and Debug.** 370 ms after any close, if the overview isn't open again, `offerExplainerAfterOverview()` runs. It is the Phase 4 `offerExplainer`, which already checks `granted == false` and the shown-once key. The open log line and `onOpened` measure from the trigger to the end of the open animation. Debug S6 reads "Last overview: none yet" or "Last overview: {ms} ms to open, {n} windows, {s} snapshots", with branches for 1 window and 1 snapshot. It sits after S4 until 06-11 adds S5.

## Verification

- VM (macOS guest, `scripts/vm-live-test.sh`, one suite per run, each output has a "Test run with N tests ... passed" line):
  - `OverviewIntegrationTests`: 3 tests pass.
    - `pickParkedWindowFramesItsLeaf`: window 1, parked, fills the framed view and becomes frontmost.
    - `windowsOpeningAndClosingWhileOpenUpdateTheTiles`: 2 → 3 → 2 tiles, and the overview stays open throughout.
    - `overviewOpensPerDisplayAndCloses`: now also checks that Debug S6 recorded the open (windows ≥ 2, ms ≥ 250).
  - Tracer gate: Task 1's verify ran again before expanding, and passed.
  - Regressions: `OverviewKeyboardIntegrationTests` (1 test) and `OverviewSpaceSwitchIntegrationTests` (2 tests) pass.
- Host: `swift test --filter 'GestureControllerTests|OverviewCopyTests|ZoomOffTests'` passes 18 tests. `TransomEngineTests|OverviewCopyTests|GestureControllerTests|GestureTapRulesTests|ZoomOffTests` passes 789 + 46 tests, with no ✘. `swift build` and `scripts/check-no-appkit.sh` pass.
- Acceptance greps:
  - "camera move" appears in OverviewController.
  - `pickParkedWindowFramesItsLeaf` appears 1 time.
  - The full-screen refusal string appears 1 time.
  - `interrupt(reason:` appears 5 times in ArrangeController.
  - `.menu` appears 1 time in StatusItemController.
  - `accessibilityDisplayShouldReduceMotion` appears 3 times.
  - `offerExplainerAfterOverview` appears 2 times.
  - `(s)` appears 0 times.

## TDD Gate Compliance

- Task 2: RED commit 7d66fcf (10 assertion failures over 15 tests, using signature-only stubs as in 06-08), then GREEN commit 296d34c.
- Task 3: RED commit 0c82789 (24 failing test lines, 20 issues), then GREEN commit c81e2e3.
- No separate refactor commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The app-switch interruption sat on the wrong event.**
- **Found during:** Task 2.
- **Issue:** 06-06 interrupted on any `.windowFocused`. ⌘-Tab sends no focused-window change (the G-04-12 note on the activation observer), so a real app switch could leave the overview open. A window opening inside the frontmost app takes focus, so the new must-have, "a new window's tile fades in", could never be seen.
- **Fix:** interrupt with `.appSwitch` from the NSWorkspace activation observer for any app other than Transom. `.windowFocused` now only ends pick mode, as before.
- **Files:** ArrangeController.swift. **Commit:** 296d34c

**2. [Rule 2 - Missing] The live-update path had no live test.**
- **Issue:** Task 2 had no VM check for tiles fading in and out while the overview is open.
- **Fix:** added `windowsOpeningAndClosingWhileOpenUpdateTheTiles`. Also wired `.liveWindowsChanged`, so a window missing from the CG on-screen list at creation still gets its tile.
- **Commit:** 296d34c

**3. [Rule 3 - Blocking] The new disarm reason broke an exhaustive switch.**
- **Issue:** adding the `DisarmReason` case broke the exhaustive `passText` switch in the gesture spike.
- **Fix:** added an "overview open" case there.
- **Commit:** 7d66fcf

### Interpretation notes (from the 06-08 handoff)

- "Cancel keys and hover monitor" in `interrupt` means `releaseKeys()` in `close()`. It already runs on every path, and the hover is a tracking area.
- The plan's `disarmReason(... busy: true)` sketch would have logged "rect zoom or drag in progress". A separate `overviewOpen:` parameter and case gives the required "overview open" log text.
- "Parked tiles slide in from the display edge" (the open motion row) was not in this plan's tasks and is not done. Parked tiles still move from their parked sliver frames.

## Notes for later plans

- **06-10:** check in the VM whether a Carbon hotkey (⌃⌥⌘A, F3) fires while the overview panel is key. This is carried over from 06-08 and still untested.
- **06-11:** put S5 between the S4 and S6 lines in `StatusItemController` (see the comment there).
- **06-12 UAT (human-check):**
  - Reduce Motion crossfades on open and close.
  - VoiceOver reads arrows, Tab and display names.
  - The explainer appears only after the first overview closes without Screen Recording.
  - The status menu opening closes the overview.
  - ⌘-Tab while the overview is open closes it.

## Known Stubs

None.

## Threat Flags

None. T-06-24 is mitigated: every interruption source closes the overview in 120 ms through the one `close()`. T-06-25 is mitigated: the new log lines carry counts, IDs and reasons only, and titles appear only in VoiceOver announcements.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Overview/OverviewController.swift, Sources/TransomMac/Shell/OverviewCopy.swift, Tests/TransomMacIntegrationTests/OverviewIntegrationTests.swift
- FOUND commits: bbf54c3, 7d66fcf, 296d34c, 0c82789, c81e2e3 (5 = `git rev-list --count 0a79c9c..HEAD`)
