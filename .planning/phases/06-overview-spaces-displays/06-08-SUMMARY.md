---
phase: 06-overview-spaces-displays
plan: 08
subsystem: overview
status: complete
tags: [overview, selection, keyboard, key-panel, hover, over-01, d-04]
requires:
  - phase: 06-06
    provides: "OverviewController, OverviewLayout (tiles, thumbnails, item(at:)), StagePanel overview overlay"
  - phase: 06-07
    provides: "OverviewController.pick(_:) for thumbnails and mini tiles, switchAway, focusWindow"
provides:
  - "OverviewSelection (Engine, pure): initial cascade, arrows (45° cone, front-most on ties), strip ↑/↓/←/→, Tab/⇧Tab by display frame, reselect(afterRemoving:)"
  - "OverviewLayout.display(at:) (public), OverviewLayout.ordered, OverviewLayout.titleCapsule(tile:mainArea:size:)"
  - "Overview keys through a non-activating key panel (StagePanel.takesKeys / onKey); OverviewController.holdsKeys for tests"
  - "Same-Space pick: Return or click on a main-area tile raises it, reverses the stage and focuses the window"
  - "Hover selection, accent selection ring, selected snapshot tile title capsule, mini tile label swap, pointing hand"
  - "OverviewController.windowClosed(_:) (wired from ArrangeController .windowDestroyed) reselects"
  - "dispatchAppKitEvents() in IntegrationSupport: event pump that survives AppKit's tracking-area run loop stops"
  - "Fixture `typed` command: characters the fixture app received"
affects: [06-09, 06-10, 06-12]
tech-stack:
  added: []
  patterns:
    - "Keyboard while an overlay is open: a non-activating NSPanel that can become key only while open (canBecomeKey = takesKeys), keyDown overridden without super, so ignored keys are dropped without a beep"
    - "Integration tests dispatch AppKit events from a block run inside a nested CFRunLoopRunInMode, never from the test helper's outer main loop"
key-files:
  created:
    - Sources/TransomEngine/OverviewSelection.swift
    - Tests/TransomEngineTests/OverviewSelectionTests.swift
    - Tests/TransomMacIntegrationTests/OverviewKeyboardIntegrationTests.swift
  modified:
    - Sources/TransomEngine/OverviewLayout.swift
    - Sources/TransomMac/Overview/OverviewController.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Sources/TransomFixtureApp/main.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
    - Tests/TransomMacIntegrationTests/OverviewIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/IntegrationSupport.swift
    - .planning/phases/06-overview-spaces-displays/06-UI-SPEC.md
key-decisions:
  - "Rule 4 (user, 2026-10-31): overview keys come from a non-activating key panel, not temporary Carbon hotkeys; macOS 15 never delivers modifier-less Return, keypad Enter, Tab or Space as Carbon hotkeys. Other keys are ignored while the overview is open. The event tap mask is unchanged (T-03-28)"
  - "Key focus is released on every close path by clearing takesKeys in close(); the panel hands key back to the frontmost app when it orders out at the end of its fade (≤ ~370 ms after a dismiss); keys pressed in that window are dropped"
  - "Tab lands on the target display's initial item with the focused window counted and the pointer not; with one display Tab does nothing"
  - "From a mini tile the arrows act as from its thumbnail; arrows never land on a mini tile"
  - "Ring radius: snapshot tile 12 × display scale, fallback/collapsed tile min(12, shorter side / 2), mini tile 12 × thumbnail scale (≥ 2), thumbnail 12 outset 4"
  - "Hover uses a .activeAlways tracking area on the stage view (mouseMoved), so it works on every display's panel, not only the key one"
requirements-completed: []  # OVER-01 completes with 06-09's parked-window picks (camera move); same-Space picks are done here
duration: ~30min
completed: 2026-10-31
metrics:
  duration: "~30 min (continuation after the Rule 4 checkpoint; the first attempt's time is not counted)"
  started: 2026-10-31T20:08:10Z
  completed: 2026-10-31T20:40:00Z
actuals:
  tokens: 18000
  tasks: 3
  commits: 4
plan_head_before: 8efab78237625ecca767528aa8d1f18109f30140
plan_head_after: 31dd928c72197611f434e71b3fefa95f682140f7
---

# Phase 6 Plan 08: Overview Selection and Keyboard Summary

