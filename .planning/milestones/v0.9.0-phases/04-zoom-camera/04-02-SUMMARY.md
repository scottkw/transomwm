---
phase: 04-zoom-camera
plan: 02
subsystem: zoom
status: complete
tags: [engine, camera, view-planner, collapse, swift-testing]
requires:
  - phase: 04-01
    provides: "GO-with-conditions verdict: the ZOOM-07 budget is the write path only; the SnapshotCache is mandatory in 04-04"
provides:
  - "ViewTarget, LayoutTree.subtree(at:), ViewPlan, ViewPlanner.plan(desk:view:area:gap:mins:wanted:collapsible:)"
  - "Zoom-on collapse pass (ViewPlan.collapsed) for the session-only collapsible set"
  - "CameraState, PendingMove, CameraMove, TileMove(.stay/.entering/.leaving), Arranger.cameraMap(viewRect:onto:)"
  - "Arranger inputs .zoomEnabled / .zoomTo / .cameraSettle and effect .cameraMove; public zoomEnabled and view(on:)"
  - "View-aware planShown; parkRequested exemption in rehome, moved and correct"
  - "SettleTracker (reveal at last return + 50 ms, 1500 ms cap)"
  - "ArrangeController settles every .cameraMove at once until the 04-04 stage exists"
affects: [04-03, 04-04, 04-05, 04-06, 04-07, 04-08]
actuals:
  tokens: 12357
  tasks: 2
  commits: 4
plan_head_before: 18a3f0412eecb5b71efdcedf88d54e127a067b33
plan_head_after: 98ae97bc7be0a8d54a31c46bb277992a5e8bb89e
tech-stack:
  added: []
  patterns:
    - "Two-step camera protocol: a command emits one .cameraMove and no writes; only the matching .cameraSettle commits the view and calls planShown"
    - "All camera state lives in one CameraState value (Arranger.camera), so later plans add fields without new Arranger stored properties"
    - "effectiveView(for:notes:) is the single place planShown asks which view to plan (04-03 refines its fallback)"
key-files:
  created:
    - Sources/TransomEngine/ViewPlanner.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/SettleTracker.swift
    - Tests/TransomEngineTests/ArrangerCameraTests.swift
    - Tests/TransomEngineTests/ViewPlannerTests.swift
    - Tests/TransomEngineTests/SettleTrackerTests.swift
  modified:
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomMac/ArrangeController.swift
key-decisions:
  - "Gap handles show only on displays at the home view (planner choice, kept): a gap drag edits home weights"
  - "LayoutTree.subtree(at:) lives in TransomEngine (ViewPlanner.swift), not TransomModel; it uses only the public validating init"
  - "ViewPlanner applies the collapse pass to whichever view it plans, .home included (04-07 and 04-08 rely on it); with an empty set it is exactly Planner.plan"
  - "setZoomEnabled(false) re-plans through replan(), which is planShown() unless a gap drag is live"
requirements-completed: [ZOOM-01, ZOOM-02, ZOOM-07, ZOOM-13]
coverage:
  - id: D1
    description: "Zoom to a node and back: one .cameraMove, no writes until the matching settle, then save before parks first and only changed setFrames; zoom off by default"
    requirement: ZOOM-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#ArrangerCameraTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Writes only at settle with the matching moveID; repeated, older and unknown settles do nothing; retargets start from the pending target"
    requirement: ZOOM-07
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#aSecondSettleOrAStaleOneDoesNothing"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#aRetargetStartsFromThePendingTarget"
        status: pass
    human_judgment: false
  - id: D3
    description: "Camera-parked docked windows are never rehomed or corrected when their sliver is reported on another display"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#aParkedDockedWindowIsNeverRehomed"
        status: pass
    human_judgment: false
  - id: D4
    description: "ViewPlanner node views, Desktop view and floaters, and subtree extraction (the node views ZOOM-02 step commands target in 04-03)"
    requirement: ZOOM-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ViewPlannerTests.swift#ViewPlannerTests"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ViewPlannerTests.swift#SubtreeTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Zoom-on collapse pass with exact minimum boundaries and deterministic output"
    requirement: ZOOM-13
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ViewPlannerTests.swift#aCollapsibleWindowThatDoesNotFitGetsItsShareAndIsParked"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ViewPlannerTests.swift#onePointSmallerIsCollapsed"
        status: pass
    human_judgment: false
  - id: D6
    description: "SettleTracker reveal timing"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/SettleTrackerTests.swift#SettleTrackerTests"
        status: pass
    human_judgment: false
duration: 15min
completed: 2026-10-28
---

# Phase 4 Plan 02: Engine Camera Core Summary

