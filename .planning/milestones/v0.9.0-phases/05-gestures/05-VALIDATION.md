---
phase: "05"
slug: "gestures"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-28"
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`). Live suites are gated by `IntegrationEnv.trusted` (`TRANSOM_LIVE=1` plus Accessibility) and run only in the Tart VM |
| **Config file** | `Package.swift` (TransomEngineTests excludes `Fixtures`; gesture traces load through `#filePath` from `Tests/TransomEngineTests/Fixtures/Gestures/`) |
| **Quick run command** | `rm -f .build/X.log && swift test --filter <Suite> > .build/X.log 2>&1; ! grep -q "✘" .build/X.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/X.log` |
| **Full suite command** | `swift test` (host, headless, includes `scripts/check-no-appkit.sh` through NoAppKitTests); VM: `scripts/vm-live-test.sh "GestureTapIntegrationTests|GestureFollowIntegrationTests|InputTapIntegrationTests|ZoomSettleIntegrationTests"` |
| **Estimated runtime** | quick filter ~20 s; full host suite ~120 s; VM suites ~6 min |

---

## Sampling Rate

- **After every task commit:** run the touched suite's quick command; the executed count must be non-zero.
- **After every plan wave:** run `swift test` (host). Waves that touch the tap or follow also run the VM suites.
- **Before `/gsd-verify-work`:** full suite green, VM suites green (guest display woken), 05-SPIKE.md decision recorded, 05-UAT.md complete.
- **Max feedback latency:** 120 seconds for host checks. VM runs are wave-level.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | GEST-01, GEST-04 | T-05-01 | A ⌥ magnify is consumed whole; a plain scroll over a window passes | VM synth (spike) | `SPIKE_PRODUCT=transom-gesture-spike scripts/vm-spike.sh synth --scenario all --seconds 60` | ❌ W0 (spike target) | ⬜ pending |
| 05-01-02 | 01 | 1 | GEST-01, GEST-02, GEST-03, GEST-04 | T-05-01, T-05-03 | Stuck latch releases; ⌃/⌘, discrete wheel and non-trackpad pass; mask has no bit 30; MT callback returns 0 | unit + VM synth | `swift test --filter GestureTapRulesTests` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 1 | GEST-01..04 | T-05-05 | Host half run by the user only | manual (checkpoint) | — (user checklist, 05-SPIKE.md) | — | ⬜ pending |
| 05-02-01 | 02 | 2 | GEST-01 | T-05-06 | Clamped magnification; preview changes no engine state | unit (traces) | `swift test --filter 'GestureRecognizerTests\|ArrangerCameraTests'` | ❌ W0 / ✅ ArrangerCameraTests | ⬜ pending |
| 05-02-02 | 02 | 2 | GEST-02 | T-05-07 | Every gesture ends (timeouts) | unit (traces) | `swift test --filter GestureRecognizerTests` | ❌ W0 | ⬜ pending |
| 05-03-01 | 03 | 2 | GEST-04 | T-05-08, T-05-10 | Product tap consumes ⌥ pinch; zoom off means no tap | VM integration | `scripts/vm-live-test.sh GestureTapIntegrationTests` | ❌ W0 | ⬜ pending |
| 05-03-02 | 03 | 2 | GEST-03, GEST-04 | T-05-08, T-05-09 | Momentum tail, mid-sequence ⌥, chords, stuck latch, wallpaper, re-enable, wake re-publish | unit + VM integration | `swift test --filter ZoomOffTests` and `scripts/vm-live-test.sh GestureTapIntegrationTests` | ✅ ZoomOffTests / ❌ W0 | ⬜ pending |
| 05-04-01 | 04 | 3 | GEST-01 | T-05-14 | Commit only through zoomTo/settle | VM integration | `scripts/vm-live-test.sh GestureFollowIntegrationTests` | ❌ W0 | ⬜ pending |
| 05-04-02 | 04 | 3 | GEST-02, GEST-03 | T-05-13 | Spring back writes nothing | unit + VM integration | `swift test --filter StageFollowTests` and `scripts/vm-live-test.sh GestureFollowIntegrationTests` | ❌ W0 | ⬜ pending |
| 05-05-01 | 05 | 4 | GEST-02 | T-05-17 | Refusals never beep; logged | VM integration | `scripts/vm-live-test.sh GestureFollowIntegrationTests` | ❌ W0 (from 05-04) | ⬜ pending |
| 05-05-02 | 05 | 4 | GEST-01 | T-05-16 | No stranded pending move after a takeover | VM integration | `scripts/vm-live-test.sh GestureFollowIntegrationTests` | ❌ W0 (from 05-04) | ⬜ pending |
| 05-06-01 | 06 | 4 | GEST-04 | T-05-18 | Debug lines show counts only | unit | `swift test --filter GestureCopyTests` | ❌ W0 | ⬜ pending |
| 05-06-02 | 06 | 4 | GEST-04 | T-05-19 | Unknown pinch preference is never "off" | unit (conditional) | `swift test --filter GestureCopyTests` | ❌ W0 | ⬜ pending |
| 05-07-01 | 07 | 5 | GEST-04 | T-05-20 | Canary, forced off, never linked (only if E-01 = tap+multitouch) | unit + VM spike | `swift test --filter CapabilitiesTests` and `SPIKE_PRODUCT=transom-gesture-spike scripts/vm-spike.sh mt-devices --seconds 10` | ✅ CapabilitiesTests | ⬜ pending |
| 05-07-02 | 07 | 5 | GEST-01, GEST-04 | T-05-21, T-05-22 | MT never consumes; no device over-release (conditional) | unit | `swift test --filter GestureRecognizerTests` | ❌ W0 (from 05-02) | ⬜ pending |
| 05-07-03 | 07 | 5 | GEST-04 | — | Zoom off opens no device (conditional) | unit | `swift test --filter 'GestureCopyTests\|ZoomOffTests'` | ✅ | ⬜ pending |
| 05-08-01 | 08 | 6 | GEST-01..04 | T-05-25 | No regression; VM suites green | full suite + VM | `swift test` and `scripts/vm-live-test.sh "GestureTapIntegrationTests\|GestureFollowIntegrationTests\|InputTapIntegrationTests\|ZoomSettleIntegrationTests"` | ✅ | ⬜ pending |
| 05-08-02 | 08 | 6 | GEST-01..04 | T-05-24 | User UAT on real trackpads | manual (checkpoint) | — (05-UAT.md, 16 items) | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Sources/transom-gesture-spike/main.swift` + Package.swift target and `SPIKE_PRODUCT` in `scripts/vm-spike.sh` (05-01 T1)
- [ ] `Tests/TransomMacTests/GestureTapRulesTests.swift` (05-01 T2)
- [ ] `Tests/TransomEngineTests/GestureRecognizerTests.swift` + `Tests/TransomEngineTests/Fixtures/Gestures/*.jsonl` (05-02)
- [ ] `Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift` with the synthetic poster and the downstream listen-only tail tap (05-03)
- [ ] `scripts/vm-live-test.sh` guest display wake + `caffeinate -dimsu` (05-03 T1)
- [ ] `Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift`, `Tests/TransomMacTests/StageFollowTests.swift` (05-04)
- [ ] `Tests/TransomMacTests/GestureCopyTests.swift` (05-06)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Tap visibility and consume over Safari, Preview, Finder, wallpaper and full screen; multitouch layout, int32 return, rescan, latency | GEST-01..04 | The VM has no trackpad, and agents never open taps or devices on the host (D-08) | 05-SPIKE.md "Host half": UI-SPEC Surface 7 spike gate checklist, items 1-7, both trackpads |
| Real-trackpad feel, no leak in Safari/Preview, chords, mice, Reduce Motion, VoiceOver, sleep/wake, Magic Trackpad reconnect, Debug lines | GEST-01..04 | Same | 05-UAT.md: UI-SPEC Surface 7 phase UAT checklist, 16 items, both trackpads |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
