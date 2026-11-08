---
phase: 03-tiling-mvp
plan: 05
subsystem: arranger
status: complete
tags: [swift, paneEngine, paneMac, panePrivate, spaces, skylight, arranger, tdd, tracer]

requires:
  - phase: 02-window-control
    provides: "SkyLightSpaces per-window lookup, Capability.spaces, ObservationContext.windowSpaces, SpaceSwitchMarks and the activeSpaceDidChange observer (02-14, 02-17)"
  - phase: 03-tiling-mvp
    provides: "Arranger, Planner, ArrangeController, lastRequested diff (03-04); World.reflow (03-03)"
provides:
  - "PanePrivate SkyLightSpaces.currentSpace(displayUUID:session:) through dlsym of SLSManagedDisplayGetCurrentSpace"
  - "PaneMac Displays.current() fills DisplayInfo.currentSpaceID"
  - "AXWindowSystem emits .spaceChanged(displayUUID:spaceID:) per display whose Space changed, and re-reads displays before .displaysChanged"
  - "PaneEngine WindowInfo.spaces: Set<UInt64>?, filled by WindowTracker.ingest"
  - "WindowTracker reports windowChanged after CloseRule (state first, then the new Space)"
  - "Arranger: per display and Space desks, home(of:), rehome(_:), ArrangerEffect.info, Spaces-off notice once"
  - "ArrangeController feeds a fresh inventory after .displaysChanged and logs .info"
  - "FakeWindowSystem.showSpace sets every display's currentSpaceID and yields .spaceChanged when notifying"
affects: [03-06, 03-07, 03-08, 03-10, persistence, drag, displays, phase-6]

actuals:
  tokens: 9900
  tasks: 2
  commits: 4
plan_head_before: 770d456883b45aa18604f7297fa7642da4b3cfd3
plan_head_after: 101b60c9aba467d76093f1fb32b4aeb264d751d9

tech-stack:
  added: []
  patterns:
    - "A display change reaches the pure Arranger as a new inventory, never as a bare event"
    - "lastRequested keeps present windows on hidden desks, so showing a Space again re-sends nothing unchanged"
    - "A cross-desk move is two World.reflow calls on one candidate World, committed together"

key-files:
  created:
    - Tests/PaneEngineTests/ArrangerSpacesTests.swift
  modified:
    - Sources/PanePrivate/SkyLightSpaces.swift
    - Sources/PaneMac/Displays.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneEngine/WindowSystem.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Tests/PaneEngineTests/TrackerDisplayTests.swift
    - Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift
    - Tests/PaneMacTests/CapabilitiesTests.swift

key-decisions:
  - "WindowTracker emits windowChanged after CloseRule's state events, so a window going fullscreen is never seen as a present window on a foreign Space (that would have re-homed it onto a fullscreen-Space desk)"
  - "Re-home runs only on windowChanged and on an inventory, never on a state change, whose stored info may carry a stale Space set"
  - "A window's home Space is the display's shown Space when its Spaces are nil, empty or include it; otherwise the lowest of its Spaces"
  - "Display changes reach the Arranger as an inventory: AXWindowSystem re-reads displays before yielding displaysChanged, and ArrangeController then feeds .inventory"
  - "currentSpace takes a CapabilitySession (default Capabilities.session) so the Spaces-off path is tested without touching the process-wide session"

patterns-established:
  - "Fake Space scenarios: switchTo(space) feeds the notification's events, then a refresh, as the live shell sees them"

requirements-completed: []

