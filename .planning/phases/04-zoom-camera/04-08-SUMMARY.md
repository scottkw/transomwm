---
phase: 04-zoom-camera
plan: 08
subsystem: zoom
status: complete
tags: [engine, recovery, quit-restore, restore-all, screencapturekit, live-gate, swift-testing]
requires:
  - phase: 04-02
    provides: "ViewPlanner.plan(view: .home) with collapsible, CameraState, planShown save-before-park"
  - phase: 04-04
    provides: "ZoomController settle tracking (lastSettle, isIdle), SnapshotCapture, ZoomSettleIntegrationTests"
  - phase: 04-07
    provides: "collapsed windows (docked, parked, no home tile), the T-04-24 risk handed to this plan"
provides:
  - "Recovery.terminationPlan(…, homeTiles:) (defaulted): a docked window more than 2 pt off its home-view tile goes back to it on quit"
  - "Arranger.homeTiles(): home-view tiles of every desk whose camera is not at home (shown or not); empty at home and with zoom off"
  - "Arranger.goHome(): clears views, paths and pending moves; Restore All calls it before the Phase 3 rescue"
  - "SnapshotCapture.touches and ArrangeController.hasZoomController (zoom-off guard)"
  - "ZoomController keeps its reveal timer (fix: an earlier settle's cap timer no longer reveals the next move early)"
  - "Live phase gates: fifteenWindowsSettleWithinBudget (p95), quitWhileZoomedRestoresHomeTiles, aRelaunchAfterACrashWhileZoomedBringsWindowsBack"
affects: [verify-work, ship]
tech-stack:
  added: []
  patterns:
    - "Quit-time camera rescue keyed on 'camera not at home', so zoom off and home keep the Phase 3 quit plan byte for byte"
    - "A class value in a dictionary is stored explicitly before calling a method on it (the `default:` subscript only reads)"
key-files:
  created:
    - Tests/TransomMacTests/ZoomOffTests.swift
  modified:
    - Sources/TransomEngine/Recovery.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/Arranger+Commands.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Zoom/SnapshotCapture.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Tests/TransomEngineTests/RecoveryTests.swift
    - Tests/TransomEngineTests/ArrangerCameraTests.swift
    - Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift
key-decisions:
  - "homeTiles() covers only desks whose camera is not at home. At home the OS can keep a docked window a few points off its tile (Terminal cells; the VM's SSH-session visibleFrame includes the menu bar), and Phase 3 leaves such windows alone at quit"
  - "homeTiles() also covers zoomed desks on Spaces that are not shown, so parked windows there get a quit write too (it lands if AX can reach them)"
  - "Crash and crash-loop relaunches needed no code: the camera is never persisted, rescueStranded runs while paused and re-attach rewrites tiles more than 0.5 pt off. Tests now pin it"
  - "A crash-loop rescue centres parked docked windows (Phase 3 rule) and Resume puts them in their tiles; it does not use home tiles while paused (that would change the Phase 3 rescue expectations)"
  - "SnapshotCapture.touches also counts refreshShareable, which reaches ScreenCaptureKit too (5 increment sites, not the plan's 3)"
requirements-completed: [ZOOM-01, ZOOM-02, ZOOM-04, ZOOM-05, ZOOM-07, ZOOM-09]
estimate:
  tokens: 80000
  tasks: 3
actuals:
  tokens: 8106
  tasks: 3
  commits: 6
