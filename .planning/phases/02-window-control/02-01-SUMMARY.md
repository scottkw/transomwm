---
phase: 02-window-control
plan: 01
subsystem: window-control
tags: [swift, accessibility, axuielement, cfrunloop, dlsym, swift-testing, appkit]

requires:
  - phase: 01-layout-model
    provides: "PaneModel (Rect, WindowIdentity, WindowRef, WindowState) and the draft PaneEngine WindowSystem contract"
provides:
  - "Revised WindowSystem contract: WindowKind, NeverDockReason, WindowIDSource, extended WindowInfo/WindowInventory/WindowEvent, windowInfo(_:), synthetic ID range"
  - "WindowSnapshot / AppObservation / CGWindowEntry / ObservationContext / FrameWriteResult / AXFailure fact types"
  - "Pure WindowTracker shared by the live and fake window systems"
  - "PanePrivate: Capability registry, --disable-private parsing, dlopen/dlsym _AXUIElementGetWindow"
  - "PaneMac: AXAppThread (per-app thread + CFRunLoop), AXSnapshotReader, AXWindowSystem, PaneMacApp"
  - "PaneApp executable with --print-inventory-summary"
  - "PaneTestSupport.FakeWindowSystem (actor) over the real tracker"
  - "PaneFixtureApp with every window shape and a stdin command channel; FixtureProcess/IntegrationEnv helpers"
affects: [02-02, 02-03, 02-06, 02-07, 02-08, 02-09, 02-10, 02-11, 02-12, 02-13, phase-03]

actuals:
  tokens: 20039
  tasks: 3
  commits: 4
plan_head_before: cd96b381abf546627e66970f50c41c3db617d8be
plan_head_after: 3e15c8eb68042b5a6f4e380388c69aad541f3b2e

tech-stack:
  added: []
  patterns:
    - "Per-app AXAppThread: nonisolated @unchecked Sendable class, AX objects thread-confined, jobs via CFRunLoopPerformBlock + CheckedContinuation, enqueue/stop under one OSAllocatedUnfairLock"
    - "Private APIs as static optional @convention(c) pointers loaded by explicit dlopen + dlsym, gated by Capabilities.isForcedOff"
    - "AX errors kept as AXFailure (invalidElement vs cannotComplete), never collapsed to nil, including per-attribute errors in batched reads"
    - "Live and fake window systems share one pure WindowTracker; the fake builds AppObservations from a simulated OS"
    - "Fixture stdin protocol: a command's window lines come before its ok/error line, which terminates the reply"

key-files:
  created:
    - Sources/PanePrivate/Capabilities.swift
    - Sources/PanePrivate/AXWindowID.swift
    - Sources/PaneEngine/WindowSnapshot.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneApp/main.swift
    - Sources/PaneFixtureApp/main.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Tests/PaneMacIntegrationTests/IntegrationSupport.swift
    - Tests/PaneMacIntegrationTests/FixtureTrackingTests.swift
    - Tests/PaneMacIntegrationTests/FixtureShapesTests.swift
    - Tests/PaneEngineTests/WindowTrackerTests.swift
    - Tests/PaneEngineTests/FakeWindowSystemTests.swift
    - Tests/PaneMacTests/CapabilitiesTests.swift
    - .planning/phases/02-window-control/tdd/02-01-red.json
  modified:
    - Package.swift
    - Sources/PaneEngine/WindowSystem.swift
    - Tests/PaneModelTests/NoAppKitTests.swift
    - .github/workflows/ci.yml

key-decisions:
  - "AXAppThread signals ready right after capturing its run loop and installs the AX observer afterwards, because AXObserverAddNotification is IPC that can block on a hung app and init runs on main"
  - "WindowTracker keeps a window's known kind while it is absent (minimised or app hidden), since subrole reads AXDialog then (Pitfall 3); Plan 03's classifier replaces the rule but keeps the stickiness"
  - "WindowTracker skips a new window whose frame could not be read; a later refresh picks it up"
  - "Fixture prints a command's window lines before its ok line so FixtureProcess.send returns every line the command produced; FixtureProcess.launch reads windows with list after ready"
  - "Fixture quits on stdin EOF so a crashed test run never leaves fixture windows behind"
  - "PaneApp summary counts apps as distinct pids among tracked windows"

