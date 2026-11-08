---
phase: "7"
slug: "tab-groups"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: true
created: "2026-11-01"
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (swift test) + Tart VM live suites |
| **Config file** | Package.swift |
| **Quick run command** | `swift test --filter TabGroup` (must report ≥1 test run) |
| **Full suite command** | `swift test` on host; VM: `scripts/vm-live-test.sh TabGroupIntegrationTests` |
| **Estimated runtime** | ~120 seconds (host full suite) |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter <touched suite>`
- **After every plan wave:** Run `swift test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | TABS-01, TABS-05 | T-07-01, T-07-02 | Hidden members never get a window rect; one frame per group | unit + VM | `swift test --filter 'TabGroupModelTests\|ArrangerTabsTests\|ResolveTests\|PlannerTests\|ViewPlannerTests\|ArrangerDragTests\|FakeWindowSystemTests'` + `scripts/vm-live-test.sh TabGroupIntegrationTests` | ✅ | ✅ green |
| 07-01-02 | 01 | 1 | TABS-01 | — | N/A | unit | `swift test --filter 'ArrangerTabsTests\|ArrangerDragTests\|DragSessionTests\|ArrangerCollapseTests'` | ✅ | ✅ green |
| 07-01-03 | 01 | 1 | TABS-01 | — | N/A | unit | `swift test` (TabCopyTests, PreviewStyleTests) + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-02-01 | 02 | 2 | TABS-02, TABS-01 | T-07-03, T-07-05, T-07-08 | Strip never activates Transom; reveal before park; strip presses never start drags | unit + VM | `swift test --filter ArrangerTabsTests` + `scripts/vm-live-test.sh TabGroupIntegrationTests` | ✅ | ✅ green |
| 07-02-02 | 02 | 2 | TABS-02 | T-07-06 | Focus echoes and post-close focus never flip a group | unit | `swift test --filter 'ArrangerTabsTests\|ArrangerFocusTests\|ArrangerCameraTests'` | ✅ | ✅ green |
| 07-02-03 | 02 | 2 | TABS-02 | T-07-04 | Titles never logged | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-03-01 | 03 | 3 | TABS-01 | T-07-09 | Backstop poll reads CG bounds only | unit | `swift test --filter ArrangerTabsTests` + `swift build` | ✅ | ✅ green |
| 07-03-02 | 03 | 3 | TABS-02 | — | N/A | unit | `swift test --filter 'TabStripLayoutTests\|TabCopyTests'` | ✅ | ✅ green |
| 07-03-03 | 03 | 3 | TABS-02 | T-07-07 | Strips only on their Space; stranded panels replaced | unit + VM | `swift test` + `scripts/vm-live-test.sh TabStripSpaceIntegrationTests` | ✅ | ✅ green |
| 07-04-01 | 04 | 4 | TABS-05, TABS-01 | T-07-10, T-07-11 | Hostile layout.json groups rejected; old files decode | unit | `swift test --filter 'TabGroupModelTests\|DesktopLayerTests\|PersistenceTests\|InvariantTests\|ArrangerTabsTests\|PlannerTests\|LayoutStoreTests'` | ✅ | ✅ green |
| 07-04-02 | 04 | 4 | TABS-05, TABS-02 | T-07-12 | Hidden member echoes never move a group | unit | `swift test --filter 'ArrangerTabsTests\|ArrangerDesktopTests\|ArrangerFocusTests'` | ✅ | ✅ green |
| 07-04-03 | 04 | 4 | TABS-05 | — | N/A | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-05-01 | 05 | 5 | TABS-03 | T-07-13, T-07-14 | Normal close press only; excluded apps never receive close/minimise | unit + VM | `swift test --filter 'ArrangerTabsTests\|FakeWindowSystemTests\|ExclusionScenarioTests'` + `scripts/vm-live-test.sh TabGroupIntegrationTests` | ✅ | ✅ green |
| 07-05-02 | 05 | 5 | TABS-03, TABS-02 | T-07-15 | Minimize Group survives same-app focus shift | unit + VM | `swift test --filter ArrangerTabsTests` + `scripts/vm-live-test.sh TabGroupIntegrationTests` | ✅ | ✅ green |
| 07-05-03 | 05 | 5 | TABS-03 | — | N/A | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-06-01 | 06 | 6 | TABS-03 | T-07-16 | Whole-leaf moves validated, all-or-nothing | unit | `swift test --filter 'TabGroupModelTests\|LayoutEditTests\|InvariantTests\|ArrangerTabsTests\|TabCopyTests\|TabStripLayoutTests'` | ✅ | ✅ green |
| 07-06-02 | 06 | 6 | TABS-03, TABS-05 | T-07-16 | No path tears out a member | unit | `swift test --filter 'TabGroupModelTests\|ArrangerTabsTests\|ArrangerCommandTests\|ArrangerGreenButtonTests\|ArrangerDesktopTests\|ArrangerSpacesTests'` | ✅ | ✅ green |
| 07-06-03 | 06 | 6 | TABS-03 | T-07-16 | Whole-group drag keeps the Core Value | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-07-01 | 07 | 7 | TABS-04 | T-07-18 | Strip presses reach the engine as tab presses only | unit | `swift test --filter 'ArrangerTabsTests\|ArrangerDragTests\|DragSessionTests'` + `swift build` | ✅ | ✅ green |
| 07-07-02 | 07 | 7 | TABS-04 | — | N/A | unit | `swift test --filter 'ArrangerTabsTests\|TabCopyTests'` | ✅ | ✅ green |
| 07-07-03 | 07 | 7 | TABS-04 | T-07-17 | Esc hotkeys only during a tear-off; never ⌥⌘Esc | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-08-01 | 08 | 8 | TABS-06, TABS-04 | — | N/A | unit | `swift test --filter 'ArrangerTabsTests\|TabCopyTests'` + `swift build` | ✅ | ✅ green |
| 07-08-02 | 08 | 8 | TABS-06 | T-07-19 | Close Tab reveals first, stops at a prompt | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-09-01 | 09 | 9 | TABS-02, TABS-04 | T-07-21 | Hotkey names pinned | unit | `swift test --filter 'ArrangerTabsTests\|HotkeyTableTests\|CommandTests\|ArrangerCommandTests'` | ✅ | ✅ green |
| 07-09-02 | 09 | 9 | TABS-02, TABS-06 | T-07-20 | URL whitelist, rate limit, no beep | unit | `swift test --filter 'TransomURLTests\|ShortcutsModelTests\|CommandMenuTests\|MenuCopyTests'` | ✅ | ✅ green |
| 07-09-03 | 09 | 9 | TABS-02 | — | N/A | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-10-01 | 10 | 10 | TABS-02, TABS-05 | T-07-22 | Quit leaves no member off screen | unit + VM | `swift test --filter 'ArrangerTabsTests\|RecoveryTests'` + `scripts/vm-live-test.sh TabGroupIntegrationTests` | ✅ | ✅ green |
| 07-10-02 | 10 | 10 | TABS-02 | T-07-22, T-07-23 | Restore All dissolves before rescue; logged | unit | `swift test --filter 'ArrangerTabsTests\|ArrangerRestoreTests\|ArrangerCommandTests'` | ✅ | ✅ green |
| 07-10-03 | 10 | 10 | TABS-01, TABS-05 | — | N/A | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-11-01 | 11 | 11 | TABS-01, TABS-05 | T-07-24 | Hidden members never drawn or captured | unit | `swift test --filter 'ArrangerTabsTests\|ArrangerCameraTests\|TileLayerTests\|StageFollowTests'` + `swift build` | ✅ | ✅ green |
| 07-11-02 | 11 | 11 | TABS-01 | — | N/A | unit | `swift test --filter 'ArrangerTabsTests\|TabCopyTests\|OverviewCopyTests\|OverviewLayoutTests'` | ✅ | ✅ green |
| 07-11-03 | 11 | 11 | TABS-01 | T-07-24 | Captures stay in memory | unit | `swift test` + `scripts/check-no-appkit.sh` | ✅ | ✅ green |
| 07-12-01 | 12 | 12 | TABS-01..06 | T-07-25 | Live suites only in the VM | full + VM | `swift test` + each VM suite via `scripts/vm-live-test.sh` + `scripts/build-debug.sh` | ✅ | ✅ green |
| 07-12-02 | 12 | 12 | TABS-01..06 | — | N/A | doc check | 07-UAT.md phrase check loop | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Phase gate (07-12, 2026-11-02, HEAD `8a8973a`): `scripts/check-no-appkit.sh` OK (55 files); host `swift test` 219 + 390 + 93 + 952 = 1,654 tests, 0 failures (`.build/0712-full.log`); VM (`pane-test`, macOS 15.7.7), one suite per run: TabGroupIntegrationTests 5, TabStripSpaceIntegrationTests 1, QuitRestoreIntegrationTests 3, FocusParkIntegrationTests 2, TabsIntegrationTests 1, all passed (`.build/0712-vm-*.log`); `scripts/build-debug.sh` OK.

