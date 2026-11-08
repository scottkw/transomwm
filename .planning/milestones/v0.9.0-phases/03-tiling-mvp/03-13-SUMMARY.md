---
phase: 03-tiling-mvp
plan: 13
subsystem: pointer-resize
status: complete
tags: [swift, paneEngine, paneMac, appkit, cgeventtap, accessibility, resize, gap-handles, green-button, tdd, tracer]

requires:
  - phase: 03-tiling-mvp
    provides: "03-11 InputTap / DragSession move-vs-resize classification / transient-free drag plans; 03-02 resizeBetween and Neighbours.boundary; 03-06 docked-window correction; 03-10 pause reasons"
provides:
  - "WindowSnapshot.greenButton and WindowInfo.greenButton (offset from the window's top-left, optional so corpus fixtures decode)"
  - "PaneMac GreenButton.shouldSwallow (pure tap rule), InputTap.setGreenButtons, TapEvent.Kind.greenButton(windowID:), CGWindowList.topmostWindow(at:)"
  - "ArrangerInput.greenButton (Dock on a floating window, Float on a docked one) and D-33 handling of a frame change during a press with no travel"
  - "Edge-resize sessions: BoundaryMove, Arranger.boundaryChange (points to weights, cut at the shrinking side's minimum), live follow on a transient World, one World.edit on mouse-up"
  - "PaneEngine GapHandle / GapHandles.handles; ArrangerInput.gapDrag; ArrangerEffect.gapHandles (sent per display on change)"
  - "PaneMac GapHandlePanels (pooled non-activating handle panels with hover, drag and limit cursors)"
affects: [03-14, 03-15, 03-16, 03-17, phase-04-zoom]

estimate:
  tokens: 110000
  tasks: 3
actuals:
  tokens: 34500
  tasks: 3
  commits: 6
plan_head_before: 9b59c2564982c5ec5c5fc9a1b2f3ba3d172c6562
plan_head_after: c72f46658f869e07b88eadf97ec4a2925dfd3814

tech-stack:
  added: []
  patterns:
    - "Live resizes plan a transient copy of the World (`replan(with:on:)`, a reflow that is thrown away); only mouse-up commits a World.edit"
    - "Points become weight through the split's laid-out length and are cut to what the shrinking side can give, measured by one trial resolve, so stored weights always match the screen"
    - "Effects that drive panels (gap handles) are sent only when they change, keyed by display"

key-files:
  created:
    - Sources/PaneMac/Input/GreenButton.swift
    - Sources/PaneEngine/GapHandles.swift
    - Sources/PaneMac/Overlay/GapHandlePanels.swift
    - Tests/PaneMacTests/GreenButtonHitTests.swift
    - Tests/PaneEngineTests/ArrangerGreenButtonTests.swift
    - Tests/PaneEngineTests/ArrangerResizeTests.swift
    - Tests/PaneEngineTests/GapHandleGeometryTests.swift
    - Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-13-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-13-task2-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-13-task3-red.json
  modified:
    - Sources/PaneEngine/WindowSnapshot.swift
    - Sources/PaneEngine/WindowSystem.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/DragSession.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneMac/Input/InputTap.swift
    - Sources/PaneMac/CGWindowList.swift
    - Sources/PaneMac/ArrangeController.swift
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift

key-decisions:
  - "GreenButton.shouldSwallow takes an extra `swallowing: inout Bool` (the tap thread's state between press and release), since a pure static rule cannot otherwise swallow the matching up and drags"
  - "When the event's window field is 0 (as 03-11 saw at the session tap), a press inside some published button costs one CG on-screen list read in the callback to find the topmost window, so a button covered by another window is never taken"
  - "A green-button rect is kept only if it is finite and lies inside its own window (T-03-36), so a bogus AX value can only cover that window"
  - "A press with no pointer travel whose window's frame changed (an ⌥-zoom landing before mouse-up, a title-bar double-click) is answered at mouse-up like the app's own change: a floating window keeps it (clamped only across a tile), a docked one goes back to its tile (D-33)"
  - "Edge resize and gap drag share BoundaryMove and boundaryChange; an edge with only minimised siblings beyond it, or no room left, counts as outer and snaps back"
  - "Gap handles are created eagerly as a GapHandlePanels object in ArrangeController.init, but no NSPanel exists until a handle first shows"
  - "On a Space change the old handles are withdrawn and the same re-plan shows the new Space's (panels join all Spaces, so the swipe animation itself cannot hide them)"

