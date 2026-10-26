---
phase: 03-tiling-mvp
plan: 09
subsystem: finder-split
status: complete
tags: [swift, paneEngine, paneMac, accessibility, finder, menu-press, notices, hotkeys, tdd, tracer]

requires:
  - phase: 03-tiling-mvp
    provides: "Arranger with .wake/.notice/.tick (03-04, 03-06), dock dry run and noRoom (03-05), targetKey and the Desktop leaf (03-01, 03-08), AXAppThread.perform, NoticeQueue/NoticeCopy/toast"
provides:
  - "MenuPress: finds the first enabled ⌘-only N menu item (depth <= 3) by key equivalent and presses it with kAXPressAction"
  - "AXWindowSystem.pressNewWindowItem(pid:) runs MenuPress on that app's AX thread"
  - "Command.finderSplit, ArrangerEffect.openFinderWindow, Notice.finderNoWindow (N9)"
  - "Arranger Finder expectation: target leaf, longer-side edge, known Finder windows, 2 s deadline; the first new Finder window docks after a dry run"
  - "ArrangeController.openFinderWindow: press on Finder's thread, launch a quit Finder first, home-folder fallback"
  - "Hotkey finderSplit (⌃⌥⌘N); fixture File ▸ New Window ⌘N"
affects: [03-10, 03-15, menu, url-scheme]

estimate:
  tokens: 70000
  tasks: 2
actuals:
  tokens: 25900
  tasks: 2
  commits: 4
plan_head_before: ffe3925ca982f1b443d06e5d6b8672ab97ab5103
plan_head_after: f66386ca5cf63e4e7557ec6c24a3326519f6f425

tech-stack:
  added: []
  patterns:
    - "Another app's menu item is found by its key equivalent and modifiers, never by its title, so it works in any localisation and no untrusted string is read"
    - "The shell keeps one wake, so nextWake is the minimum of every pending deadline (corrections and the Finder wait)"

key-files:
  created:
    - Sources/PaneMac/AX/MenuPress.swift
    - Tests/PaneEngineTests/ArrangerFinderTests.swift
    - Tests/PaneMacTests/MenuPressTests.swift
    - Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-09-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-09-task2-red.json
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Command.swift
    - Sources/PaneEngine/Notice.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/Input/Hotkeys.swift
    - Sources/PaneMac/Shell/NoticeCopy.swift
    - Sources/PaneMac/Overlay/NoticeQueue.swift
    - Sources/PaneFixtureApp/main.swift
    - Tests/PaneMacTests/HotkeyTableTests.swift
    - Tests/PaneMacTests/NoticeCopyTests.swift

key-decisions:
  - "nextWake includes the Finder deadline: the shell's single WakeTimer would otherwise let a correction wake replace it, or the Finder wake delay a correction"
  - "A Finder window that opens on another display is taken off that Desktop (World.reflow, no undo step) and docked on the target desk, so a multi-display user does not get a misleading N9"
  - "Only windowCreated is matched: a change to a Finder window tracked at the press, or any non-Finder window, is never taken"
  - "A press on a desk that does not exist yet treats the whole visible frame as the Desktop tile (width >= height splits right)"
  - "A hidden Desktop target has no tile rect, so the press beeps"
  - "A freshly launched Finder is pressed once Pane tracks it, retrying every 100 ms for up to 1.5 s, which leaves room in the 2 s wait for the window to arrive"

patterns-established:
  - "AX jobs that walk another app's UI stay on that app's AXAppThread under the global 1 s messaging timeout"

requirements-completed: []

coverage:
  - id: D1
    description: "MenuPress matcher and the live AX press of a ⌘N item (fixture only)"
    requirement: TILE-17
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MenuPressTests.swift (3 tests)"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift#pressingTheFixturesCommandNItemOpensANewWindow"
        status: pass
    human_judgment: false
  - id: D2
    description: "⌃⌥⌘N splits the current tile along its longer side with the first new Finder window; targets; no room; second press"
    requirement: TILE-17
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerFinderTests.swift (9 tests)"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/HotkeyTableTests.swift#entriesMapStableNamesToCommands"
        status: pass
    human_judgment: true
    rationale: "Real Finder pressed while inactive (assumption A12), relaunch, and the absence of an Automation prompt need the plan's human check"
  - id: D3
    description: "N9 at the 2 s deadline with the layout unchanged"
    requirement: TILE-17
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerFinderTests.swift#withNoNewFinderWindowByTheDeadlineN9ShowsAndTheLayoutIsUnchanged"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/NoticeCopyTests.swift#finderNoWindowIsN9"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-10-26
---

# Phase 3 Plan 09: Split with a New Finder Window Summary

**⌃⌥⌘N now splits the current tile along its longer side. Pane presses Finder's own ⌘N menu item through Accessibility, which needs no Apple Events and no Automation prompt. The first new Finder window that appears within 2 s docks in the split. If none appears, toast N9 says "Finder didn't open a new window." and the layout does not change.**

