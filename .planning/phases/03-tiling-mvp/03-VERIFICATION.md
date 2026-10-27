---
phase: 03-tiling-mvp
verified: 2026-10-27T01:18:02Z
status: gaps_found
score: 8/10 must-haves verified
covered_files: [".github/workflows/ci.yml",".planning/phases/03-tiling-mvp/03-01-PLAN.md",".planning/phases/03-tiling-mvp/03-01-SUMMARY.md",".planning/phases/03-tiling-mvp/03-02-PLAN.md",".planning/phases/03-tiling-mvp/03-02-SUMMARY.md",".planning/phases/03-tiling-mvp/03-03-PLAN.md",".planning/phases/03-tiling-mvp/03-03-SUMMARY.md",".planning/phases/03-tiling-mvp/03-04-PLAN.md",".planning/phases/03-tiling-mvp/03-04-SUMMARY.md",".planning/phases/03-tiling-mvp/03-05-PLAN.md",".planning/phases/03-tiling-mvp/03-05-SUMMARY.md",".planning/phases/03-tiling-mvp/03-06-PLAN.md",".planning/phases/03-tiling-mvp/03-06-SUMMARY.md",".planning/phases/03-tiling-mvp/03-07-PLAN.md",".planning/phases/03-tiling-mvp/03-07-SUMMARY.md",".planning/phases/03-tiling-mvp/03-08-PLAN.md",".planning/phases/03-tiling-mvp/03-08-SUMMARY.md",".planning/phases/03-tiling-mvp/03-09-PLAN.md",".planning/phases/03-tiling-mvp/03-09-SUMMARY.md",".planning/phases/03-tiling-mvp/03-10-PLAN.md",".planning/phases/03-tiling-mvp/03-10-SUMMARY.md",".planning/phases/03-tiling-mvp/03-11-PLAN.md",".planning/phases/03-tiling-mvp/03-11-SUMMARY.md",".planning/phases/03-tiling-mvp/03-12-PLAN.md",".planning/phases/03-tiling-mvp/03-12-SUMMARY.md",".planning/phases/03-tiling-mvp/03-13-PLAN.md",".planning/phases/03-tiling-mvp/03-13-SUMMARY.md",".planning/phases/03-tiling-mvp/03-14-PLAN.md",".planning/phases/03-tiling-mvp/03-14-SUMMARY.md",".planning/phases/03-tiling-mvp/03-15-PLAN.md",".planning/phases/03-tiling-mvp/03-15-SUMMARY.md",".planning/phases/03-tiling-mvp/03-16-PLAN.md",".planning/phases/03-tiling-mvp/03-16-SUMMARY.md",".planning/phases/03-tiling-mvp/03-17-PLAN.md",".planning/phases/03-tiling-mvp/03-17-SUMMARY.md",".planning/phases/03-tiling-mvp/03-18-PLAN.md",".planning/phases/03-tiling-mvp/03-18-SUMMARY.md",".planning/phases/03-tiling-mvp/03-19-PLAN.md",".planning/phases/03-tiling-mvp/03-19-SUMMARY.md",".planning/phases/03-tiling-mvp/03-20-PLAN.md",".planning/phases/03-tiling-mvp/03-20-SUMMARY.md",".planning/phases/03-tiling-mvp/03-21-PLAN.md",".planning/phases/03-tiling-mvp/03-21-SUMMARY.md",".planning/phases/03-tiling-mvp/03-22-PLAN.md",".planning/phases/03-tiling-mvp/03-22-SUMMARY.md","Package.resolved","Package.swift","Sources/PaneEngine/Arranger+Commands.swift","Sources/PaneEngine/Arranger.swift","Sources/PaneEngine/Command.swift","Sources/PaneEngine/ConflictPolicy.swift","Sources/PaneEngine/DragSession.swift","Sources/PaneEngine/GapHandles.swift","Sources/PaneEngine/LayoutFile.swift","Sources/PaneEngine/LayoutRestore.swift","Sources/PaneEngine/LifecycleSync.swift","Sources/PaneEngine/MinimumSizeLearner.swift","Sources/PaneEngine/Notice.swift","Sources/PaneEngine/PaneURL.swift","Sources/PaneEngine/PendingFocus.swift","Sources/PaneEngine/PermissionReducer.swift","Sources/PaneEngine/Planner.swift","Sources/PaneEngine/Recovery.swift","Sources/PaneEngine/WindowSnapshot.swift","Sources/PaneEngine/WindowSystem.swift","Sources/PaneEngine/WindowTracker.swift","Sources/PaneFixtureApp/main.swift","Sources/PaneMac/AX/AXAppThread.swift","Sources/PaneMac/AX/AXSnapshotReader.swift","Sources/PaneMac/AX/MenuPress.swift","Sources/PaneMac/AXWindowSystem.swift","Sources/PaneMac/AppDelegate.swift","Sources/PaneMac/ArrangeController.swift","Sources/PaneMac/CGWindowList.swift","Sources/PaneMac/ConflictController.swift","Sources/PaneMac/Displays.swift","Sources/PaneMac/GapPreference.swift","Sources/PaneMac/Input/DragFramePoller.swift","Sources/PaneMac/Input/GreenButton.swift","Sources/PaneMac/Input/Hotkeys.swift","Sources/PaneMac/Input/InputTap.swift","Sources/PaneMac/LayoutStore.swift","Sources/PaneMac/MinimumHintsStore.swift","Sources/PaneMac/Overlay/GapHandlePanels.swift","Sources/PaneMac/Overlay/NoticeQueue.swift","Sources/PaneMac/Overlay/PreviewPanel.swift","Sources/PaneMac/Overlay/PreviewStyle.swift","Sources/PaneMac/Overlay/Toast.swift","Sources/PaneMac/PaneMacApp.swift","Sources/PaneMac/Shell/CommandMenu.swift","Sources/PaneMac/Shell/ConflictCopy.swift","Sources/PaneMac/Shell/MenuCopy.swift","Sources/PaneMac/Shell/NoticeCopy.swift","Sources/PaneMac/Shell/StatusItemController.swift","Sources/PaneMac/WindowManagerSettings.swift","Sources/PaneModel/DesktopLayer.swift","Sources/PaneModel/DropZones.swift","Sources/PaneModel/IDs.swift","Sources/PaneModel/LayoutTree.swift","Sources/PaneModel/Neighbours.swift","Sources/PaneModel/Resolve.swift","Sources/PaneModel/Snap.swift","Sources/PaneModel/TreeEdits.swift","Sources/PaneModel/Undo.swift","Sources/PaneModel/World.swift","Sources/PanePrivate/SkyLightSpaces.swift","Sources/PaneTestSupport/FakeWindowSystem.swift","Tests/PaneEngineTests/ArrangerCommandTests.swift","Tests/PaneEngineTests/ArrangerDesktopTests.swift","Tests/PaneEngineTests/ArrangerDragTests.swift","Tests/PaneEngineTests/ArrangerExclusionTests.swift","Tests/PaneEngineTests/ArrangerFinderTests.swift","Tests/PaneEngineTests/ArrangerFocusTests.swift","Tests/PaneEngineTests/ArrangerGreenButtonTests.swift","Tests/PaneEngineTests/ArrangerLifecycleTests.swift","Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift","Tests/PaneEngineTests/ArrangerPauseTests.swift","Tests/PaneEngineTests/ArrangerReflowTests.swift","Tests/PaneEngineTests/ArrangerResizeTests.swift","Tests/PaneEngineTests/ArrangerRestoreTests.swift","Tests/PaneEngineTests/ArrangerSpacesTests.swift","Tests/PaneEngineTests/CommandTests.swift","Tests/PaneEngineTests/ConflictPolicyTests.swift","Tests/PaneEngineTests/DragSessionTests.swift","Tests/PaneEngineTests/FrameScenarioTests.swift","Tests/PaneEngineTests/GapHandleGeometryTests.swift","Tests/PaneEngineTests/LifecycleSyncTests.swift","Tests/PaneEngineTests/MinimumSizeLearnerTests.swift","Tests/PaneEngineTests/PaneURLTests.swift","Tests/PaneEngineTests/PendingFocusTests.swift","Tests/PaneEngineTests/PermissionReducerTests.swift","Tests/PaneEngineTests/PlannerTests.swift","Tests/PaneEngineTests/RecoveryTests.swift","Tests/PaneEngineTests/TooBigDockedWindowTests.swift","Tests/PaneEngineTests/TrackerDisplayTests.swift","Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift","Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift","Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift","Tests/PaneMacIntegrationTests/InputTapIntegrationTests.swift","Tests/PaneMacIntegrationTests/IntegrationSupport.swift","Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift","Tests/PaneMacIntegrationTests/QuitRestoreIntegrationTests.swift","Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift","Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift","Tests/PaneMacIntegrationTests/TitleBarDragIntegrationTests.swift","Tests/PaneMacTests/AppDelegateTests.swift","Tests/PaneMacTests/CapabilitiesTests.swift","Tests/PaneMacTests/CommandMenuTests.swift","Tests/PaneMacTests/ConflictControllerTests.swift","Tests/PaneMacTests/ConflictCopyTests.swift","Tests/PaneMacTests/GapPreferenceTests.swift","Tests/PaneMacTests/GreenButtonHitTests.swift","Tests/PaneMacTests/HotkeyTableTests.swift","Tests/PaneMacTests/LayoutStoreTests.swift","Tests/PaneMacTests/MenuCopyTests.swift","Tests/PaneMacTests/MenuPressTests.swift","Tests/PaneMacTests/MinimumHintsStoreTests.swift","Tests/PaneMacTests/NoScreenCaptureTests.swift","Tests/PaneMacTests/NoticeCopyTests.swift","Tests/PaneMacTests/NoticeQueueTests.swift","Tests/PaneMacTests/PreviewStyleTests.swift","Tests/PaneMacTests/TopmostWindowTests.swift","Tests/PaneMacTests/WakeTimerTests.swift","Tests/PaneMacTests/WindowManagerSettingsTests.swift","Tests/PaneModelTests/DesktopLayerTests.swift","Tests/PaneModelTests/DesktopLeafTests.swift","Tests/PaneModelTests/LayoutEditTests.swift","Tests/PaneModelTests/LifecycleTests.swift","Tests/PaneModelTests/NeighbourTests.swift","Tests/PaneModelTests/PersistenceTests.swift","Tests/PaneModelTests/ResolveFuzzTests.swift","Tests/PaneModelTests/ResolveTests.swift","Tests/PaneModelTests/ScenarioTests.swift","Tests/PaneModelTests/SkeletonTests.swift","Tests/PaneModelTests/SnapTests.swift","Tests/PaneModelTests/TabsTests.swift","Tests/PaneModelTests/TreeEditTests.swift","Tests/PaneModelTests/UndoTests.swift","Tests/PaneModelTests/WorldRekeyTests.swift","scripts/check-no-appkit.sh","scripts/release.sh","scripts/vm-live-test.sh","xcode/Pane-Info.plist","xcode/project.yml"]
covered_digest: "v3:sha256:f9da5c83fcb7e5947d67dc7162575abbbbe12432d9a4dde5abfc2b10d51807d6"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 6/7
  gaps_closed:
    - "G-03-3 gap drag (TILE-05): split re-base for a pinned side and the live move held in Arranger state (03-20), plus WR-01 lost-room float on the committed World. Named tests pass."
    - "G-03-4 green button (TILE-06/TILE-19): the tap's window-0 fallback looks through only a whole-display overlay (03-18, CR-01). Pure selection tests pass. Still needs a live re-check (human)."
    - "G-03-5 focus of a new window (TILE-09): PendingFocus keeps a hint until its window is tracked (03-19). Tests pass and the wiring is confirmed in AXWindowSystem.refresh."
    - "G-03-6 too-big docked window (core value, D-26): the Planner drops floaters that would push docked windows out (03-21, WR-02), and an unmoved refusal is retried once and learned (03-22, WR-03). The learned size stays per window and session only (CR-02). Tests pass."
    - "G-03-7 live too-big test: a test bug, fixed in 9ffc59a. REVIEW-FIX reports a VM pass (not re-run here, live suites are VM-only)."
    - "SC5 update keeps the grant: UAT test 13 passed with a bumped version (0.3.1/999); 03-18..03-22 kept the grant across 0.3.2-0.3.6"
  gaps_remaining: []
  regressions: []
