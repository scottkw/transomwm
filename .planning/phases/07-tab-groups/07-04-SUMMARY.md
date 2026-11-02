---
phase: 07-tab-groups
plan: 04
subsystem: tiling
tags: [swift, tab-groups, floating, desktop-layer, persistence, hit-test]

requires:
  - phase: 07-tab-groups
    plan: 03
    provides: TabStrip, strip follow / Space handling, raiseStrip on focus
  - phase: 07-tab-groups
    plan: 02
    provides: reveal-then-park select, D-08 activation and suppression, showStrips
  - phase: 07-tab-groups
    plan: 01
    provides: TabBand, group dwell, decideGroup / commitGroup, sized parks
provides:
  - FloatingTabGroup sidecar on DesktopLayer (group / addTab / selectTab / group(containing:), dissolve on remove, member frames = content rect)
  - Backward-compatible DesktopLayer Codable (absent `groups` decodes, empty list not written), group validation in DesktopLayer and World
  - GroupTarget.floating / .floatingGroup, floatingGroupTarget hit test, droppingIntoFloating, floating decide / commit (one undo step)
  - TabGroupRef + tabGroup(holding:) covering docked and floating groups; public isHiddenTab(_:)
  - Planner floating-group placement (hidden members parked once at the content size, band in the Desktop minimum); floating strips (floating: true)
affects: [07-05, 07-06, 07-07, 07-08, 07-09, 07-10, 07-11, 07-12]

actuals:
  tokens: 15400
  tasks: 3
  commits: 4
plan_head_before: 8121e1fc496613f9449c751e407919622eee8a7d
plan_head_after: 508cbeb8394a8de18332b4a61c0155bd67d49670

tech-stack:
  added: []
  patterns:
    - "Floating group = sidecar over FloatingWindow records (add-alongside): members stay in DesktopLayer.windows, each stored at the group's content rect"
    - "One group lookup (tabGroup(holding:)) for docked leaves and floating groups; GroupKey.node is the leaf ID or the floating group ID (same IDSource)"

key-files:
  created: []
  modified:
    - Sources/TransomModel/DesktopLayer.swift
    - Sources/TransomModel/World.swift
    - Sources/TransomEngine/DragSession.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Planner.swift
    - Sources/TransomMac/Overview/OverviewController.swift
    - Tests/TransomModelTests/TabGroupModelTests.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift

key-decisions:
  - "Assumption delta (pluralization): add-alongside. FloatingWindow stays the primary record; FloatingTabGroup only groups. Debt: member frames are duplicated (each equals the content rect). Promote to a primary group record only if groups need state beyond membership/selection/frame (group z-order, nesting) or member frames drift"
  - "World.undo keeps the snapshot frame of a window whose floating group the undone edit changed (that frame came from the edit, not the OS); other floaters keep their current frame as before (Pitfall 10)"
  - "A floating group's wanted frame belongs to its selected member: the drop commit gives the dragged window the replaced tab's wanted frame (none for a new group), a select carries it to the new member, and a window leaving a group (dissolve, undo) loses its wanted frame, followed by one more replan"
  - "Floating hit test: the topmost present floater under the pointer (live frame), skipping the dragged window and hidden members; if that window is excluded / never-dock or the point is outside its middle 50%, nothing groups (no fall-through to a window behind)"
  - "A floating group whose selected member is absent takes no part, as docked: hidden members get no park and are not moved"

patterns-established:
  - "Engine paths that must skip hidden members ask isHiddenTab(_:) or the group's selected index; moved() drops a floating hidden member's reports before recording (Pitfall 5)"

requirements-completed: [TABS-05, TABS-01, TABS-02]