**The engine moves the camera to any node and back headlessly: one `.cameraMove` with start and end rects per tile, no AX write until the matching `.cameraSettle`, then `planShown` saves first, parks the windows outside the view at their own size and writes only the frames that changed. Zoom is off by default, so the whole Phase 3 suite still passes unchanged.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-10-28T12:48Z
- **Completed:** 2026-10-28T13:03Z
- **Tasks:** 2 (both TDD, RED then GREEN)
- **Files modified:** 8 (6 created, 2 modified)

## Accomplishments

- `ViewPlanner`: `.home` is exactly `Planner.plan`. `.node(X)` resolves X's subtree in the display's whole visibleFrame and parks every present window outside it, plus the floaters when the Desktop tile is out of view, sorted by identity.
- The camera protocol in `Arranger+Camera.swift`. `zoomTo` refuses with an `.info` line when zoom is off, paused, the display has no desk, the node is missing or the view is already showing. Otherwise it plans both views and emits a `.cameraMove` (tiles sorted by identity; leaving and entering tiles use the camera map of their home rect). `cameraSettle` commits the view and returns `planShown()`.
- `planShown` plans a zoomed display's committed view after the Phase 3 lost-room float, so OS-caused lost room still floats (CONTEXT E). The park loop, `homeFrames`, `parkRequested`, the 0.5 pt rule and save-before-park are unchanged.
- The `parkRequested` exemption in `rehome`, `moved` and `correct` (RESEARCH Pitfall 1).
- The zoom-on collapse pass. Unfit collapsible windows are planned again at a 1x1 minimum. A window whose share is still below its minimum becomes a collapsed block and is parked. One still unfit at 1x1 is parked with no block. Unfit windows outside the set stay in `unfit`.
- `SettleTracker` for 04-04's reveal timing.

## Task Commits

1. **Task 1: Tracer: zoom to a node and back** - RED `9f15bb1` (test), GREEN `a31ebb5` (feat)
2. **Task 2: View planner edge cases, collapse pass, settle timer** - RED `bf064de` (test), GREEN `98ae97b` (feat)

## TDD

- **Task 1 RED (`9f15bb1`):** ArrangerCameraTests failed to compile (`cannot find type 'CameraMove'`, no `.zoomTo`, no `zoomEnabled`). **GREEN (`a31ebb5`):** 10/10 pass. Mutation check: with the `parkRequested` exemptions removed, `aParkedDockedWindowIsNeverRehomed` fails with 3 issues, so the test exercises them.
- **Task 2 RED (`bf064de`):** failed to compile (`cannot find 'SettleTracker'`). With SettleTracker added and the collapse pass not yet written, 5 collapse tests failed with 11 issues while the subtree, node-view and timer tests passed. **GREEN (`98ae97b`):** 49/49 on the Task 2 filter.
- Tracer gate: the Task 1 `<verify>` ran again before expansion and passed (54 tests in 4 suites).

## Verification

- Task 1 filter (`ArrangerCameraTests|ArrangerDesktopTests|ArrangerLifecycleTests|ArrangerMultiDeskRestoreTests`): 54 tests in 4 suites passed, no "✘".
- Task 2 filter (`ViewPlannerTests|SubtreeTests|SettleTrackerTests|PlannerTests|ArrangerCameraTests`): 49 tests in 5 suites passed, no "✘".
- Full headless `swift test`: 193 + 201 + 42 + 592 = 1028 Swift Testing tests passed across 4 test bundles, no "✘". The XCTest lines report 0 executed because the suites are Swift Testing.
- `scripts/check-no-appkit.sh`: OK (43 files).
- Acceptance greps: `parkRequested.contains` 3 (baseline 0), `ViewPlanner.plan` in Arranger.swift 1, `cameraSettle` in ArrangeController.swift 1, `struct SubtreeTests` 1, `milliseconds(1500)` 1.
- Expectation guard: `grep -c '^-.*#expect'` over the 04-02 Tests diff prints 0.

## Files Created/Modified

- `Sources/TransomEngine/ViewPlanner.swift`: ViewTarget, `LayoutTree.subtree(at:)`, ViewPlan, ViewPlanner with the collapse pass.
- `Sources/TransomEngine/Arranger+Camera.swift`: CameraState, PendingMove, CameraMove, TileMove, `zoomTo`, `cameraSettle`, `setZoomEnabled`, `effectiveView(for:notes:)`, `view(on:)`, `cameraMap(viewRect:onto:)`.
- `Sources/TransomEngine/SettleTracker.swift`: pure reveal timing with an injected clock.
- `Sources/TransomEngine/Arranger.swift`: three inputs and one effect, `var camera`, view-aware `planShown`, gap handles at home only, park exemptions. `planShown`, `sessionPaused` and `key(_:)` went from private to internal so the extension file can reach them.
- `Sources/TransomMac/ArrangeController.swift`: `.cameraMove` answered with an immediate `.cameraSettle`. Production never sends `.zoomEnabled(true)` yet, so shipped behaviour is unchanged.
- Tests: `ArrangerCameraTests.swift` (10), `ViewPlannerTests.swift` (SubtreeTests 3 + ViewPlannerTests 10), `SettleTrackerTests.swift` (5).

