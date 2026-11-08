---
phase: 08-saved-views-urls-persistence
plan: 06
subsystem: overlay
tags: [placeholders, nspanel, click-through, camera, overview, tab-groups, swift-testing, vm-live]

requires:
  - phase: 08-saved-views-urls-persistence
    provides: "08-04 Placeholder, isPlaceholder, placeholderCount; 08-05 the Command-line tool Debug line"
provides:
  - ArrangerEffect.placeholders([PlaceholderTile], displayUUID:), sent from planShown only on change
  - PlaceholderPanels and PlaceholderView (click-through, normal level ordered back, one Space, out of captures)
  - TileLayer.Content.placeholder, the one recipe for panel, stage and overview; PlaceholderLook for name, icon and colour
  - CameraMove.placeholders, OverviewDisplayInput.placeholders, OverviewDisplayLayout.placeholders, Arranger.homePlaceholders(on:)
  - Arranger.liveTabs and withoutWaiting, the two helpers shown-desk paths use to skip waiting windows
  - ViewCopy.placeholderLabel, placeholderHelp, waitingLine and the "Waiting for windows" Debug line
  - the fixture's `order-back {index}` command
affects: [08-07 UAT looks at the drawing and proves the real-app paths]

actuals:
  tokens: 20400
  tasks: 2
  commits: 5

plan_head_before: 683b0d4715c6dfae0a0fd751ae4caf04dbb8e232
plan_head_after: 1d62754120bdb3abf42d4a4a30deaff0c8817603

tech-stack:
  added: []
  patterns:
    - "One drawing recipe: a panel view hosts the same TileLayer content the stage and overview draw"
    - "What looks for a place to go gets a Resolution without the waiting nodes, so Neighbours and Navigator needed no change"

key-files:
  created:
    - Sources/TransomMac/Overlay/PlaceholderPanels.swift
  modified:
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Placeholders.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Navigator.swift
    - Sources/TransomEngine/OverviewLayout.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overview/OverviewController.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Shell/ViewCopy.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/TileLayer.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomFixtureApp/main.swift
    - Tests/TransomEngineTests/ArrangerPlaceholderTests.swift
    - Tests/TransomEngineTests/OverviewLayoutTests.swift
    - Tests/TransomMacTests/ViewCopyTests.swift
    - Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift

key-decisions:
  - "The panel view hosts a TileLayer instead of drawing its own layers, so the panel, the stage and the overview cannot drift apart"
  - "A group that all waits shows one tile over its whole group frame and no strip, since the band would otherwise be an empty hole"
  - "A collapsed placeholder is shown as a placeholder tile at its block rect, never as a collapsed block with a double-click"
  - "A placeholder on another Space gets no mini tile: it would count and select as a window"
  - "An expired tile leaves at once during a pause; a filled one stays until Resume, when its window is written"
  - "The click-through VM check clicks twice at one point: through the panel to a fixture window sent behind it, then, with that window closed, to Finder's desktop"

patterns-established:
  - "Tests that click in the guest pick a point at least 16 pt clear of its own windows: a click just outside a window goes to that window's resize margin"

requirements-completed: [VIEW-04]

coverage:
  - id: D1
    description: "A waiting tile shows a click-through panel at its rect, at normal level, behind real windows; a click goes through it to the window beneath, or to Finder's desktop, and leaves Transom inactive"
    requirement: VIEW-04
    verification:
      - kind: e2e
        ref: "scripts/vm-live-test.sh RematchIntegrationTests#aPlaceholderIsClickThroughAndBehindRealWindows"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift#eachWaitingWindowGetsATileAtItsRectOnceAndNoMore"
        status: pass
    human_judgment: false
  - id: D2
    description: "Filled and expired placeholders leave the next list, expiry also during a pause"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift#aFilledPlaceholderLeavesTheNextListAndAnExpiredOneToo, #expiryWhilePausedStillTakesTheTileAway"
        status: pass
    human_judgment: false
  - id: D3
    description: "Camera moves carry placeholders apart from tiles; the overview draws them but never counts or selects them"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift#aCameraMoveCarriesPlaceholdersApartFromTiles; Tests/TransomEngineTests/OverviewLayoutTests.swift#aPlaceholderIsDrawnButNeverCountedOrSelected"
        status: pass
    human_judgment: false
  - id: D4
    description: "No shown-desk path faults on or targets a waiting window: tab strips, collapsed blocks, Next Tab, Close Group, focus moves, step-in, pan"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift (Shown-desk paths section)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Copy: the label, its fallback, the help text and the Debug line"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/ViewCopyTests.swift"
        status: pass
    human_judgment: false
  - id: D6
    description: "How a placeholder looks: dim fill, dashed border, icon, capsule, light and dark, Increase Contrast, small tiles, and on the stage and in the overview"
    verification: []
    human_judgment: true
    rationale: "No test asserts pixels, and the panel is sharingType .none, so a screenshot may not show it; check it by eye in 08-07 UAT"
  - id: D7
    description: "The fade timing, and Space changes with a placeholder shown or a panel stranded"
    verification: []
    human_judgment: true
    rationale: "No VM test switches Spaces with a placeholder shown, and no test measures the 120 ms fades; check in 08-07 UAT"

