---
phase: 04-zoom-camera
plan: 07
subsystem: zoom
status: complete
tags: [engine, collapse, panels, core-animation, accessibility, swift-testing]
requires:
  - phase: 04-02
    provides: "ViewPlanner collapse pass (ViewPlan.collapsed), CameraState.collapsible, TileMove, planShown save-before-park"
  - phase: 04-04
    provides: "ZoomController (tiles, reveal, onRevealed), TileLayer, AppColor"
  - phase: 04-06
    provides: "ZoomInput pick mode and zoom(toLeafOf:), PreviewStyle recipes, ArrangeController.zoom(to:displayUUID:focus:)"
provides:
  - "Zoom-on acceptance of unfit drops, keyboard Dock and Move Window (D-A, CONTEXT E); every other refusal unchanged"
  - "ArrangerEffect.collapsedBlocks([CollapsedBlock], displayUUID:), sent per display only on change (CameraState.shownBlocks)"
  - "Arranger.minimums floors collapsible windows to 1x1; Arranger.learnedMinimums feeds ViewPlanner"
  - "TileMove.Kind.collapsed (a block in the end view)"
  - "PreviewState.collapsed(Rect, label:) and CollapseCopy (labels, announcements)"
  - "CollapsedPanels / CollapsedBlockView: pooled never-key block panels, hover ring, double-click and VoiceOver press zoom in"
  - "TileLayer.Content.collapsed; ZoomController collapsed tiles, settle-log and reveal collapsed counts"
affects: [04-08]
tech-stack:
  added: []
  patterns:
    - "Collapsible windows plan at 1x1 in every Phase 3 plan and dry run, so one set membership keeps them out of `unfit` everywhere; ViewPlanner alone sees real minimums to decide who is collapsed"
    - "Collapsed-block panels hide per display on .cameraMove and fade in on that display's reveal"
key-files:
  created:
    - Sources/TransomMac/Zoom/CollapsedPanels.swift
    - Tests/TransomEngineTests/ArrangerCollapseTests.swift
  modified:
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/Arranger+Commands.swift
    - Sources/TransomEngine/DragSession.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Zoom/ZoomInput.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Zoom/TileLayer.swift
    - Sources/TransomMac/Overlay/PreviewStyle.swift
    - Sources/TransomMac/Overlay/PreviewPanel.swift
    - Tests/TransomMacTests/PreviewStyleTests.swift
key-decisions:
  - "Collapsible windows get a 1x1 minimum in `minimums` (every Planner.plan site), and ViewPlanner gets `learnedMinimums`. Without this, one collapsed window would make every later dry run unfit, so grow, rotate, Arrange All and every drop would refuse or collapse"
  - "The collapsible set is never pruned while zoom is on: only closing the window or turning zoom off removes an entry. A window that later gets room again simply keeps its frame"
  - "TileMove.Kind.collapsed means a block in the END view. A window collapsed only at the start keeps stay/leaving, with its start rect at the block. This keeps the reveal counts and pick tiles exact"
  - "Pick mode takes a collapsed block's click in ZoomInput.pointerDown (from the tap), not in the panel. The tap's pass-through press would otherwise end pick mode before the panel's mouseDown arrived"
  - "ZOOM-13 is not marked complete here: live UAT of the blocks has not run, and 04-08 owns the quit/crash rescue of camera-parked docked windows (T-04-24)"
requirements-completed: []
estimate:
  tokens: 100000
  tasks: 3
actuals:
  tokens: 16369
  tasks: 3
  commits: 6
plan_head_before: 62876a2aa72277a4d3a919049ca021e7b8a00f89
plan_head_after: 305782b5ed4d3e48e9d173ef5e9d9ba7df31422c
duration: 13 min
completed: 2026-10-28
coverage:
  - id: D1
    description: "With zoom on, an unfit drop is accepted and the window becomes a collapsed block (parked after an immediate save); with zoom off Phase 3 refuses"
    requirement: "ZOOM-13"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCollapseTests.swift#anOversizedDropIsAcceptedWithZoomOn"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCollapseTests.swift#theSameDropIsRefusedWithZoomOff"
        status: pass
    human_judgment: false
  - id: D2
    description: "Collapsed preview labels and announcements; keyboard Dock and Move Window collapse; grow, shrink, rotate, flip, balance, Arrange All and the shift bypass still refuse"
    requirement: "ZOOM-13"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCollapseTests.swift#ArrangerCollapseTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Turning zoom off floats collapsed windows with N1; a relaunch floats them (set never saved)"
    requirement: "ZOOM-13"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCollapseTests.swift#turningZoomOffFloatsCollapsedWindowsWithTheLostRoomNotice"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCollapseTests.swift#aRelaunchFloatsAFormerlyCollapsedWindow"
        status: pass
    human_judgment: false
  - id: D4
    description: "Collapsed preview style (Dock colours, glyph, label, Increase Contrast), label clearance, block VoiceOver label and help"
    requirement: "ZOOM-13"
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/PreviewStyleTests.swift#CollapsedLookTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Block panels at rest: look, hover ring and pointing hand, double-click zooms in and focuses, beep while paused, hidden during moves and faded in at reveal, stage block tiles, VoiceOver press"
    requirement: "ZOOM-13"
    verification:
      - kind: manual_procedural
        ref: "VM UAT (pane-test): zoom on, drop a window into a too-small tile, inspect the block, double-click it, VoiceOver press, zoom out/in"
        status: unknown
    human_judgment: true
