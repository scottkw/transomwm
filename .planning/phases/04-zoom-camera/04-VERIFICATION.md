---
phase: 04-zoom-camera
verified: 2026-10-28T21:40:00Z
status: passed
score: 18/18 must-haves verified
covered_files: [".planning/phases/04-zoom-camera/04-01-PLAN.md", ".planning/phases/04-zoom-camera/04-01-SUMMARY.md", ".planning/phases/04-zoom-camera/04-02-PLAN.md", ".planning/phases/04-zoom-camera/04-02-SUMMARY.md", ".planning/phases/04-zoom-camera/04-03-PLAN.md", ".planning/phases/04-zoom-camera/04-03-SUMMARY.md", ".planning/phases/04-zoom-camera/04-04-PLAN.md", ".planning/phases/04-zoom-camera/04-04-SUMMARY.md", ".planning/phases/04-zoom-camera/04-05-PLAN.md", ".planning/phases/04-zoom-camera/04-05-SUMMARY.md", ".planning/phases/04-zoom-camera/04-06-PLAN.md", ".planning/phases/04-zoom-camera/04-06-SUMMARY.md", ".planning/phases/04-zoom-camera/04-07-PLAN.md", ".planning/phases/04-zoom-camera/04-07-SUMMARY.md", ".planning/phases/04-zoom-camera/04-08-PLAN.md", ".planning/phases/04-zoom-camera/04-08-SUMMARY.md", "Package.swift", "Sources/TransomEngine/Arranger+Camera.swift", "Sources/TransomEngine/Arranger+Commands.swift", "Sources/TransomEngine/Arranger.swift", "Sources/TransomEngine/Command.swift", "Sources/TransomEngine/DragSession.swift", "Sources/TransomEngine/Navigator.swift", "Sources/TransomEngine/Recovery.swift", "Sources/TransomEngine/SettleTracker.swift", "Sources/TransomEngine/TransomURL.swift", "Sources/TransomEngine/ViewPlanner.swift", "Sources/TransomMac/ArrangeController.swift", "Sources/TransomMac/Displays.swift", "Sources/TransomMac/Input/Hotkeys.swift", "Sources/TransomMac/Input/InputTap.swift", "Sources/TransomMac/Input/ZoomTapRules.swift", "Sources/TransomMac/Overlay/PreviewPanel.swift", "Sources/TransomMac/Overlay/PreviewStyle.swift", "Sources/TransomMac/Overlay/Toast.swift", "Sources/TransomMac/Shell/CommandMenu.swift", "Sources/TransomMac/Shell/MenuCopy.swift", "Sources/TransomMac/Shell/StatusItemController.swift", "Sources/TransomMac/Shell/ZoomCopy.swift", "Sources/TransomMac/TransomMacApp.swift", "Sources/TransomMac/Zoom/AppColor.swift", "Sources/TransomMac/Zoom/CollapsedPanels.swift", "Sources/TransomMac/Zoom/ShortcutsWindowController.swift", "Sources/TransomMac/Zoom/SnapshotCapture.swift", "Sources/TransomMac/Zoom/StagePanel.swift", "Sources/TransomMac/Zoom/TileLayer.swift", "Sources/TransomMac/Zoom/ZoomController.swift", "Sources/TransomMac/Zoom/ZoomInput.swift", "Sources/transom-zoom-spike/main.swift", "Tests/TransomEngineTests/ArrangerCameraTests.swift", "Tests/TransomEngineTests/ArrangerCollapseTests.swift", "Tests/TransomEngineTests/NavigatorTests.swift", "Tests/TransomEngineTests/RecoveryTests.swift", "Tests/TransomEngineTests/SettleTrackerTests.swift", "Tests/TransomEngineTests/TransomURLTests.swift", "Tests/TransomEngineTests/ViewPlannerTests.swift", "Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift", "Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift", "Tests/TransomMacIntegrationTests/SnapshotCaptureIntegrationTests.swift", "Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift", "Tests/TransomMacTests/AppColorTests.swift", "Tests/TransomMacTests/CommandMenuTests.swift", "Tests/TransomMacTests/HotkeyTableTests.swift", "Tests/TransomMacTests/MenuCopyTests.swift", "Tests/TransomMacTests/NoScreenCaptureTests.swift", "Tests/TransomMacTests/PreviewStyleTests.swift", "Tests/TransomMacTests/ShortcutsModelTests.swift", "Tests/TransomMacTests/TileLayerTests.swift", "Tests/TransomMacTests/ZoomCopyTests.swift", "Tests/TransomMacTests/ZoomOffTests.swift", "Tests/TransomMacTests/ZoomTapRulesTests.swift", "scripts/vm-spike.sh"]
covered_digest: "v4:sha256:4ea5297af557febf20f83c983d337fec0cc0eb65425ed86eba0e19dfa7ae231a"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 11/18
  gaps_closed:
    - "ZOOM-03: ⌘⇧-drag rectangle zoom (UAT 1, 13-band.png)"
    - "ZOOM-06: click a window in a zoomed view to zoom in and focus it (UAT 2, 10-hover.png)"
    - "ZOOM-08: zoom hotkeys are rebindable (UAT 3, 19/21/22-*.png)"
    - "ZOOM-10 pointer half: title-bar double-click frames and toggles back (UAT 4, 24-titlebar-frame.png)"
    - "ZOOM-11 pointer half: Desktop double-click frames and toggles back; an icon double-click only opens the icon (UAT 4, 25/26-*.png)"
    - "ZOOM-12: Esc cancels a rectangle zoom and leaves no Esc hotkey behind (UAT 1, 15-esc.png, 16-forcequit.png)"
    - "ZOOM-13 shell half: collapsed blocks show at rest and zoom in on double-click (UAT 5, 32/33/34-*.png)"
    - "IN-01: frame toggles of the root node commit .home (9ccd9d6, NavigatorTests.frameDesktopOnAnEmptyDeskStaysHome)"
    - "G-04-10: fallback tile titles legible in dark mode (2f0823c, TileLayerTests.aDarkTitleStaysLightTextWhenDrawnLater, UAT 10, 45-dark-fixed-crop.png)"
    - "G-04-12: pick mode ends when another app activates (fab166d, UAT 12 re-test, 62-after-cmdtab.png)"
  gaps_remaining: []
  regressions: []