---

## Wave 0 Requirements

- [x] `Tests/TransomModelTests/TabGroupModelTests.swift` — band in `resolve`, floating group edits/validation/decode, leaf moves (07-01, 07-04, 07-06)
- [x] `Tests/TransomEngineTests/ArrangerTabsTests.swift` — dwell, drops, reveal/park, D-08, close/minimise, whole-group moves, tear-off, move out, commands, safety (07-01 onward)
- [x] `Tests/TransomMacTests/TabCopyTests.swift` — copy, plurals, Debug line (07-01 onward)
- [x] `Tests/TransomMacTests/TabStripLayoutTests.swift` — strip geometry and overflow (07-03)
- [x] `Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift` — five VM tests (07-01, 07-02, 07-05 ×2, 07-10)
- [x] `Tests/TransomMacIntegrationTests/TabStripSpaceIntegrationTests.swift` — strip Space behaviour, VM only (07-03)
- [x] `FakeWindowSystem` support for `.park(size:)`, `.close`, `.minimize` (07-01, 07-05)
- [x] Existing `ResolveTests` expectations updated for tab leaves (07-01)

Each suite is created by the first task that names it in its `<files>`; every `swift test --filter` gate requires a non-zero "Test run with N tests … passed" line, so a filter matching nothing fails.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Strip follows a quick drag with no visible lag | TABS-01 | Visual timing on real hardware | 07-UAT.md hardware backstop |
| No wallpaper flash on tab switch | TABS-02 | Visual, frame-level | 07-UAT.md hardware backstop |
| Close Group with an unsaved TextEdit document | TABS-03 | Real app save sheet | 07-UAT.md host checklist item 5 |
| Native Safari tab group as one member | TABS-05 | Real Safari | 07-UAT.md host checklist item 4 |
| VoiceOver reads the strip as a tab group | TABS-02, TABS-06 | Screen reader output | 07-UAT.md hardware backstop |
| Tear-off dock/float/Esc, ⌘Tab to hidden member, strip ordering, inactive click, context menu tracking, kill -9 relaunch, Restore All + Undo, lock/unlock | TABS-02, TABS-04, TABS-06 | Needs pointer gestures or session events the suites do not post | 07-UAT.md VM checks (Tart VM only) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** {pending / approved YYYY-MM-DD}
