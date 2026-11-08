---
phase: 02-window-control
plan: 17
subsystem: window-identity
tags: [swift, tab-groups, spaces, fallback, nsworkspace, fold-guard, gap-closure]

requires:
  - phase: 02-window-control
    provides: "02-14 TabGroupTracker orphan handoff, hidden-tab fold and fold guard; 02-16 ObservationContext.windowSpaces and re-keying"
provides:
  - "ObservationContext.spaceChanged (Bool, default false)"
  - "SpaceSwitchMarks (PaneEngine, pure): per-pid marks with a generation counter; spaceDidChange(pids:), take(pid:readGeneration:), forget(pid:)"
  - "TabGroupTracker.update(..., spaceChanged:): no orphan handoff and no new fold in a flagged update without Space data"
  - "WindowTracker fold guard holds (no count, no destroy) in a flagged update without Space data"
  - "FakeWindowSystem.showSpace(_:notifies:)"
  - "AXWindowSystem observes NSWorkspace.activeSpaceDidChangeNotification; read generation recorded per refresh and per sweep snapshot"
affects: [phase-03-tiling, phase-06-spaces]

actuals:
  tokens: 5100
  tasks: 2
  commits: 4
plan_head_before: 038fb768ebd523c8a940f9cd99e2e59fa4bfc47b
plan_head_after: 2a13fbab5a4e20e60d2265bad728310d9166d36e

tech-stack:
  added: []
  patterns:
    - "Asynchronous OS signals reach the pure engine as a Bool in ObservationContext; the generation of the signal is compared with when an update's reads began"

key-files:
  created:
    - Sources/PaneEngine/SpaceSwitchMarks.swift
    - Tests/PaneEngineTests/SpaceSwitchMarksTests.swift
  modified:
    - Sources/PaneEngine/WindowSnapshot.swift
    - Sources/PaneEngine/TabGroupTracker.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Tests/PaneEngineTests/TabScenarioTests.swift
    - Tests/PaneEngineTests/TabGroupTrackerTests.swift

key-decisions:
  - "02-17: 'the hidden-tab fold or merge' is read as one rule, a tracked standalone window taken as a hidden tab (the Merge All Windows case); the room-rule join and the Cmd-T opener are not refused in a flagged update"
  - "02-17: a Space-switch mark is consumed only by a full AXWindows answer whose reads began at or after the notification; a notification during the reads flags that update and the next one"
  - "02-17: with Space data a flagged update resolves exactly as an unflagged one; the flag only matters in single-Space fallback"

patterns-established:
  - "Read generation: record the signal counter when the reads begin (before the sweep's CG snapshot, before thread.observe), never at ingest"

requirements-completed: [WIN-06, WIN-09]

coverage:
  - id: D1
    description: "Without Space data, a whole tab group closing in the same update as a Space switch that shows a same-frame twin is destroyed by CloseRule and the twin is created on its own; it never inherits the group (all three modes)"
    requirement: WIN-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TabScenarioTests.swift#aSpaceSwitchAsAWholeGroupClosesNeverHandsTheGroupToTheShownTwin(spacesAvailable:hiddenTabsReportSpace:)"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/TabGroupTrackerTests.swift#withoutSpaceDataAFlaggedUpdateMakesNoOrphanHandoff()"
        status: pass
    human_judgment: false
  - id: D2
    description: "SpaceSwitchMarks consume rule, including a notification injected between the start of the reads and ingest"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/SpaceSwitchMarksTests.swift#SpaceSwitchMarksTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "A flagged fallback update takes no tracked standalone window as a new hidden tab and the fold guard neither counts nor destroys; with Space data, and without the flag, folds and the guard are unchanged"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TabGroupTrackerTests.swift#withoutSpaceDataAFlaggedUpdateFoldsNoTrackedWindow()"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/TabScenarioTests.swift#withoutSpaceDataAFlaggedUpdateNeitherCountsNorDestroysAFold()"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/TabScenarioTests.swift#withSpaceDataAFlaggedUpdateCompletesTheFoldGuardAsUsual()"
        status: pass
    human_judgment: false
  - id: D4
    description: "Live wiring: AXWindowSystem observes activeSpaceDidChangeNotification and flags updates; the live tab, Spaces and fixture integration tests still pass"
    requirement: WIN-06
    verification:
      - kind: integration
        ref: "caffeinate -d -i swift test --filter \"TabsIntegrationTests|SpacesIntegrationTests|FixtureTrackingTests\""
        status: pass
    human_judgment: true
    rationale: "A real Space switch while a Safari tab group closes cannot be driven from the fixture; the Task 2 human-check is end-of-phase UAT"

duration: 8min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 17: Space-Switch Race Without Space Data Summary

