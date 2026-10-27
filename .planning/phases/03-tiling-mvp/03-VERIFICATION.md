---
phase: 03-tiling-mvp
verified: 2026-10-27T18:18:26Z
status: passed
score: 17/17 must-haves verified
covered_files: [".github/workflows/ci.yml",".planning/phases/03-tiling-mvp/03-01-PLAN.md",".planning/phases/03-tiling-mvp/03-01-SUMMARY.md",".planning/phases/03-tiling-mvp/03-02-PLAN.md",".planning/phases/03-tiling-mvp/03-02-SUMMARY.md",".planning/phases/03-tiling-mvp/03-03-PLAN.md",".planning/phases/03-tiling-mvp/03-03-SUMMARY.md",".planning/phases/03-tiling-mvp/03-04-PLAN.md",".planning/phases/03-tiling-mvp/03-04-SUMMARY.md",".planning/phases/03-tiling-mvp/03-05-PLAN.md",".planning/phases/03-tiling-mvp/03-05-SUMMARY.md",".planning/phases/03-tiling-mvp/03-06-PLAN.md",".planning/phases/03-tiling-mvp/03-06-SUMMARY.md",".planning/phases/03-tiling-mvp/03-07-PLAN.md",".planning/phases/03-tiling-mvp/03-07-SUMMARY.md",".planning/phases/03-tiling-mvp/03-08-PLAN.md",".planning/phases/03-tiling-mvp/03-08-SUMMARY.md",".planning/phases/03-tiling-mvp/03-09-PLAN.md",".planning/phases/03-tiling-mvp/03-09-SUMMARY.md",".planning/phases/03-tiling-mvp/03-10-PLAN.md",".planning/phases/03-tiling-mvp/03-10-SUMMARY.md",".planning/phases/03-tiling-mvp/03-11-PLAN.md",".planning/phases/03-tiling-mvp/03-11-SUMMARY.md",".planning/phases/03-tiling-mvp/03-12-PLAN.md",".planning/phases/03-tiling-mvp/03-12-SUMMARY.md",".planning/phases/03-tiling-mvp/03-13-PLAN.md",".planning/phases/03-tiling-mvp/03-13-SUMMARY.md",".planning/phases/03-tiling-mvp/03-14-PLAN.md",".planning/phases/03-tiling-mvp/03-14-SUMMARY.md",".planning/phases/03-tiling-mvp/03-15-PLAN.md",".planning/phases/03-tiling-mvp/03-15-SUMMARY.md",".planning/phases/03-tiling-mvp/03-16-PLAN.md",".planning/phases/03-tiling-mvp/03-16-SUMMARY.md",".planning/phases/03-tiling-mvp/03-17-PLAN.md",".planning/phases/03-tiling-mvp/03-17-SUMMARY.md",".planning/phases/03-tiling-mvp/03-18-PLAN.md",".planning/phases/03-tiling-mvp/03-18-SUMMARY.md",".planning/phases/03-tiling-mvp/03-19-PLAN.md",".planning/phases/03-tiling-mvp/03-19-SUMMARY.md",".planning/phases/03-tiling-mvp/03-20-PLAN.md",".planning/phases/03-tiling-mvp/03-20-SUMMARY.md",".planning/phases/03-tiling-mvp/03-21-PLAN.md",".planning/phases/03-tiling-mvp/03-21-SUMMARY.md",".planning/phases/03-tiling-mvp/03-22-PLAN.md",".planning/phases/03-tiling-mvp/03-22-SUMMARY.md",".planning/phases/03-tiling-mvp/03-23-PLAN.md",".planning/phases/03-tiling-mvp/03-23-SUMMARY.md",".planning/phases/03-tiling-mvp/03-24-PLAN.md",".planning/phases/03-tiling-mvp/03-24-SUMMARY.md",".planning/phases/03-tiling-mvp/03-25-PLAN.md",".planning/phases/03-tiling-mvp/03-25-SUMMARY.md",".planning/phases/03-tiling-mvp/03-26-PLAN.md",".planning/phases/03-tiling-mvp/03-26-SUMMARY.md","Package.resolved","Package.swift","Sources/PaneEngine/Arranger+Commands.swift","Sources/PaneEngine/Arranger.swift","Sources/PaneEngine/CloseRule.swift","Sources/PaneEngine/Command.swift","Sources/PaneEngine/ConflictPolicy.swift","Sources/PaneEngine/DragSession.swift","Sources/PaneEngine/GapHandles.swift","Sources/PaneEngine/LayoutFile.swift","Sources/PaneEngine/LayoutRestore.swift","Sources/PaneEngine/LifecycleSync.swift","Sources/PaneEngine/MinimumSizeLearner.swift","Sources/PaneEngine/Notice.swift","Sources/PaneEngine/PaneURL.swift","Sources/PaneEngine/PendingFocus.swift","Sources/PaneEngine/PermissionReducer.swift","Sources/PaneEngine/Planner.swift","Sources/PaneEngine/Recovery.swift","Sources/PaneEngine/WindowSnapshot.swift","Sources/PaneEngine/WindowSystem.swift","Sources/PaneEngine/WindowTracker.swift","Sources/PaneFixtureApp/main.swift","Sources/PaneMac/AX/AXAppThread.swift","Sources/PaneMac/AX/AXSnapshotReader.swift","Sources/PaneMac/AX/MenuPress.swift","Sources/PaneMac/AXWindowSystem.swift","Sources/PaneMac/AppDelegate.swift","Sources/PaneMac/ArrangeController.swift","Sources/PaneMac/CGWindowList.swift","Sources/PaneMac/ConflictController.swift","Sources/PaneMac/Displays.swift","Sources/PaneMac/GapPreference.swift","Sources/PaneMac/Input/DragFramePoller.swift","Sources/PaneMac/Input/GreenButton.swift","Sources/PaneMac/Input/Hotkeys.swift","Sources/PaneMac/Input/InputTap.swift","Sources/PaneMac/LayoutStore.swift","Sources/PaneMac/MinimumHintsStore.swift","Sources/PaneMac/Overlay/GapHandlePanels.swift","Sources/PaneMac/Overlay/NoticeQueue.swift","Sources/PaneMac/Overlay/PreviewPanel.swift","Sources/PaneMac/Overlay/PreviewStyle.swift","Sources/PaneMac/Overlay/Toast.swift","Sources/PaneMac/PaneMacApp.swift","Sources/PaneMac/Shell/CommandMenu.swift","Sources/PaneMac/Shell/ConflictCopy.swift","Sources/PaneMac/Shell/MenuCopy.swift","Sources/PaneMac/Shell/NoticeCopy.swift","Sources/PaneMac/Shell/StatusItemController.swift","Sources/PaneMac/WindowManagerSettings.swift","Sources/PaneModel/DesktopLayer.swift","Sources/PaneModel/DropZones.swift","Sources/PaneModel/IDs.swift","Sources/PaneModel/LayoutTree.swift","Sources/PaneModel/Neighbours.swift","Sources/PaneModel/Resolve.swift","Sources/PaneModel/Snap.swift","Sources/PaneModel/TreeEdits.swift","Sources/PaneModel/Undo.swift","Sources/PaneModel/World.swift","Sources/PanePrivate/SkyLightSpaces.swift","Sources/PaneTestSupport/FakeWindowSystem.swift","Tests/PaneEngineTests/ArrangerCommandTests.swift","Tests/PaneEngineTests/ArrangerDesktopTests.swift","Tests/PaneEngineTests/ArrangerDragTests.swift","Tests/PaneEngineTests/ArrangerExclusionTests.swift","Tests/PaneEngineTests/ArrangerFinderTests.swift","Tests/PaneEngineTests/ArrangerFocusTests.swift","Tests/PaneEngineTests/ArrangerGreenButtonTests.swift","Tests/PaneEngineTests/ArrangerLifecycleTests.swift","Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift","Tests/PaneEngineTests/ArrangerPauseTests.swift","Tests/PaneEngineTests/ArrangerReflowTests.swift","Tests/PaneEngineTests/ArrangerResizeTests.swift","Tests/PaneEngineTests/ArrangerRestoreTests.swift","Tests/PaneEngineTests/ArrangerSpacesTests.swift","Tests/PaneEngineTests/CommandTests.swift","Tests/PaneEngineTests/ConflictPolicyTests.swift","Tests/PaneEngineTests/DragSessionTests.swift","Tests/PaneEngineTests/FrameScenarioTests.swift","Tests/PaneEngineTests/GapHandleGeometryTests.swift","Tests/PaneEngineTests/LifecycleSyncTests.swift","Tests/PaneEngineTests/MinimumSizeLearnerTests.swift","Tests/PaneEngineTests/PaneURLTests.swift","Tests/PaneEngineTests/PendingFocusTests.swift","Tests/PaneEngineTests/PermissionReducerTests.swift","Tests/PaneEngineTests/PlannerTests.swift","Tests/PaneEngineTests/RecoveryTests.swift","Tests/PaneEngineTests/TooBigDockedWindowTests.swift","Tests/PaneEngineTests/TrackerDisplayTests.swift","Tests/PaneEngineTests/WantedFrameTests.swift","Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift","Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift","Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift","Tests/PaneMacIntegrationTests/InputTapIntegrationTests.swift","Tests/PaneMacIntegrationTests/IntegrationSupport.swift","Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift","Tests/PaneMacIntegrationTests/QuitRestoreIntegrationTests.swift","Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift","Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift","Tests/PaneMacIntegrationTests/TitleBarDragIntegrationTests.swift","Tests/PaneMacTests/AppDelegateTests.swift","Tests/PaneMacTests/CapabilitiesTests.swift","Tests/PaneMacTests/CommandMenuTests.swift","Tests/PaneMacTests/ConflictControllerTests.swift","Tests/PaneMacTests/ConflictCopyTests.swift","Tests/PaneMacTests/GapPreferenceTests.swift","Tests/PaneMacTests/GreenButtonHitTests.swift","Tests/PaneMacTests/HotkeyTableTests.swift","Tests/PaneMacTests/LayoutStoreTests.swift","Tests/PaneMacTests/MenuCopyTests.swift","Tests/PaneMacTests/MenuPressTests.swift","Tests/PaneMacTests/MinimumHintsStoreTests.swift","Tests/PaneMacTests/NoScreenCaptureTests.swift","Tests/PaneMacTests/NoticeCopyTests.swift","Tests/PaneMacTests/NoticeQueueTests.swift","Tests/PaneMacTests/PreviewStyleTests.swift","Tests/PaneMacTests/TopmostWindowTests.swift","Tests/PaneMacTests/WakeTimerTests.swift","Tests/PaneMacTests/WindowManagerSettingsTests.swift","Tests/PaneModelTests/DesktopLayerTests.swift","Tests/PaneModelTests/DesktopLeafTests.swift","Tests/PaneModelTests/LayoutEditTests.swift","Tests/PaneModelTests/LifecycleTests.swift","Tests/PaneModelTests/NeighbourTests.swift","Tests/PaneModelTests/PersistenceTests.swift","Tests/PaneModelTests/ResolveFuzzTests.swift","Tests/PaneModelTests/ResolveTests.swift","Tests/PaneModelTests/ScenarioTests.swift","Tests/PaneModelTests/SkeletonTests.swift","Tests/PaneModelTests/SnapTests.swift","Tests/PaneModelTests/TabsTests.swift","Tests/PaneModelTests/TreeEditTests.swift","Tests/PaneModelTests/UndoTests.swift","Tests/PaneModelTests/WorldRekeyTests.swift","scripts/check-no-appkit.sh","scripts/release.sh","scripts/vm-live-test.sh","xcode/Pane-Info.plist","xcode/project.yml"]
covered_digest: "v3:sha256:4c5103cf6dc2e33b8fda066b4b44dd37b43647c60b122bae8c1191dd01fafac1"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 16/16
  gaps_closed:
    - "Previous human item 1 (03-26 review fixes CR-01, WR-01, WR-02 live): passed in the Tart VM on 0.3.11 (3c53e72)"
    - "Previous human item 5(a) (plain green click on a floater that exactly fills the Desktop tile): fixed by quick 261027-gqo (e0733c7..39e8e11). Planner.dockTarget ties the exact centre to the left edge (fx <= 0.5). Both new tests pass at HEAD and fail at e0733c7 (RED re-run in a scratch worktree, removed)"
    - "deferred-items 03-19 (no-room dock refusal is only a beep and a VoiceOver line): 307834b logs every .announce at info level"
    - "deferred-items 03-22 (notices never logged): 7e2b0a9 logs every notice in ArrangeController.post, and the effect runner's .notice case now goes through post"
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "G-03-9: closing a window removes it from Pane's tracking and layout.json (Safari keeps a Space-less, layer-0 CG entry for a closed window)"
    addressed_in: "Phase 6"
    evidence: "ROADMAP Phase 6 scope note: 'Also closes deferred G-03-9: a window whose only CG entry has no Space ... must count as closed, not alive'. User decision 2026-10-26. 03-23 review WR-03 already treats such an entry as not alive at restore and prune. CloseRule in a running session still waits for the entry to go"
  - truth: "Human items 2-5 (wanted-frame relaunch in the VM; UAT 16 and the display half of UAT 17 on the DELL second display, with WR-04; the Dock-tile-over-green-button case). User decision 2026-10-27: close Phase 3 without waiting for them. Human item 1 passed in the VM on 0.3.11; item 5(a) is fixed by quick 261027-gqo"
    addressed_in: "Re-check on the first Transom build (STATE.md Pending Todos)"
    evidence: "Headless tests cover each case: aDockedWindowsPreDockFrameSurvivesARelaunch, twoDisplaysWithTwoSpacesEach..., the CR-02 park tests. STATE.md Pending Todos lists the re-check"