One shared overview selection driven by the keyboard (through a non-activating key panel, after macOS 15 refused modifier-less Return/Tab/Space Carbon hotkeys) and by the pointer. It is drawn as a 2 pt accent ring with the selected window's title capsule. Return on a same-Space tile raises and focuses that window.

## What was built

- **OverviewSelection (Engine, AppKit-free).** Initial selection: the focused window if shown, else the tile under the pointer, else the largest tile on the pointer's display, else that display's current-Space thumbnail, else the largest tile on the first display left to right. Arrows use the Phase 3 rule (nearest centre in a 45° cone, then any centre on that side; equal distances go to the front-most window). ↑ from the top row enters the strip at the thumbnail nearest in x, ↓ returns to the tile nearest in x, and ← → step between thumbnails. Edges do nothing. Tab and ⇧Tab order displays by frame (left edge, then top edge, then UUID) and wrap. A closed selected window hands the selection to the nearest remaining tile, or else to the current-Space thumbnail.
- **Keys.** While the overview is open, one stage panel is key without activating Transom. It handles Esc, ← → ↑ ↓, Tab, ⇧Tab, Return and keypad Enter. Every other key is dropped silently. The Carbon overview streams are gone. Only ⌃⌥⌘A (KeyboardShortcuts) remains a hotkey.
- **Picks.** Return or a click on a main-area tile logs `pick window {id} on space {sid} (same space)`, puts that tile on top, starts the reverse animation and sends the focus command. Return on a thumbnail or mini tile goes through the 06-07 pick paths.
- **Pointer and visuals.** Moving the pointer onto an item selects it, and the backdrop, gaps and the empty capsule keep the current selection. The selection ring is 2 pt controlAccentColor at 85% (100% with Increase Contrast). It sits inside tiles and mini tiles, and 4 pt outside thumbnails at radius 12. It fades in over 80 ms and out over 120 ms. A selected snapshot tile shows a Body title capsule: 8 pt above its bottom edge, or 8 pt below a short tile, kept inside the main area, at most the tile's width minus 32. A selected mini tile swaps its thumbnail's label to the window title in Label Regular. The cursor is a pointing hand over items and an arrow elsewhere.

## Verification

- `scripts/vm-live-test.sh OverviewKeyboardIntegrationTests` passes in the VM (macOS 15.7.7 guest). It checks four things.
  - The focused window is the initial selection.
  - Arrows and Return: → selects the right window, a second → at the edge does nothing, Tab with one display does nothing, and Return closes the overview and focuses the right window.
  - Hover and other keys: hovering the left tile selects it. While the overview is open, "x" does nothing and never reaches the fixture.
  - Key hand-back: the panel stops being key, and the fixture receives the next letter, after each of six close paths: Return (pick), Esc, the Show Overview toggle, `interrupt` (the Space switch / focus / command / session path), `displaysChanged` (the display change / zoom off path) and a click near the screen edge.
- Regression in the VM: `OverviewIntegrationTests` (1 test) and `OverviewSpaceSwitchIntegrationTests` (2 tests) pass.
- `swift test --filter 'TransomEngineTests|OverviewCopyTests|TileLayerTests'`: 789 + 10 tests pass, no ✘. `OverviewSelectionTests` has 25 tests. `scripts/check-no-appkit.sh` passes.
- `grep -c keyDown Sources/TransomMac/Input/InputTap.swift` prints 0, so the tap mask is unchanged. `kCGWindowName` does not appear in OverviewController.swift.

## Deviations from Plan

### Rule 4: architectural change (user decision 2026-10-31)

**1. Overview keys come from a non-activating key panel, not temporary Carbon hotkeys.**
- **Found during:** Task 1, VM verify. In the macOS 15.7.7 guest, modifier-less Carbon hotkeys registered fine and fired for arrows, Esc and F-keys, but never for Return, keypad Enter, Tab or Space (`.build/0608-t1-vm-diag.log`).
- **Decision:** Option A, "Overview takes keyboard". While open, the StagePanel is key without activating Transom (`canBecomeKey` is true only while open) and handles the overview keys in `keyDown`. Other keys are ignored, like Mission Control. No RegisterEventHotKey for overview navigation. No keyboard tap.
- **Consequences:**
  - The plan's must-have "any other key reaches the frontmost app and the overview stays open" changed to "other keys do nothing while open; after close the frontmost app gets keys again", and the VM test asserts the new rule.
  - Task 1's acceptance grep for `Shortcut(.return)` / `Shortcut(.leftArrow)` / `Shortcut(.rightArrow)` is obsolete: those names are absent on purpose.
  - 06-UI-SPEC.md Surface 3 is updated: the key mechanism, the "Any other key" row, and the change note "(changed 2026-10-31: macOS 15 does not deliver modifier-less Return/Tab/Space Carbon hotkeys; user chose key panel)". The Discretion row is updated too.
