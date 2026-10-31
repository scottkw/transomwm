---
phase: 05-gestures
plan: 02
subsystem: engine
status: complete
tags: [gestures, recognizer, camera, preview, tdd]
requires:
  - "05-01: sample record keys (t, kind, phase, momentum, m, dx, dy), recorded tap-listen traces, spike conditions C2 and C4"
provides:
  - "GestureTuning: every gesture threshold in one enum"
  - "GestureRecognizer: source-neutral Sample in; started/progress/reversed/ended(Release) out; follow(hasTarget:) gives t plus overscroll; timeout(now:)"
  - "Arranger.previewMove(to:displayUUID:) and stillMove(displayUUID:): non-committing CameraMoves, id 0"
  - "Arranger.gestureTarget(_:displayUUID:pointer:): direction -> Phase 4 cameraStep target or refusal, no beep"
  - "Arranger.planTiles: the single tile planner shared by zoomTo and the previews"
affects: [05-03, 05-04, 05-05, 05-07]
tech-stack:
  added: []
  patterns:
    - "One recognizer for every gesture source: Sample keeps raw CG phase/momentum integers; multitouch (05-07) builds the same type"
    - "Preview and commit share one tile function, so the snap's tiles equal the previewed ones"
    - "Trace fixtures are JSONL in the spike's sample keys, loaded through #filePath"
key-files:
  created:
    - Sources/TransomEngine/GestureRecognizer.swift
    - Tests/TransomEngineTests/GestureRecognizerTests.swift
    - Tests/TransomEngineTests/Fixtures/Gestures/pinch-in-commit.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/pinch-out-short.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/pan-left-third.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/pan-flick.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/pan-reverse.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pinch-out.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pinch-in-small.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-up.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-down.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-maybegin-start.jsonl
    - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-noise.jsonl
  modified:
    - Sources/TransomEngine/Arranger+Camera.swift
    - Tests/TransomEngineTests/ArrangerCameraTests.swift
key-decisions:
  - "C2 applied kind-agnostically: a sequence that never started and saw no phase 1/2 or no motion ends silently (no Update at all, isFinished true); a started gesture always gets exactly one .ended"
  - "Release.direction is optional (nil when the gesture never left the dead zone or locked an axis) and Release carries progress (|p|)"
  - "Fingers-down timeout (2 s) ends as a cancel (never commits); a pending fingers-up release decides normally after momentumWait, flagged endedByTimeout only when polled past fingersUpTimeout (0.3 s)"
  - "Deltas accumulate from phases 1, 2 and 4 (real pinches carry magnification on phase 4); 128 and momentum samples never move progress"
requirements-completed: []  # engine half only; GEST-01/02 are user-visible after 05-04/05-05 wire the tap and stage
metrics:
  duration: "~10 min"
  started: 2026-10-29T23:41:05Z
  completed: 2026-10-29T23:51:00Z
actuals:
  tokens: 15954
  tasks: 2
  commits: 2
plan_head_before: 525faa5c40511494d7c46567d3aeba5d6670001a
plan_head_after: de81080b03e336f1738d9dd31819d54e68c50163
---

# Phase 5 Plan 02: Gesture Recognizer and Camera Preview Summary

**A pure, AppKit-free `GestureRecognizer` turns source-neutral pinch and pan samples into progress, overscroll and a snap decision. `Arranger.previewMove` returns exactly the tiles the next `zoomTo` commits, and changes no camera state. Both are tested headless from synthetic and recorded built-in-trackpad JSONL traces.**

## What was built

- **`GestureTuning`** holds every threshold from D-01, D-03 and E-02, plus `scaleFloor` 0.05 (T-05-06). No threshold literal appears elsewhere in the file.
- **`GestureRecognizer`** (`init(kind:viewSize:)`, `feed`, `timeout(now:)`, `follow(hasTarget:)`, `static overscroll(_:limit:)`, `isFinished`):
  - Pinch: s = 1 + Σm (each m clamped to ±1, NaN/∞ → 0, s floored at 0.05), p = ln s / ln 2, dead zone |ln s| < 0.03, commit at |p| ≥ 0.5 or a flick of ≥ 2.0/s over 80 ms with |p| ≥ 0.15.
  - Pan: the axis locks at |Σ| ≥ 12 pt once one axis is 1.5× the other. p = |d|/W. Commit at p ≥ 1/3, or a flick of ≥ 800 pt/s toward the drag with |d| ≥ 24 pt, measured over the last 80 ms or from the first momentum sample. Edges follow natural scrolling: fingers left → `.right`, fingers up → `.bottom`.
  - Crossing zero emits `.reversed`. Motion on the unlocked axis is ignored. Samples after `.ended` are ignored.
  - `follow` implements UI-SPEC Surface 1: t = min(|p|, 1) with a target, overscroll R(x, L) with L = 0.25 level (as a scale 2^±R) or W (as an offset).
