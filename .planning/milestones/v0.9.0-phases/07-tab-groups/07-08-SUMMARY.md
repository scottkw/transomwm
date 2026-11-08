---
phase: 07-tab-groups
plan: 08
subsystem: tiling
tags: [swift, tab-groups, context-menu, voiceover, close-tab, move-out]

requires:
  - phase: 07-tab-groups
    plan: 07
    provides: commitTearOff (remove from group + float + raise/focus), movedOut announcement, tearOffDesktop, contentRect(of:)
  - phase: 07-tab-groups
    plan: 05
    provides: CloseQueue, closeProgress, closeConfirmation, reveal-before-close
provides:
  - TabAction.moveOut(WindowRef, via: TabLeaveSource) and .closeTab(WindowRef); TabLeaveSource { menu, hotkey, url, voiceOver }
  - Arranger.moveOutFrame(size:group:desktop:) (pure landing rule), Arranger.moveOut, Arranger.closeTab
  - CloseQueue.oneTab (Close Tab announces a dissolve; Close Group does not)
  - TabStripView right-click / ⌃-click context menu; per-tab NSAccessibilityCustomAction for Close Tab and Move Out of Group
  - TabCopy.closeTab ("Close Tab"), TabCopy.moveOut ("Move Out of Group")
affects: [07-09, 07-10, 07-11]

estimate:
  tokens: 100000
actuals:
  tokens: 4300
  tasks: 2
  commits: 2
plan_head_before: 1bd9548283ba0f63952dac7ba1ddafda430c7e35
plan_head_after: d90d7295a58d3baa12ce9daa897342a16eccca35

tech-stack:
  added: []
  patterns:
    - "Move Out of Group is the tear-off float commit with a computed landing frame: commitTearOff/movedOut take a `via` source for the Leave log line"

key-files:
  created: []
  modified:
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomMac/Overlay/TabStripPanels.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Sources/TransomMac/ArrangeController.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift

key-decisions:
  - "Move Out measures 'beside the group' against the group frame as currently planned, and 'fits' against the Desktop tile computed with the member out of its group and the Desktop shown (tearOffDesktop); commitTearOff clamps again in the edit"
  - "Close Tab marks its CloseQueue oneTab so a two-tab group's dissolve is announced ('Tab group ended'); Close Group still stays silent on the way through"
  - "A ⌃-click on a strip panel sends no pressTab to the engine, so the context menu's tracking drags can never start a tear-off"
  - "Close Tab while the same group is already closing does nothing (same guard as Close Group's second click)"

patterns-established:
  - "Strip context menus set the tab's pressed fill before popUp and clear it after popUp returns (popUp blocks for the menu's tracking)"

requirements-completed: [TABS-06]

coverage:
  - id: D1
    description: "moveOutFrame: 8 pt right with tops aligned; else 8 pt left; else 24/24 cascade, then clamped"
    requirement: TABS-06
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabsMoveOutTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Move Out floats the member at the landing frame in one undo step, raised and focused, movedOut announced, neighbour selected or group dissolved, hidden Desktop shown first, Undo restores the group, paused / not ready refused"
    requirement: TABS-06
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabsMoveOutTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Close Tab: selected closes at once then the neighbour is selected; hidden is shown and read back first; still open after closeConfirmation stays selected with one didNotClose and nothing to resume; a dissolve is announced; paused / not ready refused"
    requirement: TABS-06
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabsCloseTabTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Context menu tracks from the never-active app (A3), pressed fill while open, VoiceOver lists both custom actions on each tab"
    requirement: TABS-06
    verification:
      - kind: manual
        ref: "VM UAT backstop at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "AppKit menu tracking and VoiceOver need the VM; the plan runs no VM test"

duration: 5min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 08: Tab Context Menu Summary

**Right-clicking or ⌃-clicking a tab now opens a system menu with Close Tab and Move Out of Group. VoiceOver users get the same two actions on every tab. Move Out floats the window 8 pt to the right of its group (else 8 pt left, else a 24/24 cascade, then clamped) as one undo step. Close Tab runs that one window through Close Group's queue, so a hidden tab is shown before its close and the run stops if a save prompt appears.**

## Performance

- **Duration:** about 5 min
- **Started:** 2026-11-02T02:38:29Z
- **Completed:** 2026-11-02T02:43Z
- **Tasks:** 2
- **Files modified:** 6 (260 insertions, 6 deletions)