patterns-established:
  - "Integration helpers in a test target without NonisolatedNonsendingByDefault use nonisolated(nonsending) async functions so MainActor tests can pass non-Sendable closures"
  - "AppKit + HIToolbox export a WindowRef type, so PaneMac names PaneModel.WindowRef explicitly where both are visible"

requirements-completed: [WIN-02, SAFE-05]

coverage:
  - id: D1
    description: "A real fixture window is tracked end to end (AXAppThread -> AXSnapshotReader + PanePrivate ID -> WindowTracker -> AXWindowSystem inventory) with its real CGWindowID, pid, unbundled bundle key, .present state, .axPrivate source and frame within 1 pt"
    requirement: WIN-02
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FixtureTrackingTests.swift#aFixtureWindowIsTrackedWithItsRealIDPidFrameAndState"
        status: pass
    human_judgment: false
  - id: D2
    description: "PaneApp --print-inventory-summary prints `pane: tracked windows=N apps=M` from a trusted terminal and exits 0"
    requirement: WIN-02
    verification:
      - kind: other
        ref: "swift run PaneApp --print-inventory-summary | grep -E '^pane: tracked windows=[0-9]+ apps=[0-9]+$'"
        status: pass
    human_judgment: false
  - id: D3
    description: "WindowTracker behaviour: create, no-op repeat, move, minimise to absent with sticky kind, non-windows/nil IDs/failed reads ignored, identical frames stay two entries, identity ordering, missing windows never closed"
    requirement: WIN-02
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/WindowTrackerTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "FakeWindowSystem drives the production WindowTracker from a simulated OS (events, inventory, windowInfo, hung app, perform log)"
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FakeWindowSystemTests.swift"
        status: pass
    human_judgment: false
  - id: D5
    description: "--disable-private parsing accepts only known capability names and reports unknown ones; every capability is reported"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/CapabilitiesTests.swift"
        status: pass
    human_judgment: false
  - id: D6
    description: "_AXUIElementGetWindow reached only by dlopen/dlsym; --disable-private=AXWindowID makes it nil (PaneApp then tracks 0 windows until the Plan 11 fallback)"
    requirement: SAFE-05
    verification:
      - kind: other
        ref: "swift run PaneApp --print-inventory-summary --disable-private=AXWindowID,Bogus -> pane: tracked windows=0 apps=0"
        status: pass
    human_judgment: false
  - id: D7
    description: "Fixture opens every window shape with distinct IDs and obeys move/list/quit"
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FixtureShapesTests.swift#theFixtureOpensEveryWindowShapeAndObeysCommands"
        status: pass
    human_judgment: false
  - id: D8
    description: "PaneTestSupport and PanePrivate import no UI framework; CI never runs the AX fixture suite"
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/NoAppKitTests.swift#testSupportAndPrivateAreClean"
        status: pass
      - kind: other
        ref: "ruby ci.yml check (PANE_SKIP_AX_INTEGRATION=1) -> ci.yml OK"
        status: pass
    human_judgment: false
  - id: D9
    description: "Capability report is logged once at launch to Logger(subsystem com.eightabyte.pane, category private) with .public privacy"
    requirement: SAFE-05
    verification: []
    human_judgment: true
    rationale: "Unified-log output is not asserted by any test; check with `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 5m` after a launch during phase UAT"

duration: 14min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 01: Window-control tracer Summary

**A fixture window travels fixture -> per-app AXAppThread -> batched AX snapshot plus dlsym'd `_AXUIElementGetWindow` -> pure WindowTracker -> AXWindowSystem cache, with its real CGWindowID, pid and frame. A FakeWindowSystem runs the same tracker over a simulated OS, and a fixture app with every window shape takes stdin commands.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-10-24T15:07:06Z
- **Completed:** 2026-10-24T15:21:05Z
- **Tasks:** 3
- **Files modified:** 22

