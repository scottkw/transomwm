---
phase: 05-gestures
plan: 01
subsystem: input
status: complete
tags: [spike, event-tap, multitouch, gestures, vm]
requires: []
provides:
  - "transom-gesture-spike CLI (tap-listen, tap-consume, mt-devices, mt-stream, compare, rescan, synth)"
  - "GestureTapRules.swift: the product's pure latch/consume rules, unit-tested (19 tests)"
  - "GestureEventFields.swift: undocumented CGEvent gesture field constants"
  - "Spike-only MultitouchSupport dlsym shim (Sources/transom-gesture-spike/Multitouch.swift), promoted by 05-07"
  - "scripts/vm-spike.sh parameterised by SPIKE_PRODUCT"
  - "05-SPIKE.md: VM synth 13/13, host gates T1-T6 and M1-M4, E-01 = tap+multitouch, conditions C1-C5"
affects: [05-02, 05-03, 05-04, 05-05, 05-06, 05-07, 05-08]
tech-stack:
  added: [MultitouchSupport (private, dlopen/dlsym, spike target only for now)]
  patterns:
    - "One decision per gesture sequence at its first event, applied through momentum end"
    - "Spike consumes with the exact product rules (GestureTapRules.decide)"
    - "Host live half is user-run from a checklist; agents only read recorded out.jsonl"
key-files:
  created:
    - Sources/TransomMac/Input/GestureTapRules.swift
    - Sources/TransomPrivate/GestureEventFields.swift
    - Sources/transom-gesture-spike/main.swift
    - Sources/transom-gesture-spike/Multitouch.swift
    - Tests/TransomMacTests/GestureTapRulesTests.swift
    - .planning/phases/05-gestures/05-SPIKE.md
  modified:
    - Package.swift
    - scripts/vm-spike.sh
key-decisions:
  - "E-01 (user, verbatim): \"tap+multitouch\". Plan 05-07 ships the MT shim with canary and IOKit rescan; decision-matrix row 2"
  - "C1: while a pinch sequence is latched as consumed, consume every type-29 event in it (all sub-types); sub-type 4 leaked 81 times inside taken pinches on the host"
  - "C2: the recognizer ignores pan sequences with no phase 1/2 or zero delta (128→8, Δ 0,0 noise at pinch starts)"
  - "C3: GestureTapState.trustsTargetPID stays false; field 40 is the frontmost app on real trackpad events (77/77), not the app under the pointer (56/77)"
  - "C4: multitouch is the pinch source when the tap sees no zoom events (always so with 'Zoom in or out' off); the tap still does all consuming"
  - "C5: the host has the built-in trackpad only (no Magic Trackpad); Magic Trackpad and reconnect UAT items are N/A; Spaces switch with 4 fingers or ⌃←→"
  - "E-04 sender filter works: field 87 = the trackpad's multitouch registry ID (0x100000a1f) on every event"
requirements-completed: []
metrics:
  duration: "~23h 43m wall clock (includes the overnight go/no-go checkpoint wait for the user's host runs)"
  started: 2026-10-28T23:54:04Z
  completed: 2026-10-29T23:40:00Z
actuals:
  tokens: 37000
  tasks: 3
  commits: 3
plan_head_before: ac1a5676fa1721e8aa3bbe761eeb02f39dbfa3c3
plan_head_after: f4cef28
---

# Phase 5 Plan 01: Gesture Spike Summary

**A session event tap sees and consumes ⌥ pinch and pan over every surface on the built-in trackpad (callback p99 21 µs), but goes blind to pinch when the user turns off pinch-to-zoom, so the user chose "tap+multitouch": the tap consumes and pans, and MultitouchSupport supplies pinch (plan 05-07 ships).**

## What was built

- `transom-gesture-spike`: a windowless CLI with seven subcommands, each stopping itself after `--seconds` (max 120) or Control-C, printing readings next to gate thresholds (never PASS/FAIL) and writing JSON lines under `.build/spike/`.
- `GestureTapRules` (production, pure): one decision per sequence at its first event, ⌥ takes (not with ⌃/⌘), no-⌥ takes only over wallpaper, discrete wheels and non-trackpad senders always pass, latch released after 0.3 s quiet with fingers up or 2 s with fingers down. 19 unit tests pass.
- `GestureEventFields`: type 29 and fields 110/113/132/55/87/40 with provenance.
- Spike-only MultitouchSupport shim: dlopen/dlsym, Int32 callback returning 0, list devices never released.

## VM half (Tart, synthetic)

`.build/spike/gesture-synth-20261028-192053`: **13 of 13 scenarios match** their downstream counts. Supporting runs: `gesture-synth-20261028-190535`, `-191433`, `-191623`, `-191850`; `gesture-mt-devices-20261028-191906` (12/12 symbols resolve on macOS 15.7.7, 0 devices). VM finding: field 40 is the frontmost app, so `trustsTargetPID` was turned off by default.

## Host half (user-run, macOS 27.2, built-in trackpad only)

