---
phase: 03-tiling-mvp
verified: 2026-10-26T15:30:00Z
status: gaps_found
score: 5/7 must-haves verified
covered_files: [".planning/phases/03-tiling-mvp/03-01-PLAN.md",".planning/phases/03-tiling-mvp/03-01-SUMMARY.md",".planning/phases/03-tiling-mvp/03-02-PLAN.md",".planning/phases/03-tiling-mvp/03-02-SUMMARY.md",".planning/phases/03-tiling-mvp/03-03-PLAN.md",".planning/phases/03-tiling-mvp/03-03-SUMMARY.md",".planning/phases/03-tiling-mvp/03-04-PLAN.md",".planning/phases/03-tiling-mvp/03-04-SUMMARY.md",".planning/phases/03-tiling-mvp/03-05-PLAN.md",".planning/phases/03-tiling-mvp/03-05-SUMMARY.md",".planning/phases/03-tiling-mvp/03-06-PLAN.md",".planning/phases/03-tiling-mvp/03-06-SUMMARY.md",".planning/phases/03-tiling-mvp/03-07-PLAN.md",".planning/phases/03-tiling-mvp/03-07-SUMMARY.md",".planning/phases/03-tiling-mvp/03-08-PLAN.md",".planning/phases/03-tiling-mvp/03-08-SUMMARY.md",".planning/phases/03-tiling-mvp/03-09-PLAN.md",".planning/phases/03-tiling-mvp/03-09-SUMMARY.md",".planning/phases/03-tiling-mvp/03-10-PLAN.md",".planning/phases/03-tiling-mvp/03-10-SUMMARY.md",".planning/phases/03-tiling-mvp/03-11-PLAN.md",".planning/phases/03-tiling-mvp/03-11-SUMMARY.md",".planning/phases/03-tiling-mvp/03-12-PLAN.md",".planning/phases/03-tiling-mvp/03-12-SUMMARY.md",".planning/phases/03-tiling-mvp/03-13-PLAN.md",".planning/phases/03-tiling-mvp/03-13-SUMMARY.md",".planning/phases/03-tiling-mvp/03-14-PLAN.md",".planning/phases/03-tiling-mvp/03-14-SUMMARY.md",".planning/phases/03-tiling-mvp/03-15-PLAN.md",".planning/phases/03-tiling-mvp/03-15-SUMMARY.md",".planning/phases/03-tiling-mvp/03-16-PLAN.md",".planning/phases/03-tiling-mvp/03-16-SUMMARY.md",".planning/phases/03-tiling-mvp/03-17-PLAN.md",".planning/phases/03-tiling-mvp/03-17-SUMMARY.md","Package.resolved","Package.swift","Sources/PaneEngine/Arranger+Commands.swift","Sources/PaneEngine/Arranger.swift","Sources/PaneEngine/Command.swift","Sources/PaneEngine/ConflictPolicy.swift","Sources/PaneEngine/DragSession.swift","Sources/PaneEngine/GapHandles.swift","Sources/PaneEngine/LayoutFile.swift","Sources/PaneEngine/LayoutRestore.swift","Sources/PaneEngine/LifecycleSync.swift","Sources/PaneEngine/Notice.swift","Sources/PaneEngine/PaneURL.swift","Sources/PaneEngine/PermissionReducer.swift","Sources/PaneEngine/Planner.swift","Sources/PaneEngine/Recovery.swift","Sources/PaneEngine/WindowSnapshot.swift","Sources/PaneEngine/WindowSystem.swift","Sources/PaneEngine/WindowTracker.swift","Sources/PaneFixtureApp/main.swift","Sources/PaneMac/AX/AXAppThread.swift","Sources/PaneMac/AX/AXSnapshotReader.swift","Sources/PaneMac/AX/MenuPress.swift","Sources/PaneMac/AXWindowSystem.swift","Sources/PaneMac/AppDelegate.swift","Sources/PaneMac/ArrangeController.swift","Sources/PaneMac/CGWindowList.swift","Sources/PaneMac/ConflictController.swift","Sources/PaneMac/Displays.swift","Sources/PaneMac/GapPreference.swift","Sources/PaneMac/Input/DragFramePoller.swift","Sources/PaneMac/Input/GreenButton.swift","Sources/PaneMac/Input/Hotkeys.swift","Sources/PaneMac/Input/InputTap.swift","Sources/PaneMac/LayoutStore.swift","Sources/PaneMac/Overlay/GapHandlePanels.swift","Sources/PaneMac/Overlay/NoticeQueue.swift","Sources/PaneMac/Overlay/PreviewPanel.swift","Sources/PaneMac/Overlay/PreviewStyle.swift","Sources/PaneMac/Overlay/Toast.swift","Sources/PaneMac/PaneMacApp.swift","Sources/PaneMac/Shell/CommandMenu.swift","Sources/PaneMac/Shell/ConflictCopy.swift","Sources/PaneMac/Shell/MenuCopy.swift","Sources/PaneMac/Shell/NoticeCopy.swift","Sources/PaneMac/Shell/StatusItemController.swift","Sources/PaneMac/WindowManagerSettings.swift","Sources/PaneModel/DesktopLayer.swift","Sources/PaneModel/IDs.swift","Sources/PaneModel/LayoutTree.swift","Sources/PaneModel/Neighbours.swift","Sources/PaneModel/Resolve.swift","Sources/PaneModel/Snap.swift","Sources/PaneModel/TreeEdits.swift","Sources/PaneModel/Undo.swift","Sources/PaneModel/World.swift","Sources/PanePrivate/SkyLightSpaces.swift","Sources/PaneTestSupport/FakeWindowSystem.swift","Tests/PaneEngineTests/ArrangerCommandTests.swift","Tests/PaneEngineTests/ArrangerDesktopTests.swift","Tests/PaneEngineTests/ArrangerDragTests.swift","Tests/PaneEngineTests/ArrangerExclusionTests.swift","Tests/PaneEngineTests/ArrangerFinderTests.swift","Tests/PaneEngineTests/ArrangerFocusTests.swift","Tests/PaneEngineTests/ArrangerGreenButtonTests.swift","Tests/PaneEngineTests/ArrangerLifecycleTests.swift","Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift","Tests/PaneEngineTests/ArrangerPauseTests.swift","Tests/PaneEngineTests/ArrangerReflowTests.swift","Tests/PaneEngineTests/ArrangerResizeTests.swift","Tests/PaneEngineTests/ArrangerRestoreTests.swift","Tests/PaneEngineTests/ArrangerSpacesTests.swift","Tests/PaneEngineTests/CommandTests.swift","Tests/PaneEngineTests/ConflictPolicyTests.swift","Tests/PaneEngineTests/DragSessionTests.swift","Tests/PaneEngineTests/GapHandleGeometryTests.swift","Tests/PaneEngineTests/LifecycleSyncTests.swift","Tests/PaneEngineTests/PaneURLTests.swift","Tests/PaneEngineTests/PermissionReducerTests.swift","Tests/PaneEngineTests/PlannerTests.swift","Tests/PaneEngineTests/RecoveryTests.swift","Tests/PaneEngineTests/TrackerDisplayTests.swift","Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift","Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift","Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift","Tests/PaneMacIntegrationTests/InputTapIntegrationTests.swift","Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift","Tests/PaneMacIntegrationTests/QuitRestoreIntegrationTests.swift","Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift","Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift","Tests/PaneMacIntegrationTests/TitleBarDragIntegrationTests.swift","Tests/PaneMacTests/AppDelegateTests.swift","Tests/PaneMacTests/CapabilitiesTests.swift","Tests/PaneMacTests/CommandMenuTests.swift","Tests/PaneMacTests/ConflictControllerTests.swift","Tests/PaneMacTests/ConflictCopyTests.swift","Tests/PaneMacTests/GapPreferenceTests.swift","Tests/PaneMacTests/GreenButtonHitTests.swift","Tests/PaneMacTests/HotkeyTableTests.swift","Tests/PaneMacTests/LayoutStoreTests.swift","Tests/PaneMacTests/MenuCopyTests.swift","Tests/PaneMacTests/MenuPressTests.swift","Tests/PaneMacTests/NoScreenCaptureTests.swift","Tests/PaneMacTests/NoticeCopyTests.swift","Tests/PaneMacTests/NoticeQueueTests.swift","Tests/PaneMacTests/PreviewStyleTests.swift","Tests/PaneMacTests/WakeTimerTests.swift","Tests/PaneMacTests/WindowManagerSettingsTests.swift","Tests/PaneModelTests/DesktopLayerTests.swift","Tests/PaneModelTests/DesktopLeafTests.swift","Tests/PaneModelTests/LayoutEditTests.swift","Tests/PaneModelTests/LifecycleTests.swift","Tests/PaneModelTests/NeighbourTests.swift","Tests/PaneModelTests/PersistenceTests.swift","Tests/PaneModelTests/ResolveFuzzTests.swift","Tests/PaneModelTests/ResolveTests.swift","Tests/PaneModelTests/ScenarioTests.swift","Tests/PaneModelTests/SkeletonTests.swift","Tests/PaneModelTests/SnapTests.swift","Tests/PaneModelTests/TabsTests.swift","Tests/PaneModelTests/TreeEditTests.swift","Tests/PaneModelTests/UndoTests.swift","Tests/PaneModelTests/WorldRekeyTests.swift","scripts/release.sh","xcode/Pane-Info.plist","xcode/project.yml"]
covered_digest: "v3:sha256:387845a1f8f16388bd464a6a7770cdd2d6a0924484d96cd6aa06c9ee332917e0"
behavior_unverified: 1
overrides_applied: 0
gaps:
  - truth: "SC1 / TILE-01: Dragging a window by its title bar to a screen edge or another window's edge shows a drop preview and docks it there on release"
    status: partial
    reason: "Observed live on the 0.3.0 build in the Tart VM (deferred-items 03-17): Safari windows dragged by their unified-toolbar title area never dock and stay floating, with no preview. TextEdit docks correctly. Review WR-03 gives a probable cause (drag classification needs leftMouseDragged travel and AX/CG size agreement) but it was skipped pending a live log, so the code is unchanged at HEAD 81c5fd3. Safari is a mainstream app, so drag-to-dock, the Core Value, does not work for it. Dock from the keyboard (Ctrl-Opt-Cmd-D) and the green button are a workaround, not a fix."
    artifacts:
      - path: "Sources/PaneEngine/Arranger.swift"
        issue: "Travel is counted only from session.pointer (leftMouseDragged/flagsChanged), and .up does not update the pointer (around :826-844)"
      - path: "Sources/PaneEngine/DragSession.swift"
        issue: "observe compares CG-bounds samples with an AX startFrame size within 1 pt, so differing chrome sizes classify a move as .resize (around :124-139)"
      - path: "Sources/PaneMac/ArrangeController.swift"
        issue: "startFrame comes from AX, not from DragFramePoller.bounds(of:) (around :283-290)"
    missing:
      - "One live Safari drag log at release (session.kind, travelled, first sample against startFrame) to confirm which condition fails"
      - "A fix for the confirmed cause, e.g. take startFrame from CG bounds at mouse-down, count travel from window origin displacement, and set session.pointer on .up"
      - "A fake regression test where CG bounds differ from the AX frame and/or no leftMouseDragged arrives, and the window still docks"
      - "A live re-check: Safari docks by drag in the VM"