patterns-established:
  - "BoundaryMove + boundaryChange: any future pointer resize (Phase 4 zoomed stage) can reuse the same weight conversion and minimum cut"

requirements-completed: [TILE-05, TILE-06, TILE-19]

coverage:
  - id: D1
    description: "A green-button click toggles docked and floating (Dock where a drop at the centre lands, Float at the tile rect); excluded, never-dock and paused windows are left alone"
    requirement: TILE-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerGreenButtonTests.swift (onAFloatingWindowItDocksLikeDock, onADockedWindowItFloatsLikeFloat, excludedNeverDockOrPausedWindowsAreLeftAlone)"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/GreenButtonHitTests.swift (5 tests)"
        status: pass
      - kind: integration
        ref: "caffeinate -d -i swift test --filter ButtonFrameIntegrationTests (trusted, not skipped)"
        status: pass
    human_judgment: true
    rationale: "Real green-button clicks through the session tap on TextEdit and an excluded app (Task 1 human-check) are end-of-phase UAT"
  - id: D2
    description: "⌥-click passes through for the native zoom; afterwards a floating window keeps the zoom (clamped only across a tile) and a docked window snaps back"
    requirement: TILE-19
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerGreenButtonTests.swift (afterAnOptionZoom*, aZoomDuringThePressOfADockedWindowIsCorrectedOnMouseUp)"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/GreenButtonHitTests.swift#optionPassesThroughSoMacOSZooms"
        status: pass
    human_judgment: true
    rationale: "Native zoom behaviour of Safari (floating and docked) is the Task 1 human-check"
  - id: D3
    description: "Dragging a docked window's own edge moves its split boundary: neighbours follow live, the window is never written, mouse-up is one undo step; outer edges snap back; corners move two boundaries; minimums stop it; floating resizes are facts; double-clicks never resize"
    requirement: TILE-05
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerResizeTests.swift (6 edge-resize tests)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Gap handles cover exactly each gap between taking-part siblings, follow every plan, hide under 4 pt, while paused, during a window drag and on a Space change; a drag resizes both sides live and commits once; a minimised sibling keeps its weight"
    requirement: TILE-05
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/GapHandleGeometryTests.swift (5 tests)"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerResizeTests.swift (4 gap tests)"
        status: pass
    human_judgment: true
    rationale: "Hover highlight, the resize cursor while another app is frontmost (A5), Safari staying frontmost and the feel of live resizing are the Task 3 human-check"

duration: 17 min
completed: 2026-10-26
---

# Phase 3 Plan 13: Green Button, Edge Resize and Gap Handles Summary

**The green button now toggles a window between docked and floating, decided in the event tap from cached button rects with no AX call, while ⌥-click keeps the macOS zoom. Docked windows resize by their own edges or by dragging the gap between them: neighbours follow live, and mouse-up commits one undo step whose weights stop at each neighbour's minimum.**

## Performance

- **Duration:** about 17 min (2026-10-26T05:27:24Z to 05:44:48Z)
- **Tasks:** 3 (Task 1 a tracer)
- **Files:** 21 changed (8 new source and test files, 3 RED records, 10 modified)

## Accomplishments