gaps:
  - truth: "SC4 / SAFE-06: quitting and relaunching Pane while apps keep running brings each layout back with the same windows in their tiles"
    status: partial
    reason: "Space 1 restores (UAT test 10). The docked windows of a desk on a Space that is not shown at launch are dropped on every relaunch. This is a clean, deterministic repro, seen twice in the VM in 03-18 and again in 03-22: layout.json had Space 41 with Notes#150 and reminders#693 docked, both apps running; after quit and relaunch the desk key stays but its docked list is empty. LayoutRestore.reattach removes every saved window that is not in the first complete inventory, through the close path. The likely cause (not confirmed by a debug session) is that AXWindows lists only the current Space's windows, so off-Space windows are not tracked when the restore runs. ArrangerMultiDeskRestoreTests passes only because FakeWindowSystem reports windows on hidden Spaces, which the real AX path does not. Phase 3 defines one layout per display and Space (03-05), and its scope note keeps 'unchanged window IDs while apps keep running' in Phase 3. So each Space's layout is part of this contract, and UAT test 17 would fail its two-Space half."
    artifacts:
      - path: "Sources/PaneEngine/LayoutRestore.swift"
        issue: "reattach treats 'not tracked at the first complete inventory' as closed, for windows on Spaces that are not shown too"
      - path: "Sources/PaneEngine/Arranger.swift"
        issue: "the restore runs once at inventory.initialRefreshComplete (~line 195), when the off-Space windows have not been seen yet"
      - path: "Sources/PaneTestSupport/FakeWindowSystem.swift"
        issue: "the fake inventory includes windows on hidden Spaces, so ArrangerMultiDeskRestoreTests cannot see this failure (fixture-only reliance)"
    missing:
      - "Debug session to confirm the cause (AXWindows on a Space that is not shown, in the VM)"
      - "Keep a saved window that is not tracked yet but whose ID is still in the CG window list (optionAll), or that is on a Space that is not shown (SkyLightSpaces), as a dormant entry in its desk instead of closing it. Re-attach it when it is first tracked, for example when its Space is shown"
      - "A FakeWindowSystem mode that hides windows on a Space that is not shown from the inventory, as AX does, plus a restore test that fails today"
      - "Live re-check in the VM: dock on Space 2, switch to Space 1, quit and relaunch, switch back: same tiles"
