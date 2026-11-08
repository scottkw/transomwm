---
phase: 02-window-control
plan: 06
subsystem: window-tracking
tags: [accessibility, axobserver, nsworkspace, coordinates, displays, debounce]

requires:
  - phase: 02-window-control (02-03)
    provides: WindowTracker settle delay and hasPendingWindows, AXWindowSystem with one CG list per refresh
  - phase: 02-window-control (02-01)
    provides: AXAppThread, AXEventHint, DisplayInfo, ObservationContext.displays, FakeWindowSystem
provides:
  - Coordinates.topLeft(fromAppKit:primaryHeight:) / appKit(fromTopLeft:primaryHeight:) / displayUUID(for:among:)
  - Displays.current() and Displays.localizedNames() (public, PaneMac)
  - WindowInfo.displayUUID set on every upsert; a display change emits windowChanged
  - AppRegistry (NSWorkspace lifecycle, Pitfall 11 re-checks)
  - RefreshScheduler (per-pid cancel-latest, scheduleAll, periodic sweep, cancel)
  - AXEventHint.windowID from the thread's element cache; per-window AX notifications
  - appLaunched / appTerminated / windowFocused / displaysChanged events from AXWindowSystem
  - FakeWindowSystem.setDisplays(_:)
affects: [02-07, 02-08, 02-09, 02-10, 02-11, 02-12, tracked-windows-ui, close-rule]

actuals:
  tokens: 11000
  tasks: 2
  commits: 3
plan_head_before: 7225c0edb5846019e731b05db2631945a58465c3
plan_head_after: b8ce33007f1203208947981ad4652bec26406436

tech-stack:
  added: []
  patterns:
    - "Coordinates is the only place y is flipped; AX/CG/CGDisplayBounds values are used as they are"
    - "AX notifications are hints: each only schedules a cancel-latest per-pid refresh"
    - "A refresh that finds a pending (settling) window schedules its own follow-up at tracker.settleDelay"
    - "NSWorkspace / NotificationCenter observers on queue .main, bridged with MainActor.assumeIsolated; extract Sendable values from the Notification first"

key-files:
  created:
    - Sources/PaneEngine/Coordinates.swift
    - Sources/PaneMac/Displays.swift
    - Sources/PaneMac/AX/AppRegistry.swift
    - Sources/PaneMac/RefreshScheduler.swift
    - Tests/PaneEngineTests/CoordinatesTests.swift
    - Tests/PaneEngineTests/TrackerDisplayTests.swift
    - Tests/PaneMacIntegrationTests/LiveTrackingTests.swift
  modified:
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift

key-decisions:
  - "AppRegistry's onStop is (pid, terminated) so AXWindowSystem emits appTerminated only for a quit, not when an app merely stops being .regular"
  - "Public refreshAll() (and so the 5 s sweep and the 500 ms display refresh) re-reads displays and re-checks the registry before refreshing every app"
  - "Apps already running when start() is called get threads but no appLaunched event; appLaunched means launched after Pane started"
  - "The hint loop starts only after the initial sweep, so no per-pid refresh races the initial (no-settle) ingest"
  - "Displays is public so the integration test can check a window's UUID against it independently of the inventory"

patterns-established:
  - "Live integration tests start AXWindowSystem first, then launch the fixture, and filter events by the fixture's pid (suites run in parallel)"

requirements-completed: [WIN-02, WIN-04]

coverage:
  - id: D1
    description: "One tested AppKit to top-left conversion and display assignment by largest intersection, nearest centre, smaller UUID"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/CoordinatesTests.swift"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every tracked window carries its display UUID; a move to another display updates it and emits windowMoved and windowChanged; the fake reports its displays"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TrackerDisplayTests.swift"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/LiveTrackingTests.swift#theWindowCarriesItsDisplayUUID()"
        status: pass
    human_judgment: false
  - id: D3
    description: "Apps launched and windows opened after Pane started are tracked (within 2 s and 1 s); moves and minimises are reported within 1 s; quitting emits appTerminated within 2 s"
    requirement: WIN-02
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/LiveTrackingTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "A destroyed notification alone never closes or removes a tracked window"
    requirement: WIN-02
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/LiveTrackingTests.swift#aDestroyedNotificationAloneNeverClosesAWindow()"
        status: pass
    human_judgment: false
  - id: D5
    description: "Display UUIDs and frames are correct on real multi-display arrangements (external above, left, below) and after plugging or unplugging a display"
    requirement: WIN-04
    verification: []
    human_judgment: true
    rationale: "Only one built-in display is attached here; arrangement and hot-plug behaviour need real hardware"
  - id: D6
    description: "windowFocused is emitted after a focus change, and an app that changes activation policy gains or loses its thread"
    verification: []
    human_judgment: true
    rationale: "Implemented but not asserted by any test; the fixture cannot change its activation policy and focus hints for brand-new windows can arrive before the element is cached"

