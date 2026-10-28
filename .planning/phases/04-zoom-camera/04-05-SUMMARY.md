---
phase: 04-zoom-camera
plan: 05
subsystem: zoom
status: complete
tags: [shell, hotkeys, url-scheme, menu, swiftui, keyboardshortcuts]
requires:
  - phase: 04-03
    provides: "Command.camera, ArrangerInput.camera(_:displayUUID:focused:pointer:), CommandContext.displayUUID, cameraAvailable, isFramingFocused/Desktop, MenuCopy.cameraTitle, Navigator.Refusal"
  - phase: 04-04
    provides: "ZoomController (onRevealed, captureState, lastSettle, cacheStats, purge), SnapshotCapture.isGranted/request, ZoomCopy"
provides:
  - "11 zoom hotkeys (zoomOutAll, stepOut, stepIn, zoomBack, zoomForward, panLeft, panRight, panUp, panDown, frameWindow, frameDesktop) on the ctrl-opt-cmd base"
  - "Hotkeys.zoomNames, setZoomHotkeys(enabled:), logSystemConflicts()"
  - "11 transom:// hosts (zoom-out ... frame-desktop) in the strict whitelist"
  - "ArrangeController: camera dispatch on the pointer's display, pointerDisplay(), isZoomEnabled, setZoomEnabled(_:) (home first, then off), onViewChanged"
  - "CommandMenu: camera items, moveViewMenu, zoomSection(enabled:framingWindow:framingDesktop:previews:toggle:)"
  - "Status menu Zoom section, Allow Window Previews..., Turn Off/On Zoom, Shortcuts..., Debug zoom lines, 'Transom: zoomed in'"
  - "ShortcutsModel / ShortcutsView / ShortcutsWindowController (44 Recorder rows, duplicate check, Mouse toggle, Restore Defaults)"
  - "Preference key zoomTitleBarDoubleClick (ShortcutsModel.doubleClickKey), default on, for 04-06's double-click input"
affects: [04-06, 04-07, 04-08]
estimate:
  tokens: 100000
  tasks: 3
actuals:
  tokens: 9500
  tasks: 3
  commits: 6
plan_head_before: 87b4a9d739ea358974d5fafe2bc796596d099972
plan_head_after: 9fd5bd09a089780e50ea040aae9ebd9ef464dda1
tech-stack:
  added: []
  patterns:
    - "Camera commands skip the generic availability gate and go straight to the engine, so a refusal beeps and announces its Surface 1 reason; the shell refuses only for not-ready and no display"
    - "Zoom hotkeys are disabled with KeyboardShortcuts.disable while zoom is off; menuDidClose re-enables only what zoom allows"
    - "ShortcutsModel derives every row title from Hotkeys.entries through ZoomCopy.shortcutTitle, so a row and its menu item cannot drift"
key-files:
  created:
    - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
    - Tests/TransomMacTests/ShortcutsModelTests.swift
  modified:
    - Sources/TransomMac/Input/Hotkeys.swift
    - Sources/TransomEngine/TransomURL.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Sources/TransomMac/Shell/CommandMenu.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Shell/ZoomCopy.swift
    - Tests/TransomMacTests/HotkeyTableTests.swift
    - Tests/TransomEngineTests/TransomURLTests.swift
    - Tests/TransomMacTests/CommandMenuTests.swift
    - Tests/TransomMacTests/ZoomCopyTests.swift
key-decisions:
  - "Camera commands bypass Arranger.availability in dispatch: the engine's camera() returns [.beep, .announce, .info] for each refusal, while the availability gate would only beep. URL sources drop .beep and .announce"
  - "setZoomHotkeys and logSystemConflicts run in TransomMacApp right after Hotkeys.register, not in ArrangeController.start, because start() waits for Accessibility and the chords must pass through from launch"
  - "Turn Off Zoom sends .zoomTo(.home) to every display and waits only for the ones that produced a .cameraMove; a 3 s fallback finishes the switch if a reveal never comes"
  - "ZoomController.onRevealed is owned by ArrangeController (revealed(_:)), which feeds both the Turn Off wait and onViewChanged for the status description"
  - "Before the first move the Debug capture line uses a fresh CGPreflightScreenCaptureAccess (only with zoom on), since captureState is a placeholder until then"
