---
phase: 07-tab-groups
plan: 07
subsystem: tiling
tags: [swift, tab-groups, tear-off, drag, hotkeys, overlay]

requires:
  - phase: 07-tab-groups
    plan: 06
    provides: movingGroup / whole-group drag paths, takeGroup, Float Group clamp of the group frame
  - phase: 07-tab-groups
    plan: 02
    provides: strip panels, windowNumbers (Pitfall 4 strip-press guard), shownStrips
provides:
  - PointerEvent.pressTab; DragSession.Origin (.window / .tearOff(group, stripRect, landingSize)), tearOffGroup, landingFrame(at:)
  - DropAction.tearOffFloat(DeskKey); Hover.overStrip
  - Arranger tear-off: pressTab, tearOff, tearOffMiss, tearOffDesktop, releaseTearOff, commitTearOff, cancelTearOff, movedOut
  - TabAction.cancelTearOff; TabAnnouncement.movedOut(dissolved:) / .tearOffCanceled; ArrangerEffect.tearOffGhost(TearOffGhost?)
  - TabStripPanels.member(atWindowNumber:point:); TearOffGhostPanel (show / move(to:) / hide)
  - Temporary Esc hotkeys during a tear-off (ZoomInput.escapeModifiers, now internal)
  - Planner clamps a floating group's whole frame (strip band included)
affects: [07-08, 07-11]

estimate:
  tokens: 130000
actuals:
  tokens: 15200
  tasks: 3
  commits: 5
plan_head_before: 7acf788b9ee5efee73ef556d5e312b10880517c8
plan_head_after: ad79b1f7524d6dda0d9605c8b8501e7f3c5716ef

tech-stack:
  added: []
  patterns:
    - "A tear-off is a DragSession with origin .tearOff and kind .move set at once: the existing hover / dwell / dry run / preview run on a synthetic landing frame under the pointer, with no frame poll"
    - "tabs.tearing names the tab that moves alone, so movingGroup (and with it dropping, decide, settleDrag) never takes its whole group; endDrag clears it and releaseTearOff re-sets it for the commit"

key-files:
  created:
    - Sources/TransomMac/Overlay/TearOffGhost.swift
  modified:
    - Sources/TransomEngine/DragSession.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Planner.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overlay/TabStripPanels.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Sources/TransomMac/Zoom/ZoomInput.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift

key-decisions:
  - "The engine reads the strip rect from the strips it last sent (tabs.shownStrips), so the shell sends only the pressed member; a group whose strip is not on screen cannot be torn from"
  - "A release before any dwell outside the strip is the float on the display under the pointer (the tear-off's miss rule), like a Phase 3 release before the dwell takes the miss rules"
  - "A refused Dock (no room) on a tear-off announces \"Not enough room\" and leaves the tab in its group: the tear-off's analogue of a docked window's snap-back"
  - "Edge bands of the tab's own group leaf dock beside it (the leaf survives the removal under the same NodeID); only its own group's centre is excluded"
  - "A tear-off can float onto another display's desk: the source desk loses the tab as a reflow, the target desk's float is the one undo step (as dropping does)"
  - "A group join from a tear-off announces only the join (\"Grouped as tabs\" / \"Added as a tab\"), per the UI-SPEC release table; Dock and float announce movedOut(dissolved:)"

patterns-established:
  - "Temporary hotkeys follow a shell overlay's lifetime: registered when the engine's effect goes nil to a value, cancelled when it returns to nil (every engine exit path emits the nil)"

requirements-completed: [TABS-04]

