---
phase: 02-window-control
plan: 05
subsystem: permissions
tags: [accessibility, tcc, tccutil, swiftui, appkit, state-machine, swift-testing]

requires:
  - phase: 02-window-control
    provides: "02-02 StatusItemController, MenuCopy, PaneMacApp.run, signed Debug build scripts"
provides:
  - "PermissionReducer: pure permission state machine (notTrusted, waitingForGrant, probing, ready, staleTrustedButFailing, resetting) with effects"
  - "PermissionController: runs prompt-once-per-cycle, Settings deep link, 1 s poll, AX probe, tccutil reset, tracking start"
  - "TCCReset (fixed-argv /usr/bin/tccutil) and PermissionProbe (Finder AXRole, retries, frontmost fallback)"
  - "Set Up Pane window (SetupView + SetupWindowController) and permission-aware status glyph and menu"
affects: [02-08 Tracked Windows no-permission state (calls SetupWindowController.show()), 02-06, 02-13, phase-3 onboarding]

actuals:
  tokens: 18793
  tasks: 3
  commits: 6
plan_head_before: 21d4e472f96003410555423209a16cf91a2d9d45
plan_head_after: 6b9944c3d6913b02131578e8b62ad2d2647134bd

tech-stack:
  added: []
  patterns:
    - "Pure reducer in PaneEngine + MainActor effect runner in PaneMac; every UI and timer event goes through reduce"
    - "Combine $state sinks for AppKit observers (status glyph, launch decision); SwiftUI observes via @ObservedObject"
    - "RED commits carry compiling no-op stubs of the public API so suites fail on assertions, not on the build"

key-files:
  created:
    - Sources/PaneEngine/PermissionReducer.swift
    - Sources/PaneMac/Permission/PermissionController.swift
    - Sources/PaneMac/Permission/PermissionProbe.swift
    - Sources/PaneMac/Permission/TCCReset.swift
    - Sources/PaneMac/Permission/SetupView.swift
    - Sources/PaneMac/Permission/SetupWindowController.swift
    - Tests/PaneEngineTests/PermissionReducerTests.swift
    - Tests/PaneMacTests/TCCResetTests.swift
  modified:
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Tests/PaneMacTests/MenuCopyTests.swift

key-decisions:
  - "A trusted launch waits for its probe before deciding whether to show Set Up Pane, so a working grant never flashes the window on every launch"
  - "bringWindowForward only acts on a visible setup window, so a user-closed window is never reopened"
  - "Probe: only -25211 means stale; -25204 retries; any other AX answer proves the API is reachable and counts as success"
  - "Esc and Cmd-W close the setup window through an NSWindow subclass (accessory apps have no main menu); windowShouldClose blocks every close while resetting"
  - "Menu header for the resetting phase reads \"Accessibility access isn't working\" (a reset only starts from a stale form); Fix item shows in form A, form B and while resetting"

patterns-established:
  - "Permission flow: PermissionReducer.reduce decides, PermissionController.perform executes, views only send events"

requirements-completed: [WIN-01]

