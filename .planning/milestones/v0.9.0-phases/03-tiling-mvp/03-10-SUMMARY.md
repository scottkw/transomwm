---
phase: 03-tiling-mvp
plan: 10
subsystem: status-menu
status: complete
tags: [swift, paneEngine, paneMac, appkit, nsmenu, keyboardshortcuts, pause, gaps, exclusions, tdd, tracer]

requires:
  - phase: 03-tiling-mvp
    provides: "Command enum and Hotkeys table (03-04..03-09), Arranger.isAvailable, ExclusionStore and the window system's exclusion filter (02-13), StatusItemController add…Items sections, MenuCopy"
provides:
  - "CommandMenu: command items built once, setShortcut(for:) from the hotkey table, each calling the same dispatch closure as the hotkeys"
  - "Status menu grouped into Arrange, Safety and Exclusions section headers; Debug (now holding Show Tracked Windows) only when ⌥ is held"
  - "Hotkeys disabled in menuWillOpen and re-enabled in menuDidClose"
  - "CommandContext and Arranger.availability(_:context:): the one rule for greying items and beeping refused commands; isAvailable delegates to it"
  - "Header \"Looking for windows…\" until the first sweep, counting non-closed windows only"
  - "PauseReason (stageManager > crashLoop > user), Arranger.pauseReasons, ArrangerInput.setPaused and .gap; Command.togglePause (⌃⌥⌘P)"
  - "Pause line, Pause/Resume Arranging row, dimmed status glyph with \"Pane: arranging paused\""
  - "GapPreference (UserDefaults key gap, allow-list 0/4/8/12/16/24, default 8) and the Gaps ▸ radio submenu"
  - "Command.toggleExcludeFrontmost (⌃⌥⌘E), handled by ArrangeController with ExclusionStore; a docked window that becomes excluded floats at its frame"
affects: [03-12, 03-14, 03-16, menu, url-scheme, settings]

estimate:
  tokens: 100000
  tasks: 3
actuals:
  tokens: 17400
  tasks: 3
  commits: 6
plan_head_before: 55abcbd0042359c1384791ea64a599b0431e6f14
plan_head_after: 5fc27c761964cf418b2fb6d08df5b078ac324801

tech-stack:
  added: []
  patterns:
    - "Menu items that carry a KeyboardShortcuts binding are created once and re-inserted on every open; only info lines and shortcut-free submenus (Gaps, Never Arrange, Debug) are rebuilt"
    - "CommandMenu answers validateMenuItem with the isEnabled that update(availability:) set, so NSMenu's auto-enabling keeps the availability rule's answer"
    - "Pause is a set of reasons; replan() returns nothing while any is set, and leaving the paused state re-plans once"
    - "Excluded windows are filtered out of the plan in the Arranger (frames, parks, minimums), not only dropped by the window system's filter"

key-files:
  created:
    - Sources/PaneMac/Shell/CommandMenu.swift
    - Sources/PaneMac/GapPreference.swift
    - Tests/PaneMacTests/CommandMenuTests.swift
    - Tests/PaneMacTests/GapPreferenceTests.swift
    - Tests/PaneEngineTests/CommandTests.swift
    - Tests/PaneEngineTests/ArrangerPauseTests.swift
    - Tests/PaneEngineTests/ArrangerExclusionTests.swift
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Command.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Input/Hotkeys.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Tests/PaneMacTests/HotkeyTableTests.swift
    - Tests/PaneMacTests/MenuCopyTests.swift
    - Tests/PaneEngineTests/ArrangerDesktopTests.swift

key-decisions:
  - "Hotkeys and menu items share one closure built in PaneMacApp (Task { await arrangeController.dispatch(command) }); CommandMenu looks up each item's shortcut name from Hotkeys.entries, so the command-to-chord table exists once"
  - "ArrangeController.dispatch checks availability with the real context (frontmost focused window + isReady, wired to the permission state) and beeps on refusal; the Arranger's .command input still checks the ready case itself"
  - "Resume drops lastRequested entries for windows not at their requested frame, so a window moved while paused goes back on Resume without rewriting every tile"
  - "While paused, a window move records the fact only: no clamp, no correction"
  - "Don't Arrange and togglePause availability: toggleExcludeFrontmost is always available to the rule (Exclusions stay enabled paused or not ready); the shell disables its row and beeps when no regular frontmost app qualifies. togglePause is off only when not ready or when stageManager is the only reason"
  - "GapPreference rejects strings and Bools even when they would convert to an allowed number, and writes 8 back over a bad stored value"

patterns-established:
  - "New command rows: add the Command case, a MenuCopy.commandTitle entry, the CommandMenu.commands entry and (if bound) a Hotkeys entry; the status menu places the item"

requirements-completed: [TILE-09, TILE-08, TILE-04, TILE-18]

