---
phase: 02-window-control
plan: 07
subsystem: window-tracking
tags: [accessibility, responsiveness, sigstop, coalescing, probe]

requires:
  - phase: 02-window-control (02-06)
    provides: RefreshScheduler, AppRegistry.onStop, hint loop after the initial sweep, AXAppThread element cache
  - phase: 02-window-control (02-01)
    provides: AppObservation.listFailure/duration, WindowInventory.degradedPIDs, WindowEvent.appResponsiveness, FakeApp.hung/responseDelay
provides:
  - ResponsivenessTracker / JobOutcome / ResponsivenessChange (PaneEngine, pure)
  - AXAppThread.probe() (AXRole only) and a stop token checked between AX calls in observe()
  - AXWindowSystem degraded handling: one in-flight job per pid, one coalesced follow-up, 2 s probe loop, degradedPIDs in inventory()
  - FakeWindowSystem hung/slow simulation through the same tracker
affects: [02-08, 02-09, 02-10, 02-12, status-menu, planner]

actuals:
  tokens: 8000
  tasks: 2
  commits: 3
plan_head_before: 5404b58b253e3a5c4da872c12c4095c84c7fbf1f
plan_head_after: bcdd4455d6b612594d8e3c28d22086789091dbab

tech-stack:
  added: []
  patterns:
    - "Every AX job result (refresh or probe) goes through ResponsivenessTracker.record; only transitions emit events"
    - "Refresh requests pass one gate: dropped while degraded, collapsed into a follow-up while a job is in flight"
    - "A degraded app has its own probe Task; the sweep never awaits it"

key-files:
  created:
    - Sources/PaneEngine/ResponsivenessTracker.swift
    - Tests/PaneEngineTests/ResponsivenessTrackerTests.swift
    - Tests/PaneEngineTests/ResponsivenessScenarioTests.swift
    - Tests/PaneMacIntegrationTests/FreezeIntegrationTests.swift
  modified:
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift

key-decisions:
  - "A degraded app is probed by its own 2 s loop, not by the 5 s sweep, so a resumed app recovers within about 2 s"
  - "observe() times the whole job (AXHidden + AXWindows + window reads), so one SIGSTOPped job (~2 s) degrades the app at once"
  - "A slow success while degraded keeps the app degraded; only a success within 1.5 s recovers it"
  - "The job token is the thread's stop flag: with one in-flight job per pid no job is ever superseded"

patterns-established:
  - "Freeze tests SIGSTOP only a fixture they launched and resume it in a defer before terminating it"

requirements-completed: [WIN-03]

coverage:
  - id: D1
    description: "One tested degraded/recovered rule: 2 consecutive -25204 or one job > 1.5 s (exactly 1.5 s does not), probe every 2 s, fast success recovers, forget clears"
    requirement: WIN-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ResponsivenessTrackerTests.swift"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fake hung and slow apps go through the same tracker: only the hung app is degraded, keeps its window, does not delay another app's new window, and recovers at the first probe 2 s later"
    requirement: WIN-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ResponsivenessScenarioTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "With a SIGSTOPped fixture: inventory() < 50 ms, the other fixture's new window tracked within 1 s, degraded within 5 s, window kept, refreshAll() < 500 ms while degraded, recovered within 4 s of SIGCONT"
    requirement: WIN-03
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FreezeIntegrationTests.swift#aStoppedAppNeitherStallsPaneNorDelaysAnotherApp()"
        status: pass
    human_judgment: false
  - id: D4
    description: "Real kill -STOP on a user app (TextEdit) with Pane Debug: menu opens instantly, shows 1 app not responding within about 5 s plus up to one 5 s sweep, line disappears within about 4 s of CONT"
    requirement: WIN-03
    verification: []
    human_judgment: true
    rationale: "ROADMAP SC4 names a real kill -STOP on a user app and the status menu line; needs the signed app and a human (end-of-phase UAT)"

duration: 10min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 07: Unresponsive Apps Summary

