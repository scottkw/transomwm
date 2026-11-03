---
phase: 07-tab-groups
plan: 06
subsystem: tiling
tags: [swift, tab-groups, whole-group, float-group, dock-group, drag]

requires:
  - phase: 07-tab-groups
    plan: 05
    provides: strip buttons (mouse-up inside), tabGroup(_ key:), refusal path
  - phase: 07-tab-groups
    plan: 04
    provides: FloatingTabGroup sidecar, TabGroupRef / tabGroup(holding:), isHiddenTab
provides:
  - LayoutTree.removeLeaf / insertLeaf / insertRootLeaf (whole-leaf moves); insert and insertRoot call them
  - LayoutTree.swap of a panel with one tab group (two groups still throw)
  - LayoutTree.applyDrop(_:leaf:states:ids:) (a centre throws)
  - DesktopLayer.removeGroup / addGroup (member states kept)
  - TabAction.toggleGroupFloat; Arranger.floatGroup / dockGroup / takeGroup / movingGroup / groupMinimum
  - Whole-group branches in dock, float, green button, Arrange All, Float All, rehome, Move, Swap, Snap and the title-bar drag
  - Strip's third button: Float Group (macwindow) / Dock Group (rectangle.split.2x1); TabCopy.floatGroup / dockGroup
affects: [07-07, 07-08, 07-11]

actuals:
  tokens: 20200
  tasks: 3
  commits: 4
plan_head_before: 1b060850c2194a77e3bad751fb240a5530112372
plan_head_after: 49efad9ed42e1a5c7523652bcd53bfbe342d83d8

tech-stack:
  added: []
  patterns:
    - "A group moves as one unit through takeGroup (its tree leaf or its floating group, with member states) plus insertLeaf / applyDrop(leaf:) / addGroup, inside the one World.edit the single-window path already used"
    - "movingGroup(window) (selected member only) marks a whole-group drag; command paths use tabGroup(holding:) (any member)"

key-files:
  created: []
  modified:
    - Sources/TransomModel/TreeEdits.swift
    - Sources/TransomModel/DesktopLayer.swift
    - Sources/TransomModel/DropZones.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Arranger+Commands.swift
    - Sources/TransomMac/Overlay/TabStripPanels.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Tests/TransomModelTests/TabGroupModelTests.swift
    - Tests/TransomModelTests/LayoutEditTests.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift

key-decisions:
  - "removeGroup returns the group and its members' states, and addGroup takes them, so an absent or fullscreen member keeps its state through Float / Dock Group (the plan's signature returned only the group)"
  - "A floated group gets a new ID from the IDSource, not its old leaf's NodeID; Dock Group's leaf gets a new NodeID from insertLeaf"
  - "Dock Group is Dock Window on the selected member: dock() branches on a floating group and docks it at the group frame's centre, so keyboard, green button and strip button share one path"
  - "A window that leaves a floating group by docking keeps its wanted frame as its pre-dock frame, as Dock Window keeps a floater's; only windows still floating lose it (07-04's rule narrowed)"
  - "Keyboard Swap: the focused window may be a group member, the previous one must be a plain panel, the same rule as the ⌘ drag"
  - "⇧-drag float clamps the whole group frame into the Desktop when it crosses a tile; the miss path for a floating group still uses the planner's content-rect clamp (07-04)"

patterns-established:
  - "Commands that move 'the focused window' ask tabGroup(holding:) first and move the group's leaf or floating frame"

requirements-completed: [TABS-03, TABS-05]

coverage:
  - id: D1
    description: "Model: removeLeaf / insertLeaf keep members, order, selection and states, weights sum to 1, a duplicate identity throws and changes nothing, the last leaf going shows a hidden Desktop; removeGroup / addGroup round trip; applyDrop(leaf:) docks on edges and throws on a centre; a tabs leaf swaps with a panel, two groups throw"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomModelTests/TabGroupModelTests.swift#WholeGroupEditTests, #WholeGroupDropTests; Tests/TransomModelTests/LayoutEditTests.swift#swapRejectsSelfTabsAndUnknownWindows"
        status: pass
    human_judgment: false
  - id: D2
    description: "Float Group: floating group with the same members and selection, one setFrame into the content rect, a sized park for the hidden member, a floating strip, one undo step, Undo restores the docked leaf; paused / not ready refused"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerWholeGroupTests/floatGroupFloatsTheWholeDockedGroupInOneUndoStep, aRefusedFloatGroupBeepsAndChangesNothing"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dock Group docks one tabs leaf at the group centre (one undo step, Undo restores); no room refused with beep, \"Not enough room\" and the Blocked flash; Float / Dock Window and the green button on a member move the whole group; Arrange All / Float All treat a group as one window and count it once; rehome moves the whole group, a hidden member's report is ignored; Focus, Grow, Move, Swap and Snap act on the group"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerWholeGroupTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Title-bar drag of the selected member: edge band previews the group frame and moves the whole leaf (one undo step); ⇧ floats the whole group at the release; ⌘ swaps with a plain panel only, never another group; miss snaps a docked group back and moves a floating one; a floating group docks whole on an edge; centres never group"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerWholeGroupDragTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Float Group / Dock Group button drawing, tooltip and VoiceOver label; a real whole-group drag in the VM"
    requirement: TABS-03
    verification:
      - kind: manual
        ref: "VM UAT at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "The AppKit view and a live drag need eyes; the plan runs no VM test (the moves reuse proven frame and park writes)"

duration: 16min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 06: Whole-group moves Summary