**Pane now listens for `NSWorkspace.activeSpaceDidChangeNotification` and tells the engine, per app, "the Space changed since your last full update". Without SkyLight Space data, such an update makes no orphan handoff and no new hidden-tab fold, and the fold guard waits. So a closed tab group can no longer hand its identity to a same-frame window from another Space.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-10-25T20:28:15Z
- **Completed:** 2026-10-25T20:36:30Z
- **Tasks:** 2
- **Files modified:** 9 source and test files, plus 3 TDD evidence records

## Accomplishments

- `ObservationContext.spaceChanged`, a trailing init parameter that defaults to false, so no existing call site changed.
- `SpaceSwitchMarks` (pure PaneEngine). Each notification bumps a generation and marks the pids running then. A full update consumes its pid's mark only if its reads began at or after that generation. A notification that lands while the reads are in flight therefore flags that update and the next one, never zero.
- TabGroupTracker, only when the flag is set and there is no Space data:
  - The orphan handoff is refused.
  - No tracked standalone window becomes a new hidden tab.
  - A window folded earlier, the Cmd-T opener and the room-rule join are unchanged.
- WindowTracker: in the same case the fold guard destroys nothing. It keeps a same-shown-tab count as it is and does not advance it.
- FakeWindowSystem: `showSpace(_:notifies:)` marks every app. `refresh(pid:)` records the generation before it builds the observation and takes the mark only on a full answer. `terminate` forgets the mark.
- AXWindowSystem:
  - Observes the notification on `NSWorkspace.shared.notificationCenter` (`queue: .main`, `MainActor.assumeIsolated`).
  - Records the generation before the sweep's `CGWindowList.snapshot()` (line 223) and before `thread.observe(known:)` (line 244).
  - Takes the mark in `ingest` only when `listFailure == nil`.
  - Forgets the mark in `appStopped`. The terminate and recheck contexts stay unflagged.

## Task Commits

1. **Task 1: Tracer, Space switch as a whole group closes**: `87bdba3` (test, RED), `946df0c` (feat, GREEN)
2. **Task 2: Fold refusal, fold-guard hold, live observer**: `9392512` (test, RED), `2a13fba` (feat, GREEN)

## TDD Gate Compliance

Each task has a `test(02-17)` commit before its `feat(02-17)` commit. All three RED records returned `RED_EVIDENCE_OK`.
- `tdd/02-17-task1-red.json`, target `aSpaceSwitchAsAWholeGroupClosesNeverHandsTheGroupToTheShownTwin`. It failed in mode (false, false) only. The failures were `Expectation failed: await fake.windowInfo(ref(30))?.visibleMemberID != 50` after each of the three refreshes, `destroyed(events) → []` and `created(events).map(\.window) → [window 30]`: 50 inherited G. The two Space-data modes passed, as planned. Four marks tests failed against the `take` stub. The no-notification control and `noMarkIsNotFlagged` passed by design.
- `tdd/02-17-task2-red.json`, target `withoutSpaceDataAFlaggedUpdateFoldsNoTrackedWindow()`: 20 was folded (`folded == [identity(20)]`, members [10, 20]).
- `tdd/02-17-task2-foldguard-red.json`, target `withoutSpaceDataAFlaggedUpdateNeitherCountsNorDestroysAFold()`: the flagged step destroyed 20.
- In the same Task 2 run, the Space-data variants and the negative controls passed: the unflagged handoff and fold, the Space-data handoff and fold under the flag, the earlier fold kept, and the Cmd-T opener kept. The flagged fallback handoff refusal also passed there, because Task 1 had already implemented it.

## Tracer gate

The mode is end-of-phase and the tracer's verify is automated only. After GREEN, the tracer verify passed (75 tests in 8 suites), and the full non-integration suite passed with no existing assertion changed. So Task 2 went ahead.

## Verification

- `swift test --skip PaneMacIntegrationTests`: 142 + 96 + 225 pass. The engine product grew from 208 to 225 tests, and none of the existing ones changed. `showSpace` now marks the next update in every existing scenario, and no existing scenario behaved differently.
- `swift test --filter "TabGroupTrackerTests|TabScenarioTests|FoldGuardTests|WindowTrackerTests|SpaceSwitchMarksTests"`: 85 pass.
- `scripts/check-no-appkit.sh`: OK (25 files). `scripts/build-debug.sh`: exits 0 (valid on disk, satisfies its designated requirement).
- `caffeinate -d -i swift test --filter "TabsIntegrationTests|SpacesIntegrationTests|FixtureTrackingTests"`: 3 suites pass, TabsIntegrationTests among them. The full `PaneMacIntegrationTests` run also passed: 24 tests, with the existing two-display skip. Both live runs started after a lock check (`locked: nil`). Afterwards `pgrep -fl PaneFixtureApp` printed nothing. Only fixture windows were used.
- Acceptance greps:
  - WindowSnapshot: `public var spaceChanged` 1.
  - SpaceSwitchMarks: `readGeneration` 4.
  - FakeWindowSystem: `SpaceSwitchMarks` 1, `notifies` 3.
  - TabGroupTracker: `spaceChanged` 4.
  - WindowTracker: `context.spaceChanged` 1.
  - AXWindowSystem: `activeSpaceDidChangeNotification` 2, `spaceChanged:` 1, `spaceSwitches` 6, `readGeneration` 8.
  - Order: generation at line 223 before the snapshot at 224, and at line 244 before `thread.observe` at 245.

