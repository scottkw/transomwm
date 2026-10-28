---
phase: 02-window-control
plan: 09
subsystem: window-tracking
tags: [accessibility, close-rule, cg-window-list, lock-screen, sleep, session-gate, id-reuse]

requires:
  - phase: 02-window-control (02-07)
    provides: AXWindowSystem with ResponsivenessTracker, in-flight gate and probe loop; AXAppThread element cache; fake hung/slow apps
  - phase: 02-window-control (02-06)
    provides: AppRegistry onStop(pid, terminated), RefreshScheduler, per-window AX hints, settle follow-up refreshes
provides:
  - CloseRule.decide / CloseDecision / AXWindowFact / AppLiveness / ClosedIDCache (PaneEngine, pure)
  - WindowTracker decides every known window with CloseRule; appTerminated(pid:context:), recheckTerminated(context:), knownWindowIDs(pid:), needsQuickRecheck(pid:)
  - AXAppThread.observe(known:) probes known windows that left AXWindows through the cached element
  - SessionGate (PaneMac) and AXWindowSystem pause/resume with sessionPaused events and inventory flag
  - FakeWindowSystem.close(_:), setLocked(_:gate:), terminate keeping CG entries, probes of unlisted windows
affects: [02-10, 02-11, 02-12, 02-13, tracked-windows-ui, lifecycle-sync, phase-3-tiling]

actuals:
  tokens: 11359
  tasks: 3
  commits: 7
plan_head_before: dcd2e7f3b1442b25ed612a3ac72034c3ce66715e
plan_head_after: f94155b07d834a54a96dff5cd36270a9c0b36ce4

tech-stack:
  added: []
  patterns:
    - "Upsert and decide are separate passes: listed reads update frame, kind and title; CloseRule alone sets state or removes a known window"
    - "A .recheck asks for a follow-up refresh after 250 ms, at most 8 times in a row, then the 5 s sweep takes over"
    - "SessionGate keeps one flag per signal family and fires callbacks only on the paused edge"

key-files:
  created:
    - Sources/PaneEngine/CloseRule.swift
    - Sources/PaneMac/SessionGate.swift
    - Tests/PaneEngineTests/CloseRuleTests.swift
    - Tests/PaneEngineTests/CloseScenarioTests.swift
    - Tests/PaneMacTests/SessionGateTests.swift
    - Tests/PaneMacIntegrationTests/CloseIntegrationTests.swift
  modified:
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/RefreshScheduler.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneFixtureApp/main.swift
    - Tests/PaneMacIntegrationTests/LiveTrackingTests.swift

key-decisions:
  - "02-09: a known window's state comes only from CloseRule; a new window starts from its snapshot"
  - "02-09: a .recheck triggers a follow-up refresh after 250 ms, up to 8 in a row (maxQuickRechecks), because WindowServer drops a closed window ~0.3 s after AX reports -25202"
  - "02-09: probed windows (left AXWindows) stay in the AXAppThread element cache while the tracker knows them, so every refresh can probe them"
  - "02-09: a quit app's windows are rechecked every 250 ms for 5 s, then after every refresh"
  - "02-09: A3 confirmed on macOS 27 while locked: CGSSessionScreenIsLocked = 1 and frontmost is com.apple.loginwindow"
  - "02-09: PaneFixtureApp frees a closed NSWindow; before, a closed fixture window stayed in the CG list forever"

patterns-established:
  - "Live tests of close behaviour need the fixture to release its windows; keeping the NSWindow alive keeps its CG entry"
  - "Hunk-level staging (git apply --cached) when one file carries two tasks' changes, verified by building the staged tree"

requirements-completed: [WIN-09, WIN-02]

coverage:
  - id: D1
    description: "One tested two-source close table: closed only on (AX invalid or app terminated) plus CG absence; paused, timeouts and other failures never change anything; minimised/hidden absent, fullscreen, present"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/CloseRuleTests.swift"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fake scenarios: a close is destroyed once, invalid-but-in-CG is kept until CG agrees, a hung app keeps its windows, terminate closes only after CG absence, lock blanking of 10 windows closes nothing (gate on and off), a reused id is a new window with a larger creationOrder, unlisted windows are probed"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/CloseScenarioTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "Live fixture: close noticed within 1 s (~0.35 s measured), SIGSTOP for 3 s removes nothing, hide-app .absent then .present, quit removes every window within 2 s"
    requirement: WIN-02
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/CloseIntegrationTests.swift#closeFreezeHideAndQuitAreDecidedByTwoSources()"
        status: pass
    human_judgment: false
  - id: D4
    description: "SessionGate pauses on any lock/sleep/session signal and resumes only when all clear, once per edge"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/SessionGateTests.swift"
        status: pass
    human_judgment: false
  - id: D5
    description: "Real lock (⌃⌘Q, 30 s) and system sleep (1 min) with 10 windows open: every Tracked Windows row survives, the footer briefly shows 'Refreshing after wake · ', nothing is moved or forgotten"
    requirement: WIN-09
    verification: []
    human_judgment: true
    rationale: "A real lock and sleep can't be triggered from automation (and must not be); D-14 manual UAT item"

