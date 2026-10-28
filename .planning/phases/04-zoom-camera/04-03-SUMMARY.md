---
phase: 04-zoom-camera
plan: 03
subsystem: zoom
status: complete
tags: [engine, camera, navigator, history, swift-testing]
requires:
  - phase: 04-02
    provides: "ViewTarget, ViewPlanner, CameraState, PendingMove, zoomTo/cameraSettle two-step protocol, effectiveView"
provides:
  - "Command.camera(CameraCommand) with zoomOutAll, stepOut, stepIn, back, forward, pan(Edge), frameWindow, frameDesktop"
  - "ArrangerInput.camera(_, displayUUID:, focused:, pointer:) and .zoomTo(_, displayUUID:, focus:)"
  - "CommandContext.displayUUID; Arranger.cameraAvailable, isFramingFocused, isFramingDesktop, shownLeafRects, leafNode(of:)"
  - "Navigator (pure): ancestors, target, stepIn, stepOut, pan, lowestCommonAncestor, rectTarget, widenTarget; Navigator.Refusal with the Surface 1 announcements"
  - "ViewEntry and CameraHistory (limit 50), one per display, changed only at settle"
  - "CONTEXT E widening on windowFocused / windowCreated, with unparkedNew so a new window is never parked before it is shown"
  - "Vanished view node falls back to the deepest live node of its stored path"
  - "MenuCopy.cameraTitle for every camera command"
affects: [04-04, 04-05, 04-06, 04-07, 04-08]
actuals:
  tokens: 14835
  tasks: 3
  commits: 6
plan_head_before: dd2bd51749b6bdd3ee291073ba12bc38c8df3793
plan_head_after: 3aba1ab15df0dfb8c2430c339ce9fb447e59fa42
tech-stack:
  added: []
  patterns:
    - "One cameraStep resolver feeds both camera() and cameraAvailable(), so a greyed item and a refused hotkey always agree"
    - "PendingMove.kind (.navigate, .back(n), .forward(n)) carries the history change to the settle; a second Back during a pending Back goes on from it"
    - "Refusals are one shape: [.beep, .announce(Surface 1 text), .info(\"refused {command}: {reason}\")]"
key-files:
  created:
    - Sources/TransomEngine/Navigator.swift
    - Tests/TransomEngineTests/NavigatorTests.swift
  modified:
    - Sources/TransomEngine/Command.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
    - Tests/TransomEngineTests/ArrangerCameraTests.swift
    - Tests/TransomMacTests/MenuCopyTests.swift
key-decisions:
  - "Navigator.Refusal is nested in Navigator and conforms to Error so cameraStep returns Result<CameraStep, Refusal>; plan failures still throw LayoutError and become .fault"
  - "Back/Forward skip entries equal to the current view as well as dead or not-shown ones; skipped entries are dropped at settle, live passed-over ones go on the other stack"
  - "Frame toggles compare against the current view only (the pending target while pending), per the concurrency probe"
  - "Frame Focused Window acts on the pointer's display like every camera command; a focused window docked on another display is refused"
  - "Widening also covers a present floater on a shown Desktop (leafNode maps it to .desktop); excluded windows never widen"
  - "unparkedNew is cleared per desk at settle, not globally, so a settle on another display cannot park a new window early"
requirements-completed: []
coverage:
  - id: D1
    description: "Zoom Out to All Windows, Step Out, Step In targets and refusals; availability needs zoom on, ready, not paused and a desk on the display; a display-less .command(.camera) faults"
    requirement: ZOOM-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#NavigatorTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Step In toward the focused window, then the pointer, then the largest child (ties to the lower NodeID)"
    requirement: ZOOM-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#stepInOtherwiseGoesToTheLargestChild"
        status: pass
    human_judgment: false
  - id: D3
    description: "Back/Forward per display, limit 50, settle-only pushes, retarget pushes once, dead and not-shown entries skipped"
    requirement: ZOOM-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#CameraHistoryTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Move View: same-depth node across the edge, longest overlap, ties to recency then NodeID; refused at home and with nothing across"
    requirement: ZOOM-09
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#PanAndFrameNavigatorTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Frame Focused Window and Frame Desktop toggles, idempotency and pending-move concurrency probes, refusals"
    requirement: ZOOM-10
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#frameWindowDuringAPendingMoveComparesAgainstThePendingTarget"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#frameDesktopTogglesAndIsRefusedWhileHidden"
        status: pass
    human_judgment: false
  - id: D6
    description: "Rect target: closed-band LCA of on-screen leaf centres, Desktop and collapsed tiles count"
    requirement: ZOOM-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#RectTargetNavigatorTests"
        status: pass
    human_judgment: false
  - id: D7
    description: "zoomTo with focus focuses right after the settle's writes"
    requirement: ZOOM-06
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#zoomToWithFocusFocusesAfterTheWrites"
        status: pass
    human_judgment: false
  - id: D8
    description: "Widening for focus and new windows outside the view; a new window is not parked before the move settles; vanished node fallback"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/NavigatorTests.swift#WideningNavigatorTests"
        status: pass
    human_judgment: false