duration: 10min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 06: Live Display-Aware Tracking Summary

**Live tracking: NSWorkspace lifecycle and per-window AX notifications drive per-pid cancel-latest refreshes (75 ms, 250 ms settle follow-up, 5 s sweep), and every window is keyed to a display UUID through one tested coordinate flip**

## Performance

- **Duration:** 10 min
- **Started:** 2026-10-24T16:12:54Z
- **Completed:** 2026-10-24T16:23:40Z
- **Tasks:** 2
- **Files modified:** 13 (including the RED evidence record)

## Accomplishments
- `Coordinates`: `y_top = H_primary − (y + h)` in one place, round-tripping exactly, plus `displayUUID(for:among:)`
- `Displays.current()`: UUIDs from `CGDisplayCreateUUIDFromDisplayID`, frames from `CGDisplayBounds`, visibleFrame through `Coordinates`. A display with no UUID is skipped and logged.
- The tracker assigns `displayUUID` on every upsert. `inventory().displays` is populated in both the live system and the fake.
- `AXAppThread` caches window elements and registers destroyed, moved, resized, miniaturized, deminiaturized and title-changed on each one. App-level registrations: created, focused-window, main-window, hidden and shown. Hints carry `windowID`, resolved by `CFEqual`.
- `RefreshScheduler` and `AppRegistry` take over app enumeration from `AXWindowSystem.start()`. Launch, quit, hint, settle follow-up and the sweep all go through them.

## Task Commits

1. **Task 1 RED: failing coordinate and display tests** - `57c1f7b` (test)
2. **Task 1 GREEN: one coordinate boundary and display UUIDs on every window** - `cdbdf93` (feat)
3. **Task 2: live tracking (app lifecycle, AX hints, cancel-latest refresh, sweep)** - `b8ce330` (feat)

No refactor commit was needed.

## TDD

- **RED** (`57c1f7b`): `CoordinatesTests` and `TrackerDisplayTests` ran against a `Coordinates` stub that compiles and returns its input or nil. 7 of 9 tests failed on `#expect` assertions: 4 of 5 conversion vectors, every displayUUID rule, and both tracker display tests. The classifier returned `RED_EVIDENCE_OK` (`.planning/phases/02-window-control/tdd/02-06-task1-red.json`). Semantic check: the build succeeded and the target tests ran and failed on the planned values. The identity-safe cases (primary vector, round trip, empty list) passed against the stub, as expected.
- **GREEN** (`cdbdf93`): real conversion and assignment, plus tracker, Displays, AXWindowSystem and fake wiring. 10 tests in 3 suites pass.
- Task 2 is `type="auto"` with no `tdd` flag: its integration tests were written alongside the code.

## Files Created/Modified
- `Sources/PaneEngine/Coordinates.swift` - the flip and display assignment
- `Sources/PaneEngine/WindowTracker.swift` - sets `displayUUID`; a display change emits `windowChanged`
- `Sources/PaneMac/Displays.swift` - the current displays by UUID, and UUID → localized name
- `Sources/PaneMac/AX/AppRegistry.swift` - NSWorkspace launch, quit, activate and hide/unhide; eligibility re-checks
- `Sources/PaneMac/RefreshScheduler.swift` - per-pid debounce, global debounce, sweep
- `Sources/PaneMac/AX/AXAppThread.swift` - element cache, notification registration, `windowID` on hints, teardown order
- `Sources/PaneMac/AX/AXSnapshotReader.swift` - the internal `observeApp` also returns the listed elements by window ID
- `Sources/PaneMac/AXWindowSystem.swift` - registry, scheduler, hint loop, focus, settle follow-up, displays, screen-change observer
- `Sources/PaneTestSupport/FakeWindowSystem.swift` - `setDisplays(_:)`
- `Tests/PaneEngineTests/CoordinatesTests.swift`, `Tests/PaneEngineTests/TrackerDisplayTests.swift`, `Tests/PaneMacIntegrationTests/LiveTrackingTests.swift`