coverage:
  - id: D1
    description: "A tab press with drags inside the strip creates no session and changes nothing; leaving the strip starts a .move session with no .pollDragFrame and shows the ghost"
    requirement: TABS-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTearOffTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Release over empty Desktop floats the tab at the clamped landing frame in one undo step; the group keeps its other members or dissolves at one; Undo restores the group"
    requirement: TABS-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTearOffTests/aReleaseOverEmptyDesktopFloatsTheTabAtTheClampedLandingFrameInOneUndoStep, tearingFromATwoTabGroupDissolvesIt"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dock preview docks the tab out (one undo step, movedOut); Group preview forms that group, selected; own group's centre never groups; release over the strip cancels with no change; ⌘ never swaps; ⇧ floats; the selected tab's right neighbour is selected"
    requirement: TABS-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTearOffReleaseTests; Tests/TransomMacTests/TabCopyTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "Esc (.cancelTearOff) ends the session, withdraws preview and ghost, announces \"Tab move canceled\", the rest of the press does nothing; a stale tear-off or tab press is cleared by the next press with no commit"
    requirement: TABS-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTearOffCancelTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Live tear-off: ghost drawing and truncation, Esc hotkeys heard, dock / float / Esc on real windows"
    requirement: TABS-04
    verification:
      - kind: manual
        ref: "VM UAT backstop at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "The plan runs no VM test; AppKit drawing, Carbon hotkeys and a real drag need the VM"

duration: 17min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 07: Tear-off Summary

**Dragging a tab out of its strip now turns into a normal window drag: the existing Dock and Group previews apply to the torn tab, anywhere else shows a dashed landing ghost where it will float, and releasing over the strip or pressing Esc cancels. A click-through capsule ghost follows the pointer while you drag.**

## Performance

- **Duration:** about 17 min
- **Started:** 2026-11-02T02:18:00Z
- **Completed:** 2026-11-02T02:35Z
- **Tasks:** 3, plus the extra fix
- **Files modified:** 11 (695 insertions, 19 deletions)

## Accomplishments
- Shell routing: a left-mouse-down on a strip panel asks `TabStripPanels.member(atWindowNumber:point:)` for the tab under the point. The engine gets `PointerEvent(pressTab:)` and never a `pressWindow` (Pitfall 4). A press on a button or the background is still only the strip's AppKit click.
- Engine: the press is held as a `TearPress` (member, group, the strip rect the engine last sent). The first drag outside that rect starts a `DragSession` with `origin = .tearOff(group, stripRect:, landingSize:)` and `kind = .move` set at once, with no frame poll. The landing size is the tab's saved pre-group size, else the content size.
- The hover hit-tests the pointer. Over the source strip there is no preview. ⌘ never swaps. Edge bands dock, including beside the tab's own group. Other centres group after the 400 ms dwell, but its own group's centre never does. ⇧ and every miss give `.tearOffFloat`, with the landing frame (centred on the pointer, top 12 pt above it) shown as the clamp ghost in the Desktop rect. That rect is computed with the tab out of its group and the Desktop shown.
- Release: over the strip it cancels and logs. A Dock commit goes through `commitDock`/`dropping`, which take the tab out alone because `tabs.tearing` stops `movingGroup` taking the whole group. A Group commit goes through `commitGroup`. The float is `commitTearOff`: one `World.edit` that removes the tab from its group and floats it at the clamped landing frame, showing a hidden Desktop first. The tab is raised and focused. Dock and float announce "Moved out of the tab group", plus ". Tab group ended." when the group dissolved, and write the Leave log line.
- D-12: the model's removal already selects the right neighbour, else the left one, and dissolves at one. Tests cover both.
- Esc: `TabAction.cancelTearOff` ends the session, withdraws the preview and ghost, and announces "Tab move canceled". The shell registers Esc, ⇧Esc, ⌘Esc and ⌘⇧Esc only while the ghost shows, from `ZoomInput.escapeModifiers` (now internal, no ⌥). It cancels them whenever the ghost hides, on release, cancel, a stale press or a pause.
- Ghost: `TearOffGhostPanel` is click-through, one level above the drop preview, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, and excluded from capture. It is a capsule with a 16 pt icon and a middle-truncated Body title, at most 240 pt wide, showing the app name when the window has no title. Its top-left sits at the pointer + (8, 8). It fades in over 120 ms and out over 80 ms, and is replaced if `leftOnAnotherSpace` reports it was stranded on another Space.