plan_head_before: b6faf3d484f5faa0ebeb47a98da923699a63463a
plan_head_after: 113f70957496cecec2ddb9b75ceb9b9f24bc20ca
duration: 21 min
completed: 2026-10-28
coverage:
  - id: D1
    description: "Quit while zoomed: parked and zoomed docked windows go to their home tiles, within 2 pt left alone, no tile keeps the stranded rule, floaters and the no-homeTiles call unchanged"
    requirement: "ZOOM-07"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/RecoveryTests.swift#aParkedDockedWindowGoesBackToItsHomeTile"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#homeTilesAreTheHomeViewWhileZoomed"
        status: pass
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift#quitWhileZoomedRestoresHomeTiles"
        status: pass
    human_judgment: false
  - id: D2
    description: "Restore All returns every display's camera home first, then rescues; N6 counts un-parked windows; paused rescue then Resume tiles everything"
    requirement: "ZOOM-01"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#restoreAllReturnsEveryCameraHome"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#restoreAllWhilePausedUnparksAndResumeTilesEveryWindow"
        status: pass
    human_judgment: false
  - id: D3
    description: "Recovery and crash-loop relaunches after a crash while zoomed bring parked docked windows back (camera starts home)"
    requirement: "ZOOM-07"
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#aRecoveryLaunchBringsParkedDockedWindowsBack"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerCameraTests.swift#aCrashLoopLaunchStillRescuesParkedDockedWindows"
        status: pass
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift#aRelaunchAfterACrashWhileZoomedBringsWindowsBack"
        status: pass
    human_judgment: false
  - id: D4
    description: "Zoom off: every camera command dispatched (hotkey, menu, URL) makes no ZoomController and touches no ScreenCaptureKit"
    requirement: "ZOOM-05"
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/ZoomOffTests.swift#zoomOffNeverTouchesScreenCaptureKit"
        status: pass
    human_judgment: false
  - id: D5
    description: "ZOOM-07 gate: 15 fixture windows, 20 settles, every window on target, write-path p95 <= 500 ms"
    requirement: "ZOOM-07"
    verification:
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift#fifteenWindowsSettleWithinBudget"
        status: pass
    human_judgment: false
  - id: D6
    description: "kill -9 Transom Debug while zoomed, relaunch: no window parked and N2 shows (UI-SPEC backstop)"
    requirement: "ZOOM-07"
    verification:
      - kind: manual_procedural
        ref: "VM UAT (pane-test), /gsd-verify-work"
        status: unknown
    human_judgment: true
---

# Phase 4 Plan 08: Parking Safety and Phase-Gate Live Runs Summary

**No exit path strands a window any more. Quitting while zoomed puts every docked window back in its home tile. Restore All sends every camera home before its Phase 3 rescue. Crash and crash-loop relaunches bring parked windows back, and zoom off provably never touches ScreenCaptureKit. In the VM, 15 windows settle at p95 149 ms and 79 ms over two runs (budget 500 ms). That run also exposed and fixed a 04-04 reveal-timer bug that made the stage reveal before the writes had landed.**

## Performance

- Duration: about 21 min (16:15Z to 16:37Z)
- Tasks: 3 of 3. Task 1 was a tracer. Its gate re-ran both automated verifies (headless 62 tests; VM QuitRestore 3/3) before expanding.
- Files: 12 (1 created, 11 modified)

## Task Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | 7ec7290 | test(04-08): add failing quit-while-zoomed home tile tests |
| 1 GREEN | 2137f3d | feat(04-08): quit while zoomed puts docked windows back in their home tiles |
| 2 RED | 57e510c | test(04-08): add failing Restore All home-first, crash relaunch and zoom-off guard tests |
| 2 GREEN | 75acb3f | feat(04-08): Restore All goes home first; zoom-off ScreenCaptureKit touch guard |
| 3 fix | 8edc31f | fix(04-08): keep the stage's reveal timer so an old settle's cap cannot reveal the next move |
| 3 | 113f709 | test(04-08): phase-gate live runs: 15-window settle p95 and crash relaunch while zoomed |

## TDD

- **Task 1:** RED `7ec7290`: RecoveryTests and ArrangerCameraTests failed to compile (`extra argument 'homeTiles'`, `no member 'homeTiles'`). GREEN `2137f3d`: 62 tests in 3 suites (RecoveryTests, ArrangerCameraTests, ArrangerRestoreTests) passed; VM QuitRestore 3/3.
- **Task 2:** RED `57e510c`: ZoomOffTests failed to compile (no `SnapshotCapture.touches`, no `hasZoomController`). The two Restore All tests failed: the views stayed zoomed and windows were not back in their tiles. The recovery and crash-loop tests already passed on existing behaviour, as RESEARCH Pattern 9 predicted. They pin that behaviour. GREEN `75acb3f`: full suite passed.
- Expectation guard: `git diff 7ec7290^ -- Tests/ | grep -c '^-.*#expect'` printed 0.