## Decisions Made
See `key-decisions` in the frontmatter. The main one is `AppRegistry.onStop(pid, terminated)`: the plan's interface had `onStop: (pid_t) -> Void`, but `AXWindowSystem` has to know whether to emit `appTerminated`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `AXSnapshotReader.observeApp` did not expose the window elements**
- **Found during:** Task 2
- **Issue:** The element cache needs the AX elements that `observeApp` already reads. Re-reading `AXWindows` would cost a second IPC round trip per refresh.
- **Fix:** The internal overload now returns `(observation, elements)`, where elements is nil when `AXWindows` failed, so a failed read never clears the cache. The public `observeApp(pid:bundleID:)` used by pane-dump is unchanged.
- **Files modified:** Sources/PaneMac/AX/AXSnapshotReader.swift
- **Committed in:** b8ce330

**2. [Interface] `AppRegistry.onStop` carries a `terminated` flag; `AppRegistry.recheck()` added**
- **Found during:** Task 2
- **Issue:** The plan has `onStop` emit `appTerminated` "for termination" only, but its signature had no way to say which case applied. Pitfall 11 also needs the sweep to re-check eligibility, and `start()` alone cannot do that.
- **Fix:** `onStop: (Int32, Bool) -> Void` and `func recheck()`. `recheck()` runs from `refreshAll()`, and it also stops an app that disappeared without a termination notice.
- **Committed in:** b8ce330

**3. [Rule 2 - Verification] Added a seventh integration case for the flagged prohibition**
- **Found during:** Task 2
- **Issue:** The prohibition "an AX notification alone must never remove or close a tracked window" was marked `status: unverified`.
- **Fix:** `aDestroyedNotificationAloneNeverClosesAWindow()` closes the fixture window. It then checks that the window is still tracked after 500 ms and that no `windowDestroyed` was emitted.
- **Committed in:** b8ce330

---

**Total deviations:** 3 (1 blocking, 1 interface, 1 added verification). **Impact:** no public contract changed. `AppRegistry` and `RefreshScheduler` are internal.

## Issues Encountered
- None. NSWorkspace launch and terminate notifications do reach the `swift test` process: all seven live cases pass in about 0.6–1.2 s each, well under the 5 s sweep. The first six passed in 3 consecutive runs; all seven passed standalone and again inside a full `swift test`.

## Human checks for phase UAT (end-of-phase)
1. **Multi-display arrangements (D5):** attach an external display. Arrange it above, then left, then below the built-in display (System Settings › Displays › Arrange). For each arrangement, put a window on each display and check that the window's display matches in `swift run PaneApp --print-inventory-summary` or the Tracked Windows view (Plan 02-08/10). Expected: each window reports the UUID of the display it is mostly on, and frames on the external display have negative y (above), negative x (left), or y ≥ the built-in height (below).
2. **Hot-plug:** unplug and replug the external display while Pane runs. Expected: the unified log shows one `displaysChanged`, followed about 500 ms later by one refresh, and windows move to the remaining display's UUID.
3. **Focus and activation policy (D6):** click between two windows of one app and look for `windowFocused` in a debug event log (no UI shows it yet). An app that switches to accessory policy (for example a menu-bar app that hides its Dock icon) should lose its thread at its next activation or sweep.

## Known Stubs
None introduced. `perform` still drops commands until Plan 02-12. That stub was already recorded by Plan 02-01.

## Threat Flags
None. No new trust boundary: hints and NSWorkspace events were already in the plan's threat model (T-02-16..18 mitigated as planned).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 09 (two-source close rule) can rely on `appTerminated` and on windows staying tracked after a quit or a destroyed hint.
- The Tracked Windows UI can use `Displays.localizedNames()` for its Display column.
- Watch for: `inventory().displays` is refreshed on every sweep, but `displaysChanged` is only emitted on the AppKit screen-parameters notification.

## Self-Check: PASSED
- All 7 created files exist; commits 57c1f7b, cdbdf93 and b8ce330 are on HEAD.
- Task acceptance greps all at least 1. `scripts/check-no-appkit.sh` OK (18 files).
- `swift test --filter "CoordinatesTests|TrackerDisplayTests|LiveTrackingTests"` passes (integration not skipped). Full `swift test` passes: 142 model + 15 PaneMac + 10 integration (7 of them live) + 69 engine tests.

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
