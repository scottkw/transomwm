---
phase: 07-tab-groups
plan: 11
subsystem: zoom-stage
tags: [swift, tab-groups, zoom, overview, core-animation, accessibility, screencapturekit]

requires:
  - phase: 07-tab-groups
    plan: 10
    provides: tab group safety paths
  - phase: 07-tab-groups
    plan: 04
    provides: isHiddenTab, overview hidden-tab filter
  - phase: 07-tab-groups
    plan: 02
    provides: PendingReveal and revealed(_:actual:now:)
provides:
  - StripMove and CameraMove.strips (one per group whose selected member has a non-collapsed tile)
  - Hidden tabs excluded from every TileMove (never drawn or captured on the stage)
  - StripLayerStyle.layout(frame:scale:count:) and StripLayerStyle.image(size:icons:selected:)
  - TileLayer.Content.strip and StageTile.stripID(_:)
  - TabStripPanels.hide(on:) / fadeIn(on:) driven with the collapsed-block panels
  - CollapsedBlock.groupSize; TabCopy.collapsedGroupLabel(count:app:title:), TabCopy.overviewTabSuffix(index:count:)
  - Arranger.tabGroupMembers(holding:)
  - ArrangerEffect.tabRevealed(WindowRef) and ZoomController.captureRevealed(_:)
affects: [07-12]

estimate:
  tokens: 120000
actuals:
  tokens: 11200
  tasks: 3
  commits: 3
plan_head_before: 456cc289b560fe4972bc99fda2883b3eae7c47d8
plan_head_after: 5fc7eb981b1a60ca908a723b640f057dc59476f4

tech-stack:
  added: []
  patterns:
    - "A group's strip is a StageTile of its own (content .strip, ID = selected tile's ID with the top bit flipped), so every stage path (move, crossfade, retarget, follow, spring back, overview reverse) animates it with no new code"
    - "The strip is drawn once as an image at its end size and stretched (contentsGravity .resize) while its bounds animate"
    - "hidePanels/showPanels in ArrangeController pair the collapsed-block and tab strip panels everywhere a stage orders in or goes"

key-files:
  created:
    - Tests/TransomMacTests/OverviewTabInputsTests.swift
  modified:
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overlay/TabStripPanels.swift
    - Sources/TransomMac/Overview/OverviewController.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Sources/TransomMac/Zoom/CollapsedPanels.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/TileLayer.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift
    - Tests/TransomMacTests/TileLayerTests.swift

key-decisions:
  - "StripMove.start/end are strip rects (the group frame's top band, 28 pt × the view's scale), not whole group frames: the shell cannot recover the scale from a group frame, and a mapped (leaving/entering) strip is the home strip mapped like its tile"
  - "A collapsed group gets no StripMove: it is one collapsed block (UI-SPEC Surface 6)"
  - "Strips are stage tiles with a derived ID rather than a second layer set in StagePanel; a click on a strip matches no window and does nothing"
  - "Strip panels hide whenever a stage is up (camera move, gesture follow, overview) and fade back with the collapsed-block panels; zoom off fades both back in case a stage was purged before its reveal"
  - "The overview looks up a selected tile's content by tile ID instead of by index, so strip tiles in the same list cannot shift it"
  - "captureRevealed uses the existing post-reveal refresh path (re-read shareable content, capture into the cache only) at the window's frame × backing scale"

patterns-established:
  - "Overview group strip: Rect(x: tile.x, y: tile.y - 32 × scale, width: tile.width, height: 28 × scale), the same affine map as the tile"

requirements-completed: [TABS-01, TABS-05]