duration: 23min
completed: 2026-11-04
status: complete
---

# Phase 8 Plan 06: Placeholder Tiles Summary

**A window that has not come back now holds its tile as a dim, click-through "Waiting for {App}…" panel behind every real window, drawn with the same recipe on the stage and in the overview, and no shown-desk path faults on or targets it.**

## Performance

- **Duration:** 23 min
- **Started:** 2026-11-04T01:01:45Z
- **Completed:** 2026-11-04T01:24:58Z
- **Tasks:** 2
- **Files modified:** 19

## Accomplishments

- `planShown` reports each placeholder's tile per shown display, only on change.
- `PlaceholderPanels` shows them click-through, at normal level ordered back, on their desk's Space only and out of captures, with 120 ms fades.
- Camera moves and the overview draw them with the panel's recipe; they are never selected or counted.
- Debug has "Waiting for windows: none / 1 / {k}" between Saved views and Command-line tool.

## Pitfall 8 audit: shown-desk paths changed

| Path | Change |
|---|---|
| `tabStrips` (docked and floating) | A waiting member gets no tab (the 08-04 handoff); a group whose selected member waits has no strip |
| `planTiles` strips (`StripMove`) | Same member filter |
| `tabGroupMembers` (overview strip and tab suffix) | Same member filter |
| `planShown` collapsed blocks | A waiting window is a placeholder tile, not a block; `groupSize` counts live members |
| `tabCommand` Next and Previous Tab | Cycle live members only; refuse when every member waits |
| `closeGroup` | The queue skips waiting members |
| `focusNeighbour` | Skips waiting tiles and waiting floaters |
| `cameraStep` step-in and pan (gestures too) | Skip nodes holding only waiting windows; pan keeps the current view's own rect |
| `OverviewController.plannedWindows` | No mini tile for a placeholder on another Space |
| `planFloatingLostRoom` | A fault fixed, see Deviations |

Checked and left alone: `groupable` (already refuses untracked windows), `stageClick` (a dead ID matches no tracked window), `zoomTo`'s focus (already checks `windows`), `saveView` and `viewDestination` (a saved view keeps waiting identities, remapped on fill), `floatAll` and `moveOrSnap` (a placeholder holds its tile like a window, no crash).

## VM logs

- `.build/0806-t1-vm.log`: `RematchIntegrationTests`, 3 tests passed, tracer gate re-run after the commit.
- `.build/0806-t2-RematchIntegrationTests.log`: 3 tests passed on the final code, with the Finder check.
- `.build/0806-t2-OverviewIntegrationTests.log`: 3 tests passed, one VM job, before a one-line refactor of `waitingLine`.
- Host: `.build/0806-t2.log`, full `swift test` passed on the final code. Nothing live ran on the host.

## Task Commits

1. **Task 1: Tracer, a dim click-through tile at its rect** - `a984e50` (feat). The tracer gate re-ran its verify after the commit and passed.
2. **Task 2: Stage, overview, Debug line, audit** - `a365bd8` (test), `38b3c8c` (feat)
3. **Finder check added after the first close-out** - `1d62754` (test); `39595be` is the first docs commit, so `commits` counts it too

## Files Created/Modified

