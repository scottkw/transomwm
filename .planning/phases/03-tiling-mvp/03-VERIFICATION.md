---
phase: 03-tiling-mvp
verified: 2026-10-27T03:00:24Z
status: human_needed
score: 11/11 must-haves verified
covered_files: [".github/workflows/ci.yml",".planning/phases/03-tiling-mvp/03-01-PLAN.md",".planning/phases/03-tiling-mvp/03-01-SUMMARY.md",".planning/phases/03-tiling-mvp/03-02-PLAN.md",".planning/phases/03-tiling-mvp/03-02-SUMMARY.md",".planning/phases/03-tiling-mvp/03-03-PLAN.md",".planning/phases/03-tiling-mvp/03-03-SUMMARY.md",".planning/phases/03-tiling-mvp/03-04-PLAN.md",".planning/phases/03-tiling-mvp/03-04-SUMMARY.md",".planning/phases/03-tiling-mvp/03-05-PLAN.md",".planning/phases/03-tiling-mvp/03-05-SUMMARY.md",".planning/phases/03-tiling-mvp/03-06-PLAN.md",".planning/phases/03-tiling-mvp/03-06-SUMMARY.md",".planning/phases/03-tiling-mvp/03-07-PLAN.md",".planning/phases/03-tiling-mvp/03-07-SUMMARY.md",".planning/phases/03-tiling-mvp/03-08-PLAN.md",".planning/phases/03-tiling-mvp/03-08-SUMMARY.md",".planning/phases/03-tiling-mvp/03-09-PLAN.md",".planning/phases/03-tiling-mvp/03-09-SUMMARY.md",".planning/phases/03-tiling-mvp/03-10-PLAN.md",".planning/phases/03-tiling-mvp/03-10-SUMMARY.md",".planning/phases/03-tiling-mvp/03-11-PLAN.md",".planning/phases/03-tiling-mvp/03-11-SUMMARY.md",".planning/phases/03-tiling-mvp/03-12-PLAN.md",".planning/phases/03-tiling-mvp/03-12-SUMMARY.md",".planning/phases/03-tiling-mvp/03-13-PLAN.md",".planning/phases/03-tiling-mvp/03-13-SUMMARY.md",".planning/phases/03-tiling-mvp/03-14-PLAN.md",".planning/phases/03-tiling-mvp/03-14-SUMMARY.md",".planning/phases/03-tiling-mvp/03-15-PLAN.md",".planning/phases/03-tiling-mvp/03-15-SUMMARY.md",".planning/phases/03-tiling-mvp/03-16-PLAN.md",".planning/phases/03-tiling-mvp/03-16-SUMMARY.md",".planning/phases/03-tiling-mvp/03-17-PLAN.md",".planning/phases/03-tiling-mvp/03-17-SUMMARY.md",".planning/phases/03-tiling-mvp/03-18-PLAN.md",".planning/phases/03-tiling-mvp/03-18-SUMMARY.md",".planning/phases/03-tiling-mvp/03-19-PLAN.md",".planning/phases/03-tiling-mvp/03-19-SUMMARY.md",".planning/phases/03-tiling-mvp/03-20-PLAN.md",".planning/phases/03-tiling-mvp/03-20-SUMMARY.md",".planning/phases/03-tiling-mvp/03-21-PLAN.md",".planning/phases/03-tiling-mvp/03-21-SUMMARY.md",".planning/phases/03-tiling-mvp/03-22-PLAN.md",".planning/phases/03-tiling-mvp/03-22-SUMMARY.md",".planning/phases/03-tiling-mvp/03-23-PLAN.md",".planning/phases/03-tiling-mvp/03-23-SUMMARY.md","Package.resolved","Package.swift","Sources/PaneEngine/Arranger+Commands.swift","Sources/PaneEngine/Arranger.swift","Sources/PaneEngine/CloseRule.swift","Sources/PaneEngine/Command.swift","Sources/PaneEngine/ConflictPolicy.swift","Sources/PaneEngine/DragSession.swift","Sources/PaneEngine/GapHandles.swift","Sources/PaneEngine/LayoutFile.swift","Sources/PaneEngine/LayoutRestore.swift","Sources/PaneEngine/LifecycleSync.swift","Sources/PaneEngine/MinimumSizeLearner.swift","Sources/PaneEngine/Notice.swift","Sources/PaneEngine/PaneURL.swift","Sources/PaneEngine/PendingFocus.swift","Sources/PaneEngine/PermissionReducer.swift","Sources/PaneEngine/Planner.swift","Sources/PaneEngine/Recovery.swift","Sources/PaneEngine/WindowSnapshot.swift","Sources/PaneEngine/WindowSystem.swift","Sources/PaneEngine/WindowTracker.swift","Sources/PaneFixtureApp/main.swift","Sources/PaneMac/AX/AXAppThread.swift","Sources/PaneMac/AX/AXSnapshotReader.swift","Sources/PaneMac/AX/MenuPress.swift","Sources/PaneMac/AXWindowSystem.swift","Sources/PaneMac/AppDelegate.swift","Sources/PaneMac/ArrangeController.swift","Sources/PaneMac/CGWindowList.swift","Sources/PaneMac/ConflictController.swift","Sources/PaneMac/Displays.swift","Sources/PaneMac/GapPreference.swift","Sources/PaneMac/Input/DragFramePoller.swift","Sources/PaneMac/Input/GreenButton.swift","Sources/PaneMac/Input/Hotkeys.swift","Sources/PaneMac/Input/InputTap.swift","Sources/PaneMac/LayoutStore.swift","Sources/PaneMac/MinimumHintsStore.swift","Sources/PaneMac/Overlay/GapHandlePanels.swift","Sources/PaneMac/Overlay/NoticeQueue.swift","Sources/PaneMac/Overlay/PreviewPanel.swift","Sources/PaneMac/Overlay/PreviewStyle.swift","Sources/PaneMac/Overlay/Toast.swift","Sources/PaneMac/PaneMacApp.swift","Sources/PaneMac/Shell/CommandMenu.swift","Sources/PaneMac/Shell/ConflictCopy.swift","Sources/PaneMac/Shell/MenuCopy.swift","Sources/PaneMac/Shell/NoticeCopy.swift","Sources/PaneMac/Shell/StatusItemController.swift","Sources/PaneMac/WindowManagerSettings.swift","Sources/PaneModel/DesktopLayer.swift","Sources/PaneModel/DropZones.swift","Sources/PaneModel/IDs.swift","Sources/PaneModel/LayoutTree.swift","Sources/PaneModel/Neighbours.swift","Sources/PaneModel/Resolve.swift","Sources/PaneModel/Snap.swift","Sources/PaneModel/TreeEdits.swift","Sources/PaneModel/Undo.swift","Sources/PaneModel/World.swift","Sources/PanePrivate/SkyLightSpaces.swift","Sources/PaneTestSupport/FakeWindowSystem.swift","Tests/PaneEngineTests/ArrangerCommandTests.swift","Tests/PaneEngineTests/ArrangerDesktopTests.swift","Tests/PaneEngineTests/ArrangerDragTests.swift","Tests/PaneEngineTests/ArrangerExclusionTests.swift","Tests/PaneEngineTests/ArrangerFinderTests.swift","Tests/PaneEngineTests/ArrangerFocusTests.swift","Tests/PaneEngineTests/ArrangerGreenButtonTests.swift","Tests/PaneEngineTests/ArrangerLifecycleTests.swift","Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift","Tests/PaneEngineTests/ArrangerPauseTests.swift","Tests/PaneEngineTests/ArrangerReflowTests.swift","Tests/PaneEngineTests/ArrangerResizeTests.swift","Tests/PaneEngineTests/ArrangerRestoreTests.swift","Tests/PaneEngineTests/ArrangerSpacesTests.swift","Tests/PaneEngineTests/CommandTests.swift","Tests/PaneEngineTests/ConflictPolicyTests.swift","Tests/PaneEngineTests/DragSessionTests.swift","Tests/PaneEngineTests/FrameScenarioTests.swift","Tests/PaneEngineTests/GapHandleGeometryTests.swift","Tests/PaneEngineTests/LifecycleSyncTests.swift","Tests/PaneEngineTests/MinimumSizeLearnerTests.swift","Tests/PaneEngineTests/PaneURLTests.swift","Tests/PaneEngineTests/PendingFocusTests.swift","Tests/PaneEngineTests/PermissionReducerTests.swift","Tests/PaneEngineTests/PlannerTests.swift","Tests/PaneEngineTests/RecoveryTests.swift","Tests/PaneEngineTests/TooBigDockedWindowTests.swift","Tests/PaneEngineTests/TrackerDisplayTests.swift","Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift","Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift","Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift","Tests/PaneMacIntegrationTests/InputTapIntegrationTests.swift","Tests/PaneMacIntegrationTests/IntegrationSupport.swift","Tests/PaneMacIntegrationTests/MenuPressIntegrationTests.swift","Tests/PaneMacIntegrationTests/QuitRestoreIntegrationTests.swift","Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift","Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift","Tests/PaneMacIntegrationTests/TitleBarDragIntegrationTests.swift","Tests/PaneMacTests/AppDelegateTests.swift","Tests/PaneMacTests/CapabilitiesTests.swift","Tests/PaneMacTests/CommandMenuTests.swift","Tests/PaneMacTests/ConflictControllerTests.swift","Tests/PaneMacTests/ConflictCopyTests.swift","Tests/PaneMacTests/GapPreferenceTests.swift","Tests/PaneMacTests/GreenButtonHitTests.swift","Tests/PaneMacTests/HotkeyTableTests.swift","Tests/PaneMacTests/LayoutStoreTests.swift","Tests/PaneMacTests/MenuCopyTests.swift","Tests/PaneMacTests/MenuPressTests.swift","Tests/PaneMacTests/MinimumHintsStoreTests.swift","Tests/PaneMacTests/NoScreenCaptureTests.swift","Tests/PaneMacTests/NoticeCopyTests.swift","Tests/PaneMacTests/NoticeQueueTests.swift","Tests/PaneMacTests/PreviewStyleTests.swift","Tests/PaneMacTests/TopmostWindowTests.swift","Tests/PaneMacTests/WakeTimerTests.swift","Tests/PaneMacTests/WindowManagerSettingsTests.swift","Tests/PaneModelTests/DesktopLayerTests.swift","Tests/PaneModelTests/DesktopLeafTests.swift","Tests/PaneModelTests/LayoutEditTests.swift","Tests/PaneModelTests/LifecycleTests.swift","Tests/PaneModelTests/NeighbourTests.swift","Tests/PaneModelTests/PersistenceTests.swift","Tests/PaneModelTests/ResolveFuzzTests.swift","Tests/PaneModelTests/ResolveTests.swift","Tests/PaneModelTests/ScenarioTests.swift","Tests/PaneModelTests/SkeletonTests.swift","Tests/PaneModelTests/SnapTests.swift","Tests/PaneModelTests/TabsTests.swift","Tests/PaneModelTests/TreeEditTests.swift","Tests/PaneModelTests/UndoTests.swift","Tests/PaneModelTests/WorldRekeyTests.swift","scripts/check-no-appkit.sh","scripts/release.sh","scripts/vm-live-test.sh","xcode/Pane-Info.plist","xcode/project.yml"]
covered_digest: "v3:sha256:ce70aeef299d6f8dfa3e4520d7a765526f6e81db0ac62a4ebbe05e10cb4b23a3"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 8/10
  gaps_closed:
    - "SC4 / SAFE-06 (G-03-8): desks on a Space not shown at relaunch keep their windows. 03-23 keeps saved windows that are still in the layer-0 CG list (same windowID and pid) dormant in their desk and re-attaches them on their first windowCreated. I re-ran the new tests at the RED commit fbfa115: they fail (Space 2 desk empty, world != saved, for both .normal and .recovery). At HEAD they pass. The VM clean and kill -9 cycles on 0.3.7/1005 and UAT 17's Space half passed."
    - "SC1 green button (G-03-4 after CR-01): UAT re-run 4 on 0.3.7/1005 used real VNC clicks. A plain click floats or docks and never goes fullscreen. Option-click zooms, then D-33 returns the window. A Finder menu item over the green button got the click 3 times out of 3. A check by hand is still open (human item 1)."
    - "UAT 6, 7 and 15 re-run on the final build passed (G-03-5 focus, split-finder with other Finder windows open, Reminders refusal with no persisted hint after CR-02)"
    - "The fixture-only warning on ArrangerMultiDeskRestoreTests is resolved. Relaunches now use a fresh FakeWindowSystem whose showSpace unlists windows on Spaces that are not shown from AX, as the real AX path does."
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "G-03-9: closing a window removes it from Pane's tracking and layout.json (a closed Safari window lingers because Safari keeps its layer-0, Space-less CG entry)"
    addressed_in: "Phase 6"
    evidence: "ROADMAP Phase 6 scope note: 'Also closes deferred G-03-9: a window whose only CG entry has no Space (Safari keeps closed windows' entries for minutes) must count as closed, not alive'. The user deferred it on 2026-10-26 (03-UAT.md G-03-9, deferred-items.md)."
