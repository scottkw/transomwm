---
phase: 02-window-control
plan: 10
subsystem: window-tracking
tags: [swift, accessibility, appkit-tabs, tab-groups, cgwindowlist, swift-testing]

requires:
  - phase: 02-window-control (02-09)
    provides: CloseRule two-source close with isKnownTabMember, WindowTracker.decide, cached-element probes of known IDs, FakeWindowSystem close/lock simulation
  - phase: 02-window-control (02-01, 02-03)
    provides: WindowSnapshot.tabGroup (AXTabGroup count), CGWindowEntry in ObservationContext, WindowInfo.visibleMemberID/tabCount, fixture tabs:N and select-tab
provides:
  - TabGroupTracker (pure): group membership, leader identity, visible-member rebinding, boundsTolerance 1 pt
  - TabResolution (groupFor, memberIDs, tabCount)
  - WindowTracker tracks one window per native tab group under the leader's identity, sets visibleMemberID on every window
  - FakeWindowSystem.tabGroup(ids:frame:pid:visible:) and selectTab(_:)
  - TabsIntegrationTests (fixture tabs:3 switch and close, live)
affects: [02-11, 02-12, 02-13, phase-03-tiling, phase-04-zoom]

actuals:
  tokens: 11506
  tasks: 2
  commits: 4
plan_head_before: 8912e632d659384ab3896d758a37b67f93fcfce0
plan_head_after: 42a93c367007bf2b0b2f2eedc38149f16551dbad

tech-stack:
  added: []
  patterns:
    - "A tab group's identity is its first-seen visible member (the leader) for its whole life; address it through visibleMemberID"
    - "Close decisions for a tracked window go through the window ID it currently shows"

key-files:
  created:
    - Sources/PaneEngine/TabGroupTracker.swift
    - Tests/PaneEngineTests/TabGroupTrackerTests.swift
    - Tests/PaneEngineTests/TabScenarioTests.swift
    - Tests/PaneMacIntegrationTests/TabsIntegrationTests.swift
    - .planning/phases/02-window-control/tdd/02-10-task1-red.json
    - .planning/phases/02-window-control/tdd/02-10-task2-red.json
  modified:
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - .planning/phases/02-window-control/deferred-items.md

key-decisions:
  - "visibleMemberID is set on every tracked window (its own ID when untabbed), so Phases 3-4 can always address windows through it"
  - "knownWindowIDs returns each window's shown tab, so the app thread probes the tab that is actually on screen"
  - "Tab groups are re-resolved only on a full AXWindows answer; a failed list or a lock never dissolves a group"
  - "When the shown tab closes but members remain in the CG list, the group is kept (tabCount lowered) and the next listed tab rebinds it; it is destroyed only when no member remains"
  - "TabGroupTracker gained members(of:) beyond the planned API: the tracker needs the remaining members to decide whether a group survives a closed tab"

patterns-established:
  - "Listed members of one group bind in rank order (onscreen, leader, tab count), so a tab dragged out of a group leaves it instead of stealing its identity"

requirements-completed: [WIN-06]