- `Sources/TransomMac/Overlay/PlaceholderPanels.swift` - panel pool, view, `PlaceholderLook`
- `Sources/TransomMac/Zoom/TileLayer.swift` - the placeholder recipe; `text` takes a colour
- `Sources/TransomEngine/Arranger+Placeholders.swift` - `PlaceholderTile`, `homePlaceholders`, `withoutWaiting`, `showPlaceholders`
- `Sources/TransomEngine/Arranger+Camera.swift`, `OverviewLayout.swift` - placeholder rects apart from tiles
- `Sources/TransomEngine/Arranger.swift`, `Arranger+Tabs.swift`, `Navigator.swift` - the audit
- `Sources/TransomMac/ArrangeController.swift`, `Overview/OverviewController.swift`, `Zoom/StagePanel.swift`, `Zoom/ZoomController.swift` - shell wiring and drawing
- `Sources/TransomMac/Shell/ViewCopy.swift`, `StatusItemController.swift` - copy and Debug line
- `Sources/TransomFixtureApp/main.swift` - `order-back`
- Tests as listed in the frontmatter

## Decisions Made

See `key-decisions` above. VIEW-04 stays unchecked in REQUIREMENTS.md: 08-07 also declares it, so the shared-ID gate (`requirements.ready-ids`) reports it blocked until 08-07's SUMMARY exists. I did not override the gate. `requirements-completed` lists it because the template copies the plan's array.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A held window with a learned minimum stopped its whole desk's plan**
- **Found during:** Task 2 (collapsed-block test)
- **Issue:** `forget` dropped a held window's collapsibility, so its minimum made it unfit. `planFloatingLostRoom` then threw `windowNotFound`, because a waiting window has no frame to float at, and the desk got no plan until expiry.
- **Fix:** a held window stays collapsible and a fill passes that on; an unfit waiting window loses its minimum in that plan instead of faulting.
- **Files modified:** `Sources/TransomEngine/Arranger.swift`, `Arranger+Placeholders.swift`
- **Verification:** `aCollapsedPlaceholderIsATileNotABlock`, including its zoom-off step
- **Committed in:** `38b3c8c`

**2. [Rule 2 - Missing critical] Waiting members in paths the plan did not name**
- **Found during:** Task 2 audit
- **Issue:** Next Tab could select a waiting member, Close Group would press one, floating strips showed one, and a mini tile counted one.
- **Fix:** the rows of the audit table above. Also an expired tile leaves during a pause, whose replan sends nothing.
- **Verification:** the Shown-desk paths tests
- **Committed in:** `a984e50`, `38b3c8c`

**3. [Rule 3 - Blocking] Files outside the plan's list**
- **Issue:** `TileLayer.swift` holds the shared recipe, `ZoomController.swift` builds stage tiles, `Arranger+Tabs.swift` holds strips, and the fixture needed `order-back` for the click check.
- **Fix:** edited them. `PlaceholderView` hosts a `TileLayer`, so the plan's `CAShapeLayer` lives there rather than in the panel file.
- **Committed in:** `a984e50`, `38b3c8c`

**4. [Rule 3 - Blocking] The VM test's click check grew**
- **Found during:** Task 1
- **Issue:** the plan checks only that Transom does not activate, which a swallowed click would also pass, and the guest's own windows cover much of each tile.
- **Fix:** the test picks a point 16 pt clear of the guest's windows, then requires a click through the panel to reach a fixture window sent behind it (new fixture `order-back`), and with that window closed to make Finder frontmost.
- **Files modified:** `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift`, `Sources/TransomFixtureApp/main.swift`
- **Committed in:** `a984e50`, `1d62754`

---

**Total deviations:** 4 auto-fixed (1 bug, 1 missing critical, 2 blocking)
**Impact on plan:** all needed for the stated truths. No new features.

## Issues Encountered

- My first VM clicks and a guest probe landed 6 pt beside a TextEdit window, inside its resize margin, and did nothing. From that I wrongly concluded a posted click on the guest's desktop never activates Finder, and wrote so in the first SUMMARY and a test comment. A second probe at a clear point showed Finder does activate, so both were corrected and the Finder check added. The test now needs 16 pt of clearance; it picks the first such point in tile 0, and if the guest's windows ever cover that tile it fails with an explicit message.
- A stray file from a mistyped `rsync` destination landed in the repo root. It was never staged, and was removed.

## Known Stubs

None. One `shortcut:` in `Arranger.homePlaceholders`: a waiting window whose learned minimum no longer fits gets no tile in the overview or a zoomed plan until it expires. Its tile stays reserved; only the drawing is missing, in that edge case.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 08-07 UAT should look at a placeholder by eye (coverage D6), switch Spaces with one shown (D7), and ⌘Q a real app (08-04's D4).
- The VM is stopped.

---
*Phase: 08-saved-views-urls-persistence*
*Completed: 2026-11-04*

## Self-Check: PASSED