**The strip's third button floats a docked group, or docks a floating one, as one unit in one undo step. Dock Window, Float Window, the green button, Arrange All, Float All, re-homing, Move, Swap, Snap and a title-bar drag of the selected window now act on the whole group, so no path tears out one member or overlaps windows.**

## Performance

- **Duration:** about 16 min
- **Started:** 2026-11-02T01:59:50Z
- **Completed:** 2026-11-02T02:16Z
- **Tasks:** 3
- **Files modified:** 12 (760 insertions, 93 deletions)

## Accomplishments
- Model: `removeLeaf` takes a panel or tab group out of the tree like `remove` takes a panel. It returns the node and its members' states, and `remove` now uses it for panels. `insertLeaf` / `insertRootLeaf` are `insert` / `insertRoot` for a whole leaf; they refuse a member already in the tree and validate in release. `swap` exchanges two leaves when at most one is a group. `applyDrop(_:leaf:states:ids:)` maps edges and the layout edge to `insertLeaf`, and a centre throws. `DesktopLayer.removeGroup` / `addGroup` move a floating group with its member states, members at the content rect.
- Engine: `toggleGroupFloat` refuses while paused or not ready, then calls `floatGroup` or `dockGroup`. `floatGroup` uses `Planner.floatFrame` on the group frame: the selected member's pre-dock frame plus the band, else 90% of the tile. The minimum is the largest member minimum plus 32 pt, and a hidden Desktop is shown first. `dock()` handles a floating group at the group frame's centre, including the Blocked flash over the group's would-be tile. `float()` sends a docked member to `floatGroup`. The green button reaches both through the commands.
- Arrange All docks a floating group as one leaf, standing in the order as its selected member. Float All floats one unit per leaf at its tile rect. Both count a group once.
- `rehome` moves the selected member's whole group to the new desk's Desktop as a floating group at its content frame plus the band, and ignores a hidden member.
- Move Window moves the leaf. Swap lets the focused window be a group member, but the window it swaps with must be a plain panel. Snap snaps the group frame.
- Drag: `movingGroup` marks a drag of a group's selected member. `hover` skips both group targets for it. Previews, the snap-back origin, the clamp ghost and tile crossing use the group frame. `dropping`, `commitUndock` and `undockPlan` move the leaf or floating group as one unit, and `commitSwap` uses the relaxed `swap`.
- Shell: the strip's buttons are `[.closeGroup, .minimizeGroup, floating ? .dockGroup : .floatGroup]`, with tooltip and accessibility label "Float Group" / "Dock Group". Pressing sends `.toggleGroupFloat(group)`.

## Task Commits

1. **Task 1: Tracer, Float Group end to end (model, engine, strip)** - `7564a35` (feat)
2. **Task 2: Dock Group, Dock/Float Window, green button, Arrange/Float All, rehome, tree commands** - `7cc20c9` (feat)
3. **Task 3: Whole-group title-bar drag** - `9c7beb5` (test, RED), `49efad9` (feat, GREEN)

## Verification
- Task 1 `<verify>` (tracer gate): the filtered run passed with 49 + 9 + 69 tests before expansion.
- Task 2 `<verify>`: the filtered run passed with 26 + 135 tests, and the engine and model suites passed in full (219 + 892).
- Task 3 `<verify>`: `swift test` full suite green with 219 + 379 + 92 + 899 tests and no failures, and `scripts/check-no-appkit.sh` OK (55 files).
- No VM run, as planned: the moves reuse proven frame and park writes. The drag goes to the 07-11 UAT backstop. Nothing live ran on the host.

## Deviations from Plan

1. **[Rule 2 - Missing critical] `removeGroup` / `addGroup` carry member states.** The plan's `removeGroup` returned only the group, so docking a group with an absent member would have marked it present. It now returns `(group, states)`, and `addGroup` takes the states. Commit `7564a35`.
2. **`swap` relaxation landed in Task 1, not Task 3.** It is a TreeEdits change next to the other leaf edits, and its model tests went in with them. `LayoutEditTests.swapRejectsSelfTabsAndUnknownWindows` asserted that panel and group throw. It now uses two groups for the refusal (an intended behaviour change). Commit `7564a35`.
3. **[Rule 1 - Bug] Wanted frame lost on Dock Group.** 07-04's rule cleared the wanted frame of every window that left a floating group, including one that left by docking. A Dock Group then Float Group round trip lost the pre-dock frame. The rule now applies only to windows still floating. Commit `7cc20c9`.
4. **Task 2 had no separate RED commit.** Its tests went in with the code in one commit, and passed on their first green run apart from one test that computed the snap rect from the wrong Desktop rect. Task 3 followed RED then GREEN.
5. **Move and Swap commands added.** They are not bullets in Task 2, but they are in the must-have truths ("Focus, Move, Swap … act on the group's tile"). `moveOrSnap` uses `removeLeaf` + `insertLeaf`, and `previousDocked` accepts a group member as the focused window.
6. **Test fixture: `bareGroup(displays:)` and `bareFloatingGroup(fMinimum:)` parameters** were added for the rehome and no-room tests.

## Known Stubs
None. 07-05's stub (`TabStripView.label` / `press` empty for `.floatGroup` / `.dockGroup`) is resolved.

## Threat Flags
None. T-07-16 is mitigated: each whole-group move is one `World.edit` whose candidate is validated all-or-nothing, `insertLeaf` refuses duplicate identities (model test), and every drag, float, dock, swap, arrange and rehome path with a group has an engine test.

## Self-Check: PASSED