| Gate | Verdict | Evidence |
|---|---|---|
| T1 visibility | PASS | 34/34 pinches, 43/43 pans over Safari, Preview, Finder window, wallpaper, full-screen Safari (`gesture-tap-listen-20261029-073133`, `-082731`) |
| T2 consume | PASS with C1 | 25 taken, 7 passed (all no-⌥); user saw "Nothing moved"; sub-type 4 passed inside taken pinches (`gesture-tap-consume-20261029-182241`) |
| T3 pass-through | PASS | all no-⌥ sequences passed; normal app zoom/scroll |
| T4 coexistence | PASS | 80 Dock-control events never consumed; Spaces and Mission Control normal |
| T5 timing | PASS | p50 1 µs, p99 21 µs, max 2.19 ms, passed p50 1 µs, tap disabled 0 |
| T6 fields | Recorded | field 40 = frontmost app; field 87 = trackpad registry ID |
| Item 3 | No pinch lines | 0 zoom events with "Zoom in or out" off (`gesture-tap-listen-20261029-182546`) |
| M1 layout | PASS | 1,396 frames, 2,508 touches, all in range, stable ids (`gesture-mt-stream-20261029-182726`) |
| M2 Int32 return | PASS | system gestures normal while streaming |
| M3 re-enumeration | PASS with note; reconnect N/A | first frame 2,014 ms after wake, including time to the first touch (`gesture-rescan-20261029-182931`) |
| M4 latency | Recorded | MT leads tap: pan 63 ms (n 10), pinch 248 ms (n 2), touch-down to recognition (`gesture-compare-20261029-183044`) |

`gesture-tap-listen-20261029-072735` was a dry run with no gestures and is ignored.

## E-01 decision

User reply, verbatim: **"tap+multitouch"**. Decision-matrix row 2. Verdict: go with conditions C1-C5 (05-SPIKE.md "Verdict and conditions").

## Handoff to downstream plans

- **05-02 (recognizer):** C2. Pan samples whose sequence has no phase 1 or 2, or whose total delta is zero (128→8, Δ 0,0), are noise: add a fixture and a test that such a sequence yields nothing.
- **05-03 (product tap):** C1 and C3. In `GestureTapRules.decide`, a consuming pinch latch takes every type-29 event (drop the `zoom || hidRotate || hidType == 0` filter, keep the 61/62 envelope rule only if A4 still requires it; the host showed passing envelopes caused no stuck state). Extend `GestureTapRulesTests` and add a VM synth scenario with a sub-type-4 event inside an ⌥ pinch. Decide whether type-29 companions of a taken pan (sub-types 0, 6, 32) and trailing sub-type 0 after zoom ended belong to the latch. `hidRotate = 5` looks wrong for real hardware (sub-type 4 appeared during rotation-like motion; 5 appeared twice); check before relying on it. `trustsTargetPID` stays false. The E-04 sender filter is on: field 87 matched the IOKit registry ID.
- **05-04 (live follow):** C1 and C2 apply through 05-02/05-03; no extra change beyond consuming the whole pinch.
- **05-06 (Debug lines):** the "pan only" G1 value does not ship (Task 2 needs E-01 = "tap-only"). Item 3 did show no pinch lines, so record "pan-only value not shipped: spike item 3 = no pinch lines / E-01 = tap+multitouch".
- **05-07 (multitouch):** ships. Role per C4: MT is the pinch source when the tap delivers no sub-type 8 for a touch sequence (always so with pinch-to-zoom off); the tap still consumes. Built-in trackpad only on the host, so hot-plug of a second trackpad is untested on real hardware (VM has no device either). Wake re-enumeration must not add delay (M3 was 2,014 ms including the first touch).
- **05-08 (UAT):** C5. Drop the Magic Trackpad items and the "connect the Magic Trackpad" note; (both) items run on the built-in trackpad only; the reconnect item (UAT 15) is N/A; Spaces checks use 4-finger swipes or ⌃←→, not 3-finger. 05-08 pastes UI-SPEC Surface 7 "verbatim", so the conflicting UI-SPEC text is: the (both) definition (line ~319), UAT item 15 (line ~353) and the backstop row "Sleep/wake and Magic Trackpad reconnect" (line ~465), plus the 05-08 must_have "with (both) items run on the built-in trackpad and the Magic Trackpad" and the backstop statement at its line 33. UAT item 8 (mouse wheel or Magic Mouse with ⌥) needs a mouse; confirm the user has one, else N/A.

## Deviations from Plan

- **Magic Trackpad half not run.** The plan and CONTEXT assumed two trackpads; the user has only the built-in one. Every (both) and reconnect item is recorded N/A, not as a failure.
- **Optional no-⌥ consume run skipped.** T5's worst case with sequence-start CG reads (no `--require-alt`) is unmeasured on the host.

## Deferred Issues

None. The C1 leak is a condition for 05-03, not a defect in shipped code (the tap ships in 05-03).

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Input/GestureTapRules.swift, Sources/TransomPrivate/GestureEventFields.swift, Sources/transom-gesture-spike/main.swift, Sources/transom-gesture-spike/Multitouch.swift, Tests/TransomMacTests/GestureTapRulesTests.swift, .planning/phases/05-gestures/05-SPIKE.md
- FOUND commits: 856c52f, b7ba647, f4cef28
- `swift build --product transom-gesture-spike` succeeds; `swift test --filter GestureTapRulesTests`: 19 tests passed, no "✘"
