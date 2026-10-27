---
phase: 03-tiling-mvp
verified: 2026-10-27T16:38:36Z
status: human_needed
score: 16/16 must-haves verified
covered_files: [".github/workflows/ci.yml",".planning/phases/03-tiling-mvp/03-01-PLAN.md",".planning/phases/03-tiling-mvp/03-01-SUMMARY.md",".planning/phases/03-tiling-mvp/03-02-PLAN.md",".planning/phases/03-tiling-mvp/03-02-SUMMARY.md",".planning/phases/03-tiling-mvp/03-03-PLAN.md",".planning/phases/03-tiling-mvp/03-03-SUMMARY.md",".planning/phases/03-tiling-mvp/03-04-PLAN.md",".planning/phases/03-tiling-mvp/03-04-SUMMARY.md",".planning/phases/03-tiling-mvp/03-05-PLAN.md",".planning/phases/03-tiling-mvp/03-05-SUMMARY.md",".planning/phases/03-tiling-mvp/03-06-PLAN.md",".planning/phases/03-tiling-mvp/03-06-SUMMARY.md",".planning/phases/03-tiling-mvp/03-07-PLAN.md",".planning/phases/03-tiling-mvp/03-07-SUMMARY.md",".planning/phases/03-tiling-mvp/03-08-PLAN.md",".planning/phases/03-tiling-mvp/03-08-SUMMARY.md",".planning/phases/03-tiling-mvp/03-09-PLAN.md",".planning/phases/03-tiling-mvp/03-09-SUMMARY.md",".planning/phases/03-tiling-mvp/03-10-PLAN.md",".planning/phases/03-tiling-mvp/03-10-SUMMARY.md",".planning/phases/03-tiling-mvp/03-11-PLAN.md",".planning/phases/03-tiling-mvp/03-11-SUMMARY.md",".planning/phases/03-tiling-mvp/03-12-PLAN.md",".planning/phases/03-tiling-mvp/03-12-SUMMARY.md",".planning/phases/03-tiling-mvp/03-13-PLAN.md",".planning/phases/03-tiling-mvp/03-13-SUMMARY.md",".planning/phases/03-tiling-mvp/03-14-PLAN.md",".planning/phases/03-tiling-mvp/03-14-SUMMARY.md",".planning/phases/03-tiling-mvp/03-15-PLAN.md",".planning/phases/03-tiling-mvp/03-15-SUMMARY.md",".planning/phases/03-tiling-mvp/03-16-PLAN.md",".planning/phases/03-tiling-mvp/03-16-SUMMARY.md",".planning/phases/03-tiling-mvp/03-17-PLAN.md",".planning/phases/03-tiling-mvp/03-17-SUMMARY.md",".planning/phases/03-tiling-mvp/03-18-PLAN.md",".planning/phases/03-tiling-mvp/03-18-SUMMARY.md",".planning/phases/03-tiling-mvp/03-19-PLAN.md",".planning/phases/03-tiling-mvp/03-19-SUMMARY.md",".planning/phases/03-tiling-mvp/03-20-PLAN.md",".planning/phases/03-tiling-mvp/03-20-SUMMARY.md",".planning/phases/03-tiling-mvp/03-21-PLAN.md",".planning/phases/03-tiling-mvp/03-21-SUMMARY.md",".planning/phases/03-tiling-mvp/03-22-PLAN.md",".planning/phases/03-tiling-mvp/03-22-SUMMARY.md",".planning/phases/03-tiling-mvp/03-23-PLAN.md",".planning/phases/03-tiling-mvp/03-23-SUMMARY.md",".planning/phases/03-tiling-mvp/03-24-PLAN.md",".planning/phases/03-tiling-mvp/03-24-SUMMARY.md",".planning/phases/03-tiling-mvp/03-25-PLAN.md",".planning/phases/03-tiling-mvp/03-25-SUMMARY.md",".planning/phases/03-tiling-mvp/03-26-PLAN.md",".planning/phases/03-tiling-mvp/03-26-SUMMARY.md","Package.resolved","Package.swift","Sources/PaneEngine/Arranger+Commands.swift","Sources/PaneEngine/Arranger.swift","Sources/PaneEngine/CloseRule.swift","Sources/PaneEngine/Command.swift","Sources/PaneEngine/ConflictPolicy.swift","Sources/PaneEngine/DragSession.swift","Sources/PaneEngine/GapHandles.swift","Sources/PaneEngine/LayoutFile.swift","Sources/PaneEngine/LayoutRestore.swift","Sources/PaneEngine/LifecycleSync.swift","Sources/PaneEngine/MinimumSizeLearner.swift","Sources/PaneEngine/Notice.swift","Sources/PaneEngine/PaneURL.swift","Sources/PaneEngine/PendingFocus.swift","Sources/PaneEngine/PermissionReducer.swift","Sources/PaneEngine/Planner.swift","Sources/PaneEngine/Recovery.swift","Sources/PaneEngine/WindowSnapshot.swift","Sources/PaneEngine/WindowSystem.swift","Sources/PaneEngine/WindowTracker.swift","Sources/PaneFixtureApp/main.swift","Sources/PaneMac/AX/AXAppThread.swift","Sources/PaneMac/AX/AXSnapshotReader.swift","Sources/PaneMac/AX/MenuPress.swift","Sources/PaneMac/AXWindowSystem.swift","Sources/PaneMac/AppDelegate.swift","Sources/PaneMac/ArrangeController.swift","Sources/PaneMac/CGWindowList.swift","Sources/PaneMac/ConflictController.swift","Sources/PaneMac/Displays.swift","Sources/PaneMac/GapPreference.swift","Sources/PaneMac/Input/DragFramePoller.swift","Sources/PaneMac/Input/GreenButton.swift","Sources/PaneMac/Input/Hotkeys.swift","Sources/PaneMac/Input/InputTap.swift","Sources/PaneMac/LayoutStore.swift","Sources/PaneMac/MinimumHintsStore.swift","Sources/PaneMac/Overlay/GapHandlePanels.swift","Sources/PaneMac/Overlay/NoticeQueue.swift","Sources/PaneMac/Overlay/PreviewPanel.swift","Sources/PaneMac/Overlay/PreviewStyle.swift","Sources/PaneMac/Overlay/Toast.swift","Sources/PaneMac/PaneMacApp.swift","Sources/PaneMac/Shell/CommandMenu.swift","Sources/PaneMac/Shell/ConflictCopy.swift","Sources/PaneMac/Shell/MenuCopy.swift","Sources/PaneMac/Shell/NoticeCopy.swift","Sources/PaneMac/Shell/StatusItemController.swift","Sources/PaneMac/WindowManagerSettings.swift","Sources/PaneModel/DesktopLayer.swift","Sources/PaneModel/DropZones.swift","Sources/PaneModel/IDs.swift","Sources/PaneModel/LayoutTree.swift","Sources/PaneModel/Neighbours.swift","Sources/PaneModel/Resolve.swift","Sources/PaneModel/Snap.swift","Sources/PaneModel/TreeEdits.swift","Sources/PaneModel/Undo.swift","Sources/PaneModel/World.swift","Sources/PanePrivate/SkyLightSpaces.swift","Sources/PaneTestSupport/FakeWindowSystem.swift","Tests/PaneEngineTests/ArrangerCommandTests.swift","Tests/PaneEngineTests/ArrangerDesktopTests.swift","Tests/PaneEngineTests/ArrangerDragTests.swift","Tests/PaneEngineTests/ArrangerExclusionTests.swift","Tests/PaneEngineTests/ArrangerFinderTests.swift","Tests/PaneEngineTests/ArrangerFocusTests.swift","Tests/PaneEngineTests/ArrangerGreenButtonTests.swift","Tests/PaneEngineTests/ArrangerLifecycleTests.swift","Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift","Tests/PaneEngineTests/ArrangerPauseTests.swift","Tests/PaneEngineTests/ArrangerReflowTests.swift","Tests/PaneEngineTests/ArrangerResizeTests.swift","Tests/PaneEngineTests/ArrangerRestoreTests.swift","Tests/PaneEngineTests/ArrangerSpacesTests.swift","Tests/PaneEngineTests/CommandTests.swift","Tests/PaneEngineTests/ConflictPolicyTests.swift","Tests/PaneEngineTests/DragSessionTests.swift","Tests/PaneEngineTests/FrameScenarioTests.swift","Tests/PaneEngineTests/GapHandleGeometryTests.swift","Tests/PaneEngineTests/LifecycleSyncTests.swift","Tests/PaneEngineTests/MinimumSizeLearnerTests.swift","Tests/PaneEngineTests/PaneURLTests.swift","Tests/PaneEngineTests/PendingFocusTests.swift","Tests/PaneEngineTests/PermissionReducerTests.swift","Tests/PaneEngineTests/PlannerTests.swift","Tests/PaneEngineTests/RecoveryTests.swift","Tests/PaneEngineTests/TooBigDockedWindowTests.swift","Tests/PaneEngineTests/TrackerDisplayTests.swift","Tests/PaneEngineTests/WantedFrameTests.swift","Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift","Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift","Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift","Tests/PaneMacIntegrationTests/InputTapIntegrationTests.swift","Tests/PaneMacIntegrationTests/IntegrationSupport.swift","Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift","Tests/PaneMacIntegrationTests/QuitRestoreIntegrationTests.swift","Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift","Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift","Tests/PaneMacIntegrationTests/TitleBarDragIntegrationTests.swift","Tests/PaneMacTests/AppDelegateTests.swift","Tests/PaneMacTests/CapabilitiesTests.swift","Tests/PaneMacTests/CommandMenuTests.swift","Tests/PaneMacTests/ConflictControllerTests.swift","Tests/PaneMacTests/ConflictCopyTests.swift","Tests/PaneMacTests/GapPreferenceTests.swift","Tests/PaneMacTests/GreenButtonHitTests.swift","Tests/PaneMacTests/HotkeyTableTests.swift","Tests/PaneMacTests/LayoutStoreTests.swift","Tests/PaneMacTests/MenuCopyTests.swift","Tests/PaneMacTests/MenuPressTests.swift","Tests/PaneMacTests/MinimumHintsStoreTests.swift","Tests/PaneMacTests/NoScreenCaptureTests.swift","Tests/PaneMacTests/NoticeCopyTests.swift","Tests/PaneMacTests/NoticeQueueTests.swift","Tests/PaneMacTests/PreviewStyleTests.swift","Tests/PaneMacTests/TopmostWindowTests.swift","Tests/PaneMacTests/WakeTimerTests.swift","Tests/PaneMacTests/WindowManagerSettingsTests.swift","Tests/PaneModelTests/DesktopLayerTests.swift","Tests/PaneModelTests/DesktopLeafTests.swift","Tests/PaneModelTests/LayoutEditTests.swift","Tests/PaneModelTests/LifecycleTests.swift","Tests/PaneModelTests/NeighbourTests.swift","Tests/PaneModelTests/PersistenceTests.swift","Tests/PaneModelTests/ResolveFuzzTests.swift","Tests/PaneModelTests/ResolveTests.swift","Tests/PaneModelTests/ScenarioTests.swift","Tests/PaneModelTests/SkeletonTests.swift","Tests/PaneModelTests/SnapTests.swift","Tests/PaneModelTests/TabsTests.swift","Tests/PaneModelTests/TreeEditTests.swift","Tests/PaneModelTests/UndoTests.swift","Tests/PaneModelTests/WorldRekeyTests.swift","scripts/check-no-appkit.sh","scripts/release.sh","scripts/vm-live-test.sh","xcode/Pane-Info.plist","xcode/project.yml"]
covered_digest: "v3:sha256:d030f333081dcb62629412d0f16108e226939d4f12cfc5e02ac933813fd226e0"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 11/11
  gaps_closed:
    - "G-03-10 (SAFE-06, locked start): 03-24 counts a sweep as the initial one only when no pause happened during it (AXWindowSystem pauseCount, initialRefreshComplete). The fake mirrors the rule, and aStartWhileLockedKeepsEveryDeskOnceUnlocked passes. VM re-check on 0.3.9 kept both Space desks after a user unlock"
    - "G-03-11 (floaters stay shrunk): 03-25 added wanted frames and floater floors. WantedFrameTests pass. The user's hand check on 0.3.10 showed the drag stopping at the floaters' floor, and all 9 floaters returned to their exact start frames"
    - "G-03-4 reopened (toggle invisible on a desk's only docked window): 03-25 makes Float go to the pre-dock frame or a centred 90% frame, and 03-26 persists the frames. The user's hand check on 0.3.10 passed"
    - "03-26 review CR-01, WR-01, WR-02: fixed in 7d2bef3, 75d2424 and 9cb65bd. I re-ran the new WantedFrameTests at ef6d12e (before the fixes): the 4 new tests fail there and pass at HEAD"
    - "Previous human items 1 (green button by hand), 2 (gap drag by hand) and 5 (docked Safari close) passed in the VM on 0.3.8 and 0.3.10, except the remainder carried as human item 5 below"
    - "Previous coincidental-reliance item (restore with a nil CG list treated as 'nothing alive'): fixed by 03-23 review CR-03. A nil list now keeps every saved window (Arranger.swift:224-233, LayoutRestore.swift:22), and aRestoreWithAnUnknownCGListKeepsEverySavedWindow passes"
    - "03-UAT.md G-03-3, G-03-5, G-03-6 and G-03-8 are now marked resolved, with resolved_by, because the VM re-runs and hand checks support closing them"
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "G-03-9: closing a window removes it from Pane's tracking and layout.json (Safari keeps a Space-less, layer-0 CG entry for a closed window)"
    addressed_in: "Phase 6"
    evidence: "ROADMAP Phase 6 scope note: 'Also closes deferred G-03-9: a window whose only CG entry has no Space ... must count as closed, not alive'. User decision 2026-10-26. 03-23 review WR-03 already treats such an entry as not alive at restore and prune. CloseRule in a running session still waits for the entry to go"
