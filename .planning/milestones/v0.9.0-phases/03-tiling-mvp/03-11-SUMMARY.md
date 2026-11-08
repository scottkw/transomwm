---
phase: 03-tiling-mvp
plan: 11
subsystem: drag-to-dock
status: complete
tags: [swift, paneEngine, paneMac, appkit, cgeventtap, coreanimation, drag, overlay, tdd, tracer]

requires:
  - phase: 03-tiling-mvp
    provides: "DropZones.target / applyDrop, Planner.plan / clamp, LayoutTree.swap, World.edit / reflow, the Arranger with .wake/.tick (03-06) and pause reasons (03-10), Toast's panel recipe (03-06), CGWindowList"
provides:
  - "PaneEngine Modifiers, PointerEvent, PreviewState, DragSession (3 pt travel, move vs resize, ±2 pt echo rule, 150 ms dwell, one dry run per held hover)"
  - "ArrangerInput.pointer / .dragFrame; ArrangerEffect.preview / .pollDragFrame / .flashBlocked; Arranger.drag and Arranger.isDragging (plan 16 defers alerts while true)"
  - "The whole UI-SPEC Surface 2 state matrix in the Arranger: dock, blocked, ⌘ swap, snap-back ghost, clamp ghost, ⇧ bypass (undock, hidden-Desktop refusal, too-big blocked), the miss rules, keyboard Dock flash"
  - "PaneMac InputTap (one active session tap on its own thread and CFRunLoop, watchdogTick), DragFramePoller (60 Hz CG bounds), PreviewStyle (pure overlay recipe), PreviewPresenter (per-display click-through panels)"
  - "ArrangeController.startTap / stopTap / accessChanged(ready:) / isTapRunning, the 2 s watchdog; PaneMacApp starts the tap after tracking and stops it when access leaves .ready"
  - "CGWindowList.onScreenFrontToBack; MenuCopy.tapRunning / tapOff / tapItem(running:) and the Debug tap line"
affects: [03-12, 03-13, 03-16, 03-17, drag, overlays, gap-handles, alerts]

estimate:
  tokens: 120000
  tasks: 3
actuals:
  tokens: 44700
  tasks: 3
  commits: 7
plan_head_before: 670c242ab79de3e63ed082e9280d4ced8f507cd2
plan_head_after: 4bc8d426efb0e198918890b9d3351f711e880960

tech-stack:
  added: []
  patterns:
    - "Drag decisions are pure: the Arranger reduces each pointer sample to a Hover (display, normalised target, swap partner, effective modifiers, crosses-a-tile); only a Hover change restarts the dwell, and the dry run runs once per held Hover"
    - "WYSIWYG release: mouse-up applies the decision made at the dwell end (whose preview went out at the same moment); without one, the miss rules"
    - "The pressed window is skipped in replan's write loop and in moved()/rehome while the button is down, so nothing writes or corrects it before mouse-up"
    - "Desk plans a drag hit-tests against are cached per drag and dropped whenever the World changes"
    - "One makePort helper is the only CGEvent.tapCreate, shared by the real tap and the watchdog's trial tap"

key-files:
  created:
    - Sources/PaneEngine/DragSession.swift
    - Sources/PaneMac/Input/InputTap.swift
    - Sources/PaneMac/Input/DragFramePoller.swift
    - Sources/PaneMac/Overlay/PreviewPanel.swift
    - Sources/PaneMac/Overlay/PreviewStyle.swift
    - Tests/PaneEngineTests/DragSessionTests.swift
    - Tests/PaneEngineTests/ArrangerDragTests.swift
    - Tests/PaneMacTests/PreviewStyleTests.swift
    - Tests/PaneMacIntegrationTests/InputTapIntegrationTests.swift
    - Tests/PaneMacIntegrationTests/TitleBarDragIntegrationTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-11-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-11-task2-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-11-task3-red.json
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/CGWindowList.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift
    - Tests/PaneMacTests/MenuCopyTests.swift