coverage:
  - id: D1
    description: "Each Space keeps its own desk; a switch writes nothing to the Space left, and switching back re-sends nothing unchanged"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerSpacesTests.swift#aSpaceSwitchLeavesTheOtherSpacesLayoutAlone, aCloseOnAHiddenSpaceIsAppliedAndPlannedOnlyOnReturn"
        status: pass
    human_judgment: true
    rationale: "Real Space switches cannot be driven from a test (plan human-check)"
  - id: D2
    description: "SLSManagedDisplayGetCurrentSpace gives the main display's current Space, equal to a visible window's Space and to Displays.current().currentSpaceID"
    requirement: TILE-03
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift#theMainDisplaysCurrentSpaceIsTheSpaceOfAVisibleWindow"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/CapabilitiesTests.swift#theCurrentSpaceLookupIsNilWhileSpacesAreOff"
        status: pass
    human_judgment: false
  - id: D3
    description: "A fullscreen Space gets no desk; the fullscreen window stays reserved on its desk and returns to its tile"
    requirement: WIN-07
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerSpacesTests.swift#aFullscreenSpaceGetsNoDeskAndTheWindowReturnsToItsTile; Tests/PaneEngineTests/TrackerDisplayTests.swift#goingFullscreenReportsTheStateBeforeTheNewSpace"
        status: pass
    human_judgment: true
    rationale: "Native fullscreen switches Spaces, which the live-test rules forbid; the plan's human-check covers it"
  - id: D4
    description: "Windows go to their own Space's desk; re-home across Spaces and displays with no undo step; an empty Space set never moves a window"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerSpacesTests.swift (launch, floating, docked, empty-set and cross-display rows); TrackerSpacesTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Spaces off: one desk per display, logged once; a display change re-plans the shown desk and a gone display gets no frames"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerSpacesTests.swift#withSpacesOffEachDisplayHasOneDeskAndThatIsLoggedOnce, aDisplayChangeReplansTheShownDeskAndAGoneDisplayGetsNothing"
        status: pass
    human_judgment: true
    rationale: "The `--disable-private=Spaces` run in Pane Debug is part of the plan's human-check"

duration: 8min
completed: 2026-10-26
---

# Phase 3 Plan 05: Per-display, per-Space desks and fullscreen Spaces Summary

**Every display and Space now has its own layout. `SLSManagedDisplayGetCurrentSpace` (through dlsym, behind `Capability.spaces`) gives each display its current Space, `AXWindowSystem` reports Space switches as `spaceChanged`, and the Arranger plans only the shown Space's desk. Windows go to their own Space's desk, a fullscreen Space never gets a desk, and a window that moves to another Space or display is re-homed with no undo step.**

## Performance

- **Duration:** about 8 min
- **Started:** 2026-10-26T02:40:04Z
- **Completed:** 2026-10-26T02:48:00Z
- **Tasks:** 2 (4 commits)
- **Files:** 1 created, 11 modified

## Accomplishments