advisory:
  - finding: "undockedWanted (WR-02 fix) is cleared only by Undo, forget and rekey. If a window is undocked by Float All or a shift-drag and then docked again by a drag or Dock instead of Undo, the old entry stays. A later Undo that docks that window again gives back the older pre-dock frame"
    category: other
    reason: "Found by reading Arranger.swift:905 and Arranger+Commands.swift:144. Worst case: Float later goes to a stale pre-dock frame. There is no overlap and no data loss. The code already marks the one-level limit with 'shortcut:' (Arranger.swift:112). To resolve, clear undockedWanted[id] wherever a window docks other than through undo"
    evidence_status: "none provided: no test or VM run shows it"
human_verification:
  - test: "VM, build containing 7d2bef3..9cb65bd (pending: a separate agent is running these now). (a) CR-01: float a window with the green button, double-click its title bar to zoom, double-click again to un-zoom, then change focus. Repeat with Window > Center on a window that Float centred. (b) CR-01 side effect: with an app that applies a write late or in two steps, check that a floater outside a boundary drag is not pushed back and forth. (c) WR-01: dock a large window beside another, Float the large one (it is clamped), then Float the other. (d) WR-02: Float All, then Undo, then Float one window. Also: shift-drag undock, then Undo, then Float"
    expected: "(a) Pane never re-zooms or re-moves the window. (b) No oscillation. (c) The first window grows back to its pre-dock frame. (d) The window goes to its pre-dock frame, not to the centred 90% fallback"
    why_human: "The headless tests pin each fix, and I confirmed they fail before the fixes and pass after. But own-write detection depends on real apps' echo timing, which only a live run shows. The 0.3.10 hand checks predate these commits"
  - test: "VM: dock a window that had a distinctive floating frame, quit Pane, relaunch, then Float it. Also move a floater while Pane is not running, then relaunch"
    expected: "Float goes to the pre-dock frame from the previous session. The floater moved while Pane was off stays where the user put it, with no setFrame"
    why_human: "This is the live half of 03-26's truth 1, and the 03-26 SUMMARY lists it for a VM re-check. The 0.3.10 re-check record covers the green button and the gap drag but not a relaunch. Headless tests (aDockedWindowsPreDockFrameSurvivesARelaunch, aFloaterMovedWhilePaneWasNotRunningKeepsWhereTheUserPutIt) pass. Skip this if the pending agent's run already covers it"
  - test: "Host with the DELL second display: Hide Desktop Tile on one display (UAT 16)"
    expected: "No parked window appears on the other display or over its tiles"
    why_human: "Needs two physical displays"
  - test: "Host with the DELL second display: dock windows on both displays and on two Spaces, then quit and relaunch, both clean and with kill -9 (UAT 17, display half). While a window is dormant on a hidden Space, also drag a window across displays (03-23 review WR-04)"
    expected: "Each display and Space gets its own layout back. The dragged window is not re-homed mid-drag"
    why_human: "Needs two physical displays. The Space half passed in the VM on 0.3.7, 0.3.8 and 0.3.9. The two-display case passes headlessly (twoDisplaysWithTwoSpacesEach…)"
  - test: "Decide on, or check by hand, the remainder of the previous green-button item: (a) a plain green click on a floater that exactly fills the Desktop tile, for example after an Option-click zoom (deferred-items 03-18: dock targets the Desktop centre and beeps); (b) a Dock tile that sits over a docked window's green button"
    expected: "(a) The floater docks, or the user accepts the beep as a known TILE-06 limit. (b) The Dock tile owns the click"
    why_human: "(a) is logged in deferred-items.md with options but no decision. The code still beeps on a .center target (Arranger.swift:849). (b) Only the menu-over-button case of review CR-01 was recorded by hand"
