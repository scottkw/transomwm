---
phase: "06"
slug: "overview-spaces-displays"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: true
created: "2026-10-31"
---

# Phase 06 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`). Live suites are gated by `IntegrationEnv.trusted` (`TRANSOM_LIVE=1` plus Accessibility) and run only in the Tart VM; multi-display hot-plug is covered by the UI-SPEC user hardware checklist |
| **Config file** | `Package.swift` (new `transom-spaces-spike` VM product per 06-RESEARCH Wave 0) |
| **Quick run command** | `rm -f .build/X.log && swift test --filter <Suite> > .build/X.log 2>&1; ! grep -q "✘" .build/X.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/X.log` |
| **Full suite command** | `swift test` (host, headless, includes `scripts/check-no-appkit.sh`); VM: `scripts/vm-live-test.sh <Phase 6 integration suites>` one suite per invocation |
| **Estimated runtime** | quick filter ~20 s; full host suite ~120 s; VM suites ~6 min each |

---

## Sampling Rate

- **After every task commit:** Run the quick run command
- **After every plan wave:** Run the full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Test Type | Automated Command | Status |
|---------|------|------|-------------|------------|-----------|-------------------|--------|
| 06-01-01 | 01 | 1 | OVER-01/04 | T-06-03, T-06-06 | unit + VM spike | `swift test --filter SpacesSnapshotTests` (count line, no ✘); `transom-spaces-spike spaces-dump` (VM) | ✅ green |
| 06-01-02 | 01 | 1 | OVER-02/03 | T-06-01, T-06-02 | unit + VM spike | `swift test --filter CapabilitiesTests` (count line, no ✘); spike subcommands incl. reboot diff (VM) | ✅ green |
| 06-01-03 | 01 | 1 | OVER-04 | — | decision | manual: schema decision recorded in 06-SPIKE.md | ✅ green |
| 06-02-01 | 02 | 2 | OVER-01/04 | T-06-04 | unit | `swift test --filter 'CloseRuleTests\|CloseScenarioTests\|TabScenarioTests'` (count line, no ✘) | ✅ green |
| 06-02-02 | 02 | 2 | OVER-01/04 | T-06-05 | unit | `swift test --filter 'CoVisibilitySpacesTests\|ArrangerSpacesTests\|OverviewCopyTests\|MenuCopyTests'` (count line, no ✘); `scripts/check-no-appkit.sh` | ✅ green |
| 06-03-01 | 03 | 2 | OVER-04/06 | T-06-07 | unit | `swift test --filter 'LayoutStoreTests\|SpaceRekeyTests'` (count line, no ✘) | ✅ green |
| 06-03-02 | 03 | 2 | OVER-04/06 | T-06-07, T-06-09 | unit | `swift test --filter 'SpaceRekeyTests\|ArrangementsTests\|LayoutStoreTests\|PersistenceTests'` (count line, no ✘); `scripts/check-no-appkit.sh` | ✅ green |
| 06-04-01 | 04 | 3 | OVER-05/06 | T-06-11 | unit | `swift test --filter ArrangerDisplaySettleTests` (count line, no ✘) | ✅ green |
| 06-04-02 | 04 | 3 | OVER-04/05/06 | T-06-11, T-06-12 | unit | `swift test --filter 'ArrangerDisplaySettleTests\|ArrangementsTests\|ArrangerSpacesTests\|ArrangerMultiDeskRestoreTests\|ArrangerRestoreTests\|TrackerDisplayTests'` (count line, no ✘); `scripts/check-no-appkit.sh` | ✅ green |
| 06-05-01 | 05 | 4 | OVER-05/06 | T-06-13, T-06-14 | unit | `swift test --filter 'DisplaySettlerTests\|LayoutStoreTests\|SessionGateTests'` (count line, no ✘) | ✅ green |
| 06-05-02 | 05 | 4 | OVER-05/06 | T-06-15 | unit | `swift test --filter 'NoticeCopyTests\|NoticeQueueTests\|OverviewCopyTests'` (count line, no ✘) | ✅ green |
| 06-06-01 | 06 | 5 | OVER-01 | T-06-17, T-06-18 | VM live | `scripts/vm-live-test.sh OverviewIntegrationTests` | ⚠️ flaky (06-12: Esc check failed twice in a row, then passed 3 times unchanged) |
| 06-06-02 | 06 | 5 | OVER-01 | — | unit | `swift test --filter 'OverviewLayoutTests\|OverviewCopyTests'` (count line, no ✘); `scripts/check-no-appkit.sh` | ✅ green |
| 06-06-03 | 06 | 5 | OVER-01 | T-06-16 | unit | `swift test --filter 'TransomURLTests\|HotkeyTableTests\|ShortcutsModelTests\|CommandMenuTests\|MenuCopyTests'` (count line, no ✘) | ✅ green |
| 06-07-01 | 07 | 6 | OVER-01 | T-06-19 | VM live | `scripts/vm-live-test.sh OverviewSpaceSwitchIntegrationTests` | ✅ green |
| 06-07-02 | 07 | 6 | OVER-01 | T-06-19 | unit + VM live | `swift test --filter 'SpaceSwitchPlanTests\|OverviewCopyTests'` (count line, no ✘); `scripts/vm-live-test.sh OverviewSpaceSwitchIntegrationTests` | ✅ green |
| 06-07-03 | 07 | 6 | OVER-01 | T-06-20, T-06-21 | unit | `swift test --filter 'NoScreenCaptureTests\|TileLayerTests\|OverviewLayoutTests'` (count line, no ✘) | ✅ green |
| 06-08-01 | 08 | 7 | OVER-01 | T-06-22 | VM live | `scripts/vm-live-test.sh OverviewKeyboardIntegrationTests` | ✅ green |
| 06-08-02 | 08 | 7 | OVER-01 | — | unit | `swift test --filter OverviewSelectionTests` (count line, no ✘); `scripts/check-no-appkit.sh` | ✅ green |
| 06-08-03 | 08 | 7 | OVER-01 | T-06-23 | unit + UAT | `swift test --filter 'OverviewCopyTests\|TileLayerTests'` (count line, no ✘); visuals in 06-UAT | ✅ green |
| 06-09-01 | 09 | 8 | OVER-01 | — | VM live | `scripts/vm-live-test.sh OverviewIntegrationTests` | ✅ green |
| 06-09-02 | 09 | 8 | OVER-01 | T-06-24 | unit | `swift test --filter 'GestureControllerTests\|OverviewCopyTests\|ZoomOffTests'` (count line, no ✘) | ✅ green |
| 06-09-03 | 09 | 8 | OVER-01 | T-06-25 | unit + UAT | `swift test --filter OverviewCopyTests` (count line, no ✘); Reduce Motion / VoiceOver in 06-UAT | ✅ green |
| 06-10-01 | 10 | 9 | OVER-02/03 | T-06-26 | VM live | `scripts/vm-live-test.sh TakeoverIntegrationTests` | ✅ green |
| 06-10-02 | 10 | 9 | OVER-02/03 | T-06-27, T-06-29 | unit | `swift test --filter 'TakeoverPolicyTests\|TakeoverKeysTests\|CapabilitiesTests'` (count line, no ✘); `scripts/check-no-appkit.sh` | ✅ green |
| 06-10-03 | 10 | 9 | OVER-02/03 | T-06-26, T-06-28 | VM live + UAT | `scripts/vm-live-test.sh TakeoverIntegrationTests`; kill -9 host item in 06-UAT | ✅ green |
| 06-11-01 | 11 | 10 | OVER-02/03 | T-06-31 | unit | `swift test --filter 'TakeoverMenuTests\|OverviewCopyTests'` (count line, no ✘) | ✅ green |
| 06-11-02 | 11 | 10 | OVER-02/03 | T-06-31 | unit | `swift test --filter 'NoticeCopyTests\|NoticeQueueTests\|TakeoverMenuTests\|ConflictControllerTests'` (count line, no ✘) | ✅ green |
| 06-11-03 | 11 | 10 | OVER-02 | T-06-30 | record | swipe kept (06-SPIKE verdict): no SwipeTakeoverTap.swift; nothing to test | ✅ green |
| 06-12-01 | 12 | 11 | OVER-01…06 | T-06-32 | full + VM live | `swift test`; each Phase 6 VM suite plus SpacesIntegrationTests, ZoomSettleIntegrationTests; `scripts/build-debug.sh` | ✅ green |
| 06-12-02 | 12 | 11 | OVER-01…06 | T-06-32 | UAT | 06-UAT.md (user, hardware) | ⬜ pending (user) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `Sources/transom-spaces-spike/main.swift`: VM-only spike product (spaces-dump, hotkeys, takeover crash cycle, Space-switch methods, reboot diff)
- [x] `06-SPIKE.md`: spike results, schema decision and swipe verdict (kept)
- [x] `Tests/TransomEngineTests/SpacesSnapshotTests.swift`: fixture dictionaries for `SpacesSnapshot.parse`
- [x] Framework: Swift Testing plus `scripts/vm-live-test.sh` already in place, nothing to install

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Multi-display unplug / re-plug, arrangement switch, sleep with a display change | OVER-05/06 | the Tart VM can't hot-plug displays | 06-UAT.md hardware checklist 1-5 |
| "Displays have separate Spaces" off | OVER-04/05 | needs a logout on real hardware | 06-UAT.md hardware checklist 6 |
| Overview across two displays | OVER-01 | one display in the VM | 06-UAT.md hardware checklist 7 |
| Mission Control key after quit and kill -9 | OVER-02/03 | agents never change the host's symbolic hotkeys | 06-UAT.md takeover host item |
| Smoothness, ring/capsule/cursor visuals, VoiceOver, Reduce Motion | OVER-01 | human judgement | 06-UAT.md backstops |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** {pending / approved YYYY-MM-DD}
