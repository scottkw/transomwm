---
phase: 08-saved-views-urls-persistence
plan: 04
subsystem: engine
tags: [placeholders, relaunch, hint-matching, layout-restore, wake-clock, swift-testing, vm-live]

requires:
  - phase: 08-saved-views-urls-persistence
    provides: "08-02 HintMatcher and hint matches in LayoutRestore; 08-03 remapViews"
provides:
  - World.adopt(_:by:history:), a returning window takes a placeholder's place as an OS fact
  - Placeholder (ref, origin, wait, deadline, minimum) and PlaceholderState (table, quitting, fresh)
  - public Arranger.isPlaceholder(_:), placeholderCount, quitWait, launchWait, neverOpenedWait
  - the app-quit hold, the relaunch fill, launch-time placeholders, expiry through LifecycleSync, the wake on a deadline change
  - LayoutRestore.reattach returns `waiting` (and `removed` only for identity collisions)
  - ArrangeController.onEvent (internal), the event order the VM test reads
  - RematchIntegrationTests.quitAndRelaunchRefillsBothTiles
affects: [08-06 draws placeholders and audits tab strips for waiting members, 08-07 UAT]

actuals:
  tokens: 22300
  tasks: 2
  commits: 3

plan_head_before: d7d35450f80e28988933f99cc0fa1e0ed3a949cc
plan_head_after: 1d03e3a5221e8624dd5b9a5a5b5e016725bac213

tech-stack:
  added: []
  patterns:
    - "A placeholder is an untracked ref kept in the World plus a table entry with a deadline on the single wake clock"
    - "`handle` emits one .wake whenever the earliest placeholder deadline changes, so hooks need not"

key-files:
  created:
    - Sources/TransomEngine/Arranger+Placeholders.swift
    - Tests/TransomModelTests/WorldAdoptTests.swift
    - Tests/TransomEngineTests/ArrangerPlaceholderTests.swift
  modified:
    - Sources/TransomModel/World.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/LayoutRestore.swift
    - Sources/TransomMac/ArrangeController.swift
    - Tests/TransomEngineTests/ArrangerLifecycleTests.swift
    - Tests/TransomEngineTests/ArrangerRestoreTests.swift
    - Tests/TransomEngineTests/ArrangerMultiDeskRestoreTests.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift

key-decisions:
  - "The Pitfall 1 rollback was not added: the VM showed .appTerminated before both .windowDestroyed on every run, with the fixture's exit(0) quit"
  - "A returning window is matched before admit, so it never shows a hidden Desktop on its way to its tile (D-31), and a fill does not widen the camera"
  - "A stored display arrangement is not a launch: its unmatched windows still close instead of waiting"
  - "A saved ref whose identity a tracked window now carries (reused or synthetic ID) closes as before; only the rest wait"
  - "A dormant window (hidden Space, after a Transom restart) still closes on its app's quit, as its existing test requires"

patterns-established:
  - "Run live suites one per VM job: separate suites run in parallel and their fixtures fight"

requirements-completed: []

coverage:
  - id: D1
    description: "An app's quit keeps its docked tiles with no reflow, and its relaunch puts each window back in its own tile"
    requirement: VIEW-04
    verification:
      - kind: e2e
        ref: "scripts/vm-live-test.sh RematchIntegrationTests#quitAndRelaunchRefillsBothTiles"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift#quitThenRelaunchRefillsBothTiles"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every placeholder expires through the close path at 30 s, a sliding 10 s or 5 min, with no undo step and writes held while paused"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift (deadlines and pause sections)"
        status: pass
    human_judgment: false
  - id: D3
    description: "At Transom launch unattached docked windows wait, floaters are kept until expiry, ties leave tiles waiting with the windows floating"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerRestoreTests.swift#aDockedSavedWindowStillUnattachedHoldsItsTile, #aTieAtLaunchLeavesTheTilesWaitingAndTheWindowsFloating"
        status: pass
    human_judgment: false
  - id: D4
    description: "Command-Q of real apps (TextEdit, Safari, Terminal) reaches the Arranger in the same event order as the fixture"
    verification: []
    human_judgment: true
    rationale: "The plan limits the VM test to fixture windows, and the fixture quits with exit(0), not AppKit's terminate path; Assumption A1 stays unproven for real apps, so check it in 08-07 UAT"

duration: 22min
completed: 2026-11-04
status: complete
---

# Phase 8 Plan 04: Placeholder Lifecycle Summary

**Quitting an app now keeps its docked tiles reserved and its relaunch refills them through HintMatcher, while every saved window that never returns expires through the close path on the Arranger's wake clock.**

## Performance

- **Duration:** 22 min of the resumed run (an earlier attempt stopped on a network error with no edits on disk)
- **Started:** 2026-11-04T00:13:44Z
- **Completed:** 2026-11-04T00:35:28Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- `World.adopt` puts a returning window in a placeholder's panel, tab position or floating slot, and undo snapshots follow it.
- `.appTerminated` then `.windowDestroyed` holds a docked window; ⌘W with the app alive still closes the tile at once.
- Deadlines: quit + 30 s; launch + 10 s, restarted by each new window of the app; Transom launch + 5 min if the app never opens.
- Inventories can't close a placeholder, and every deadline is in `nextWake`.
- Launch-time placeholders, ties, late titles, tab members, pause, Restore All, Arrange All and Undo are all covered by engine tests.