## Task Commits

1. **Task 1: Tracer, tear onto empty Desktop floats at the landing frame** - `8dac0b0` (feat)
2. **Task 2: Dock / Group targets, strip cancel, neighbour selection, copy** - `933074e` (test)
3. **Task 3: Esc cancel, ghost, stale-press cleanup** - `0b88dbc` (test, RED), `9514617` (feat, GREEN)
4. **Extra fix: clamp a floating group's whole frame** - `ad79b1f` (fix, with its RED test run first)

## Verification
- Task 1 `<verify>` (tracer gate, auto mode): filtered run green with 113 tests (`ArrangerTabsTests|ArrangerDragTests|DragSessionTests|ArrangerTearOffTests`), then `swift build` OK, before expanding.
- Task 2 `<verify>`: filtered run green with 96 + 4 tests (`ArrangerTabsTests|ArrangerTearOff|TabCopyTests`).
- Task 3 `<verify>`: full `swift test` green with 219 + 379 + 92 + 912 tests, `scripts/check-no-appkit.sh` OK (55 files).
- After the extra fix: full `swift test` green again (219 + 379 + 92 + 913).
- No VM run, as planned. The live tear-off (dock, float, Esc) is a 07-11 UAT backstop item. Nothing live ran on the host.

## Deviations from Plan

1. **[Extra fix, requested by the orchestrator] Floating-group clamp covered only the content rect.** When a floating group crossed a tile, `Planner.plan` clamped only the selected member's content rect, so a group at the top of the Desktop tile could have its strip above the Desktop's top edge (07-06's reported gap). The planner now tests the group frame for overlap and clamps the group frame, strip band included, as the ⇧-drag float and Float Group do. Test: `FloatingGroupPlannerTests/aFloatingGroupCrossingATileIsClampedWholeStripIncluded` (failed before the fix). Files: `Sources/TransomEngine/Planner.swift`. Commit `ad79b1f`.
2. **The ghost's fades, truncation and app-name fallback were built in Task 1, not Task 3.** The panel was written once, complete. Task 3 added only the Esc hotkeys.
3. **TabCopy strings landed in Task 1.** Adding `TabAnnouncement` cases broke `TabCopy`'s exhaustive switch, so the copy went in with the engine. Task 2 added the copy tests.
4. **Task 2 had no failing RED run.** Task 1's engine already covered the release table, so Task 2's tests passed on their first run, and they were committed as `test`. Task 3 and the extra fix did fail first.
5. **The tests are in new suites in `ArrangerTabsTests.swift`** (`ArrangerTearOffTests`, `ArrangerTearOffReleaseTests`, `ArrangerTearOffCancelTests`). The plan's `--filter 'ArrangerTabsTests'` does not match suite names, so every gate here added `ArrangerTearOff` to the filter (07-06's suites have the same issue).
6. **`Arranger.drag` is `internal(set)` and `endDrag` is internal** (they were private), so the tear-off code in `Arranger+Tabs.swift` can start and end sessions.
7. **Edge case choices** (listed in key-decisions): a release before the dwell floats, a refused Dock cancels with "Not enough room", the tab can dock beside its own group, and it can float onto another display.

## Known Stubs
None.

## Threat Flags
None. T-07-17 is mitigated: the Esc hotkeys exist only while the ghost shows. Every engine exit (release, cancel, stale press, pause, exclusion) goes through `endDrag`, which emits `.tearOffGhost(nil)`, and that cancels the hotkey tasks. ⌥ is never in the list. T-07-18 is mitigated: `abandonDrag` never commits a tear-off, a stale `TearPress` is cleared on every down and up, and after Esc the rest of the press finds no session (engine tests).

## Self-Check: PASSED