coverage:
  - id: D1
    description: "Pure tab group membership: visible tab with AXTabGroup N >= 2 plus same-pid, layer-0, offscreen CG siblings within 1 pt; leader identity kept; rebinding on switch; 1.0/1.01 pt boundary"
    requirement: WIN-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TabGroupTrackerTests.swift (10 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A tabbed window is one tracked window; a tab switch emits windowFocused(groupRef) and no create/destroy; closing the visible tab keeps the group; the last tab closing destroys it once; an untabbed window stays its own window"
    requirement: WIN-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TabScenarioTests.swift (5 scenarios)"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/TabsIntegrationTests.swift#aTabbedWindowIsOneWindowThatFollowsItsVisibleTab() (6 of 6 live runs passed)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Finder, Terminal and Safari windows with three tabs each show as one Tracked Windows row reading \"3 tabs\", and clicking tabs never adds or removes rows"
    requirement: WIN-06
    verification: []
    human_judgment: true
    rationale: "Real apps' tab implementations differ (RESEARCH A1, A2: Safari may draw tabs inside one AX window with no AXTabGroup); needs end-of-phase UAT on this Mac"

duration: 11min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 10: Native Tab Groups Summary

**A natively tabbed window counts as one window. A pure `TabGroupTracker` builds each group from the visible tab's AXTabGroup count plus its offscreen CG siblings, and keeps the first-seen tab's identity. WindowTracker follows the visible tab through `visibleMemberID`, so a tab switch or a closed tab never reads as one window closing and another opening.**

## Performance

- **Duration:** about 11 min
- **Started:** 2026-10-25T16:13:30Z
- **Completed:** 2026-10-25T16:24:30Z
- **Tasks:** 2
- **Files modified:** 9 (6 source/test, 2 RED evidence, 1 deferred list)

## Accomplishments

- `TabGroupTracker` (PaneEngine, no AppKit) groups tabs. A group needs a visible tab whose AXTabs count is 2 or more. Its other members are CG windows of the same pid on layer 0, offscreen, with every side within 1 pt. Members are recomputed from the CG list on every refresh. The leader stays the same while any member is left. A new tab whose siblings overlap an existing group joins that group.
- `WindowTracker.ingest` maps each listed window to its group's identity before upserting it. Hidden tabs never become separate windows. A change of `visibleMemberID` emits `.windowFocused(groupRef)`.
- Close decisions use the tab that is showing (`visibleMemberID`) and pass `isKnownTabMember`. A group ends only when its last member has closed by the two-source rule.
- On the fake, `tabGroup(ids:frame:pid:visible:)` and `selectTab(_:)` mimic AppKit tabs: one listed, onscreen tab, the rest CG-only and offscreen.
- Live: the fixture's `tabs:3` window is one tracked window with tabCount 3. `select-tab` moves `visibleMemberID` within 1 s with no create or destroy. Closing the visible tab drops tabCount to 2 and keeps the identity.

## Task Commits

1. **Task 1: Tab group tracker**: `f27ef1f` (test, RED), `daa19b5` (feat, GREEN)
2. **Task 2: One window per tab group in tracker, fake and live**: `ff85da3` (test, RED), `42a93c3` (feat, GREEN)

**Plan metadata:** this SUMMARY's docs commit

## TDD Gate Compliance

- **RED Task 1:** `swift test --filter TabGroupTrackerTests` exited 1. The target `aVisibleTabAndItsHiddenSiblingsFormOneGroupLedByTheVisibleTab()` failed on its groupFor/memberIDs/tabCount assertions against a compiling stub. The classifier returned `RED_EVIDENCE_OK` (10 tests, 10 failing). Semantic check: no build or load faults; every failure was on a planned assertion. Evidence: `tdd/02-10-task1-red.json`.
- **RED Task 2:** `swift test --filter TabScenarioTests` exited 1. The target `aTabSwitchRebindsTheVisibleTabWithoutCreatingOrDestroying()` failed on `visibleMemberID == 11` and `windowFocused(ref 10)`. The classifier returned `RED_EVIDENCE_OK`. Semantic check: it failed for the intended reason (the tracker ignored tab groups). `closingTheLastTabsDestroysTheGroupOnce` already passed before GREEN, because the old tracker never reported the unsettled tab 11. Evidence: `tdd/02-10-task2-red.json`.
- **GREEN:** both feat commits pass their suites. No REFACTOR commit was needed.

## Files Created/Modified

- `Sources/PaneEngine/TabGroupTracker.swift`: `TabResolution` and `TabGroupTracker` (`boundsTolerance`, `update`, `memberClosed`, `isKnownMember`, `members(of:)`)
- `Sources/PaneEngine/WindowTracker.swift`: group resolution in `ingest`, `visibleMemberID`, close decisions through the shown tab, `knownWindowIDs` returns shown tabs
- `Sources/PaneTestSupport/FakeWindowSystem.swift`: `tabGroup(ids:frame:pid:visible:)`, `selectTab(_:)`
- `Tests/PaneEngineTests/TabGroupTrackerTests.swift`: membership, boundary, rebinding, leader-close, separate groups, new tab, drag-out, CG departure
- `Tests/PaneEngineTests/TabScenarioTests.swift`: the fake scenarios from the plan's behaviour list
- `Tests/PaneMacIntegrationTests/TabsIntegrationTests.swift`: live fixture `tabs:3` switch and close

## Decisions Made

See `key-decisions` in the frontmatter. The main one: if the leader tab closes first, the group keeps the leader's ref (02-01 assumption delta, Open Question 5). Phases 3-4 must address windows through `visibleMemberID`. The doc comment on `TabGroupTracker` says so.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] `TabGroupTracker.members(of:)` added to the public API**
- **Found during:** Task 2
- **Issue:** The planned API (`update`, `memberClosed`, `isKnownMember`) has no way to ask whether a group still has members after its shown tab closes. The tracker needs that answer to keep or destroy the group.
- **Fix:** Added `members(of leader:)`. The tracker intersects it with the CG list, which also covers terminated apps whose groups are never re-resolved.
- **Files modified:** Sources/PaneEngine/TabGroupTracker.swift, Sources/PaneEngine/WindowTracker.swift
- **Committed in:** daa19b5, 42a93c3

**2. [Rule 1 - Bug] `knownWindowIDs` returns the shown tab, not the identity's ID**
- **Found during:** Task 2
- **Issue:** Once the leader is hidden, probing the identity's window ID would probe a hidden tab and never see the shown tab close.
- **Fix:** It now returns `visibleMemberID ?? windowID`. Callers in AXWindowSystem only test it for emptiness or pass it to the probe, so their behaviour is unchanged for untabbed windows.
- **Committed in:** 42a93c3

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug). **Impact:** both are needed for the plan's close behaviour. No scope creep.

