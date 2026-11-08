---
phase: 03-tiling-mvp
plan: 20
subsystem: layout-engine
status: complete
tags: [tile-05, g-03-3, gap-drag, resize, gap-closure]
gap_closure: true
gap_ids: [G-03-3]
requires:
  - "03-12: GapHandles, gapDrag, boundaryChange (TILE-05)"
provides:
  - "TreeEdits.setWeights(in:_:): validated, normalised weight setter for one split"
  - "boundaryChange re-bases each named split to its laid-out sizes before the move (H1)"
  - "Arranger.liveGap: the live gap move, applied by every replan until mouse-up (H2)"
affects:
  - "Edge resize (followResize) shares boundaryChange and gets the re-base"
  - "Every replan() caller (window events, correct, tick, commands) plans the live layout during a gap drag"
tech-stack:
  added: []
  patterns:
    - "Transient live state applied in replan() (liveGap), the same way `drag` holds an edge-resize session"
key-files:
  created: []
  modified:
    - Sources/PaneModel/TreeEdits.swift
    - Sources/PaneEngine/Arranger.swift
    - Tests/PaneModelTests/TreeEditTests.swift
    - Tests/PaneEngineTests/ArrangerResizeTests.swift
decisions:
  - "Re-base a split only where some taking child's weight share is off its laid-out size by more than 1 pt; an unpinned split keeps its weights bit-identical (whole-point re-based sizes otherwise floor a point short)"
  - "A live move that throws in replan is dropped with a fault effect; a live move whose split is gone is dropped silently"
  - "replan(with:on:) calls planShown(), so the live path cannot recurse"
metrics:
  duration: "~35 min (code ~15 min, VM ~20 min)"
  completed: 2026-10-26
estimate:
  tokens: 70000
  tasks: 3
actuals:
  tokens: 5000
  tasks: 3
  commits: 4
plan_head_before: 3cdf6df2da31fb75f196722a933512c5515770ca
plan_head_after: ea3ff4d
---

# Phase 3 Plan 20: Gap drag pinned-side re-base and live drag state (G-03-3) Summary

**Both G-03-3 causes are fixed. H1: before a gap move, `boundaryChange` re-bases the split's weights to the laid-out sizes, so a side held at its minimum no longer absorbs the drag. H2: the live move is now Arranger state (`liveGap`) that every replan applies until mouse-up, so a window event or a correction mid-drag no longer writes the pre-drag desk. Verified in the VM, Pane 0.3.4 (1002).**

## What changed

| Task | Name | Commits | Files |
|---|---|---|---|
| 1 | Tracer: re-base split weights to laid-out sizes (H1) | 39d02f3 (RED), eea2afa (GREEN) | TreeEdits.swift, Arranger.swift, TreeEditTests.swift, ArrangerResizeTests.swift |
| 2 | Hold the live gap move across replans (H2) | ebab4b2 (RED), ea3ff4d (GREEN) | Arranger.swift, ArrangerResizeTests.swift |
| 3 | VM UAT re-check of test 3 (no source change) | this SUMMARY commit | 03-20-SUMMARY.md |

- `setWeights(in:_:)` checks the count, and that every value is finite and greater than 0 (otherwise `.invalidGeometry`). It normalises the values to sum 1 and goes through `commit`, so the tree invariants hold.
- `boundaryChange.apply` re-bases each split once (a `Set<NodeID>`). The taking children get weights proportional to their sizes in `before.nodeRects`, and their weight total stays the same. A minimised child keeps its weight. The re-base runs inside `apply`, so both the raw trial and the cut change include it. The < 0.5 pt no-op guard is unchanged.
- `liveGap: (handle, delta)?`. `gapDrag` clears it first on `ended`, before the guard, then commits with `world.edit` + `replan()`. On a non-ended event that passes the guard it stores the move and calls `replan()`. `replan()` applies `liveGap` through `boundaryChange` + `replan(with:on:)`. If the move's split is gone it is dropped. If the move fails it is dropped with a fault. Otherwise `replan()` falls back to `planShown()`, which is the old body. `shownDesk(holding:)` is shared by `gapDrag` and `replan`.

## Verification

- `PANE_SKIP_AX_INTEGRATION=1 swift test --filter "TreeEditTests|ArrangerResizeTests"` → 21 (Model) and 14 tests passed after Task 1. `--filter "ArrangerResizeTests|ArrangerPauseTests|ArrangerReflowTests"` → `✔ Test run with 34 tests in 3 suites passed`.
- Full unit run, `PANE_SKIP_AX_INTEGRATION=1 swift test` → `✔ 193 tests in 20 suites` / `✔ 193 tests in 30 suites` / `✔ 465 tests in 50 suites passed`. All integration suites were skipped.
- `scripts/check-no-appkit.sh` → `no-appkit: OK (40 files)`.
- Acceptance greps: `func setWeights` 1, `setWeights` in Arranger.swift 1, `liveGap` 7, `func planShown` 1.

