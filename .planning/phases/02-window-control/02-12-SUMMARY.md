---
phase: 02-window-control
plan: 12
subsystem: window-control
tags: [ax, frame-write, axenhanceduserinterface, os-allocated-unfair-lock, minimum-size, swift-testing]

requires:
  - phase: 02-window-control (02-10)
    provides: WindowTracker with TabGroupTracker visibleMemberID; FakeWindowSystem tab groups
  - phase: 02-window-control (02-11)
    provides: AXWindowSystem, AXAppThread element cache (incl. synthetic IDs), CapabilitySession
  - phase: 02-window-control (02-07)
    provides: ResponsivenessTracker degraded/probe rule, FakeWindowSystem hung apps
provides:
  - MinimumSizeLearner (pure, per-axis, +2 pt tolerance, values only grow)
  - WindowTracker.applyFrameResult (frameApplied plus moved/resized/changed, learnedMinimum)
  - FrameWriter (enhanced UI off, size -> position -> size, read-back, restore)
  - AXAppThread latest-wins frame slots, drainEnabled, frameResults
  - AXWindowSystem.perform for setFrame (validated, visible tab, drains paused while degraded)
  - FakeWindowSystem frame writes with hidden-minimum clamping and held frames for hung apps
affects: [02-13 (exclusion filter in perform, minimum hints persistence, Nudge), 03 tiling (setFrame is the write path)]

actuals:
  tokens: 10528
  tasks: 2
  commits: 3
plan_head_before: 9cc705d610e260d2e6159ed9c7f94f156303f048
plan_head_after: 02c4f26c64cd3d7cdfe0b1ca7a86af5ead5cfa4d

tech-stack:
  added: []
  patterns:
    - "Latest-wins queue: per-key slots plus drainScheduled/drainEnabled in one OSAllocatedUnfairLock state; a mutating claimDrain() decides scheduling inside the lock, the CFRunLoopPerformBlock happens outside it"
    - "The responsiveness rule drives the write queue: record() ends by setting drainEnabled = shouldRefresh(pid), so one place pauses, retries and flushes"

key-files:
  created:
    - Sources/PaneEngine/MinimumSizeLearner.swift
    - Sources/PaneMac/AX/FrameWriter.swift
    - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
    - Tests/PaneEngineTests/FrameScenarioTests.swift
    - Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift
    - .planning/phases/02-window-control/tdd/02-12-task1-red.json
  modified:
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneFixtureApp/main.swift

key-decisions:
  - "A write the app did not answer (-25204) goes back in its slot (unless a newer frame is waiting) and the drain stops; recording it with ResponsivenessTracker then re-enables the drain once (retry) or pauses it (degraded), so a frame queued just before a freeze is not lost"
  - "Frame write failures are recorded with duration .zero: FrameWriteResult has no duration, and the consecutive-failure count alone degrades a hung app"
  - "applyFrameResult does not recompute displayUUID (the tracker has no displays there); the refresh that the AX moved notification triggers updates it, which the second-display test confirms within 2 s"
  - "The fixture's minsize:WxH spec now sets NSWindow.minSize (frame minimum) instead of contentMinSize, matching the plan's and RESEARCH's 'minSize 250x150 reads back 250x150'"

patterns-established:
  - "Read-back numbers are untrusted: isValidGeometry gates both learning and the tracker's frame update"

requirements-completed: [WIN-04, WIN-03]

coverage:
  - id: D1
    description: "MinimumSizeLearner learns per axis with the +2 / +2.01 pt boundary, ignores smaller axes and invalid read-backs, only grows"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/MinimumSizeLearnerTests.swift (8 tests, 11 cases)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Tracker reports every read-back as frameApplied with moved/resized/changed and learnedMinimum; failures change nothing; closed windows forget their minimum"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FrameScenarioTests.swift#aReadBackFrameMovesResizesAndLearns, aFailedWriteLearnsNothingAndClosesNothing, aClosedWindowsLearnedMinimumIsForgotten"
        status: pass
    human_judgment: false
  - id: D3
    description: "Fake refusing-size and hung-app scenarios use the shared tracker and learner (D-14)"
    requirement: WIN-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FrameScenarioTests.swift#theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsIt, aHungAppHoldsOnlyItsLatestFrameAndAnotherAppIsWrittenAtOnce"
        status: pass
    human_judgment: false
  - id: D4
    description: "Live: exact move/resize with read-back confirmed by the fixture's own list, learned 250x150, burst ends at the latest frame, a SIGSTOPped app does not delay another app's write, move onto the second display changes displayUUID"
    requirement: WIN-04
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift (5 tests, 5 consecutive passing runs)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Frame writes on real third-party apps (Chrome/Electron enhanced UI, terminals snapping to cells, an app with a real minimum size)"
    requirement: WIN-04
    verification: []
    human_judgment: true
    rationale: "Live tests drive only the fixture app; real-app behaviour is end-of-phase human UAT (02-13 Nudge)"

