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
  commits: 3

plan_head_before: 683b0d4715c6dfae0a0fd751ae4caf04dbb8e232
plan_head_after: 38b3c8cd67379e8fa0a21b00372c4aed939aef5e

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
  - "The click-through VM check aims at a fixture window sent behind the panel: a posted click on the guest's bare desktop does not activate Finder, panel or no panel"

patterns-established:
  - "Tests that click in the guest pick a point at least 16 pt clear of its own windows: a click just outside a window goes to that window's resize margin"

requirements-completed: [VIEW-04]

coverage:
  - id: D1
    description: "A waiting tile shows a click-through panel at its rect, at normal level, behind real windows; a click goes through it to the window beneath and leaves Transom inactive"
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
    description: "A real Finder desktop click through a placeholder, the fade timing, Space changes with a stranded panel"
    verification: []
    human_judgment: true
    rationale: "The guest's bare desktop did not activate Finder on a posted click even with no panel, and no VM test switches Spaces with a placeholder shown; check in 08-07 UAT"

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
- `.build/0806-t2-RematchIntegrationTests.log` and `.build/0806-t2-OverviewIntegrationTests.log`: both passed, one VM job each, on the Task 2 code before a one-line copy refactor.
- Host: `.build/0806-t2.log`, full `swift test` passed on the final code. Nothing live ran on the host.

## Task Commits

1. **Task 1: Tracer, a dim click-through tile at its rect** - `a984e50` (feat). The tracer gate re-ran its verify after the commit and passed.
2. **Task 2: Stage, overview, Debug line, audit** - `a365bd8` (test), `38b3c8c` (feat)

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

See `key-decisions` above. VIEW-04 is marked complete, as the orchestrator allowed; VIEW-03 and VIEW-05 stay open for 08-07.

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

**4. [Rule 3 - Blocking] The VM test's click proof changed**
- **Found during:** Task 1
- **Issue:** the truth says a click reaches Finder, but a probe in the guest with no panel and no Transom showed a posted click on the bare desktop leaves the frontmost app unchanged, so Finder cannot be the witness there.
- **Fix:** a fixture window is sent behind the panel, and a click through the panel must make it frontmost. That is a stronger proof of click-through. The Finder wording stays a UAT item (coverage D7).
- **Files modified:** `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift`, `Sources/TransomFixtureApp/main.swift`
- **Committed in:** `a984e50`

---

**Total deviations:** 4 auto-fixed (1 bug, 1 missing critical, 2 blocking)
**Impact on plan:** all needed for the stated truths. No new features.

## Issues Encountered

- The first VM click landed 6 pt beside a guest TextEdit window, inside its resize margin, and did nothing. The test now needs 16 pt of clearance. It picks the first such point in tile 0; if the guest's windows ever cover that tile, the test fails with an explicit message.
- A stray file from a mistyped `rsync` destination landed in the repo root. It was never staged, and was removed.

## Known Stubs

None. One `shortcut:` in `Arranger.homePlaceholders`: a waiting window whose learned minimum no longer fits gets no tile in the overview or a zoomed plan until it expires. Its tile stays reserved; only the drawing is missing, in that edge case.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 08-07 UAT should look at a placeholder by eye (coverage D6), click one over the real desktop, switch Spaces with one shown (D7), and ⌘Q a real app (08-04's D4).
- The VM is stopped.

---
*Phase: 08-saved-views-urls-persistence*
*Completed: 2026-11-04*

## Self-Check: PASSED
