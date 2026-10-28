---
phase: 03-tiling-mvp
verified: 2026-10-28T02:34:09Z
status: passed
score: 17/17 must-haves verified
covered_files: [".github/workflows/ci.yml",".planning/phases/03-tiling-mvp/03-01-PLAN.md",".planning/phases/03-tiling-mvp/03-01-SUMMARY.md",".planning/phases/03-tiling-mvp/03-02-PLAN.md",".planning/phases/03-tiling-mvp/03-02-SUMMARY.md",".planning/phases/03-tiling-mvp/03-03-PLAN.md",".planning/phases/03-tiling-mvp/03-03-SUMMARY.md",".planning/phases/03-tiling-mvp/03-04-PLAN.md",".planning/phases/03-tiling-mvp/03-04-SUMMARY.md",".planning/phases/03-tiling-mvp/03-05-PLAN.md",".planning/phases/03-tiling-mvp/03-05-SUMMARY.md",".planning/phases/03-tiling-mvp/03-06-PLAN.md",".planning/phases/03-tiling-mvp/03-06-SUMMARY.md",".planning/phases/03-tiling-mvp/03-07-PLAN.md",".planning/phases/03-tiling-mvp/03-07-SUMMARY.md",".planning/phases/03-tiling-mvp/03-08-PLAN.md",".planning/phases/03-tiling-mvp/03-08-SUMMARY.md",".planning/phases/03-tiling-mvp/03-09-PLAN.md",".planning/phases/03-tiling-mvp/03-09-SUMMARY.md",".planning/phases/03-tiling-mvp/03-10-PLAN.md",".planning/phases/03-tiling-mvp/03-10-SUMMARY.md",".planning/phases/03-tiling-mvp/03-11-PLAN.md",".planning/phases/03-tiling-mvp/03-11-SUMMARY.md",".planning/phases/03-tiling-mvp/03-12-PLAN.md",".planning/phases/03-tiling-mvp/03-12-SUMMARY.md",".planning/phases/03-tiling-mvp/03-13-PLAN.md",".planning/phases/03-tiling-mvp/03-13-SUMMARY.md",".planning/phases/03-tiling-mvp/03-14-PLAN.md",".planning/phases/03-tiling-mvp/03-14-SUMMARY.md",".planning/phases/03-tiling-mvp/03-15-PLAN.md",".planning/phases/03-tiling-mvp/03-15-SUMMARY.md",".planning/phases/03-tiling-mvp/03-16-PLAN.md",".planning/phases/03-tiling-mvp/03-16-SUMMARY.md",".planning/phases/03-tiling-mvp/03-17-PLAN.md",".planning/phases/03-tiling-mvp/03-17-SUMMARY.md",".planning/phases/03-tiling-mvp/03-18-PLAN.md",".planning/phases/03-tiling-mvp/03-18-SUMMARY.md",".planning/phases/03-tiling-mvp/03-19-PLAN.md",".planning/phases/03-tiling-mvp/03-19-SUMMARY.md",".planning/phases/03-tiling-mvp/03-20-PLAN.md",".planning/phases/03-tiling-mvp/03-20-SUMMARY.md",".planning/phases/03-tiling-mvp/03-21-PLAN.md",".planning/phases/03-tiling-mvp/03-21-SUMMARY.md",".planning/phases/03-tiling-mvp/03-22-PLAN.md",".planning/phases/03-tiling-mvp/03-22-SUMMARY.md",".planning/phases/03-tiling-mvp/03-23-PLAN.md",".planning/phases/03-tiling-mvp/03-23-SUMMARY.md",".planning/phases/03-tiling-mvp/03-24-PLAN.md",".planning/phases/03-tiling-mvp/03-24-SUMMARY.md",".planning/phases/03-tiling-mvp/03-25-PLAN.md",".planning/phases/03-tiling-mvp/03-25-SUMMARY.md",".planning/phases/03-tiling-mvp/03-26-PLAN.md",".planning/phases/03-tiling-mvp/03-26-SUMMARY.md","Package.resolved","Package.swift","Sources/TransomEngine/Arranger+Commands.swift","Sources/TransomEngine/Arranger.swift","Sources/TransomEngine/CloseRule.swift","Sources/TransomEngine/Command.swift","Sources/TransomEngine/ConflictPolicy.swift","Sources/TransomEngine/DragSession.swift","Sources/TransomEngine/GapHandles.swift","Sources/TransomEngine/LayoutFile.swift","Sources/TransomEngine/LayoutRestore.swift","Sources/TransomEngine/LifecycleSync.swift","Sources/TransomEngine/MinimumSizeLearner.swift","Sources/TransomEngine/Notice.swift","Sources/TransomEngine/PendingFocus.swift","Sources/TransomEngine/PermissionReducer.swift","Sources/TransomEngine/Planner.swift","Sources/TransomEngine/Recovery.swift","Sources/TransomEngine/TransomURL.swift","Sources/TransomEngine/WindowSnapshot.swift","Sources/TransomEngine/WindowSystem.swift","Sources/TransomEngine/WindowTracker.swift","Sources/TransomFixtureApp/main.swift","Sources/TransomMac/AX/AXAppThread.swift","Sources/TransomMac/AX/AXSnapshotReader.swift","Sources/TransomMac/AX/MenuPress.swift","Sources/TransomMac/AXWindowSystem.swift","Sources/TransomMac/AppDelegate.swift","Sources/TransomMac/ArrangeController.swift","Sources/TransomMac/CGWindowList.swift","Sources/TransomMac/ConflictController.swift","Sources/TransomMac/Displays.swift","Sources/TransomMac/GapPreference.swift","Sources/TransomMac/Input/DragFramePoller.swift","Sources/TransomMac/Input/GreenButton.swift","Sources/TransomMac/Input/Hotkeys.swift","Sources/TransomMac/Input/InputTap.swift","Sources/TransomMac/LayoutStore.swift","Sources/TransomMac/MinimumHintsStore.swift","Sources/TransomMac/Overlay/GapHandlePanels.swift","Sources/TransomMac/Overlay/NoticeQueue.swift","Sources/TransomMac/Overlay/PreviewPanel.swift","Sources/TransomMac/Overlay/PreviewStyle.swift","Sources/TransomMac/Overlay/Toast.swift","Sources/TransomMac/Shell/CommandMenu.swift","Sources/TransomMac/Shell/ConflictCopy.swift","Sources/TransomMac/Shell/MenuCopy.swift","Sources/TransomMac/Shell/NoticeCopy.swift","Sources/TransomMac/Shell/StatusItemController.swift","Sources/TransomMac/TransomMacApp.swift","Sources/TransomMac/WindowManagerSettings.swift","Sources/TransomModel/DesktopLayer.swift","Sources/TransomModel/DropZones.swift","Sources/TransomModel/IDs.swift","Sources/TransomModel/LayoutTree.swift","Sources/TransomModel/Neighbours.swift","Sources/TransomModel/Resolve.swift","Sources/TransomModel/Snap.swift","Sources/TransomModel/TreeEdits.swift","Sources/TransomModel/Undo.swift","Sources/TransomModel/World.swift","Sources/TransomPrivate/SkyLightSpaces.swift","Sources/TransomTestSupport/FakeWindowSystem.swift","Tests/TransomEngineTests/ArrangerCommandTests.swift","Tests/TransomEngineTests/ArrangerDesktopTests.swift","Tests/TransomEngineTests/ArrangerDragTests.swift","Tests/TransomEngineTests/ArrangerExclusionTests.swift","Tests/TransomEngineTests/ArrangerFinderTests.swift","Tests/TransomEngineTests/ArrangerFocusTests.swift","Tests/TransomEngineTests/ArrangerGreenButtonTests.swift","Tests/TransomEngineTests/ArrangerLifecycleTests.swift","Tests/TransomEngineTests/ArrangerMultiDeskRestoreTests.swift","Tests/TransomEngineTests/ArrangerPauseTests.swift","Tests/TransomEngineTests/ArrangerReflowTests.swift","Tests/TransomEngineTests/ArrangerResizeTests.swift","Tests/TransomEngineTests/ArrangerRestoreTests.swift","Tests/TransomEngineTests/ArrangerSpacesTests.swift","Tests/TransomEngineTests/CommandTests.swift","Tests/TransomEngineTests/ConflictPolicyTests.swift","Tests/TransomEngineTests/DragSessionTests.swift","Tests/TransomEngineTests/FrameScenarioTests.swift","Tests/TransomEngineTests/GapHandleGeometryTests.swift","Tests/TransomEngineTests/LifecycleSyncTests.swift","Tests/TransomEngineTests/MinimumSizeLearnerTests.swift","Tests/TransomEngineTests/PendingFocusTests.swift","Tests/TransomEngineTests/PermissionReducerTests.swift","Tests/TransomEngineTests/PlannerTests.swift","Tests/TransomEngineTests/RecoveryTests.swift","Tests/TransomEngineTests/TooBigDockedWindowTests.swift","Tests/TransomEngineTests/TrackerDisplayTests.swift","Tests/TransomEngineTests/TransomURLTests.swift","Tests/TransomEngineTests/WantedFrameTests.swift","Tests/TransomMacIntegrationTests/ArrangeIntegrationTests.swift","Tests/TransomMacIntegrationTests/ButtonFrameIntegrationTests.swift","Tests/TransomMacIntegrationTests/FocusParkIntegrationTests.swift","Tests/TransomMacIntegrationTests/InputTapIntegrationTests.swift","Tests/TransomMacIntegrationTests/IntegrationSupport.swift","Tests/TransomMacIntegrationTests/MenuPressIntegrationTests.swift","Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift","Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift","Tests/TransomMacIntegrationTests/SpacesIntegrationTests.swift","Tests/TransomMacIntegrationTests/TitleBarDragIntegrationTests.swift","Tests/TransomMacTests/AppDelegateTests.swift","Tests/TransomMacTests/CapabilitiesTests.swift","Tests/TransomMacTests/CommandMenuTests.swift","Tests/TransomMacTests/ConflictControllerTests.swift","Tests/TransomMacTests/ConflictCopyTests.swift","Tests/TransomMacTests/GapPreferenceTests.swift","Tests/TransomMacTests/GreenButtonHitTests.swift","Tests/TransomMacTests/HotkeyTableTests.swift","Tests/TransomMacTests/LayoutStoreTests.swift","Tests/TransomMacTests/MenuCopyTests.swift","Tests/TransomMacTests/MenuPressTests.swift","Tests/TransomMacTests/MinimumHintsStoreTests.swift","Tests/TransomMacTests/NoScreenCaptureTests.swift","Tests/TransomMacTests/NoticeCopyTests.swift","Tests/TransomMacTests/NoticeQueueTests.swift","Tests/TransomMacTests/PreviewStyleTests.swift","Tests/TransomMacTests/TopmostWindowTests.swift","Tests/TransomMacTests/WakeTimerTests.swift","Tests/TransomMacTests/WindowManagerSettingsTests.swift","Tests/TransomModelTests/DesktopLayerTests.swift","Tests/TransomModelTests/DesktopLeafTests.swift","Tests/TransomModelTests/LayoutEditTests.swift","Tests/TransomModelTests/LifecycleTests.swift","Tests/TransomModelTests/NeighbourTests.swift","Tests/TransomModelTests/PersistenceTests.swift","Tests/TransomModelTests/ResolveFuzzTests.swift","Tests/TransomModelTests/ResolveTests.swift","Tests/TransomModelTests/ScenarioTests.swift","Tests/TransomModelTests/SkeletonTests.swift","Tests/TransomModelTests/SnapTests.swift","Tests/TransomModelTests/TabsTests.swift","Tests/TransomModelTests/TreeEditTests.swift","Tests/TransomModelTests/UndoTests.swift","Tests/TransomModelTests/WorldRekeyTests.swift","scripts/check-no-appkit.sh","scripts/release.sh","scripts/vm-live-test.sh","xcode/Transom-Info.plist","xcode/Transom.entitlements","xcode/project.yml"]
covered_digest: "v4:sha256:a23cdc10644cfbc8f82b6608e0db53d2e42f96aa1538612f1855260fbdd5a846"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: passed
  previous_score: 17/17
  reason: "Stale fingerprint only: quick 261027-ijh (221fd39) renamed Pane to Transom (Sources/Pane* -> Sources/Transom*, Tests/Pane*Tests -> Tests/Transom*Tests, PaneURL -> TransomURL, xcode/Pane-Info.plist -> xcode/Transom-Info.plist, pane:// -> transom://, bundle IDs, data folder, PANE_* -> TRANSOM_*)"
  gaps_closed:
    - "Prior Anti-Patterns warning (notarised DMG predates the fixes; rebuild as Transom before release): build/Transom-0.3.0.dmg (2026-10-27 14:24, after the rename) is Notarized Developer ID, stapled, and holds Transom.app com.eightabyte.transom 0.3.0 with the transom URL scheme"
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "G-03-9: closing a window removes it from Transom's tracking and layout.json (Safari keeps a Space-less, layer-0 CG entry for a closed window)"
    addressed_in: "Phase 6"
    evidence: "ROADMAP Phase 6 scope note: 'Also closes deferred G-03-9: a window whose only CG entry has no Space (Safari keeps closed windows' entries for minutes) must count as closed, not alive'. User decision 2026-10-26"
  - truth: "Human items 2-5 from the 2026-10-27 run (wanted-frame relaunch in the VM; UAT 16 and the display half of UAT 17 with WR-04 on the DELL second display; a Dock tile over a docked window's green button)"
    addressed_in: "Re-check on the first Transom build (STATE.md Pending Todos)"
    evidence: "User decision 2026-10-27 (e1d443a). Headless tests cover each case and pass at HEAD (twoDisplaysWithTwoSpacesEach..., WantedFrameTests, the CR-02 park tests). STATE.md Pending Todos line 263 lists the re-check"
