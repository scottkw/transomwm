---
phase: 04-zoom-camera
fixed_at: 2026-10-28T17:39:25Z
review_path: .planning/phases/04-zoom-camera/04-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 4: Code Review Fix Report

**Fixed at:** 2026-10-28T17:39:25Z
**Source review:** .planning/phases/04-zoom-camera/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (2 critical, 6 warning; Info excluded by `critical_warning` scope)
- Fixed: 8
- Skipped: 0

Work ran in the main checkout on branch `gsd/phase-01-layout-model`, with no worktree, as instructed. Each fix is one `fix(04): ...` commit.

## Verification

- **Where:** main checkout `/Users/ken/dev/transomwm`, headless only. No `TRANSOM_LIVE` run, and no window opened on the host.
- **Critical regression tests** (Swift Testing + FakeWindowSystem). Each one was run before its fix and failed for the reason the review gives, then passed after the fix:
  - CR-01: `ArrangerCameraTests.restoreAllBringsACollapsedWindowBackOnScreen`. A collapsed window's minimum is learned from a refused write in the fake, then Restore All runs.
  - CR-02: `ArrangerCameraTests.turningZoomOffWhilePausedLeavesNoWindowParked(zoomedIn:)`, with two cases: collapsed at home, and zoomed in with a camera-parked window.
- **Warning regression tests:** WR-05 `aMoveOnADisplayThatWentAwayIsForgotten`; WR-01 `aWindowThatFitsAgainIsNoLongerCollapsible` and `aCollapsedWindowThatFloatsIsNoLongerCollapsible`. All failed before their fixes and pass after.
- **Full headless `swift test` at the end:** 1165 Swift Testing tests, 0 failures (193 + 261 + 49 + 662 across the four test products). XCTest executed 0, since its live tests are gated. The known `FreezeTestTests.itResumesByItself` flake did not show up.
- **Filtered runs:** every `--filter` run executed a non-zero number of tests.
- **Architecture:** TransomEngine still has no AppKit import (the `check-no-appkit` test passes). ScreenCaptureKit is still used only in `SnapshotCapture.swift` (`NoScreenCaptureTests` passes).

## Fixed Issues

### CR-01: Restore All Windows parks collapsed windows again

**Files modified:** `Sources/TransomEngine/Arranger+Commands.swift`, `Tests/TransomEngineTests/ArrangerCameraTests.swift`
**Commit:** a8ccdd1
**Applied fix:** `restoreAll()` clears `camera.collapsible` before the rescue and replan, and appends `showBlocks([:])`. A rescued collapsed window now stays on screen and floats with N1, the same rule as zoom off, and its block is hidden even while paused. N6 counts it once. This applies the review's first option, which matches CONTEXT D and UI-SPEC ("Parked windows return ... via Restore All Windows").

### CR-02: Turn Off Zoom while paused leaves parked windows off screen

**Files modified:** `Sources/TransomEngine/Arranger+Camera.swift`, `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/ArrangerCameraTests.swift`
**Commit:** ce7867a
**Applied fix:** `setZoomEnabled(false)` runs `rescueStranded` when arranging is paused, for any reason or the session pause, before the replan. `rescueStranded` gained a `sparing:` set. Floating windows of a hidden Desktop tile are spared, because they are parked by Phase 3's rule, not by the camera. On Resume, the rescued windows are tiled, or floated with N1. I chose the rescue option because the "refuse while paused" option would contradict UI-SPEC Surface 6, which keeps Z11 "Turn Off Zoom" enabled while paused.