## TDD Gate Compliance

- RED 39d02f3: TreeEditTests failed to compile (`no member 'setWeights'`). With them set aside, the engine tests failed for the H1 reasons: the 2-child pinned gap left history depth 0 and nothing moved, and on the 3-child row a stayed 700 and the Desktop moved.
- GREEN eea2afa: all pass. The first GREEN attempt broke three existing tests by a 1 pt drift. Re-basing an unpinned split floored one share a point short. The re-base now runs only where a share is more than 1 pt off.
- RED ebab4b2: windowChanged, an off-plan windowResized and a tick each wrote the pre-drag tiles and the pre-drag handle (12 issues). The paused and split-gone tests are guard tests and passed before the fix.
- GREEN ea3ff4d: all pass. No REFACTOR step was needed.

## VM re-check G-03-3

**Setup.** The lock `.build/pane-vm.lock` was taken with `mkdir` and released with `rmdir` (`ls -d` now fails). `scripts/build-debug.sh --release` exited 0. The app was copied with ditto and bumped to 0.3.4 / 1002 (installed: 0.3.3 / 1001). It was re-signed with `Developer ID Application: Ken Scott (S2K7P43927)`, `--options runtime --timestamp`, and the build's own entitlements (`app-sandbox false`, identical to the built ones). The DR is unchanged (`… leaf[subject.OU] = S2K7P43927`). Pane was quit, the app was copied over with a tar pipe, and `codesign --verify --strict` passed in the guest. It was relaunched with `open`, and the log showed `permission notTrusted -> probing` then `probing -> ready`. Guest: Tart pane-test 192.168.64.18, macOS 15.7.7. Saved first: /tmp/layout-before-0320.json and /tmp/hints-before-0320.json.

**Before (Space 1).** This is the debug session's pinned layout, already in place. Root H[column 73, Terminal 160], all weights 0.5. Frames: TextEdit 202 `12 375 729 326`, TextEdit 578 `598 37 143 326`, Terminal 160 `753 37 256 659`. The floating Safari 669 (574 pt hint) and Finder windows pin the Desktop tile at 574. Hints: Terminal 165, TextEdit 143, Safari 574, Finder 460.

**(a) H1, pinned root gap.** Injected with `/tmp/injx`, 30-step drags:

| Step | Command | TextEdit 202 | TextEdit 578 | Terminal 160 |
|---|---|---|---|---|
| before | | `12 375 729 326` | `598 37 143 326` | `753 37 256 659` |
| +50 | `drag 747 400 797 400` | `12 375 779 326` | `598 37 193 326` | `803 37 207 659` |
| −50 | `drag 797 400 747 400` | `12 375 729 326` | `598 37 143 326` | `753 37 256 659` |
| ⌃⌥⌘Z | `key com 6` | `… 779 …` | `… 193 …` | `803 37 207 659` |
| ⌃⌥⌘Z | `key com 6` | `… 729 …` | `… 143 …` | `753 37 256 659` |

Before the fix, this +50 drag changed no frame (debug log, 16:00). After it, layout.json had root weights `[0.788, 0.212]`, the re-based screen weights. Each drag was one undo step. The first undo reversed the −50 and the second reversed the +50.

**(b) H2, hand-speed drags with the 5 ms sampler.** `/tmp/sampler <s> 202 578 160` ran in the background and `/tmp/pathdrag 16 1500 …` started 0.5 s later, so sampler ms ≈ pathdrag ms + ~500.

Run 1, Desktop shown (pinned): `pathdrag 16 1500 747 400 837 400 777 400 807 400`. Pathdrag: down 140, at 837 861, at 777 1265, at 807 1467, up 2970. Sampler, 135 changes. Terminal x/w: `47:753/256 693:756/256 … 1340:837/172 1375:840/172 1422:837/172 … 1948:807/207 1971:810/200 1987:813/200`. The last change is at 2003 ms (TextEdit 578 w 203). Nothing changed through the 1.5 s hold and mouse-up (~3470 ms). No sample after the press equals a pre-drag frame. No window moved more than 12 pt between samples. Final frames, kept after mouse-up: TextEdit 202 `12 375 789 326`, 578 `598 37 203 326`, Terminal `813 37 200 659`.