advisory:
  - finding: "undockedWanted (WR-02 fix) is cleared only by Undo, forget and rekey. A window undocked by Float All or a shift-drag and then docked again by drag or Dock keeps the old entry, so a later Undo can give back an older pre-dock frame"
    category: other
    reason: "Carried unchanged: Arranger.swift:114/905 and Arranger+Commands.swift:144 are identical to the pre-rename code apart from module paths. Worst case is a stale Float target; no overlap, no data loss. Marked 'shortcut:' at Arranger.swift:112. To resolve, clear undockedWanted[id] wherever a window docks other than through undo"
    evidence_status: "none provided: no test or VM run shows it"
---

# Phase 3: Tiling MVP Verification Report

**Phase Goal:** As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp (user-story goal, validated in earlier runs; text unchanged)
**Verified:** 2026-10-28T02:34:09Z
**Status:** passed
**Re-verification:** Yes. This is a rename-regression re-run. The previous report (2026-10-27T18:18:26Z, passed, 17/17) went stale only because quick 261027-ijh renamed the project from Pane to Transom. Plans, summaries and ROADMAP history still use the old names. Mapping: `Sources/Pane{Model,Engine,Mac,Private,App,FixtureApp,TestSupport}` -> `Sources/Transom*`, `Tests/Pane*Tests` -> `Tests/Transom*Tests`, `PaneURL` -> `TransomURL`, `PaneMacApp.swift` -> `TransomMacApp.swift`, `xcode/Pane-Info.plist` -> `xcode/Transom-Info.plist`, `xcode/Pane.entitlements` -> `xcode/Transom.entitlements`, `pane://` -> `transom://`, `pane-debug://` -> `transom-debug://`, `PANE_LIVE` -> `TRANSOM_LIVE`, `com.eightabyte.pane` -> `com.eightabyte.transom`, `Application Support/Pane` -> `Application Support/Transom`.

