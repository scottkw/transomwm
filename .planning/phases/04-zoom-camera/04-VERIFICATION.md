---
phase: 04-zoom-camera
verified: 2026-10-28T18:20:00Z
status: human_needed
score: 11/18 must-haves verified
covered_files: [".planning/phases/04-zoom-camera/04-01-PLAN.md", ".planning/phases/04-zoom-camera/04-01-SUMMARY.md", ".planning/phases/04-zoom-camera/04-02-PLAN.md", ".planning/phases/04-zoom-camera/04-02-SUMMARY.md", ".planning/phases/04-zoom-camera/04-03-PLAN.md", ".planning/phases/04-zoom-camera/04-03-SUMMARY.md", ".planning/phases/04-zoom-camera/04-04-PLAN.md", ".planning/phases/04-zoom-camera/04-04-SUMMARY.md", ".planning/phases/04-zoom-camera/04-05-PLAN.md", ".planning/phases/04-zoom-camera/04-05-SUMMARY.md", ".planning/phases/04-zoom-camera/04-06-PLAN.md", ".planning/phases/04-zoom-camera/04-06-SUMMARY.md", ".planning/phases/04-zoom-camera/04-07-PLAN.md", ".planning/phases/04-zoom-camera/04-07-SUMMARY.md", ".planning/phases/04-zoom-camera/04-08-PLAN.md", ".planning/phases/04-zoom-camera/04-08-SUMMARY.md", "Package.swift", "Sources/TransomEngine/Arranger+Camera.swift", "Sources/TransomEngine/Arranger+Commands.swift", "Sources/TransomEngine/Arranger.swift", "Sources/TransomEngine/Command.swift", "Sources/TransomEngine/DragSession.swift", "Sources/TransomEngine/Navigator.swift", "Sources/TransomEngine/Recovery.swift", "Sources/TransomEngine/SettleTracker.swift", "Sources/TransomEngine/TransomURL.swift", "Sources/TransomEngine/ViewPlanner.swift", "Sources/TransomMac/ArrangeController.swift", "Sources/TransomMac/Displays.swift", "Sources/TransomMac/Input/Hotkeys.swift", "Sources/TransomMac/Input/InputTap.swift", "Sources/TransomMac/Input/ZoomTapRules.swift", "Sources/TransomMac/Overlay/PreviewPanel.swift", "Sources/TransomMac/Overlay/PreviewStyle.swift", "Sources/TransomMac/Overlay/Toast.swift", "Sources/TransomMac/Shell/CommandMenu.swift", "Sources/TransomMac/Shell/MenuCopy.swift", "Sources/TransomMac/Shell/StatusItemController.swift", "Sources/TransomMac/Shell/ZoomCopy.swift", "Sources/TransomMac/TransomMacApp.swift", "Sources/TransomMac/Zoom/AppColor.swift", "Sources/TransomMac/Zoom/CollapsedPanels.swift", "Sources/TransomMac/Zoom/ShortcutsWindowController.swift", "Sources/TransomMac/Zoom/SnapshotCapture.swift", "Sources/TransomMac/Zoom/StagePanel.swift", "Sources/TransomMac/Zoom/TileLayer.swift", "Sources/TransomMac/Zoom/ZoomController.swift", "Sources/TransomMac/Zoom/ZoomInput.swift", "Sources/transom-zoom-spike/main.swift", "Tests/TransomEngineTests/ArrangerCameraTests.swift", "Tests/TransomEngineTests/ArrangerCollapseTests.swift", "Tests/TransomEngineTests/NavigatorTests.swift", "Tests/TransomEngineTests/RecoveryTests.swift", "Tests/TransomEngineTests/SettleTrackerTests.swift", "Tests/TransomEngineTests/TransomURLTests.swift", "Tests/TransomEngineTests/ViewPlannerTests.swift", "Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift", "Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift", "Tests/TransomMacIntegrationTests/SnapshotCaptureIntegrationTests.swift", "Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift", "Tests/TransomMacTests/AppColorTests.swift", "Tests/TransomMacTests/CommandMenuTests.swift", "Tests/TransomMacTests/HotkeyTableTests.swift", "Tests/TransomMacTests/MenuCopyTests.swift", "Tests/TransomMacTests/NoScreenCaptureTests.swift", "Tests/TransomMacTests/PreviewStyleTests.swift", "Tests/TransomMacTests/ShortcutsModelTests.swift", "Tests/TransomMacTests/ZoomCopyTests.swift", "Tests/TransomMacTests/ZoomOffTests.swift", "Tests/TransomMacTests/ZoomTapRulesTests.swift", "scripts/vm-spike.sh"]
covered_digest: "v4:sha256:415c7f690113a059615e4df62a6e75700be3db85817dbf0972b9b2adbbfac7d1"
behavior_unverified: 7
overrides_applied: 0
behavior_unverified_items:
  - truth: "ZOOM-03: User can ⌘⇧-drag a rectangle to zoom to the windows it frames"
    test: "In the VM with zoom on, hold ⌘⇧ and drag a band across two tiles; release"
    expected: "Band (8% labelColor fill) and accent target preview draw after 4 pt; the drag reaches no app; the camera moves to the lowest common ancestor of the tiles whose centres are inside; a band over nothing does nothing and does not beep"
    why_human: "ZoomTapRules, Navigator.rectTarget and ZoomInput are unit-tested, but the real event tap, consumption of drags and the band drawing have only run headless"
  - truth: "ZOOM-06: Clicking a window in a zoomed view zooms in to it and focuses it"
    test: "Zoom Out to All Windows (⌃⌥⌘O) with 3+ windows; after the reveal, plain-click one window; also click a stage tile mid-move"
    expected: "The click is consumed, the camera zooms to that window's leaf and the window is focused after the settle; any other click passes and ends pick mode"
    why_human: "Pick mode lives in the shell (tap state, global monitor, Esc hotkey); only the pure rules are tested. Also check WR-02: no stray windowFocused right after the reveal ends pick mode at once"
  - truth: "ZOOM-08: Zoom hotkeys are rebindable"
    test: "Open Shortcuts…, rebind Zoom Out to All Windows, press the new chord; try a chord another Transom command uses; Restore Defaults"
    expected: "44 Recorder rows; the new chord works and shows in the menu; the duplicate is refused with the in-Transom message; Restore Defaults confirms and resets"
    why_human: "ShortcutsModel is tested (44 unique names, duplicate message) but the SwiftUI Recorder window has not run"
  - truth: "ZOOM-10 (pointer half): double-clicking a docked window's title bar frames it and toggles back"
    test: "Double-click a docked window's title bar twice; then turn the Shortcuts window's Mouse toggle off and double-click again"
    expected: "First double-click frames the window, second goes back; with the toggle off macOS's own double-click action runs (note IN-05: the toggle takes effect only after the next republish)"
    why_human: "Title-band rule is unit-tested; the tap path and the CG window-list read only ran headless"
  - truth: "ZOOM-11 (pointer half): double-clicking the Desktop frames it and toggles back"
    test: "Double-click bare wallpaper inside the Desktop tile, then double-click a desktop icon"
    expected: "Wallpaper double-click frames the Desktop (and toggles back); an icon double-click only opens the icon (RESEARCH A4 roles)"
    why_human: "Depends on Finder's AX hit-test roles, unverified on a real desktop"
  - truth: "ZOOM-12: Esc cancels a ⌘⇧-drag rectangle zoom in progress"
    test: "Start a ⌘⇧ band, press Esc (also with ⌘⇧ still held), release"
    expected: "Band fades in 80 ms, 'Zoom canceled' announced, no move, the release reaches no app, and the Esc hotkeys are gone afterwards (Esc works normally in apps); ⌥⌘Esc still opens Force Quit"
    why_human: "Temporary KeyboardShortcuts Esc streams are registered at runtime; registration and teardown have not run outside headless tests"
  - truth: "ZOOM-13 (shell half): collapsed blocks show at rest and double-click zooms in to them"
    test: "With zoom on, drop a window with a large minimum into a tile too small for it; hover and double-click the block; try VoiceOver press"
    expected: "Drop preview reads 'Collapsed until you zoom in'; an app-colour block with icon covers the tile; hover ring + pointing hand; double-click zooms to the leaf and focuses it; VoiceOver label '“App”, collapsed: title'"
    why_human: "Engine collapse is fully tested; CollapsedPanels (NSPanel pool, hover, double-click, accessibility) has only run headless"