duration: 92min
completed: 2026-10-28
---

# Phase 4 Plan 03: Navigation Summary

**Every camera command now resolves in the engine: Zoom Out to All Windows, Step In/Out, Back/Forward with a 50-entry history per display, Move View, and the Frame Focused Window / Frame Desktop toggles. Each refuses with the exact UI-SPEC Surface 1 announcement, and one resolver drives both the action and the menu's enabled state. The engine also has the rubber-band target, zoom-to-with-focus for clicks, and the CONTEXT E rule: focusing a window outside the view, or opening one there, widens the camera, and a new window is never parked before the camera shows it.**

## Performance

- **Duration:** 92 min (13:06Z to 14:38Z; the full suite was run three times and once more at the base commit, see Issues)
- **Tasks:** 3, all TDD (RED then GREEN)
- **Files:** 8 (2 created, 6 modified)

## Public names for the shell plans (04-05, 04-06)

- `Command.camera(CameraCommand)`. `CameraCommand`: `.zoomOutAll, .stepOut, .stepIn, .back, .forward, .pan(Edge), .frameWindow, .frameDesktop`. The URL and hotkey tables map one-to-one to these. `.pan(.top)` is "Up" and `.pan(.bottom)` is "Down".
- Dispatch: `ArrangerInput.camera(command, displayUUID:, focused:, pointer:)`. A bare `.command(.camera(...))` returns one `.fault`.
- Clicks: `ArrangerInput.zoomTo(.node(leaf), displayUUID:, focus: window)`. The settle ends with `.perform([.focus(window)])`.
- Availability: `arranger.availability(.camera(c), context: CommandContext(focused:, ready:, displayUUID:))`, or `cameraAvailable(_:context:)` directly.
- Checkmarks: `isFramingFocused(displayUUID:focused:)`, `isFramingDesktop(displayUUID:)`.
- Rubber band: `try arranger.shownLeafRects(displayUUID:)` gives the tiles, then `Navigator.rectTarget(band:tiles:tree:)`. It returns a NodeID; convert it with `Navigator.target(_:in:)`, which gives `.home` for the root.
- Refusal copy: `Navigator.Refusal.announcement`. `.notReady` is for the shell to use, since the engine never sees "not ready".
- Window leaf: `leafNode(of:)` (the docked leaf, or `.desktop` for a present floater on a shown Desktop).
- Menu titles: `MenuCopy.cameraTitle(_:)` (through `commandTitle(.camera(_))`).

## Task Commits

1. **Task 1 (tracer): Step In / Step Out / Zoom Out** - RED `73e5691`, GREEN `c2f20f3`
2. **Task 2: history, Move View, Frame toggles** - RED `3f2ad60`, GREEN `f3cb046`
3. **Task 3: zoom with focus, rect target, widening** - RED `a600e19`, GREEN `3aba1ab`

## TDD

- **Task 1 RED (`73e5691`):** the tests failed to compile (no `CameraCommand`, no `.camera` input). **GREEN (`c2f20f3`):** the filter `NavigatorTests|ArrangerCameraTests|CommandTests|MenuCopyTests|ArrangerCommandTests` passed 48 tests in 4 suites plus 19 XCTest-side lines. **Tracer gate:** I ran the Task 1 `<verify>` again before expanding. It passed (48 tests, no "✘").
- **Task 2 RED (`3f2ad60`):** the tests failed to compile (no `.back`, `.pan`, `.frameWindow`, `CameraHistory`). **GREEN (`f3cb046`):** 39 tests in 4 suites passed on the Task 2 filter. The pan/frame suite was renamed `PanAndFrameNavigatorTests` so the plan's `NavigatorTests` filter matches it.
- **Task 3 RED (`a600e19`):** the tests failed to compile (no `focus:` on `.zoomTo`, no `rectTarget`). **GREEN (`3aba1ab`):** 48 tests in 6 suites passed. Two band rects in my own new tests missed the full-height tiles' centres (y = 500) and were corrected before GREEN. **Mutation check:** with the `unparkedNew` park exemption removed, `aNewWindowOutsideTheViewWidensAndIsNotParkedFirst` fails with 2 issues, so the test exercises it.

## Verification