## Decisions Made

- **How the lead decision is read.** "The hidden-tab fold or merge" is one rule: a tracked standalone window taken as a hidden tab of a group. The 02-14 tests name the Merge All Windows case this way (`mergingTwoTrackedWindowsLeavesOneGroupAndReportsTheOtherGone`).
  - The room-rule join is not refused. It never takes a tracked standalone window and never passes on a closed group's identity. Its evidence is the same at the next update.
  - The Cmd-T opener is still taken. Its evidence is a shown tab absent from the previous CG list, and a Space switch cannot produce that.
- With Space data, a flagged update behaves exactly as an unflagged one (a local `blindSwitch = spaceChanged && spaces == nil`).
- The fold guard, in a flagged fallback update: an identity whose previous entry has the same shown tab keeps that entry unchanged. Any other folded identity gets no entry and starts at 1 at the next update.

## Deviations from Plan

None in behaviour. One test-only change:
- **[Rule 3 - Blocking, test]** The first draft of `SpaceSwitchMarksTests` called the mutating `take` inside `#expect`. The macro cannot do that ("cannot use mutating member on immutable value"). A small `takes(_:pid:reads:)` helper now returns the sequence of results, and each test compares it with the expected list. The RED record is from the run after that fix. Committed in `87bdba3`.

**Total deviations:** 1 (test compile fix). **Impact:** none on scope.

## Known limits

- **Closed: 02-14 SUMMARY known limit 3** ("Plan-check advisory: race without Space data"). It is closed for every update whose notification arrives first.
- **Done: the 02-16 SUMMARY item "Not done here (02-17)".**
- **Residual: a late notification.** A notification that reaches main only after the ingest of the update that already saw the new Space does not protect that update. A notification during the reads is covered by the generation rule. The test `knownLimitWithoutTheSpaceNotificationTheShownTwinTakesTheClosedGroup` pins this limit. It asserts a known limit, NOT desired behaviour: the twin wrongly inherits the closed group. Invert its expectation to the race's when this limit closes (likely with the Phase 6 window-to-Space map).
- **Residual: a refused handoff is final, not postponed.** When a real former tab is refused during a flagged fallback update, it never inherits the group later. It is reported as a new window, and the group closes through CloseRule. No window is lost, but the tile identity does not carry over.
- **Residual: a merge during a Space switch.** A Merge All Windows in the same update as a Space switch, without Space data, leaves the merged window tracked on its own (kept, never destroyed) until its tab is next shown. The fold guard then folds it as usual.
- **Residual: rapid switching.** Constant Space switching keeps deferring folds. Windows then stay tracked separately and are never lost (T-02-48).
- **Not refused: the room-rule join**, as Decisions explains.

## Issues Encountered

None.

## Threat Flags

None. The one new input is an in-process NSWorkspace notification, already in the plan's threat model (T-02-47). T-02-45 and T-02-46 are mitigated and covered by the race scenario in all three modes, the injected-notification marks test, and the fold and fold-guard tests.

## Human UAT (end of phase, Task 2 human-check)

1. Launch with `scripts/run-debug.sh --no-build --disable-private=Spaces`, so Debug shows "Spaces lookup: off, single Space".
2. Put a Safari window with two tabs on Space 1 and a single Safari window on Space 2, both at the same frame (Window > Fill on each).
3. On Space 1, close the whole tab group, then immediately switch to Space 2 (Control-Right Arrow).
4. Open Tracked Windows.
5. Repeat once without `--disable-private=Spaces`.

Expected in both runs: the group's row is gone, and the Space 2 window has its own row, added as a new window. No row shows it under the closed group's entry or creation order. This does not block the plan.

## User Setup Required

None.

## Next Phase Readiness

- All 17 Phase 2 plans have summaries. The next step is Phase 2 re-verification, including the human UAT items above and from 02-14 to 02-16.
- Phase 6's co-visibility window-to-Space map can build on the same notification. This plan keeps no Space history.

## Self-Check: PASSED

- FOUND: Sources/PaneEngine/SpaceSwitchMarks.swift, Tests/PaneEngineTests/SpaceSwitchMarksTests.swift, and tdd/02-17-task1-red.json, 02-17-task2-red.json, 02-17-task2-foldguard-red.json
- FOUND commits: 87bdba3, 946df0c, 9392512, 2a13fba (all ancestors of HEAD)
- No "RED stub", TODO, FIXME or placeholder left in the changed sources
- Every task's acceptance criteria and the plan-level verification commands were re-run and pass, as listed above

---
*Phase: 02-window-control*
*Completed: 2026-10-25*