### WR-01: `camera.collapsible` membership is sticky

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/ArrangerCollapseTests.swift`
**Commit:** 330cc67
**Status:** fixed: requires human verification (logic change)
**Applied fix:** With zoom on, `planShown` also plans each shown desk's home view (the view plan is reused when the view is already home). At the end, `planShown` drops from the set every window that gets a home frame, and every window no longer in any tree because it floated or closed. Windows on desks that are not shown keep their membership. Nothing is pruned while paused, because `planShown` returns early. The cost is one extra `ViewPlanner` pass per zoomed display per replan.

### WR-02: Pick mode takes Esc from every app until the next click

**Files modified:** `Sources/TransomMac/ArrangeController.swift`
**Commit:** b48444c
**Applied fix:** A `.windowFocused` event in the system event loop calls `zoomInput.endPick(reason: "focus changed")`. That removes the Esc hotkey, the hover monitor and the published pick tiles. This adds one exit to Surface 5's list and contradicts none of its rules. The idle-timeout idea was not implemented (see the notes at the end).

### WR-03: The first move after launch, and every move after a window opens, never has snapshots

**Files modified:** `Sources/TransomMac/Zoom/SnapshotCapture.swift`
**Commit:** cabf885
**Applied fix:** If `captureAll` is asked for a window that is missing from `scWindows`, and that window was not already missing after an earlier re-read, it re-reads `SCShareableContent` first, inside the move's own 120 ms deadline. Windows still not listed after a re-read are remembered, so a window that is never listed does not cause a re-read on every move. This runs only after the existing granted check, so zoom off still never touches ScreenCaptureKit.

### WR-04: An in-flight refresh keeps calling ScreenCaptureKit after Turn Off Zoom

**Files modified:** `Sources/TransomMac/Zoom/SnapshotCapture.swift`, `Sources/TransomMac/Zoom/ZoomController.swift`
**Commit:** 9974d42
**Applied fix:** `SnapshotCapture.purge()` is replaced by `close()`, which clears the cache and sets a `closed` flag. `refreshShareable`, `capture` and `refresh` return before any ScreenCaptureKit call (and before `touches` is incremented) once the capture is closed. A capture that finishes after the close puts nothing in the cache. `ZoomController.purge()` calls `close()`.

I used a flag rather than the suggested stored and cancelled tasks. The capture work runs in unstructured `Task`s, which do not inherit cancellation, so a cancel would not have reached them. The flag also covers the per-capture timeout tasks.

### WR-05: A move dropped by `displaysChanged` leaves engine state stuck

**Files modified:** `Sources/TransomEngine/Arranger+Camera.swift`, `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/ArrangerCameraTests.swift`
**Commit:** a05c79c
**Status:** fixed: requires human verification (state handling)
**Applied fix:** A new `forgetMoves(onDisplaysOtherThan:)` runs on every inventory. It drops the pending moves of displays that are gone, together with the `unparkedNew` windows on those moves' desks; the next plan parks those windows. `forget(_:)` also removes a closed window from `unparkedNew`.

### WR-06: Turn Off Zoom treats an older move's reveal as the home move's reveal

**Files modified:** `Sources/TransomMac/ArrangeController.swift`
**Commit:** c7de0a4
**Applied fix:** `awaitingHome` is now `[String: UInt64]`, mapping each display to the ID of its `.zoomTo(.home)` move. `revealed(_:moveID:)` counts a reveal only when the ID matches. The existing 3 s fallback still covers a home move that never reveals.

## Notes for VM UAT and follow-up

- **WR-02:** check in the VM that no stray `windowFocused` event arrives just after a zoom-out reveal. If one does, pick mode would end immediately. I could not check this headless. Typing Esc in the window that is already focused, with no click and no focus change, is still consumed once. An idle timeout would close that gap but was not added.
- **WR-03:** on the very first move, the re-read alone can use up the 120 ms budget. That move then still shows fallback tiles, and the next move gets snapshots. Confirm in the VM with Screen Recording granted.
- **WR-04, WR-06:** shell-only changes with no headless test. Both are covered by the existing zoom-off UAT pass.
- **CR-02:** desks zoomed on a Space that is not shown still return home only when that Space is next shown (the review's "softer form"). The rescue covers present windows only. Not changed.

---

_Fixed: 2026-10-28T17:39:25Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