## Rename regression check (the point of this run)

1. **The rename commit is mechanical (independently re-derived, not taken from the ijh SUMMARY).** I extracted the tree at 82697cf (Phase 3 complete, before the rename) and rewrote it with token rules `Pane(?!l)` -> `Transom`, `pane(?!l)` -> `transom` and `PANE(?!L)` -> `TRANSOM`, applied to both paths and contents. I then ran `diff -r` against the tree at 221fd39 for `Sources Tests Package.swift scripts xcode .github`. **The only remaining differences** are in `scripts/release.sh` (notary keychain profile kept as `pane-notary`) and `scripts/vm-live-test.sh` (Tart VM `pane-test` and SSH key `pane_vm_ed25519` kept). Both are deliberate kept names for existing host resources. No Swift source, test, Package.swift, project.yml, Info.plist, entitlements or CI line differs beyond the rename. "panel"/`NSPanel`/`.panel` were untouched.
2. **After the rename, later commits touched only Phase 2 code.** These are 02-18, 02-19 and the 02 review fixes: `TabGroupTracker.swift`, a 2-line `listed:` argument in `WindowTracker.swift`, a `#if DEBUG` test seam in `PermissionController.swift`, `SetupWindowController.swift` and `FakeWindowSystem` tab-frame semantics. They come with their own tests and were verified by the Phase 2 re-verification (d623731). Phase 3 suites that depend on `FakeWindowSystem` still pass (below).
3. **Renamed wiring is consistent end to end:**
   - `xcode/project.yml` sets `TRANSOM_URL_SCHEME` to `transom` (Release) and `transom-debug` (Debug). `Transom-Info.plist` puts `$(TRANSOM_URL_SCHEME)` in `CFBundleURLSchemes`. `AppDelegate.registeredScheme()` reads it back from the bundle, and `TransomURL.parse(url, scheme:)` checks it (AppDelegate.swift:55,69; TransomMacApp.swift:98).
   - The data folder is `MinimumHintsStore.defaultDirectory` = `Application Support/Transom`. Both the hints store and `LayoutStore` use it (TransomMacApp.swift:41,58).
   - The live gate is `TRANSOM_LIVE` in IntegrationSupport.swift:9, and `scripts/vm-live-test.sh` passes `TRANSOM_LIVE=1`.
   - `check-no-appkit.sh` defaults to `Sources/TransomModel Sources/TransomEngine`.
   - CI runs `swift test`.
   - No word `pane` remains in `Sources/` or `Tests/` (`grep -rniw pane | grep -vi panel` is empty).