## Decisions Made

- **Gap handles at home only** (planner choice, confirmed in code): a zoomed display gets an empty handle list.
- **`subtree(at:)` in TransomEngine** (planner choice): it needs only LayoutTree's public validating init, so the model is unchanged.
- **Collapse applies to whichever view is planned, `.home` included.** 04-08's `homeTiles` and 04-07's home plan expect this. With an empty set, the output equals `Planner.plan` field for field, parks order included.
- **The camera map is non-uniform** (separate x and y scales). The subtree is resolved stretched to the display, so the slide-in and slide-off geometry matches the planned rects.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A parked floater would have been unparked at once in a node view**
- **Found during:** Task 1
- **Issue:** planShown's "floating window not where the model has it" loop guarded only on `!desktopHidden`. In a node view without the Desktop tile, a camera-parked floater is off its recorded frame, so the loop would have sent it straight back.
- **Fix:** that loop also skips windows parked in this pass (`!parkedNow.contains`).
- **Files modified:** Sources/TransomEngine/Arranger.swift
- **Committed in:** a31ebb5

**2. [Rule 1 - Bug] The `moved` exemption goes before the floater frame is recorded**
- **Found during:** Task 1
- **Issue:** `moved` records a floater's reported frame before its own-write check. A camera-parked floater with the Desktop shown would have had its park position saved as its floating frame.
- **Fix:** the `parkRequested` guard sits at the top of `moved`, before any recording, as the plan's "neither recorded nor corrected" requires.
- **Files modified:** Sources/TransomEngine/Arranger.swift
- **Committed in:** a31ebb5

**3. [Minor] `setZoomEnabled(false)` calls `replan()` rather than `planShown()` directly**
- **Issue:** a bare `planShown()` during a live gap drag would write the geometry without the drag for one plan.
- **Fix:** `replan()`, which is exactly `planShown()` when no gap drag is live. `cameraSettle` still calls `planShown()` as the key link specifies.
- **Committed in:** a31ebb5

**4. [Test precision] Expected numbers corrected in my own new tests**
- The "stay" tile's end rect is the visibleFrame less resolve's 8 pt outer gap (`Rect(8, 33, 1424, 859)`), not the raw visibleFrame. Same meaning as the plan's "end = display.visibleFrame".
- The collapsed block is 453 pt, not 454: resolve floors a thirds-weighted share that lands just under 454 in doubles.
- A nested `#require` (recursive macro expansion) was split into two statements.
- Committed in a31ebb5 / 98ae97b. No pre-existing expectation was touched.

---

**Total deviations:** 2 auto-fixed bugs (Rule 1), 1 minor robustness choice, 1 group of test-precision fixes. **Impact:** all are needed for correct parking. No scope creep.

## Issues Encountered

None.

## Known Stubs

- `Sources/TransomMac/ArrangeController.swift`, `case .cameraMove`: settles at once with no animation. This is intentional per the plan; 04-04's stage replaces it. Nothing user-visible depends on it yet, because production never enables zoom.

## Threat Flags

None. T-04-06/07/08/09 are mitigated as planned: save before park through planShown, the park exemption in all three paths, writes only on the matching settle, and a collapse loop bounded by the window count.

## User Setup Required

None. No live or VM run was needed: this plan is headless engine work.

## Next Phase Readiness

- Ready for 04-03 (Navigator: step in/out, back/forward, rect target, which refines `effectiveView`) and for 04-04 (the stage takes over `case .cameraMove` and uses `SettleTracker`).
- Note for 04-03: `zoomTo` reads the current view from the pending move only when that move is on the same desk key. A move pending on a Space that is no longer shown counts as stale.

## Self-Check: PASSED

- FOUND: Sources/TransomEngine/ViewPlanner.swift, Sources/TransomEngine/Arranger+Camera.swift, Sources/TransomEngine/SettleTracker.swift, Tests/TransomEngineTests/ArrangerCameraTests.swift, Tests/TransomEngineTests/ViewPlannerTests.swift, Tests/TransomEngineTests/SettleTrackerTests.swift
- FOUND commits on HEAD: 9f15bb1, a31ebb5, bf064de, 98ae97b
- Measured commits: `git rev-list --count 18a3f04..HEAD` = 4

---
*Phase: 04-zoom-camera*
*Completed: 2026-10-28*
