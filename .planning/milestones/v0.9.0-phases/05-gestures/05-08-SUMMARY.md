---
phase: 05-gestures
plan: 08
subsystem: input
status: complete
tags: [gestures, uat, phase-gate, multitouch, crash-fix, crash-canary]
requires:
  - "05-05: Reduce Motion follow and crossfade snap"
  - "05-06: GestureCopy, Debug G1-G3, VoiceOver announcements"
  - "05-07: multitouch pinch source (tap+multitouch), MultitouchCanary, Debug G4"
provides:
  - "05-UAT.md: VM suite results, VM UAT run (synthetic events), and the 24-item phase UAT with host results; status complete, no open gaps"
  - "G-01 fix: MultitouchSupport FrameSink (os_unfair_lock buffer + DispatchSourceUserDataAdd on main) replaces the lock-held frame closure"
  - "Crash canary rule: armed for the whole multitouch run, cleared only at a clean stop"
affects: [06]
tech-stack:
  added: []
  patterns:
    - "C callback thread to main: append to a lock-protected buffer and signal a DispatchSourceUserDataAdd; never store a closure behind generic lock state that a read writes back"
key-files:
  created:
    - .planning/phases/05-gestures/05-UAT.md
  modified:
    - Sources/TransomPrivate/MultitouchSupport.swift
    - Sources/TransomPrivate/Capabilities.swift
    - Sources/TransomMac/Input/MultitouchDevices.swift
    - Tests/TransomMacTests/MultitouchDevicesTests.swift
    - .planning/phases/05-gestures/05-UI-SPEC.md
    - .planning/phases/05-gestures/05-08-PLAN.md
key-decisions:
  - "G-01: multitouch frames go through a lock-protected buffer drained on main by a DispatchSourceUserDataAdd; the handler is a plain @MainActor stored property, with no per-frame DispatchQueue.main.async"
  - "The multitouch crash canary stays armed for the whole run and clears only at a clean stop (zoom off, quit); the 2 s healthy-frames clear is gone. Any crash while zoom is on disables multitouch for that OS build + app version until the privateCanary.Multitouch key is deleted"
  - "Phase UAT closed with the core items run on hardware; items 7, 8, 10, 11, 14, 20, 21 and 24 skipped by user decision, each with its partial automated cover recorded"
  - "No GestureTuning change: the user found pinch-out travel and flick commit fine (item 23)"
requirements-completed: [GEST-01, GEST-02, GEST-03, GEST-04]
metrics:
  duration: "~6 h wall clock including the user's host UAT and the G-01 fix (agent time not measured separately)"
  completed: 2026-10-30
commits: 4
plan_head_before: 8b647923b23d5f69238b54df7c4ed2d268c76d4a
plan_head_after: f57cf23acd372b66c94d66209f77c159058a2e14
actuals:
  tokens: 10500
  tasks: 2
  commits: 4
---

# Phase 5 Plan 08: Phase gate and gesture UAT Summary

Every automated suite was green on the finished phase. The user ran the core gesture items on the MacBook Air's built-in trackpad, and they all passed: ⌥-pinch in and out, ⌥-pan, plain pinch and pan on wallpaper, multitouch pinch with "Zoom in or out" off, and sleep/wake. UAT found one crash in the multitouch frame path (G-01). It was fixed and then verified on the host.

## Automated results

| Run | Result |
|---|---|
| `scripts/check-no-appkit.sh` | OK (45 files) |
| `import ScreenCaptureKit` | only `Sources/TransomMac/Zoom/SnapshotCapture.swift` |
| Host `swift test` (gate) | 1,263 passed, 0 failed (FreezeTestTests flake did not occur) |
| Host `swift test` (after G-01 fix) | 1,264 passed |
| VM `GestureTapIntegrationTests` | 12 passed |
| VM `GestureFollowIntegrationTests` | 13 passed |
| VM `InputTapIntegrationTests` | 3 passed |
| VM `ZoomSettleIntegrationTests` | 2 passed |
| VM `MultitouchIntegrationTests` | 1 passed (no device in the guest) |

The VM was Tart `pane-test` on macOS 15.7.7, with the display woken and caffeinate held, using fixtures only.

## UAT outcome (05-UAT.md, status complete)

- **Host, built-in trackpad, macOS 27.2 (user):** items 1, 2, 3, 6, 17, 18 and 23 passed.
  - 17: `TrackpadPinch` read `0` with the setting off, which resolves the 05-07 risk.
  - 6: on the first try Safari didn't visibly zoom, but Transom took nothing. A retry did zoom. Recorded as a pass.
- **VM, synthetic events (agent):** items 4, 5, 9, 12, 13, 16, 19 and 22 passed. The host also confirmed "Multitouch: available, 1 trackpad" and the "Gestures taken" count.
- **Skipped by user decision ("Done. I think we're good."):** 7, 8, 10, 11, 14, 20, 21 and 24. Each one lists its partial automated cover. Item 7's E-05 ⌃-scroll Accessibility zoom is recorded explicitly as **not confirmed on hardware**.
- **N/A:** item 15 (no external trackpad, 05-SPIKE C5).
- **Totals:** 24 items. 15 passed, 8 skipped, 1 N/A, 0 open issues.