coincidental_reliance_items:
  - truth: "SC4 / SAFE-06: hidden-Space desks survive a relaunch"
    reason: undeclared-precondition
    harden: "At restore, Arranger uses `inventory.liveWindows ?? []` (Arranger.swift ~205). If the first complete inventory has no CG list, because CGWindowList.snapshot failed or the session was paused (AXWindowSystem.inventory reports nil while sessionPaused), every hidden-Space window is treated as closed and removed, which is the pre-03-23 behaviour. The prune path treats nil as 'decide nothing', but the restore path does not. To harden it, defer the restore until liveWindows is non-nil (or the session is active), or keep untracked saved windows when liveWindows is nil."
human_verification:
  - test: "VM, final build: by hand, plain-click the green button of a docked window and of a floating window that does not fill the Desktop tile, then Option-click both. Also click a Dock tile and a context-menu item that sit over a docked window's green button, and plain-click an Option-zoomed floater that fills the Desktop tile"
    expected: "Docked floats and floating docks, never fullscreen. Option-click zooms, then D-33 returns the window. The Dock or menu owns its click. The Option-zoomed floater docks, or D-26 refuses with a beep for lack of room"
    why_human: "The UAT re-run drove these through VNC, and only the Finder menu-item case of CR-01 was recorded. A hand click on real hardware, the Dock-tile and context-menu overlays, and the deferred-items 03-18 'Desktop-centre' no-op are not covered"
  - test: "VM: drag the gap between two docked tiles by hand, including toward a side held at its minimum, hold still, then release (UAT 3)"
    expected: "Both tiles follow smoothly, nothing jumps back, and the split sticks"
    why_human: "The original report was about feel. The re-run sampled injected drags (122 and 274 changes with no snap-back), not a hand drag"
  - test: "Host, second display: Hide Desktop Tile on one display (UAT 16)"
    expected: "No parked window appears on the other display or over its tiles"
    why_human: "Needs two physical displays; the user is away"
  - test: "Host, second display: dock windows on both displays (and two Spaces), quit and relaunch, both clean and with kill -9 (UAT 17, display half)"
    expected: "Each display and Space gets its own layout back"
    why_human: "Needs two physical displays. The Space half passed in the VM, and the two-display case passes headlessly (twoDisplaysWithTwoSpacesEach…, fresh fake)"
  - test: "VM: dock a Safari window beside a TextEdit window, then close the Safari window with Cmd-W"
    expected: "TextEdit reflows into the freed space within a second or two. If it does not, decide whether the G-03-9 deferral still stands, because it was assessed as 'bookkeeping only'"
    why_human: "CloseRule (CloseRule.swift: alive + invalidElement + CG present -> recheck) never closes a window while Safari keeps its ghost CG entry. By that rule, a docked Safari window that closes should keep its tile reserved, so its neighbours do not reflow (TILE-03) until Safari drops the entry. G-03-9 was observed and assessed only for a floating window. This is inferred from the code and has not been seen live"