human_verification:
  - test: "Run the 7 behavior_unverified items above in the Tart VM (Claude-driven, TRANSOM_STAGE_CAPTURABLE=1)"
    expected: "Each behaves as described in behavior_unverified_items"
    why_human: "Pointer, event-tap and UI behaviour tested only headless (04-08 UAT list)"
  - test: "Zoom in, kill -9 Transom Debug, relaunch"
    expected: "No window parked; N2 shows"
    why_human: "UI-SPEC backstop; only the engine paths and a scripted crash relaunch were automated"
  - test: "⌘⇧-click a Safari link"
    expected: "Opens in a new tab (the re-posted press reaches Safari)"
    why_human: "Synthesised event re-post can only be judged against a real app"
  - test: "fn⌃⌥⌘← / → / ↑ / ↓ while zoomed into a node"
    expected: "View pans; macOS window tiling does not also act"
    why_human: "System shortcut interplay"
  - test: "Turn on Reduce Motion, zoom in and out"
    expected: "Crossfade; no tile moves or scales"
    why_human: "Visual"
  - test: "Deny Screen Recording; zoom with Notes, Terminal and a saturated-icon app in light and dark mode"
    expected: "Fallback tiles legible (icon + title capsule); explainer shows once after the first reveal, never again"
    why_human: "Visual legibility; one-time alert flow"
  - test: "Open a status-item menu during a camera move"
    expected: "Menu stays above the stage"
    why_human: "Window-level interplay (spike G5 used a harness, not the product)"
  - test: "Shell-only review fixes: WR-02 (pick mode ends on focus change), WR-03 (first move after launch gets snapshots on the second move at latest), WR-04 (Turn Off Zoom during a post-reveal refresh makes no more ScreenCaptureKit calls), WR-06 (Turn Off Zoom waits for the home move's own reveal)"
    expected: "Each behaves as 04-REVIEW-FIX.md describes"
    why_human: "No headless test reaches these shell paths"
  - test: "Review the 6 flagged prohibitions (see report: Prohibitions)"
    expected: "Human confirms each MUST NOT holds; the verifier's verdicts are non-authoritative"
    why_human: "Judgment-tier prohibitions, status unresolved/flagged in the plans; unverified-prohibition, human review recommended"