key-decisions:
  - "A drag session starts at mouse-down on a tracked, dockable, present, non-excluded window (not parked, not paused); it becomes a move once the pointer has travelled 3 pt and a frame report shows the origin changed with the size unchanged; the first verdict sticks"
  - "The frame poll starts at the first 3 pt of travel (not at every click) and stops on mouse-up; the poller also stops itself once the left button is up"
  - "A hover change withdraws the shown preview at once (.preview(nil)) and restarts the dwell; morphs therefore only happen within one state (the clamp ghost follows the window frame without easing)"
  - "⇧ ignores the target; ⌘ swaps only with another docked panel of the same desk, from any part of its tile (tab groups and the Desktop fall through to the no-modifier row); a docked window over its own tile or any tile centre is a miss"
  - "A ⇧-undock or floating miss clamps into the Desktop rect only when the release frame crosses a docked tile, so a window partly off screen stays where it was released"
  - "A cross-display dock leaves its old desk through World.reflow (no undo step there) and is one World.edit on the target desk, as the Finder split does"
  - "The app starts the tap after tracking starts (not ArrangeController.start), so live tests that only arrange never install an active tap"
  - "At .cgSessionEventTap the window-under-pointer field arrived as 0 in the fixture spike; the press window then comes from the topmost on-screen tracked window under the point (CGWindowList.onScreenFrontToBack, since optionAll order is not front-to-back)"
  - "The tap callback re-enables on tapDisabledByUserInput too, which macOS also sends for Pane's own tapEnable(false); stop() therefore invalidates the port rather than relying on disable"

patterns-established:
  - "Drag-related effects (preview, poll, flash) are plain values the shell maps to AppKit; the engine never sees a panel"

requirements-completed: [TILE-01, TILE-02]