behavior_unverified_items:
  - truth: "SC5: the Developer ID build's Accessibility grant survives updates"
    test: "Install build N in /Applications and grant Accessibility. Quit, replace it with build N+1 (same bundle ID and Team ID, bumped CURRENT_PROJECT_VERSION), relaunch."
    expected: "Pane is still trusted (menu header shows window counts, not the Set Up prompt), and no new grant is needed"
    why_human: "The designated requirement is Team-ID based (verified: identifier com.eightabyte.pane plus leaf OU S2K7P43927), which should make TCC keep the grant, but no update over an existing install has been exercised"
human_verification:
  - test: "VM: Safari drag-dock diagnosis (the open gap). Stream Pane's log and drag a Safari window by its toolbar to the left edge and hold it."
    expected: "Preview after about 150 ms, then the window docks. If it does not, capture the session kind, travel, and first sample against the start frame for WR-03"
    why_human: "Needs a real Safari window and the WindowServer drag path"
  - test: "VM: grant Accessibility in System Settings directly (without the Set Up button) while Pane runs"
    expected: "Tracking starts without a relaunch (WR-02 fix)"
    why_human: "Real TCC transition; the fix has only a reducer test"
  - test: "VM: drag TextEdit windows: hold at an edge (preview), Shift-drag (free move), Cmd-release over another tile (swap), drop on a docked window's edge (nested split)"
    expected: "Preview matches the final frame; Shift never docks; Cmd swaps; nesting works 3+ levels deep"
    why_human: "Overlay appearance and live drag behaviour"
  - test: "VM: close a docked window; drag the gap between two tiles; change Gaps in the menu"
    expected: "Neighbours reflow; both sides resize; new gap applied at once and kept after relaunch"
    why_human: "Live AX writes and overlay handles"
  - test: "VM: green button on floating and docked windows; Opt-click green; minimise and restore a docked window; native fullscreen and exit on a docked window"
    expected: "Toggles dock/float; Opt-click zooms natively; minimised and fullscreen windows lend their tile and return to it (WIN-07, TILE-20)"
    why_human: "Real title-bar buttons and fullscreen Spaces (the live fullscreen test is opt-in and has not been run)"
  - test: "VM: keyboard pass: Ctrl-Opt-Cmd arrows, Shift-arrows, S, =, -, B, R, X on docked windows; 1/2/3, U/I/J/K, Return, C, Shift-arrows on a floating window"
    expected: "Focus, move, swap, grow/shrink, balance, rotate (its own inverse), flip, and every snap target behave as the UI-SPEC table says"
    why_human: "Global hotkey registration and live frames"
  - test: "VM: menu pass: Hide/Show Desktop Tile, Arrange All, Float All, Split with New Finder Window, Don't Arrange frontmost app, Pause/Resume, Undo (dock A, open B, undo: B stays floating and dockable, the CR-01 fix)"
    expected: "Each item acts on the frontmost window's desk; Pause moves nothing and ignores drags; Resume re-applies"
    why_human: "Live menu and AX behaviour"
  - test: "VM: open pane://toggle-desktop, pane://split-finder and pane://restore from Terminal"
    expected: "Each runs its command once; a malformed URL (e.g. pane://restore?x=1) does nothing"
    why_human: "LaunchServices URL routing in an installed bundle"
  - test: "VM: hide the Desktop (parks floating windows), then quit Pane from the menu"
    expected: "Every parked window returns to an on-screen frame (SAFE-01)"
    why_human: "Bounded quit-time AX writes on real apps"
  - test: "VM: hide the Desktop, kill -9 Pane, relaunch; then kill -9 again within 60 s and relaunch"
    expected: "First relaunch: stranded windows come on-screen, then the layout is re-applied with a crash notice. Second: starts paused with the crash-loop notice (SAFE-02)"
    why_human: "Real crash path and layout.json on disk"
  - test: "VM: dock three windows, quit Pane (apps keep running), relaunch"
    expected: "Same windows in the same tiles (SAFE-06)"
    why_human: "Window-ID re-attach against real windows"
  - test: "VM: turn on Stage Manager, then use Turn Off; turn on click-wallpaper-to-reveal, Turn Off; then Restore macOS Window Settings"
    expected: "Stage Manager pauses arranging with the reason in the menu; Turn Off takes effect; Restore puts back the original values (SAFE-04). Edge-tiling Turn Off was already confirmed live"
    why_human: "Real com.apple.WindowManager writes and read-back"
  - test: "VM: with Screen Recording never granted, do a full dock/float session and check System Settings, Screen Recording"
    expected: "No Screen Recording prompt ever appears and Pane is not listed; tiling works (TILE-10)"
    why_human: "TCC prompt behaviour"
  - test: "VM: update over an install (see behavior_unverified_items)"
    expected: "Accessibility grant kept"
    why_human: "TCC designated-requirement matching across builds"
  - test: "VM (Spaces) or host: dock windows on Space 1, switch to Space 2 and dock others, switch back"
    expected: "Each Space keeps its own layout; switching never moves the other Space's windows"
    why_human: "Real SkyLight Space lookup"
  - test: "Host, second display: Hide Desktop Tile on the left display"
    expected: "Parked windows do not appear on the right display or over its tiles (CR-02 fix)"
    why_human: "Needs two physical displays"
  - test: "Host, second display: dock windows on both displays (and two Spaces), quit and relaunch Pane"
    expected: "Each display and Space gets back its own layout (the real version of ArrangerMultiDeskRestoreTests)"
    why_human: "Needs two physical displays"
  - test: "Host, second display: rerun the live ArrangeIntegrationTests aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop under the live-test rules"
    expected: "Passes, or the failure is shown to be the test sizing minimums from the main display only (deferred-items 03-08)"
    why_human: "Live test that moves real windows; the user runs it at home"