Run 2, Desktop hidden (`open pane://toggle-desktop`). This is the run that reverted twice in UAT. Start: 202 `12 375 494 326`, 578 `12 37 494 326`, Terminal `518 37 494 659`. `pathdrag 16 1500 512 400 650 400 400 400 560 400`: down 117, at 650 1058, at 400 2699, at 560 3722, up 5232. Sampler, 535 changes, and no window moved more than 12 pt between samples. One sample matched the pre-drag frames, at 3943 ms. That is the pointer passing back through the start x on its way from 400 to 560, and it is continuous: 202 width `3855:481 3877:484 3894:487 3927:490 3943:494 3957:495 3978:498`. The last change is at 4241 ms (202 w 542, Terminal 566/445). Nothing changed through the hold and mouse-up (~5730 ms). The same layout in the diagnosis jumped to the pre-drag frames at 3420 and 4134–5582 ms.

Each run was undone with ⌃⌥⌘Z, and the second toggle showed the Desktop again. The frames were back to "Before".

**(c) Test 3's other parts.** Finder and Safari were hidden (⌘H) so a new window has room (D-26, as in 03-19).
- Close: TextEdit ⌘N, then ⌃⌥⌘D docked 1032 (578 shrank to `348 37 158 326`). ⌘W closed it, and 578 went back to `265 37 241 326`.
- Gaps: `/tmp/axgap "16 pt"` (a new guest helper that presses Gaps ▸ through AX) set defaults `gap` to 16. Frames: 202 `16 377 488 320`, 578 `268 41 236 320`, Terminal `520 41 487 659`. `"12 pt"` restored it exactly.
- Relaunch: a +50 drag (`drag 512 400 562 400`) gave 202 w 544 and Terminal `568 37 445 659`. Pane was quit and relaunched (`probing -> ready`). Frames were unchanged, and layout.json root weights were `[0.5506, 0.4494]`, so the split persisted.

**Restore.** Pane was quit. Finder and Safari were unhidden. /tmp/layout-before-0320.json was copied back, and Pane was relaunched (`probing -> ready`). Floating TextEdit 722/567, which the close test had clamped to 156 wide while the Desktop tile was small, were put back at `12 37 574 326` with `/tmp/axset`. Every frame matches "Before". layout.json's `world` compares equal to the saved copy. `min-size-hints.json` was byte-identical (`cmp`) to the saved copy after the drags and at the end. The gap is 12. The installed app is now 0.3.4 (1002) with this fix.

The human-check (a hand drag by feel, including toward a pinned side) remains for end of phase, per the plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The re-base only runs where a weight share is off screen by more than 1 pt**
- **Found during:** Task 1 GREEN
- **Issue:** Re-basing every split to its whole-point laid-out sizes made `resolve`'s `rounded(.down)` floor one share a point short (469.999… → 469). Unpinned drags moved the far boundary by 1 pt, which broke `draggingTheInnerRightEdgeMovesTheBoundaryAndCommitsOnce`, `aResizeStopsAtTheNeighboursMinimum` and `aGapDragResizesBothSidesLiveAndCommitsOnMouseUp` (exact `maxX` / `desktopRect` checks).
- **Fix:** The re-base is skipped when every taking child's weight share is within 1 pt of its laid-out size. Such a split already matches the screen, so the plan's truth holds within a point. A pinned split is still re-based.
- **Files modified:** Sources/PaneEngine/Arranger.swift
- **Commit:** eea2afa

**2. [Rule 2] A live move that throws in replan returns a fault effect**
- The plan says to drop it. It is dropped, and the fault is also reported, which matches what `gapDrag`'s old live path did.

### Process note

After Task 1 GREEN, one unfiltered `swift test` on the host also ran PaneMacIntegrationTests, because the shell process has the AX grant. For about 14 s, PaneFixtureApp windows were launched and moved on the host. `FrameWriteIntegrationTests.aRefusedSizeIsReadBackAndLearned` failed its 2 s learning wait. That path is AXWindowSystem/learner timing, which this plan does not touch. `pgrep` found no leftover PaneFixtureApp or test process then, or after the coordinator's stop request. Every later run used `PANE_SKIP_AX_INTEGRATION=1`.

## Known limits

- When a window closes mid-drag and the split survives with fewer children, the handle's `first`/`second` indices can name a different pair. The panel keeps its press (GapHandlePanels matches on split and indices), so the next drag event, and mouse-up, move that pair. This behaviour predates this plan. A drag whose split is gone is dropped (tested).
- If AppKit ever lost the handle's mouse-up, `liveGap` would stay until the next `ended`. The panel's `mouseUp` sends `ended` from the view that took the press.

## Known Stubs

None.

## Threat Flags

None. T-03-56: an ended event clears `liveGap` first. A gone or failing move is dropped, and `liveGap` is never persisted. T-03-57: `setWeights` validates count, finiteness and > 0, and commits through `commit`. Its inputs are Planner node rects.

## Self-Check: PASSED