duration: 19min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 09: Two-Source Close Rule and Session Gate Summary

**Pane now treats a window as closed only when two sources agree: AX says the element is gone (-25202) or NSWorkspace says the app quit, and the window has left the CG list. Timeouts, frozen apps, the lock screen and sleep never remove a window, and reconciliation pauses while the Mac is locked or asleep, with one full refresh 1.5 s after it wakes.**

## Performance

- **Duration:** 19 min
- **Started:** 2026-10-24T16:57:33Z
- **Completed:** 2026-10-24T17:17:31Z
- **Tasks:** 3
- **Files modified:** 16 (including 3 RED evidence records)

## Accomplishments
- `CloseRule.decide`: one exhaustive switch that mirrors the RESEARCH Pattern 4 table, which is also reproduced in its doc comment. `ClosedIDCache` keeps closed identities for 60 s.
- `WindowTracker` handles a refresh in two passes:
  - Listed reads update frame, kind and title.
  - `CloseRule` then decides every known window of the pid. A close removes the window, records it in the cache and emits `windowDestroyed`. A state decision emits `windowStateChanged`. Every other decision changes nothing.
  - A whole-app list failure, or a window with no answer, counts as timed out.
- Quits: `appTerminated` and `recheckTerminated` close a quit app's windows once the CG list agrees. The live system rechecks every 250 ms for 5 s after the quit, then after every refresh.
- `AXAppThread.observe(known:)` probes, through the cached element, each known window that left `AXWindows` (one AXRole read, `listedInAXWindows: false`). A closed window therefore answers -25202 instead of silently disappearing.
- `SessionGate` handles six signal families. While it is paused:
  - `AXWindowSystem` emits `sessionPaused(true)`, drops scheduled refreshes, stops the sweep and decides nothing.
  - On resume it waits 1.5 s with no new pause, refreshes every app once, then emits `sessionPaused(false)` and restarts the sweep.
  - The Tracked Windows footer's "Refreshing after wake · " prefix (02-08) now shows during that window.

## Task Commits

1. **Task 1 RED: failing close table and cache tests** - `2d29170` (test)
2. **Task 1 GREEN: close decision table and closed-ID cache** - `4e3d28b` (feat)
3. **Task 2 RED: failing close, blanking and id-churn scenarios** - `d6a91cf` (test)
4. **Task 2 GREEN: tracker close handling, cached-element probes, terminate rechecks** - `6adf68d` (feat)
5. **Task 2 fix: quick rechecks and a fixture that frees closed windows** - `729c197` (fix)
6. **Task 3 RED: failing session gate tests** - `bfb4519` (test)
7. **Task 3 GREEN: session gate, pause and post-resume refresh** - `f94155b` (feat)

No refactor commit was needed.

## TDD

- **Task 1 RED** (`2d29170`): 6 tests ran against a stub that returns `.noChange` and caches nothing.
  - `theTableDecides(row:)` failed for every row that expects something other than `.noChange`, and the cache containment tests failed on `#expect`. `RED_EVIDENCE_OK` (`tdd/02-09-task1-red.json`).
  - Semantic check: the build succeeded and the target tests failed on the planned values. `noSingleSourceEverCloses` and `purgeDropsExpiredEntries` passed against the stub, which is expected because they assert that nothing happens.
- **Task 1 GREEN** (`4e3d28b`): 20 table rows plus 5 cache and invariant tests pass.
- **Task 2 RED** (`d6a91cf`): 9 scenario tests ran against the never-closing tracker.
  - The 5 close-path tests failed on `#expect`. `RED_EVIDENCE_OK` (`tdd/02-09-task2-red.json`).
  - Semantic check: the 4 tests that passed (hung app, blanking with and without the gate, state transitions) hold for a tracker that never closes, as expected.