coverage:
  - id: D1
    description: "Model: group / addTab / selectTab / setFrame / remove-dissolve / rekey / mapWindows keep the invariant (every member once in windows, stored frame = content rect); JSON round trip; a group-less fixture desk decodes; empty list not written"
    requirement: TABS-05
    verification:
      - kind: unit
        ref: "Tests/TransomModelTests/TabGroupModelTests.swift#FloatingTabGroupModelTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Validation rejects <2 members, missing member, window in two groups, out-of-range selected, non-finite frame, duplicate IDs, too many groups; World rejects group IDs >= ids.next or equal to a tree node"
    requirement: TABS-05
    verification:
      - kind: unit
        ref: "Tests/TransomModelTests/TabGroupModelTests.swift#FloatingTabGroupModelTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Centre drop on a floater after 400 ms previews and forms a group at its frame (one setFrame, one sized park, one undo step, floating strip); a group's centre adds a tab; the Desktop's own centre and a floater's edge band form nothing; undo restores both floaters; a docked window can group onto a floater"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerFloatingTabsTests, #FloatingGroupPlannerTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Selected-member move moves the group and strip; hidden members' moves and resizes change nothing; reveal-then-park select with no undo step; D-08 activation with 1 s suppression; a dissolve gives the survivor the whole frame; members from different apps, docked and floating"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerFloatingGroupBehaviourTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Desktop focus moves skip hidden members; a hidden Desktop parks every member once and showing it brings back only the selected; isHiddenTab exact for docked and floating"
    requirement: TABS-05
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#FloatingGroupVisibilityTests"
        status: pass
    human_judgment: false
  - id: D6
    description: "Overview drops hidden tabs from the shown list and hidden Spaces' planned floaters"
    requirement: TABS-05
    verification:
      - kind: manual
        ref: "VM UAT at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "OverviewController.inputs needs a live CG window list; no unit test covers the filter"

duration: 13min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 04: Floating tab groups Summary

**A window rested 400 ms in the middle 50% of a floating window on the Desktop tile now groups with it at that window's frame (dragged window selected, target parked at the content size), or joins a floating group as its last tab. Floating groups persist as an optional `groups` list on each Desktop layer, so schema 2 files without it still load. They move by their selected window, switch tabs with 07-02's reveal-then-park and D-08 rules, and stay out of focus moves and the overview.**

## Performance

- **Duration:** about 13 min
- **Started:** 2026-11-02T01:28:35Z
- **Completed:** 2026-11-02T01:41Z
- **Tasks:** 3
- **Files modified:** 9 (999 insertions, 46 deletions)

## Accomplishments
- Model: `FloatingTabGroup` and `DesktopLayer.groups`. Members stay `FloatingWindow`s at the content rect. `setFrame` on a member moves the whole group, and `remove` dissolves a group at one member, giving the survivor the full frame. Custom Codable uses `decodeIfPresent` and leaves `groups` out when it is empty. Validation is linear in windows and members and caps groups at `LayoutTree.maxNodes`. `World.validate` checks group IDs against `ids.next` and the desk's tree.
- Engine: `floatingGroupTarget` hit test in `hover(for:)` when the pointer is over the Desktop tile or no tile. `droppingIntoFloating` handles both the dry run and the commit in one `World.edit`, reflowing the source desk when the window comes from another desk. Blocked and Collapsed cases work as for docked groups. Announcements and `group N: created … (floating)` log lines are emitted.
- Planner: hidden members of a floating group are parked once at the content size, also when the Desktop is hidden. The selected member's minimum plus 32 pt counts toward the Desktop minimum.
- Floating strips (`floating: true`) appear over the planned or stored content rect. They are hidden while the Desktop is hidden or the selected member is parked.
- One group lookup, `tabGroup(holding:)`, now serves select, reveal timeout, D-08, raise and suppression. Floating selection is a `World.reflow` with `desktop.selectTab`.
- `isHiddenTab(_:)` is used by `focusNeighbour` and by both of `OverviewController`'s window lists.

## Task Commits

1. **Task 1: Tracer, centre drop on a floating window makes a floating group** - `c767b93` (feat)
2. **Task 2: Floating group moves, selection and activation** - `f4a3c74` (feat)
3. **Task 3: Hidden members out of focus moves and the overview; full suite** - `ed4286f` (test, RED), `508cbeb` (feat, GREEN)

## Files Created/Modified
- `Sources/TransomModel/DesktopLayer.swift` - `FloatingTabGroup`, the group mutators, dissolve, validation, Codable
- `Sources/TransomModel/World.swift` - group ID validation; undo keeps snapshot frames when group membership changed
- `Sources/TransomEngine/DragSession.swift` - `GroupTarget.floating`, `.floatingGroup`
- `Sources/TransomEngine/Arranger+Tabs.swift` - hit test, `droppingIntoFloating`, floating decide/commit, `TabGroupRef`, `tabGroup(holding:)`, `isHiddenTab`, `selectInWorld`, floating strips
- `Sources/TransomEngine/Arranger.swift` - floating hit in `hover`, hidden-member guard in `moved`, hidden members skipped by the "move to the model's frame" loop, wanted frames dropped when a window leaves a group, Desktop focus filter
- `Sources/TransomEngine/Planner.swift` - floating group parks and band in the Desktop minimum
- `Sources/TransomMac/Overview/OverviewController.swift` - hidden tabs filtered
- Tests: `FloatingTabGroupModelTests` (15), `ArrangerFloatingTabsTests` (7), `FloatingGroupPlannerTests` (3), `ArrangerFloatingGroupBehaviourTests` (6), `FloatingGroupVisibilityTests` (3)

