---
phase: 03-tiling-mvp
plan: 15
subsystem: app-lifecycle
status: complete
tags: [quit-restore, safety, url-scheme, app-delegate, sigterm]
requires:
  - 03-07 (layout.json, writeCleanExit)
  - 03-08 (home frames, park)
  - 03-14 (Recovery.isStranded/destination, Command.restoreAll, crash path)
provides:
  - Recovery.terminationPlan
  - AXAppThread.writeForTermination, AXWindowSystem.restoreForTermination, ArrangeController.restoreForTermination
  - AppDelegate (terminateLater quit restore, SIGTERM, application(_:open:))
  - PaneURL.parse, PaneURLRateLimiter, CommandSource, ArrangeController.dispatch(_:from:)
  - PANE_URL_SCHEME build setting (pane-debug in Debug, pane in Release), xcode/Pane-Info.plist
affects:
  - Phase 8 (generalises the URL scheme on top of PaneURL)
tech-stack:
  added: []
  patterns:
    - "Bounded synchronous AX writes at quit: CFRunLoopPerformBlock on the app's thread plus a DispatchSemaphore with a shared deadline, fanned out per app with a DispatchGroup"
    - "Strict whitelist URL parsing on percent-encoded URLComponents fields"
key-files:
  created:
    - Sources/PaneMac/AppDelegate.swift
    - Sources/PaneEngine/PaneURL.swift
    - xcode/Pane-Info.plist
    - Tests/PaneEngineTests/PaneURLTests.swift
    - Tests/PaneMacTests/AppDelegateTests.swift
    - Tests/PaneMacIntegrationTests/QuitRestoreIntegrationTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-15-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-15-task2-red.json
  modified:
    - Sources/PaneEngine/Recovery.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/PaneMacApp.swift
    - xcode/project.yml
    - Tests/PaneEngineTests/RecoveryTests.swift
decisions:
  - "A window with a home frame that is not docked counts as parked at quit even when it is not stranded, since the park corner of one display can be mostly visible on a display to its right; it goes home on the display that holds its home frame's centre"
  - "The quit restore leaves windows that are docked and on screen, excluded, never-dock or not present alone; a docked window that is stranded is centred on its display"
  - "A URL-sourced command that cannot act is silent on both refusal paths: the availability check and the Arranger's own .beep effects"
  - "The URL rate limit counts only admitted commands, so a burst cannot keep a command blocked"
  - "The expected URL scheme comes from the bundle's first CFBundleURLSchemes entry; run outside the app bundle (swift run) every URL is rejected"
metrics:
  duration: 10 min
  completed: 2026-10-26
  tasks: 2
  files: 15
estimate:
  tokens: 90000
  tasks: 2
actuals:
  tokens: 12000
  tasks: 2
  commits: 4
plan_head_before: 2ddb90ce291e46ddb0d52b10a332e70d5e85a8b3
plan_head_after: 8d6f2022b7e71b7c8593eab29290cf12a315f3e0
---

# Phase 3 Plan 15: Quit Restore and pane:// URL Commands Summary

Every normal quit (menu, ⌘Q, logout, SIGTERM from `killall`) now waits up to 2 s while each parked or off-screen window goes back to its home frame, clamped on screen. A window with no home frame is centred on its display instead. After that Pane records `cleanExit` and exits. A hung app is abandoned at the deadline. `pane://` (Release) and `pane-debug://` (Debug) accept exactly `restore`, `toggle-desktop` and `split-finder`. Each one goes through the same dispatcher as its hotkey and menu item, runs at most once a second, and never beeps.

## What was built