coverage:
  - id: D1
    description: "A title-bar drag held 150 ms over a drop zone shows the exact dry-run frame and docks there on release; a release inside the dwell is a plain move; the dragged window is never written before mouse-up"
    requirement: TILE-01
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerDragTests.swift#aFloatingWindowHeldInTheLeftEdgeBandDocksAtThePreviewedFrame"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerDragTests.swift#aReleaseInsideTheDwellIsAPlainMove"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/DragSessionTests.swift"
        status: pass
    human_judgment: true
    rationale: "Task 1 human-check (A1, A16) with a real TextEdit drag in Pane Debug is end-of-phase UAT; a fixture spike (TitleBarDragIntegrationTests, opt-in) already showed the tap sees a native title-bar drag in top-left points"
  - id: D2
    description: "The Surface 2 state matrix: blocked, ⌘ swap, ⌘ ignored when floating, snap-back from own tile / centre / gap / nowhere, plain move, clamp ghost, ⇧ undock, ⇧ with the Desktop hidden, ⇧ too big, ⇧ mid-drag, no session when excluded / never-dock / paused, keyboard Dock flash, lost mouse-up"
    requirement: TILE-02
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerDragTests.swift (16 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Preview recipe per state, Increase Contrast and label clearance"
    requirement: TILE-10
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/PreviewStyleTests.swift"
        status: pass
    human_judgment: true
    rationale: "Panel styling, dark mode, accent, Increase Contrast, Reduce Motion, capture exclusion and never activating Pane are Task 2's human-check (end-of-phase UAT)"
  - id: D4
    description: "The tap runs on its own thread, a watchdog tick re-enables it, losing access stops it at once and regaining access restarts it; Debug shows the tap line"
    verification:
      - kind: integration
        ref: "caffeinate -d -i swift test --filter InputTapIntegrationTests (3 tests, trusted)"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/MenuCopyTests.swift#theDebugTapLineNamesTheTapState"
        status: pass
    human_judgment: true
    rationale: "Revoking Accessibility in System Settings while Pane Debug runs (clicks keep working within 2 s) is Task 3's human-check"

duration: 26 min
completed: 2026-10-26
---

# Phase 3 Plan 11: Drag to Dock Summary

**Title-bar drags dock windows at exactly the frame a 150 ms hover previews, through one active session tap on its own run loop, with the full ⇧ bypass / ⌘ swap / blocked / snap-back / clamp state matrix and a watchdog that drops the tap the moment Accessibility goes.**

## Performance

- **Duration:** 26 min (2026-10-26T04:32:56Z to 04:58:38Z)
- **Tasks:** 3 (Task 1 a tracer), plus one fix
- **Files:** 21 changed (10 created source/test files, 3 RED records, 8 modified)

## Accomplishments

- **Drag sessions (PaneEngine).** `DragSession` classifies a press: 3 pt of travel, then an origin change with the same size is a move, a size change an edge resize (left to plan 13), and a frame within 2 pt of Pane's last read-back is an echo. The Arranger reduces each pointer sample to a `Hover`. A change restarts the 150 ms dwell (a `.wake`). At the dwell end it runs one dry run (`dropping` = take the window off its desk, `applyDrop`, plan) and emits `.preview`. Mouse-up applies that decision exactly, or the miss rules when there is none.
- **The state matrix.** Dock when it fits. Blocked at the minimum-free frame, refused with "Not enough room to dock here". ⌘ swap of two docked panels, announced "Swapped". ⌘ is ignored for floating windows. A docked window snaps back from its own tile, a centre, a gap or outside every zone. A floating window gets a plain move, or the clamp ghost that follows its frame while it would cross a tile. ⇧ undocks at the release frame. ⇧ with the Desktop hidden shows the labelled snap-back and announces "Show the Desktop Tile to float windows". ⇧ for a window that can't fit the Desktop shows blocked over the Desktop rect. A refused keyboard Dock also emits `.flashBlocked`.
- **No fighting the user.** The pressed window is skipped by replan's writes, by `moved()` corrections and by `rehome` until mouse-up. 03-06's once-a-second pull-back of a dragged docked window is gone.
- **InputTap.** One `.defaultTap` session tap watches left down, dragged and up, plus flagsChanged. It runs on a dedicated thread with its own CFRunLoop. The callback copies type, location, flags and the window field, then returns. It re-enables after `tapDisabledByTimeout` and `tapDisabledByUserInput`.
- **Watchdog.** It runs every 2 s and on app activation. It re-enables a disabled tap. A refused trial tap invalidates Pane's tap at once. Losing `.ready` stops the tap, and coming back restarts it. Debug ▸ shows "Event tap: running" or "Event tap: off, drags not detected".
- **Preview panels.** There is one `[.borderless, .nonactivatingPanel]` panel per display: click-through, never key or main, floating level, every Space, `sharingType = .none`, not an accessibility element. `PreviewStyle` holds the recipe as values. The panel re-resolves semantic colours on appearance and accent changes. It fades and morphs per the UI-SPEC table, with no morph under Reduce Motion, and does the 600 ms keyboard flash.

## Task Commits

1. **Task 1 (tracer): dock at the previewed frame**: `19aa106` (test, RED), `a784db9` (feat, GREEN)
2. **Task 2: the drop state matrix and the preview panel**: `ba32510` (test, RED), `e8f6ea2` (feat, GREEN)
3. **Task 3: tap watchdog, access teardown, Debug tap line**: `081b10e` (test, RED), `fee2626` (feat, GREEN)
4. **Fix: lost mouse-up**: `4bc8d42` (fix, test and code together)

## TDD Gate Compliance

| Task | RED | Evidence | GREEN |
|------|-----|----------|-------|
| 1 | `19aa106` | `tdd/03-11-task1-red.json` RED_EVIDENCE_OK (target `aFloatingWindowHeldInTheLeftEdgeBandDocksAtThePreviewedFrame()`). The stub Arranger ignored pointer input. The click test and two nil-kind DragSession tests passed as expected. | `a784db9` |
| 2 | `ba32510` | `tdd/03-11-task2-red.json` RED_EVIDENCE_OK (target `commandOverAnotherDockedTileSwapsTheTwoWindows()`). Every new matrix row failed on its preview, announcement or edit assertion with sound preconditions. Rows Task 1 already covers passed. | `e8f6ea2` |
| 3 | `081b10e` | `tdd/03-11-task3-red.json` RED_EVIDENCE_OK (target `oneWatchdogTickReenablesADisabledTap()`, live and trusted). The access test failed on the tap still running. | `fee2626` |

The fix commit `4bc8d42` was written test-first: the new test failed on its assertion before the code. It was committed as one `fix` commit.

## Verification

- `swift test --filter "DragSessionTests|ArrangerDragTests"`: 9 tests passed (Task 1). After Task 2 and the fix, `ArrangerDragTests|DragSessionTests|PreviewStyleTests`: 22 + 7 passed.
- `caffeinate -d -i swift test --filter InputTapIntegrationTests`: 1 test passed after Task 1, 3 after Task 3. Trusted, not skipped.
- **Tracer gate (A1, A16):** `PANE_LIVE_DRAG=1 caffeinate -d -i swift test --filter TitleBarDragIntegrationTests` passed on its third run. This is a bounded synthetic drag on the fixture's own title bar with the cursor restored. The tap saw the down, at least 5 drags and the up, at the posted top-left points. The fixture moved natively. Run 1 posted nothing: its z-order guard used the `optionAll` list. Run 2 showed the window field is 0 at the session tap and that AppKit keeps about 10 pt as its drag threshold; the expectations were adjusted. Logged: ⚡ Tracer verified end-to-end — expanding.
- Non-live suites: PaneModelTests 190, PaneEngineTests 346, PaneMacTests 146, all passing.
- Live batch (Mac unlocked, caffeinated): `ArrangeIntegrationTests|InputTapIntegrationTests` with the known `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` skipped. 3 arrange tests passed, fullscreen was skipped (opt-in) and the 3 tap tests passed after the watchdog test fix below. No fixtures were left over.
- `scripts/build-debug.sh` exit 0 (signed, designated requirement satisfied). `scripts/check-no-appkit.sh` exit 0.
- Acceptance greps: `options: .defaultTap` = 1; `keyDown` = 0; `CFRunLoopRun` = 1; `AXUIElement` = 0; `CFMachPortInvalidate` = 2; `nonactivatingPanel`, `sharingType = .none` and `ignoresMouseEvents = true` = 1 each; no hex colour literals; "Event tap: off, drags not detected" in MenuCopy = 1.
- The full live suite was not run at once (project live-test rules), as in 03-10.

## Decisions Made

See `key-decisions` in the frontmatter. In short: one decision per held hover, applied exactly on release. The pressed window is untouchable until mouse-up. ⇧ ignores the target, and ⌘ only swaps docked panels. Clamping happens only when a frame crosses a tile. The app, not `ArrangeController.start()`, starts the tap.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The press-window fallback used a list that is not front to back**
- **Found during:** Task 1 (fixture spike run 1)
- **Issue:** `CGWindowList.snapshot()` reads `optionAll`, which does not promise z-order, so "topmost window under the point" could pick a window behind.
- **Fix:** added `CGWindowList.onScreenFrontToBack()` (`optionOnScreenOnly`, `excludeDesktopElements`). The fallback and the spike's safety guard use it.
- **Files:** Sources/PaneMac/CGWindowList.swift, Sources/PaneMac/ArrangeController.swift
- **Commit:** `a784db9`

**2. [Rule 3 - Blocking] The old keyboard-refusal test compared the exact effect list**
- **Found during:** Task 2
- **Issue:** `ArrangerLifecycleTests/aDockWithoutRoomIsRefusedAndChangesNothing` expected exactly `[.beep, .announce]`. The plan adds `.flashBlocked` to that refusal.
- **Fix:** the test checks the two-effect prefix and allows only `.flashBlocked` after it. ArrangerDragTests checks the flash frame.
- **Commit:** `e8f6ea2`

**3. [Rule 1 - Bug] Racy precondition in the watchdog live test**
- **Found during:** Task 3 (bounded live batch, run concurrently with ArrangeIntegrationTests)
- **Issue:** `tapEnable(false)` makes macOS send `tapDisabledByUserInput`, and the callback re-enables on it (as specified). Under load, "the tap is disabled" had already flipped back before the check.
- **Fix:** the test no longer asserts the disabled state. It still requires the tap to be enabled after one `watchdogTick()`.
- **Commit:** `fee2626`

**4. [Rule 2 - Missing critical] A lost mouse-up left a docked window off its tile**
- **Found during:** self-review after Task 3
- **Issue:** a tap disabled for a moment can drop a mouse-up. The next press ended the old session silently.
- **Fix:** `abandonDrag()` applies the miss rules to the old session (snap back, or record the floating frame) and never applies its preview. Covered by a new test.
- **Commit:** `4bc8d42`

**5. [Scope] The tap starts from PaneMacApp, not `ArrangeController.start()`**
- Live ArrangeController tests would otherwise each install an active tap they never remove (live-test rule: taps must be bounded and torn down). `onTrackingStarted` now calls `start()` then `startTap()`.
- **Commit:** `fee2626`

**Total deviations:** 4 auto-fixed (2 bugs, 1 blocking, 1 missing critical) plus 1 scoping change. **Impact:** none on the plan's contract. The new `TitleBarDragIntegrationTests` (opt-in, `PANE_LIVE_DRAG=1`) is an extra live test, not a replacement for the human checks.

## Issues Encountered

- At `.cgSessionEventTap`, `mouseEventWindowUnderMousePointer` was 0 for the posted down event, so on this Mac the geometry fallback is the normal path. That costs one on-screen CG window-list read per mouse-down on main (a few ms). If UAT shows lag on clicks, resolve the press window lazily at the first 3 pt of travel instead.

## Known Stubs

None.

## Threat Flags

None. The tap, the panels and the watchdog are exactly the surfaces in the plan's threat model (T-03-28..31). No keyboard events are in the mask, the callback never logs, and the panels are excluded from capture.

## Pending Human Checks (end-of-phase UAT)

1. **Task 1 (A1, A16, about 5 min):** run Pane Debug with `log stream --predicate 'subsystem == "com.eightabyte.pane" AND category == "tap"'`. Drag a TextEdit window by its title bar to the left screen edge and hold, then release. Expect drag events during the native drag, the press resolving to TextEdit, a preview after about 150 ms, and a dock at exactly that frame. The fixture spike already confirmed the event path.
2. **Task 2:** with three docked windows and a floating one, try each zone; hold ⌘ over another tile; press ⇧ mid-drag; drag a docked window into a centre; drag Xcode (huge minimum) into a narrow band; ⇧-drag with the Desktop hidden. Repeat in dark mode, with a Graphite accent, Increase Contrast and Reduce Motion, and take a screenshot during a drag. Expect the UI-SPEC states, no morph under Reduce Motion, no preview in the screenshot, and Pane never active.
3. **Task 3:** Debug ▸ (hold ⌥) shows "Event tap: running". Remove Pane Debug from Accessibility while it runs and click in Finder for 10 s. Clicks keep working within 2 s and the line reads "Event tap: off, drags not detected". Re-granting brings drags back.

## Requirements

- **TILE-01, TILE-02:** delivered end to end (drag-to-dock with preview; ⇧ bypass). Marked complete; live UAT is above.
- **TILE-11:** the ⌘-drag form is delivered here. The row was already Complete; 03-12 also declares it (hotkey form).
- **TILE-10:** this plan's share is delivered: the overlays need no Screen Recording. 03-17 also declares TILE-10, so it stays Pending until that plan finishes.

## Next Phase Readiness

Ready for 03-12. Plan 13 (edge resize, gap handles) builds on `DragSession.Kind.resize`, which this plan classifies but leaves alone. Plan 16 defers alerts while `Arranger.isDragging`.

## Self-Check: PASSED

- All created files exist on disk.
- All 7 plan commits (`19aa106`, `a784db9`, `ba32510`, `e8f6ea2`, `081b10e`, `fee2626`, `4bc8d42`) are ancestors of HEAD.
