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

Filled in by the planner (2026-10-27), one row per task; the executor updates Status. "unit" commands pass only with a non-zero executed count and no "✘"; VM commands run only in the Tart VM.

| Task ID | Plan | Wave | Requirement | Threat Ref | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------|-------------------|-------------|--------|
| 04-01-T1 | 01 | 1 | ZOOM-05, ZOOM-07 | T-04-01, T-04-03 | static + VM spike | `swift test --filter NoScreenCaptureTests`; `scripts/vm-spike.sh settle --runs 2 --fixtures 4` | ✅ narrow / ❌ W0 | ⬜ pending |
| 04-01-T2 | 01 | 1 | ZOOM-07 | T-04-02, T-04-04, T-04-05 | VM spike gates G1-G8 | `scripts/vm-spike.sh settle --stage …`, `capture`, `layers`, `soak`, `menus`; `swift test` | ❌ W0 | ⬜ pending |
| 04-01-T3 | 01 | 1 | ZOOM-07 | — | checkpoint (go/no-go) | manual: 04-SPIKE.md Verdict | — | ⬜ pending |
| 04-02-T1 | 02 | 2 | ZOOM-01, ZOOM-02, ZOOM-07 | T-04-06, T-04-07, T-04-08 | unit | `swift test --filter "ArrangerCameraTests\|ArrangerDesktopTests\|ArrangerLifecycleTests\|ArrangerMultiDeskRestoreTests"` | ❌ W0 | ⬜ pending |
| 04-02-T2 | 02 | 2 | ZOOM-13, ZOOM-07 | T-04-09 | unit | `swift test --filter "ViewPlannerTests\|SubtreeTests\|SettleTrackerTests\|PlannerTests\|ArrangerCameraTests"`; `swift test` | ❌ W0 | ⬜ pending |
| 04-03-T1 | 03 | 3 | ZOOM-01, ZOOM-02 | T-04-12 | unit | `swift test --filter "NavigatorTests\|ArrangerCameraTests\|CommandTests\|MenuCopyTests\|ArrangerCommandTests"` | ❌ W0 | ⬜ pending |
| 04-03-T2 | 03 | 3 | ZOOM-04, ZOOM-09, ZOOM-10, ZOOM-11 | — | unit | `swift test --filter "NavigatorTests\|CameraHistoryTests\|ArrangerCameraTests\|MenuCopyTests"` | ❌ W0 | ⬜ pending |
| 04-03-T3 | 03 | 3 | ZOOM-03, ZOOM-06 | T-04-10, T-04-11 | unit | `swift test --filter "ArrangerCameraTests\|NavigatorTests\|CameraHistoryTests"`; `swift test` | ❌ W0 | ⬜ pending |
| 04-04-T1 | 04 | 3 | ZOOM-01, ZOOM-02, ZOOM-07 | T-04-14 | unit + live (VM) | `swift test`; `scripts/vm-live-test.sh ZoomSettleIntegrationTests` | ❌ W0 | ⬜ pending |
| 04-04-T2 | 04 | 3 | ZOOM-05 | T-04-13, T-04-16 | unit | `swift test --filter "AppColorTests\|SnapshotCacheTests\|NoScreenCaptureTests"` | ❌ W0 | ⬜ pending |
| 04-04-T3 | 04 | 3 | ZOOM-05 | T-04-15 | unit + live (VM) | `swift test --filter "ZoomCopyTests\|AppColorTests\|NoScreenCaptureTests"`; `scripts/vm-live-test.sh "SnapshotCaptureIntegrationTests\|ZoomSettleIntegrationTests"` | ❌ W0 | ⬜ pending |
| 04-05-T1 | 05 | 4 | ZOOM-08, ZOOM-09, ZOOM-10, ZOOM-11 | T-04-17, T-04-18, T-04-19 | unit | `swift test --filter "HotkeyTableTests\|TransomURLTests\|CommandTests"` | ✅ extend | ⬜ pending |
| 04-05-T2 | 05 | 4 | ZOOM-01, ZOOM-02, ZOOM-04 | — | unit | `swift test --filter "CommandMenuTests\|MenuCopyTests\|ZoomCopyTests"` | ✅ extend | ⬜ pending |
| 04-05-T3 | 05 | 4 | ZOOM-08 | — | unit | `swift test` (ShortcutsModelTests must run) | ❌ W0 | ⬜ pending |
| 04-06-T1 | 06 | 5 | ZOOM-03 | T-04-20, T-04-23 | unit | `swift test --filter "ZoomTapRulesTests\|GreenButtonHitTests\|TopmostWindowTests"` | ❌ W0 | ⬜ pending |
| 04-06-T2 | 06 | 5 | ZOOM-12, ZOOM-03 | T-04-21, T-04-22 | unit + UAT | `swift test --filter "ZoomTapRulesTests\|ZoomCopyTests\|PreviewStyleTests"` | ❌ W0 | ⬜ pending |
| 04-06-T3 | 06 | 5 | ZOOM-06, ZOOM-10, ZOOM-11 | T-04-20 | unit + UAT | `swift test` (ZoomTapRulesTests must run) | ❌ W0 | ⬜ pending |
| 04-07-T1 | 07 | 6 | ZOOM-13 | T-04-24, T-04-25 | unit | `swift test --filter "ArrangerCollapseTests\|ArrangerDragTests\|TooBigDockedWindowTests\|ArrangerCameraTests"` | ❌ W0 | ⬜ pending |
| 04-07-T2 | 07 | 6 | ZOOM-13 | T-04-26 | unit | `swift test --filter "ArrangerCollapseTests\|ArrangerCommandTests\|ArrangerDragTests\|PreviewStyleTests"` | ❌ W0 | ⬜ pending |
| 04-07-T3 | 07 | 6 | ZOOM-13 | — | unit | `swift test`; `scripts/check-no-appkit.sh` | ✅ extend | ⬜ pending |
| 04-08-T1 | 08 | 7 | ZOOM-07 (SC-4) | T-04-27 | unit + live (VM) | `swift test --filter "RecoveryTests\|ArrangerCameraTests"`; `scripts/vm-live-test.sh QuitRestoreIntegrationTests` | ✅ extend | ⬜ pending |
| 04-08-T2 | 08 | 7 | ZOOM-05 (SC-5), SC-4 | T-04-28, T-04-29, T-04-30 | unit | `swift test` (ZoomOffTests must run); `scripts/check-no-appkit.sh` | ❌ W0 | ⬜ pending |
| 04-08-T3 | 08 | 7 | ZOOM-07, SC-4 | — | live (VM) + UAT | `scripts/vm-live-test.sh "ZoomSettleIntegrationTests\|SnapshotCaptureIntegrationTests"`; `scripts/vm-live-test.sh "QuitRestoreIntegrationTests\|RecoveryIntegrationTests"` | ✅ extend | ⬜ pending |