---

# Phase 4: Zoom Camera Verification Report

**Phase Goal:** As a Mac user, I want to zoom out to see every window and zoom back in to any of them, so that I can find and focus any window fast.
**Verified:** 2026-10-28T21:40:00Z
**Status:** passed
**Re-verification:** Yes. This follows the VM UAT (04-UAT.md, complete, 16/16) and the fix commits 9ccd9d6 (IN-01), 2f0823c (G-04-10, dark-mode tile title) and fab166d (G-04-12), plus UAT commits ee2181b and 0bbfea6.

## What changed since the previous report

| Commit | Change | Checked how | Verdict |
|---|---|---|---|
| 9ccd9d6 | `cameraStep(.frameWindow/.frameDesktop)` now calls `toggle(Navigator.target(id, in: desk.tree))`, so framing the root node gives `.home` (Navigator.swift:291, 294) | Diff read. `Navigator.target` maps `id == tree.root` to `.home` (Navigator.swift:40). New test `frameDesktopOnAnEmptyDeskStaysHome` removes all windows so the Desktop is the root, then checks every move targets `.home` and the view stays `.home`. It passed in the full run. Without the fix the target would be `.node(.desktop)` and the test would fail | ✓ correct, tested |
| 2f0823c | `TileLayer.text` resolves `labelColor` to a CGColor when the image is made, not when CA draws it lazily | Diff read. The new `TileLayerTests.aDarkTitleStaysLightTextWhenDrawnLater` makes the image under `.darkAqua` and draws it under `.aqua`, then checks the brightest pixel is above 0.8. With the old lazy resolve, the colour would be black under `.aqua`, so the test would fail. It passed in the full run. VM: 45-dark-fixed-crop.png (inspected) shows white "TransomFixtureApp" on the dark capsule | ✓ correct, tested |
| fab166d | The `didActivateApplicationNotification` observer (installed once in `startWatchdog`, which `startTap` calls) now calls `zoomInput.endPick(reason: "app activated")` for any app other than Transom itself | Diff read. `endPick` returns early when `pick == nil` (ZoomInput.swift:205), so firing on unrelated activations is harmless. The own-pid guard keeps the status menu from ending pick mode. No headless test reaches this shell path. VM UAT 12 re-test on fab166d: `pick mode on` 21:04:39.249, then ⌘-Tab gives `pick mode off: app activated` 21:04:41.998, and Esc then closed Spotlight. Pick mode lasting 2.7 s before the ⌘-Tab also shows the new exit does not fire right after the reveal | ✓ correct, VM-verified |
| ee2181b, 0bbfea6 | 04-UAT.md only | Read in full; screenshots spot-checked (see below) | evidence |