## Assumption A1 and the VM

- **Observed order, three runs:** `["appTerminated", "windowDestroyed N", "windowDestroyed N+1"]`.
- **The 1.5 s rollback (Pitfall 1):** not needed for the fixture, so not added.
- **Limit:** the fixture exits with `exit(0)`. Real apps' ⌘Q is unverified (coverage D4).
- **VM logs:** `.build/0804-t1-vm.log`, `.build/0804-t1-gate-vm.log`, `.build/0804-t2-RematchIntegrationTests.log`.
- **Other suites, each alone:** `RecoveryIntegrationTests`, `QuitRestoreIntegrationTests` and `TabGroupIntegrationTests` passed after the contract change. `ViewsIntegrationTests` passed only in the combined run below and was not re-run alone.
- **Combined run:** one run with five suites in a single filter failed in four tests (`.build/0804-t2-vm.log`). The suites ran in parallel, so their fixtures interfered; the three that failed passed when re-run alone.

## Task Commits

1. **Task 1: Tracer, quit and relaunch** - `3517df1` (feat). The tracer gate re-ran its VM verify after the commit and passed.
2. **Task 2: Placeholder lifecycle** - `8466987` (test), `1d03e3a` (feat)

## Files Created/Modified

- `Sources/TransomEngine/Arranger+Placeholders.swift` - placeholder table, deadlines, hold, fill, expiry
- `Sources/TransomModel/World.swift` - `adopt`
- `Sources/TransomEngine/Arranger.swift` - hooks in events, tick, `nextWake`, restore, dormant handling
- `Sources/TransomEngine/LayoutRestore.swift` - `waiting` replaces closing unmatched windows
- `Sources/TransomEngine/Arranger+Tabs.swift` - Restore All keeps a group whose members all wait
- `Sources/TransomMac/ArrangeController.swift` - `onEvent` test hook
- `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`, `Tests/TransomModelTests/WorldAdoptTests.swift` - new suites
- `Tests/TransomEngineTests/ArrangerRestoreTests.swift`, `ArrangerLifecycleTests.swift`, `ArrangerMultiDeskRestoreTests.swift`, `ArrangerTabsTests.swift`, `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift` - extended or moved to the new contract

## Decisions Made

See `key-decisions` above. VIEW-04 stays open in REQUIREMENTS.md until 08-06 finishes, as the orchestrator asked.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `ArrangeController.onEvent` hook**
- **Found during:** Task 1
- **Issue:** the plan asks the test to log event order, but the controller is the only reader of `system.events`.
- **Fix:** one internal closure called just before the Arranger gets each event.
- **Files modified:** `Sources/TransomMac/ArrangeController.swift` (not in the plan's list)
- **Committed in:** `3517df1`

**2. [Rule 1 - Bug] Tests that encoded the old "unmatched saved window closes at launch" contract**
- **Found during:** Task 2
- **Issue:** four tests in `ArrangerTabsTests` and two in `ArrangerMultiDeskRestoreTests` expected the close at launch, and neither file is in the plan's list.
- **Fix:** each now asserts the waiting state, then the same final shape after expiry. The "relaunch: group re-formed" log no longer fires at launch, because the members wait; the expiry log line replaces it, and `regroupedLog` remains for identity collisions.
- **Committed in:** `1d03e3a`

**3. [Rule 2 - Missing critical] Correctness details the plan left out**
- **Found during:** Tasks 1 and 2
- **Added:**
  - a placeholder keeps its learned minimum, so neighbours don't reflow on a quit
  - a placeholder keeps its latest title, which the live World's ref may lack (Pitfall 2)
  - a window created before its old window's destroy event can still fill, because `quitting` also marks it fresh
  - a placeholder's own window returning ends the wait, in the event and inventory paths
  - a live member takes a waiting member's selection, so a group's tile shows what is there
  - `dissolveAllGroups` skips a group whose members all wait
- **Committed in:** `3517df1`, `1d03e3a`

---

**Total deviations:** 3 auto-fixed (1 blocking, 1 bug, 1 missing critical)
**Impact on plan:** all were needed for the stated truths. No new features.

## Issues Encountered

The first attempt at this plan stopped on a network error while the laptop slept, before any edit reached disk. This run started again from Task 1.

## Known Stubs

None. A hidden waiting member still gets a tab in `tabStrips` with an empty title until 08-06's Pitfall 8 audit, which the plan assigns there. The `shortcut:` in `LayoutRestore.reattach` documents the identity-collision close.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 08-06 can draw from `isPlaceholder`, `placeholderCount` and the table; it still needs `PlaceholderTile`, the effect and the tab strip filter.
- 08-07 UAT should ⌘Q a real app with docked windows and confirm the tiles wait (coverage D4). If they collapse, add the Pitfall 1 rollback.

---
*Phase: 08-saved-views-urls-persistence*
*Completed: 2026-11-04*

## Self-Check: PASSED