coverage:
  - id: D1
    description: "Pure permission reducer: transitions, once-per-cycle prompt, 14.9 s / 15 s form B boundary, reset paths, no-repeat-prompt property over 20 sequences"
    requirement: WIN-01
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/PermissionReducerTests.swift (16 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "tccutil reset runner with fixed argv, refusal without a bundle ID, real tccutil exit status"
    requirement: WIN-01
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/TCCResetTests.swift (3 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Menu copy for the permission header, Grant/Fix item and reset-failed body"
    requirement: WIN-01
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MenuCopyTests.swift (permission cases)"
        status: pass
    human_judgment: false
  - id: D4
    description: "First-launch grant flow end to end: prompt once, Settings deep link, window advances to Pane is ready by itself, tracking starts only when ready"
    requirement: WIN-01
    verification:
      - kind: manual_procedural
        ref: "smoke: unbundled PaneApp from a trusted shell logged notTrusted -> probing -> ready in 63 ms"
        status: pass
    human_judgment: true
    rationale: "TCC prompts, System Settings and real grant state cannot be driven from tests (Pitfall 9: UAT must launch through LaunchServices)"
  - id: D5
    description: "Stale grant recipe: form B callout after 15 s, Reset Permission returns to Turn Pane on again; closed setup window never reopens; warning glyph until ready"
    requirement: WIN-01
    verification: []
    human_judgment: true
    rationale: "Needs an ad-hoc re-signed copy of the app and real TCC state; visual layout and wrapping at 480 pt need a human"

duration: 9min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 05: Accessibility Permission Flow Summary

**A pure PermissionReducer drives a "Set Up Pane" window and status menu: macOS's prompt appears once per grant cycle, a 1 s poll and Finder AXRole probe confirm access, and both stale forms (trusted-but-refused and the 15 s "Already turned on?" case) get a one-click fixed-argv tccutil reset.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-10-24T16:01:04Z
- **Completed:** 2026-10-24T16:10:39Z
- **Tasks:** 3
- **Files modified:** 12 source/test files (+3 RED evidence records)

## Accomplishments
- `PermissionReducer` (PaneEngine, Foundation-free) decides every state and effect. Pairs the behaviour doesn't list keep the state and emit nothing.
- `PermissionController` runs the effects in order. `AXIsProcessTrustedWithOptions` uses the string literal. The Settings deep link is a constant. The poll is a MainActor Task. The probe and reset run off main. `system.start()` runs at most once.
- `PaneMacApp` no longer starts tracking directly. It sends `.launched(trusted:)`, and tracking starts only through the `startTracking` effect. The `--print-inventory-summary` path is unchanged.
- The Set Up Pane window covers every UI-SPEC state: S1–S5, callouts B and E, spinners, and all buttons disabled while resetting. The status glyph shows `exclamationmark.triangle` until ready. The menu header and the Grant/Fix item follow the permission phase.

## Task Commits

1. **Task 1: Permission reducer** - `abbc682` (test, RED), `1d71082` (feat, GREEN)
2. **Task 2: Permission effects** - `996a747` (test, RED), `5aab429` (feat, GREEN)
3. **Task 3: Set Up Pane window and menu** - `2fe5ac4` (test, RED), `6b9944c` (feat, GREEN)

No refactor commits were needed.

## TDD Gate Compliance
- Each task has a `test(02-05)` commit before its `feat(02-05)` commit.
- **RED evidence:** `tdd/02-05-task{1,2,3}-red.json`. The classifier returned `RED_EVIDENCE_OK` for all three (targets `trustedLaunchProbes()`, `argumentsAreTheFixedResetArgv()`, `permissionItemSaysFixWhenStale()`).
- **Semantic assessment:** every target compiled and failed on its `#expect` assertions against no-op stubs. None failed on a build or load error. Some reducer tests passed against the stub (initial state, the untrusted launch, ignored resets, the no-prompt property). That is expected, because those tests assert "no effect".

## Files Created/Modified
- `Sources/PaneEngine/PermissionReducer.swift`: phases, state, events, effects, `reduce`, `staleFormBDelay`
- `Sources/PaneMac/Permission/PermissionController.swift`: the effect runner (ObservableObject)
- `Sources/PaneMac/Permission/PermissionProbe.swift`: Finder AXRole read with a 1 s timeout, 3 retries, then one try against the frontmost regular app; logs inconclusive results
- `Sources/PaneMac/Permission/TCCReset.swift`: `/usr/bin/tccutil reset Accessibility <id>` through `terminationHandler`
- `Sources/PaneMac/Permission/SetupView.swift`: SwiftUI state matrix
- `Sources/PaneMac/Permission/SetupWindowController.swift`: 480 pt titled/closable window, launch decision, `userClosed`, Esc/⌘W
- `Sources/PaneMac/Shell/StatusItemController.swift`: glyph sink, permission header plus Grant/Fix item
- `Sources/PaneMac/Shell/MenuCopy.swift`: `permissionHeader`, `permissionItem`, `resetFailedBody`
- `Sources/PaneMac/PaneMacApp.swift`: wiring
- Tests: `PermissionReducerTests` (16), `TCCResetTests` (3), and new `MenuCopyTests` cases (4)

## Decisions Made
See `key-decisions` in the frontmatter. The launch decision is the one most visible to users. UI-SPEC says the window "appears at launch only if the state is not ready". A trusted launch starts in `probing`, so taking that literally would flash the window on every normal launch. The controller waits for the launch probe instead. It shows the window for `notTrusted` or form A, and stays hidden when the probe reaches ready.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] No-reopen guard on bringWindowForward**
- **Found during:** Task 2/3
- **Issue:** The plan says to call `orderFrontRegardless()` "if the window exists". Pane keeps a closed window alive (`isReleasedWhenClosed = false`), so that call would reopen a window the user had closed, which breaks the no-looping contract.
- **Fix:** It now acts only when `setupWindow.isVisible`.
- **Files modified:** Sources/PaneMac/Permission/PermissionController.swift
- **Committed in:** 5aab429

**2. [Rule 2 - Missing critical] Launch decision waits for the trusted-launch probe**
- **Found during:** Task 3
- **Issue:** Without it, users who already granted access would see the setup window flash ("Checking access", then "Pane is ready") on every launch.
- **Fix:** `SetupWindowController.decideAtLaunch()` defers the decision until the phase leaves `probing`.
- **Files modified:** Sources/PaneMac/Permission/SetupWindowController.swift, Sources/PaneMac/PaneMacApp.swift
- **Committed in:** 6b9944c

---

**Total deviations:** 2 auto-fixed (2 missing critical). **Impact on plan:** both enforce the UI-SPEC no-looping contract. No scope creep.

## Issues Encountered
- xcodebuild still logs the unrelated "CoreSimulator is out of date" notice. The build and signature checks pass.

## Human checks for phase UAT (end-of-phase)
1. Run `tccutil reset Accessibility com.eightabyte.pane.debug`, then `scripts/run-debug.sh --no-build`. Expected: S1 with a default "Open System Settings" button. The macOS prompt appears exactly once. After you turn on "Pane Debug", the window shows "Pane is ready" with no click, and the glyph switches from the warning triangle to `rectangle.split.2x1`.
2. Form B: copy the app to the scratchpad, re-sign only the copy ad hoc, launch the copy and click Open System Settings. Expected: "Already turned on?" appears after 15 s, not before. Reset Permission shows "Resetting permission…" with every button disabled, then "Turn Pane on again".
3. Close the setup window while not ready. Expected: it never reopens by itself, and the menu's "Grant Accessibility Access…" (or "Fix…" when stale) reopens it. Esc and ⌘W close it, except while resetting.
4. Backstop: with a long CFBundleName, the body text wraps at 480 pt and the window height follows each state. Nothing is truncated (`.intrinsicContentSize` sizing has not been checked visually yet).
5. Form A (AX probe -25211) has not been reproduced locally. It is covered only by the reducer tests.

## User Setup Required
None. No external service configuration required.

## Next Phase Readiness
- 02-08 (Tracked Windows) can call `SetupWindowController.show()` for its Grant/Fix button and observe `PermissionController.state`.
- No blockers.

## Self-Check: PASSED
- All 8 created files exist. Commits abbc682, 1d71082, 996a747, 5aab429, 2fe5ac4 and 6b9944c are on HEAD.
- `swift test` passes all 219 tests. `scripts/build-debug.sh` ends in "Pane Debug.app" and its signature checks pass. `scripts/check-no-appkit.sh` passes.

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