---

# Phase 3: Tiling MVP Verification Report

**Phase Goal:** As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp (user story validated by `user-story.validate`: valid)
**Verified:** 2026-10-26T15:30:00Z
**Status:** gaps_found
**Re-verification:** No, initial verification

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| Drag a window by its title bar | A drag session starts, frames are polled, a 150 ms dwell shows the WYSIWYG preview | `InputTap` -> `ArrangeController` -> `Arranger` drag path -> `DropZones.target` (Arranger.swift:971) -> `.preview` effect -> `PreviewPanel`; `ArrangerDragTests` (17 tests) pass; TextEdit docked live in the VM | VERIFIED for TextEdit, FAILED for Safari |
| Release over an edge, nested to any depth | `applyDrop` + `resolve` docks it; a drop onto a docked window's edge nests | Arranger.swift:1047 `applyDrop`; `DropZoneTests`, `TreeEditTests`, `aFloatingWindowHeldInTheLeftEdgeBandDocksAtThePreviewedFrame` pass | VERIFIED |
| Windows open | New windows float on the Desktop tile, never auto-split | `Node.desktop`, `Arranger.admit`; `DesktopLeafTests`, `ArrangerLifecycleTests` pass | VERIFIED |
| Windows close, minimise, go fullscreen | Neighbours reflow; minimised and fullscreen windows return to their tile | `aMinimisedDockedWindowLendsItsTileAndReturnsToIt`, `aFullscreenDockedWindowKeepsItsLeafAndReturnsToItsTile`, `aFullscreenSpaceGetsNoDeskAndTheWindowReturnsToItsTile` pass | VERIFIED (fake); live fullscreen not run |
| Outcome: windows never overlap | Floating windows live inside the Desktop tile; drops that leave no room are refused; windows that lose room float | `resolve(..., desktopMinimum:)`, `aDropThatLeavesAWindowWithoutRoomShowsBlockedAndIsRefused`, lost-room floating (03-06), park corner avoids other displays (CR-02 fix, `hidingNeverParksAWindowOntoTheDisplayBeside`) | VERIFIED (Safari stays floating but clamped, so it does not overlap) |