## Performance

- **Duration:** about 9 min
- **Started:** 2026-10-26T04:00:18Z
- **Completed:** 2026-10-26T04:09Z
- **Tasks:** 2 (each RED then GREEN)
- **Files modified:** 17

## Accomplishments

- **`MenuPress`**
  - Reads `kAXMenuBarAttribute`, then walks `kAXChildrenAttribute` down to depth 3 (menu bar item, its menu, that menu's items).
  - For each item it reads the command character, the modifiers and whether the item is enabled. It presses the first enabled item whose key equivalent is ⌘N with modifiers 0, using `kAXPressAction`.
  - It never reads or logs a title.
  - `AXWindowSystem.pressNewWindowItem(pid:)` runs it on that app's own `AXAppThread`.
- **Arranger**
  - `.finderSplit` resolves the target tile:
    - the focused docked window's leaf;
    - otherwise the Desktop tile of that window's desk;
    - with no focused window, the Desktop tile of the main display's desk.
  - It picks the edge from the tile's resolved rect: width ≥ height splits to the right, otherwise below.
  - It records one expectation (a newer press replaces it) and emits `.openFinderWindow` and `.wake`.
  - The first `windowCreated` that matches all of the following docks through a dry run plus `World.edit` with `applyDrop(.tile(target, .edge(edge)))`:
    - it comes from `com.apple.finder`;
    - its window was not tracked at the press;
    - it arrives before the deadline.
  - If docking would leave any window without room, it beeps, announces "Not enough room to dock here", and the window stays floating (D-26).
  - At the deadline tick it shows N9 and changes nothing.
- **Shell**
  - `.openFinderWindow` runs in its own Task, so a slow Finder never holds up the effects queued behind it.
  - If Finder isn't running, the shell launches it with `NSWorkspace.openApplication`. It then retries the press every 100 ms for up to 1.5 s, until Pane tracks the new Finder.
  - If there is no ⌘N item to press, it opens the home folder instead.
- **Hotkey and fixture**
  - New hotkey `finderSplit` on ⌃⌥⌘N.
  - The fixture now has File ▸ New Window (⌘N), which opens a `standard` window and prints its `window` line.

## Task Commits

1. **Task 1 RED:** `27d225e` test(03-09): add failing tests for the Finder split and the ⌘N menu press
2. **Task 1 GREEN:** `a182461` feat(03-09): split the current tile with a new Finder window by pressing its ⌘N item through AX
3. **Task 2 RED:** `f5538b0` test(03-09): add failing tests for N9, a second press, no room and the Desktop target
4. **Task 2 GREEN:** `f66386c` feat(03-09): show N9 when Finder opens no window, launch a quit Finder, fall back to the home folder

There were no refactor commits.

## TDD Gate Compliance

- **Task 1 RED:** `swift test --filter "ArrangerFinderTests|MenuPressTests|HotkeyTableTests"` exited 1.
  - All three Finder tests failed on their planned assertions against compiling stubs (`.finderSplit` was always refused). Their preconditions passed: a's tile was wide or tall as intended, and e was floating.
  - MenuPressTests failed on the stub matcher. `noMatchIsNil` passed because nil is its expected result.
  - HotkeyTableTests failed on the missing row.
  - Classifier verdict: `RED_EVIDENCE_OK` (`tdd/03-09-task1-red.json`).
- **Task 2 RED:** `swift test --filter "ArrangerFinderTests|NoticeCopyTests"` exited 1.
  - The target `withNoNewFinderWindowByTheDeadlineN9ShowsAndTheLayoutIsUnchanged` failed on the missing N9. `finderNoWindowIsN9` failed on the empty stub copy.
  - Five other new tests passed at RED: no room, second press, floating focus, no focus, and late arrival. Task 1's action already resolved those targets and ran the dry run, so these tests pin rules GREEN must keep.
  - Classifier verdict: `RED_EVIDENCE_OK` (`tdd/03-09-task2-red.json`).
- **GREEN:** every suite passes.

## Verification

- `swift test --filter "ArrangerFinderTests|MenuPressTests|HotkeyTableTests"`: 3 + 7 tests ran and passed after Task 1. After Task 2, `ArrangerFinderTests|NoticeCopyTests` ran 9 + 5 tests, all passing.
- `caffeinate -d -i swift test --filter MenuPressIntegrationTests`: 1 test passed. It was not skipped, the Mac was checked for a lock first, and no fixtures were left over.
- Live regression batch `MenuPressIntegrationTests|FocusParkIntegrationTests|FixtureShapesTests`: 4 tests passed. The fixture's new main menu breaks nothing. No fixtures were left over.
- `PANE_SKIP_AX_INTEGRATION=1 swift test`: 190 + 122 + 33 (skipped live) + 310 tests, all passing.
- `scripts/check-no-appkit.sh`: OK (33 files).
- Acceptance greps:

  | Pattern | File | Count |
  |---|---|---|
  | `kAXPressAction` | MenuPress.swift | 1 |
  | `NSAppleScript\|automation.apple-events` | Sources, xcode | 0 |
  | `Self("finderSplit"` | Hotkeys.swift | 1 |
  | `case finderNoWindow` | Notice.swift | 1 |
  | `Finder didn't open a new window.` | NoticeCopy.swift | 1 |

## Decisions Made

See `key-decisions` in the frontmatter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The Finder deadline shares the shell's single wake**
- **Found during:** Task 1 design
- **Issue:** `WakeTimer` keeps one wake. A correction's `.wake` would replace the Finder deadline, and the Finder `.wake` would push back an earlier correction. A tick that never clears an expired expectation would also re-arm a wake that is already in the past, which loops.
- **Fix:**
  - `nextWake` is now the minimum over the corrections and the Finder deadline.
  - The command emits `nextWake`.
  - `tick` clears an expired expectation first.
- **Commit:** a182461

**2. [Rule 2 - Correctness] A Finder window on another display is still taken**
- **Issue:** `admit` floats the new window on its own display's desk. If Finder opened it on a different display from the target tile, the split would wrongly end in N9.
- **Fix:** The window leaves that Desktop through `World.reflow` (an OS fact, no undo step). It is then docked by `World.edit` on the target desk, after the dry run.
- **Commit:** a182461

**3. [Rule 3 - Blocking] NoticeQueue's merge switch** (file not in the plan's list)
- **Issue:** Adding `Notice.finderNoWindow` made `Notice.merged(with:)` non-exhaustive.
- **Fix:** Two N9s merge into one. Any other pair does not merge. The switch lists cases explicitly with no `default`, so a future case still fails to compile until it is handled.
- **Commit:** f5538b0