## User Flow Coverage (MVP mode)

The user-story guard passes: "As a Mac user, I want to …, so that I can find and focus any window fast."

| Step | Expected | Evidence | Status |
|---|---|---|---|
| Zoom out to see every window | ⌃⌥⌘O / menu / `transom://zoom-out` moves the camera home; the stage animates and windows settle once | Engine tests (NavigatorTests, ArrangerCameraTests); VM UAT 2 (`pick mode on` after a Zoom Out reveal), UAT 13 (snapshots on every tile from the second move on), live ZoomSettleIntegrationTests (04-08) | ✓ |
| Zoom back in to any window | Step in, frame window, rectangle zoom, pick click, collapsed-block double-click | Keyboard and URL paths tested headless; pointer paths observed in the VM (UAT 1, 2, 4, 5) | ✓ |
| Find and focus fast (outcome) | The chosen window is framed and focused after the move; write path ≤ 500 ms for 15 windows | `zoomToWithFocusFocusesAfterTheWrites`; UAT 2 `pick → window 5500` → `home → node(n11)`, `frontmost index=0`; UAT 5 `frontmost index=3`; spike G1 p95 205.1 / 93.1 ms (re-parsed from raw data in the previous report) | ✓ |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | SC1 / ZOOM-01: zoom out to see every window on the display | ✓ VERIFIED | Unchanged from the previous report (ViewPlanner home = Phase 3 plan; `zoomOutAll*` tests); regression: suites pass |
| 2 | SC1 / ZOOM-02: step in or out one level | ✓ VERIFIED | Unchanged; NavigatorTests pass |
| 3 | SC1 / ZOOM-03: ⌘⇧-drag a rectangle to zoom to the windows it frames | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 1: log `rect zoom → n12` then `home → node(n12)`; 13-band.png (inspected) shows the band over TextEdit and Fixture 0 with the target preview over the bottom row; a band that misses every tile centre logged `rect zoom: no target` and made no move |
| 4 | SC2 / ZOOM-04: back and forward through previous views | ✓ VERIFIED | Unchanged; CameraHistoryTests pass |
| 5 | SC2 / ZOOM-06: clicking a window in a zoomed view zooms in and focuses it | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 2: `pick mode on` → `pick mode off: picked` → `pick → window 5500` → `home → node(n11)`, Fixture 0 framed at 8,33 1008x673, `frontmost index=0`; hover ring in 10-hover.png; mid-move tile click `retarget node(n14) → node(n13) during moving`, Fixture 1 focused. WR-02/G-04-12: UAT 12 re-test on fab166d |
| 6 | SC3 / ZOOM-05: snapshots when granted, app colour + icon when not; denial never breaks zoom | ✓ VERIFIED | Previously verified; now also observed both ways. Denied: UAT 10 fallback tiles legible in light (42-motion-mid.png) and dark after 2f0823c (45-dark-fixed-crop.png, inspected); the explainer showed once in 40 min across relaunches and a crash. Granted: UAT 13 `3 tiles, 3 snapshots, 0 fallback`; 61-rm-second-a.png (inspected) shows real "Alpha one" content in the stage |
| 7 | SC4 / ZOOM-07: 15 windows at new sizes within 500 ms (write path), no stale-layout flash | ✓ VERIFIED | Unchanged (raw spike data re-parsed in the previous report; product SettleTracker) |
| 8 | SC4: parked windows come back on quit, after a crash and via Restore All Windows | ✓ VERIFIED | Previously verified by tests. Now also observed in the VM: UAT 6 kill -9 while zoomed with 3 windows parked, relaunch gave `crashRecovered(unplaced: 0)` and every window on screen (35-after-crash.png, inspected: N2 toast shows); UAT 16 quit `quit restore: 6 of 6 windows`, Restore All `restored(count: 3)` |
| 9 | SC5 / ZOOM-08: user can rebind every zoom hotkey | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 3: Zoom Out rebound to ⌃⌥⌘9 (defaults `carbonKeyCode 25`), ⌃⌥⌘O went dead and ⌃⌥⌘9 zoomed; duplicate ⌃⌥⌘Z refused with "This shortcut is already used by “Undo Layout Change” in Transom." (21-duplicate.png, inspected; the 11 Zoom rows are visible); Restore Defaults confirmed and reset to keyCode 31. The 44-row count comes from ShortcutsModelTests, not AX |
| 10 | SC5: turning zoom off leaves Phase 3 tiling fully working | ✓ VERIFIED | Full suite passes (below); UAT 15 Turn Off Zoom left every window at its home tile; UAT 14 zero ScreenCaptureKit lines after zoom off. IN-09 (weak ZoomOffTests) remains an info-level test-quality note |
| 11 | SC6 / ZOOM-09: move the view to a neighbouring area by hotkey and URL | ✓ VERIFIED | Unchanged tests; UAT 8 fn⌃⌥⌘ arrows pan (`node(n15) → node(n11)`, `→ node(n0)`, `→ node(n15)`, right refused) and macOS tiling did not act |
| 12 | SC6 / ZOOM-10 (hotkey, URL) | ✓ VERIFIED | Unchanged; now routed through `Navigator.target` (9ccd9d6) |
| 13 | SC6 / ZOOM-10 (title-bar double-click) | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 4: `title bar double-click → frame window 5482` → `home → node(n9)` (24-titlebar-frame.png); the second double-click gave `node(n9) → home`; macOS's own title-bar action did not run |
| 14 | SC6 / ZOOM-11 (hotkey, URL) | ✓ VERIFIED | Unchanged plus `frameDesktopOnAnEmptyDeskStaysHome` (IN-01) |
| 15 | SC6 / ZOOM-11 (Desktop double-click) | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 4: wallpaper hit `AXGroup` → `frame desktop` → `home → node(n0)` (25-desktop-frame.png), then back home; icon hit `AXImage`, no camera move, file opened (26-icon-dblclick.png). RESEARCH A4 confirmed on macOS 15.7 |
| 16 | SC6 / ZOOM-12: Esc cancels a ⌘⇧-drag rectangle zoom | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 1: `rect zoom canceled (Esc)` with ⌘⇧ held and with plain Esc; no move (15-esc.png); Esc then closed Spotlight (no lingering hotkey); ⌥⌘Esc opened Force Quit (16-forcequit.png) |
| 17 | SC6 / ZOOM-13 (engine): oversized tiles collapse instead of being refused with zoom on | ✓ VERIFIED | Unchanged; ArrangerCollapseTests pass |
| 18 | SC6 / ZOOM-13 (shell): collapsed app-colour blocks zoom in on double-click | ✓ VERIFIED | Was PRESENT_BEHAVIOR_UNVERIFIED. UAT 5: drop preview "Collapsed until you zoom in" (32-collapse-preview2.png); block with app icon and hover ring (33-collapsed-block2.png, inspected: dark block with Terminal-style icon and accent ring at top right); double-click `home → node(n17)`, Fixture 3 focused (34-block-zoomed.png); AX `AXButton desc=“TransomFixtureApp”, collapsed: Fixture 3`, AXPress zooms too. First-drop-floats residual accepted by the user (below) |

