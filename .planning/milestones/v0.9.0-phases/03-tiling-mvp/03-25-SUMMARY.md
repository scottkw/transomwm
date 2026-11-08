---
phase: 03-tiling-mvp
plan: 25
subsystem: engine-floaters
status: complete
tags: [g-03-11, g-03-4, tile-05, tile-06, tile-07, tile-09, wanted-frame, gap-closure, tdd]
requires: []
provides:
  - "Arranger.wantedFrames: per-window frame a floater goes back to; kept while docked (the pre-dock frame)"
  - "Planner.plan(wanted:floors:): floaters planned at their wanted frame (clamped only when it overlaps a tile); floors raise floaters' Desktop minimums"
  - "Planner.floatFrame(wanted:tile:desktop:minimum:): Float's placement, pre-dock frame or a 90% centred fallback"
  - "Arranger.floaterFloors: session-only refused sizes of floaters, counted by boundary drags only"
affects: [Arranger.moved echo rule for floaters, planShown / live gap-drag replans, boundaryChange cut, float(), green button, 03-26 (persists wantedFrames)]
tech-stack:
  added: []
  patterns: ["intent vs fact: a separate wanted frame per window that only user actions write, beside the recorded (real) frame"]
key-files:
  created:
    - Tests/PaneEngineTests/WantedFrameTests.swift
    - .planning/phases/03-tiling-mvp/03-25-SUMMARY.md
  modified:
    - Sources/PaneEngine/Planner.swift
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Arranger+Commands.swift
    - Tests/PaneEngineTests/PlannerTests.swift
    - Tests/PaneEngineTests/ArrangerGreenButtonTests.swift
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift
decisions:
  - "Wanted-frame writers: admit, a floater's own/user move (even while paused or excluded), release (excluded app), rehome (OS fact, deliberate exception), missed (floating release), commitUndock, Snap, Float, Float All, lost-room floats, wakeDormant when it records the real frame. reattach seeds floaters with none. forget drops, rekey moves. Undo, parks, echoes and rescues leave it alone; rescueStranded replaces only a stranded wanted frame (T-03-72)."
  - "Pane's own floater frames: within 2 pt of lastApplied, of lastRequested (late apply, plan-check W1), or any floater frame while a boundary drag is live (liveGap or a docked edge resize), since the mouse holds the drag."
  - "Narrowed off-screen rule (D-24 fence): a floater at its wanted frame and clear of tiles is left alone even past the screen edge; aFloatingWindowOffTheScreenEdgeButClearOfTilesIsLeftAlone unchanged."
  - "Lost-room floats record their float frame as the wanted frame, so D-26 placement and ArrangerReflowTests stay unchanged and the next plan does not move them again."
  - "Float All keeps its tile-rect placement (TILE-16); the user decision names Float and the green button only."
  - "Fallback size: 90% of the tile per axis, at least the known minimum, at most the Desktop, centred on the Desktop (Claude's discretion for 'slightly smaller')."
  - "Floors apply to boundary drags only (boundaryChange before/after plans). Counting them in planShown or the dock fit changes TooBigDockedWindowTests' dock target. T-03-71 accepted: a late applier's stale read-back can stop a drag early until its next frame event, which drops the floor axis it went below."
metrics:
  duration: "~30 min"
  completed: 2026-10-27
  tasks: 3
  files: 7
actuals:
  tokens: 9600
  tasks: 3
  commits: 6
plan_head_before: 2387cb4a3d2f6d04e60d627e464352f5e2d20a35
plan_head_after: dae0ffbafa474d7d27ea97630e3e7fdc05b0e6ef
---

# Phase 3 Plan 25: Wanted frames and floater floors (G-03-11, G-03-4) Summary

Each window now has a wanted frame that only user actions write, kept while docked. Floaters are planned from it, so a Desktop that a gap drag shrinks and grows back returns them to where they were. A floater's refused read-back sets a floor that stops a boundary drag at its real size. Float and the green button put a docked window back at its pre-dock frame, or at a centred frame 90% of the tile's size, so every toggle moves the window.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 (tracer) | Floaters keep a wanted frame that Pane's clamps never overwrite | 3fe6245 (RED), 8390892 (GREEN) |
| 2 | A refused floater clamp stops a boundary drag at the floater's real size | 01cc1a3 (RED), 9f55466 (GREEN) |
| 3 | Float and the green button go to the pre-dock frame or a 90% centred frame | f88e905 (RED), dae0ffb (GREEN) |

## TDD

**Task 1 RED (3fe6245)**, `swift test --filter WantedFrameTests`:
- `aDesktopThatShrinksAndGrowsBackReturnsFloatersToTheirFrames` failed on all three floaters. Finder ended at (40,571 460x252), the same as the g311 probe at HEAD.
- `aClampTheAppAppliesLateIsStillPanesOwn` failed: textEdit ended at its late clamp (270,481 729x220), not its start (270,420 729x260).
- `aFloaterTheUserMovesWhilePausedStaysWhereTheyLeftIt` passed at HEAD, as planned. It guards the `moved` restructure and is not RED evidence.