- **Green-button frame (AX).** The batched snapshot read takes the fullscreen button, or the zoom button when there is none, and reads its position and size in one more batched call. It is stored as an offset from the window's top-left and dropped unless it is finite and inside the window. The tracker copies it to `WindowInfo` and reports a `windowChanged` only when it moves by more than 1 pt. Smaller drift keeps the old value, so it cannot add up unreported.
- **The tap rule.** `GreenButton.shouldSwallow` takes a left press inside the published rect of the window under the pointer, unless ⌥ is held. It then also takes that click's drags and its release. The callback copies the rect dictionary under the lock, swallows the press (returns nil) and yields `.greenButton(windowID)`. When the event has no window, one CG list read finds the topmost window under the point. `ArrangeController` publishes `[visibleMemberID ?? windowID: global rect]` after every Arranger change. Excluded, never-dock and non-present windows are left out, and nothing is published while paused.
- **Toggle.** `.greenButton` acts exactly like Dock on a floating window and Float on a docked one, including the refusal flash when there is no room.
- **D-33.** If a press had no pointer travel but the window's frame changed (an ⌥-zoom, a title-bar double-click), that change is answered at mouse-up as the app's own. Before, it was dropped if it arrived during the press.
- **Edge resize.** Each inner edge the frame has moved off its tile becomes a `Neighbours.boundary` move between the nearest taking-part siblings. While the drag lasts, the World is re-planned on a transient copy, so neighbours follow and the dragged window is never written. Mouse-up commits one `World.edit`. Its weight change is cut to what the shrinking side can give before its minimum, so the stored weights match the screen and dragging back has no dead zone. An outer edge, or no room left, snaps the window back.
- **Gap handles.** `GapHandles.handles` returns one strip per pair of consecutive taking-part children of each split. Each strip spans the split's rect, so at a T-junction the parent's handle runs through and the child's stops at its edge. There are none under 4 pt. The Arranger sends `.gapHandles` per display only when they change. They are hidden while paused, during a window drag and on a Space change, and they follow the live resize. `.gapDrag` follows live, then commits one edit on `ended`.
- **Handle panels.** Panels are pooled, `[.borderless, .nonactivatingPanel]`, never key, at floating level on every Space, and excluded from capture. Each one takes mouse events only over its gap. Its tracking area is always active and sets the cursor with `NSCursor.set()`; there is no cursor-update handling. `acceptsFirstMouse` returns true. The strip shows the accent at 50% on hover (fading in over 80 ms and out over 120 ms) and at 85% while dragged. The cursor is `columnResize`/`rowResize` on macOS 15 and later, and the older resize cursors before that. It switches to the single-direction cursor once the strip has stopped short of the pointer.

## Task Commits

1. **Task 1 (tracer): green button toggle and tap rule.** `3a9b187` (test, RED), `827d0e2` (feat, GREEN). Tracer gate: the automated `<verify>` passed end to end, including the live `ButtonFrameIntegrationTests` (trusted, not skipped). Tracer verified end to end, expanding. Its human-check is end-of-phase UAT (`human_verify_mode: end-of-phase`), as in 03-11 and 03-12.
2. **Task 2: edge resize.** `90f003a` (test, RED), `6f610c7` (feat, GREEN)
3. **Task 3: gap handles.** `4214b15` (test, RED), `c72f466` (feat, GREEN)

## TDD Gate Compliance

| Task | RED | Evidence | GREEN |
|------|-----|----------|-------|
| 1 | `3a9b187` | `tdd/03-13-task1-red.json` RED_EVIDENCE_OK (target `aPressInsideTheButtonIsSwallowedWithItsDragsAndRelease()`). Stubs compiled. Swallow, toggle, tracker and zoom-during-press rows failed on their assertions. Rows the old code already covered passed. | `827d0e2` |
| 2 | `90f003a` | `tdd/03-13-task2-red.json` RED_EVIDENCE_OK (target `draggingTheInnerRightEdgeMovesTheBoundaryAndCommitsOnce()`). Live follow, corner and minimum rows failed. Outer-edge, floating-fact and double-click rows already held. | `6f610c7` |
| 3 | `4214b15` | `tdd/03-13-task3-red.json` RED_EVIDENCE_OK (target `aPairGetsOneHandleOverTheWholeStripBetweenThem()`). Every geometry and Arranger gap row failed against the stubs. | `c72f466` |