coverage:
  - id: D1
    description: "Every command menu item shows its hotkey and calls the same dispatcher with the same Command; items are built once"
    requirement: TILE-09
    verification:
      - kind: unit
        ref: "swift test --filter CommandMenuTests"
        status: pass
      - kind: unit
        ref: "swift test --filter CommandTests"
        status: pass
  - id: D2
    description: "Pause/Resume Arranging: nothing is sent while paused, Resume re-applies the layout; Stage Manager alone cannot be resumed"
    requirement: TILE-08
    verification:
      - kind: unit
        ref: "swift test --filter ArrangerPauseTests"
        status: pass
  - id: D3
    description: "Gaps ▸ None/4/8/12/16/24 pt, saved with an allow-list, applied at once or on Resume"
    requirement: TILE-04
    verification:
      - kind: unit
        ref: "swift test --filter GapPreferenceTests"
        status: pass
      - kind: unit
        ref: "swift test --filter ArrangerPauseTests (aGapChange…)"
        status: pass
  - id: D4
    description: "Don't Arrange the frontmost app by menu or ⌃⌥⌘E floats its docked windows and its neighbours reflow"
    requirement: TILE-18
    verification:
      - kind: unit
        ref: "swift test --filter ArrangerExclusionTests|FrontmostExclusionTests"
        status: pass
      - kind: integration
        ref: "caffeinate -d -i swift test --filter ExclusionIntegrationTests"
        status: pass
  - id: D5
    description: "Menu look, ⌥-only Debug, dimmed glyph, ⌃⌥⌘D in the open menu docks once, VO-⌘-H in Safari unaffected"
    verification:
      - kind: manual_procedural
        ref: "Task 3 human-check in 03-10-PLAN.md (end-of-phase UAT)"
        status: unknown
---

# Phase 3 Plan 10: Regrouped status menu, one dispatcher, Pause, Gaps and Don't Arrange Summary

**The status menu is now Arrange / Safety / Exclusions, every command item is a once-built NSMenuItem showing its ⌃⌥⌘ chord and calling the same dispatcher as its hotkey, and the menu adds Pause/Resume Arranging (⌃⌥⌘P), a Gaps ▸ radio list and Don't Arrange “App” (⌃⌥⌘E).**

## Performance

- **Duration:** about 13 min
- **Started:** 2026-10-26T04:11:55Z
- **Completed:** 2026-10-26T04:25:06Z
- **Tasks:** 3 (Task 1 a tracer)
- **Files modified:** 17

## Accomplishments