**Score:** 18/18 truths verified (0 present, behavior-unverified)

The seven truths that were PRESENT_BEHAVIOR_UNVERIFIED are promoted on directly observed VM behaviour: guest logs from `log stream --level debug` plus screenshots, on builds 9ccd9d6, 2f0823c and fab166d (test 12 and the re-tests). I opened 13-band, 21-duplicate, 33-collapsed-block2, 35-after-crash, 45-dark-fixed-crop and 61-rm-second-a, and each matches its UAT description. The log lines are quoted from 04-UAT.md. The raw guest logs are not kept under `.build/uat-04/`, so they could not be re-read.

### Accepted Residuals (not gaps)

| # | Residual | Basis | Why it does not block |
|---|---|---|---|
| 1 | IN-01 leftover: with one window and the Desktop hidden, Frame Focused Window commits `.node(leaf)`. The root is a split that includes the hidden Desktop, so `Navigator.target` does not normalise it. The view looks like home, but the status reads "zoomed in" | User judgement recorded in 04-UAT.md "User Judgements", 2026-10-28: accepted as cosmetic | Windows are on screen. Quit and crash use `homeTiles`, so nothing is left parked |
| 2 | First oversized drop floats: the first drop of a window whose minimum is not yet learned floats with N1 instead of collapsing; the second drop collapses | User judgement in 04-UAT.md, 2026-10-28: accepted as-is. Follows CONTEXT E (an OS-caused loss of room floats). Logged under Deferred Follow-Ups | The window stays on screen and reachable. The truth holds once the minimum is known |
| 3 | WR-04 in-flight case: Turn Off Zoom while a post-reveal refresh is actually inside ScreenCaptureKit | Verified by code reading only. UAT 14 could only trigger zoom off about 340 ms after the refresh ended. In code, `SnapshotCapture` is `@MainActor`; `close()` sets `closed` (line 91), and `refreshShareable` (45), `capture` (53, and again after the await at 75) and `refresh` (105) all check it before any SCK call or cache insert. `captureAll` starts every capture through `capture()`, so after close it can start no new ScreenCaptureKit call. At most one `captureImage` already dispatched finishes, and its result is dropped. `ZoomController.purge()` calls `close()` (ZoomController.swift:252) | The design is correct on reading, and the observable half passed in UAT 14 |
| 4 | IN-02..IN-09 info items (table below) | Review info scope, outside the fix scope | Cosmetic or test-quality only |