**Task 1 GREEN (8390892):** the verify filter (8 suites) ran 99 tests and all passed. The full suite ran 518 and all passed. The paused and late-apply tests also gained `wantedFrames` expectations, and PlannerTests gained three wanted-frame rows.

**Task 2 RED (01cc1a3):** `aFloaterWhoseMinimumIsAboveTheShrunkenDesktopNeverEndsBelowIt` failed with 8 maxY issues. Finder ended at (40,571 460x252), bottom 823, at +190 and after the release. Safari ended at (420,571 574x224).

**Task 2 GREEN (9f55466):** the verify filter (6 suites) ran 70 tests and all passed. The full suite ran 519 and all passed. TooBigDockedWindowTests and RefusalRetryBoundTests are unchanged and pass.

**Task 3 RED (f88e905):**
- `onTheDesksOnlyDockedWindowTheButtonFloatsItToItsPreDockFrameAndDocksItBack` failed: after the click, w1 was still at its tile (8,33 708x859), not at frame1.
- `aFloatWithNoKnownPreDockFrameGetsASlightlySmallerCentredFrame` failed: Float sent no setFrame for w1, because it stayed at the tile.

**Task 3 GREEN (dae0ffb):** the full `swift test` passed every test binary: 524 + 193 + 196 + 42, with no "✘". `scripts/check-no-appkit.sh` printed OK (40 files).

## The one replaced expectation

In ArrangerLifecycleTests, `floatPutsADockedWindowOnTheDesktopAtItsClampedTileRect` was renamed to `floatPutsADockedWindowOnTheDesktopAtItsPreDockFrame`. Its frame line `#expect(desk.desktop.frame(of: w1) == Planner.clamp(tile, into: desktop))` became `Planner.clamp(frame1, into: desktop)`. A new expectation checks that the frame is not the tile. The user decision of 2026-10-27 requires this: Float returns the window to its pre-dock frame. Every other line of the test is unchanged.

The expectation guard (`git diff <parent of 3fe6245> -- Tests/PaneEngineTests/ | grep -c "^-.*#expect"`) prints 1.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A late apply after a floor replan was still recorded as the wanted frame**
- **Found during:** Task 2.
- **Issue:** The floor that a stale read-back sets makes `frameApplied` replan at once. That replan changes `lastRequested` before the app's late frame event arrives, so Task 1's lastRequested rule no longer saw the late clamp as Pane's own, and `aClampTheAppAppliesLateIsStillPanesOwn` failed.
- **Fix:** While a boundary drag is live (`liveGap`, or a docked edge resize), a floater's frame event counts as Pane's own. The mouse is holding the drag, so the user cannot be moving a floater. One condition was added to the `own` test in `moved`.
- **Files modified:** Sources/PaneEngine/Arranger.swift
- **Commit:** 9f55466

**2. [Rule 1 - Bug] wakeDormant records a woken floater's real frame but kept the saved one as wanted**
- **Found during:** Task 1, while listing every writer of a floater's frame.
- **Issue:** reattach seeds a dormant floater's wanted frame from its saved frame. When the window wakes on screen, wakeDormant records its real frame (CR-02). Without a wanted-frame write, the next plan would move it back to the saved frame, which is not what HEAD does.
- **Fix:** In the same branch, wakeDormant also sets the wanted frame to the real frame. Parked and stranded frames are still never recorded.
- **Files modified:** Sources/PaneEngine/Arranger.swift
- **Commit:** 8390892

**3. Small reuse:** `Planner.near(_:_:within:)` was added for the 0.5 pt test. `Arranger.near` now calls it instead of keeping its own copy of the same body.

## Known Stubs

None.

## Residual risk

If an app applies one live step's clamp after Pane has already sent a later step and the drag has been released, that clamp is not Pane's own under any rule here. It would become the floater's wanted frame. This needs a slow app and a release in the same window of time. The VM re-check will show whether real apps do this.

## Output note

The VM re-check of G-03-4 and G-03-11 is not part of this plan. After 03-26, the orchestrator runs it in the Tart VM and checks that:
- the green button moves the desk's only docked window visibly, both ways;
- a gap drag down and back up returns the floaters, with none off screen.

G-03-4 and G-03-11 stay open in 03-UAT.md until 03-26 and that VM check are done. /gsd-verify-work closes them.

## Self-Check: PASSED

- Files: WantedFrameTests.swift, Planner.swift (`func floatFrame`), Arranger.swift (`wantedFrames` ×18, `floaterFloors` ×8, `Planner.floatFrame` ×1) all exist.
- Commits 3fe6245, 8390892, 01cc1a3, 9f55466, f88e905 and dae0ffb are all ancestors of HEAD.
- The run was headless only: PANE_LIVE was never set, and neither Pane nor PaneFixtureApp was launched.