requirements-completed: []
coverage:
  - id: D1
    description: "11 zoom hotkeys with the UI-SPEC raw names, defaults and Command.camera mappings; Phase 3's 33 names kept; comma and period used only by stepOut/stepIn; ctrl-opt-cmd-8 unused"
    requirement: ZOOM-08
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/HotkeyTableTests.swift#HotkeyTableTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "11 transom:// hosts parse to their camera commands; uppercase, query, path, fragment and unknown hosts are rejected"
    requirement: ZOOM-09
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/TransomURLTests.swift#theZoomCommandsParse"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/TransomURLTests.swift#malformedZoomURLsAreRejected"
        status: pass
    human_judgment: false
  - id: D3
    description: "Zoom section: camera items with live shortcuts, Move View submenu order, frame checkmarks, greying while paused, zoom off shows only the header and Turn On Zoom, previews item only when passed"
    requirement: ZOOM-10
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/CommandMenuTests.swift#ZoomCommandMenuTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Menu, announcement, Debug (explicit plurals) and Shortcuts window copy"
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/ZoomCopyTests.swift#ZoomCopyTests"
        status: pass
      - kind: unit
        ref: "Tests/TransomMacTests/ShortcutsModelTests.swift#theWindowCopyMatchesTheContract"
        status: pass
    human_judgment: false
  - id: D5
    description: "Shortcuts window model: 6 sections, 44 rows binding every Hotkeys name once, Surface 8 titles, in-Transom duplicate message"
    requirement: ZOOM-08
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/ShortcutsModelTests.swift#ShortcutsModelTests"
        status: pass
    human_judgment: false
  - id: D6
    description: "Hotkey, menu and URL zoom on the pointer's display end to end; Turn Off Zoom goes home first then removes the stage; zoom off lets the chords reach apps"
    requirement: ZOOM-01
    verification:
      - kind: manual_procedural
        ref: "VM UAT (04-08 / verify-work)"
        status: unknown
    human_judgment: true
  - id: D7
    description: "Shortcuts window look and behaviour: recording, duplicate alert, system-conflict 'Use Anyway', Restore Defaults confirm/cancel, remembered frame, Mouse toggle disabled with zoom off"
    requirement: ZOOM-08
    verification:
      - kind: manual_procedural
        ref: "VM UAT (04-08 / verify-work)"
        status: unknown
    human_judgment: true
  - id: D8
    description: "Pan keys fire from fn+arrows on a built-in keyboard and macOS window tiling does not also act (UI-SPEC backstop)"
    requirement: ZOOM-09
    verification:
      - kind: manual_procedural
        ref: "VM UAT backstop"
        status: unknown
    human_judgment: true
duration: 9min
completed: 2026-10-28
---

# Phase 4 Plan 05: Hotkeys, URLs, Zoom Menu and Shortcuts Window Summary

**Every zoom command can now be triggered and rebound. There are 11 ⌃⌥⌘ hotkeys and 11 `transom://` URLs, and both act on the display under the pointer. The status menu has a Zoom section with live shortcuts, checkmarks, Allow Window Previews… and Turn Off / Turn On Zoom. Turning zoom off first moves every display home. The Shortcuts window has 44 KeyboardShortcuts Recorder rows, rejects duplicate bindings, and offers a confirmed Restore Defaults and the double-click Mouse toggle.**

## Performance

- **Duration:** about 9 min of execution (2026-10-28T15:20Z to 15:28Z), plus reading before that
- **Tasks:** 3 (Task 1 tracer; Tasks 2 and 3 RED then GREEN)
- **Files:** 2 created, 11 modified (+646 / −17)

## Task Commits

1. **Task 1 (tracer): hotkeys and URLs**: RED `8be9f45`, GREEN `94731e5`
2. **Task 2: Zoom menu section and toggle**: RED `330f236`, GREEN `65da7b1`
3. **Task 3: Shortcuts window, Debug lines, zoomed-in status**: RED `15108fd`, GREEN `9fd5bd0`