## Accomplishments
- The revised WindowSystem contract (all `<interfaces>` names) plus the Codable AX fact types, so later plans only add behaviour
- One thread per app, each with its own CFRunLoop. The 1.0 s global AX timeout is set once. Pane's own pid and loginwindow are skipped, and `inventory()` never waits for an app
- The PanePrivate capability registry with `--disable-private` and a dlopen/dlsym window-ID shim; nothing private is linked at link time
- The FakeWindowSystem actor over the production tracker, plus new PaneEngineTests and PaneMacTests targets
- The fixture app covers standard, nofullscreen, borderless-floating, utility-panel, sheet, minsize and tabs windows, and takes 11 stdin commands

## Task Commits

1. **Task 1: Tracer, a fixture window tracked end to end** - `f5d6fc1` (feat)
2. **Task 2: FakeWindowSystem + engine/Mac unit-test targets** - `d556f43` (test, RED), `f161188` (feat, GREEN)
3. **Task 3: Fixture app with every window kind + stdin channel** - `3e15c8e` (feat)

Tracer gate: interactive, end-of-phase, automated-only verify. The tracer verify was re-run and passed (FixtureTrackingTests, summary line), so expansion continued with no checkpoint.

## TDD Gate Compliance (Task 2)

- **RED** `d556f43`: `swift test --filter PaneEngineTests` exited 1. The classifier returned `RED_EVIDENCE_OK` (swift-testing, 14 tests, 4 failing) for target `openingAWindowAndRefreshingYieldsWindowCreated()`. Record: `.planning/phases/02-window-control/tdd/02-01-red.json`. Semantic assessment: the build succeeded, and the target ran and failed on its planned assertion. No `.windowCreated` arrived because the committed FakeWindowSystem API skeleton has empty bodies. The 4 failures are exactly the Fake behaviours.
- **GREEN** `f161188`: all 14 PaneEngineTests pass.
- **REFACTOR:** none needed.
- WindowTracker and `Capabilities.parseDisabled` were built in Task 1, as the plan specifies, so their Task 2 tests are characterization tests that passed from the start. Only FakeWindowSystem went through a true RED.

## Files Created/Modified
- `Package.swift` - PanePrivate, PaneMac (plus a library product), PaneApp, PaneFixtureApp, PaneTestSupport and three test targets; PaneModel and PaneEngine are unchanged
- `Sources/PaneEngine/WindowSystem.swift` - revised contract, with defaulted new fields so the old initialisers still compile
- `Sources/PaneEngine/WindowSnapshot.swift` - AX fact types shared by the live reader, the fake and the corpus
- `Sources/PaneEngine/WindowTracker.swift` - the pure observation-to-WindowInfo/events core
- `Sources/PanePrivate/{Capabilities,AXWindowID}.swift` - registry, flag parsing, launch log and window-ID shim
- `Sources/PaneMac/AX/AXAppThread.swift` - the per-app thread with its own run loop, kAXWindowCreated hints and teardown on the thread
- `Sources/PaneMac/AX/AXSnapshotReader.swift` - one batched read of 15 attributes, then buttons and children (tab group, sheet)
- `Sources/PaneMac/AXWindowSystem.swift` - the MainActor WindowSystem: app enumeration, concurrent sweep, cached inventory
- `Sources/PaneMac/PaneMacApp.swift`, `Sources/PaneApp/main.swift` - the entry point and `--print-inventory-summary`
- `Sources/PaneFixtureApp/main.swift` - window shapes and the stdin protocol
- `Sources/PaneTestSupport/FakeWindowSystem.swift` - the simulated OS
- `Tests/PaneMacIntegrationTests/*` - IntegrationEnv, FixtureProcess, waitUntil, FixtureTrackingTests, FixtureShapesTests
- `Tests/PaneEngineTests/*`, `Tests/PaneMacTests/CapabilitiesTests.swift`, `Tests/PaneModelTests/NoAppKitTests.swift`, `.github/workflows/ci.yml`

## Decisions Made
See `key-decisions` in the frontmatter. The most important one: `AXAppThread.init` returns as soon as the thread's run loop exists, and the observer is registered on the thread afterwards. Without that, creating a thread for a hung app would block main for up to the AX timeout.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `WindowRef` is ambiguous in PaneMac**
- **Found during:** Task 1
- **Issue:** AppKit/HIToolbox also export a `WindowRef` type, so `windowInfo(_ window: WindowRef)` failed to compile in AXWindowSystem
- **Fix:** spelled `PaneModel.WindowRef` there. The PaneEngine protocol keeps the exact signature the acceptance grep checks.
- **Files modified:** Sources/PaneMac/AXWindowSystem.swift
- **Committed in:** f5d6fc1