---

# Phase 4 Plan 07: Collapsed App-Colour Blocks Summary

**With zoom on, a drop, keyboard Dock or Move Window that does not fit is now accepted. The windows that lose room become collapsed app-colour blocks in their tiles: pooled click-taking panels at rest, block tiles on the stage during moves. Double-clicking a block (or pressing it with VoiceOver) zooms in to it. Zoom off keeps Phase 3's refusal exactly.**

## Performance

- Duration: about 13 min (15:56Z to 16:09Z)
- Tasks: 3 of 3. Task 1 was a tracer; its gate re-ran the automated verify (43 tests, 5 suites) before expanding.
- Files: 13 (2 created, 11 modified)

## Task Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | b4dd082 | test(04-07): add failing collapse acceptance tests |
| 1 GREEN | 859a2a9 | feat(04-07): accept oversized drops with zoom on as collapsed blocks |
| 2 RED | 56f9157 | test(04-07): add failing Collapsed preview, keyboard collapse and CONTEXT E refusal tests |
| 2 GREEN | 2da33b3 | feat(04-07): Collapsed drop preview, keyboard Dock/Move collapse and announcements |
| 3 RED | d678e49 | test(04-07): add failing Collapsed preview style and block label tests |
| 3 GREEN | 305782b | feat(04-07): collapsed stage tiles, reveal counts and block accessibility |

## TDD

- **Task 1:** RED `b4dd082`: ArrangerCollapseTests failed to compile (`cannot find type 'CollapsedBlock'`). GREEN `859a2a9`: 43 tests in 5 suites passed (ArrangerCollapseTests, ArrangerDragTests, TooBigDockedWindowTests, ArrangerCameraTests and RefusalRetryBoundTests).
- **Task 2:** RED `56f9157`: failed to compile (no `PreviewState.collapsed`, no `CollapseCopy`). GREEN `2da33b3`: 54 engine tests in 3 suites and 8 PreviewStyleTests passed. Two of my new tests were corrected before GREEN (see Deviations 5).
- **Task 3:** RED `d678e49`: failed to compile (no `CollapsedBlockView.label` / `.help`). The Collapsed style expectations in the same suite would already have passed, because Task 2 added the mapping; they pin it. GREEN `305782b`: the full suite passes.
- Expectation guard: `git diff b4dd082^ -- Tests/ | grep -c '^-.*#expect'` printed 0.

## Verification

- Task 1 gate: `swift test --filter "ArrangerCollapseTests|ArrangerDragTests|TooBigDockedWindowTests|ArrangerCameraTests"`: 43 tests passed, no ✘.
- Task 2 gate: `swift test --filter "ArrangerCollapseTests|ArrangerCommandTests|ArrangerDragTests|PreviewStyleTests"`: 54 + 8 tests passed, no ✘.
- Full headless `swift test`: 193 + 260 + 46 + 646 = 1145 Swift Testing tests passed across 4 bundles, no ✘. The XCTest lines report 0 executed, as before. The known FreezeTestTests flake did not fire this run.
- `scripts/check-no-appkit.sh`: OK (44 files). ScreenCaptureKit is still imported only in SnapshotCapture.swift.
- Acceptance greps:
  - `collapsedBlocks` in Arranger.swift (non-comment): 2
  - `sharingType = .none` and `clickCount` in CollapsedPanels.swift: 1 each
  - `case collapsed` and `Collapsed until you zoom in` in DragSession.swift: 1 each
  - `collapsible` in Arranger+Commands.swift (non-comment): 3
  - `accessibilityPerformPress` and `Double-click to zoom in` in CollapsedPanels.swift: 1 each
  - `arrow.down.right.and.arrow.up.left` in PreviewPanel.swift: 0. It is 1 in PreviewStyle.swift (see Deviations 4).
- Headless only. No live or VM run in this plan.

## Deviations from Plan

### Auto-fixed / adjusted

**1. [Rule 1 - Bug] Collapsible windows plan at 1x1 everywhere (`minimums`), with real minimums only for ViewPlanner (`learnedMinimums`)**
- **Found during:** Task 1 design
- **Issue:** About 25 Planner.plan sites (dry runs for grow/shrink/rotate, keyboard Dock, drops, Arrange All, snap, drag hit tests, lost-room floats) use real minimums. A collapsed window is unfit at its real minimum by definition. So once anything was collapsed, every later command would refuse with "Not enough room", and every drop would collapse.
- **Fix:** `minimums` gives a collapsible window 1x1, so it is never unfit at home. `learnedMinimums` keeps the real values; ViewPlanner gets those (zoomTo, planShown, collapse) to decide which windows are collapsed. With zoom off the set is empty, so every Phase 3 plan is unchanged; the full suite confirms it.
- **Files:** Arranger.swift, Arranger+Camera.swift. **Commit:** 859a2a9