### Required Artifacts

`verify.artifacts`: 30/30 across 8 plans in the previous run. The three fix commits changed only Navigator.swift, TileLayer.swift and ArrangeController.swift, plus two test files, and each change was read above. No artifact was removed.

| Artifact | Status | Details |
|---|---|---|
| Engine: ViewPlanner, Arranger+Camera, Navigator, SettleTracker, Recovery | ✓ VERIFIED | Navigator edited by 9ccd9d6 |
| `Sources/TransomMac/Zoom/ZoomController.swift`, `SnapshotCapture.swift`, `StagePanel.swift`, `AppColor.swift` | ✓ VERIFIED | Behaviour observed in UAT 9, 10, 13, 14 |
| `Sources/TransomMac/Zoom/TileLayer.swift` | ✓ VERIFIED | 2f0823c; `text` is now internal for its test |
| `Sources/TransomMac/Zoom/ZoomInput.swift`, `Input/ZoomTapRules.swift` | ✓ VERIFIED | UAT 1, 2, 4, 12 |
| `Sources/TransomMac/Zoom/CollapsedPanels.swift` | ✓ VERIFIED | UAT 5 |
| `Sources/TransomMac/Zoom/ShortcutsWindowController.swift` | ✓ VERIFIED | UAT 3 |
| `Sources/TransomMac/ArrangeController.swift` | ✓ VERIFIED | fab166d activation exit; UAT 12, 15 |
| `Tests/TransomMacTests/TileLayerTests.swift` | ✓ VERIFIED (new) | passes |

### Key Link Verification

All 18 links from the previous report still hold. They were re-checked for the edited files:

| From | To | Status |
|---|---|---|
| `cameraStep(.frameWindow/.frameDesktop)` | `toggle(Navigator.target(...))` → `.home` for the root | ✓ WIRED (Navigator.swift:291, 294) |
| `NSWorkspace.didActivateApplicationNotification` (ArrangeController.swift:226) | `zoomInput.endPick(reason: "app activated")` | ✓ WIRED (observer installed by `startWatchdog`, which `startTap` calls at line 190) |
| `TileLayer` fallback content | `TileLayer.text` with the colour resolved at creation | ✓ WIRED |
| `ZoomController.purge` | `SnapshotCapture.close` | ✓ WIRED |

### Data-Flow Trace (Level 4)