- **Task 2 GREEN** (`6adf68d`, then `729c197`): all scenarios pass. `729c197` added the bounded quick recheck and its own unit test, `QuickRecheckTests`.
- **Task 3 RED** (`bfb4519`): 7 tests ran against a never-pausing stub, and 6 failed on `#expect`. `RED_EVIDENCE_OK` (`tdd/02-09-task3-red.json`). The empty-dictionary case passed, as expected.
- **Task 3 GREEN** (`f94155b`): 7 of 7 pass.

## Files Created/Modified
- `Sources/PaneEngine/CloseRule.swift`: `AppLiveness`, `AXWindowFact`, `CloseDecision`, `CloseRule`, `ClosedIDCache`
- `Sources/PaneEngine/WindowTracker.swift`: decide pass, terminated pids, quick rechecks, `knownWindowIDs`
- `Sources/PaneMac/AX/AXAppThread.swift`: `observe(known:)` probes, cache keeps known unlisted elements
- `Sources/PaneMac/AXWindowSystem.swift`:
  - known IDs passed to `observe`
  - CG read after AX answers
  - late jobs dropped
  - terminate path and its recheck loop
  - gate wiring, `sessionPaused`, post-resume refresh
- `Sources/PaneMac/RefreshScheduler.swift`: `stop()`
- `Sources/PaneMac/SessionGate.swift`: the gate
- `Sources/PaneTestSupport/FakeWindowSystem.swift`: `close`, `setLocked(_:gate:)`, `terminate` through the tracker, unlisted probes, a shared `context()`
- `Sources/PaneFixtureApp/main.swift`: `close` releases the window
- `Tests/...`:
  - added `CloseRuleTests`, `CloseScenarioTests` (+ `QuickRecheckTests`), `SessionGateTests`, `CloseIntegrationTests`
  - removed the 02-06 placeholder `aDestroyedNotificationAloneNeverClosesAWindow`

## Decisions Made
See `key-decisions` in the frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A real close waited for the 5 s sweep**
- **Found during:** Task 2 (CloseIntegrationTests)
- **Issue:** WindowServer removes a closed window from the CG list about 0.3 s after AX reports -25202. The refresh triggered by the destroyed hint saw CG still present, decided `.recheck`, and nothing refreshed the app again until the sweep. The "within 1 s" truth failed.
- **Fix:** The tracker counts consecutive `.recheck` decisions per window. `needsQuickRecheck(pid:)` makes `AXWindowSystem` refresh again after 250 ms, at most 8 times in a row. A window that never settles is left to the sweep, so a permanently CG-absent window cannot cause a refresh storm.
- **Files modified:** Sources/PaneEngine/WindowTracker.swift, Sources/PaneMac/AXWindowSystem.swift, Tests/PaneEngineTests/CloseScenarioTests.swift
- **Verification:** `QuickRecheckTests`; live close noticed in about 0.35 s
- **Committed in:** 729c197

**2. [Rule 3 - Blocking] The fixture never really closed a window**
- **Found during:** Task 2
- **Issue:** `PaneFixtureApp` kept every `NSWindow` in `entries`. A closed fixture window therefore stayed alive and in the CG list for good (observed for more than 7.6 s), unlike a real app.
- **Fix:** `close` sets the entry's window to nil, so the window is freed. Indices stay stable.
- **Files modified:** Sources/PaneFixtureApp/main.swift
- **Committed in:** 729c197

**3. [Rule 1 - Bug] A late AX job could re-create a quit app's windows**
- **Found during:** Task 2
- **Issue:** A refresh still running when the app quit could ingest its result after the terminate path had already decided the app's windows.
- **Fix:** `refresh(pid:)` ingests only if `threads[pid] === thread`, the same guard the probe loop uses.
- **Committed in:** 6adf68d

**4. [Rule 1 - Correctness] CG is read after AX answers**
- **Found during:** Task 2
- **Issue:** The per-pid refresh took the CG snapshot before the AX job, which is the stalest possible second source for a close.
- **Fix:** The snapshot is now taken after `observe` returns. The sweep still shares one snapshot.
- **Committed in:** 6adf68d

**5. [Superseded test] Removed the 02-06 `aDestroyedNotificationAloneNeverClosesAWindow` live test**
- **Found during:** Task 2
- **Issue:** That test asserted that a closed fixture window stays tracked. It was a placeholder until this plan; the real close is now correctly reported.
- **Replacement coverage:**
  - The "notification alone never closes" property is covered by `anInvalidElementStillInTheCGListIsKeptUntilItLeaves` and `noSingleSourceEverCloses`.
  - The live close is covered by `CloseIntegrationTests`.
- **Committed in:** 6adf68d

