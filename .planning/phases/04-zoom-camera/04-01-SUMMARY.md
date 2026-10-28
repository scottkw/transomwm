---
phase: 04-zoom-camera
plan: 01
subsystem: zoom
status: complete
tags: [spike, screencapturekit, core-animation, ax, vm]
requires: []
provides:
  - "transom-zoom-spike harness (settle, capture, layers, soak, menus, minsize, frames)"
  - "SnapshotCapture.swift: the only ScreenCaptureKit file"
  - "StagePanel.swift: stage core that 04-04 extends"
  - "scripts/vm-spike.sh: VM-only spike runner"
  - "04-SPIKE.md: G1-G8 numbers and the GO-with-conditions verdict"
affects: [04-02, 04-03, 04-04, 04-05, 04-06, 04-07, 04-08]
tech-stack:
  added: [ScreenCaptureKit (SCScreenshotManager one-shot captures), AVFoundation (harness frame extraction only)]
  patterns:
    - "Timeout race through a resume-once continuation (a task group would wait for a hung child)"
    - "Opaque stage fades with window alphaValue, not layer opacity"
    - "Spike runs only in the Tart VM through scripts/vm-spike.sh under the shared .build/transom-vm.lock"
key-files:
  created:
    - Sources/transom-zoom-spike/main.swift
    - Sources/TransomMac/Zoom/SnapshotCapture.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - scripts/vm-spike.sh
    - .planning/phases/04-zoom-camera/04-SPIKE.md
  modified:
    - Package.swift
    - Tests/TransomMacTests/NoScreenCaptureTests.swift
    - .planning/phases/04-zoom-camera/04-UI-SPEC.md
    - .planning/phases/04-zoom-camera/04-01-PLAN.md
    - .planning/phases/04-zoom-camera/04-04-PLAN.md
    - .planning/phases/04-zoom-camera/04-08-PLAN.md
    - .planning/REQUIREMENTS.md
key-decisions:
  - "Spike verdict GO with conditions (user, 2026-10-28): G4 crossfade stalls accepted as VM noise, no host run"
  - "SnapshotCache is mandatory in 04-04 (only ~6 of 15 captures land inside the 120 ms budget in the VM)"
  - "sharingType .none does not hide the stage from system screen recording on macOS 15.7; it only keeps it out of Transom's own snapshots"
  - "ZOOM-07's 500 ms is the write path only: first AX write to last read-back, capture budget and animation separate"
  - "No mitigation ladder step: G1 p95 205 ms passes on the existing FrameWriter path; Sources/TransomMac/AX unchanged"
requirements-completed: [ZOOM-07, ZOOM-05]
metrics:
  duration: "8h 34m wall clock (includes the go/no-go checkpoint wait and the 60-minute soak)"
  started: 2026-10-28T04:11:11Z
  completed: 2026-10-28
  tasks: 3
  files: 12
estimate:
  tokens: 95000
  tasks: 3
actuals:
  tokens: 21500
  tasks: 3
  commits: 3
plan_head_before: 6c6e542748f86ae98647085c947c750ead216d25
plan_head_after: 863bb1b
coverage:
  - deliverable: "ScreenCaptureKit confined to SnapshotCapture.swift, guarded by NoScreenCaptureTests"
    human_judgment: false
    verification:
      - kind: test
        ref: "Tests/TransomMacTests/NoScreenCaptureTests.swift#noSourceFileUsesScreenCapture"
        status: pass
      - kind: test
        ref: "Tests/TransomMacTests/NoScreenCaptureTests.swift#theAllowedCaptureFileExists"
        status: pass
  - deliverable: "Spike harness and VM runner produce G1-G8 records in the VM"
    human_judgment: false
    verification:
      - kind: command
        ref: "scripts/vm-spike.sh settle --runs 2 --fixtures 4 (>= 4 G1 lines)"
        status: pass
  - deliverable: "Headless suite still passes with the new targets"
    human_judgment: false
    verification:
      - kind: command
        ref: "swift test (564 tests in 54 suites, no failures)"
        status: pass
  - deliverable: "Go/no-go decision on the measured gates"
    human_judgment: true
    rationale: "Feasibility verdict is the user's call (CONTEXT D); recorded in 04-SPIKE.md Verdict as GO with conditions"
---

# Phase 4 Plan 1: Zoom Camera Feasibility Spike Summary