## Live Results (VM pane-test, scripts/vm-live-test.sh, under caffeinate)

| Run | Result |
|-----|--------|
| `QuitRestoreIntegrationTests` (Task 1) | 3/3 passed, no skips |
| `ZoomSettleIntegrationTests\|SnapshotCaptureIntegrationTests` | 5/5 passed, no skips; `p95 149 ms` |
| `QuitRestoreIntegrationTests\|RecoveryIntegrationTests` | 5/5 passed, no skips |
| `fifteenWindowsSettleWithinBudget` second sample | passed; `p95 79 ms` |

**ZOOM-07 settle, write path only (first AX write to last read-back; capture budget, animation and 50 ms redraw excluded):**

| Source | Windows | n | p50 | p95 | max |
|--------|---------|---|-----|-----|-----|
| 04-08 live run 1 (fixture only, in + home) | 15 | 20 | 23 ms | 149 ms | 151 ms |
| 04-08 live run 2 (fixture only, in + home) | 15 | 20 | 31 ms | 79 ms | 86 ms |
| 04-SPIKE.md G1 in (8 fixture + VS Code, Safari, Terminal, TextEdit) | 15 | 20 | 64.8 ms | 205.1 ms | 280.3 ms |
| 04-SPIKE.md G1 out | 15 | 20 | 58.0 ms | 93.1 ms | 110.3 ms |
| 04-SPIKE.md G1 fixture bundle only, in | 8 | 20 | 18.7 ms | 204.6 ms | 205.1 ms |

Every one of the 40 live settles had all 15 windows within 2 pt of their planned frame (parked ones stranded). Electron and other real apps are covered by the spike's G1, not by this fixture-only suite (flagged assumption).

## Verification

- Full headless `swift test`: 193 + 261 + 49 + 657 = **1160** Swift Testing tests passed across 4 bundles, no ✘. The XCTest lines report 0 executed, as before. The known FreezeTestTests flake did not fire.
- `scripts/check-no-appkit.sh`: OK (44 files). `import ScreenCaptureKit` appears only in `Sources/TransomMac/Zoom/SnapshotCapture.swift`.
- Acceptance greps: `homeTiles` in Recovery.swift (non-comment) 2; `homeTiles: arranger.homeTiles()` in ArrangeController.swift 1; `goHome()` in Arranger+Commands.swift 1; `touches` in SnapshotCapture.swift 6; `fifteenWindowsSettleWithinBudget` and `aRelaunchAfterACrashWhileZoomedBringsWindowsBack` 1 each.
- Nothing live ran on the host. `.planning/config.json` and `.planning/state.json` were never staged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The stage's reveal timer was never stored (04-04 code)**
- **Found during:** Task 3, first live 15-window run (p95 1500 ms; 2 of 20 settles "capped")
- **Issue:** `revealTimers[uuid, default: WakeTimer()].set(at)` calls a method on a class through the `default:` subscript. That only reads the dictionary, so no timer was ever stored. `cancel()` did nothing, and every armed timer stayed alive. The previous settle's `started + 1500 ms` timer fired during the next move's settle and revealed the stage before the writes had landed. That is a stale-flash risk, and it logged a false 1500 ms. The guest log shows it: settle started 16:30:51.625, false cap at 53.123 (1.5 s later, about 80 ms into the next settle). The early reveal also let the next move start while writes were still queued, which inflated later settles too (run p50 253 ms vs 23 ms after the fix).
- **Fix:** store the timer before calling `set`. No other `default:` call site holds a class (`CameraHistory` is a struct).
- **Files:** Sources/TransomMac/Zoom/ZoomController.swift. **Commit:** 8edc31f