deferred: []
human_verification:
  - test: "VM, final build (HEAD 159a77b, Developer ID re-sign): by hand, click the green button of a docked window, then of a floating window that does not fill the Desktop tile, then Option-click both"
    expected: "Docked floats, floating docks, neither goes fullscreen. Option-click zooms, then the window returns to its tile or the Desktop tile (D-33)"
    why_human: "The CR-01 fix (ae5560e) changed the window-0 fallback after the 03-18 VM pass: it now looks through an overlay only when it covers CGDisplayBounds of the display under the point. Whether the macOS 15 Dock overlay's CG bounds equal CGDisplayBounds is a live OS fact. The 03-18 plan also asks for a re-test by hand"
  - test: "VM: with a docked window under an open app menu, a context menu and a Dock tile, click the menu item or tile that sits over the green button"
    expected: "The menu or Dock gets the click. Pane does not toggle the window underneath (CR-01)"
    why_human: "Real menu and Dock windows with real layers; the pure function is tested only with synthetic entries"
  - test: "VM: drag the gap between two docked tiles by hand, including toward a side held at its minimum, hold still, then release (UAT test 3)"
    expected: "Both tiles follow smoothly, nothing jumps back, and the split sticks after release"
    why_human: "The user reported jank by feel. The 03-20 VM check used injected drags before the WR-01 change"
  - test: "VM: re-run UAT tests 6 and 7 with the final build: dock A, open B, Undo; then a fresh C; pane://split-finder with Finder windows already open, with no exclusions"
    expected: "B and C can be docked with Ctrl-Opt-Cmd-D, the menu enables Dock for them, and split-finder docks the new Finder window when there is room"
    why_human: "Real AX focus notifications. 03-19 passed these before the review fixes; CR-02 also touched AXWindowSystem.emit"
  - test: "VM: re-run UAT test 15 (Reminders' Welcome window docked beside Notes on Space 2) with the final build, then check min-size-hints.json"
    expected: "Reminders floats about 2 s after docking and Notes keeps its tile. min-size-hints.json gains no com.apple.reminders entry (CR-02 keeps it per window and session only)"
    why_human: "Real app refusal timing; CR-02 changed the persistence path after the 03-22 VM run"
  - test: "VM: Option-click zoom a floating window so it fills the Desktop tile, then plain-click its green button"
    expected: "It docks, or Pane beeps because there is no room (D-26). The deferred item says Planner.dockTarget returns .tile(_, .center) here, but the code converts a centre target to the nearest edge band, so the refusal is more likely D-26 (room), which 03-21 changed"
    why_human: "Live desk state; the cause in deferred-items (03-18) is not supported by the code"
  - test: "Host, second display: Hide Desktop Tile on one display (UAT test 16)"
    expected: "No parked window appears on the other display or over its tiles (CR-02 of the earlier review)"
    why_human: "Needs two physical displays"
  - test: "Host, second display: dock windows on both displays and two Spaces, quit and relaunch (UAT test 17)"
    expected: "Each display and Space gets its own layout back. Expected to fail on the Space half until the SAFE-06 gap above is closed"
    why_human: "Needs two physical displays"