---

# Phase 4: Zoom Camera Verification Report

**Phase Goal:** As a Mac user, I want to zoom out to see every window and zoom back in to any of them, so that I can find and focus any window fast.
**Verified:** 2026-10-28T18:20:00Z
**Status:** human_needed
**Re-verification:** No (initial verification)

## User Flow Coverage (MVP mode)

| Step | Expected | Evidence in codebase | Status |
|---|---|---|---|
| Zoom out to see every window | ⌃⌥⌘O / menu / `transom://zoom-out` moves the camera home; stage animates, windows settle once | `Navigator.cameraStep(.zoomOutAll)` → `Arranger.zoomTo` → `.cameraMove` → `ZoomController.run` → `.cameraSettle` → `planShown`; NavigatorTests, ArrangerCameraTests; live ZoomSettleIntegrationTests (VM, 04-08) | ✓ |
| Zoom back in to any window | Step in, frame window, rect zoom, pick click, collapsed-block double-click | Engine paths all tested; pointer paths (rect, pick, double-clicks) wired but headless-only | ⚠️ partial: keyboard/URL verified, pointer needs VM UAT |
| Find and focus fast (outcome) | Window is focused after the move, settle ≤ 500 ms write path | `PendingMove.focus` → `.perform([.focus])` after settle writes (`zoomToWithFocusFocusesAfterTheWrites`); spike G1 p95 205.1 / 93.1 ms recomputed from raw data | ✓ engine / ⚠️ click-to-focus in UAT |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | SC1 / ZOOM-01: zoom out to see every window on the display | ✓ VERIFIED | `ViewPlanner.plan(.home)` = `Planner.plan` (`homeViewEqualsThePhase3Plan`); `zoomOutAllFromANodeTargetsHome`, `zoomOutAllAtHomeIsRefused`; stage shell `ZoomController` (capture → show → animate → settle → `SettleTracker` → reveal) wired from `ArrangeController.run(.cameraMove)` |
| 2 | SC1 / ZOOM-02: step in or out one level | ✓ VERIFIED | `Navigator.stepOut/stepIn` (focus → pointer → largest child); 5 NavigatorTests incl. refusal on a single leaf |
| 3 | SC1 / ZOOM-03: ⌘⇧-drag a rectangle to zoom to the windows it frames | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `ZoomTapRules.decide` (band consume), `InputTap` mask includes `leftMouseDragged`, `ZoomInput.bandEvent` → `Navigator.rectTarget` → `controller.zoom(to:)`; rules and rectTarget unit-tested; real tap path headless only |
| 4 | SC2 / ZOOM-04: back and forward through previous views | ✓ VERIFIED | `CameraHistory` (50 entries, per display, pushed only at settle in `recordHistory`); 9 CameraHistoryTests + retarget-pushes-once |
| 5 | SC2 / ZOOM-06: clicking a window in a zoomed view zooms in and focuses it | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Pick mode in `ZoomInput.revealed/pickClick`, stage tile click → `stageClick`; `zoom(to:focus:)` focus after settle is tested; pointer path headless only |
| 6 | SC3 / ZOOM-05: live snapshots when granted, app colour + icon when not; denial never breaks zoom | ✓ VERIFIED | `ZoomController.run`: `granted ? captureStart : [:]`; each tile picks capture → cache → `fallback` (AppColor + icon + title); 128 MB `SnapshotCache` (spike condition 2 applied); explainer once (`explainerShownKey` saved at show); `SnapshotCaptureIntegrationTests` live in VM per 04-08; ScreenCaptureKit only in `SnapshotCapture.swift` (`NoScreenCaptureTests` pass) |
| 7 | SC4 / ZOOM-07: 15 real windows at new sizes within 500 ms (write path), no stale-layout flash | ✓ VERIFIED | Raw `.build/spike/settle-20261028-000855/out.jsonl` re-parsed: 15 windows, 20 runs each way, in p50/p95/max 64.8/205.1/280.3 ms, out 58.0/93.1/110.3 ms, 0 missing read-backs; G2 0 mismatches / 0 unstranded in 40 moves. Product: `SettleTracker` holds the stage until every write + 50 ms (cap 1500); 04-08 reveal-timer bug fixed (stored timer, `ZoomController.armReveal`); `fifteenWindowsSettleWithinBudget` asserts p95 in VM |
| 8 | SC4: parked windows come back on quit, after a crash and via Restore All Windows | ✓ VERIFIED | `Recovery.terminationPlan(homeTiles:)` + `ArrangeController.restoreForTermination`; `restoreAll` → `goHome()` + clears collapsible (CR-01); `setZoomEnabled(false)` rescues while paused (CR-02); tests `aParkedDockedWindowGoesBackToItsHomeTile`, `restoreAllReturnsEveryCameraHome`, `restoreAllBringsACollapsedWindowBackOnScreen`, `turningZoomOffWhilePausedLeavesNoWindowParked`, `aRecoveryLaunch…`, `aCrashLoopLaunch…`; live Quit/Recovery integration in VM per 04-08. kill -9 stays a UAT backstop |
| 9 | SC5 / ZOOM-08: user can rebind every zoom hotkey | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 11 names in `Hotkeys.entries`; `ShortcutsWindowController` with 44 `KeyboardShortcuts.Recorder` rows, duplicate validation, Restore Defaults; opened from the status menu; model tests pass; UI not run |
| 10 | SC5: turning zoom off leaves Phase 3 tiling fully working | ✓ VERIFIED | Engine default `camera.enabled = false`; full suite 1165/1165 passes; only phase-4 test-expectation change is the intended 33→44 hotkey table; with zoom off: no `ZoomController` (`zoom()` reached only when `zoomEnabled`), status menu calls `isGranted()` only `if on`, hotkeys disabled at launch (`TransomMacApp` line 94); `ZoomOffTests` (weak, see IN-09) |
| 11 | SC6 / ZOOM-09: move the view to a neighbouring area by hotkey and URL | ✓ VERIFIED | `Navigator.pan` (same depth, longest shared edge, recency, NodeID); 4 pan tests; hotkeys Home/End/PgUp/PgDn; URLs `pan-left/right/up/down` in `TransomURL` (TransomURLTests) |
| 12 | SC6 / ZOOM-10 (hotkey, URL): frame the focused window and toggle back | ✓ VERIFIED | `cameraStep(.frameWindow)` → `toggle(.node(leaf))`; `frameWindowFramesTheFocusedLeafAndTogglesBack`, pending-target and refusal tests; ⌃⌥⌘M and `transom://frame-window` |
| 13 | SC6 / ZOOM-10 (title-bar double-click) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `ZoomTapRules` title-band rule tested; `ZoomInput.titleBarDoubleClick` → `controller.camera(.frameWindow)`; headless only |
| 14 | SC6 / ZOOM-11 (hotkey, URL): frame the Desktop and toggle back | ✓ VERIFIED | `cameraStep(.frameDesktop)`, `frameDesktopTogglesAndIsRefusedWhileHidden`; ⌃⌥⌘G and `transom://frame-desktop` |
| 15 | SC6 / ZOOM-11 (Desktop double-click) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `ZoomInput.desktopDoubleClick` (wallpaper check + Finder AX hit test off the tap); RESEARCH A4 unverified |
| 16 | SC6 / ZOOM-12: Esc cancels a ⌘⇧-drag rectangle zoom | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `cancelBand`, Esc streams for [], ⇧, ⌘, ⌘⇧ only (no ⌥, so never ⌥⌘Esc), torn down in `endBand`; `anEscCanceledBandStillTakesTheRestOfItsPressThenLetsGo`; runtime registration not exercised |
| 17 | SC6 / ZOOM-13 (engine): tiles too small for their window collapse instead of being refused (zoom on) | ✓ VERIFIED | `ViewPlanner.collapsing` two-pass, `Arranger.collapse/accept`, `TileMove.Kind.collapsed`, `.collapsedBlocks` effect; boundary/precision probes; CONTEXT E refusals kept (`growShrinkRotateFlipBalanceStillRefuseWithZoomOn`, `anOSCausedLossOfRoomStillFloats`); WR-01 pruning tested |
| 18 | SC6 / ZOOM-13 (shell): collapsed app-colour blocks zoom in on double-click | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `CollapsedPanels` (pool, `.floating`, `clickCount == 2`, `accessibilityPerformPress`) → `ArrangeController.openBlock` → `ZoomInput.zoom(toLeafOf:)`; headless only |