**6. [Fake fidelity] Locked observations count as -25204 for responsiveness, and the fake probes unlisted windows**
- **Found during:** Task 2
- **Issue:** The fake has to drive the same decisions as the live system for lock blanking and for windows that leave `AXWindows`.
- **Fix:**
  - A locked observation is recorded as `cannotComplete`.
  - Known windows with `listedInAX == false` are probed with `listedInAXWindows: false`, as `AXAppThread` does.
  - `terminate(pid:)` no longer removes CG entries itself, so the plan's terminate scenario can test the CG lag.
- **Committed in:** 6adf68d

---

**Total deviations:** 6 (3 bugs/correctness, 1 blocking, 1 superseded test, 1 fake fidelity). **Impact:** no public contract changed beyond the plan's interfaces. Additions beyond the plan: `WindowTracker.needsQuickRecheck(pid:)`, `WindowTracker.maxQuickRechecks`, `ClosedIDCache.remove(_:)` and `RefreshScheduler.stop()`.

## Issues Encountered
- **The screen locked during execution** (`IOConsoleLocked = true`). Every live suite failed because AX reads were blanked, which is Pitfall 7 in real life, not a regression. The non-live suites were verified while it was locked. All live suites were re-run and passed after the screen was unlocked.
- **A3 verified at that moment, read-only:**
  - `CGSessionCopyCurrentDictionary()` contained `CGSSessionScreenIsLocked = 1` (plus `CGSSessionScreenLockedTime`).
  - The frontmost app was `com.apple.loginwindow`.
  - Both of the gate's polled signals therefore work on macOS 27.
- **Full `swift test` passes:** 142 model, 52 PaneMac, 11 integration (live, not skipped) and 99 engine tests. Release mode (`-c release -Xswiftc -enable-testing`, live suites skipped) also passes. No fixture process was left running.
- **Pre-existing release-build warning** in `PermissionReducer.swift:110`, outside this plan's scope. Logged in `deferred-items.md`.

## Human checks for phase UAT (end-of-phase)
1. **Lock and sleep (D-14, WIN-09, D5):**
   - Run Pane Debug with 10 windows open in several apps and open Tracked Windows.
   - Lock the screen (⌃⌘Q) for 30 s, then unlock.
   - Sleep the Mac from the Apple menu for a minute, then wake it.
   - **Expected:** all 10 rows remain after each cycle, the footer briefly shows "Refreshing after wake · " (about 1.5 s plus one refresh), and no window is moved or forgotten.
2. **Fast user switching (optional):** switch to another user and back. **Expected:** the same as check 1.

## Known Stubs
None introduced. `isKnownTabMember` is always false until Plan 10 supplies tab membership, as the plan specifies. `perform` still drops commands until Plan 12, which Plan 02-01 already recorded.

## Known Limits
- A lock signal is cleared only by its own counterpart notification. If `com.apple.screenIsUnlocked` were ever lost, Pane would stay paused until the next lock/unlock or sleep/wake cycle. This is fail-safe (nothing closes), and T-02-25 accepts it.
- Production close detection depends on the destroyed hint. Without a hint (for example a window whose notifications never registered), a close is found by the 5 s sweep.

## Threat Flags
None. T-02-24 and T-02-26 are mitigated as planned; T-02-25 is accepted as planned. There is no new trust boundary.

The flagged prohibition "never discard a tracked window because one source looked empty or timed out" is now verified by:
- `noSingleSourceEverCloses`, the lock-blanking scenarios with and without the gate, and the hung-app scenario
- the live SIGSTOP step

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Plan 10 (tabs):** pass `isKnownTabMember: true` for known tab members, so an invalid-but-in-CG tab becomes `.absent`. `knownWindowIDs` and the cached-element probes already cover hidden tabs that left `AXWindows`.
- **LifecycleSync:** now gets real `windowDestroyed` events. `.closed` reaches the World through `World.apply` (02-04).
- **Plan 12 (frame writes):** skip writes while `inventory().sessionPaused` is true.

## Self-Check: PASSED
- All 6 created files exist. Commits 2d29170, 4e3d28b, d6a91cf, 6adf68d, bfb4519, 729c197 and f94155b are on HEAD (7 = `git rev-list --count dcd2e7f..HEAD`).
- Every acceptance grep returns at least 1, and `scripts/check-no-appkit.sh` OK (20 files).
- `swift test --filter CloseRuleTests|CloseScenarioTests|SessionGateTests|CloseIntegrationTests` passes, integration not skipped. Full `swift test` passes.

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