The outcome clause holds. The flow fails at step 1 for Safari, so the "drag windows" part of the story is only partly delivered.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | Drag by title bar to an edge shows a preview and docks it on release, nesting at any depth; bypass modifier moves freely; new windows float on the Desktop; green button toggles docked/floating | FAILED (partial) | Everything except Safari is implemented and tested: drag tests, `shiftUndocksADockedWindowAtItsReleaseFrame`, `onAFloatingWindowItDocksLikeDock`, `onADockedWindowItFloatsLikeFloat`, plus the TextEdit live check in the VM. **Safari windows do not dock by drag** (observed live, WR-03 not fixed). |
| 2 | Close reflows neighbours; gap drag resizes both; gap size settable; window leaving native fullscreen returns to its tile | VERIFIED | `ArrangerReflowTests`, `aGapDragResizesBothSidesLiveAndCommitsOnMouseUp`, `GapPreferenceTests` plus Gaps submenu (0/4/8/12/16/24), the two fullscreen tests above. Live fullscreen (`PANE_LIVE_FULLSCREEN`) is opt-in and not run, so it is in the human list. |
| 3 | Menu and hotkeys through one dispatcher: dock, float, focus neighbour, undo, pause/resume, Restore all windows (also `pane://restore`) | VERIFIED | `PaneMacApp.swift` builds one `dispatch` closure used by `Hotkeys.register` and `StatusItemController`/`CommandMenu`; URLs go to `arrangeController.dispatch(command, from: .url)`. `PaneURL.commands` maps restore, toggle-desktop and split-finder. `CommandMenuTests`, `HotkeyTableTests`, `PaneURLTests`, `AppDelegateTests` pass. |
| 4 | Quit returns moved windows on-screen; crash/force-quit rescue on next launch; detects edge tiling, Stage Manager, click wallpaper, explains, offers Turn Off, restores originals; quit+relaunch restores layouts | VERIFIED | `Recovery.terminationPlan`, `AppDelegate.applicationShouldTerminate` (terminateLater plus SIGTERM), `RecoveryTests`, `ArrangerRestoreTests` (including WR-04/05/06 regressions), `ConflictPolicy` key allow-list, `ConflictControllerTests`, `LayoutStoreTests`, `ArrangerMultiDeskRestoreTests` (user-accepted fake). Live: the conflict alert's Turn Off set the edge-tiling defaults in the VM. Live quit, crash and Restore are in the human list. |
| 5 | Works with zoom absent and Screen Recording denied; testers install a Developer ID-signed, notarised build whose Accessibility grant survives updates | PRESENT_BEHAVIOR_UNVERIFIED | `NoScreenCaptureTests` passes and no source uses ScreenCaptureKit or CG capture APIs. Re-checked today: `build/Pane-0.3.0.dmg` sha256 ee940af0...5761, `stapler validate` worked, `spctl -t open` accepted with source=Notarized Developer ID, Authority Developer ID Application: Ken Scott (S2K7P43927). The designated requirement is Team-ID based, but no update over an existing install has been tried. |
| 6 | Swap tiles, balance, rotate, flip, move focused window into neighbour, resize tile from keyboard, snap floating windows to halves/thirds/quarters/max/centre by hotkey | VERIFIED | `Command` cases plus 33-entry `Hotkeys.entries` table; `LayoutEditTests`, `NeighbourTests`, `SnapTests`, `ArrangerCommandTests`, `ArrangerFocusTests`, `commandOverAnotherDockedTileSwapsTheTwoWindows` pass. |
| 7 | Hide/show the Desktop, arrange all / float all, split a tile with a new Finder window, mark frontmost "Don't Arrange" from the menu; Opt-click green gives native zoom; minimised docked window returns to its tile | VERIFIED | `StatusItemController` adds arrangeAll, floatAll, toggleDesktop, the Split submenu with finderSplit, and toggleExcludeFrontmost; `ArrangerDesktopTests`, `ArrangerFinderTests`, `ArrangerExclusionTests`, `afterAnOptionZoom...` (3 tests), `aMinimisedDockedWindowLendsItsTileAndReturnsToIt` pass. |