---

# Phase 3: Tiling MVP Verification Report

**Phase Goal:** As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp (`user-story.validate`: valid)
**Verified:** 2026-10-27T01:18:02Z
**Status:** gaps_found
**Re-verification:** Yes. It replaces the 16:15Z report, which came before UAT and gap plans 03-18..03-22. That report had no `gaps:` section, so every must-have was checked again in full.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| Drag a window by its title bar to an edge | A preview appears and the window docks on release, at any depth | `InputTap` -> `ArrangeController` -> `Arranger` drag path -> `DropZones.target` -> `PreviewPanel`; `ArrangerDragTests` pass; UAT test 2 passed live (preview, Shift, Cmd swap, 3+ levels deep) | VERIFIED |
| Windows open | New windows float on the Desktop tile and never auto-split | `Arranger.admit`, `Node.desktop`; UAT test 14 passed live; 03-21 keeps the Desktop widening when a floater fits (`PlannerTests`) | VERIFIED |
| Windows close, minimise, go fullscreen | Neighbours reflow; minimised and fullscreen windows return to their tile | `ArrangerReflowTests`, the minimise and fullscreen tests; UAT tests 3 and 4 passed live (close, minimise, fullscreen) | VERIFIED |
| Resize by gap | Both sides follow, and the split sticks | 03-20 re-base plus `liveGap`; `aTwoChildGapWithAPinnedGrowingSideIsNotFrozen`, `aWindowChangeMidDragKeepsTheLiveLayout`, `anOffPlanFrameAndACorrectionTickMidDragKeepTheLiveLayout`, `aWindowThatLosesItsRoomMidDragFloatsOnceWithOneNotice` pass | VERIFIED (hand feel: human) |
| Outcome: windows never overlap | A docked window that can't fit floats; one too-big floater doesn't float the whole desk | 03-21 `baselineUnfit` plus WR-02 re-add; 03-22 retry plus unmoved learning; `TooBigDockedWindowTests`, `RefusalRetryBoundTests`, `aFloaterTooBigForTheRoom…` pass. Accepted trade-offs: T-03-58 (a floater that can't shrink may overlap a docked tile) and overflow of 32 pt or less tolerated | VERIFIED (with the accepted trade-offs) |
| Layout survives a Pane relaunch | Each layout comes back | Space 1: UAT test 10 passed. Space 2: docked windows dropped on every relaunch (deferred-items 03-18, repro twice) | FAILED (multi-Space) |

The outcome clause ("my windows never overlap") holds within the accepted trade-offs. The phase's own SC4 restore contract fails for Spaces that are not shown at launch.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | SC1: title-bar drag to an edge shows a preview and docks, nesting at any depth; bypass moves freely; new windows float on the Desktop; the green button toggles docked/floating | ? UNCERTAIN (human) | Drag, bypass, nesting and new-window parts pass live (UAT tests 2 and 14) and in tests. Green button: `CGWindowList.topmost(at:in:excludingPID:display:)` (CGWindowList.swift:33) is called from InputTap.swift:135, and its result feeds `GreenButton.shouldSwallow`. All 7 `TopmostWindowTests` pass, including the Dock overlay listed first and the CR-01 menu and Dock-tile cases. The 03-18 VM pass (plain clicks toggle, Option-click passes through) ran on code from before CR-01. The final rule depends on the macOS 15 Dock overlay's CG bounds matching `CGDisplayBounds`, which has not been seen live |
| 2 | SC2: close reflows; gap drag resizes both; gap size settable; a window leaving fullscreen returns to its tile | ✓ VERIFIED | UAT test 3 (close reflow, Gaps menu, relaunch) and test 4 (fullscreen return) passed live. G-03-3: `boundaryChange` re-bases each split once (Arranger.swift:1222-1263, `TreeEdits.setWeights` :243). `replan()` applies `liveGap` until mouse-up (:1301), and `gapDrag` clears it first on `ended` (:1423). The named H1/H2/WR-01 tests pass |
| 3 | SC3: menu and hotkeys through one dispatcher (dock, float, focus neighbour, undo, pause/resume, Restore all, `pane://restore`) | ✓ VERIFIED | One dispatcher (as before). UAT tests 5, 6 (minus G-03-5), 7 and 9 passed live. G-03-5: `handle(_ hint:)` records every focus hint, including those with no ID (AXWindowSystem.swift:478). `refresh(pid:)` resolves it after ingest, with AXMain only from a successful read (:327-330). `PendingFocusTests` (9) pass, including `aSecondWindowOfTheAppBecomesFocusedOnceTracked`. A live re-run with the final build is a human item |
| 4 | SC4: quit returns windows on-screen; crash rescue; conflict detection, Turn Off, restore originals; quit and relaunch with apps running brings each layout back with the same windows in their tiles | ✗ FAILED (partial) | Quit restore (UAT 8), crash and crash loop (UAT 9), conflicts (UAT 11) and Space 1 relaunch (UAT 10) passed live. **A Space that is not shown at launch loses its docked windows on every relaunch** (deferred-items 03-18, repro twice; seen again in 03-22). See Gaps |
| 5 | SC5: works with zoom absent and Screen Recording denied; Developer ID signed and notarised; the grant survives updates | ✓ VERIFIED | UAT 12 (no Screen Recording prompt; TCC holds only Accessibility). UAT 13: a bumped-version install kept the grant, and 03-18..03-22 kept it across 0.3.2-0.3.6. `build/Pane-0.3.0.dmg` re-checked today: `stapler validate` worked; `spctl` accepted it, source=Notarized Developer ID, Ken Scott (S2K7P43927). Warning: that DMG predates every UAT and review fix |
| 6 | SC6: swap, balance, rotate, flip, move into a neighbour, resize from the keyboard, snap floaters | ✓ VERIFIED | UAT test 5 passed (docked half by hand, floating half by injected keys with exact frames); `LayoutEditTests`, `SnapTests`, `ArrangerCommandTests` pass |
| 7 | SC7: hide/show the Desktop, arrange all, float all, Finder split, Don't Arrange; Option-click zoom; a minimised docked window returns | ✓ VERIFIED | UAT test 6 menu items passed except the G-03-5 dock (now fixed, truth 3). UAT 4: minimise passed; Option-click zooms and D-33 returns the window (user decision 2026-10-26; 03-18 checks d1/d2). UAT 7: toggle-desktop and restore passed; split-finder failed only because Finder was excluded (diagnosed) |
| 8 | G-03-3: a gap drag next to a pinned side moves that gap; no mid-drag event writes the pre-drag tiles; a drag that moves nothing adds no undo step | ✓ VERIFIED | `aTwoChildGapWithAPinnedGrowingSideIsNotFrozen`, `aGapNextToAPinnedSideMovesThatGapAndNoOther`, `aDragIntoThePinnedSidesOwnMinimumMovesNothing`, `aWindowChangeMidDragKeepsTheLiveLayout`, `anOffPlanFrameAndACorrectionTickMidDragKeepTheLiveLayout`, `aWindowThatLosesItsRoomMidDragFloatsOnceWithOneNotice`: all pass in this run |
| 9 | G-03-5: a second window of an app with a docked window becomes the command target | ✓ VERIFIED | Truth 3's evidence. `focusedWindow(of:)` (:278) still prefers `focusedIdentities`, which `.windowFocused` now updates for the new window |
| 10 | G-03-6: a docked window that can't fit its tile floats instead of overlapping a neighbour; one too-big floater doesn't float the whole desk | ✓ VERIFIED | Planner.swift:22-48 (`baselineUnfit`, WR-02 re-add). Arranger `retryRefusal` (:587) is called from `.frameApplied` (:493). The learner's `unmoved` record and `persistable` map (MinimumSizeLearner.swift:28-33) apply, and only `persistableMinimum` reaches `bundleHints` and `onLearnedMinimum` (WindowTracker.swift:163-175, AXWindowSystem.swift:435-450). `TooBigDockedWindowTests`, `RefusalRetryBoundTests`, `PlannerTests` (14), `MinimumSizeLearnerTests` and `aMinimumLearnedFromUnmovedRefusalsStaysWithItsWindow` pass. Accepted: T-03-58 and the 32 pt tolerance |

**Score:** 8/10 truths verified (0 present but behaviour-unverified; 1 uncertain and routed to a human; 1 failed)

### Required Artifacts

`verify.artifacts` over all 22 plans: 71/71 pass (exist and substantive). New in 03-18..03-22: `CGWindowList.swift` (`layer == 0`), `TopmostWindowTests.swift`, `PendingFocus.swift`, `PendingFocusTests.swift`, `TreeEdits.setWeights`, `Arranger` (`liveGap`, `refusalRetried`), `Planner.swift`, `PlannerTests.swift`, `ArrangerDesktopTests.swift`, `MinimumSizeLearner.swift` (`unmoved`) and `TooBigDockedWindowTests.swift`. All are substantive, with no stubs.

### Key Link Verification

`verify.key-links`: 03-01..03-19 resolve, except the known 03-11 `DragSession -> DropZones.target` miss. That link is wired through `Arranger.swift`, which calls `DropZones.target` and feeds the session. The 03-20, 03-21 and 03-22 links use a symbol in `from:`, which the tool cannot parse, so I checked them by hand:

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| InputTap.swift:135 | `CGWindowList.topmostWindow(at:)` -> `topmost(…display:)` | window-0 fallback, then `GreenButton.shouldSwallow` | WIRED |
| AXWindowSystem `handle(_ hint:)` :478 / `refresh` :328 | `PendingFocus.hint` / `.resolve` | then `emit(.windowFocused)`, which sets `focusedIdentities` (:433) | WIRED |
| Arranger `boundaryChange` :1246 | `TreeEdits.setWeights` | re-base before `resizeBetween` | WIRED |
| Arranger event paths (29 `replan()` calls) | `replan()` :1301 | applies `liveGap`, after `floatLostRoom()` | WIRED |
| `planFloatingLostRoom` :1453 | `Planner.plan` | `plan.unfit` drives the float loop | WIRED |
| `.frameApplied` :491-493 | `retryRefusal` -> `pendingCorrections` -> `tick` / `correct` | one retry per window and tile | WIRED |
| WindowTracker `applyFrameResult` :317 | `learner.recordWrite` | unmoved promotion, then `persistableMinimum` | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
| -------- | ---- | ------ | --------- | ------ |
| Green-button swallow | window ID | live `CGWindowListCopyWindowInfo` front-to-back plus `CGDisplayBounds` | yes | FLOWING (live result after CR-01 is a human item) |
| Command target | `focusedWindow(of:)` | AX focus notifications -> `PendingFocus` -> `focusedIdentities` | yes | FLOWING |
| min-size-hints.json | per-bundle minimum | `persistableMinimum` only (no unmoved axes) | yes | FLOWING |
| layout.json restore | saved World | `LayoutStore` -> `.restore` -> `LayoutRestore.reattach(tracked:)` | Space 1 yes. Off-Space windows are not in `tracked` | DISCONNECTED for Spaces that are not shown (gap) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Live gate before any test run | `grep IntegrationEnv.trusted`; all 20 integration suites gated; `PANE_LIVE` unset | `trusted = AXIsProcessTrusted() && PANE_LIVE == "1"` | PASS |
| Headless suites (one full run) | `env -u PANE_LIVE swift test` | 193 + 196 + 42 + 492 tests. 1 failure: `FreezeTestTests/itResumesByItself` (timing). All gap-closure suites passed | PASS (one known flake) |
| The flake alone | `swift test --filter FreezeTestTests` | 8/8 passed | PASS (flaky under load; deferred-items 03-08) |
| No AppKit in Model/Engine | `scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | PASS |
| Notarised DMG | `stapler validate`, `spctl -a -t open` | worked; accepted, Notarized Developer ID | PASS (stale build) |
| Live AX suites | not run (host rule; VM only through `scripts/vm-live-test.sh`) | REVIEW-FIX reports `ArrangeIntegrationTests|ButtonFrameIntegrationTests` 6 passed, 1 skipped in the VM | SKIP (not re-run here) |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist and no plan declares a probe. Not applicable.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| TILE-01 | 03-11, 03-22 | SATISFIED | UAT 2 live; drag tests |
| TILE-02 | 03-11 | SATISFIED | UAT 2 (Shift never docks) |
| TILE-03 | 03-04, 03-06, … | SATISFIED | UAT 3 close reflow |
| TILE-04 | 03-10 | SATISFIED | UAT 3 Gaps menu, kept after relaunch |
| TILE-05 | 03-02, 03-13, 03-20 | SATISFIED (feel: human) | G-03-3 tests |
| TILE-06 | 03-13, 03-18 | NEEDS HUMAN | pure tests pass; live re-check after CR-01 pending |
| TILE-07 | 03-01, 03-04, 03-21, … | SATISFIED | UAT 14; Planner tests |
| TILE-08 | 03-10, … | SATISFIED | UAT 6 Pause/Resume |
| TILE-09 | 03-19, … | SATISFIED (live re-run: human) | `PendingFocus` wiring and tests |
| TILE-10 | 03-11, 03-17, … | SATISFIED | UAT 12 |
| TILE-11..14 | 03-02, 03-12 | SATISFIED | UAT 5 |
| TILE-15 | 03-01, 03-08, 03-15 | SATISFIED | UAT 6 and 7 toggle-desktop |
| TILE-16 | 03-12 | SATISFIED | UAT 6 |
| TILE-17 | 03-09, 03-15 | SATISFIED (URL re-run: human) | UAT 6 menu; 03-19 VM docked Finder 1017 via URL |
| TILE-18 | 03-10 | SATISFIED | UAT 6 |
| TILE-19 | 03-13, 03-18 | SATISFIED | UAT 4 and 03-18 d1/d2 (Option-click passes through; D-33 kept by user decision) |
| TILE-20 | 03-04 | SATISFIED | UAT 4 minimise |
| WIN-07 | 03-04, 03-05 | SATISFIED | UAT 4 and 03-18 e2 live. REQUIREMENTS.md still says `[ ]` / Pending (bookkeeping) |
| WIN-04 | 03-22 (extra, Phase 2 ID) | SATISFIED | the unmoved-refusal learning extends it; it does not count toward the phase list |
| SAFE-01 | 03-15 | SATISFIED | UAT 8 |
| SAFE-02 | 03-14 | SATISFIED | UAT 9 |
| SAFE-03 | 03-14, 03-15 | SATISFIED | UAT 7 `pane://restore` |
| SAFE-04 | 03-16 | SATISFIED | UAT 11 |
| SAFE-06 | 03-07, … | BLOCKED (partial) | Space 1 passes (UAT 10). Spaces not shown at launch are dropped on relaunch (gap) |

All 26 phase IDs are claimed by at least one plan. No requirement is orphaned.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Sources (all) | — | TBD/FIXME/XXX | none | — |
| Sources/PaneEngine/LayoutRestore.swift | 18-23 | an untracked saved window is treated as closed | 🛑 Blocker | Drops the layouts of Spaces that are not shown on every relaunch (SAFE-06 gap) |
| Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift | 63 | fixture-only: the fake tracks windows on hidden Spaces | ⚠️ Warning | The test gives a green result on a path that fails in production |
| Tests/PaneMacTests/FreezeTestTests.swift | 58 | timing-sensitive (50 ms resume) | ⚠️ Warning | It failed in this full run, so a full `swift test` exits 1 at random; CI flake |
| Sources/PaneMac/CGWindowList.swift | 34 | own-pid windows always looked through | ℹ️ Info | A click on Pane's own status menu over a green button is still swallowed (REVIEW-FIX: not done) |
| Sources/PaneEngine/Arranger.swift | 587-598 | `refusalRetried` not cleared when a write fits (WR-03 partial) | ℹ️ Info | Documented in REVIEW-FIX. The re-dock scenario is fixed |
| Sources/PaneEngine/MinimumSizeLearner.swift | 14 | "Known limit": an app that lags more than 2 s on two writes is learned | ℹ️ Info | Now per window and session only (CR-02), so the damage is bounded |
| build/Pane-0.3.0.dmg | — | built 2026-10-26 08:16, before every UAT, gap and review fix | ⚠️ Warning | Rebuild before any tester distribution (release held for the Transom rename) |
| .planning/ROADMAP.md | Phase 3 | 03-18..03-22 still `[ ]`, "17/22 plans executed" | ℹ️ Info | Bookkeeping for the orchestrator |
| .planning/REQUIREMENTS.md | 29, 172 | WIN-07 `[ ]` / Pending | ⚠️ Warning | Live-verified now (UAT 4); tick it |
| deferred-items.md (03-18) | — | "Desktop-centre green dock no-op" is put down to `.tile(_, .center)` | ℹ️ Info | `Planner.dockTarget` turns a centre target into an edge band (Planner.swift:73-78), so the beep is more likely D-26 room. Re-check (human) |
| deferred-items.md (03-19, 03-22) | — | a silent D-26 refusal with Dock enabled; notices never logged | ℹ️ Info | Hard to diagnose; no correctness impact |

### Human Verification Required

These items are also in the frontmatter `human_verification` list (8 items). They run in the Tart VM with the final build (HEAD 159a77b), except the last two, which need the host's second display.

1. **Green button by hand (G-03-4 after CR-01).** Plain click on docked and floating windows, then Option-click. Expected: toggles, no fullscreen; Option zooms, then D-33 returns the window.
2. **Menus and Dock over a green button (CR-01).** Expected: the menu or Dock owns the click.
3. **Gap drag by hand (UAT 3).** Expected: smooth, no snap-back, the split sticks.
4. **UAT 6 and 7 re-run (G-03-5).** Expected: B and C dock; the menu enables Dock; split-finder docks when there is room.
5. **UAT 15 re-run (G-03-6 after CR-02).** Expected: Reminders floats, Notes keeps its tile, and no Reminders entry in min-size-hints.json.
6. **Option-zoomed floater, then a plain green click.** Expected: it docks, or D-26 refuses for lack of room. Confirms or refutes the deferred-items cause.
7. **Host, two displays: Hide Desktop (UAT 16).**
8. **Host, two displays and two Spaces: relaunch (UAT 17).** Expected to fail its Space half until the gap below is closed.

### Gaps Summary

**One gap blocks the goal contract: SAFE-06 / SC4 for Spaces that are not shown at launch.** Quit and relaunch keep the shown Space's layout (UAT 10). A desk on any other Space loses its docked windows every time, and the user's layout there is silently wiped. `LayoutRestore.reattach` runs once, at the first complete inventory, and closes every saved window that is not tracked yet. Windows on a hidden Space are very likely not in AXWindows at that point. The engine test that should catch this passes only because the fake reports windows on hidden Spaces. Phase 3 introduced one layout per display and Space (03-05), and its scope note keeps restore with unchanged IDs while apps keep running in Phase 3. VIEW-04 (Phase 8) covers re-matching after a reboot or app relaunch, so Phase 8 does not own this case. Phase 6 SC3 ("each Space keeps its own layout") is about switching, which UAT 15 already passed here. Neither later phase is a clear, specific owner, so this stays a gap.

**This may be deliberate.** If you decide multi-Space relaunch restore belongs in Phase 6 (Spaces & Displays), accept the deviation with an override instead of planning a fix:

```yaml
overrides:
  - must_have: "SC4 / SAFE-06: quitting and relaunching Pane while apps keep running brings each layout back with the same windows in their tiles"
    reason: "Only the shown Space's layout is restored in Phase 3; off-Space desks need Phase 6's SpacesProvider"
    accepted_by: "Ken Scott"
    accepted_at: "<ISO timestamp>"
```

If you accept it, also add the case to Phase 6's success criteria, so it has an owner.

The four UAT gaps G-03-3/4/5/6 are closed in code with passing tests, and the review's 2 critical and 5 warning findings are fixed and tested. G-03-4's final rule (after CR-01) has not been seen live, so SC1 stays with a human until the green-button re-check. The remaining items are hand-feel and live re-runs with the final build, plus the two second-display tests.

---

_Verified: 2026-10-27T01:18:02Z_
_Verifier: Claude (gsd-verifier)_