Conclusion: the rename brought no functional regression to Phase 3.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| ---- | -------- | -------------------- | ------ |
| Drag a window by its title bar to an edge | A preview appears and the window docks on release, at any depth | `ArrangerDragTests` (TransomEngineTests) pass; UAT 2 live | VERIFIED |
| Windows open | New windows float on the Desktop tile and never auto-split | `PlannerTests` pass; UAT 14 | VERIFIED |
| Windows close, minimise, go fullscreen | Neighbours reflow; minimised and fullscreen windows return | Reflow tests; UAT 3 and 4 re-runs | VERIFIED |
| Resize by gap | Both sides follow, the split sticks, floaters keep their size | G-03-3 tests, `WantedFrameTests` (8/8 pass in this run) | VERIFIED |
| Green button | Docked floats to its pre-dock frame; floating docks, including a floater that fills the Desktop tile | `ArrangerGreenButtonTests` and `GreenButtonTrackingTests` pass in this run | VERIFIED |
| Outcome: windows never overlap | A docked window that can't fit floats; a too-big floater doesn't float the desk | `TooBigDockedWindowTests`, `RefusalRetryBoundTests`; UAT 15 | VERIFIED (accepted T-03-58 overlap of a floater that can't shrink) |
| Layout survives a Transom relaunch | Each layout comes back, including after a locked start | `ArrangerMultiDeskRestoreTests` and `LayoutStoreTests` pass in this run; VM on 0.3.7..0.3.9 | VERIFIED (display half and wanted-frame relaunch deferred by the user) |

## Goal Achievement

### Observable Truths

Truths 1-17 carry over from the previous report. Each was re-checked against the renamed files: they exist, they are mechanically identical, and the full headless suite passes.

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | SC1: title-bar drag docks with a preview at any depth; bypass moves freely; new windows float; the green button toggles docked/floating | ✓ VERIFIED | `Sources/TransomEngine/{DragSession,Arranger,Planner}.swift`, `Sources/TransomMac/Input/InputTap.swift`. Green-button suites pass in this run. UAT 2 and 14; VM run on 0.3.11 |
| 2 | SC2: close reflows; gap drag resizes both; gap size is settable; a window leaving fullscreen returns to its tile | ✓ VERIFIED | Full suite passes (orchestrator run: 564 tests in 54 suites at HEAD). UAT 3 and 4 re-runs |
| 3 | SC3: menu and hotkeys through one dispatcher; undo; pause/resume; Restore all; `transom://restore` (ROADMAP text still says `pane://restore`) | ✓ VERIFIED | `TransomURLTests` pass in this run: `transom://restore`, `toggle-desktop`, `split-finder`, `transom-debug://` under the debug scheme, and rejection of the variant forms. The scheme is wired from project.yml through Info.plist and `registeredScheme()` to `TransomURL.parse`. The Release Transom.app Info.plist has scheme `transom`. UAT 6 and 7 |
| 4 | SC4: quit restore; crash rescue; conflicts; relaunch with apps running brings each layout back | ✓ VERIFIED | `LayoutStoreTests` (8) and `ArrangerMultiDeskRestoreTests` pass in this run. `LayoutStore` and `MinimumHintsStore` share `Application Support/Transom`. UAT 8, 9 and 11 |
| 5 | SC5: works with zoom absent and Screen Recording denied; Developer ID signed and notarised; the grant survives updates | ✓ VERIFIED | **Rename re-check:** `build/Transom-0.3.0.dmg` (2026-10-27 14:24, after 221fd39). `stapler validate` worked. `spctl` says accepted, `source=Notarized Developer ID`, `origin=Developer ID Application: Ken Scott (S2K7P43927)`. Mounted read-only, it holds `Transom.app`: `com.eightabyte.transom`, 0.3.0, scheme `transom`, spctl accepted, stapled. Designated requirement: `identifier "com.eightabyte.transom" and ... leaf[subject.OU] = S2K7P43927`. That has the same shape (stable identifier plus team) that kept the grant across Pane 0.3.6..0.3.11 in the VM. `Transom.entitlements` is byte-identical to `Pane.entitlements`. `NoScreenCaptureTests` is in the passing suite. UAT 12 |
| 6 | SC6: swap, balance, rotate, flip, move and resize from the keyboard; snap floaters | ✓ VERIFIED | `LayoutEditTests`, `SnapTests` and `ArrangerCommandTests` are in the passing suite. UAT 5 |
| 7 | SC7: hide/show the Desktop, arrange all, float all, Finder split, Don't Arrange; Option-click zoom; a minimised docked window returns | ✓ VERIFIED | Passing suite. UAT 4, 6 and 7 |
| 8 | G-03-3: a gap drag beside a pinned side moves that gap; no mid-drag event writes the pre-drag tiles | ✓ VERIFIED | Passing suite; hand checks on 0.3.8 and 0.3.10 |
| 9 | G-03-5: a second window of an app with a docked window becomes the command target | ✓ VERIFIED | `PendingFocusTests` in the passing suite |
| 10 | G-03-6: a docked window that can't fit floats instead of overlapping; one too-big floater doesn't float the desk | ✓ VERIFIED | `TooBigDockedWindowTests` in the passing suite |
| 11 | G-03-8: desks on a Space not shown at relaunch keep their windows; a dormant window is pruned when it closes | ✓ VERIFIED | `ArrangerMultiDeskRestoreTests` pass in this run (incl. `aDeskOnASpaceNotShownAtRelaunchKeepsItsWindowsInTheirTiles`, `aDormantWindowIsPrunedWhenItsAppTerminates`) |
| 12 | G-03-10: a start while locked keeps every saved desk once the screen is unlocked | ✓ VERIFIED | `aStartWhileLockedKeepsEveryDeskOnceUnlocked` passes in this run |
| 13 | G-03-11: a gap drag that shrinks and then grows the Desktop returns floaters to their frames; a floater that refuses to shrink stops the drag at its real size | ✓ VERIFIED | `aDesktopThatShrinksAndGrowsBackReturnsFloatersToTheirFrames` and the rest of `WantedFrameTests` pass in this run |
| 14 | G-03-4: Float puts a docked window at its clamped pre-dock frame or a centred 90% frame; docking fills the tile | ✓ VERIFIED | See truth 1 |
| 15 | 03-26: wanted frames are saved in layout.json and validated like home frames; older files load with none; stranded saved wanted frames are dropped | ✓ VERIFIED | `WantedFrameTests` and `LayoutStoreTests` pass in this run. Live relaunch deferred by the user |
| 16 | 03-26 review fixes CR-01, WR-01, WR-02 | ✓ VERIFIED | `WantedFrameTests` 8/8 pass in this run. VM on 0.3.11 |
| 17 | quick 261027-gqo (TILE-06): a plain green click on a floater that exactly fills the Desktop tile docks it; Dock at the exact centre ties left | ✓ VERIFIED | `aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt` is in `ArrangerGreenButtonTests` (passing in this run). The RED re-run was done in the previous report. Planner.swift is mechanically identical after the rename |

**Score:** 17/17 truths verified (0 present but behaviour-unverified). No truth rests on a coincidental precondition.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | G-03-9: a closed Safari window stays tracked in a running session | Phase 6 | ROADMAP Phase 6 scope note names G-03-9 |
| 2 | Human items 2-5: wanted-frame relaunch (VM); UAT 16 and display half of UAT 17 with WR-04 (DELL); Dock tile over a docked window's green button (VM) | First Transom build | User decision 2026-10-27 (e1d443a); STATE.md Pending Todos. The rename does not change what these checks test. They were already scheduled for a Transom build |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | `undockedWanted` is not cleared when a window docks again by drag or Dock rather than Undo | other | Carried. Code unchanged; no deterministic evidence; worst case is a stale Float target |

The rename adds no new advisories.

### Required Artifacts

All 142 implementation files from the previous report's `covered_files` exist at their Transom paths. I checked each mapped path with `[ -e ]`: none is missing. `xcode/Transom.entitlements` is added to the coverage set for SC5. Between 82697cf and HEAD, every artifact is identical to its pre-rename version apart from the token rename, except the post-rename Phase 2 files listed above.

| Artifact (old -> current) | Status |
| ------------------------- | ------ |
| `Sources/PaneEngine/*` -> `Sources/TransomEngine/*` (incl. `PaneURL.swift` -> `TransomURL.swift`) | ✓ VERIFIED (mechanical) |
| `Sources/PaneMac/*` -> `Sources/TransomMac/*` (incl. `PaneMacApp.swift` -> `TransomMacApp.swift`) | ✓ VERIFIED (mechanical) |
| `Sources/PaneModel/*`, `PanePrivate`, `PaneTestSupport`, `PaneFixtureApp` -> `Transom*` | ✓ VERIFIED (mechanical; `FakeWindowSystem` later changed by Phase 2 only) |
| `Tests/Pane{Model,Engine,Mac,MacIntegration}Tests` -> `Tests/Transom*Tests` | ✓ VERIFIED (mechanical) |
| `xcode/Pane-Info.plist` -> `xcode/Transom-Info.plist`; `xcode/project.yml` | ✓ VERIFIED (scheme via `$(TRANSOM_URL_SCHEME)`; bundle IDs `com.eightabyte.transom(.debug)`; team S2K7P43927; hardened runtime) |
| `scripts/release.sh`, `scripts/vm-live-test.sh`, `scripts/check-no-appkit.sh` | ✓ VERIFIED (kept host-resource names are documented in comments) |

### Key Link Verification

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| project.yml `TRANSOM_URL_SCHEME` | Info.plist `CFBundleURLSchemes` | `$(TRANSOM_URL_SCHEME)` in Transom-Info.plist:12; the built Release app shows `transom` | WIRED |
| AppDelegate URL event | `TransomURL.parse` -> dispatcher | AppDelegate.swift:55 with `registeredScheme()` (:69), passed in at TransomMacApp.swift:98 | WIRED |
| LayoutStore / MinimumHintsStore | `Application Support/Transom` | MinimumHintsStore.swift:20; TransomMacApp.swift:41,58 | WIRED |
| Live integration gate | `TRANSOM_LIVE=1` | IntegrationSupport.swift:9; vm-live-test.sh:52 | WIRED |
| All key links from the previous report (effect runner -> `ArrangeController.post`, ConflictController N7/N8 -> `post`, `.announce` -> logger, save/restore paths) | — | mechanically identical files | WIRED (regression) |

### Data-Flow Trace (Level 4)

Unchanged from the previous report. The rename touched only identifiers, the logger subsystem (`com.eightabyte.transom`) and the data-folder name. Wanted frames, floater floors, layout.json wanted frames and the restore gate still flow from real sources.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Rename is mechanical | token-normalised `diff -r` of 82697cf against 221fd39 | only the documented kept names in release.sh and vm-live-test.sh | PASS |
| Live gate off | `env \| grep -c -E '^(TRANSOM\|PANE)_LIVE'` | 0 | PASS |
| No AppKit in Model and Engine | `scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | PASS |
| Named Phase 3 suites | `swift test --filter "TransomURLTests\|ArrangerGreenButtonTests\|WantedFrameTests\|ArrangerMultiDeskRestoreTests\|LayoutStoreTests"` | TransomEngineTests: 42 tests in 5 suites passed. TransomMacTests: `LayoutStoreTests` 8 tests passed | PASS |
| Full headless suite | orchestrator's single `swift test` at HEAD | 564 tests in 54 suites pass. TransomMacTests 200 pass apart from an intermittent `FreezeTestTests.itResumesByItself` (a Phase 2 timing test) | PASS |
| Release app signature | `codesign -d -r-` and `codesign --verify --strict` on `xcode/.xcode-build/.../Release/Transom.app` | DR identifier `com.eightabyte.transom`, team S2K7P43927; verify ok | PASS |
| Notarised Transom DMG | `xcrun stapler validate`; `spctl -a -t open`; mounted read-only and inspected the app | Notarized Developer ID, stapled; Transom.app 0.3.0, scheme `transom` | PASS |
| Live AX suites / VM | not run (no TRANSOM_LIVE, no Transom launch, no VM) | the UAT record covers 0.3.7..0.3.11 | SKIP |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist, and no plan declares a probe. Not applicable.

### Requirements Coverage

The plans claim all 26 phase IDs (they also claim WIN-04, which REQUIREMENTS maps to Phase 2). REQUIREMENTS.md maps exactly these 26 to Phase 3, so none is orphaned. All are marked Complete, and REQUIREMENTS.md now names Transom (SAFE-01, SAFE-04, SAFE-06).

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| TILE-01, TILE-02 | SATISFIED | UAT 2; drag tests |
| TILE-03 | SATISFIED | UAT 3; reflow tests |
| TILE-04 | SATISFIED | UAT 3 Gaps menu; `GapPreferenceTests` |
| TILE-05 | SATISFIED | G-03-3/G-03-11 tests; `WantedFrameTests` pass in this run |
| TILE-06 | SATISFIED | green-button suites pass in this run; Dock-tile-over-button case deferred by the user |
| TILE-07 | SATISFIED | UAT 14; wanted-frame tests |
| TILE-08 | SATISFIED | UAT 6 |
| TILE-09 | SATISFIED | UAT 6; command and Undo tests |
| TILE-10 | SATISFIED | UAT 12; `NoScreenCaptureTests` |
| TILE-11..14 | SATISFIED | UAT 5; edit and snap tests |
| TILE-15, TILE-17 | SATISFIED | UAT 6 and 7; URL forms now `transom://toggle-desktop`, `transom://split-finder` (`TransomURLTests` pass) |
| TILE-16, TILE-18 | SATISFIED | UAT 6 and 7 |
| TILE-19 | SATISFIED | UAT 4 |
| TILE-20, WIN-07 | SATISFIED | UAT 4 |
| SAFE-01, SAFE-02 | SATISFIED | UAT 8 and 9 |
| SAFE-03 | SATISFIED | UAT 7; `transom://restore` (`TransomURLTests`) |
| SAFE-04 | SATISFIED | UAT 11 |
| SAFE-06 | SATISFIED (display half and wanted-frame relaunch deferred by the user) | `ArrangerMultiDeskRestoreTests` and `LayoutStoreTests` pass in this run; VM 0.3.7..0.3.9 |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| Sources, Tests, scripts | — | TBD/FIXME/XXX/TODO/HACK | none found | — |
| Sources/TransomEngine/Arranger.swift | 112 | `shortcut:` one-level `undockedWanted` (documented WR-02 limit) | ℹ️ Info | Carried |
| .planning/STATE.md | 273, 307-308 | Says the DMG must still be rebuilt as Transom, but `build/Transom-0.3.0.dmg` is already notarised and stapled. Line 307 (Transom not yet installed in the VM; it needs a fresh Accessibility grant there and on the host) is still true | ℹ️ Info | Planning-doc staleness only. The one-time re-grant comes from the new bundle ID, not a Phase 3 defect |
| build/Transom-0.3.0.dmg | — | built 14:24 on 2026-10-27, before the Phase 2 post-rename fixes (15:57 onward) | ℹ️ Info | Rebuild before a tester or public release so it includes the Phase 2 fixes. Phase 3 code in it equals the final Phase 3 code |
| ROADMAP.md Phase 3 SC3/SC4 | — | still say `pane://restore` and "Pane" | ℹ️ Info | History text that the ijh rename deliberately left alone |
| 03-REVIEW-03-26.md, 03-REVIEW-03-23.md, 03-REVIEW.md | IN-* | open Info items | ℹ️ Info (open) | Carried |
| Tests/TransomMacTests/FreezeTestTests.swift | — | timing-sensitive `itResumesByItself` (Phase 2) | ℹ️ Info | Intermittent in the orchestrator's run; not a Phase 3 test |

### Human Verification Required

None. The completed UAT in 03-UAT.md still holds. The rename is mechanical: the token-normalised diff is empty apart from the kept host-resource names, so no UAT result is invalidated. The four remaining live checks were already deferred by the user to the first Transom build (Deferred Items row 2).

### Gaps Summary

No gaps. The rename from Pane to Transom was verified to be purely mechanical for all Phase 3 code, tests, build configuration and CI. The URL scheme, data folder, live-test gate and signing identity are wired consistently under the new names. Named Phase 3 suites pass at the new paths, and the orchestrator's full headless run passes. A notarised, stapled `Transom-0.3.0.dmg` now exists, which closes the previous report's DMG warning. The Phase 3 goal remains achieved.

---

_Verified: 2026-10-28T02:34:09Z_
_Verifier: Claude (gsd-verifier)_