**2. [Rule 3 - Blocking] Test-target async helpers are @concurrent by default**
- **Found during:** Task 1
- **Issue:** without `NonisolatedNonsendingByDefault` in the integration test target, `waitUntil` was `@concurrent`, so MainActor tests could not pass it non-Sendable closures
- **Fix:** marked `waitUntil`, `FixtureProcess.launch` and `send` `nonisolated(nonsending)`
- **Files modified:** Tests/PaneMacIntegrationTests/IntegrationSupport.swift
- **Committed in:** f5d6fc1, 3e15c8e

**3. [Rule 1 - Bug] Kind would flip to never-dock when a window is minimised**
- **Found during:** Task 1
- **Issue:** the plan's interim rule (`AXStandardWindow` means dockable, anything else means `.neverDock(.subrole)`) would demote a minimised window, because its subrole reads AXDialog (RESEARCH Pitfall 3)
- **Fix:** the tracker keeps the known kind while the window is absent. This is covered by `aMinimizedSnapshotChangesTheStateToAbsentAndKeepsTheKind`.
- **Files modified:** Sources/PaneEngine/WindowTracker.swift
- **Committed in:** f5d6fc1

**4. [Protocol ordering] Fixture command replies end with ok/error**
- **Found during:** Task 3
- **Issue:** the plan text has `ok` followed by fresh window lines, which would leave `send()` unable to tell when a reply is complete
- **Fix:** a command's window lines are printed before its `ok <command>` line, and the error form is `error <command>: <message>`. `launch` reads windows with `list` after `ready` instead of counting lines per spec.
- **Files modified:** Sources/PaneFixtureApp/main.swift, Tests/PaneMacIntegrationTests/IntegrationSupport.swift
- **Committed in:** 3e15c8e

---

**Total deviations:** 4 (2 blocking, 1 bug, 1 protocol ordering). **Impact:** none changes a public contract name. The fixture protocol change matters to later plans: they read a command's window lines before its `ok`.

## Issues Encountered
- `swift run PaneApp --print-inventory-summary` reports `windows=1 apps=1` on this Mac. A direct AX probe confirmed it: most running apps list 0 AX windows on the current Space, and Finder's only entry is the desktop `AXScrollArea`, which is filtered on purpose. Windows on other Spaces wait for Phase 6.
- With `--disable-private=AXWindowID` the summary shows 0 windows. That is expected: the fallback matcher comes in Plan 11.

## Known Stubs
- `Sources/PaneMac/AXWindowSystem.swift:66` - `perform` logs and drops commands until the frame write pipeline (Plan 02-12). Recorded in `.planning/WINDOWS.md`.
- `AXWindowSystem.hints` is produced but not consumed until the refresh scheduler arrives (Plan 06). `WindowTracker.settleDelay` is stored but unused until classification scheduling (Plans 03/06). `ObservationContext` is ignored by the tracker until close and fallback rules (Plans 09/11). None of these blocks this plan's goal.

## Human checks for phase UAT (end-of-phase)
- Capability report in the unified log after a launch (coverage D9): `log show --predicate 'subsystem == "com.eightabyte.pane" AND category == "private"' --last 5m` should show `AXWindowID: available`. With `--disable-private=AXWindowID,Bogus` it should show `off` plus an error line for `Bogus`.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plans 02-02..02-13 can build on the contract, tracker, AX thread, fake and fixture without renaming anything
- Integration tests rely on this terminal's Accessibility trust. CI skips them through `PANE_SKIP_AX_INTEGRATION`.

## Self-Check: PASSED
- All 17 created source and test files exist on disk
- Commits f5d6fc1, d556f43, f161188 and 3e15c8e are ancestors of HEAD; evaluation-scope resolves them for 02-01
- `swift test` and `swift test -c release -Xswiftc -enable-testing` pass (142 + 2 + 2 + 14 tests, with the integration suites running, not skipped). `scripts/check-no-appkit.sh` is OK. Every acceptance grep meets its threshold.

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