**Score:** 11/18 truths verified (7 present, behavior-unverified)

The 04-01..04-08 plan truths are covered by the rows above. Plan backstops (`verification: backstop`): settle/no-flash (G1/G2) is backed by directly observed raw data; G3 soak PASS; G4 strict-FAIL on 2/82 crossfade runs was accepted by the user as VM noise (04-SPIKE verdict condition 1, 2026-10-28); G5/G6 reported; the remaining backstops (kill -9, fallback legibility, Reduce Motion, ⌘⇧-click re-post, fn-arrows, desktop icon, menu above stage) are in Human Verification.

### Required Artifacts

`gsd-tools verify.artifacts`: 30/30 across 8 plans, no stub or missing pattern.

| Artifact | Status | Details |
|---|---|---|
| `Sources/TransomEngine/ViewPlanner.swift` | ✓ VERIFIED | ViewTarget, subtree, collapse pass; used by planShown, zoomTo, homeTiles |
| `Sources/TransomEngine/Arranger+Camera.swift` | ✓ VERIFIED | CameraState/Move, zoomTo, cameraSettle, homeTiles, goHome, forgetMoves |
| `Sources/TransomEngine/Navigator.swift` | ✓ VERIFIED | all 11 commands, refusals, history, rectTarget, widen |
| `Sources/TransomEngine/SettleTracker.swift` | ✓ VERIFIED | used by ZoomController |
| `Sources/TransomEngine/Recovery.swift` | ✓ VERIFIED | homeTiles parameter, called from restoreForTermination |
| `Sources/TransomMac/Zoom/ZoomController.swift` | ✓ VERIFIED | created lazily only on a zoom-on camera move |
| `Sources/TransomMac/Zoom/SnapshotCapture.swift` | ✓ VERIFIED | sole ScreenCaptureKit file; close() flag (WR-04); re-read on unknown window (WR-03) |
| `Sources/TransomMac/Zoom/StagePanel.swift`, `TileLayer.swift`, `AppColor.swift` | ✓ VERIFIED | used by ZoomController |
| `Sources/TransomMac/Zoom/ZoomInput.swift`, `Input/ZoomTapRules.swift` | ✓ VERIFIED (wired) | behaviour UAT pending |
| `Sources/TransomMac/Zoom/CollapsedPanels.swift` | ✓ VERIFIED (wired) | behaviour UAT pending |
| `Sources/TransomMac/Zoom/ShortcutsWindowController.swift` | ✓ VERIFIED (wired) | behaviour UAT pending |
| `Sources/transom-zoom-spike/main.swift`, `scripts/vm-spike.sh`, `04-SPIKE.md` | ✓ VERIFIED | raw output present under `.build/spike/` |