## Issues Encountered

- The intermittent `CloseIntegrationTests` unhide flake (deferred-items.md) did not recur in the 2 runs made here: one filtered run and one full `swift test`.
- New deferred item: `AXWindowSystem`'s focus-hint path looks a window up by its own CGWindowID, so a focus hint for a non-leader tab emits no `windowFocused`. The tracker's own `windowFocused` on a tab switch covers the case this plan needs. `AXWindowSystem` belongs to 02-11 in this wave, so it was not touched here.
- Known limits, marked in code with `shortcut:`:
  - If two listed tabs of one group appear in the same refresh (mid drag-out), they bind in AX order. That lasts one refresh.
  - Two separate tab groups of one app stacked at identical bounds could be merged. Not handled.

## Verification

- `swift test --filter TabGroupTrackerTests`: 10 passed
- `swift test --filter TabScenarioTests`: 5 passed
- `swift test --filter TabsIntegrationTests`: passed 6 of 6 live runs, run from this trusted terminal, not skipped; the fixture was cleaned up each time
- `swift test --filter "CloseScenarioTests|CloseIntegrationTests|ClassificationIntegrationTests"`: all passed, none skipped
- Full `swift test`: exit 0 (142 + 53 + 12 live + 114 tests)
- `swift build -c release -Xswiftc -enable-testing --build-tests`: only the known PermissionReducer warning
- `scripts/check-no-appkit.sh`: OK. Acceptance greps all pass: `public struct TabGroupTracker`, `boundsTolerance`, `tabGroups.update`, `isKnownMember`, `func selectTab`.

## Human UAT (end of phase)

- With Pane Debug running, open a Finder, a Terminal and a Safari window and give each three tabs (⌘T). Open Tracked Windows and click between tabs in each app. Expected: each app shows one row reading "3 tabs". Clicking tabs changes the Title column but never adds or removes rows. Note which apps report AXTabGroup: Safari may report one AX window with no tab group, which also shows one row (A1/A2).

## User Setup Required

None.

## Next Phase Readiness

- WIN-06 holds in unit, scenario and live fixture tests. Real-app behaviour still needs the UAT above.
- Phases 3-4: address windows through `WindowInfo.visibleMemberID`. A group's identity can name a tab that has already closed.

---
*Phase: 02-window-control*
*Completed: 2026-10-25*

## Self-Check: PASSED
