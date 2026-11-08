---
phase: "8"
slug: "saved-views-urls-persistence"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-11-03"
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source: 08-RESEARCH.md "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`), Swift 6.4 toolchain |
| **Config file** | none (SwiftPM test targets in Package.swift) |
| **Quick run command** | `swift test --filter "<suites the task touches>"` (must show a non-zero executed test count) |
| **Full suite command** | `swift test` (live suites skip on the host) + `scripts/check-no-appkit.sh` |
| **Live (VM only)** | `scripts/vm-live-test.sh <SuiteName>` (passes only with "Test run with N tests … passed") |
| **Estimated runtime** | ~120 seconds full host suite |

---

## Sampling Rate

- **After every task commit:** quick run for the touched suites
- **After every plan wave:** `swift test` + `scripts/check-no-appkit.sh`
- **Before `/gsd-verify-work`:** full host suite green, then VM `RematchIntegrationTests` and the CLI VM script
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

Filled by the planner per task (each task's `<automated>` verify). Requirement → suite map:

| Requirement | Behavior | Test Type | Automated Command | File Exists | Status |
|-------------|----------|-----------|-------------------|-------------|--------|
| VIEW-01 | Save / go / resolve LCA / all gone → home / refusals | unit | `swift test --filter TransomEngineTests.ArrangerViewsTests` | ❌ W0 | ⬜ pending |
| VIEW-01 | Hotkey version rule, 18 names, in zoomNames | unit | `swift test --filter TransomMacTests.HotkeysTests` | ❌ W0 | ⬜ pending |
| VIEW-02 | Views survive split/move; remap on rekey and placeholder fill | unit | `swift test --filter TransomEngineTests.ArrangerViewsTests` | ❌ W0 | ⬜ pending |
| VIEW-02 | layout.json schema 3 round trip, schema 2 loads, newer untouched, titles written 0600 | unit | `swift test --filter "TransomMacTests.LayoutStoreTests\|TransomEngineTests.SpaceRekeyTests"` | ✅ extend | ⬜ pending |
| VIEW-03 | `view/N` / `save-view/N` parse; rejected forms nil; per-slot rate limit | unit | `swift test --filter TransomEngineTests.TransomURLTests` | ✅ extend | ⬜ pending |
| VIEW-03 | Help table covers every command once | unit | `swift test --filter TransomEngineTests.CLICopyTests` | ❌ W0 | ⬜ pending |
| VIEW-04 | HintMatcher scoring table | unit | `swift test --filter TransomEngineTests.HintMatcherTests` | ❌ W0 | ⬜ pending |
| VIEW-04 | Restore + placeholders (10 s / 5 min / 30 s, adopt, ⌘W closes, boot-session guard) | unit | `swift test --filter "TransomEngineTests.ArrangerRestoreTests\|TransomEngineTests.ArrangerPlaceholderTests"` | ❌ W0 / ✅ extend | ⬜ pending |
| VIEW-04 | World.adopt / refreshingTitles | unit | `swift test --filter TransomModelTests.WorldAdoptTests` | ❌ W0 | ⬜ pending |
| VIEW-04 | Fixture quit/relaunch and Transom relaunch re-match | live (VM) | `scripts/vm-live-test.sh RematchIntegrationTests` | ❌ W0 | ⬜ pending |
| VIEW-05 | CLI parsing, stderr text, exit codes 0/1/2/64 | unit | `swift test --filter "TransomEngineTests.CLICommandLineTests\|TransomEngineTests.CLIProtocolTests"` | ❌ W0 | ⬜ pending |
| VIEW-05 | IPC round trip on a test port | integration (host-safe IPC only) | `swift test --filter TransomMacTests.CLIListenerTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Tests/TransomEngineTests/HintMatcherTests.swift`
- [ ] `Tests/TransomEngineTests/ArrangerViewsTests.swift`
- [ ] `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
- [ ] `Tests/TransomEngineTests/CLICommandLineTests.swift`, `CLIProtocolTests.swift`, `CLICopyTests.swift`
- [ ] `Tests/TransomModelTests/WorldAdoptTests.swift`
- [ ] `Tests/TransomMacTests/CLIListenerTests.swift`
- [ ] `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift` (VM only)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Installed CLI exit codes (incl. Transom quit → 2) | VIEW-05 | Needs the built app bundle and a GUI session (`launchctl asuser` in VM) | VM UAT script: `transom view 3; echo $?` for success, unknown, bad slot, rate limit, not running |
| Real reboot re-match | VIEW-04 | Reboot not automatable in tests | Host check after relaunch/reboot |
| Placeholder click-through, VoiceOver joined line, ⌥ chords | VIEW-01/04 | Visual / assistive tech | Host checklist |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