### Key Link Verification

`verify.key-links` could not parse 23 of 25 `from:` fields (they carry a symbol after the path, a plan-format issue). Each was checked by hand:

| From | To | Status |
|---|---|---|
| `Arranger.process(.camera)` (Arranger.swift:356) | `Arranger.camera(_:displayUUID:focused:pointer:)` | ✓ WIRED |
| `cameraSettle` | `planShown()`; `recordHistory` → `camera.histories` | ✓ WIRED |
| `planShown` | `ViewPlanner.plan` (zoom on), `.save(.now)` before `.perform`, parks first | ✓ WIRED |
| `windowFocused` / `windowCreated` (Arranger.swift:634/638) | `widen(toShow:)` | ✓ WIRED |
| `ArrangeController.run(.cameraMove)` | `zoom().run` → `settle` → `.cameraSettle` → `beginSettle` | ✓ WIRED |
| event loop `frameApplied` | `ZoomController.frameApplied` → `SettleTracker.applied` | ✓ WIRED |
| `TransomMacApp` | `ArrangeController(zoomEnabled:)` from preference (default true) | ✓ WIRED |
| `Hotkeys.entries` (`onKeyDown`) | `dispatch(.camera)` → `dispatchCamera` (pointer display) | ✓ WIRED |
| Status menu Turn Off Zoom | `setZoomEnabled(false)` → home moves → `finishZoomOff` (move-ID matched, WR-06) | ✓ WIRED |
| Shortcuts rows | `Hotkeys.entries` names | ✓ WIRED |
| `InputTap` callback | `ZoomTapRules.decide` on lock-copied state | ✓ WIRED |
| band release | `Navigator.rectTarget` → `controller.zoom(to:)` | ✓ WIRED |
| `ZoomController.onRevealed` | `ZoomInput.revealed` (pick mode), `revealed` (zoom off) | ✓ WIRED |
| drop / Dock / Move | `collapse` → `camera.collapsible` → `ViewPlanner.plan(collapsible:)` | ✓ WIRED |
| `planShown` | `.collapsedBlocks` → `CollapsedPanels.show` | ✓ WIRED |
| `CollapsedPanels` double-click | `openBlock` → `zoom(toLeafOf:)` → `zoom(to:focus:)` | ✓ WIRED |
| `restoreForTermination` | `terminationPlan(homeTiles: arranger.homeTiles())` | ✓ WIRED |
| `restoreAll` | `goHome()` | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| Stage tiles | start/end rects | `CameraMove.tiles` from two `ViewPlanner` plans of the live desk | yes | ✓ FLOWING |
| Tile content | CGImage | `SnapshotCapture.captureAll` / cache, else AppColor of the running app's icon | yes | ✓ FLOWING |
| Reveal timing | pending writes | settle's `.perform` commands → `frameApplied` read-backs | yes | ✓ FLOWING |
| Debug lines | lastSettle, cacheStats | ZoomController state | yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full headless suite (run once) | `swift test` (TRANSOM_LIVE unset) | 193 + 261 + 49 + 662 = 1165 passed, exit 0; FreezeTest flake did not fire | ✓ PASS |
| All 18 phase-4 suites ran | grep of the saved log | ViewPlanner, ArrangerCamera, Navigator, CameraHistory, SettleTracker, ArrangerCollapse, Recovery, TransomURL, ZoomTapRules, ShortcutsModel, HotkeyTable, CommandMenu, ZoomOff, AppColor, ZoomCopy, PreviewStyle, NoScreenCapture, SnapshotCache all passed | ✓ PASS |
| ZOOM-07 numbers | re-parse raw `out.jsonl` | p95 205.1 / 93.1 ms, 15 windows, 0 missing, 0 G2 mismatches | ✓ PASS |
| No expectation weakened | `git diff 6c6e542..HEAD -- Tests/ \| grep '^-.*#expect'` | 2 lines, both the intended 33 → 44 hotkey-table change | ✓ PASS |
| Live VM suites | not run (host rule) | evidence only in 04-04/04-08 SUMMARYs | ? SKIP |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist and no plan declares a probe. Step 7c: not applicable.