## Accomplishments
- Engine: `Arranger.moveOutFrame(size:group:desktop:)` is a pure function implementing the UI-SPEC landing rule. A side fits when its rect lies inside the Desktop tile.
- `moveOut(member, via:)` takes the member's saved pre-group size (else the content size) and the group frame. The Desktop rect comes from `tearOffDesktop`, which computes it with the member out of its group and the Desktop shown. The commit reuses 07-07's `commitTearOff`: one `World.edit`, a hidden Desktop shown first, then raise and focus, and `movedOut(dissolved:)`. The log line reads `group N: W moved out via menu, landed floating`.
- `closeTab(member)` builds a `CloseQueue` with only that member, flagged `oneTab`. The existing `closeProgress` reveals a hidden member first and closes after the read-back. If the window is still open after `closeConfirmation`, it announces `didNotClose` and clears the queue, so nothing is left to resume.
- Shell: `TabStripView.rightMouseDown`, and a left mouse-down with ⌃ held, pop an `NSMenu` over a tab with both items (always enabled, `representedObject` = the member). The pressed fill shows while it is open. Over a button or the background nothing happens. Each tab's `PressElement` has two `NSAccessibilityCustomAction`s, overflowed tabs included.
- `TabCopy.closeTab` / `TabCopy.moveOut` strings, with tests.

## Task Commits

1. **Task 1: Tracer, right-click → Move Out of Group floats beside the group** - `73f7bcb` (feat)
2. **Task 2: Close Tab through the close queue; VoiceOver custom actions** - `d90d729` (feat)

## Verification
- Task 1 `<verify>` (tracer gate, auto mode, re-run before expanding): filtered run `ArrangerTabsTests|ArrangerTabsMoveOutTests|TabCopyTests` green with 107 + 4 tests, with the new MoveOut tests listed as passed. Then `swift build` OK.
- Task 2 `<verify>`: full `swift test` green with 219 + 379 + 92 + 926 tests, and `scripts/check-no-appkit.sh` OK (55 files).
- Mutation check: with the `oneTab` test removed from `dissolved`, `closingOneOfTwoTabsAnnouncesTheDissolve` fails. File restored afterwards.
- No VM run, as planned. Menu tracking from a never-active app (A3) and VoiceOver are 07-11 UAT backstop items. Nothing live ran on the host.

## Deviations from Plan

1. **[Rule 1 - Bug] A ⌃-click would have started a tear press.** The event tap sends `pressTab` for any left mouse-down on a strip. A ⌃-click opens the menu on mouse-down, and dragging to an item could then leave the strip and start a tear-off. `ArrangeController` now sends no `pressTab` while ⌃ is held. Files: `Sources/TransomMac/ArrangeController.swift` (not in the plan's file list). Commit `73f7bcb`.
2. **[Rule 1 - Bug] Close Tab would have stayed silent on a dissolve.** `dissolved()` drops "Tab group ended" while a close queue runs for the group, which was meant for Close Group. Added `CloseQueue.oneTab` so Close Tab announces the dissolve (UI-SPEC D-12). Test: `closingOneOfTwoTabsAnnouncesTheDissolve`. Commit `73f7bcb` (code), `d90d729` (test).
3. **The Close Tab engine landed in Task 1.** Adding the two `TabAction` cases made `tab(_:)`'s switch need both handlers, so `closeTab` went in with `moveOut`. As a result, Task 2's engine tests passed on their first run (no RED). The mutation check above shows the new flag is load-bearing.
4. **Tests were written alongside the engine, not before it.** Task 1's tests passed on their first run.
5. **The plan's flag** ("so a stop does not leave a resumable list") **needed no code.** 07-05's `closeProgress` already clears the queue on a stop. The test asserts it.
6. **Suite names start with `ArrangerTabs`** (`ArrangerTabsMoveOutTests`, `ArrangerTabsCloseTabTests`), so the plan's `--filter 'ArrangerTabsTests|…'` gates find them by prefix.
7. **`Arranger.swift` was not changed.** Nothing there needed editing.

## Known Stubs
None.

## Threat Flags
None. T-07-19 is mitigated: Close Tab sends only `WindowCommand.close` (the AX close-button press, which `ExclusionFilter` still guards). A hidden member is shown and read back before its press. After `closeConfirmation` the run stops with the window in view, and there is no force close.

## Self-Check: PASSED