**Score:** 5/7 truths verified (1 present but behaviour-unverified, 1 failed)

### Required Artifacts

`verify.artifacts` over all 17 plans: 57/57 artifacts pass (exist and substantive). `verify.key-links`: 40/41 verified. The one miss (03-11 "DragSession -> DropZones.target") is wired through another file: `DropZones.target` is called from `Arranger.swift:971` and `Planner.swift:47`, and the result feeds the drag session. Counted as WIRED.

### Key Link Verification

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| `Hotkeys.register` / `CommandMenu` / `AppDelegate.application(_:open:)` | `ArrangeController.dispatch` | one `dispatch` closure in `PaneMacApp.run` | WIRED |
| `ArrangeController.run(effects)` | `PreviewPanel`, `GapHandlePanels`, `NoticeQueue`, `LayoutStore` | `.preview`, `.gapHandles`, `.notice`, `.save` effects | WIRED |
| `PermissionController.onTrackingStarted` | `ArrangeController.start` + `startTap` | closure in `PaneMacApp.run` | WIRED |
| `ConflictController` | `ArrangeController.setPaused(.stageManager)` | `setStageManagerPaused` closure | WIRED |
| `AppDelegate.applicationShouldTerminate` | `restoreForTermination` + `writeCleanExit` | init closures | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
| -------- | ---- | ------ | --------- | ------ |
| Status menu header and items | inventory, availability | `ArrangeController.onInventory` -> `StatusItemController.update` | AX inventory | FLOWING |
| Drop preview | `PreviewState` | Arranger dry run of `applyDrop` + `resolve` | live drag frames from `DragFramePoller` | FLOWING (not for Safari: no `.move` classification) |
| layout.json | World, home frames, session | `Arranger.snapshot` -> `LayoutStore.save` | Arranger state | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Headless suites | `swift test --filter "PaneModelTests\|PaneEngineTests\|PaneMacTests"` | 190 + 188 + 448 test runs printed, all passed, exit 0 (the orchestrator's 448-test result reproduced) | PASS |
| No AppKit in Model/Engine | `scripts/check-no-appkit.sh` | `no-appkit: OK (39 files)` | PASS |
| 20 named regression and behaviour tests (CR-01, CR-02, WR-01/02/04/05/06, fullscreen, minimise, drag, swap, gap, green button, no-capture, multi-desk restore) | grep of the saved run log | all 20 `passed` | PASS |
| Release DMG | `shasum`, `stapler validate`, `spctl -a -t open`, `codesign -dvv` | digest matches, stapled, accepted (Notarized Developer ID), Team ID S2K7P43927 | PASS |
| Live integration tests | not run (they move real windows; orchestrator rule) | — | SKIP (human) |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist and no plan declares a probe. Step 7c not applicable.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| TILE-01 | 03-11 | BLOCKED (partial) | Works for TextEdit (live); Safari never docks by drag (gap) |
| TILE-02 | 03-11 | SATISFIED | Shift bypass tests |
| TILE-03 | 03-04, 03-06 | SATISFIED | reflow tests |
| TILE-04 | 03-10 | SATISFIED | `GapPreference`, Gaps submenu |
| TILE-05 | 03-02, 03-13 | SATISFIED | edge-resize and gap-handle tests |
| TILE-06 | 03-13 | SATISFIED | green-button tests |
| TILE-07 | 03-01, 03-04 | SATISFIED | Desktop tile admit |
| TILE-08 | 03-10 | SATISFIED | `ArrangerPauseTests` |
| TILE-09 | 03-10, 03-12 | SATISFIED | one dispatcher |
| TILE-10 | 03-11, 03-17 | SATISFIED | `NoScreenCaptureTests`; no zoom code exists |
| TILE-11 | 03-02, 03-12 | SATISFIED | swap by hotkey and Cmd-drop |
| TILE-12 | 03-02, 03-12 | SATISFIED | balance/rotate/flip |
| TILE-13 | 03-02, 03-12 | SATISFIED | move and grow/shrink |
| TILE-14 | 03-02, 03-12 | SATISFIED | 13 `SnapTarget`s, hotkeys |
| TILE-15 | 03-01, 03-08, 03-15 | SATISFIED | hotkey, menu, `pane://toggle-desktop` |
| TILE-16 | 03-12 | SATISFIED | arrangeAll/floatAll |
| TILE-17 | 03-09, 03-15 | SATISFIED | Ctrl-Opt-Cmd-N, `pane://split-finder` |
| TILE-18 | 03-10 | SATISFIED | Don't Arrange menu item, Ctrl-Opt-Cmd-E |
| TILE-19 | 03-13 | SATISFIED | Opt-zoom tests |
| TILE-20 | 03-04 | SATISFIED | minimise test |
| WIN-07 | 03-04, 03-05 | SATISFIED (fake) / NEEDS HUMAN (live) | fullscreen tests pass. REQUIREMENTS.md still shows `[ ]` and "Pending" (bookkeeping, see warnings) |
| SAFE-01 | 03-15 | SATISFIED (engine) / NEEDS HUMAN | `terminationPlan`, AppDelegate |
| SAFE-02 | 03-14 | SATISFIED (engine) / NEEDS HUMAN | `Recovery`, restore tests |
| SAFE-03 | 03-14, 03-15 | SATISFIED | Restore All menu, hotkey, URL |
| SAFE-04 | 03-16 | SATISFIED | edge-tiling Turn Off confirmed live; Stage Manager and Restore need a human |
| SAFE-06 | 03-07 | SATISFIED (engine) / NEEDS HUMAN | `LayoutRestore.reattach`, multi-desk fake |

No orphaned requirements: every Phase 3 ID in REQUIREMENTS.md appears in at least one plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Sources (all) | — | TBD/FIXME/XXX | none found | — |
| Sources/PaneMac/AXWindowSystem.swift | 211 | `setHidden` logged and dropped | Info | Lead-accepted decision (CONTEXT, Claude's Discretion) |
| 5 files | — | `shortcut:` comments | Info | Documented, bounded |
| .planning/REQUIREMENTS.md | 29, 172 | WIN-07 still `[ ]` / Pending though implemented | Warning | Traceability is wrong; tick it when the live fullscreen check passes |
| build/Pane-0.3.0.dmg | — | built 08:16, before the review fixes adb93d2..82f767c (09:48-10:00) | Warning | The notarised DMG lacks CR-01, CR-02 and WR-01/02/04/05/06. Rebuild before UAT and before any distribution |
| Planner (deferred-items 03-12) | — | a floating window whose minimum exceeds the display blocks every dock on its desk | Warning | Edge case that breaks SC1 for that desk; no plan owns it |
| App bundle | — | no AppIcon in Resources (blank icon in alerts) | Info | Cosmetic |
| scripts/release.sh | ~97 | hdiutil fallback lost the DMG once; no `[ -f ]` check, no DMG `spctl` (IN-07) | Warning | Release flake; create-dmg or a retry would fix it |
| Tests | — | `FreezeTestTests/itResumesByItself` timing-sensitive; live minimise test flaked once | Info | Flaky tests (deferred-items) |
| 03-REVIEW.md | — | IN-01..IN-09 open | Info | Out of fix scope |

### Human Verification Required

These are listed in the frontmatter `human_verification` list (18 items). They run after the gap fix. **Rebuild from HEAD first:** the 0.3.0 DMG predates the review fixes. A Developer ID `release.sh --build-only` app copied by scp has no quarantine and keeps a stable designated requirement.

**VM (`pane-test`, macOS 15.7.7, single display):**
1. Safari drag-dock with Pane's log streaming (gap diagnosis, WR-03)
2. Accessibility granted in System Settings while Pane runs, without the Set Up button: tracking starts with no relaunch (WR-02)
3. TextEdit drags: edge preview, Shift free move, Cmd-release swap, nesting on a docked window's edge
4. Close reflow, gap-handle drag, Gaps submenu change kept after relaunch
5. Green button toggle; Opt-click native zoom; minimise and restore; fullscreen and exit return to the tile (WIN-07)
6. Keyboard pass: focus, move, swap, grow/shrink, balance, rotate, flip, every snap target
7. Menu pass: Hide/Show Desktop, Arrange All, Float All, Finder split, Don't Arrange, Pause/Resume, Undo-after-new-window (CR-01)
8. `open pane://toggle-desktop`, `pane://split-finder`, `pane://restore`; a malformed URL does nothing
9. Hide Desktop, then quit from the menu: parked windows come back on-screen (SAFE-01)
10. Hide Desktop, `kill -9`, relaunch: rescue and crash notice; a second kill within 60 s starts paused (SAFE-02)
11. Dock 3, quit, relaunch with apps running: same tiles (SAFE-06)
12. Stage Manager pause, Turn Off; click-wallpaper Turn Off; Restore macOS Window Settings (SAFE-04)
13. Screen Recording never granted: no prompt, not listed, tiling works (TILE-10)
14. Install build N+1 over build N: Accessibility grant kept (SC5)
15. Spaces: separate layouts on Space 1 and Space 2 (VM if Spaces work there, else host)

**Host, second display (when the user is home):**
16. Hide Desktop on the left display: no parked window appears on the right display (CR-02)
17. Two displays and two Spaces: quit and relaunch restores each layout
18. Rerun the live `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` under the live-test rules

### Gaps Summary

One gap blocks the goal. **Drag-to-dock does not work for Safari** (SC1/TILE-01, partial). Dragging is the phase's headline interaction and the project's Core Value. It is observed failing live for a mainstream app, and the probable fix (WR-03) was deliberately skipped until a live log confirms the cause. Close it by:

1. capturing one Safari drag log in the VM;
2. fixing the confirmed condition (CG-vs-AX start frame size, or travel counted only from `leftMouseDragged`);
3. adding a fake regression test;
4. re-checking live.

No later milestone phase covers this, so it is not deferred.

Everything else is implemented, wired and covered by passing headless tests. Hands-on checks remain for real-OS behaviour: quit, crash, TCC, conflicts, fullscreen, URLs, and two displays.

Non-blocking warnings:
- The notarised 0.3.0 DMG predates the review fixes.
- REQUIREMENTS.md still lists WIN-07 as Pending.
- The "floating window too big blocks every dock" edge case has no owner.
- The release.sh DMG flake is unresolved.

---

_Verified: 2026-10-26T15:30:00Z_
_Verifier: Claude (gsd-verifier)_