## TDD

- **Task 1 RED (`8be9f45`):** the build failed with "type 'Hotkeys' has no member 'zoomNames'". The URL tests compiled but had no hosts to parse. **GREEN (`94731e5`):** the plan filter `HotkeyTableTests|TransomURLTests|CommandTests` ran 11 + 32 tests and all passed. **Tracer gate** (end-of-phase mode, automated-only verify): I re-ran the same filter after the commit (11 + 32 passed) before starting Task 2.
- **Task 2 RED (`330f236`):** the build failed with "type 'ZoomCopy' has no member 'zoomSection'". **GREEN (`65da7b1`):** 43 tests in 6 suites passed on `CommandMenuTests|MenuCopyTests|ZoomCopyTests`. I renamed the new suite `ZoomCommandMenuTests` so the plan's filter matches it. I also marked its static argument list `nonisolated` so the `@Test(arguments:)` macro compiles.
- **Task 3 RED (`15108fd`):** the build failed with "cannot find 'ShortcutsModel' in scope". **GREEN (`9fd5bd0`):** the full headless `swift test` passed, ShortcutsModelTests included.

## Sanctioned HotkeyTableTests changes

These are the only changes, and each comes from a locked decision (CONTEXT C, UI-SPEC Surface 8):
1. `entriesMapStableNamesToCommands` and `defaultsAreControlOptionCommandPlusALetter`: the lists gained the 11 zoom names, commands and defaults at the end. The 33 Phase 3 entries are unchanged.
2. `theTableHasExactlyThe33UISpecNames` became `theTableKeepsThe33Phase3Names`. The 33-name set is still asserted verbatim, but as a subset of the table (`spec.isSubset(of:)`) instead of equal to it. The `entries.count == 33` assertion moved to the new `theZoomNamesAreExactlyTheUISpecEleven` as `entries.count == 44`. The two removed `#expect` lines are exactly these.
3. `noEntryUsesAShortcutReservedByMacOSAccessibility`: ⌃⌥⌘, and ⌃⌥⌘. left the reserved list. ⌃⌥⌘8 stays reserved. The new `commaAndPeriodAreUsedOnlyByStepOutAndStepIn` pins those two keys to stepOut and stepIn only.

The expectation guard found 6 `(04-05)` commits. `grep -c '^-.*#expect'` over the Tests diff, excluding HotkeyTableTests, prints **0**.

## Verification

- **Full headless `swift test`:** 193 (TransomModel) + 237 (TransomMac) + 46 (integration, which skips live without TRANSOM_LIVE) + 632 (TransomEngine) = **1108 Swift Testing tests passed**, no "✘". `FreezeTestTests.itResumesByItself` passed in this run.
- **`scripts/check-no-appkit.sh`:** OK (44 files). ScreenCaptureKit is still imported only in `SnapshotCapture.swift`. ZoomController only mentions it in a comment.
- **Acceptance greps:**
  - Each of the 11 `Self("<name>"` lines appears once in Hotkeys.swift.
  - `"frame-desktop"` in TransomURL: 1.
  - `"focusLeft"` in HotkeyTableTests: 2.
  - `ignored: zoom off`: 1.
  - `Allow Window Previews…` in ZoomCopy: 1.
  - `Privacy_ScreenCapture` in StatusItemController: 1.
  - `func setZoomEnabled`: 1.
  - `onRevealed` in ArrangeController: 1.
  - `KeyboardShortcuts.Recorder`, `setFrameAutosaveName("Shortcuts")` and `zoomTitleBarDoubleClick` in ShortcutsWindowController: 1 each.
  - `Shortcuts…`: 1 (in ZoomCopy; StatusItemController uses `ZoomCopy.shortcutsItem`).