- Task 1, 2 and 3 filters: all non-zero counts, no "✘" (see TDD).
- Full headless `swift test` (this run and the base run both fail only `FreezeTestTests.itResumesByItself`): TransomModelTests 193, TransomEngineTests 630 (was 592), XCTest-side 42, all passed. TransomMacTests: 202 tests, of which 201 pass. `FreezeTestTests.itResumesByItself` failed in both full runs and passed 8/8 when its suite ran alone. See Issues Encountered.
- `scripts/check-no-appkit.sh`: OK (44 files).
- Acceptance greps: `camera(CameraCommand)` in Command.swift 1, "Zoom Out to All Windows" in MenuCopy 1, "Already showing all windows" in Navigator 1, `struct CameraHistoryTests` 1, `public static let limit = 50`, `"Frame Focused Window"` 1, `func rectTarget` 1, `unparkedNew` in Arranger.swift 1.
- Expectation guard: 5 `(04-03)` commits at check time; `grep -c '^-.*#expect'` over the Tests diff from before the first one prints 0.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] Back/Forward skip entries equal to the current view**
- **Found during:** Task 2
- **Issue:** an entry equal to the current view (for example after a retarget back to the committed view) would make Back target the view already shown. `zoomTo` then refuses with only an info line, with no beep or announcement.
- **Fix:** the liveness test also requires `entry.target != view`.
- **Commit:** f3cb046

**2. [Rule 2 - Correctness] A second Back or Forward during a pending one goes on from it**
- **Found during:** Task 2
- **Issue:** history changes only at settle, so a second press before the settle would recompute the same entry. UI-SPEC says a double press moves two levels.
- **Fix:** `PendingMove.Kind` carries the entry count (`.back(n)`, `.forward(n)`). A second press skips the pending count. The settle moves the view left, then the live passed-over entries, onto the other stack. Test: `aDoubleBackGoesBackTwoAndForwardRetracesThem`.
- **Commit:** f3cb046

**3. [Rule 1 - Robustness] `unparkedNew` is cleared per desk at settle**
- **Issue:** clearing it on any settle would let a settle on another display park a new window before its own widen move settles.
- **Fix:** a settle removes only the identities its desk holds.
- **Commit:** 3aba1ab

**4. [Scope note] Widening covers floaters too**
- `leafNode(of:)` maps a present floater on a shown Desktop to `.desktop`, so one rule covers focus on a docked window, focus on a floater, and new windows. Excluded windows never widen, because Transom never moves them.

**5. [Test naming] Suite names chosen to match the plan's filters**
- The new suites are `PanAndFrameNavigatorTests`, `RectTargetNavigatorTests` and `WideningNavigatorTests`, so `--filter NavigatorTests` runs them.

---

**Total deviations:** 3 auto-fixed (Rules 1 and 2), 2 notes. **Impact:** these are needed for the probes and the UI-SPEC double-press rule. No scope creep and no architectural change.

## Issues Encountered

- `FreezeTestTests.itResumesByItself` (TransomMac, unchanged by this plan) failed in both full parallel runs and passed alone. It busy-waits up to 1 s for a 50 ms `Task.sleep` resume, which is wall-clock sensitive under load. This plan's only TransomMac change is MenuCopy strings and one string test. Base-commit check: a full `swift test` at `dd2bd51` (before 04-03), in a scratch worktree that has since been removed, fails the same test with the same 3 issues (TransomMac 201 tests, 1 failing). So it is pre-existing and load-sensitive, not caused by this plan. It is logged in `deferred-items.md`.

## Known Stubs

None added. The 04-02 stub (`ArrangeController` settles every `.cameraMove` at once) still stands until 04-04. Production still never sends `.zoomEnabled(true)` or `.camera`, so shipped behaviour is unchanged.

## Flagged Assumptions (unchanged from the plan, implemented as written)

- Step In from `.home` treats the root as the view's node. With only the Desktop tile it refuses "Nothing to zoom in to".
- The band is a closed rect. The shell clamps it to the drag's display.
- History is session-only, so it starts empty at home on every launch.
- Focus is sent right after the settle's writes, not after the reveal fade (move it to `.cameraRevealed` if UAT shows a problem).
- Pan never changes depth. From a depth-2 leaf it only reaches depth-2 nodes.
- New: Frame Focused Window acts on the pointer's display. A focused window docked on another display is refused "No docked window to frame".

## Threat Flags

None. T-04-10: only a window outside the view moves the camera, a retarget reuses the pending move, and `focusInsideTheViewDoesNotMoveTheCamera` covers focus inside the view. T-04-11: `unparkedNew`, with its mutation-checked test. T-04-12: a display-less `.command(.camera)` faults.

## Next Phase Readiness

- 04-04 (stage) can treat `.cameraMove` as before. The settle may now end with `.perform([.focus(window)])`.
- 04-05 and 04-06 have the public names above. `requirements-completed` is left empty: the ZOOM IDs here are shared with the shell plans, so the orchestrator marks them at phase end.

## Self-Check: PASSED

- FOUND: Sources/TransomEngine/Navigator.swift, Tests/TransomEngineTests/NavigatorTests.swift
- FOUND commits on HEAD: 73e5691, c2f20f3, 3f2ad60, f3cb046, a600e19, 3aba1ab
- Measured commits: `git rev-list --count dd2bd51..HEAD` = 6

---
*Phase: 04-zoom-camera*
*Completed: 2026-10-28*