**2. [Rule 1 - Bug] `homeTiles()` limited to desks whose camera is not at home**
- **Found during:** Task 1, first VM run. The existing `theQuitRestoreReturnsAParkedWindowToItsHomeFrame` counted 2 writes, not 1.
- **Issue:** in the VM's SSH session the visibleFrame includes the menu bar, so macOS keeps a docked window 17 pt below its planned tile. A rule covering every shown desk rewrote that Phase 3 docked window at quit. The same would happen to any window the OS keeps a few points off (Terminal snaps to character cells), and it broke a Phase 3 expectation.
- **Fix:** `homeTiles()` plans only desks whose resolved view is not `.home`, shown or not. Zoom off and home are exactly Phase 3; zoomed desks on non-shown Spaces are covered too. `homeTilesAreTheHomeViewWhileZoomed` also checks it is empty at home.
- **Files:** Arranger+Camera.swift. **Commit:** 2137f3d

### Adjustments

**3. [Test precision] Corrections to my own new tests before GREEN**
- The fake reports whole points and plans can be half points (485.5 vs 485), so the relaunch tests compare within 1 pt.
- The crash-loop test checks where the windows end up after Resume, not which writes Resume sends. b's centred rescue frame happens to equal its middle-column tile, so Resume correctly writes nothing for it.
- The live quit test's tiling precondition uses the settled, non-overlapping fixture frames instead of `homeTiles()`, which is now empty at home.
- No pre-existing expectation was touched.

**4. [Scope] `goHome()` also clears `camera.paths`**: these are the committed views' ancestor paths; `commit(.home)` clears them the same way.

**5. [Scope] `SnapshotCapture.touches` also counts `refreshShareable()`**: it reaches ScreenCaptureKit too, so the guard would otherwise miss it.

**6. [Live harness] Arrange All instead of move-then-Dock** to dock 3 or 15 fixture windows in the live tests: one command, with no per-window positioning into the Desktop tile's edge band.

## Known Stubs

None.

## Known Limitations

- **Restore All with collapsed windows:** a collapsed window at home is parked by design (it shows as a block). Restore All rescues it on screen (and counts it), then the replan parks it again as a block. Turn Off Zoom floats collapsed windows with N1, as 04-07 built. This flicker was not changed.
- **Crash-loop:** parked docked windows are centred (on screen, not parked) until Resume, then tiled. This follows the Phase 3 rule.
- **Zoomed desk on a Space that is not shown:** the quit plan includes its windows, but a write only lands if AX can reach a window on another Space. Not exercised live.

## Threat Flags

None beyond the plan's register:
- T-04-27: `homeTiles` in `terminationPlan`, headless and live.
- T-04-28: camera never persisted; recovery and crash-loop tests; live crash relaunch; the kill -9 check stays a UAT backstop.
- T-04-29: `goHome()` before the rescue; `restoreAllReturnsEveryCameraHome`.
- T-04-30: `zoomOffNeverTouchesScreenCaptureKit` (touches stays 0, no ZoomController).

## UAT Checklist for /gsd-verify-work (VM only, Claude-driven, TRANSOM_STAGE_CAPTURABLE=1)

1. kill -9 Transom Debug while zoomed, relaunch: no window parked, N2 shows.
2. ⌘⇧-click a Safari link opens a new tab (re-post).
3. fn⌃⌥⌘← pans; macOS window tiling does not also act.
4. Double-click a desktop icon opens it without framing; bare wallpaper in the Desktop tile frames the Desktop (records RESEARCH A4's roles).
5. Reduce Motion crossfades, with no tile moving or scaling.
6. With Screen Recording denied, fallback tiles for Notes, Terminal and a saturated-icon app are legible in light and dark mode.
7. A menu opened during a move stays above the stage.
8. Earlier plans' open UAT items: Shortcuts window (04-05), ⌘⇧-drag band and Esc, pick-mode click, title-bar double-click (04-06), collapsed block panels, hover, double-click and VoiceOver (04-07).

Recorded in `.planning/WINDOWS.md` as an `unrun-verify` entry for phase 4.

## Self-Check: PASSED

- FOUND: Tests/TransomMacTests/ZoomOffTests.swift, Sources/TransomEngine/Recovery.swift, Sources/TransomEngine/Arranger+Camera.swift, Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift, this SUMMARY.
- FOUND commits on HEAD: 7ec7290, 2137f3d, 57e510c, 75acb3f, 8edc31f, 113f709.
- Measured: `git rev-list --count b6faf3d..HEAD` = 6 before this SUMMARY's commit.
