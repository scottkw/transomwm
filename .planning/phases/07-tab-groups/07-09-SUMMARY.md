---
phase: 07-tab-groups
plan: 09
subsystem: tiling
tags: [swift, tab-groups, hotkeys, url-scheme, menu, shortcuts, debug]

requires:
  - phase: 07-tab-groups
    plan: 08
    provides: moveOut(_:via:), TabLeaveSource, TabCopy.moveOut
  - phase: 07-tab-groups
    plan: 02
    provides: select(_:via:) reveal-then-park flow, TabRefusal, tabGroup(holding:)
provides:
  - Command.tabs(TabCommand { next, previous, moveOut })
  - TabAction.command(TabCommand, focused:, via: TabLeaveSource) and Arranger.tabCommand (wrapping select / move out, refusals)
  - availability(.tabs) rule
  - Hotkey names nextTab (⌃⌥⌘T), previousTab (⇧⌃⌥⌘T), moveOutOfGroup (⌃⌥⌘L)
  - URL hosts next-tab, previous-tab, move-out-of-group
  - CommandMenu.tabsMenu (Arrange ▸ Tabs), Shortcuts "Tabs" section (48 rows)
  - Arranger.tabGroupCounts(), TabCopy.debugLine(groups:tabs:), TabCopy.tabsMenu/nextTab/previousTab
affects: [07-10, 07-11]

estimate:
  tokens: 110000
actuals:
  tokens: 8400
  tasks: 3
  commits: 3
plan_head_before: 4ad4aaf37ca302a12b81abea6712f0e005a0683e
plan_head_after: e6f7e2f58d48bd23214855273ab1f1ff06b82d2b

tech-stack:
  added: []
  patterns:
    - "Tab commands bypass the bare-beep availability gate: the engine's tabCommand refuses with beep + announcement + 'refused {command}: {reason}', and the shell strips the beep and refusal announcement for URLs"

key-files:
  created: []
  modified:
    - Sources/TransomEngine/Command.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/TransomURL.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Input/Hotkeys.swift
    - Sources/TransomMac/Shell/CommandMenu.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomEngineTests/TransomURLTests.swift
    - Tests/TransomMacTests/HotkeyTableTests.swift
    - Tests/TransomMacTests/ShortcutsModelTests.swift
    - Tests/TransomMacTests/CommandMenuTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift

key-decisions:
  - "Tab commands go to the engine as TabAction.command with the shell's ready flag and source, so 'not ready' is refused by the engine with its announcement (like select/moveOut); a bare .command(.tabs) uses via .hotkey and ready true"
  - "Next/Previous step from the group's selected index (the focused member is the selected one unless a hidden member was focused another way); the source maps to TabSelectSource for the select log line"
  - "URL refusals drop both the beep and the refusal announcement (must_haves: 'URL refusals only log'), matching the camera-command URL path; a successful URL select still announces 'Tab i of n'"
  - "availability(.tabs) also checks sessionPaused, matching the refusal guard in select/moveOut"

patterns-established:
  - "Refusal log for tab commands: 'refused next tab|previous tab|move out of group: not in a tab group|arranging is paused|not ready'"

requirements-completed: [TABS-02, TABS-04, TABS-06]

coverage:
  - id: D1
    description: "Next/Previous Tab select the wrapping neighbour through the reveal flow and announce 'Tab i of n'; Move Out of Group moves the focused member out via the source"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabCommandTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Refusals (no group / paused / not ready) beep, announce and log 'refused {command}: {reason}'; availability true only for a grouped focused window, unpaused, ready"
    requirement: TABS-06
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabCommandTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Hotkey names and defaults pinned, not zoom names, no duplicate chords; URL hosts parse and malformed variants are rejected"
    requirement: TABS-04
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/HotkeyTableTests.swift; Tests/TransomEngineTests/TransomURLTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "Arrange ▸ Tabs submenu items, shortcuts, dispatch and disabled state; Shortcuts Tabs section after Snap, 48 rows; Debug line branches and counts"
    requirement: TABS-04
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/CommandMenuTests.swift; ShortcutsModelTests.swift; TabCopyTests.swift; ArrangerTabsTests.swift#tabGroupCounts"
        status: pass
    human_judgment: false
  - id: D5
    description: "Live: ⌃⌥⌘T / ⇧⌃⌥⌘T / ⌃⌥⌘L in the real app, submenu placement in the status menu, URL rate limit and no-beep refusal, VoiceOver letter-chord fallback"
    requirement: TABS-02
    verification:
      - kind: manual
        ref: "VM UAT backstop at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "Registering global hotkeys and opening transom:// URLs are live and VM-only; this plan runs no VM test"

duration: 6min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 09: Tab Commands Summary