- **`Recovery.terminationPlan` (PaneEngine, pure).** It covers dockable, present, non-excluded windows. A window with a home frame that is not docked goes to that frame, clamped onto the display that holds the frame's centre. Any other stranded window goes to its `destination` on its own display. A docked window on screen is left out of the plan.
- **`AXAppThread.writeForTermination`.** It runs the existing `FrameWriter` sequence as one block on the app's own thread, outside the latest-wins queue, and blocks on a semaphore until the deadline. It returns true only for a finished write with a read-back.
- **`AXWindowSystem.restoreForTermination`.** It skips excluded apps, untracked windows and invalid rects, the same way `perform` does, and addresses each window's visible tab. It runs one global-queue worker per app under a `DispatchGroup` and waits for all of them until the shared deadline. Nothing in it needs the main queue (Pitfall 14).
- **`ArrangeController.restoreForTermination(limit:)`.** It builds the plan from the Arranger's windows, home frames, displays and docked set, and logs how many of the planned writes finished.
- **`AppDelegate`.**
  - `applicationShouldTerminate` returns `.terminateLater`. It then runs restore, the `cleanExit` write and `reply(toApplicationShouldTerminate: true)`, in that order, on the main queue.
  - The `cleanExit` write moved here from the `willTerminate` observer. That observer still resumes a Debug-frozen app (Chesterton's Fence).
  - SIGTERM is ignored as a signal and handled by a `DispatchSource`, which calls `NSApp.terminate(nil)`.
  - `application(_:open:)` parses each URL against the bundle's registered scheme. It logs a rejection (category `url`) without the URL's contents, rate-limits, and dispatches from `.url`.
- **`PaneURL` / `PaneURLRateLimiter`.**
  - `PaneURL` accepts only the exact scheme and a host of `restore`, `toggle-desktop` or `split-finder`. The URL may not carry a user, password, port, query (even an empty `?`) or fragment, and its path must be empty or `/`. Every check reads the percent-encoded fields, so `re%73tore` is rejected.
  - `PaneURLRateLimiter` admits a command at most once per second, counted separately for each command.
- **`ArrangeController.dispatch(_:from:)` with `CommandSource { hotkey, menu, url }`.** Hotkeys and menu items keep the default (`.hotkey`), and their behaviour is unchanged. A `.url` dispatch drops the refusal beep and filters `.beep` out of the Arranger's effects. A `beep` seam replaces the direct `NSSound.beep()` calls.
- **Xcode.** `project.yml` sets `INFOPLIST_FILE: Pane-Info.plist` next to `GENERATE_INFOPLIST_FILE`, plus `PANE_URL_SCHEME` per configuration. `Pane-Info.plist` holds only `CFBundleURLTypes`. The built Debug app's Info.plist lists `pane-debug` under the URL name `com.eightabyte.pane`, and `LSUIElement` and the generated keys are still there (A17 confirmed).

## Tasks

1. **Task 1 (tracer): quitting returns a parked fixture window to its home frame before Pane exits.** `d6fe465` (test, RED), `cafc591` (feat, GREEN). Tracer gate: the automated `<verify>` passed end to end, including the live `QuitRestoreIntegrationTests` (trusted, not skipped), before Task 2 started. The human check is end-of-phase UAT (`human_verify_mode: end-of-phase`).
2. **Task 2: pane:// restore, toggle-desktop and split-finder, strictly parsed.** `61cb457` (test, RED), `8d6f202` (feat, GREEN).

## TDD Gate Compliance

| Task | RED | Evidence | GREEN |
|------|-----|----------|-------|
| 1 | `d6fe465` | `tdd/03-15-task1-red.json` RED_EVIDENCE_OK (target `aParkedFloatingWindowGoesToItsHomeFrameClampedOnScreen()`). The three terminationPlan rows that expect a move failed on their plan assertions against the empty stub. The empty-plan rows passed. AppDelegateTests failed on `.terminateLater` and on the step order. The live suite, run once at RED and caffeinated, got through its preconditions (window 0 docked, window 1 parked away from home). It then failed on `restored == 1` and on the home frame in both tests. | `cafc591` |
| 2 | `61cb457` | `tdd/03-15-task2-red.json` RED_EVIDENCE_OK (target `theThreeCommandsParse()`). All five parse assertions failed against the nil stub, and both rate-limit rows failed on their admitted sequences. The rejection rows passed, as they must against a parser that rejects everything. The AppDelegateTests URL row failed on its dispatched list, and the beep row failed on `beeps == 0`. | `8d6f202` |

## Verification

- `swift test --filter RecoveryTests`: 17 tests passed. `swift test --filter PaneURLTests`: 4 tests passed, one of them parameterised over 15 rejected URLs. AppDelegateTests: 4 tests passed.
- `caffeinate -d -i swift test --filter QuitRestoreIntegrationTests`: 2 tests passed, not skipped. With the hung fixture SIGSTOPped, the restore returned under 2.5 s with 1 write finished, and the responsive window landed at its target.
- `scripts/build-debug.sh` exited 0, and `plutil -p` on `Pane Debug.app/Contents/Info.plist` shows `"pane-debug"` once. Release was not built, so `pane://` is not registered for any bundle on this Mac.
- `scripts/check-no-appkit.sh`: OK (38 files).
- Full suite. The non-live suites passed: PaneModel 190, PaneEngine 168, PaneMac 424. The live suites ran caffeinated in three bounded batches with the Mac unlocked (13 + 13 + 15 tests passed). The known `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` was skipped (deferred), and the opt-in fullscreen and title-bar-drag tests skipped as usual. No fixtures were left running after any batch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A parked window can look on screen to the stranded rule**
- **Found during:** Task 1, while writing the terminationPlan rows
- **Issue:** `parkedFrame` puts a window at the main display's bottom-right corner. On this Mac a second display sits to the right, so about 60% of a parked window can be visible there, and `isStranded` says no. A plan built only on "stranded" would leave it where it is at quit.
- **Fix:** A non-docked window with a home frame is always in the plan. It goes to the display that holds its home frame's centre, not to the display it is nearest. There is a unit row for this case.
- **Files:** Sources/PaneEngine/Recovery.swift, Tests/PaneEngineTests/RecoveryTests.swift
- **Commit:** `cafc591`

**2. [Rule 2 - Correctness] URL commands are also silent when the Arranger itself refuses**
- **Found during:** Task 2
- **Issue:** Some refusals happen inside `Arranger.handle` (an `.beep` effect), past the availability check. The UI-SPEC says a URL command that can't act does not beep.
- **Fix:** A `.url` dispatch filters `.beep` out of the effects as well.
- **Commit:** `8d6f202`

### Plan items handled differently

- **AppDelegate injection.** The unit test injects `restore`, `writeCleanExit`, `open`, `urlScheme` and `reply` closures rather than a store. The `cleanExit` write stays in `ArrangeController.writeCleanExit`, which owns the store.
- **Extra test file.** `Tests/PaneMacTests/AppDelegateTests.swift` was not in the plan's file list. The plan's behaviour asks for a unit test of the delegate, and this file is it.

## Requirements

- **SAFE-01 complete:** every normal quit path (menu, ⌘Q, logout, SIGTERM) runs the bounded restore, live-tested with fixture windows and a hung fixture.
- **SAFE-03 complete:** `pane://restore` was the last missing entry point; the menu item and hotkey came in 03-14.
- **TILE-15 complete:** `pane://toggle-desktop` adds the URL to the hotkey (03-08) and menu item (03-10).
- **TILE-17 complete:** `pane://split-finder` adds the URL to the hotkey and menu item (03-09).
- The human checks (a real ⌘Q and `killall` on the signed app, and `open pane-debug://…` through LaunchServices) are end-of-phase UAT.

## Known Stubs

None.

## Threat Flags

None. The new surfaces (the URL handler and the quit-time writes) are T-03-40..43 in the plan's threat model. All four are mitigated as planned.

## Self-Check: PASSED

- All created files exist: AppDelegate.swift, PaneURL.swift, Pane-Info.plist, PaneURLTests.swift, AppDelegateTests.swift, QuitRestoreIntegrationTests.swift, and both RED records.
- Commits d6fe465, cafc591, 61cb457 and 8d6f202 are ancestors of HEAD.