### Requirements Coverage

| Req | Source plans | Status | Evidence |
|---|---|---|---|
| ZOOM-01 | 02, 03, 04, 05, 08 | ✓ SATISFIED | truth 1 |
| ZOOM-02 | 02, 03, 04, 05 | ✓ SATISFIED | truth 2 |
| ZOOM-03 | 03, 06 | ? NEEDS HUMAN | truth 3 |
| ZOOM-04 | 03, 05 | ✓ SATISFIED | truth 4 |
| ZOOM-05 | 01, 04, 08 | ✓ SATISFIED (visual backstop in UAT) | truth 6 |
| ZOOM-06 | 03, 06 | ? NEEDS HUMAN | truth 5 |
| ZOOM-07 | 01, 02, 04, 08 | ✓ SATISFIED (write-path definition, user decision) | truth 7 |
| ZOOM-08 | 05 | ? NEEDS HUMAN | truth 9 |
| ZOOM-09 | 03, 05 | ✓ SATISFIED | truth 11 |
| ZOOM-10 | 03, 05, 06 | partial: hotkey/URL ✓, double-click ? | truths 12, 13 |
| ZOOM-11 | 03, 05, 06 | partial: hotkey/URL ✓, double-click ? | truths 14, 15 |
| ZOOM-12 | 06 | ? NEEDS HUMAN | truth 16 |
| ZOOM-13 | 02, 07 | partial: engine ✓, panels ? | truths 17, 18 |