**Next Tab (⌃⌥⌘T), Previous Tab (⇧⌃⌥⌘T) and Move Out of Group (⌃⌥⌘L) now run through the one dispatcher from a hotkey, the new Arrange ▸ Tabs submenu, and `transom://next-tab`, `previous-tab` and `move-out-of-group`. Next and Previous wrap around and use the reveal-then-park switch. Refusals beep, announce and log, except from URLs, which only log. The Shortcuts window gains a Tabs section (48 rows in total), and Debug shows "Tab groups: …".**

## Performance

- **Duration:** about 6 min
- **Started:** 2026-11-02T02:46Z
- **Completed:** 2026-11-02T02:53Z
- **Tasks:** 3
- **Files modified:** 17 (231 insertions, 13 deletions)

## Accomplishments
- Engine: `Command.tabs(TabCommand)`, plus `TabAction.command(_, focused:, via:)` that leads to `Arranger.tabCommand`. Next and Previous select `members[(selected ± 1) mod n]` through `select`, so the "Tab i of n" announcement, the reveal and the focus all come from the existing flow. Move Out calls 07-08's `moveOut`, and its Leave log line names the source (hotkey, menu or url).
- Refusals are checked in a fixed order: paused, then not ready, then not in a group. Each one gives `.beep`, `.tabAnnouncement(.refused(...))` and `refused {next tab|previous tab|move out of group}: {reason}`.
- `availability(.tabs)` returns true only when the focused window is in a group, nothing has paused arranging (session pause included), and the app is ready. This one rule greys the menu items.
- Shell: `ArrangeController.dispatch` sends `.tabs` to the engine along with the real `ready` flag and the source, before the bare-beep availability gate. For URLs it removes the beep and the refusal announcement.
- Hotkey names are added to `entries` but not to `zoomNames`, so they stay on when zoom is off. The `transom://` whitelist gets three new hosts. The `CommandMenu.tabsMenu` submenu sits after Snap Floating Window. The Shortcuts Tabs section sits after Snap, and Restore Defaults already resets every entry.
- `Arranger.tabGroupCounts()` counts docked and floating groups on every desk, dormant desks included. `TabCopy.debugLine` gives the line, which appears in Debug after "Last overview".

## Task Commits

1. **Task 1: Tracer, ⌃⌥⌘T selects the next tab** - `18241f0` (feat)
2. **Task 2: URLs, Arrange ▸ Tabs submenu, Shortcuts Tabs section** - `d56add0` (feat)
3. **Task 3: Debug line, full suite** - `e6f7e2f` (feat)

## Verification

- Task 1 gate: 143 + 12 tests passed (ArrangerTabsTests, ArrangerTabCommandTests, HotkeyTableTests, CommandTests, ArrangerCommandTests). The tracer gate re-ran the automated `<verify>` (end-of-phase human-verify mode) and it passed.
- Task 2 gate: 43 + 8 tests passed (TransomURLTests, ShortcutsModelTests, CommandMenuTests, MenuCopyTests).
- Task 3 gate: the full `swift test` passed (219, 383, 92 and 934 tests across the runs, no failures), and `scripts/check-no-appkit.sh` passed (55 files).
- No live, VM or hotkey-registration code was run on the host.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The ShortcutsModel conflict test used ⌃⌥⌘L as a free chord**
- **Found during:** Task 2
- **Issue:** `aChordAnotherTransomCommandUsesIsRejectedWithItsTitle` expected no conflict for ⌃⌥⌘L, which is now Move Out of Group.
- **Fix:** The test now uses ⌃⌥⌘Y, which the UI-SPEC lists as still free.
- **Files modified:** Tests/TransomMacTests/ShortcutsModelTests.swift
- **Commit:** d56add0

**2. [Plan detail] Tab commands carry `ready` and the source through `TabAction.command`**
- **Found during:** Task 1
- **Issue:** `.command(_, focused:)` has no `ready` flag, and the shell's availability gate only beeps. The plan's "not ready" refusal needs an announcement, and the log should name the real source.
- **Fix:** The shell sends `.tab(.command(tab, focused:, via:), ready:)`. A bare `.command(.tabs)` still works with `via: .hotkey, ready: true`, as the plan's tests expect.
- **Files modified:** Sources/TransomEngine/Arranger+Tabs.swift, Sources/TransomMac/ArrangeController.swift
- **Commit:** 18241f0

## Known Stubs

None.

## Next Phase Readiness
- 07-10 and 07-11 can use the commands. The live hotkeys, the status-menu placement, and URL refusals not beeping all still need the 07-11 VM UAT.

## Self-Check: PASSED
- Files: all 17 modified files are present. 07-09-SUMMARY.md has been written.
- Commits: 18241f0, d56add0 and e6f7e2f are ancestors of HEAD.