coverage:
  - id: S1
    description: "A camera move over a docked group has one TileMove (selected member) and one StripMove; no TileMove names the hidden member"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabStageTests"
        status: pass
    human_judgment: false
  - id: S2
    description: "StripLayerStyle: radius 8 at scale 1 with three equal chips and icons; radius floors at 2 and icons hide at 0.25; fill only below 4 pt"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/TileLayerTests.swift#StripLayerStyleTests"
        status: pass
    human_judgment: false
  - id: S3
    description: "A collapsed docked group is one CollapsedBlock for its selected member with groupSize = member count; its label and the overview suffix match the copy"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabCollapsedBlockTests; Tests/TransomMacTests/TabCopyTests.swift#TabStageCopyTests"
        status: pass
    human_judgment: false
  - id: S4
    description: "The overview's inputs leave out a docked group's hidden member, so the group counts once (07-04 gap)"
    requirement: TABS-05
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/OverviewTabInputsTests.swift"
        status: pass
    human_judgment: false
  - id: S5
    description: "A matched reveal emits .tabRevealed once; a timed-out reveal emits none"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabRevealedTests"
        status: pass
    human_judgment: false
  - id: S6
    description: "Stage and overview visuals: strip drawn above the group's tile, real strip out during the move and back with a 120 ms fade, overview strip, collapsed group VoiceOver label"
    requirement: TABS-01
    verification:
      - kind: manual
        ref: "07-12 UAT (VM)"
        status: pending
    human_judgment: true
    rationale: "Core Animation and panel ordering need a live display; the plan defers visuals to 07-12"

duration: 15min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 11: Groups on the Zoom Stage and in the Overview Summary

**With zoom on, a tab group now looks like a group during camera moves and in the overview: its selected window's tile with an icon-only strip above it. Hidden tabs never get a tile, so they are never drawn or captured. The real strip panels step aside while a stage is up and fade back at reveal. A collapsed group reads "Tab group, {n} windows, collapsed: ...". The overview counts a group once and says "tab {i} of {n}". A newly selected tab is captured in the background so the next move shows it.**

## Performance

- **Duration:** about 15 min
- **Completed:** 2026-11-02T03:28Z
- **Tasks:** 3
- **Files modified:** 15 (357 insertions, 32 deletions)

## Accomplishments

- **Engine (Surface 6):** `planTiles` skips every hidden tab, then builds one `StripMove` per non-collapsed tile whose window is a group's selected member. A docked group's strip comes from its leaf's rect in each view's resolution. A floating group's strip comes from its content rect plus the band. Leaving and entering strips are the home strip mapped like their tile. `zoomTo`, `previewMove` and `stillMove` all carry the strips, so a gesture preview matches the committed move.
- **Stage:** `ZoomController.tiles(for:)` adds one `StageTile` per strip after the window tiles, so each strip draws on top. `TileLayer.Content.strip` renders `StripLayerStyle.image` once at the end size and stretches it while the bounds animate. Colours resolve in the stage's appearance and are redrawn on an appearance change. Snapshot capture still reads only `move.tiles`, so strips are never captured.
- **Panels:** `TabStripPanels.hide(on:)` / `fadeIn(on:)` use the same rules as `CollapsedPanels`. While a display is hidden, strips that arrive are placed but not ordered in, and `spaceChanged` does not fade them in. ArrangeController's `hidePanels` / `showPanels` replace the collapsed-panel-only calls for camera moves, gesture follows and the overview.
- **Collapsed group:** `CollapsedBlock.groupSize` is set from the leaf (1 for a plain window). `CollapsedBlockView` uses `TabCopy.collapsedGroupLabel` when it is above 1.
- **Overview:** main-area group tiles get a strip tile, mapped from the real strip to 28 pt × the display scale above the tile. Collapsed groups get none, and mini tiles stay selected-only. Live updates add and remove strips with their tiles. The selection announcement adds `TabCopy.overviewTabSuffix`. `tileCount(display:)` counts window tiles only.
- **Snapshots:** `revealed(...)` emits `.tabRevealed(window)`. With zoom on, ArrangeController calls `ZoomController.captureRevealed`, which returns without Screen Recording. Otherwise it refreshes that one window into the cache in the background.