No REFACTOR commits were needed.

## Verification

- `swift test --filter "GreenButtonHitTests|ArrangerGreenButtonTests|GreenButtonTrackingTests|ClassifierCorpusTests"`: 18 tests passed (5 + 13).
- `caffeinate -d -i swift test --filter ButtonFrameIntegrationTests`: 1 test passed (trusted, not skipped).
- `swift test --filter "ArrangerResizeTests|ArrangerDragTests|DragSessionTests"`: 28 tests passed after Task 2.
- `swift test --filter "GapHandleGeometryTests|ArrangerResizeTests"`: 15 tests passed.
- Non-live suites (`PANE_SKIP_AX_INTEGRATION=1 swift test`): PaneModelTests 190, PaneMacTests 157, PaneEngineTests 392, plus 39 more, all passing.
- Live suites, run caffeinated in three bounded batches with the Mac unlocked (instead of one bare `swift test`, per the live-test rules): 9 + 15 + 14 tests passed. `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` was skipped (known, deferred). The opt-in fullscreen and title-bar-drag tests were skipped. No fixtures were left running after any batch.
- `scripts/build-debug.sh` exit 0 (signed, designated requirement satisfied). `scripts/check-no-appkit.sh` exit 0.
- Acceptance greps:

  | Check | Expected | Result |
  |---|---|---|
  | `greenButton` in WindowSnapshot.swift | >= 1 | 3 |
  | `greenButton` in AXSnapshotReader.swift | >= 1 | 2 |
  | `GreenButton.shouldSwallow` in InputTap.swift | 1 | 1 |
  | `maskAlternate` in GreenButton.swift | >= 1 | 1 |
  | files among InputTap.swift and GreenButton.swift that mention `AXUIElement` | 0 | 0 |
  | files among Arranger.swift and DragSession.swift that mention `Neighbours.boundary` | >= 1 | 1 |
  | `public enum GapHandles` in GapHandles.swift | 1 | 1 |
  | `cursorUpdate` in GapHandlePanels.swift | 0 | 0 |
  | `acceptsFirstMouse` in GapHandlePanels.swift | >= 1 | 1 |

## Decisions Made

See `key-decisions` in the frontmatter. In short:

- The swallow rule carries its press-to-release state as an `inout` flag.
- A press with no window in the event pays for one CG list read, so a covered button is never taken.
- A no-travel press is answered at mouse-up.
- Edge and gap drags share one weight conversion, which stops at the neighbour's minimum.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] Green-button press with no window in the event**
- **Found during:** Task 1
- **Issue:** The plan keys the swallow by `mouseEventWindowUnderMousePointer`, but 03-11 found that field is 0 at the session tap. Every press would then pass through, and TILE-06 would never fire. A plain any-rect hit test instead would swallow clicks on a window covering another window's button (T-03-34).
- **Fix:** only when the field is 0 and the press is inside some published rect, the callback reads the on-screen CG list once and uses the topmost visible window of another process under the point. This adds no AX call.
- **Files:** Sources/PaneMac/Input/InputTap.swift, Sources/PaneMac/CGWindowList.swift
- **Commit:** `827d0e2`

**2. [Rule 3 - Blocking] `GreenButton.shouldSwallow` needs press-to-release state**
- **Found during:** Task 1
- **Issue:** The planned signature has no state, yet the behaviour swallows the up and the drags after a swallowed down.
- **Fix:** added a trailing `swallowing: inout Bool`, kept in the tap's box and touched only on the tap thread. The name is unchanged.
- **Commit:** `827d0e2`