**I built a measurement harness that uses Transom's own window-write path, plus the product files `SnapshotCapture` and `StagePanel`, and ran gates G1–G8 in the Tart VM. Settling 15 windows (2 of them VS Code) takes p95 205 ms zooming in and 93 ms zooming out. Reveals showed no stale layout in 40 moves. WindowServer grew 7.5 MB over a 1-hour soak. The user chose GO with conditions.**

## Performance

- **Duration:** 8h 34m wall clock, from 2026-10-28T04:11:11Z to 2026-10-28T12:45Z. That includes the checkpoint wait and the 60-minute soak.
- **Tasks:** 3 (2 automated, 1 go/no-go checkpoint)
- **Files:** 12 created or modified

## Headline Numbers (04-SPIKE.md)

- **G1 settle, 15 windows: PASS.** Zoom in: p50 64.8 ms, p95 205.1 ms, max 280.3 ms. Zoom out: p50 58.0 ms, p95 93.1 ms, max 110.3 ms. Data: `.build/spike/settle-20261028-000855`.
- **G2 no stale flash: PASS.** 0 position mismatches and 0 parked windows left on screen in 40 moves. All 10 recorded reveals are clean once the 120 ms fade ends. Same directory as G1.
- **G3 1-hour soak: PASS.** WindowServer grew 7.5 MB (range 389–402 MB, `top` MEM) and replayd 1.6 MB, over 343 moves. Data: `.build/spike/soak-20261028-012908`.
- **G4 120 animated tiles: strict FAIL, accepted as VM noise.** The normal animated move passed 20 of 20 runs (largest gap 20.6 ms). The Reduce Motion crossfade passed 58 of 60; the other 2 stalled for 172 ms and 51.8 ms. Data: `.build/spike/layers-20261028-001648`, `-002630`, `-002734`, `-002823`.
- **G5 (stage vs menus):** the open menu (level 101), menu bar, Dock and toast all draw above the stage (level 3). Data: `menus-20261027-234844`.
- **G6 (Terminal re-wrap):** the Terminal in the view goes 33 → 45 → 33 columns. Data: same directory as G1.
- **G7 (window too big for its tile):** the read-back refuses the size, 900x700 for a 341x345 tile, in 8.7 ms. Data: `minsize-20261028-002637`.
- **G8 (capture costs):** fetching the shareable-window list takes 52–64 ms. One capture takes 20–30 ms. About 6 of 15 captures finish within 120 ms. A parked window captures whole. Data: `capture-20261028-001631`.
- **Mitigation ladder:** no step applied.

## Accomplishments

- `transom-zoom-spike` drives `AXWindowSystem.perform` and times every `frameApplied` read-back. It covers G1–G8 and writes JSON lines.
- `SnapshotCapture.swift`, the only ScreenCaptureKit file:
  - `isGranted` and `request`
  - `refreshShareable`, kept off the move's critical path
  - `capture`, with its own 1 s timeout
  - `captureAll`, with a 120 ms deadline and at most 4 captures at a time
- `StagePanel.swift`:
  - one opaque, never-key panel per display, with a wallpaper backdrop
  - tiles that fill their rect while keeping aspect, pinned to the top edge
  - a 250 ms ease-out move, a Reduce Motion crossfade and a 120 ms fade-out
  - a Debug-only `TRANSOM_STAGE_CAPTURABLE` switch
- `NoScreenCaptureTests` now allows exactly one file and asserts that file exists. `CGWindowListCreateImage` stays forbidden in every file.
- `scripts/vm-spike.sh`:
  - builds on the host and runs only in the VM
  - takes the shared `.build/transom-vm.lock`
  - keeps the host and the guest awake with caffeinate
  - copies results to `.build/spike/` and deletes recordings from the guest after copying
- The verdict conditions are applied to the UI-SPEC, the threat models of 04-01 and 04-04, the 04-04 must-haves, ZOOM-07 in REQUIREMENTS.md and the 04-08 gate.

## Task Commits

1. **Task 1: tracer settle in the VM.** `7feb618` (feat)
2. **Task 2: stage core and gates G1–G8.** `4b4ecd4` (feat)
3. **Task 3: go/no-go verdict and its conditions.** `863bb1b` (docs)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The capture timeout races through a resume-once continuation, not a task group**
- **Found during:** Task 1
- **Issue:** A task group waits for every child task when it exits. A `captureImage` call whose completion handler never fires would still hang the caller.
- **Fix:** `withCheckedContinuation` plus a lock-guarded `ResumeOnce`. The completion handler and a 1 s timer race to resume it.
- **Files:** Sources/TransomMac/Zoom/SnapshotCapture.swift
- **Commit:** 7feb618