**4. [Test design] The wide-split test checks D-20's drop result, not a's old tile**
- A right-edge drop on a leaf whose parent is already a horizontal split joins that split (`[a, n, Desktop]`, thirds), as a drag does. The first GREEN run showed that "n stays inside a's old tile" was my wrong assumption, not an Arranger bug. The test now checks that n sits right of a at the same height, in a's row. The tall case nests, and it still checks a's old tile.

**5. [Test design] The no-room scenario uses learned minimums that fit floating but not docked**
- A single huge minimum also makes the Desktop tile, which the floating windows size, take a's room. a then floats under the existing D-26 rule before the Finder dock is ever tried.
- The test uses:
  - a with a 200 pt minimum;
  - f, floating, with a 700 pt minimum;
  - n with an 800 pt minimum.
- n fits floating but not docked beside a. The test also checks that a stays docked and that the undo depth is unchanged.

**6. [Interface extension]** `Arranger.finderBundleID` and `Arranger.finderWait` are public so the shell can use the same bundle ID. `MenuPress.maxDepth` was also added. None of this affects callers.

## Issues Encountered

None new. deferred-items.md is unchanged. The known two-display live failure (`aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop`) was not run.

## Known Stubs

None.

## Threat Flags

None.
- **T-03-22:** Pane only uses an AX press. No AppleScript bridge and no apple-events entitlement were added, and a grep confirms both are absent.
- **T-03-23:** Pane presses only the enabled ⌘-only N item at depth 3 or less, found by command character and modifiers. It never reads titles. The walk runs on Finder's thread under the global 1 s AX timeout.
- **T-03-24:** Pane docks only a `com.apple.finder` window that was untracked at the press, created before the deadline, and arriving through `windowCreated`.

## Requirements

**TILE-17 stays Pending.** The hotkey route works end to end, but the requirement also needs the `pane://split-finder` URL (plan 15) and the Arrange ▸ Split menu item (plan 10).

## Human UAT (end of phase)

From the plan's human check. It uses real Finder, so it was not run live here.
1. In Pane Debug, dock a wide window and press ⌃⌥⌘N. A Finder window should dock to its right.
2. Focus a tall docked window and press ⌃⌥⌘N. A Finder window should dock below it.
3. Run `killall Finder` in Terminal, then press ⌃⌥⌘N. Finder should relaunch and its new window should dock. Watch for a first-press timing miss here, since it tests assumption A12.
4. Focus a floating window and press ⌃⌥⌘N. The Desktop tile should split.
5. At no point should an Automation permission prompt appear.

## Next Phase Readiness

- Plan 10 can add Arrange ▸ Split ▸ Split with New Finder Window. It can grey the item out with `isAvailable(.finderSplit, focused:)`.
- Plan 15 can map `pane://split-finder` to `dispatch(.finderSplit)`.

## Self-Check: PASSED