**A frozen app is marked degraded after 2 consecutive -25204 results or one job over 1.5 s. From then on Pane only probes its AXRole every 2 s, and the first fast answer brings it back. Every other app keeps being tracked at full speed, which a SIGSTOP integration test checks.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-10-24T16:27:37Z
- **Completed:** 2026-10-24T16:38:29Z
- **Tasks:** 2
- **Files modified:** 9 (plus the RED evidence record)

## Accomplishments
- `ResponsivenessTracker` in PaneEngine (Foundation-free, `Equatable`, `Sendable`). It keeps a per-pid failure count, the time of the last attempt and the degraded set. `record` returns a change only on a transition.
- `FakeWindowSystem` handles hung and slow apps with that tracker. A hung job is `cannotComplete` with a 1 s simulated duration, and its observation never reaches `WindowTracker`. A slow job's duration is its `responseDelay`. A degraded app is skipped until its probe is due. `inventory().degradedPIDs` is filled in.
- `AXAppThread.probe()` reads only `AXRole`, timed with `ContinuousClock`. `observe()` now times the whole job and checks the stop flag between AX calls.
- `AXWindowSystem`:
  - Every job goes through `responsiveness.record`, and `appResponsiveness` is emitted once per transition.
  - Each pid has at most one job in flight; a request while one runs becomes a single follow-up.
  - Refreshes for a degraded app are dropped and the sweep skips it. Its probe loop runs every 2 s, and a recovery schedules an immediate full refresh.
  - When an app stops, all of its state is forgotten.

## Task Commits

1. **Task 1 RED: failing tracker and fake scenario tests** - `576c0dd` (test)
2. **Task 1 GREEN: tracker and hung/slow fake apps** - `5f8bcab` (feat)
3. **Task 2: degraded apps in the live system + SIGSTOP test** - `bcdd445` (feat)

No refactor commit was needed.

## TDD

- **RED** (`576c0dd`): 14 tests ran against a `ResponsivenessTracker` stub that compiles and decides nothing. 9 failed on `#expect`: every degrade, probe and recover row, and the fake's `degradedPIDs` and events. The classifier returned `RED_EVIDENCE_OK` (`.planning/phases/02-window-control/tdd/02-07-task1-red.json`).
  - Semantic check: the build succeeded and the target tests failed on the planned values.
  - The 5 tests that passed hold for a stub that does nothing, as expected: a single failure, the reset, a healthy app, forget, and the full refresh after un-hanging.
- **GREEN** (`5f8bcab`): the real rule plus the fake wiring. 19 tests pass across the tracker, scenario and existing fake suites.
- Task 2 is `type="auto"` with no `tdd` flag, so its integration test was written alongside the code.

## Files Created/Modified
- `Sources/PaneEngine/ResponsivenessTracker.swift`: `JobOutcome`, `ResponsivenessChange`, `ResponsivenessTracker`
- `Sources/PaneTestSupport/FakeWindowSystem.swift`: hung/slow simulation, probe, `degradedPIDs`, `hungJobDuration`
- `Sources/PaneMac/AX/AXAppThread.swift`: `probe()`, the stop token, and whole-job `duration`
- `Sources/PaneMac/AX/AXSnapshotReader.swift`: the internal `observeApp` takes `isCancelled`, checked before each window read
- `Sources/PaneMac/AXWindowSystem.swift`: tracker, in-flight gate, probe loop, `degradedPIDs`
- `Tests/PaneEngineTests/ResponsivenessTrackerTests.swift`, `Tests/PaneEngineTests/ResponsivenessScenarioTests.swift`, `Tests/PaneMacIntegrationTests/FreezeIntegrationTests.swift`

## Decisions Made
See `key-decisions` in the frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Correctness] Probes run in their own 2 s loop, not in the 5 s sweep**
- **Found during:** Task 2
- **Issue:** The plan has the sweep call `probe()` when `needsProbe`. The sweep runs every 5 s, so a resumed app could take up to 5 s to recover. That breaks the "recovered within 4 s" truth.
- **Fix:** Degrading an app starts a per-pid `Task` that sleeps `probeInterval`, checks `needsProbe` and probes. It ends when the app recovers or stops. The sweep just skips degraded apps.
- **Files modified:** Sources/PaneMac/AXWindowSystem.swift
- **Committed in:** bcdd445

