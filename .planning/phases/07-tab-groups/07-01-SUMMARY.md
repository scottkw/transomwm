---
phase: 07-tab-groups
plan: 01
subsystem: tiling
tags: [swift, tab-groups, resolve, drag, ax-park, preview]

requires:
  - phase: 03-drag-drop
    provides: DragSession dwell, dry run, commitDock, PreviewState, park commands
  - phase: 04-zoom
    provides: collapse/accept, ViewPlanner, camera parks
provides:
  - TabBand (32 pt band, 28 pt strip) and band-aware resolve (selected-only window rects, Resolution.hiddenTabs)
  - WindowCommand.park(size:), FramePlan/ViewPlan.parkSizes, sized parks with re-park on content-size change
  - Group dwell (400 ms / 16 pt), GroupTarget, PreviewState.group, DropAction.group, GroupCopy
  - Arranger+Tabs.swift (groupable, decideGroup, commitGroup), TabAnnouncement, ArrangerEffect.tabAnnouncement
  - TabCopy announcements, Group preview drawing, TabGroupIntegrationTests (VM)
affects: [07-02, 07-03, 07-04, 07-05, 07-06, 07-07, 07-08, 07-09, 07-10, 07-11, 07-12]

actuals:
  tokens: 22600
  tasks: 3
  commits: 3
plan_head_before: 47d5e85f87817dbd539306ab52b2d52487faf64c
plan_head_after: e4290c052c6dd841c67cc025d428f81a1cd31cfb

tech-stack:
  added: []
  patterns:
    - "A tab group is one leaf: only the selected member is written; hidden members are sized parks"
    - "Group dwell is a second deadline inside DragSession; DragSession.current = groupDecision ?? decision"

key-files:
  created:
    - Sources/TransomModel/TabBand.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Tests/TransomModelTests/TabGroupModelTests.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift
    - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift
  modified:
    - Sources/TransomModel/Resolve.swift
    - Sources/TransomEngine/WindowSystem.swift
    - Sources/TransomEngine/Planner.swift
    - Sources/TransomEngine/ViewPlanner.swift
    - Sources/TransomEngine/DragSession.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/ExclusionFilter.swift
    - Sources/TransomTestSupport/FakeWindowSystem.swift
    - Sources/TransomMac/AXWindowSystem.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overlay/PreviewStyle.swift
    - Sources/TransomMac/Zoom/ZoomController.swift

key-decisions:
  - "Only a tab group's selected member is an unfit candidate in resolve; hidden members count toward the group minimum but are never victims"
  - "A tab group whose selected member is absent takes no part (slot reserved, hidden members get no rect and no hiddenTabs entry)"
  - "commitGroup reuses commitDock at .tile(id, .center); the tab announcement is skipped when the commit already announced (collapse or refusal)"
  - "Arranger.decide, dropping, commitDock and missed dropped private to internal for Arranger+Tabs.swift"

patterns-established:
  - "Hidden tab parks: Planner turns Resolution.hiddenTabs into parks + parkSizes; planShown re-parks when the size changes by more than 0.5 pt"

requirements-completed: [TABS-01, TABS-05]

coverage:
  - id: D1
    description: "Band in resolve: a two-member group resolves one window rect (content rect) and one hidden tab; minimum +32 pt; no overlap"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomModelTests/TabGroupModelTests.swift"
        status: pass
    human_judgment: false
  - id: D2
    description: "Centre drop after 400 ms groups (dragged window selected); before 400 ms is the Phase 3 miss with no beep; one setFrame + one sized park; one undo step"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dwell rules: 16 pt restart, leaving cancels, shift bypass, command swap over a panel, command ignored over a group, exclusions, Add as a tab, Blocked (zoom off), Collapsed (zoom on)"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "A saved group re-forms on real windows with the hidden member parked at the content size (VM)"
    requirement: TABS-05
    verification:
      - kind: integration
        ref: "scripts/vm-live-test.sh TabGroupIntegrationTests (.build/0701-t1-vm.log: Test run with 1 test in 1 suite passed)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Group preview look (frame, strip band, label) and announcements via TabCopy"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/PreviewStyleTests.swift#GroupPreviewStyleTests, Tests/TransomMacTests/TabCopyTests.swift"
        status: pass
    human_judgment: true
    rationale: "The morph/fade of the drawn preview and how it reads on screen need a look in the VM UAT"

duration: 18min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 01: Tab group tracer Summary

**A docked or floating window rested 400 ms within 16 pt in another docked tile's centre groups on release: the selected member fills the tile minus a 32 pt band, the hidden one parks at that content size (proved on real windows in the VM), one undo step, spoken as "Grouped as tabs, 2 tabs".**

## Performance

- **Duration:** about 18 min
- **Started:** 2026-11-02T00:35:59Z
- **Completed:** 2026-11-02T00:54Z
- **Tasks:** 3
- **Files modified:** 25 (911 insertions, 62 deletions)

## Accomplishments
- `resolve` reserves the band: only the selected tab gets a window rect, the others go to `Resolution.hiddenTabs`; the group's minimum is the largest present member's plus 32 pt.
- Hidden tabs become sized parks end to end: `WindowCommand.park(size:)`, `parkSizes` in Planner and ViewPlanner (home size outside a zoomed view), `planShown` re-parks on a content-size change, `AXWindowSystem` parks at `size ?? info.frame.size`.
- Group dwell in `DragSession` (400 ms, 16 pt restart, kept once shown), `decideGroup` dry run with Group / Blocked / Collapsed outcomes, `commitGroup` with announcements and the "group {node}: ..." info log lines.
- Group preview drawn per the overlay recipe; `TabCopy` speaks the announcements.