GEST-01 (UAT 1, 2, 5, 17), GEST-02 (3, 4) and GEST-03 (6) are confirmed on hardware or in the VM. For GEST-04, leak-freedom in Safari (1-3, 6, 17), zoom-off pass-through (13, VM) and sleep/wake (18) are confirmed. Chords and mice (7, 8) and resting fingers (10) have automated cover only.

## Deviations from Plan

### Plan and UI-SPEC edits (C5)

**1. [Rule 3 - Blocking] The Magic Trackpad items were removed from UI-SPEC Surface 7 and 05-08-PLAN.md.**
- **Found during:** Task 1.
- **Issue:** The plan's truths and Surface 7 assumed a Magic Trackpad. 05-SPIKE C5 established that the host has only the built-in trackpad.
- **Fix:** "(both)" now means the built-in trackpad. Item 15 (reconnect) and spike item 6 are N/A. Spaces checks use four fingers or ⌃←/⌃→. Item 8 is N/A without a mouse. The plan's must_haves, objective and Task 2 wording were updated to match.
- **Commit:** `9043271`.

**2. [Rule 2 - Coverage] Eight checks were added to 05-UAT.md beyond the 16 Surface 7 items.** Items 17-24 cover what 05-02, 05-04, 05-05, 05-06 and 05-07 left to UAT: multitouch with the setting off, sleep/wake with it off, the tap-only fallback, Reduce Motion takeover, the Desktop tile, Debug G1-G4, feel, and Spaces. Commit `9043271`.

**3. [Rule 3 - Coverage] A VM UAT run with synthetic events, which the plan did not have.** Items 4, 5, 9, 12, 13, 16, 19 and 22 were run in the guest before the host session, to shorten what the user had to do. Commit `ce2cb13`.

### Auto-fixed Issues

**4. [Rule 1 - Bug] G-01: Debug build crashed in the multitouch frame path while zoom was on.**
- **Found during:** Task 2 (host UAT). Crashes at 33 s and about 3 min after launch: SIGBUS in a stack guard page on MultitouchSupport's callback thread.
- **Issue:** The frame handler was stored in `OSAllocatedUnfairLock<closure?>`. At -Onone, each `withLock { $0 }` read wrote the closure back through unspecialized generic inout state. That added one reabstraction-thunk pair per frame, so after a few thousand frames, calling the handler overflowed the framework's 512 KB thread. The spike streamed about 1,400 frames, below the limit, and the VM has no device.
- **Fix:** A `FrameSink` (an `os_unfair_lock` buffer plus a `DispatchSourceUserDataAdd` on main) now delivers frames in order to a plain `@MainActor` handler. There is no longer a per-frame `DispatchQueue.main.async`.
- **Behaviour change (canary):** the multitouch crash canary is now armed for the whole multitouch run and cleared only at a clean stop (zoom off, quit). Before, it cleared after 2 s of healthy frames, so this crash never tripped it. Now any crash while zoom is on disables multitouch for that OS build and app version, until the `privateCanary.Multitouch` key is deleted. The next launch reads "Multitouch: off after a crash last launch".
- **Tests:** `MultitouchDevicesTests.theShimFramePathSurvivesThousandsOfFramesOnASmallStack` sends 3,000 frames from a 64 KB thread; the old code SIGBUSes on it. `framesKeepTheCanaryArmedUntilACleanStop` covers the new rule.
- **Host re-check:** no crash across about 45 minutes with zoom on and multitouch running.
- **Files modified:** `Sources/TransomPrivate/MultitouchSupport.swift`, `Sources/TransomPrivate/Capabilities.swift`, `Sources/TransomMac/Input/MultitouchDevices.swift`, `Tests/TransomMacTests/MultitouchDevicesTests.swift`.
- **Commits:** `7357a32` (fix), `f57cf23` (gap doc).

After the earlier crashes, Transom correctly started with "Arranging paused after Transom quit unexpectedly" until the user chose Resume Arranging. That is the expected behaviour.

## Deferred / not verified on hardware

These are skipped items with automated cover only, recorded in 05-UAT.md:
- 7: ⌃/⌘ chords, and E-05 Accessibility modifier-scroll zoom.
- 8: mouse wheel with ⌥. The trackpad sender filter has never been exercised with a real mouse.
- 10: resting fingers mid-pan.
- 11: Reduce Motion follow.
- 14: sleep/wake with the setting on.
- 20: Reduce Motion mid-crossfade opacity pop.
- 21: the Desktop-tile wallpaper case.
- 24: Spaces with Transom running. The spike covered this with the CLI.

## Known Stubs

None. No code stubs were added; the plan changed only planning files, apart from the G-01 fix.

## Self-Check: PASSED

- FOUND: `.planning/phases/05-gestures/05-UAT.md` (status complete, 24 results, 0 pending)
- FOUND commits: `9043271`, `ce2cb13`, `7357a32`, `f57cf23` (all ancestors of HEAD)