- **Files:** OverviewController.swift, StagePanel.swift, OverviewKeyboardIntegrationTests.swift, 06-UI-SPEC.md. **Commit:** 40dca27

### Auto-fixed issues

**2. [Rule 3 - Blocking] Integration tests exited with status 0 and no results once the stage had a tracking area.**
- **Found during:** Task 3, VM verify. The suite stopped right after "test started" with rc 0. `OverviewIntegrationTests` failed the same way, silently.
- **Root cause (lldb in the guest):** `-[_NSTrackingAreaAKManager _updateActiveTrackingAreasForWindowLocation:]` → `-[NSEvent _postAtStart:]` → `CFRunLoopStop(main)`, called from inside `nextEvent`. With no NSApp.run, that stop ended the test helper's own `CFRunLoopRun` in `swift_task_asyncMainDrainQueue`, which then calls `exit(0)`. This is normal AppKit behaviour: NSApp.run only loses one wait, so the real app is unaffected.
- **Fix:** `dispatchAppKitEvents()` in IntegrationSupport sends queued events from a block inside a nested `CFRunLoopRunInMode`, so the stop ends the nested run. Both overview suites use it.
- **Files:** IntegrationSupport.swift, OverviewKeyboardIntegrationTests.swift, OverviewIntegrationTests.swift. **Commit:** 31dd928

**3. [Rule 2 - Missing] Fixture `typed` command.** The plan asked to check that the fixture received the key "if available". It wasn't, so the fixture now records the characters typed into it (a local keyDown monitor that swallows the event, so no beep). Commit 40dca27.

### TDD note

Task 2's RED commit (a0628de) also adds signature-only stubs (`reselect(afterRemoving:in:)` as a no-op and the `focused:` parameter on `move`). Without them the tests would not compile, and the plan wants RED to fail on assertions. The RED run failed 20 issues across the new behaviours. The Task 1 behaviours (cone, ties, edges, focused-first, largest) already passed.

## Notes for later plans

- **06-09:**
  - Its text says `interrupt(reason:)` "cancel keys and hover monitor". Under this plan that means `releaseKeys()`, which already runs in `close()` on every path. The hover is a tracking area on the stage view, not an NSEvent monitor, so there is nothing to remove.
  - `.windowDestroyed` already calls `OverviewController.windowClosed(_:)` → `selection.reselect`. 06-09 adds the 120 ms tile fade-out. The layout still holds the closed window's tile until then, so an arrow could land on it, and picking it only fails to focus.
  - VoiceOver selection announcements hang off `selection`'s `didSet` (`markSelection`).
- **06-10:** the takeover's F3 / ⌃↑ keys stay Carbon hotkeys (they have modifiers or are F-keys, which macOS 15 delivers). Whether a Carbon hotkey still fires while the overview panel is key has not been tested in the VM. That covers ⌃⌥⌘A closing the overview (the test used the dispatch path) and F3. Check it in 06-10's VM test or 06-12 UAT.
- **06-12 UAT:**
  - The ring, the title capsule and the cursor are human-check items.
  - After Esc, the frontmost app gets keys back once the stage has faded (≤ ~370 ms). Keys typed sooner are dropped.

## Known Stubs

None.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: input-focus | Sources/TransomMac/Zoom/StagePanel.swift | Transom now takes keyboard focus (non-activating key panel) while the overview is open. Mitigated as T-06-22 was: only while open, `takesKeys` cleared in the single `close()` used by every path, and the VM test asserts key hand-back after six close paths |

## Self-Check: PASSED

- FOUND: Sources/TransomEngine/OverviewSelection.swift, Tests/TransomEngineTests/OverviewSelectionTests.swift, Tests/TransomMacIntegrationTests/OverviewKeyboardIntegrationTests.swift
- FOUND commits: 40dca27, a0628de, 927f649, 31dd928 (4 = `git rev-list --count 8efab78..HEAD`)