duration: 10min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 12: Frame Write Pipeline Summary

**Pane now moves and resizes tracked windows: each app thread keeps one latest-wins frame slot per window, writes size, position, size with AXEnhancedUserInterface off, reads every write back, and the tracker learns a window's real minimum when the app refuses a smaller size.**

## Performance

- **Duration:** about 10 min
- **Started:** 2026-10-25T16:40:43Z
- **Completed:** 2026-10-25T16:50:18Z
- **Tasks:** 2
- **Files modified:** 12 (plus 1 RED evidence record)

## Accomplishments
- `MinimumSizeLearner` (PaneEngine, no Foundation): per axis, `actual > requested + 2` learns `max(old, actual)`; exactly +2 pt learns nothing and +2.01 pt does; read-backs that are not valid geometry are ignored.
- `WindowTracker.applyFrameResult`: the read-back becomes the frame and feeds the learner; it returns `frameApplied` plus `windowMoved`/`windowResized`, and `windowChanged` when `learnedMinimum` changed. A failed write returns nothing. A closed window forgets its minimum, so a reused ID starts fresh.
- `FakeWindowSystem.perform` clamps to `hiddenMinimum`, writes the visible tab (the other tabs follow it), and holds only the latest frame per window of a hung or degraded app until its next successful refresh.
- `FrameWriter` plus `AXAppThread` frame slots under `OSAllocatedUnfairLock`: one drain at a time, `drainEnabled`, a `frameResults` stream, and a per-bundle enhanced-UI re-enable table (empty, so it defaults to on).
- `AXWindowSystem.perform`: drops and logs invalid rects and untracked windows, addresses `visibleMemberID ?? windowID`, and feeds results through `applyFrameResult`. Writes pause while an app is degraded and flush on recovery. Other commands are still logged and dropped until Phase 3.

## Task Commits

1. **Task 1 RED: failing learner, tracker and fake frame tests** - `1375f51` (test)
2. **Task 1 GREEN: learner, applyFrameResult, fake frame writes** - `e43a3b9` (feat)
3. **Task 2: latest-wins write pipeline with read-back and live tests** - `02c4f26` (feat)

## TDD Gate Compliance

- RED `1375f51`: `swift test --filter "MinimumSizeLearnerTests|FrameScenarioTests"`, target `aRefusedSizeIsLearnedAndAnHonouredOneChangesNothing()`. 9 of 15 tests failed on assertions against the stubs (`learn` returned nil, `applyFrameResult` returned []). The classifier returned `RED_EVIDENCE_OK`. Semantic check: the target ran and failed on its planned assertion, with no build, load or fixture fault. The six rows that passed assert that nothing is learned or written, so they pass trivially against empty stubs. Record: `tdd/02-12-task1-red.json`.
- GREEN `e43a3b9`: all 15 pass. No refactor commit was needed.
- Task 2 is `type="auto"` (not TDD), so it has a single feat commit with its integration tests.

## Files Created/Modified
- `Sources/PaneEngine/MinimumSizeLearner.swift` - pure per-window minimum learning
- `Sources/PaneEngine/WindowTracker.swift` - owns the learner; `applyFrameResult`; forgets on close
- `Sources/PaneTestSupport/FakeWindowSystem.swift` - frame application, clamping, held frames
- `Sources/PaneMac/AX/FrameWriter.swift` - the AX write sequence with read-back
- `Sources/PaneMac/AX/AXAppThread.swift` - frame slots, drain, `drainEnabled`, `frameResults`
- `Sources/PaneMac/AXWindowSystem.swift` - `perform`, frame-result consumption, drain gating in `record`
- `Sources/PaneMac/AX/AXSnapshotReader.swift` - `point`/`size` AXValue helpers made internal for FrameWriter's read-back
- `Sources/PaneFixtureApp/main.swift` - `minsize:` sets the frame minimum
- `Tests/PaneEngineTests/MinimumSizeLearnerTests.swift`, `Tests/PaneEngineTests/FrameScenarioTests.swift`, `Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift`