All 13 IDs appear in at least one plan's `requirements:`; no orphaned IDs. REQUIREMENTS.md already marks ZOOM-03, 06, 08, 10, 11, 12, 13 as Pending, which matches this report; tick them after VM UAT.

### CONTEXT decisions honoured

- D-A: camera targets are NodeIDs, parks at own size via `parkedFrame`, home = Phase 3 plan, 250 ms overlay only, one write per changed window at settle. Yes.
- D-B: one-shot `SCScreenshotManager`, no SCStream, single file, permission asked after the first reveal and never at onboarding. Yes.
- D-C: ⌃⌥⌘ O , . [ ] M G plus Home/End/PgUp/PgDn; Shortcuts window; band via InputTap; URLs for every action. Yes.
- D-D: spike first, save before park, zoom off creates no overlay and touches no ScreenCaptureKit, 50-entry history per display, pointer display. Yes.
- E: widen-on-focus and new window; only drops and keyboard Dock/Move collapse. Yes (tested).
- Spike conditions: (2) cache mandatory, done; (3) UI-SPEC wording updated (line 150, 232); (4) ZOOM-07 write-path wording in REQUIREMENTS.md and the live test. Yes.

### Prohibitions (judgment tier, flagged; non-authoritative verifier verdicts)

| Plan | MUST NOT | Verifier verdict (non-authoritative) |
|---|---|---|
| 04-01 ZOOM-05 | write snapshots to disk / log image data | Holds in product code. The spike's only PNG writer (`writePNG`) writes frames decoded from the guest screen recording, which the statement allows |
| 04-04 ZOOM-05 | ask for Screen Recording more than once on its own | Holds: explainer flag saved before the alert shows; preflight only at move start; later requests only from the menu (IN-06: the first menu use may show the prompt and the Settings pane together) |
| 04-04 ZOOM-05 | persist, log or share snapshots; purge on zoom off / close | Holds: memory LRU, `close()` purges. IN-04: a closed native-tab window's entry is pruned at the next refresh, not at close |
| 04-06 ZOOM-12 | consume beyond one press-release, leave Esc registered, register ⌥⌘Esc | Holds in code: every mouse-down resets `swallow`; band Esc tasks cancelled in `endBand`; pick Esc ends with pick mode (and on focus change, WR-02); no ⌥ modifier anywhere |
| 04-06 ZOOM-03 | synthesise input other than the exact re-post | Holds: `ZoomInput.repost` is the only `CGEvent.post` in Sources outside the spike |
| 04-08 ZOOM-07 | leave any window parked/off screen after quit, crash, crash loop, Restore All, Turn Off Zoom | Holds for shown desks after CR-01/CR-02. Residual: a zoomed desk on a non-shown Space is restored at quit only if AX reaches it; crash-loop centres parked windows until Resume (on screen) |