- `CommandMenu` holds one NSMenuItem per command (Dock, Float, Undo, Focus ▸ Left/Right/Up/Down, Split ▸ Split with New Finder Window, Hide/Show Desktop Tile, Pause/Resume Arranging, Don't Arrange). Each gets `setShortcut(for:)` once, so KeyboardShortcuts observers never pile up.
- `StatusItemController.menuNeedsUpdate` rebuilds in UI-SPEC Surface 1 order with three `NSMenuItem.sectionHeader` headers. Debug appears only when ⌥ is held, and Show Tracked Windows moved into it. `menuWillOpen` / `menuDidClose` disable and re-enable every hotkey.
- `Arranger.availability(_:context:)` is the single rule. Not ready turns every Arrange and Safety command off. Paused turns every Arrange command off. Window-scoped commands need a focused, dockable, non-excluded window. Disabled items keep their titles.
- Pause reasons in the Arranger: facts (closes, moves, rekeys) still change the World, but `replan()` and move corrections emit nothing. Resume clears `user` and `crashLoop` and re-plans once.
- `GapPreference` validates the user-writable `gap` key (T-03-25). A change re-plans at once, or on Resume while paused.
- Don't Arrange for the frontmost app goes through the dispatcher to `ArrangeController.toggleExclusion`. The existing `onChange` → `setExcludedBundleIDs` → `windowChanged` path then makes the Arranger float the app's docked windows at their frames (no undo step), and their neighbours reflow. Excluded windows get no clamp, park or minimum.

## Task Commits

1. **Task 1 (tracer): menu item and ⌃⌥⌘D share one dispatcher, regrouped menu**: `dc22baa` (test, RED), `177632a` (feat, GREEN)
2. **Task 2: Pause/Resume and Gaps**: `a2b590f` (test, RED), `60e442a` (feat, GREEN)
3. **Task 3: Don't Arrange the frontmost app**: `53af59c` (test, RED), `5fc27c7` (feat, GREEN)

## Decisions Made

See `key-decisions` in the frontmatter. In short: the menu and the hotkeys share one closure. Availability is checked in the controller with the real context and again in the Arranger for the ready case. Resume re-sends only tiles whose windows moved. The exclusion toggle's availability lives in the shell, because only AppKit knows the frontmost app.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] An existing test expected a park for an excluded window to be sent and then dropped**
- **Found during:** Task 3 (full `swift test`)
- **Issue:** `ArrangerDesktopTests/anExcludedFloatingWindowIsNeverParked` asserted that the fake's exclusion filter dropped a `.park` for the excluded window. Task 3 requires the Arranger to skip excluded windows entirely ("no frame, no park"), so nothing reaches the filter now.
- **Fix:** The expectation is now `fake.dropped.isEmpty`. The test's other checks (no window parked, frame unchanged, no home frame) are unchanged.
- **Files modified:** Tests/PaneEngineTests/ArrangerDesktopTests.swift
- **Commit:** 5fc27c7

**2. [Rule 2 - Missing functionality] ArrangeController had no way to know the access state**
- **Found during:** Task 1
- **Issue:** The plan says the controller builds `CommandContext` from the permission state, but ArrangeController had no access to it.
- **Fix:** Added `ArrangeController.isReady: () -> Bool`, defaulting to true so tests and integration tests are unaffected. PaneMacApp wires it to `permissionController.state.phase == .ready`.
- **Commit:** 177632a

### Smaller adjustments

- **App-name cache:** the plan asks for a per-pid cache updated on inventory changes. The only per-row lookup on rebuild was the Never Arrange submenu's Launch Services lookup by bundle ID, so names are memoised by bundle ID instead. A miss is not cached, so an app installed later still shows. The Don't Arrange title still reads the one frontmost app's `localizedName`.
- **Test placement:** the "no qualifying frontmost app changes nothing" check went into `FrontmostExclusionTests` in `CommandMenuTests.swift`, so it can run without an AppKit frontmost app. It covers `toggleExclusion(of: nil)` and Pane itself. The beep is the caller's answer to `false`.
- **Verification scope:** following the project's live-test rules, the full 33-test live suite was not run at once. One bounded batch, under `caffeinate -d -i` and after confirming the Mac was not locked, ran `ArrangeIntegrationTests|ExclusionIntegrationTests|FocusParkIntegrationTests`. It skipped the known failure `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop`: 7 tests, 6 passed and 1 skipped (fullscreen, opt-in). No fixtures were left over.

## Verification

- `swift test --filter "CommandMenuTests|MenuCopyTests|CommandTests"`: 19 + 4 tests ran and passed (Task 1). The tracer gate re-ran it before Task 2.
- `swift test --filter "ArrangerPauseTests|GapPreferenceTests|HotkeyTableTests|MenuCopyTests"`: 26 + 7 tests passed (Task 2).
- `swift test --filter "ArrangerExclusionTests|ExclusionScenarioTests|HotkeyTableTests|CommandMenuTests|FrontmostExclusionTests"`: 12 + 11 tests passed (Task 3).
- `PANE_SKIP_AX_INTEGRATION=1 swift test`: 190 + 138 + 33 (live, skipped) + 324 tests, all passing.
- `scripts/build-debug.sh` built and verified `Pane Debug.app`. `scripts/check-no-appkit.sh` exited 0.
- Acceptance greps: sectionHeader 3, setShortcut(for: 1, KeyboardShortcuts.disable/enable 2, modifierFlags.contains(.option) 1, appearsDisabled 1, `static let key = "gap"` 1, `enum PauseReason` in exactly one file, `Self("toggleExcludeFrontmost"` 1.

## Pending Human Check (end-of-phase UAT)

This is Task 3's `<human-check>`. Run Pane Debug and check the following:
- Open the menu without ⌥ and with ⌥.
- Dock Safari and TextEdit, then choose Don't Arrange “Safari”.
- Press ⌃⌥⌘P, close TextEdit's window, and press ⌃⌥⌘P again.
- Set Gaps to 24 pt.
- With the menu open, press ⌃⌥⌘D.
- With VoiceOver on in Safari, press VO-⌘-H.

If VO-⌘-H no longer moves to the next heading, apply the UI-SPEC Accessibility fallback in a gap-closure plan.

## Known Stubs

None. The Safety section currently holds only Pause/Resume. Restore All Windows (plan 14) and Restore macOS Window Settings plus conflict lines (plan 16) are later rows, not stubs.

## Issues Encountered

None beyond the deviation above.

## Next Phase Readiness

- Plans 12, 14 and 16 add rows by extending `Command`, `MenuCopy.commandTitle`, `CommandMenu.commands` and `Hotkeys.entries`, and place them in `addArrangeItems` or the Safety section.
- Plans 14 and 16 set `crashLoop` and `stageManager` through `ArrangerInput.setPaused`. The pause line and glyph already follow them through `onPauseChanged`.
- The paused state does not yet suppress drag previews or gap handles, because no drag code exists yet. The drag plan must check `arranger.pauseReasons`.

## Self-Check: PASSED

- FOUND: Sources/PaneMac/Shell/CommandMenu.swift, Sources/PaneMac/GapPreference.swift, Tests/PaneMacTests/CommandMenuTests.swift, Tests/PaneMacTests/GapPreferenceTests.swift, Tests/PaneEngineTests/CommandTests.swift, Tests/PaneEngineTests/ArrangerPauseTests.swift, Tests/PaneEngineTests/ArrangerExclusionTests.swift
- FOUND commits: dc22baa, 177632a, a2b590f, 60e442a, 53af59c, 5fc27c7