- **Current Space (PanePrivate).** `SkyLightSpaces.currentSpace(displayUUID:)` resolves `SLSManagedDisplayGetCurrentSpace` in the existing lazy dlopen closure as its own optional. A missing symbol therefore leaves the per-window lookup working, and `isLoaded` still means the two original symbols. It returns nil when Spaces are off, when the symbol is missing, or when SkyLight answers 0. The doc comment names the signature's source: the yabai header, checked by the research probe. Nothing is linked; the SkyLight grep of `Package.swift` and `xcode/project.yml` finds nothing.
- **Phase 2 obligations met.**
  - `Displays.current()` fills `currentSpaceID`.
  - On `activeSpaceDidChange`, `AXWindowSystem` re-reads the displays (and with them the inventory's displays) and yields `.spaceChanged` for each display whose Space changed.
  - `displaysDidChange` now re-reads the displays before yielding `.displaysChanged`.
- **Tracker.** `WindowInfo.spaces` is filled from `context.windowSpaces` for the visible member and is part of the `windowChanged` comparison. `windowChanged` is now emitted after CloseRule's state events, so a window going fullscreen arrives as `.fullscreen` together with its new Space.
- **Arranger.**
  - `spaceChanged` updates the display's Space, and planning follows it.
  - `lastRequested` keeps present windows on hidden desks, so returning to a Space writes nothing that did not change. Fullscreen and absent windows are still pruned, so they get their tile rect again when they return.
  - A window's home is its display's shown Space, unless its known Spaces exclude that Space; then it is the lowest of its Spaces.
  - A desk is only created for a present, dockable window, so a fullscreen Space never gets one.
  - **Re-home rule.** It covers a present window on a present slot when either its display changed, or its known, non-empty Space set no longer includes its desk's Space. That window floats on its home desk at its current frame. The move is two `World.reflow` calls on one candidate World, so it is atomic and adds no undo step.
  - When displays report no Space IDs, `.info("Spaces lookup off: one layout per display")` is emitted once per session.
- **Shell.** `ArrangeController` logs `.info` at info level and feeds a fresh `.inventory` after `.displaysChanged`. That re-plans every shown desk against the new visible frames, and a display that went away is not planned.
- **Fake.** `showSpace` moves every display's `currentSpaceID`, and when notifying it yields `.spaceChanged` per display.

## Task Commits

1. **Task 1 (tracer): the current Space keys the desk; a switch leaves the other layout alone**: `7e27bf5` (test, RED), `ea2f85e` (feat, GREEN)
2. **Task 2: own-Space desks, no fullscreen-Space desk, re-homes, display re-plans**: `c661e62` (test, RED), `101b60c` (feat, GREEN)

## TDD Gate Compliance

- Every task starts with a `test(03-05)` commit, and a `feat(03-05)` commit follows it.
- Task 1 RED: `RED_EVIDENCE_OK`, target `aSpaceSwitchLeavesTheOtherSpacesLayoutAlone()`. All 3 tests failed on their planned assertions: no `spaceChanged` was yielded, the display stayed on Space 1, and `c` landed on desk (D, 1). The tests ran against a `currentSpace` stub that compiles and returns nil.
- Task 2 RED: `RED_EVIDENCE_OK`, target `aDockedWindowOnAnotherSpaceFloatsThereAndItsNeighbourReflows()`. It failed on the re-home assertions, against stubs for `WindowInfo.spaces` (never filled) and `ArrangerEffect.info` (never emitted). Four rows passed at RED, which is expected:
  - The empty-set and gone-display rows are negative guards.
  - The display re-plan row was already covered by the 03-04 inventory path.
  - The fullscreen row was already covered by 03-04's `.fullscreen` handling. It guards that the new re-home rule does not move a fullscreen window.
  - `withoutSpaceDataSpacesStayNil...` already held.
- Tracer gate after Task 1: the verify step was re-run end to end (unit, live and no-AppKit checks) and passed before Task 2 started.
- No refactor commits.

## Verification

- `swift test --filter ArrangerSpacesTests` (Task 1): 3 tests ran, 3 passed.
- `caffeinate -d -i swift test --filter SpacesIntegrationTests`, trusted terminal, lock checked first: 2 tests ran, 2 passed, none skipped. No fixtures were left over.
- `swift test --filter "ArrangerSpacesTests|TrackerSpacesTests|TrackerDisplayTests|ArrangerLifecycleTests"`: 35 tests in 5 suites ran and passed.
- `PANE_SKIP_AX_INTEGRATION=1 swift test`: 189 + 103 + 28 + 275 tests passed.
- Live regression after the tracker's event-order change, run as two bounded batches:
  - `ArrangeIntegrationTests|SpacesIntegrationTests`: 4 passed, plus the fullscreen test skipped by its opt-in gate.
  - `TabsIntegrationTests|LiveTrackingTests`: 7 passed.
  - No fixtures were left over after either batch.
- `scripts/check-no-appkit.sh`: OK (30 files).
- Acceptance greps:
  - `SLSManagedDisplayGetCurrentSpace` in SkyLightSpaces.swift: 2.
  - `SkyLightSpaces.currentSpace` in Displays.swift: 1.
  - `currentSpaceID: nil` in Displays.swift: 0.
  - `.spaceChanged(` in AXWindowSystem.swift: 1.
  - SkyLight in Package.swift and project.yml: 0.
  - `public var spaces: Set<UInt64>?`: 1.
  - `windowSpaces` in WindowTracker.swift: 3.

## Deviations from Plan

**1. [Rule 1 - Bug] The tracker reports windowChanged after the state events**
- **Found during:** Task 2 design
- **Issue:** `ingest` emitted `windowChanged` inside the observation loop, before CloseRule decided the state. A window going fullscreen would therefore arrive as a *present* window with Space set {9}. The re-home rule would then have moved it onto a new desk (D, 9), which breaks WIN-07.
- **Fix:** The loop collects the changed identities, and `windowChanged` is emitted with the current info after `decide`. Pinned by `goingFullscreenReportsTheStateBeforeTheNewSpace`. All existing tracker tests and the live tracking and tab tests still pass.
- **Commit:** 101b60c

**2. [Rule 3 - Blocking] ArrangeController and displaysDidChange were changed, though not in the plan's file list**
- **Issue:** The Arranger cannot learn new visible frames from a bare `.displaysChanged`. Also, `AXWindowSystem` only re-read the displays 500 ms later, in a refresh that emits nothing when no window changes.
- **Fix:** `displaysDidChange` re-reads the displays before yielding. `ArrangeController` feeds `.inventory` after `.displaysChanged`, and it handles the new `.info` effect, which it has to because the effect switch is exhaustive.
- **Commits:** ea2f85e, 101b60c

**3. [Test seam] currentSpace takes a CapabilitySession**
- **Issue:** The behaviour "with Spaces forced off, currentSpace returns nil" cannot be tested in-process without switching off the process-wide session that the live tests use.
- **Fix:** It now takes a `session:` parameter that defaults to `Capabilities.session`. The test is in CapabilitiesTests.
- **Commit:** 7e27bf5 (stub), ea2f85e

**4. [Rule 1 - Test bug] The hidden-close test's geometry**
- **Issue:** The first draft expected `a` to fill the display after `b` closed. The Desktop tile keeps its share, so `a` only takes `b`'s share.
- **Fix:** The test now asserts that `a`'s tile grew.
- **Commit:** ea2f85e

**Total deviations:** 4 (1 bug fix, 1 blocking scope addition, 1 test seam, 1 test fix). **Impact:** no product scope change.

## Known limits (not stubs)

- **Fullscreen exit flicker.** When a docked window leaves fullscreen, `spaceChanged` arrives before the refresh that reports the window present again. Its neighbours therefore take its space for one plan and give it back on the refresh. Only the final frames are tested. A fix (holding the re-plan of a newly shown desk until the next refresh) would need a real-session check.
- **Undo after a re-home.** The old desk's undo snapshots still hold a window that was re-homed. The first undo there pops that snapshot and fails validation (`duplicateWindow`), so the user gets a beep plus a fault. Undo works again from the next step. This is `World.undo`'s documented behaviour for a window on another desk.
- **Spaces off (A7).** One desk per display, so windows on other Spaces may be planned. This is accepted by A7.

## Requirements

- **WIN-07 stays Pending.** The fake covers it end to end, but real native fullscreen switches Spaces. The live test stays opt-in under the live-test rules, and the plan's human-check has not been run.
- **TILE-03** was already marked Complete by 03-04. This plan adds the per-Space and per-display re-plans and does not change its status.

## Threat Flags

None. The mitigations are in place:
- **T-03-11:** dlsym only, an optional pointer, nil when the capability is off or the symbol is missing, and 0 treated as unknown.
- **T-03-12:** only a known, non-empty, disjoint Space set or a changed display re-homes a window, and the move goes through `World.reflow`, which validates the whole World.

## Human checks pending (from the plan)

- In Pane Debug with two Desktops on the built-in display:
  1. Dock two windows on Desktop 1, then dock two more on Desktop 2.
  2. Switch back and forth.
  3. Make a docked window fullscreen, visit its fullscreen Space, come back, and leave fullscreen.
- Repeat once with `scripts/run-debug.sh --no-build --disable-private=Spaces`. Expect one layout per display and the "Spaces lookup off" line logged once.

## Self-Check: PASSED

The created file Tests/PaneEngineTests/ArrangerSpacesTests.swift exists. Commits 7e27bf5, ea2f85e, c661e62 and 101b60c are ancestors of HEAD.