**2. [Design] planShown plans every zoom-on view with ViewPlanner, home included, instead of switching `planFloatingLostRoom` to ViewPlanner**
- `planFloatingLostRoom` already skips collapsible windows through the 1x1 floor, so OS-caused lost room still floats (CONTEXT E). planShown then takes frames, parks, resolution and collapsed rects from `ViewPlanner.plan(view, collapsible:)`. With an empty set this equals the previous home plan field for field (04-02's guarantee).
- **Commit:** 859a2a9

**3. [Precision] `TileMove.Kind.collapsed` means "a block in the end view"**
- A window collapsed only at the start of a move keeps `.stay` / `.leaving`, and its start rect is its block rect (never its parked frame). It is drawn as a snapshot or fallback tile, which looks close to a block (app colour and icon).
- Why: the reveal announcement ("…, k collapsed"), the settle log's collapsed count, the refresh captures and pick-mode tiles all need to know what the end view shows. One kind cannot carry both "start" and "end" without a second field.
- **Commit:** 859a2a9, 305782b

**4. [Pattern] The Collapsed glyph name lives in PreviewStyle.swift, not PreviewPanel.swift**
- PreviewStyle already names every preview glyph (swap, blocked) and is the unit-tested recipe. PreviewPanel's existing label view draws any glyph with `NSImage.SymbolConfiguration(textStyle: .headline)` and the role's colour (`labelColor` here).
- The plan's grep on PreviewPanel.swift therefore prints 0. The behaviour (glyph, colour, headline sizing, clearance rule) is as specified and pinned by `CollapsedLookTests`.
- **Commit:** 2da33b3

**5. [Test precision] Corrections to my own new tests before GREEN**
- The ⇧-bypass test now sends the drag-frame samples, as ArrangerDragTests does.
- The relaunch test checks that the window floats and the set is empty. The re-attach float is silent: no `lostRoom` notice is emitted at the first inventory.
- A nested `#require` and a throwing call inside `#expect` were split into separate statements.
- No pre-existing expectation was touched.

**6. [Rule 1 - Race] Pick mode takes a collapsed block's click in `ZoomInput.pointerDown`**
- The tap cannot match a parked window as topmost, so it passes the press through and `pointerDown` used to end pick mode. The panel's own mouseDown can arrive after that, so a panel-side pick would race.
- Instead, `Pick.blocks` holds the block rects, and the passing press that lands on one zooms to it. The panel's single click does nothing. The block's own hover ring stands in for the pick ring.
- **Commit:** 859a2a9

**7. [API shape] `CollapsedPanels.hide(on:)` / `fadeIn(on:)` per display instead of `hideAll()` / `fadeIn()`**
- A move on one display does not hide another display's blocks. An empty `show` clears the hidden mark, so a move that never reveals cannot keep blocks out forever.

**8. [Addition] `setZoomEnabled(false)` appends `showBlocks([:])` after its replan**
- If arranging is paused when zoom turns off, planShown returns nothing; the extra call still hides every block.

## Known Stubs

None. The 04-04 `shortcut:` comments (collapsed count hard-coded to 0 in the settle log and reveal announcement) are replaced with real counts. The 04-06 stub (collapsed blocks not pickable, WINDOWS.md entry 4) is resolved and marked fixed in the ledger.

## Threat Flags

None beyond the plan's register:
- T-04-24: save before park goes through planShown; turning zoom off floats collapsed windows with N1; the set is session-only. Quit and crash rescue of camera-parked docked windows remain 04-08's.
- T-04-25: panels are never key, non-activating, cover exactly the block rect and are ordered out during moves.
- T-04-26: zoom-off refusals are pinned by `theSameDropIsRefusedWithZoomOff`, the keyboard zoom-off checks and the unchanged suite.

## Not checked (UAT backlog, VM only)

- Panel look and hover ring, the pointing-hand cursor while Transom is inactive (`.cursorUpdate` with `.activeAlways` may not fire, as noted in 04-06 for gap handles; mouseEntered also sets it), the 120 ms fade-in at reveal.
- Double-click zoom and focus, the paused beep and announcement, and the VoiceOver label and press.
- The stage's collapsed tiles during a move; a pick-mode click on a block.
- A focus command on a collapsed (parked) window at home is not widened or revealed. That is unchanged behaviour, not covered by this plan.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Zoom/CollapsedPanels.swift, Tests/TransomEngineTests/ArrangerCollapseTests.swift, this SUMMARY.
- FOUND commits on HEAD: b4dd082, 859a2a9, 56f9157, 2da33b3, d678e49, 305782b.
- Measured: `git rev-list --count 62876a2..HEAD` = 6 before this SUMMARY's commit.