### Requirement → Test Map (source: RESEARCH Validation Architecture)

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

Test files the plans create before or with their code (paths as planned; RESEARCH's SubtreeTests became a suite inside ViewPlannerTests.swift, and ZoomTapRulesTests moved to TransomMacTests beside GreenButtonHitTests because the rules take CoreGraphics event types):

- [ ] `Tests/TransomEngineTests/ViewPlannerTests.swift` (with `@Suite struct SubtreeTests`) — 04-02
- [ ] `Tests/TransomEngineTests/ArrangerCameraTests.swift` — 04-02, extended by 04-03 and 04-08
- [ ] `Tests/TransomEngineTests/SettleTrackerTests.swift` — 04-02
- [ ] `Tests/TransomEngineTests/NavigatorTests.swift` (with `@Suite struct CameraHistoryTests`) — 04-03
- [ ] `Tests/TransomMacTests/NoScreenCaptureTests.swift`: allow-list narrowed to `SnapshotCapture.swift`; add `SCScreenshotManager`, `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess` to the forbidden literals — 04-01
- [ ] `Tests/TransomMacTests/AppColorTests.swift` (with `SnapshotCacheTests`), `ZoomCopyTests.swift` — 04-04
- [ ] `Tests/TransomMacTests/ShortcutsModelTests.swift` — 04-05
- [ ] `Tests/TransomMacTests/ZoomTapRulesTests.swift` — 04-06
- [ ] `Tests/TransomEngineTests/ArrangerCollapseTests.swift` — 04-07
- [ ] `Tests/TransomMacTests/ZoomOffTests.swift` — 04-08
- [ ] `Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift`, `SnapshotCaptureIntegrationTests.swift` (VM only) — 04-04, extended by 04-08
- [ ] `Sources/transom-zoom-spike/` harness, `scripts/vm-spike.sh` and `04-SPIKE.md` results — 04-01

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