## Decisions Made
The assumption-delta decision is **add-alongside**, recorded for later phases. `FloatingWindow` stays the primary record of a floating window and `FloatingTabGroup` is only a grouping over those records. This keeps the roughly 80 `desktop.*` call sites unchanged, and an older build reads a new file as plain floaters. The accepted debt is that member frames are duplicated, since each equals the content rect. The invariant test guards this after every mutator. Promote the group to a primary record only if groups need state beyond membership, selection and frame (group z-order, nesting), or if member frames drift. The other decisions are listed under `key-decisions`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Undo of a grouping would have left the target at the content rect**
- **Found during:** Task 1
- **Issue:** `World.undo` keeps every floating window's current frame (Pitfall 10). A target that was grouped and then ungrouped by undo would have stayed at the content rect, which the grouping edit set, not the OS.
- **Fix:** the current frame is kept only when the window's group is the same in the snapshot and now. Model test added.
- **Files modified:** Sources/TransomModel/World.swift
- **Commit:** c767b93

**2. [Rule 1 - Bug] Stale wanted frames would pull a group member off its content rect**
- **Found during:** Task 2
- **Issue:** every floater gets a wanted frame at admission. The Planner plans the selected member at `wanted ?? stored`, so a stale wanted frame would move it away. A dissolve survivor would also keep a content-sized wanted frame, leaving a 32 pt gap where the band was.
- **Fix:** the commit gives the dragged window the replaced tab's wanted frame (none for a new group), and a select carries it over. A window that leaves a floating group loses its wanted frame, and the input plans once more. Test: the survivor of a dissolved, moved group is written at the whole frame.
- **Files modified:** Sources/TransomEngine/Arranger+Tabs.swift, Sources/TransomEngine/Arranger.swift
- **Commit:** c767b93, f4a3c74

**3. [Rule 2 - Missing critical] Hidden members kept out of the "move to the model's frame" loop**
- **Found during:** Task 1
- **Issue:** `planShown` moves any present floater that is away from its stored frame. Without a guard, the hidden members of a group whose selected member is absent would have been moved on top of each other at the content rect.
- **Fix:** that loop skips non-selected members.
- **Commit:** c767b93

### Scope notes
- Task 2's engine code landed in Task 1: the `moved` guard and the generalised select / D-08 / raise / suppression lookup. Floating strips and selection needed them, so Task 2's tests passed on their first run (as in 07-01). The RED step in that task was its setup fixture, not the behaviour. Task 3 had a real RED, the focus move.
- No VM run, as the plan says: floating groups reuse 07-01's park path and 07-02's reveal path.
- Not handled, for later plans: dragging a member out of a floating group, Float/Dock of a whole group (07-06), `arrangeAll` / `floatAll` of groups, and `rehome` of a selected member to another display (it leaves its group, an accepted OS fact). Rescue-stranded is not group-aware either.
- `swift format lint --strict` was not run: the repo has no `.swift-format`, and the default config disagrees with the repo's 4-space style everywhere.

**Total deviations:** 3 auto-fixed (2 bugs, 1 missing critical)
**Impact on plan:** none on scope.

## Issues Encountered
None. Host: `swift test` passed 213 + 378 + 90 + 865 tests (`.build/0704-t3.log`, integration suites skipped on the host), and `scripts/check-no-appkit.sh` passed. `LayoutFile.swift` is untouched (schema 2), and the LayoutStoreTests and PersistenceTests fixture comparisons pass unchanged. Nothing live ran on the host.

## Threat Flags
None beyond the plan's threat model. T-07-10 and T-07-12 are mitigated and tested; T-07-11 holds by construction.

## User Setup Required
None.

## Next Phase Readiness
- Later plans can use `tabGroup(holding:)` and `isHiddenTab(_:)` for any action on a group, docked or floating. `GroupKey.node` is a floating group's ID when `TabGroupRef.floating` is true.
- Strip buttons for floating groups (the Dock Group variant) can key off `TabStrip.floating`.

## Self-Check: PASSED