- **No live or VM run.** The plan is headless only.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Closing the status menu would have re-enabled the zoom chords while zoom is off**
- **Found during:** Task 2
- **Issue:** `menuDidClose` enabled every name in `Hotkeys.entries`, which now includes the zoom names. Opening and closing the menu would have broken D-D, because the chords would stop reaching apps.
- **Fix:** `menuDidClose` re-enables the zoom names only while zoom is on.
- **Commit:** 65da7b1

**2. [Rule 2 - Correctness] Camera refusals announce their reason**
- **Issue:** the generic `dispatch` path checks `Arranger.availability` first and only beeps. The UI-SPEC says no zoom hotkey fails silently: each one beeps and announces its Surface 1 reason.
- **Fix:** `.camera` goes to `dispatchCamera`, which feeds the engine directly. The engine returns the refusal with its announcement. The shell adds the not-ready refusal ("Transom needs Accessibility access") and a beep-only "no display under the pointer" case. URL sources drop `.beep` and `.announce`.
- **Commit:** 94731e5

**3. [Rule 3 - Blocking] Zoom hotkeys disabled at launch in TransomMacApp**
- **Issue:** the plan put `setZoomHotkeys(enabled:)` in `ArrangeController.start()`. `start()` waits for Accessibility, so with zoom off the chords would have been swallowed until then.
- **Fix:** both calls go right after `Hotkeys.register` in `TransomMacApp.swift`, a file outside the plan's list (2 lines).
- **Commit:** 94731e5

**4. [Rule 2 - Robustness] Turn Off Zoom cannot hang**
- **Issue:** if a home move never reveals (for example its display was unplugged mid-move), waiting for `onRevealed` would keep zoom on forever.
- **Fix:** displays whose `.zoomTo(.home)` produced no `.cameraMove` (already home, paused, no desk) are not waited for. A 3 s fallback timer finishes the switch. That covers the 1500 ms settle cap plus the capture, move and fade times. A second Turn Off during the wait is ignored.
- **Commit:** 65da7b1

**5. [Test naming] `ZoomCommandMenuTests`**
- The new suite is named to match the plan's `CommandMenuTests` filter, as 04-03 did.

---

**Total deviations:** 4 auto-fixed (Rules 1, 2 and 3), 1 note. **Impact:** no scope change and no new architecture.

## Known Stubs

None. Grepping the changed files for `TODO`, `FIXME`, `placeholder` and `coming soon` finds nothing new.

## Notes for later plans and UAT

- `CGRequestScreenCaptureAccess()` also returns false when it has just shown the first-time prompt. Allow Window Previews… may therefore show the macOS prompt and open the Screen Recording pane at the same time. This follows the UI-SPEC recovery path literally. Check it in UAT.
- Turning zoom off while paused: the move home is refused (paused). The engine still drops the camera and re-plans, and parked windows return when arranging resumes.
- UI-SPEC says "`transom://restore` additionally returns every display's camera to home". That is not part of this plan and is not implemented here. It belongs with Restore All (04-07 or 04-08).
- `zoomTitleBarDoubleClick` is only stored here. 04-06 reads it (`ShortcutsModel.doubleClickKey`).
- The status description updates on every reveal and on zoom off. It does not update when the pointer simply moves to another display (no mouse tracking), so it can be stale until the next reveal.
- The VoiceOver letter-chord fallback is not implemented. Phase 3 has no such fallback to extend (plan objective).

## Threat Flags

None new.
- T-04-17: exactly 11 hosts in the unchanged strict parser and rate limiter. Zoom URLs are ignored and logged while zoom is off. URL refusals are silent.
- T-04-18: `KeyboardShortcuts.disable` on the 11 names while zoom is off (launch, Turn Off, and after the menu closes).
- T-04-19: raw names asserted verbatim. Restore Defaults resets only `Hotkeys.entries` names.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Zoom/ShortcutsWindowController.swift, Tests/TransomMacTests/ShortcutsModelTests.swift
- FOUND commits on HEAD: 8be9f45, 94731e5, 330f236, 65da7b1, 15108fd, 9fd5bd0
- Measured commits: `git rev-list --count 87b4a9d..HEAD` = 6

---
*Phase: 04-zoom-camera*
*Completed: 2026-10-28*