**2. [Rule 3 - Blocking] The freeze test starts the sweep itself after SIGSTOP**
- **Found during:** Task 2
- **Issue:** A stopped app sends no AX notifications. Pane only learns it is frozen when a job for it times out, and only the 5 s sweep sends that job. Worst case, detection takes the sweep interval plus about 2 s for the job, which can exceed the test's 5 s window.
- **Fix:** Right after `SIGSTOP`, the test runs `Task { await system.refreshAll() }`, which is the sweep's own call, started now and not awaited. Detection then takes about 2 s.
- **Production limit:** detection latency is at most 5 s (sweep) plus about 2 s (job). The UAT step below says so.
- **Files modified:** Tests/PaneMacIntegrationTests/FreezeIntegrationTests.swift
- **Committed in:** bcdd445

**3. [Rule 3 - Blocking] `AXSnapshotReader.observeApp` gained a cancellation check**
- **Found during:** Task 2
- **Issue:** The job token has to be checked between window reads, and those happen inside `AXSnapshotReader`, a file the plan does not list.
- **Fix:** The internal overload takes `isCancelled: () -> Bool` (default never) and returns nil once cancelled. The public `observeApp(pid:bundleID:)` used by pane-dump is unchanged.
- **Committed in:** bcdd445

**4. [Rule 2 - Verification] Checked the flagged prohibition**
- **Found during:** Task 2
- **Issue:** The prohibition "MainActor code must never await a specific app's AX job in a way that blocks other apps or the UI" was `status: unverified`.
- **Fix:** While the app is degraded, the freeze test also checks that a full `refreshAll()` finishes in under 500 ms. It already checked that `inventory()` stays under 50 ms both while the stopped app's first job is in flight and while the app is degraded.
- **Committed in:** bcdd445

---

**Total deviations:** 4 (1 correctness, 2 blocking, 1 added verification). **Impact:** no public contract changed beyond the plan's interfaces. The production detection limit is documented under deviation 2.

## Issues Encountered
- None. The freeze test passed 4 runs in a row, about 5.5 s each. `LiveTrackingTests` and `FixtureTrackingTests` still pass (8 tests).
- The full `swift test` passes: 142 model, 15 PaneMac, 11 integration and 83 engine tests. No fixture process was left running or stopped (`ps` checked after the runs).

## Human checks for phase UAT (end-of-phase)
1. **Real kill -STOP (ROADMAP SC4, D4):**
   - Run Pane Debug and open TextEdit and Safari windows.
   - Run `kill -STOP <TextEdit pid>`, open a new Safari window, then open Pane's menu.
   - Expected: the menu opens instantly and the new Safari window is counted within a second. "1 app not responding" appears within about 2 s of Pane's next 5 s sweep, so up to about 7 s after the STOP.
   - Then run `kill -CONT <TextEdit pid>`. Expected: the line disappears within about 4 s, and TextEdit's windows were never dropped.

## Known Stubs
None introduced. `perform` still drops commands until Plan 02-12, which Plan 02-01 already recorded.

## Threat Flags
None. T-02-19 and T-02-20 are mitigated as planned: one in-flight job per pid, an AXRole-only probe, a stop token between AX calls, and a sweep that never awaits a degraded app. No new trust boundary was added.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The status menu's existing `degradedLine` now gets real `degradedPIDs` from the live system.
- Plan 09 (close rule) can rely on this: a timeout never reaches `WindowTracker` as a removal, and a degraded app's windows keep their last values.
- Plan 12 (frame writes) should keep only the latest frame per window for a degraded app and flush it on `appResponsiveness(pid, false)`.

## Self-Check: PASSED
- All 4 created files exist. Commits 576c0dd, 5f8bcab and bcdd445 are on HEAD.
- Every acceptance grep returns 1. `scripts/check-no-appkit.sh` OK (19 files).
- `swift test --filter "ResponsivenessTrackerTests|ResponsivenessScenarioTests|FreezeIntegrationTests"` passes with integration not skipped, and the full `swift test` passes.

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