**3. [Rule 1 - Bug] A zoom during a no-travel press was dropped**
- **Found during:** Task 1 (D-33 test)
- **Issue:** a frame change that arrives while the button is down goes to the drag session. The session has no kind without travel, and the change was then never answered.
- **Fix:** mouse-up answers it through `moved()`.
- **Commit:** `827d0e2`

**4. [Rule 2 - Missing critical] Green-button rect validation**
- **Found during:** Task 1 (T-03-36)
- **Issue:** a bogus AX rect could make the tap swallow clicks anywhere.
- **Fix:** the rect is dropped unless it is finite and inside its own window.
- **Commit:** `827d0e2`

**5. [Rule 1 - Bug] Dead zone after a resize stopped at a minimum**
- **Found during:** Task 2
- **Issue:** converting raw pointer points to weight stores more weight than the screen shows once a neighbour is pinned at its minimum. The Desktop would also pay for the rest.
- **Fix:** `boundaryChange` cuts each move to what the shrinking side actually gave in a trial resolve. Covered by `aResizeStopsAtTheNeighboursMinimum`, including the drag back.
- **Commit:** `6f610c7`

**6. [Rule 3 - Blocking] An exact effect count in an older test**
- **Found during:** Task 3
- **Issue:** `ArrangerLifecycleTests/nothingIsWrittenWhileThePauseLastsAndTheDeskIsReplannedOnResume` expected exactly one effect on resume. A closed window now also changes the gap handles.
- **Fix:** the count ignores `.gapHandles`.
- **Commit:** `c72f466`

**7. [Scope] Live verification in batches**
- The plan's `scripts/build-debug.sh && swift test` was run as the build, the non-live suites and three bounded, caffeinated live batches. A single unbounded live run would break the project's live-test rules.

**Total deviations:** 6 auto-fixed (2 bugs, 2 missing critical, 2 blocking) plus 1 verification-scope change. **Impact:** the planned interfaces are unchanged except for the added `inout` parameter. No architectural change.

## Issues Encountered

- After Task 2 was written, the history baseline of a restored World turned out to be 0, not 1: `reattach` starts the undo history empty. The new tests were corrected before the RED commit.

## Known Stubs

None.

## Threat Flags

None. The swallow, the lock and the AX rects are T-03-34..36 and are mitigated as planned. The CG list read in the callback runs only for a press inside a published button when the event has no window.

## Pending Human Checks (end-of-phase UAT)

1. **Task 1 (TILE-06, TILE-19):** in Pane Debug, click the green button of a floating TextEdit window (it docks), then click it again (it floats). ⌥-click the green button of a floating Safari window (native zoom, which it keeps) and then of a docked one (it zooms, then snaps back into its tile). Click the green button of an excluded app's window (it behaves as without Pane). Also check with `log stream` that the press resolves even though the event's window field is 0.
2. **Task 3 (TILE-05, A5):** set gaps to 8 pt and dock three windows in a T layout. With Safari frontmost, hover and drag each gap. Expect the accent highlight and both neighbours following, with Safari staying frontmost; the cursor may stay an arrow while Pane is inactive (A5). Minimise the middle window and drag the gap next to it; its share must not change. Set Gaps to None: no handles, and edge drags still resize. Drag a docked window's own edge.

## Requirements

- **TILE-05, TILE-06, TILE-19:** delivered end to end. No other Phase 3 plan declares them (`requirements.ready-ids`: all ready). They are marked complete, and live UAT is above.

## Next Phase Readiness

Ready for 03-14. Gap handles and green-button rects are both refreshed by Arranger changes, so later plans that add pause reasons (Stage Manager in 16) hide them for free.

## Self-Check: PASSED

- All created files exist on disk.
- All 6 plan commits (`3a9b187`, `827d0e2`, `90f003a`, `6f610c7`, `4214b15`, `c72f466`) are ancestors of HEAD.