Unchanged from the previous report. Tile content is real in both modes: snapshots when granted (UAT 13: `3 snapshots, 0 fallback`) and AppColor + icon when not (UAT 10).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full headless suite (run once, host) | `env -u TRANSOM_LIVE swift test` | 193 + 262 + 49 + 663 = 1167 tests; 1166 passed; 1 failure, `FreezeTestTests.itResumesByItself` (the known load flake: ran 13.4 s, 3 expectation misses). TransomMacTests grew from 261 to 262 (TileLayerTests) and TransomEngineTests from 662 to 663 (IN-01 test) | ✓ PASS (known flake) |
| Flake confirmation | `swift test --filter FreezeTestTests/itResumesByItself` | passed in 0.066 s | ✓ PASS |
| IN-01 regression test | from the full-run log | `frameDesktopOnAnEmptyDeskStaysHome()` passed | ✓ PASS |
| G-04-10 regression test | from the full-run log | `aDarkTitleStaysLightTextWhenDrawnLater()` passed | ✓ PASS |
| Live / VM suites | not run on the host (project rule) | VM evidence in 04-UAT.md and 04-08-SUMMARY | ? SKIP (covered by UAT) |

FreezeTest belongs to an earlier phase's code, and no phase-4 commit touches it.

### Probe Execution

No `scripts/*/tests/probe-*.sh` exists and no plan declares a probe, so this step does not apply.

### Requirements Coverage

| Req | Source plans | Status | Evidence |
|---|---|---|---|
| ZOOM-01 | 02, 03, 04, 05, 08 | ✓ SATISFIED | truth 1 |
| ZOOM-02 | 02, 03, 04, 05 | ✓ SATISFIED | truth 2 |
| ZOOM-03 | 03, 06 | ✓ SATISFIED | truth 3, UAT 1 |
| ZOOM-04 | 03, 05 | ✓ SATISFIED | truth 4 |
| ZOOM-05 | 01, 04, 08 | ✓ SATISFIED | truth 6, UAT 10, 13 |
| ZOOM-06 | 03, 06 | ✓ SATISFIED | truth 5, UAT 2, 12 |
| ZOOM-07 | 01, 02, 04, 08 | ✓ SATISFIED (write-path definition, user decision) | truth 7 |
| ZOOM-08 | 05 | ✓ SATISFIED | truth 9, UAT 3 |
| ZOOM-09 | 03, 05 | ✓ SATISFIED | truth 11, UAT 8 |
| ZOOM-10 | 03, 05, 06 | ✓ SATISFIED | truths 12, 13, UAT 4 |
| ZOOM-11 | 03, 05, 06 | ✓ SATISFIED | truths 14, 15, UAT 4 |
| ZOOM-12 | 06 | ✓ SATISFIED | truth 16, UAT 1 |
| ZOOM-13 | 02, 07 | ✓ SATISFIED (first-drop residual accepted) | truths 17, 18, UAT 5 |

No IDs are orphaned. REQUIREMENTS.md still shows ZOOM-03, 06, 08, 10, 11, 12 and 13 as `[ ]` / Pending. Per instructions this verifier did not edit it; the orchestrator should tick them.

### UI-SPEC backstops (from the previous human_verification list)

| Item | UAT | Result |
|---|---|---|
| kill -9 while zoomed, relaunch: nothing parked, N2 shows | 6 | pass (35-after-crash.png) |
| ⌘⇧-click on a Safari link opens a new tab | 7 | pass (40-safari-newtab.png) |
| fn-arrow pans without macOS tiling | 8 | pass |
| Reduce Motion crossfade | 9 | pass on re-test with the real System Settings switch (61-rm-second-a/b.png) |
| Fallback legibility light and dark, explainer once | 10 | pass after 2f0823c |
| Status menu stays above the stage | 11 | pass (46-menu-over-stage.png, menu at CG layer 101) |
| WR-02 / G-04-12, WR-03, WR-04, WR-06 | 12, 13, 14, 15 | pass (WR-04 in-flight is code-read, residual 3) |

### Prohibitions (judgment tier)

These were resolved in the end-of-phase UAT checkpoint (04-UAT.md test 16, pass, in the UAT the user accepted as complete). The verdicts come from Claude's observation in the VM plus code inspection; this verifier re-checked the code-inspection parts.