## Decisions Made
See key-decisions in the frontmatter. The main one: a write that times out is put back rather than dropped, and the responsiveness rule decides when to retry. So "the latest frame is held while degraded" also covers a frame queued in the second before Pane noticed the freeze.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixture `minsize:` set the content minimum, not the frame minimum**
- **Found during:** Task 2, live case (b)
- **Issue:** `contentMinSize` 250×150 reads back as a 250×178 frame (the 28 pt title bar is added), so the plan's "minSize 250×150 reads back 250×150" could not hold.
- **Fix:** the fixture sets `NSWindow.minSize` instead. Only `FixtureShapesTests` also uses the spec, and it does not check the size.
- **Files modified:** `Sources/PaneFixtureApp/main.swift`
- **Verification:** case (b) reads back and learns 250×150 ± 1. Full `swift test` passes.
- **Committed in:** `02c4f26`

**2. [Rule 3 - Blocking] FrameWriter reuses AXSnapshotReader's AXValue decoders**
- **Found during:** Task 2
- **Issue:** the `point`/`size` decoders were `private` in `AXSnapshotReader.swift`, a file outside the plan's list.
- **Fix:** made them internal (no other change) instead of copying them.
- **Files modified:** `Sources/PaneMac/AX/AXSnapshotReader.swift`
- **Committed in:** `02c4f26`

**3. [Rule 2 - Missing critical] Requeue a write the app did not answer**
- **Found during:** Task 2
- **Issue:** the plan's drain takes every slot. A frame that timed out before the app was marked degraded would be lost, which breaks "held while degraded, applied once it recovers".
- **Fix:** on -25204 the drain puts that frame and every unwritten one back (unless newer ones are waiting) and stops. `record()` sets `drainEnabled = shouldRefresh(pid)`, which gives one retry, then a pause once degraded, then a flush on recovery.
- **Files modified:** `Sources/PaneMac/AX/AXAppThread.swift`, `Sources/PaneMac/AXWindowSystem.swift`
- **Verification:** live case (d) passes with a write queued for the SIGSTOPped fixture.
- **Committed in:** `02c4f26`

---

**Total deviations:** 3 auto-fixed (1 bug, 1 blocking, 1 missing critical)
**Impact on plan:** All three were needed for the planned truths to hold. No scope creep.

## Issues Encountered
- None blocking. The case (e) second-display test ran because two displays were connected, and it passed. On a single-display Mac it is skipped with the reason "needs two displays; the manual UAT in 02-13 covers it".
- Release build: only the known `PermissionReducer.swift:110` warning (already in deferred-items.md).
- The intermittent `CloseIntegrationTests` unhide flake did not recur in this plan's full run.

## Verification
- `swift test --filter "MinimumSizeLearnerTests|FrameScenarioTests"`: 15 tests pass.
- `swift test --filter FrameWriteIntegrationTests` (trusted terminal, `caffeinate`): 5 of 5 pass, 5 runs in a row. No fixture was left running.
- `swift test` (full, including live suites): passes. `swift test -c release -Xswiftc -enable-testing --skip PaneMacIntegrationTests`: passes.
- `scripts/check-no-appkit.sh`: OK.
- Prohibition "Pane writes window frames only when a command is performed": holds. Only `perform` calls `enqueueFrame`.

## Human UAT (end of phase)
- Nudge (02-13) on real apps: a Chrome or Electron window (enhanced UI toggled and restored), Terminal or iTerm2 (cell snapping must not be learned as a minimum), and an app with a real minimum size (the learned minimum should show in the Tracked Windows list).
- Move a real window onto a second display with Nudge and check that its display column follows.

## User Setup Required
None. No external service configuration is required.

## Next Phase Readiness
- 02-13 can put `ExclusionFilter.admit` at the top of `AXWindowSystem.perform` and of `FakeWindowSystem.perform`, persist `learnedMinimum` as per-bundle hints, and drive Nudge through `setFrame`.

---
*Phase: 02-window-control*
*Completed: 2026-10-25*

## Self-Check: PASSED