**2. [Rule 1 - Bug] The stage fades with window alpha, not layer opacity**
- **Found during:** Task 2
- **Issue:** The panel is opaque (UI-SPEC), so making its content layer transparent would show black instead of the windows underneath.
- **Fix:** `fadeOut` animates `alphaValue`.
- **Files:** Sources/TransomMac/Zoom/StagePanel.swift
- **Commit:** 4b4ecd4

**3. [Rule 1 - Bug] G6 reads columns with `stty size </dev/tty`**
- **Found during:** Task 2
- **Issue:** With its output redirected to a file, `tput cols` always reported 80.
- **Fix:** read the column count from the terminal device with `stty`.
- **Files:** Sources/transom-zoom-spike/main.swift
- **Commit:** 4b4ecd4

**4. [Rule 3 - Blocking] The harness skips windows that already existed when it started**
- **Found during:** Task 2
- **Issue:** Safari, TextEdit, Terminal and Notes had been running in the guest for about 9 hours. The harness could have measured their old windows.
- **Fix:** windows that exist before the harness launches the apps are never measured. TextEdit opens a new `note-<pid>.txt` each run. My first attempt quit those apps first, and I removed it:
  - TextEdit put up its own "keep this new document?" sheet for an old untitled document. I pressed Cancel; the document is kept.
  - A Terminal "terminate?" prompt covered only the harness's own windows. I pressed Terminate, and cleanup now waits 1 s before quitting so the scripts can exit first.
- **Files:** Sources/transom-zoom-spike/main.swift
- **Commit:** 4b4ecd4

### Scope Notes

- I added a `minsize` subcommand for G7. The plan listed six subcommands and gave G7 no home.
- G2's frame extraction runs in the guest, and `settle --record` does it automatically. The plan described `frames` as a host-side helper, but that would have meant running the harness on the host, which the rules forbid.
- A marker panel that turns from red to green marks reveal start in the recordings, so frames line up without guessing the recording's start-up delay.

**Total deviations:** 4 auto-fixed (3 Rule 1, 1 Rule 3), plus 3 scope notes. **Impact:** the first two make the product files correct. The others only affect the harness.

## Issues Encountered

- **The stage appears in screen recordings.** On macOS 15.7, `sharingType = .none` does not hide the stage from `screencapture -v`. The verdict accepted this and reworded the UI-SPEC and threat model.
- **Two crossfade stalls in G4.** One run each stalled for 172 ms and 51.8 ms. They didn't repeat and weren't at the first frame. The user accepted them as VM noise.
- **One slow host-side return.** One `vm-spike.sh` run took about 10 minutes to come back after the guest had finished. The cause was on the host side and no measurement was affected.

## Known Stubs

None. The harness is spike tooling, and the collapsed-block half of G7 is "no observation" by design; 04-02 and 04-07 build it.

## Threat Flags

None beyond the plan's threat model. The new surface is the in-memory capture path (T-04-01) and the stage panel (T-04-02, residual now documented).

## Next Phase Readiness

Plans 04-02 through 04-08 are unlocked. 04-04 must build the snapshot cache (condition 2). ZOOM-07's live gate in 04-08 times only the write path (condition 4).

## Self-Check: PASSED

- Files: main.swift, SnapshotCapture.swift, StagePanel.swift, vm-spike.sh and 04-SPIKE.md exist.
- Commits: 7feb618, 4b4ecd4 and 863bb1b are ancestors of HEAD.
- Acceptance criteria re-run before the Task 2 commit:
  - ScreenCaptureKit and the Screen Recording calls appear only in SnapshotCapture.swift.
  - `CGWindowListCreateImage` appears nowhere.
  - `TRANSOM_STAGE_CAPTURABLE` sits inside `#if DEBUG`.
  - `sharingType = .none` is present.
  - 04-SPIKE.md names its `.build/spike/` directories.
  - `Sources/TransomMac/AX` is unchanged.
- Plan verification: `swift build` passes, and the full `swift test` passes 564 tests with no failures. `NoScreenCaptureTests` ran 2 tests. Every spike measurement came from the VM.