## Task Commits

1. **Task 1: Tracer, centre drop after 400 ms groups two docked windows** - `7553d25` (feat)
2. **Task 2: Group dwell rules, exclusions, Blocked/Collapsed, add a tab** - `5be028f` (feat)
3. **Task 3: Group preview drawing and group announcements via TabCopy** - `e4290c0` (feat)

## Files Created/Modified
- `Sources/TransomModel/TabBand.swift` - band geometry (content, frame, strip)
- `Sources/TransomModel/Resolve.swift` - selected-only rects, `hiddenTabs`, band in the minimum
- `Sources/TransomEngine/WindowSystem.swift` - `park(_, displayUUID:, size:)`
- `Sources/TransomEngine/Planner.swift`, `ViewPlanner.swift` - `parkSizes`
- `Sources/TransomEngine/DragSession.swift` - `PreviewState.group`, `GroupCopy`, `GroupTarget`, `DropAction.group`, group dwell
- `Sources/TransomEngine/Arranger.swift` - sized parks, centre hover → group target, nextWake, release `.group`, `ArrangerEffect.tabAnnouncement`
- `Sources/TransomEngine/Arranger+Tabs.swift` - `TabAnnouncement`, `groupable`, `decideGroup`, `commitGroup`
- `Sources/TransomMac/Shell/TabCopy.swift` - announcements
- `Sources/TransomMac/Overlay/PreviewStyle.swift` - `.group` layers, `groupGlyph`
- `Sources/TransomMac/ArrangeController.swift` - `.tabAnnouncement` → log + VoiceOver
- `Sources/TransomMac/AXWindowSystem.swift`, `Sources/TransomTestSupport/FakeWindowSystem.swift`, `ExclusionFilter.swift`, `Zoom/ZoomController.swift` - park size plumbing
- Tests: `TabGroupModelTests`, `ArrangerTabsTests` (16 tests), `GroupPreviewStyleTests`, `TabCopyTests`, `TabGroupIntegrationTests`; band contract updates in `ResolveTests`, `LifecycleTests`, `TabsTests`, `ScenarioTests`

## Decisions Made
- Arranger members that dropped `private` (now internal, for `Arranger+Tabs.swift`): `decide`, `dropping`, `commitDock`, `missed`.
- `commitGroup` is `commitDock` at the target's centre plus the announcement, rather than a copy of it.
- Only the selected member of a group can be unfit; hidden members are not victims.
- A group whose selected member is absent takes no part (the slot is reserved). Its hidden members get no rect and no park entry; they stay where they were last parked.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Session updates were dropped while the hover was unchanged**
- **Found during:** Task 2
- **Issue:** `follow` wrote the session back only when the hover changed, so a 16 pt group-dwell restart was lost.
- **Fix:** write `drag = session` before `settleDrag` in the unchanged branch. The earlier wake's tick re-arms for the new deadline.
- **Files modified:** Sources/TransomEngine/Arranger.swift
- **Committed in:** 5be028f

**2. [Rule 3 - Blocking] Stand-in code so Task 1 compiled**
- **Found during:** Task 1
- **Issue:** the new `ArrangerEffect.tabAnnouncement` and `PreviewState.group` cases broke exhaustive switches in the shell.
- **Fix:** Task 1 added a log-only `.tabAnnouncement` case and a dock-style `.group` arm. Task 3 replaced both with the real behaviour.
- **Committed in:** 7553d25, replaced in e4290c0

**3. [Rule 3 - Blocking] Existing model tests encoded the old "every tab gets the tile" contract**
- **Found during:** Task 1
- **Fix:** updated `LifecycleTests`, `TabsTests` and `ScenarioTests` (not in the plan's file list) and `ResolveTests` to the band contract.
- **Committed in:** 7553d25

### Scope notes
- The "excluded or never-dock target" exclusion has no engine test. Reporting such a window removes it from the tree (D-29) before any drag can see it. `groupable` still refuses one as a defence.
- The debug-level "group dwell canceled: ..." lines are not emitted, because the engine has no debug-level effect. The info lines for created and added groups are emitted.
- No new test that keyboard Dock never groups: `Planner.dockTarget` is unchanged and still covered by the existing tests.
- `decideGroup`'s Blocked, Collapsed and add-a-tab branches were written in Task 1 (same function), so those Task 2 tests passed on their first run. Only the 16 pt restart and the collapsed-target exclusion failed first.
- `TabCopy.announcement` takes the `appName` parameter the plan specifies. The two current cases do not use it.

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** none on scope; all needed for correctness or to compile.

## Issues Encountered
None. VM run: `scripts/vm-live-test.sh TabGroupIntegrationTests`, log at `.build/0701-t1-vm.log` ("Test run with 1 test in 1 suite passed"). Nothing live ran on the host.

## User Setup Required
None.

## Next Phase Readiness
- 07-02 onwards can build on `hiddenTabs`, sized parks, `TabAnnouncement` and `TabCopy`.
- Not handled yet, for later plans: tab strips, switching tabs, quit restore of hidden members (Pitfall 3), floating groups, whole-group drags.

## Self-Check: PASSED
