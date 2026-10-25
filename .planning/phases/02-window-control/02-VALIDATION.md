---
phase: "2"
slug: "window-control"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: true) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-10-24"
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (toolchain bundled), as in Phase 1 |
| **Config file** | none (SwiftPM); CI: `.github/workflows/ci.yml` |
| **Quick run command** | `swift test --filter PaneEngineTests` |
| **Full suite command** | `swift test && swift test -c release -Xswiftc -enable-testing` |
| **Trusted integration** | `swift test --filter PaneMacIntegrationTests` (auto-skips without AX trust) |
| **Estimated runtime** | ~30 seconds (quick), ~120 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter PaneEngineTests` plus `scripts/check-no-appkit.sh`
- **After every plan wave:** Run `swift test && swift test -c release -Xswiftc -enable-testing`
- **Before `/gsd-verify-work`:** Full suite green (integration suite from a trusted terminal), signed Debug build verified with `codesign`, manual UAT checklist signed off
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

Filled in by the planner/executor per task. Requirement → test map from RESEARCH.md:

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| WIN-01 | Permission reducer transitions; stale forms A/B; reset exit-code handling | unit | `swift test --filter PermissionReducerTests` | ✅ | ✅ green |
| WIN-02 | Inventory + created/destroyed events; CG-only and non-AXWindow ignored | unit + integration | `swift test --filter "WindowTrackerTests\|ScenarioTests\|FixtureTrackingTests\|LiveTrackingTests"` | ✅ | ✅ green | ⬜ pending |
| WIN-03 | Hung app doesn't block other apps' commands; degraded tracker | unit + integration | `swift test --filter "ResponsivenessTrackerTests\|ResponsivenessScenarioTests\|FreezeIntegrationTests"` | ✅ | ✅ green | ⬜ pending |
| WIN-04 | Learned minimum; latest-wins coalescing; size→pos→size; display coordinates | unit + integration | `swift test --filter "MinimumSizeLearnerTests\|FrameScenarioTests\|FrameWriteIntegrationTests\|CoordinatesTests"` | ✅ | ✅ green | ❌ W0 | ⬜ pending |
| WIN-05 | Corpus classification matches labels | unit + integration | `swift test --filter "ClassifierCorpusTests\|TrackerClassificationTests"` | ✅ | ✅ green |
| WIN-06 | Tab group = one window; switch rebinds without create/destroy | unit + integration | `swift test --filter "TabGroupTrackerTests\|TabScenarioTests\|TabsIntegrationTests"` | ✅ | ✅ green | ⬜ pending |
| WIN-08 | Excluded bundle IDs: commands dropped, windows still listed | unit | `swift test --filter "ExclusionStoreTests\|ExclusionScenarioTests\|ExclusionIntegrationTests"` | ✅ | ✅ green |
| WIN-09 | Close rule table incl. timeout/lock/terminated; closed-ID cache | unit + integration | `swift test --filter "CloseRuleTests\|CloseScenarioTests\|CloseIntegrationTests"` | ✅ | ✅ green (⚠️ rare unhide flake, deferred-items.md) | ⬜ pending |
| SAFE-05 | Forced-off capability → fallback matcher; launch with flag | unit + integration | `swift test --filter "CapabilitiesTests\|FallbackMatcherTests\|FallbackIntegrationTests"` | ✅ | ✅ green | ⬜ pending |
| P1 obligation | Undo-revived windows re-queried, reported via `World.apply` | unit | `swift test --filter LifecycleSyncTests` | ✅ | ✅ green |
| guardrail | PaneEngine/PaneModel stay AppKit-free | unit | `swift test --filter NoAppKitTests` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `Package.swift`: targets `PanePrivate`, `PaneMac` (+ library product), `PaneApp`, `pane-dump`, `PaneFixtureApp`, `PaneTestSupport`; test targets `PaneEngineTests`, `PaneMacIntegrationTests`
- [x] `Sources/PaneTestSupport/FakeWindowSystem.swift` — shared fixture (actor)
- [x] `Sources/PaneFixtureApp/main.swift` — windows with tabs, sheet, utility panel, borderless floating, `fullScreenNone`, `minSize`; command channel to open/close windows
- [x] `Tests/PaneEngineTests/Fixtures/AXDumps/` — corpus directory + JSON schema doc
- [x] `xcode/project.yml`, `scripts/generate.sh`, `.gitignore` entries
- [x] XcodeGen installed (checkpoint) and signed Debug build + designated requirement verified

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| First-launch grant, polling advance, Reset button | WIN-01 | Needs real TCC prompt and System Settings | `open -n` the Debug app, grant, confirm "Pane is ready"; repeat with a stale grant (RESEARCH A5 recipe) |
| Real `kill -STOP` on a user app | WIN-03 | Real third-party app | Freeze an app, nudge another app's window; it moves in < 1 s |
| Lock/unlock and sleep/wake with 10 tracked windows | WIN-09 | Needs real session events | Lock, unlock, sleep, wake; Tracked Windows keeps all 10 rows |
| Multi-display arrangements (above/left) | WIN-04 | Needs physical displays | Nudge a window on each display; frame lands where expected |
| Finder/Terminal/Safari native tabs | WIN-06 | Real apps | Open 3 tabs; Tracked Windows shows one row with "3 tabs" |
| Setup-window long app name; menu-bar glyph in light/dark | UI-SPEC backstops | Visual | Inspect during UAT |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-10-25 (all 11 rows have automated suites; full `swift test` green incl. live integration in a trusted terminal)

## Validation Audit 2026-10-25

| Metric | Count |
|---|---|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