advisory:
  - finding: "undockedWanted (WR-02 fix) is cleared only by Undo, forget and rekey. If a window is undocked by Float All or a shift-drag and then docked again by a drag or Dock instead of Undo, the old entry stays. A later Undo that docks that window again gives back the older pre-dock frame"
    category: other
    reason: "Found by reading Arranger.swift:905 and Arranger+Commands.swift:144. Worst case: Float later goes to a stale pre-dock frame. There is no overlap and no data loss. The code already marks the one-level limit with 'shortcut:' (Arranger.swift:112). To resolve, clear undockedWanted[id] wherever a window docks other than through undo"
    evidence_status: "none provided: no test or VM run shows it"
---

# Phase 3: Tiling MVP Verification Report

**Phase Goal:** As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp (the goal text is unchanged and was validated as a user story in earlier runs)
**Verified:** 2026-10-27T18:18:26Z
**Status:** passed. Human items 2-5 are deferred by the user's decision of 2026-10-27; see the frontmatter `deferred` list and STATE.md Pending Todos.
**Re-verification:** Yes, a regression re-run. It replaces dbdd094 (human_needed, 16/16). Since then: quick 261027-gqo (e0733c7..39e8e11), 307834b and 7e2b0a9 changed source; 3c53e72 recorded human item 1 passing on 0.3.11; e1d443a recorded the user's deferral. The changed code got a full check, including a RED re-run of the gqo tests on pre-fix code. Everything else got a regression check: one full headless run, plus the AppKit and anti-pattern scans.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| Drag a window by its title bar to an edge | A preview appears and the window docks on release, at any depth | `ArrangerDragTests` pass; UAT 2 live | VERIFIED |
| Windows open | New windows float on the Desktop tile and never auto-split | `PlannerTests` pass; UAT 14 re-run on 0.3.7 | VERIFIED |
| Windows close, minimise, go fullscreen | Neighbours reflow; minimised and fullscreen windows return | Reflow tests; UAT 3 and 4 re-runs; docked Safari Cmd-W freed its tile at once on 0.3.8 | VERIFIED |
| Resize by gap | Both sides follow, the split sticks, floaters keep their size | G-03-3 tests and `WantedFrameTests`; hand checks on 0.3.8 and 0.3.10 | VERIFIED |
| Green button | Each toggle moves the window visibly: docked floats to its pre-dock frame, floating docks, including a floater that fills the Desktop tile | `ArrangerGreenButtonTests` (incl. `aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt`); hand check on 0.3.10; review fixes in the VM on 0.3.11 | VERIFIED |
| Outcome: windows never overlap | A docked window that can't fit floats; a too-big floater doesn't float the desk; floaters stay inside the Desktop during a gap drag | `TooBigDockedWindowTests`, `RefusalRetryBoundTests`, `aFloaterWhoseMinimumIsAboveTheShrunkenDesktopNeverEndsBelowIt`; UAT 15 re-run; 0.3.10 hand check | VERIFIED (accepted T-03-58 overlap of a floater that can't shrink) |
| Layout survives a Pane relaunch | Each layout comes back, including after a locked start | 03-23, 03-24, 03-26; VM on 0.3.7, 0.3.8 and 0.3.9 | VERIFIED (display half and wanted-frame relaunch: deferred by the user) |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | SC1: title-bar drag docks with a preview at any depth; bypass moves freely; new windows float; the green button toggles docked/floating | ✓ VERIFIED | Unchanged since dbdd094 apart from truth 17. `float()` places the window via `Planner.floatFrame` at the clamped pre-dock frame or a centred 90% frame. Green-button tests pass in this run. Live: 0.3.10 hand check (G-03-4 resolved) and 0.3.11 VM run of the review fixes |
| 2 | SC2: close reflows; gap drag resizes both; gap size is settable; a window leaving fullscreen returns to its tile | ✓ VERIFIED | Regression: tests pass. UAT 3 and 4 re-runs; docked Safari Cmd-W on 0.3.8; gap drag by hand on 0.3.8 and 0.3.10 |
| 3 | SC3: menu and hotkeys through one dispatcher; undo; pause/resume; Restore all; `pane://restore` | ✓ VERIFIED | Regression: `PendingFocusTests` and `ArrangerCommandTests` pass. UAT 6 and 7 re-runs on 0.3.7 |
| 4 | SC4: quit restore; crash rescue; conflicts; quitting and relaunching with apps running brings each layout back | ✓ VERIFIED | Regression: restore suites pass. UAT 8, 9 and 11; VM on 0.3.8. The ConflictController's N7/N8 toasts still go through `ArrangeController.post` (PaneMacApp.swift:68), which now also logs them |
| 5 | SC5: works with zoom absent and Screen Recording denied; Developer ID signed and notarised; the grant survives updates | ✓ VERIFIED | Unchanged since dbdd094: stapled, Notarized Developer ID DMG; grant kept across 0.3.6..0.3.11 in the VM; UAT 12. ⚠️ The DMG predates the fixes (see Anti-Patterns) |
| 6 | SC6: swap, balance, rotate, flip, move and resize from the keyboard; snap floaters | ✓ VERIFIED | Regression: `LayoutEditTests`, `SnapTests` and `ArrangerCommandTests` pass. UAT 5 |
| 7 | SC7: hide/show the Desktop, arrange all, float all, Finder split, Don't Arrange; Option-click zoom; a minimised docked window returns | ✓ VERIFIED | Regression: tests pass, including `undoingFloatAllGivesBackThePreDockFrames`. UAT 6, 7 and 4 |
| 8 | G-03-3: a gap drag beside a pinned side moves that gap; no mid-drag event writes the pre-drag tiles | ✓ VERIFIED | Regression: tests pass. UAT re-run on 0.3.7, hand checks on 0.3.8 and 0.3.10 |
| 9 | G-03-5: a second window of an app with a docked window becomes the command target | ✓ VERIFIED | Regression: `PendingFocusTests` pass |
| 10 | G-03-6: a docked window that can't fit floats instead of overlapping; one too-big floater doesn't float the desk | ✓ VERIFIED | Regression: `TooBigDockedWindowTests.swift` unchanged and passing |
| 11 | G-03-8: desks on a Space not shown at relaunch keep their windows; a dormant window is pruned when it closes | ✓ VERIFIED | Regression: `ArrangerMultiDeskRestoreTests` pass. VM on 0.3.7..0.3.9 |
| 12 | G-03-10: a start while locked keeps every saved desk once the screen is unlocked | ✓ VERIFIED | AXWindowSystem.swift unchanged since dbdd094. `aStartWhileLockedKeepsEveryDeskOnceUnlocked` passes. VM on 0.3.9 |
| 13 | G-03-11: a gap drag that shrinks and then grows the Desktop returns floaters to their frames; a floater that refuses to shrink stops the drag at its real size | ✓ VERIFIED | Arranger.swift unchanged since dbdd094. `WantedFrameTests` pass. 0.3.10 hand check |
| 14 | G-03-4 (decision 2026-10-27): Float puts a docked window at its pre-dock frame clamped into the Desktop, or at a centred 90% frame; docking fills the tile, so every toggle moves the window | ✓ VERIFIED | See truth 1 |
| 15 | 03-26: wanted frames are saved in layout.json and validated like home frames; an older file loads with none; a floater moved while Pane was off keeps its real frame; a stranded saved wanted frame is dropped | ✓ VERIFIED | Regression: the save path (ArrangeController.swift `write()`, `wantedFrames: snapshot.wantedFrames`) and restore path are untouched by 307834b/7e2b0a9. The 03-26 tests pass. The live relaunch is deferred by the user |
| 16 | 03-26 review fixes: CR-01, WR-01, WR-02 | ✓ VERIFIED | RED-confirmed in dbdd094. All 8 `WantedFrameTests` pass in this run. Live: passed in the VM on 0.3.11 (3c53e72) |
| 17 | quick 261027-gqo (TILE-06): a plain green click on a floater that exactly fills the Desktop tile docks it, with no beep; Dock at a tile's exact centre ties to the left edge | ✓ VERIFIED | Planner.swift:108 `fx <= 0.5 ? .left : .right`; the vertical tie (`fy < 0.5`) is not reached at the exact centre because the horizontal branch wins on `<=`. `dockTargetAtTheDesktopsExactCentreGoesLeft` and `aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt` pass at HEAD. **RED re-run:** in a scratch worktree at e0733c7 (tests, no fix), both fail: the Planner test gets the right edge, and the Arranger test fails at `docked.maxX <= newDesktop.minX`. Worktree removed. Note: at e0733c7 the Arranger test's no-beep and docked checks already passed, so before the fix the headless click docked on the right rather than beeping. The VM beep logged in deferred-items 03-18 was the D-26 no-room refusal (460 pt minimums), as the updated deferred-items entry says |

**Score:** 17/17 truths verified (0 present but behaviour-unverified). The four remaining live checks are deferred by the user, not open.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | G-03-9: a closed Safari window stays tracked in a running session (its Space-less CG ghost blocks CloseRule) | Phase 6 | The ROADMAP Phase 6 scope note names G-03-9. User decision 2026-10-26 |
| 2 | Human items 2-5: wanted-frame relaunch (VM); UAT 16 and the display half of UAT 17 with WR-04 (DELL second display); Dock tile over a docked window's green button (VM) | First Transom build | User decision 2026-10-27, recorded in e1d443a and STATE.md Pending Todos. Headless tests cover each case and pass in this run |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | `undockedWanted` is not cleared when a window docks again by drag or Dock rather than Undo. A later Undo can give back an older pre-dock frame | other | Carried from dbdd094. New scope with no deterministic evidence. Worst case is a stale Float target; there is no overlap |

No new advisories from 261027-gqo, 307834b or 7e2b0a9.

### Required Artifacts

All artifacts from dbdd094 are still present (142 implementation files in `covered_files`, none missing) and compile. Changed since dbdd094:

| Artifact | Change | Status |
| -------- | ------ | ------ |
| `Sources/PaneEngine/Planner.swift` | `dockTarget` exact-centre tie goes left | ✓ VERIFIED |
| `Sources/PaneMac/ArrangeController.swift` | `post` logs each notice; `.announce` logged at info; effect runner's `.notice` goes through `post` | ✓ VERIFIED |
| `Tests/PaneEngineTests/PlannerTests.swift` | `dockTargetAtTheDesktopsExactCentreGoesLeft` | ✓ VERIFIED (RED-confirmed) |
| `Tests/PaneEngineTests/ArrangerGreenButtonTests.swift` | `aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt` | ✓ VERIFIED (RED-confirmed) |

### Key Link Verification

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| Arranger green button / Dock | `Planner.dockTarget` | unchanged call sites; the tie rule is inside `dockTarget` | WIRED |
| Effect runner `.notice` | `ArrangeController.post` -> logger + `notices.post` -> `present` | ArrangeController.swift:410 `post(notice)`; :85-86 | WIRED (no double queueing: `post` is the only enqueue on this path) |
| ConflictController N7/N8 | `ArrangeController.post` | PaneMacApp.swift:68 | WIRED |
| Effect runner `.announce` | logger + `postAnnouncement` | ArrangeController.swift:402-404 | WIRED |
| All 7 links listed in dbdd094 | — | files carrying them (AXWindowSystem, Arranger, LayoutFile, LayoutStore) unchanged; ArrangeController save/restore lines untouched | WIRED (regression) |

### Data-Flow Trace (Level 4)

Unchanged since dbdd094: wanted frames, floater floors, layout.json wanted frames and the restore gate all flow from real sources. The new log lines read the same `notice` and `text` values that reach the toast and VoiceOver. `Notice` carries `WindowRef`s, counts and `Conflict` values, not window titles, so logging it `.public` exposes no window content.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Live gate | `PANE_LIVE` not in the environment (checked, count 0) | the integration target's 42 tests in 20 suites passed as skipped | PASS |
| Headless suites (one full run) | `swift test` at e1d443a | exit 0. Swift Testing: 193 tests in 20 suites, 198 in 30 suites, 534 in 53 suites (PaneEngineTests, up 2 from 532) = 925 passed, 0 failures; plus the 42 gated live tests. XCTest: 0 tests per bundle. `FreezeTestTests/itResumesByItself` passed | PASS |
| gqo tests catch the bug | `swift test --filter "aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt\|dockTargetAtTheDesktopsExactCentreGoesLeft"` in a scratch worktree at e0733c7 | 2 tests fail, exit 1. Worktree removed | PASS (RED confirmed) |
| No AppKit in Model and Engine | `scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | PASS |
| Live AX suites, VM | not run (no PANE_LIVE, no Pane launch, no VM, per the run's rules) | VM record in 03-UAT.md covers 0.3.7..0.3.11 | SKIP |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist, and no plan declares a probe. Not applicable.

### Requirements Coverage

All 26 phase IDs are claimed by at least one plan; quick 261027-gqo claims TILE-06. None is orphaned. REQUIREMENTS.md marks all 26 as Complete.

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| TILE-01, TILE-02 | SATISFIED | UAT 2; drag tests |
| TILE-03 | SATISFIED | UAT 3; docked Safari close on 0.3.8 |
| TILE-04 | SATISFIED | UAT 3 Gaps menu |
| TILE-05 | SATISFIED | G-03-3 and G-03-11 tests; hand checks on 0.3.8 and 0.3.10 |
| TILE-06 | SATISFIED | green-button tests incl. the gqo test; 0.3.10 hand check; Dock-tile-over-button case deferred by the user |
| TILE-07 | SATISFIED | UAT 14; wanted-frame tests; CR-01 live on 0.3.11 |
| TILE-08 | SATISFIED | UAT 6 Pause/Resume |
| TILE-09 | SATISFIED | UAT 6; Float and Undo tests; WR-01/WR-02 live on 0.3.11 |
| TILE-10 | SATISFIED | UAT 12 |
| TILE-11..14 | SATISFIED | UAT 5; edit and snap tests |
| TILE-15, TILE-16, TILE-18 | SATISFIED | UAT 6 and 7 |
| TILE-17 | SATISFIED | UAT 7 re-run |
| TILE-19 | SATISFIED | UAT 4 re-run; 0.3.8 hand check |
| TILE-20 | SATISFIED | UAT 4 |
| WIN-07 | SATISFIED | UAT 4 |
| SAFE-01, SAFE-02, SAFE-03, SAFE-04 | SATISFIED | UAT 8, 9, 7, 11 |
| SAFE-06 | SATISFIED (display half and wanted-frame relaunch deferred by the user) | 03-23, 03-24, 03-26; VM 0.3.7..0.3.9 |

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| PlannerTests.swift (new test) | TILE-06 | 1 new | 0 | no | Value (drop target) | OK; RED-confirmed |
| ArrangerGreenButtonTests.swift (new test) | TILE-06 | 1 new | 0 | no | Behavioral (no beep, setFrame, history depth, left of the new Desktop) | OK; RED-confirmed |
| WantedFrameTests.swift | TILE-05, TILE-07, TILE-09 | 8 | 0 | no | Behavioral | OK |
| PaneMacIntegrationTests (live) | various | gated | 42 skipped (`.enabled(if: IntegrationEnv.trusted)`) | no | Behavioral | By design |

The gqo change only added test lines; no existing expectation was replaced. 307834b and 7e2b0a9 add no tests: they add log lines and route one call through an existing function, and the toast path is still covered by `NoticeQueueTests`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Planner.swift, ArrangeController.swift, PlannerTests.swift, ArrangerGreenButtonTests.swift | — | TBD/FIXME/XXX/TODO/HACK | none | — |
| Sources/PaneEngine/Arranger.swift | 112 | `shortcut:` one-level `undockedWanted` (documented WR-02 limit) | ℹ️ Info | Carried |
| build/Pane-0.3.0.dmg | — | built 2026-10-26 08:16, before the UAT, gap and review fixes | ⚠️ Warning | Rebuild and notarise before any tester distribution or release (release held for the Transom rename) |
| 03-REVIEW-03-26.md | IN-01..IN-06 | open Info items (0x0 frames pass validation; `= [:]` defaults; `liveGap` not cleared on pause; minor test gaps) | ℹ️ Info (open) | Carried |
| 03-REVIEW-03-23.md, 03-REVIEW.md | IN-01..03 | open Info items | ℹ️ Info (open) | Carried |
| Tests/PaneMacTests/FreezeTestTests.swift | 58 | timing-sensitive | ℹ️ Info | Passed in this run |

### Human Verification Required

None open. The four remaining live checks (previous items 2, 3, 4 and 5(b)) are deferred by the user to the first Transom build; see Deferred Items row 2 and STATE.md Pending Todos.

### Gaps Summary

No gaps. Since dbdd094, the remaining review-fix live check passed in the VM on 0.3.11, the Desktop-centre green-click edge is fixed with RED-confirmed tests, and the 03-19 and 03-22 logging items are closed. The full headless suite passes (925 Swift Testing tests, 0 failures). The user decided on 2026-10-27 to close Phase 3 without the four remaining live checks, which stay recorded for the first Transom build.

Before ship: rebuild and notarise the DMG, because the current one predates every fix.

---

_Verified: 2026-10-27T18:18:26Z_
_Verifier: Claude (gsd-verifier)_