---

# Phase 3: Tiling MVP Verification Report

**Phase Goal:** As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp (the goal text is unchanged and was validated as a user story in earlier runs)
**Verified:** 2026-10-27T16:38:36Z
**Status:** human_needed
**Re-verification:** Yes. This replaces f2545c0 (human_needed, 11/11), which was written before the 03-23 review fixes, plans 03-24..03-26 and the 03-26 review fixes. The new work got a full 3-level check, including a RED re-run of the review-fix tests on pre-fix code. Earlier items got a regression check: one full headless run, plus artifact, wiring and anti-pattern scans.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| Drag a window by its title bar to an edge | A preview appears and the window docks on release, at any depth | `ArrangerDragTests` pass; UAT 2 live | VERIFIED |
| Windows open | New windows float on the Desktop tile and never auto-split | `PlannerTests` pass; UAT 14 re-run on 0.3.7 | VERIFIED |
| Windows close, minimise, go fullscreen | Neighbours reflow; minimised and fullscreen windows return | Reflow tests; UAT 3 and 4 re-runs; docked Safari Cmd-W freed its tile at once on 0.3.8 | VERIFIED |
| Resize by gap | Both sides follow, the split sticks, floaters keep their size | G-03-3 tests and `WantedFrameTests`; hand checks on 0.3.8 and 0.3.10 | VERIFIED |
| Green button | Each toggle moves the window visibly: docked floats to its pre-dock frame, floating docks | `ArrangerGreenButtonTests`; user hand check on 0.3.10 | VERIFIED (review-fix live re-check pending: human item 1) |
| Outcome: windows never overlap | A docked window that can't fit floats; a too-big floater doesn't float the desk; floaters stay inside the Desktop during a gap drag | `TooBigDockedWindowTests`, `RefusalRetryBoundTests`, `aFloaterWhoseMinimumIsAboveTheShrunkenDesktopNeverEndsBelowIt`; UAT 15 re-run; 0.3.10 hand check | VERIFIED (accepted T-03-58 overlap of a floater that can't shrink) |
| Layout survives a Pane relaunch | Each layout comes back, including after a locked start | 03-23, 03-24, 03-26; VM on 0.3.7, 0.3.8 and 0.3.9 | VERIFIED (display half and wanted-frame relaunch: human) |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | SC1: title-bar drag docks with a preview at any depth; bypass moves freely; new windows float; the green button toggles docked/floating | ✓ VERIFIED | Drag, bypass and new-window behaviour are as in f2545c0. Green button: `float()` (Arranger.swift:870-893) places the window via `Planner.floatFrame` (Planner.swift:82) at the clamped pre-dock frame or a centred 90% frame. `onTheDesksOnlyDockedWindowTheButtonFloatsItToItsPreDockFrameAndDocksItBack` and `aFloatWithNoKnownPreDockFrameGetsASlightlySmallerCentredFrame` pass. Live: 0.3.10 scripted check plus the user's hand check (G-03-4 resolved) |
| 2 | SC2: close reflows; gap drag resizes both; gap size is settable; a window leaving fullscreen returns to its tile | ✓ VERIFIED | UAT 3 and 4 re-runs. Docked Safari Cmd-W freed its tile at once on 0.3.8, which closes the previous human item 5. Gap drag by hand passed on 0.3.8 and 0.3.10 |
| 3 | SC3: menu and hotkeys through one dispatcher; undo; pause/resume; Restore all; `pane://restore` | ✓ VERIFIED | UAT 6 and 7 re-runs on 0.3.7. `PendingFocusTests` and `ArrangerCommandTests` pass |
| 4 | SC4: quit restore; crash rescue; conflicts; quitting and relaunching with apps running brings each layout back | ✓ VERIFIED | UAT 8, 9 and 11. Hidden-Space relaunch (03-23) and its review fixes CR-01..03 and WR-01..04 have tests that pass, and the VM checks on 0.3.8 passed. Locked start (03-24): see truth 12. Wanted frames persist (03-26): see truth 15 |
| 5 | SC5: works with zoom absent and Screen Recording denied; Developer ID signed and notarised; the grant survives updates | ✓ VERIFIED | Re-checked today: `build/Pane-0.3.0.dmg` passes `stapler validate`, and `spctl` reports accepted, source=Notarized Developer ID (S2K7P43927). Grant kept across version bumps (UAT 13, and 0.3.6 through 0.3.10 in the VM). UAT 12 covers Screen Recording. ⚠️ The DMG dates from 2026-10-26 08:16, before every UAT, gap and review fix. Public release is held for the Transom rename |
| 6 | SC6: swap, balance, rotate, flip, move and resize from the keyboard; snap floaters | ✓ VERIFIED | Regression: `LayoutEditTests`, `SnapTests` and `ArrangerCommandTests` pass. UAT 5 |
| 7 | SC7: hide/show the Desktop, arrange all, float all, Finder split, Don't Arrange; Option-click zoom; a minimised docked window returns | ✓ VERIFIED | UAT 6, 7 and 4. Float All keeps the tile-rect landing (TILE-16), pinned by `undoingFloatAllGivesBackThePreDockFrames`, whose first check is `frame(w1) == tile` |
| 8 | G-03-3: a gap drag beside a pinned side moves that gap; no mid-drag event writes the pre-drag tiles | ✓ VERIFIED | Tests pass. UAT re-run on 0.3.7, plus user hand checks on 0.3.8 and 0.3.10 |
| 9 | G-03-5: a second window of an app with a docked window becomes the command target | ✓ VERIFIED | `PendingFocusTests` pass. UAT 6 and 7 re-runs on 0.3.7 |
| 10 | G-03-6: a docked window that can't fit floats instead of overlapping; one too-big floater doesn't float the desk | ✓ VERIFIED | `TooBigDockedWindowTests.swift`, which holds both suites, is unchanged since 8653fcc and passes. UAT 15 re-run on 0.3.7 |
| 11 | G-03-8: desks on a Space not shown at relaunch keep their windows; a dormant window is pruned when it closes | ✓ VERIFIED | `ArrangerMultiDeskRestoreTests` pass (RED at fbfa115 confirmed in f2545c0). VM: 0.3.7 clean and kill -9 runs, 0.3.8 clean relaunch, 0.3.9 locked start |
| 12 | G-03-10: a start while locked keeps every saved desk once the screen is unlocked | ✓ VERIFIED | AXWindowSystem.swift:294-320: `initial = !initialRefreshComplete`, and the flag is set only when `initial, !paused, pauseCount == pausesBefore`. `sessionDidPause` bumps `pauseCount` (:551), and `sessionDidResume` runs `refreshAll` before `.sessionPaused(false)` (:557-569). The fake reports `initialSweepDone` (FakeWindowSystem.swift:405). Arranger's restore guard requires `initialRefreshComplete` and an unpaused session (Arranger.swift:224), and ArrangeController's feed waits on it (:131). `aStartWhileLockedKeepsEveryDeskOnceUnlocked` passes. Live: VM 0.3.9 locked start plus a user unlock gave an identical layout on Space 1 and Space 41. A lock and unlock within one sweep has no headless test (review IN-06). The code is correct by inspection |
| 13 | G-03-11: a gap drag that shrinks and then grows the Desktop returns floaters to their frames; a floater that refuses to shrink stops the drag at its real size | ✓ VERIFIED | `wantedFrames` is written only by user-side writers (see the list in the 03-REVIEW-03-26 answer to question 1). `planShown` and live replans call `Planner.plan(..., wanted: wantedFrames)` (Arranger.swift:1621, 1642). A refused floater read-back sets `floaterFloors` (:551-561), and `boundaryChange` plans with `floors:` (:1392, 1420). `aDesktopThatShrinksAndGrowsBackReturnsFloatersToTheirFrames` and `aFloaterWhoseMinimumIsAboveTheShrunkenDesktopNeverEndsBelowIt` pass. Live: 0.3.10 scripted check and the user's hand check (all 9 floaters exact) |
| 14 | G-03-4 (decision 2026-10-27): Float puts a docked window at its pre-dock frame clamped into the Desktop, or at a centred 90% frame; docking fills the tile, so every toggle moves the window | ✓ VERIFIED | See truth 1. The one replaced expectation (`floatPutsADockedWindowOnTheDesktopAtItsPreDockFrame`) follows the user decision, as the 03-25 SUMMARY documents |
| 15 | 03-26: wanted frames are saved in layout.json and validated like home frames; an older file loads with none; a floater moved while Pane was off keeps its real frame; a stranded saved wanted frame is dropped | ✓ VERIFIED | `LayoutFile` decodes the key with `decodeIfPresent ?? []` (LayoutFile.swift:65), and schemaVersion is unchanged. `LayoutStore.decode` rejects a non-finite, out-of-range or duplicate entry (LayoutStore.swift:109-113). Writer: ArrangeController.swift:488 `wantedFrames: snapshot.wantedFrames`. Restore: :113 `wantedFrames: saved.wantedFrameMap`. `reattach` filters to held and non-stranded frames and applies `movedWhileOff` (Arranger.swift:377-401). `aDockedWindowsPreDockFrameSurvivesARelaunch`, `aFloaterMovedWhilePaneWasNotRunningKeepsWhereTheUserPutIt`, `aSavedWantedFrameThatIsStrandedIsNotUsed`, `aFileFromBeforeWantedFramesLoadsWithNone` and `wantedFramesRoundTripSortedThroughTheStore` pass. The live relaunch check is human item 2 |
| 16 | 03-26 review fixes: a floater moved back onto Pane's last write is not moved away (CR-01); Float keeps the pre-dock frame as the wanted frame (WR-01); Undo of Float All or a shift-undock gives back the pre-dock frames (WR-02) | ✓ VERIFIED | `moved` clears `lastApplied` on the first move that is not Pane's own (Arranger.swift:696-700). `float` keeps `wanted` when the landing frame is its clamp (:891-892). Float All and commitUndock save into `undockedWanted` (Arranger+Commands.swift:144, Arranger.swift:1315), and `undo` gives it back (:904-906). `forget` and rekey clean up (:669-671, 543-545). **RED re-run:** in a scratch worktree at ef6d12e, with HEAD's WantedFrameTests.swift, `aFloaterMovedBackOntoPanesLastWriteIsNotMovedAway`, `aFloaterCentredAgainByTheUserStaysCentred`, `aFloatedWindowGrowsBackToItsPreDockFrameWhenTheDesktopDoes` and `undoingFloatAllGivesBackThePreDockFrames` fail, and the other 4 pass. All 8 pass at HEAD. The worktree was removed. The live check is pending (human item 1) |

**Score:** 16/16 truths verified (0 present but behaviour-unverified). The status is human_needed because 5 human items remain: the pending review-fix VM run, a wanted-frame relaunch check, two tests that need the second display, and one green-button edge decision.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | G-03-9: a closed Safari window stays tracked in a running session (its Space-less CG ghost blocks CloseRule) | Phase 6 | The ROADMAP Phase 6 scope note names G-03-9. User decision 2026-10-26. Partly mitigated: WR-03 drops Space-less entries at restore and prune, and the docked Safari close passed on 0.3.8 |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | `undockedWanted` is not cleared when a window docks again by drag or Dock rather than Undo. A later Undo can give back an older pre-dock frame | other | New scope with no deterministic evidence. Worst case is a stale Float target; there is no overlap |

### Required Artifacts

`verify.artifacts`: 03-24 3/3, 03-25 4/4, 03-26 4/4 (exist and substantive). The 03-01..03-23 artifacts (78) are all still present and compile. The full suite passes.

| Artifact | Provides | Status |
| -------- | -------- | ------ |
| `Sources/PaneMac/AXWindowSystem.swift` | pause counter; initial sweep counted only when unpaused | ✓ VERIFIED |
| `Sources/PaneTestSupport/FakeWindowSystem.swift` | `initialSweepDone` reported as `initialRefreshComplete` | ✓ VERIFIED |
| `Sources/PaneEngine/Planner.swift` | `plan(wanted:floors:)`, `floatFrame`, `near` | ✓ VERIFIED |
| `Sources/PaneEngine/Arranger.swift` | `wantedFrames`, `undockedWanted`, `floaterFloors`, `float()`, CR-01 own rule | ✓ VERIFIED |
| `Sources/PaneEngine/LayoutFile.swift` | optional `wantedFrames` key, `wantedFrameMap` | ✓ VERIFIED |
| `Sources/PaneMac/LayoutStore.swift` | wanted-frame validation | ✓ VERIFIED |
| `Sources/PaneMac/ArrangeController.swift` | save and restore carry wanted frames | ✓ VERIFIED |
| `Tests/PaneEngineTests/WantedFrameTests.swift` | G-03-11 and review-fix regressions (8 tests) | ✓ VERIFIED |
| `Tests/PaneEngineTests/ArrangerGreenButtonTests.swift`, `ArrangerRestoreTests.swift`, `ArrangerMultiDeskRestoreTests.swift`, `Tests/PaneMacTests/LayoutStoreTests.swift` | G-03-4, 03-26 and G-03-10 regressions | ✓ VERIFIED |

### Key Link Verification

`verify.key-links` can't parse `from:` values that carry a symbol, so it reports "Source file not found" for all 7 links. I checked them by hand:

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| AXWindowSystem `sessionDidResume` -> `refreshAll()` | WindowTracker initial sweep (no settle hold) | `sweep()` computes `initial` from `initialRefreshComplete`, which stays false after a paused sweep | WIRED |
| AXWindowSystem `inventory().initialRefreshComplete` | Arranger restore guard; ArrangeController feed | Arranger.swift:224; ArrangeController.swift:131 | WIRED |
| Arranger `planShown` and live replans | `Planner.plan(wanted:)` | Arranger.swift:1621, 1642 `wanted: wantedFrames` | WIRED |
| Arranger `.frameApplied` (floating) | `boundaryChange` floors | `floaterFloors` set at :559, replan while `liveGap`; :1392, 1420 `floors: floors` | WIRED |
| Arranger `float()` | `Planner.floatFrame` | Arranger.swift:886 | WIRED |
| ArrangeController `write()` | `LayoutFile.init(...wantedFrames:)` | ArrangeController.swift:488 | WIRED |
| ArrangeController restore at launch | `.restore(_, homeFrames:, wantedFrames:)` -> `reattach` | ArrangeController.swift:113 -> Arranger.swift:298-299, 377 | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
| -------- | ---- | ------ | --------- | ------ |
| Floater placement | `wantedFrames` | user-side frame events, admit, Snap, Float, layout.json | yes | FLOWING |
| Gap-drag cut | `floaterFloors` | the app's refused read-back (`.frameApplied` actual) | yes | FLOWING |
| layout.json wanted frames | `snapshot.wantedFrames` -> file -> `wantedFrameMap` -> `reattach` | Arranger state; validated load | yes | FLOWING |
| Restore gate | `initialRefreshComplete`, `liveWindows` | AX sweep; CG optionAll with SkyLight Spaces | yes; nil keeps every saved window | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Live gate | `PANE_LIVE` unset in the environment (checked) | the integration target's 42 tests in 20 suites skipped ("needs a process with the Accessibility grant") | PASS |
| Headless suites (one full run) | `swift test` at d0321f2 | exit 0: 193 + 198 + 532 (PaneEngineTests) = 923 tests passed, 0 failures; the 42 live integration tests reported as a passing run, all skipped by the gate (XCTest: 0). `FreezeTestTests/itResumesByItself` passed on the first run, so no rerun was needed | PASS |
| Review-fix tests catch the bugs | `swift test --filter WantedFrameTests` in a scratch worktree at ef6d12e with HEAD's test file | 4 new tests fail (CR-01 x2, WR-01, WR-02 Float All); the 4 earlier tests pass; exit 1. Worktree removed | PASS (RED confirmed) |
| No AppKit in Model and Engine | `scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | PASS |
| Notarised DMG | `xcrun stapler validate`, `spctl -a -t open` | worked; accepted, Notarized Developer ID | PASS (stale build) |
| Live AX suites, VM | not run (no PANE_LIVE, no Pane launch, no VM) | the VM record in 03-UAT.md covers 0.3.7..0.3.10 | SKIP |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist, and no plan declares a probe. Not applicable.

### Requirements Coverage

All 26 phase IDs are claimed by at least one plan. 03-24..03-26 claim SAFE-06, TILE-05, TILE-06, TILE-07 and TILE-09. None is orphaned. REQUIREMENTS.md now marks all 26 as Complete, including WIN-07.

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| TILE-01, TILE-02 | SATISFIED | UAT 2; drag tests |
| TILE-03 | SATISFIED | UAT 3; docked Safari close on 0.3.8 |
| TILE-04 | SATISFIED | UAT 3 Gaps menu |
| TILE-05 | SATISFIED | G-03-3 and G-03-11 tests; hand checks on 0.3.8 and 0.3.10 |
| TILE-06 | SATISFIED (edge: human item 5) | green-button tests; 0.3.10 hand check |
| TILE-07 | SATISFIED (CR-01 live: human item 1) | UAT 14; wanted-frame tests |
| TILE-08 | SATISFIED | UAT 6 Pause/Resume |
| TILE-09 | SATISFIED | UAT 6; Float and Undo tests (WR-01, WR-02) |
| TILE-10 | SATISFIED | UAT 12 |
| TILE-11..14 | SATISFIED | UAT 5; edit and snap tests |
| TILE-15, TILE-16, TILE-18 | SATISFIED | UAT 6 and 7 |
| TILE-17 | SATISFIED | UAT 7 re-run |
| TILE-19 | SATISFIED | UAT 4 re-run; 0.3.8 hand check |
| TILE-20 | SATISFIED | UAT 4 |
| WIN-07 | SATISFIED | UAT 4 |
| SAFE-01, SAFE-02, SAFE-03, SAFE-04 | SATISFIED | UAT 8, 9, 7, 11 |
| SAFE-06 | SATISFIED (display half and wanted-frame relaunch: human) | 03-23, 03-24, 03-26; VM 0.3.7..0.3.9 |

### Decision Coverage

`check.decision-coverage-verify`: skipped. CONTEXT.md has no trackable decisions. `decision_coverage: {honored: 0, total: 0, not_honored: []}`.

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| WantedFrameTests.swift | TILE-05, TILE-07, TILE-09 | 8 | 0 | no | Behavioral (multi-step frames, setFrame effects) | OK; the 4 review-fix tests are RED-confirmed |
| ArrangerGreenButtonTests.swift | TILE-06 | all | 0 | no | Behavioral | OK |
| ArrangerMultiDeskRestoreTests.swift | SAFE-06 | all | 0 | no | Behavioral (fresh fake at relaunch, locked start) | OK |
| ArrangerRestoreTests.swift, LayoutStoreTests.swift | SAFE-06 | all | 0 | no | Value and behavioral | OK |
| PaneMacIntegrationTests (live) | various | gated | 42 skipped (`.enabled(if: IntegrationEnv.trusted)`) | no | Behavioral | By design. Headless tests cover the same requirements |

**Disabled tests on requirements:** 0 (the live gate is not a disable). **Circular patterns:** 0. **Insufficient assertions:** 0. **Replaced expectations:** 1 (03-25, a user decision). The 03-26 review fixes only added test lines.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Sources and the 03-24..26 test files | — | TBD/FIXME/XXX/TODO/HACK | none | — |
| Sources/PaneEngine/Arranger.swift | 112 | `shortcut:` one-level `undockedWanted` (documented WR-02 limit) | ℹ️ Info | An Undo across two undocks of one window gives back the later frame |
| build/Pane-0.3.0.dmg | — | built 2026-10-26 08:16, before every UAT, gap and review fix (03-18..03-26 and all review fixes) | ⚠️ Warning | Rebuild and notarise before any tester distribution or release (release held for the Transom rename) |
| 03-REVIEW-03-26.md | IN-01 | a 0x0 wanted or home frame passes `isValidGeometry` (Geometry.swift:60, `>= 0`) | ℹ️ Info (open) | A corrupt file could cause a 0x0 setFrame |
| 03-REVIEW-03-26.md | IN-02 | `restore(..., wantedFrames: = [:])` and `LayoutFile.init(..., wantedFrames: = [:])` defaults are still present (Arranger.swift:12, LayoutFile.swift:45) | ℹ️ Info (open) | A future caller could drop wanted frames silently |
| 03-REVIEW-03-26.md | IN-03 | `liveGap` is cleared only by mouse-up, a failed replan, or the desk no longer being shown (Arranger.swift:1474, 1481, 1591), not on pause | ℹ️ Info (open) | A lost mouse-up while paused leaves every floater move counted as Pane's own |
| 03-REVIEW-03-26.md | IN-04, IN-05, IN-06 | 2 pt "back on the tile" test; zero-size floor entries and floors outliving a dock; no headless test for a pause during a sweep | ℹ️ Info (open) | Minor |
| 03-REVIEW-03-23.md | IN-01, IN-02 | production prune trigger has no automated test; an empty live list never prunes | ℹ️ Info (open) | Minor |
| 03-REVIEW.md | IN-01..03 | stale comments after 03-20/21; `setWeights` doc; `vm-live-test.sh` word splitting | ℹ️ Info (open) | Minor |
| 03-UAT.md | Summary, tests 3/4/6/7 | Summary counts (issues: 4) and the test `result: issue` lines predate the re-run sections. `status: partial` is still correct (UAT 16 and 17 are blocked) | ℹ️ Info | Bookkeeping |
| deferred-items.md | 03-18, 03-19, 03-22, 03-24, 03-25 | open items with options and no decision (Desktop-centre green click, Dock enabled with no room, notices not logged, the AX-failed-at-first-sweep restore risk, D-24 past-screen-edge floaters, late-apply floors, Float All pre-dock frame) | ℹ️ Info | Human item 5 covers the TILE-06 one. The rest are polish or accepted risk |
| Tests/PaneMacTests/FreezeTestTests.swift | 58 | timing-sensitive | ℹ️ Info | Passed in this run; a known flake |

### Human Verification Required

The frontmatter `human_verification` list has the same 5 items.

1. **03-26 review fixes live (VM, pending in a separate agent).** Covers the CR-01 zoom/un-zoom and Window > Center cases, the CR-01 late-apply side effect, WR-01 grow-back, and WR-02 Undo of Float All and of a shift-undock. Expected: no re-move, no oscillation, and the pre-dock frames come back.
2. **Wanted frames across a relaunch (VM).** Float after a quit and relaunch should go to the previous session's pre-dock frame. A floater moved while Pane was off should stay put. This may already be covered by the pending run.
3. **Host, DELL second display: Hide Desktop (UAT 16).** Expected: nothing parks onto the other display.
4. **Host, DELL second display: relaunch with layouts on two displays and two Spaces, clean and with kill -9 (UAT 17, display half), plus a cross-display drag while a window is dormant (03-23 WR-04).** Expected: each display and Space restores its own layout, and the dragged window is not re-homed mid-drag.
5. **Green-button edge (decide, or check by hand).** A floater that exactly fills the Desktop tile beeps on a plain click (deferred-items 03-18). Also, a Dock tile over a docked window's green button. Expected: it docks, or the beep is accepted as a known limit; the Dock tile owns its click.

### Gaps Summary

No blocking gaps. Since f2545c0, four gaps closed: G-03-10 (03-24), G-03-11 and the reopened G-03-4 (03-25, 03-26), plus the 03-26 review's CR-01, WR-01 and WR-02. Each fix has headless tests that pass at HEAD, and I confirmed that the review-fix tests fail on the pre-fix code. G-03-10, G-03-11 and G-03-4 also passed live in the VM on 0.3.9 and 0.3.10. The evidence also supports closing G-03-3, G-03-5, G-03-6 and G-03-8: their VM re-runs on 0.3.7, and for G-03-3 and G-03-8 the later hand checks and relaunches on 0.3.8 and 0.3.9, all passed, and their tests are unchanged and green. 03-UAT.md now marks them resolved, with resolved_by. G-03-9 stays deferred to Phase 6.

What remains is live confirmation:
- the 03-26 review fixes, which a separate agent is checking in the VM now;
- the wanted-frame relaunch check;
- the two tests that need the host's second display;
- a decision on the green-button Desktop-centre edge case.

Before ship: rebuild and notarise the DMG, because the current one predates every fix. Consider the open Info items (IN-01 and IN-02 of the 03-26 review are one-line hardening fixes) and the UAT summary bookkeeping.

---

_Verified: 2026-10-27T16:38:36Z_
_Verifier: Claude (gsd-verifier)_