## Task Commits

1. **Task 1 (tracer): StripMove → stage strip → real strip hidden and back at reveal** - `c5c8a71` (feat)
2. **Task 2: Collapsed group label, overview group tiles, counts and announcement** - `c315e0d` (feat)
3. **Task 3: Background capture of a newly selected tab; full suite** - `5fc7eb9` (feat)

## Verification

- Task 1: `swift test --filter 'ArrangerTabsTests|ArrangerCameraTests|TileLayerTests|StageFollowTests|StripLayerStyleTests|ArrangerTabStageTests'` ran 8 + 159 tests, all passing with no "✘". `swift build` passed. That passing `<verify>` run was also the tracer gate.
- Task 2: `swift test --filter 'ArrangerTabsTests|TabCopyTests|OverviewCopyTests|OverviewLayoutTests|ArrangerTabCollapsedBlockTests|TabStageCopyTests|OverviewTabInputsTests|ArrangerCollapseTests'` ran 24 + 167 tests, all passing. All four new tests appear in the log.
- Task 3: the full `swift test` passed (219, 390, 93 and 952 tests, no "✘"). Both new reveal tests passed. `scripts/check-no-appkit.sh` passed (55 files).
- Every acceptance grep returns its expected count.
- No live code ran on the host, and no VM run was planned. Visuals are checked in 07-12.

## Deviations from Plan

**1. [Interpretation] StripMove carries strip rects, not group frames**
- The plan's interface says `start`/`end` are group frames. The shell would then have no way to know the strip height (28 pt × scale) of a mapped frame, so the engine sends `TabBand.strip(of:)` of the group frame, mapped like the tile. The test checks `strip.start == TabBand.strip(of: frame)`.

**2. [Simplification] No separate StripLayer class**
- The strip is a `TileLayer` with `.strip` content, drawn by `StripLayerStyle.image`. Making it a stage tile means the move, crossfade, retarget, follow, spring back and overview reverse paths all handle it without changes. `StripLayerStyle.layout` drops the plan's `selected` parameter because the layout doesn't depend on it; the image takes `selected`.

**3. [Rule 2 - Missing critical functionality] Strip panels must come back on every stage end**
- The plan named only the `.cameraMove` arm. The overview and gesture follows also hide the collapsed panels, and their stages also cover the strips. All of these paths now go through `hidePanels` / `showPanels`. Zoom off fades both panel kinds back in, so a stage purged before its reveal cannot leave strips hidden for good. `show(_:on:space:)` with no strips clears the hidden flag, as `CollapsedPanels` does.
- **Commit:** c5c8a71

**4. [Rule 1 - Bug] Overview selection content was looked up by index**
- `markSelection` read `shown[uuid][index]`, which assumed `shown` was in layout order. Strip tiles in the same list, plus live updates, would break that. It now looks up by tile ID.
- **Commit:** c315e0d

**5. [Scope] 07-04's overview hidden-member filter now has a unit test**
- The orchestrator asked for this. `OverviewController.inputs` runs headless with no Spaces snapshot and no CG list.

## Known Stubs

None.

## Threat Flags

None. T-07-24 is mitigated: hidden members never get a TileMove (pinned by a test), strips are never capture requests, captures stay in the in-memory cache, and stage and strip panels keep `sharingType = .none`.

## Notes for 07-12

- A click on a stage strip does nothing (its ID matches no window). In the overview, a click on a group's strip lands outside the tile's hit rect and counts as a backdrop click, so it dismisses.
- `StageTile.stripID` flips the top bit (a `shortcut:` comment marks it). A real CG window ID of 0x7000_0000 or more could collide with a synthetic tile's strip ID. CG IDs are small in practice.
- If a reveal happens after a Space change while the stage is up, it can briefly fade in strips from the previous Space, until the replan's strips replace them.

## Self-Check: PASSED