- **`Arranger+Camera.swift`**: `zoomTo`'s tile planning moved into private `planTiles(from:to:display:desk:)`. `zoomTo` keeps its guards, notes, `effectiveView` and mutation tail, and all existing ArrangerCameraTests pass unchanged. The new functions are non-mutating:
  - `previewMove`: zoomTo's guards plus "node exists" and "not already shown"; `id: 0`.
  - `stillMove`: the current view to itself, for a refused gesture's overscroll.
  - `gestureTarget`: `.pinchIn`/`.pinchOut`/`.pan(edge)` → `cameraStep` with `focused: nil` and the pointer.
  - Shared guards live in private `previewBase`. `nextMoveID` is still mutated only in zoomTo's tail; the grep count is 4 before and after.

## Tests

- `swift test --filter 'GestureRecognizerTests|ArrangerCameraTests'`: **28 tests passed** after Task 1. After Task 2, `GestureRecognizerTests` alone: **18 tests passed**, plus 5 recorded-trace cases.
- Full headless run (`--filter 'TransomEngineTests|TransomModelTests'`): **686 tests in 65 suites passed** (193 in the second runner line). Mac integration tests were not run, because they open windows on the host.
- `scripts/check-no-appkit.sh`: OK (45 files).
- New ArrangerCameraTests cases check four things: previewMove leaves `camera.pending` and `nextMoveID` unchanged, and its tiles equal the next zoomTo's tiles. While a move is pending, the preview starts from the pending target. The nil cases are zoom off, an unknown display, the view already shown, an unknown node, and paused. stillMove gives start == end == tile and changes no state. gestureTarget picks the child under the pinch point, refuses `.alreadyHome` and `.noArea(.right)` at home, and refuses `.nothingToZoomIn` at a leaf.

## Recorded traces

**Real trackpad traces were added**: six built-in trackpad sequences from the 05-01 `tap-listen` runs (`gesture-tap-listen-20261029-073133` and `-082731`). Only the hid 8 (zoom) samples were kept for pinches, and only the cgType 22 samples for pans. Keys are reduced to t/kind/phase/momentum/m/dx/dy, and t is rebased to 0. No pid, sender or label fields remain (the grep exits 1). The files cover:

- a pinch out (Σm −0.815)
- a small pinch in (Σm +0.078)
- a pan up with momentum
- a pan down with momentum
- a pan that starts with 128 then 1
- a 128 → 8 zero-delta noise pair, used for the C2 test

## Deviations from Plan

### Spike conditions applied (the plan predates them)

**1. [C2] Noise pans yield no gesture**
- Sequences that never started and have no phase 1/2 or zero total motion end silently: feed and timeout return nil and `isFinished` becomes true. This is tested with a synthetic 128 → 8 pair, the recorded noise pair, and a lone 128 that times out.
- Applied to both kinds. A started gesture always ends with exactly one `.ended`, so a stage that is up is always resolved.

### Auto-fixed / interpretation

**2. [Rule 3] `import Foundation` in GestureRecognizer.swift.** The plan said "import TransomModel only", but `log`/`pow` need Foundation. Other engine files already import it. AppKit, CoreGraphics and Cocoa are still absent.

**3. [Interpretation] fingersUpTimeout semantics.** With `momentumWait` (0.06 s) deciding a pending fingers-up release, the 0.3 s fingers-up timeout only marks a release noticed late: `timeout(now:)` polled past 0.3 s of silence sets `endedByTimeout`. A release decided within the wait is not flagged. The 2 s fingers-down timeout ends as a cancel (passedThreshold false), because the fingers never lifted.

**4. [Rule 2] Non-finite sample time** keeps the last time, so a NaN `t` can't stop the timeouts from firing (T-05-07).

**5. ArrangerCameraTests now uses `@testable import TransomEngine`** to read `camera.pending` and `nextMoveID`, as ArrangerCollapseTests already does.

## Observations for later plans

- **Real pinch-outs routinely sum below Σm = −1** (15 of 18 sequences in the safari-preview run). Additive s then hits the 0.05 floor and p ≈ −4.3. Behaviour is correct (one level per gesture, overscroll capped at ×0.84), but pinch-out reaches ½ level with half the finger travel pinch-in needs (Σm −0.29 vs +0.41). This is a feel question for UAT items 1–5; the constants are in `GestureTuning`.
- Real pans arrive at about 60 Hz. In the sequences inspected, momentum began about 7 ms after phase 4, and the first momentum sample alone gave over 4,000 pt/s, five times the 800 pt/s flick threshold. Most real released pans may therefore pass by flick. Watch for this at UAT.
- 05-04 must poll `timeout(now:)` at least every `momentumWait` while `fingersUp` is pending.

## Known Stubs

None.

## Threat Flags

None. T-05-06 (clamp, NaN/∞ → 0, scale floor) and T-05-07 (both timeouts) are implemented and tested.

## Self-Check: PASSED
