---
phase: "4"
slug: "zoom-camera"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-27"
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: 04-RESEARCH.md § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing; live suites gated by `TRANSOM_LIVE=1`, run in the Tart VM only |
| **Config file** | `Package.swift` (TransomModelTests, TransomEngineTests, TransomMacTests, TransomMacIntegrationTests) |
| **Quick run command** | `swift test --filter <Suite>` (must show ≥1 executed test; "0 tests" is a failure) |
| **Full suite command** | `swift test` (host, headless). Live: `scripts/vm-live-test.sh <filter>` (VM only) |
| **Estimated runtime** | ~60 seconds (full headless suite) |

---

## Sampling Rate

- **After every task commit:** Run the `swift test --filter` for the touched suite, with an executed count above 0
- **After every plan wave:** Run `swift test`
- **Before `/gsd-verify-work`:** Full suite must be green. Spike gates G1–G4 must be recorded as passes with numbers in `04-SPIKE.md`, and VM live suites must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

Filled in by the planner and the executor, one row per task. The requirement-to-test map below is what each row must trace back to.

| Req ID | Behavior | Test Type | Automated Command | File Exists |
|--------|----------|-----------|-------------------|-------------|
| ZOOM-01 | Home view = Phase 3 plan; Zoom Out emits cameraMove then settle unparks | unit | `swift test --filter ArrangerCameraTests` | ❌ W0 |
| ZOOM-02 | Step in/out targets, refusals at home and at a leaf | unit | `swift test --filter NavigatorTests` | ❌ W0 |
| ZOOM-03 | Lowest common ancestor of leaf centres inside the band; ⌘⇧ consume rule; a move under 4 pt is re-posted | unit | `swift test --filter "NavigatorTests\|ZoomTapRulesTests"` | ❌ W0 |
| ZOOM-04 | 50-entry history per display, dead-node skip, no double push | unit | `swift test --filter CameraHistoryTests` | ❌ W0 |
| ZOOM-05 | ScreenCaptureKit only in SnapshotCapture.swift; fallback when not granted; app colour | unit + static | `swift test --filter "NoScreenCaptureTests\|AppColorTests"` | ✅ narrow / ❌ W0 |
| ZOOM-05 | Captures work in the VM; revoking falls back silently | live (VM) | `scripts/vm-live-test.sh SnapshotCaptureIntegrationTests` | ❌ W0 |
| ZOOM-06 | Pick-mode click consumed only on docked/collapsed tiles; focus after settle | unit | `swift test --filter "ZoomTapRulesTests\|ArrangerCameraTests"` | ❌ W0 |
| ZOOM-07 | At settle, only changed and visible windows are written; parks first after `.save(.now)`; no writes between move and settle | unit | `swift test --filter "ArrangerCameraTests\|SettleTrackerTests"` | ❌ W0 |
| ZOOM-07 | ≤500 ms p95 for 15 windows, no stale flash | spike + live (VM) | `transom-zoom-spike settle --runs 20`; `scripts/vm-live-test.sh ZoomSettleIntegrationTests` | ❌ W0 |
| ZOOM-08 | 44 Recorder rows ↔ 44 stable names; duplicate validation | unit | `swift test --filter "HotkeyTableTests\|ShortcutsModelTests"` | ✅ extend / ❌ W0 |
| ZOOM-09 | Pan targets; 4 URL hosts parse, others rejected | unit | `swift test --filter "NavigatorTests\|TransomURLTests"` | ✅ extend / ❌ W0 |
| ZOOM-10 | Frame window toggles; title-bar double-click consumed only for docked windows with pref on | unit | `swift test --filter "NavigatorTests\|ZoomTapRulesTests"` | ❌ W0 |
| ZOOM-11 | Desktop view; refused while Desktop hidden | unit | `swift test --filter "NavigatorTests\|ZoomTapRulesTests"` | ❌ W0 |
| ZOOM-12 | Esc hotkeys registered only while the band is active, then unregistered | unit + UAT | `swift test --filter ZoomTapRulesTests` | ❌ W0 |
| ZOOM-13 | Two-pass collapse; drop accepted with zoom on, refused with zoom off | unit | `swift test --filter "ViewPlannerTests\|ArrangerCameraTests"` | ❌ W0 |
| SC-4 | Quit while zoomed restores home tiles; crash relaunch unparks; Restore All goes home | unit + live + UAT | `swift test --filter "RecoveryTests\|ArrangerCameraTests"`; `scripts/vm-live-test.sh "QuitRestoreIntegrationTests\|RecoveryIntegrationTests"` | ✅ extend |
| SC-5 | All Phase 3 tests unchanged with `zoomEnabled = false`; ScreenCaptureKit never touched with zoom off | unit (whole suite) | `swift test` | ✅ |
| Rehome | A parked docked window is never re-homed across displays | unit | `swift test --filter ArrangerCameraTests` | ❌ W0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/TransomModelTests/SubtreeTests.swift`
- [ ] `Tests/TransomEngineTests/ViewPlannerTests.swift`
- [ ] `Tests/TransomEngineTests/NavigatorTests.swift`, `CameraHistoryTests.swift`
- [ ] `Tests/TransomEngineTests/SettleTrackerTests.swift`
- [ ] `Tests/TransomEngineTests/ZoomTapRulesTests.swift`
- [ ] `Tests/TransomEngineTests/ArrangerCameraTests.swift`
- [ ] `Tests/TransomMacTests/NoScreenCaptureTests.swift`: allow-list narrowed to `SnapshotCapture.swift`; add `SCScreenshotManager`, `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess` to the forbidden literals
- [ ] `Tests/TransomMacTests/AppColorTests.swift`, `ZoomCopyTests.swift`
- [ ] `Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift`, `SnapshotCaptureIntegrationTests.swift` (VM only)
- [ ] `Sources/transom-zoom-spike/` harness + `04-SPIKE.md` results template

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `kill -9` while zoomed, relaunch, all windows home | SC-4 | Needs a real crash of the signed app | In the VM: zoom in, `kill -9` Transom, relaunch, confirm no window is parked or off-screen |
| ⌘⇧-click still reaches Safari | ZOOM-03 | Needs a real app's selection behaviour | ⌘⇧-click in Safari text without moving; the selection extends |
| fn⌃⌥⌘← pans and doesn't trigger macOS tiling | ZOOM-09 | Depends on the system keyboard path | Press it while zoomed in; the view pans and macOS tiling doesn't fire |
| Reduce Motion crossfade | UI-SPEC | Accessibility setting, visual | Turn Reduce Motion on, zoom; a crossfade plays instead of a zoom |
| Fallback tile legibility | ZOOM-05 | Visual judgement | With Screen Recording denied, zoom out; the app colour, icon and title are readable |
| Stage above open menus | Spike G | Window-level interaction | Open a menu, trigger a zoom; record the behaviour in 04-SPIKE.md |

All UAT is driven by Claude in the Tart VM, with the Debug-only switch that makes the stage capturable.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