### Anti-Patterns Found

No TBD / FIXME / XXX / TODO / HACK / placeholder markers in the 55 changed files.

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `Sources/TransomEngine/Navigator.swift` | 291, 294 | IN-01 (open): `toggle(.node(leaf))` / `.node(.desktop)` skip `Navigator.target`, so a root leaf commits `.node(root)` | ⚠️ Warning | Looks like home but the status reads "zoomed in" and quit plans that desk; one-line fix |
| `Tests/TransomMacTests/ZoomOffTests.swift` | 12-25 | IN-09 (open): controller never started, status menu not built, absolute `touches == 0` | ⚠️ Warning | Guard is weaker than claimed; code inspection covers the gap for now |
| `Sources/TransomMac/Zoom/ZoomInput.swift` | 69 | IN-05: double-click preference read only in `publish()` | ℹ️ Info | Toggle lags until the next republish |
| `Sources/TransomMac/Shell/StatusItemController.swift` | 160-166 | IN-06 | ℹ️ Info | First use may show prompt and Settings together |
| `Sources/TransomMac/Zoom/StagePanel.swift` | 78-94 | IN-07: observer leak, synchronous wallpaper decode | ℹ️ Info | Cost on the first move / after display changes |
| `Sources/TransomMac/Zoom/CollapsedPanels.swift` | 196 | IN-08: `.floating` above excluded windows | ℹ️ Info | Block can take clicks from an excluded window over its tile |
| `Sources/TransomMac/Zoom/SnapshotCapture.swift` | 64-74, 125-128 | IN-02: timeout tasks never cancelled | ℹ️ Info | Harmless noise |
| `Sources/TransomMac/Zoom/AppColor.swift` | 35-40 | IN-03: grey cached forever on a nil icon | ℹ️ Info | Cosmetic |
| `.planning/phases/04-zoom-camera/04-SPIKE.md` | G2 visual | The recorded 'in' reveals (`g2-1`, `g2-3` after24) show a TextEdit `note.txt` window over the Terminal tile. It appears to be an unmanaged window left over from an earlier run (the managed one is `note-15934.txt`) | ℹ️ Info | The claim that no frame shows a window at its old rect is literally inaccurate; this is a harness environment artefact, not a product defect |

### Human Verification Required

Run in the Tart VM only (Claude-driven, `TRANSOM_STAGE_CAPTURABLE=1`), never on the host:

1. **Rectangle zoom (ZOOM-03) and Esc cancel (ZOOM-12):** see behavior_unverified_items.
2. **Pick-mode click and stage-tile click (ZOOM-06):** includes the WR-02 check.
3. **Shortcuts window (ZOOM-08):** rebind, duplicate refusal, Restore Defaults.
4. **Title-bar double-click (ZOOM-10) and Desktop double-click vs icon (ZOOM-11).**
5. **Collapsed blocks (ZOOM-13):** drop preview, block, hover, double-click, VoiceOver.
6. **kill -9 while zoomed:** no window parked, N2 shows.
7. **⌘⇧-click re-post in Safari; fn-arrow pans; Reduce Motion crossfade; fallback legibility light/dark with Screen Recording denied; menu above the stage.**
8. **Shell-only review fixes WR-02, WR-03, WR-04, WR-06.**
9. **Review the six flagged prohibitions above** (04-01: 1, 04-04: 2, 04-06: 2, 04-08: 1).

### Gaps Summary

There are no blocking gaps. The engine and the keyboard, URL and menu paths that deliver the goal are present, wired and tested: zoom out, step, history, pan, frame toggles, collapse, the settle protocol and parking safety. The ZOOM-07 budget was confirmed by re-parsing the spike's raw data rather than trusting the SUMMARY. Both code-review blockers (CR-01, CR-02) are fixed, each with a regression test. What remains is the pointer, event-tap and UI behaviour that has only run headless (ZOOM-03, 06, 08, the double-click halves of 10 and 11, 12, and the panel half of 13), plus the UI-SPEC visual backstops. That work needs VM UAT before the phase can be called passed. IN-01 is a small open defect worth fixing before ship.

---

_Verified: 2026-10-28T18:20:00Z_
_Verifier: Claude (gsd-verifier)_