| Plan | MUST NOT | Resolution |
|---|---|---|
| 04-01 ZOOM-05 | write snapshots to disk / log image data | Holds. In the guest, App Support holds only layout.json and min-size-hints.json, nothing is under Caches, and no log line carries image data |
| 04-04 ZOOM-05 | ask for Screen Recording more than once on its own | Holds. The explainer showed once across 40 min, relaunches and a kill -9. `CGRequestScreenCaptureAccess` appears only in `SnapshotCapture.request()`. Note: macOS 15 showed its own "requesting to bypass the system private window picker" prompt on the first capture after the grant (61-rm-second-a.png). That prompt comes from the OS, not from a Transom request (see Info) |
| 04-04 ZOOM-05 | persist, log or share snapshots; purge on zoom off | Holds by code inspection (memory LRU; `close()` purges and blocks re-entry, residual 3); UAT 14: no SCK activity after zoom off |
| 04-06 ZOOM-12 | consume more than one press-release, leave Esc registered, register ⌥⌘Esc | Holds. UAT 1 and 2. The "Esc lingers after an app switch" exception in test 16's text came from the first run and is superseded by the UAT 12 re-test on fab166d |
| 04-06 ZOOM-03 | synthesise input other than the exact re-post | Holds. `ZoomInput.repost` is the only post site outside the spike; UAT 7 |
| 04-08 ZOOM-07 | leave any window parked after quit, crash, Restore All or Turn Off Zoom | Holds for all four in UAT 6, 15, 16. A crash loop was not exercised; it is covered by `aCrashLoopLaunch…` tests |

### Anti-Patterns Found

The files changed by the fix commits contain no TBD, FIXME, XXX, TODO or HACK markers.

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `Sources/TransomEngine/Navigator.swift` | 291 | IN-01 leftover (single window, hidden Desktop) | ℹ️ Info (accepted by the user) | Cosmetic status text |
| `Tests/TransomMacTests/ZoomOffTests.swift` | 12-25 | IN-09: controller never started, absolute `touches == 0` | ℹ️ Info | Guard weaker than claimed; UAT 14/15 cover the behaviour |
| `Sources/TransomMac/Zoom/ZoomInput.swift` | 69 | IN-05: double-click preference read only in `publish()`; the Mouse toggle was not exercised in UAT | ℹ️ Info | Toggle lags until the next republish |
| `Sources/TransomMac/Shell/StatusItemController.swift` | 160-166 | IN-06 | ℹ️ Info | First menu use may show the prompt and Settings together |
| `Sources/TransomMac/Zoom/StagePanel.swift` | 78-94 | IN-07 | ℹ️ Info | First-move cost |
| `Sources/TransomMac/Zoom/CollapsedPanels.swift` | 196 | IN-08 | ℹ️ Info | A block can take clicks from an excluded window |
| `Sources/TransomMac/Zoom/SnapshotCapture.swift` | 64-74 | IN-02 | ℹ️ Info | Uncancelled timeout tasks |
| `Sources/TransomMac/Zoom/AppColor.swift` | 35-40 | IN-03 | ℹ️ Info | Grey cached on a nil icon |
| `Sources/TransomMac/Zoom/SnapshotCapture.swift` | (cache) | IN-04: a closed native-tab window's entry is pruned at the next refresh | ℹ️ Info | Memory only |
| (OS) | — | The macOS 15 "bypass the system private window picker" consent appears on the first capture after a grant and re-appears periodically | ℹ️ Info | Cannot be suppressed; onboarding copy should mention it (STACK note) |
| (VM harness) | — | Guest display sleep leaves `CGMainDisplayID() == 0` and offsets `NSScreen` frames (UAT Deferred Follow-Ups) | ℹ️ Info | Seen only in the VM; worth a check on real hardware |

### Human Verification Required

None. Every item from the previous report was run in the Tart VM (04-UAT.md, 16/16) and is mapped above.

### Gaps Summary

There are no gaps. All 18 truths are verified. The seven pointer, event-tap and panel truths that had only run headless were observed in the VM, with logs and screenshots for each. The three fix commits are correct. IN-01 and G-04-10 each have a regression test, and both passed in the single full headless run (1166/1167, with the one failure the known FreezeTest load flake, which passes on its own). G-04-12 is shell-only and was confirmed in the VM re-test. Four residuals are recorded and none blocks: two were accepted by the user in 04-UAT.md, WR-04's in-flight case was checked by code reading, and the rest are info items. The phase goal is achieved: the user can zoom out to every window, zoom back in to any of them by keyboard, URL, rectangle, click or double-click, and the chosen window ends up framed and focused.

---

_Verified: 2026-10-28T21:40:00Z_
_Verifier: Claude (gsd-verifier)_