---

# Phase 3: Tiling MVP Verification Report

**Phase Goal:** As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp (`user-story.validate`: valid in the previous run; goal text unchanged)
**Verified:** 2026-10-27T03:00:24Z
**Status:** human_needed
**Re-verification:** Yes. It replaces cb0ea7c (gaps_found, SC4/SAFE-06 hidden-Space relaunch). The failed item got a full 3-level check, including a RED/GREEN test re-run. Passed items got a regression check: one full headless run and the artifact, wiring and anti-pattern scans.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| Drag a window by its title bar to an edge | A preview appears and the window docks on release, at any depth | Unchanged since cb0ea7c; `ArrangerDragTests` pass; UAT 2 live | VERIFIED |
| Windows open | New windows float on the Desktop tile and never auto-split | UAT 14 passed again on 0.3.7; `PlannerTests` pass | VERIFIED |
| Windows close, minimise, go fullscreen | Neighbours reflow; minimised and fullscreen windows return | UAT 3 and 4 passed again on 0.3.7; reflow tests pass | VERIFIED (docked-Safari close: human item 5, related to the G-03-9 deferral) |
| Resize by gap | Both sides follow, and the split sticks | G-03-3 tests pass; UAT 3 re-run with injected drags passed | VERIFIED (feel by hand: human) |
| Outcome: windows never overlap | A docked window that can't fit floats; one too-big floater doesn't float the desk | `TooBigDockedWindowTests`, `RefusalRetryBoundTests` pass; UAT 15 re-run passed (accepted T-03-58 overlap of a floater that can't shrink) | VERIFIED (with the accepted trade-offs) |
| Layout survives a Pane relaunch | Each layout comes back | 03-23 dormant re-attach; RED at fbfa115 and GREEN at HEAD, re-run here; VM clean and kill -9 cycles; UAT 17 Space half | VERIFIED (display half: human) |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | SC1: title-bar drag docks with a preview at any depth; bypass moves freely; new windows float; the green button toggles docked/floating | ✓ VERIFIED | The drag, bypass and new-window parts are unchanged. The green button now passes live on the final build: UAT re-run 4 (0.3.7/1005, HEAD code) used real VNC clicks. A plain click floats or docks with no fullscreen. Option-click zooms, then D-33 returns the window. The CR-01 Finder menu item got the click 3/3. `TopmostWindowTests` pass. A hand check remains (human item 1) |
| 2 | SC2: close reflows; gap drag resizes both; gap size settable; a window leaving fullscreen returns to its tile | ✓ VERIFIED | UAT 3 re-run passed: the pinned-side drag moves, holding mid-drag shows no snap-back, and Undo is exact. UAT 4 covers the fullscreen return. The G-03-3 named tests pass in this run. Feel is human item 2. The docked-Safari close case is human item 5 |
| 3 | SC3: menu and hotkeys through one dispatcher; undo; pause/resume; Restore all; `pane://restore` | ✓ VERIFIED | UAT 6 and 7 re-run passed: B docks by ⌃⌥⌘D, menu enablement follows B, split-finder works with other Finder windows open, and `restore?x=1` is rejected. `PendingFocusTests` pass |
| 4 | SC4: quit restore; crash rescue; conflicts; quitting and relaunching with apps running brings each layout back with the same windows in their tiles | ✓ VERIFIED | Quit, crash and conflicts are as before (UAT 8, 9, 11). **Hidden-Space relaunch is fixed.** `LayoutRestore.reattach(_:tracked:live:)` keeps a saved window when `isAlive` matches a layer-0 CG entry with the same windowID and pid, never for a synthetic ID (LayoutRestore.swift:15-37). `Arranger.process(.inventory)` passes `inventory.liveWindows` (Arranger.swift ~204-210). `wakeDormant` runs on the first `windowCreated`, seeds `lastRequested` and re-homes the window (~481-563). `planShown` skips untracked windows (`isExcluded == false`). AXWindowSystem fills `liveWindows` from each sweep's optionAll snapshot (~296-301). **I re-ran the 03-23 tests at RED commit fbfa115:** `aDeskOnASpaceNotShownAtRelaunchKeepsItsWindowsInTheirTiles` (.normal and .recovery), `aDormantWindowWhoseTileChangedIsWrittenOnceToItsNewTile` and the rewritten `twoDisplaysWithTwoSpacesEach…` fail there. All pass at HEAD. Live: the 03-23 VM clean and kill -9 cycles kept the Space 41 desk, Notes came back at `370 37 642 664`, and its correction after an AX move shows it really re-attached. UAT 17's Space half passed. See `coincidental_reliance_items` for the nil-liveWindows fallback |
| 5 | SC5: works with zoom absent and Screen Recording denied; Developer ID signed and notarised; the grant survives updates | ✓ VERIFIED | Re-checked today: `build/Pane-0.3.0.dmg` passes `stapler validate`, and `spctl` reports accepted, source=Notarized Developer ID, Ken Scott (S2K7P43927). The grant held across the 0.3.6 -> 0.3.7/1005 bump (03-23 VM: notTrusted -> probing -> ready). UAT 12 covers Screen Recording. Warning: the DMG predates every UAT and gap fix |
| 6 | SC6: swap, balance, rotate, flip, move, resize from the keyboard, snap floaters | ✓ VERIFIED | Regression: `LayoutEditTests`, `SnapTests` and `ArrangerCommandTests` pass in the full run. UAT 5 as before |
| 7 | SC7: hide/show the Desktop, arrange all, float all, Finder split, Don't Arrange; Option-click zoom; a minimised docked window returns | ✓ VERIFIED | UAT 6 and 7 re-run passed. UAT 4 re-run covers Option-click and minimise |
| 8 | G-03-3: a gap drag next to a pinned side moves that gap; no mid-drag event writes the pre-drag tiles | ✓ VERIFIED | The named tests pass in this run; the UAT 3 re-run passed |
| 9 | G-03-5: a second window of an app with a docked window becomes the command target | ✓ VERIFIED | `PendingFocusTests` pass; the UAT 6 re-run passed live |
| 10 | G-03-6: a docked window that can't fit floats instead of overlapping a neighbour; one too-big floater doesn't float the desk | ✓ VERIFIED | Tests pass. UAT 15 re-run: Reminders floats about 2 s after docking, Notes keeps its tile, and no `com.apple.reminders` hint is saved |
| 11 | G-03-8 prune: a dormant window is pruned when its ID leaves the layer-0 CG list or its app quits; a paused, unknown or empty list prunes nothing | ✓ VERIFIED | `closeDormant` goes through `forget` and `LifecycleSync.handle(.windowDestroyed)`, with no undo step. It is called from the post-restore `.inventory` behind a `!sessionPaused, liveWindows != nil, !isEmpty` guard, and from `.appTerminated` (Arranger.swift ~193-196, ~524-526). `aDormantWindowThatLeftTheCGListIsPrunedWithNoUndoStep`, `aDormantWindowStillInTheCGListIsKeptByEveryInventory`, `aDormantWindowIsPrunedWhenItsAppTerminates`, `aBlankOrUnknownCGListPrunesNothing` and `liveWindowsChangedAloneDoesNothing` pass. Live: in 03-23 the VM CG prune removed TextEdit#2018 from layout.json 3 s after the close. The appTerminated path is covered headlessly only |

**Score:** 11/11 truths verified (0 present but behaviour-unverified). The status is human_needed because of 5 human items: hand feel, two tests that need the second display, and one deferral check.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | G-03-9: a closed Safari window stays tracked and in layout.json (its Space-less CG ghost counts as alive) | Phase 6 | ROADMAP Phase 6 scope note names G-03-9 and the fix ("a window whose only CG entry has no Space … must count as closed"). User decision 2026-10-26 |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | At restore, `inventory.liveWindows ?? []` treats an unknown CG list as "no window alive", so hidden-Space desks are dropped as before 03-23 when the first complete inventory has no CG list (snapshot failure, or session paused at launch) | other | Edge path. No run has shown it, and it does not fail closed toward an overlap. Recorded under coincidental_reliance_items |
| 2 | A docked Safari window that closes probably keeps its tile until Safari drops its ghost CG entry (same root cause as G-03-9) | other | Inferred from the CloseRule table and not seen live. Routed to human item 5, because it bears on the G-03-9 deferral |

### Required Artifacts

`verify.artifacts` for 03-23: 7/7 pass (exist and substantive). The 71/71 result for 03-01..03-22 from cb0ea7c stands. Regression: every file is present, and the full suite builds and passes.

| Artifact | Provides | Status |
| -------- | -------- | ------ |
| `Sources/PaneEngine/WindowSystem.swift` | `WindowInventory.liveWindows` (nil = unknown), `WindowEvent.liveWindowsChanged` | ✓ VERIFIED |
| `Sources/PaneEngine/LayoutRestore.swift` | `isAlive(_:in:)`, `reattach(_:tracked:live:)` | ✓ VERIFIED |
| `Sources/PaneEngine/Arranger.swift` | `wakeDormant`, `hasDormantWindows`, `closeDormant`, `planShown` untracked skip | ✓ VERIFIED |
| `Sources/PaneTestSupport/FakeWindowSystem.swift` | `liveWindows` from the fake's CG-like list (nil while locked) | ✓ VERIFIED |
| `Sources/PaneMac/AXWindowSystem.swift` | `liveWindows` per sweep (threaded apps, layer 0), `.liveWindowsChanged` on an ID-set change | ✓ VERIFIED |
| `Sources/PaneMac/ArrangeController.swift` | feeds `.inventory` on `.liveWindowsChanged` while `hasDormantWindows` | ✓ VERIFIED |
| `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift` | fresh-fake relaunch, dormant, changed-tile, new-pid and prune cases (10 tests) | ✓ VERIFIED |

### Key Link Verification

`verify.key-links` cannot parse the 03-23 `from:` values, which contain a symbol, so it exits 1 with "Source file not found". I checked the links by hand against the diff 081bcf4..HEAD:

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| AXWindowSystem `sweep()` (~296) | `LayoutRestore.reattach(_:tracked:live:)` | `inventory().liveWindows` (nil while sessionPaused) -> `Arranger.process(.inventory)` restore branch -> private `reattach(…, live:)` | WIRED |
| AXWindowSystem `sweep()` `emit([.liveWindowsChanged])` | Arranger `.inventory` prune | ArrangeController `feed = true` when `.liveWindowsChanged` and `arranger.hasDormantWindows` -> `.inventory` non-restore branch -> `closeDormant` | WIRED |
| Arranger `handle(.windowCreated)` | `planShown()` | `wakeDormant` seeds `lastRequested[id] = info.frame` for a docked window, so `planShown` writes only a changed tile | WIRED (pinned by `aDormantWindowWhoseTileChangedIsWrittenOnceToItsNewTile`) |

The links for 03-01..03-22 are unchanged since cb0ea7c.

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
| -------- | ---- | ------ | --------- | ------ |
| layout.json restore | saved World -> `reattach(tracked:live:)` | `LayoutStore` -> `.restore`; live CG optionAll layer-0 entries of threaded apps | yes. Hidden-Space windows now flow through `live` | FLOWING (nil-CG edge: advisory) |
| Dormant prune | `liveWindows` ID set | each sweep's `CGWindowList.snapshot()` | yes | FLOWING |
| Green-button swallow, command target, min-size hints | as in cb0ea7c | live CG and AX | yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Live gate | `IntegrationEnv.trusted = AXIsProcessTrusted() && PANE_LIVE == "1"`; `PANE_LIVE` unset | gated | PASS |
| Headless suites (one full run) | `env -u PANE_LIVE swift test` | exit 0: 193 + 196 + 42 + 502 tests passed (the FreezeTest flake passed this time) | PASS |
| The G-03-8 tests catch the bug | `swift test --filter ArrangerMultiDeskRestoreTests` in a scratch worktree at fbfa115 (RED) | `aDeskOnASpaceNotShown…` (.normal, .recovery), `aDormantWindowWhoseTileChanged…` and `twoDisplaysWithTwoSpaces…` fail; `aSavedWindowWhoseAppRelaunchedIsRemoved` passes (VIEW-04 boundary). Worktree removed | PASS (RED confirmed) |
| No AppKit in Model/Engine | `scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | PASS |
| Notarised DMG | `stapler validate`, `spctl -a -t open` | worked; accepted, Notarized Developer ID | PASS (stale build) |
| Live AX suites | not run (host rule; I avoided the VM too) | 03-23 reports SpacesIntegrationTests 2/2, QuitRestoreIntegrationTests 2/2 and LiveTrackingTests 6/6 in the VM | SKIP |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist and no plan declares a probe. Not applicable.

### Requirements Coverage

All 26 phase IDs are claimed by at least one plan (WIN-04 also appears, as an extra Phase 2 ID in 03-22). None is orphaned.

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| TILE-01, TILE-02 | SATISFIED | UAT 2; drag tests |
| TILE-03 | SATISFIED (docked-Safari close: human item 5) | UAT 3 re-run; reflow tests |
| TILE-04 | SATISFIED | UAT 3 Gaps menu |
| TILE-05 | SATISFIED (feel: human) | G-03-3 tests; UAT 3 re-run |
| TILE-06 | SATISFIED (hand click: human) | UAT 4 re-run via VNC; `TopmostWindowTests` |
| TILE-07 | SATISFIED | UAT 14 re-run |
| TILE-08 | SATISFIED | UAT 6 Pause/Resume |
| TILE-09 | SATISFIED | UAT 6 re-run; `PendingFocusTests` |
| TILE-10 | SATISFIED | UAT 12 |
| TILE-11..14 | SATISFIED | UAT 5; edit and snap tests |
| TILE-15, TILE-16, TILE-18 | SATISFIED | UAT 6 and 7 |
| TILE-17 | SATISFIED | UAT 7 re-run (split-finder with Finder windows open) |
| TILE-19 | SATISFIED | UAT 4 re-run (Option-click zooms, then D-33) |
| TILE-20 | SATISFIED | UAT 4 minimise |
| WIN-07 | SATISFIED | UAT 4 fullscreen return. REQUIREMENTS.md still has `[ ]` / Pending (bookkeeping) |
| SAFE-01, SAFE-02, SAFE-03, SAFE-04 | SATISFIED | UAT 8, 9, 7, 11 |
| SAFE-06 | SATISFIED (display half: human) | 03-23; RED/GREEN re-run here; VM cycles; UAT 17 Space half |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Sources and the 03-23 test files | — | TBD/FIXME/XXX/TODO/HACK | none | — |
| Sources/PaneEngine/Arranger.swift | ~205 | `inventory.liveWindows ?? []` at restore: unknown is treated as none alive | ⚠️ Warning (advisory) | Falls back to dropping hidden-Space desks if the first complete inventory has no CG list |
| Sources/PaneEngine/CloseRule.swift | 46-47 | CG presence alone blocks every close | ℹ️ Info (deferred G-03-9) | Safari ghost windows stay tracked; possibly a delayed reflow for a docked Safari window (human item 5) |
| 03-23 diff (fbfa115..812678a) | — | not covered by 03-REVIEW.md (diff base 53d5faa, reviewed 00:50Z, before 03-23) | ℹ️ Info | Run `/gsd-code-review` on the 03-23 diff before ship |
| build/Pane-0.3.0.dmg | — | built 2026-10-26 08:16, before every UAT, gap and review fix | ⚠️ Warning | Rebuild before any tester distribution |
| .planning/ROADMAP.md | Phase 3 | 03-18..03-23 still `[ ]`, "17/23 plans executed" | ℹ️ Info | Bookkeeping |
| .planning/REQUIREMENTS.md | 29, 172 | WIN-07 `[ ]` / Pending | ⚠️ Warning | Live-verified; tick it |
| .planning/phases/03-tiling-mvp/03-UAT.md | frontmatter, Summary | `status: partial`, the counts and `updated:` predate the re-run section | ℹ️ Info | Bookkeeping |
| Tests/PaneMacTests/FreezeTestTests.swift | 58 | timing-sensitive | ℹ️ Info | Passed in this run; a known CI flake |

### Human Verification Required

The frontmatter `human_verification` list has the same 5 items.

1. **Green button by hand (VM).** Plain click and Option-click on docked and floating windows, plus Dock-tile and context-menu overlays, plus a plain click on an Option-zoomed floater. Expected: toggles with no fullscreen; Option zooms, then D-33 returns the window; the overlay owns its click; the zoomed floater docks or D-26 beeps.
2. **Gap drag by hand (VM, UAT 3).** Expected: smooth, no snap-back, the split sticks.
3. **Host, two displays: Hide Desktop (UAT 16).** Expected: nothing parks onto the other display.
4. **Host, two displays and Spaces: relaunch, clean and kill -9 (UAT 17, display half).** Expected: each display and Space restores its own layout.
5. **Docked Safari close (VM).** Dock Safari beside TextEdit, then press Cmd-W on Safari. Expected: TextEdit reflows. If it doesn't, the G-03-9 deferral ("bookkeeping only") understates the impact on TILE-03, and you should decide whether Phase 6 is still the right home for it.

### Gaps Summary

No blocking gaps remain. G-03-8 (SC4/SAFE-06) is closed: saved windows on a Space that is not shown stay dormant while the CG list still has them, re-attach in their tiles on their first `windowCreated`, and are pruned when they close or their app quits. I confirmed the new tests fail on the pre-fix code and pass at HEAD, so they reproduce the production failure and are not a fixture artefact. The VM runs (clean, kill -9, prune) and UAT 17's Space half agree. G-03-9 is deferred to Phase 6 by user decision, and the Phase 6 scope note names it.

What remains is human confirmation: hand feel for the green button and gap drag, the two tests that need the host's second display, and one check of whether G-03-9's root cause also stalls the reflow after a docked Safari window closes. Also before ship: a code review of the 03-23 diff, a fresh notarised build, and the WIN-07, ROADMAP and UAT bookkeeping.

---

_Verified: 2026-10-27T03:00:24Z_
_Verifier: Claude (gsd-verifier)_
