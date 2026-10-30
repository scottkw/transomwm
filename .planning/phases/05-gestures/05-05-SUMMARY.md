---
phase: 05-gestures
plan: 05
subsystem: zoom
status: complete
tags: [gestures, overscroll, refusal, takeover, pick-mode, vm]
requires:
  - "05-02: GestureRecognizer.follow(hasTarget:), Release.passedThreshold, Arranger.stillMove / gestureTarget"
  - "05-04: ZoomController .following, beginFollow / follow / refollow / springBack, StagePanel follow, GestureController follow path"
provides:
  - "GestureController: refused or preview-less gestures follow the current view's still tile set (overscroll) and spring back; the refusal announcement is posted only past the commit threshold; `announce` seam; a taken gesture ends pick mode; a busy display is handed to ZoomController"
  - "ZoomController: beginFollow takes over a busy display (E-03), `interrupted[uuid]` keeps the superseded move (or one queued behind a fade); a commit drops it, a spring back retargets to its tiles and `resume`s it (settle once / re-arm reveal / fade); read-backs during the follow still count"
  - "StagePanel: freezeAtPresentation(), refollow(tiles:finishingDropped:) from current frames, followFrom lerp starts, a generation that cancels a spring back's fade and a fade's order-out after a takeover; TileLayer.freeze()"
  - "ArrangeController.endPick(reason:) and isPicking; ZoomInput.isPicking"
affects: [05-06, 05-07, 05-08]
tech-stack:
  added: []
  patterns:
    - "A spring back after a takeover is Phase 4's retarget back to the interrupted move's tiles; its completion resumes that move where the gesture found it"
    - "Stage completions scheduled before a takeover are fenced by a generation counter instead of being tracked one by one"
key-files:
  created: []
  modified:
    - Sources/TransomMac/Zoom/GestureController.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/TileLayer.swift
    - Sources/TransomMac/Zoom/ZoomInput.swift
    - Sources/TransomMac/ArrangeController.swift
    - Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift
key-decisions:
  - "E-03 follow lerps from the tiles' frozen frames (StagePanel.followFrom), not from the preview's start rects, so the first sample never jumps; spring back after a takeover goes to the interrupted move's end rects (the pending target's view) through retarget"
  - "A move queued behind a reveal fade is the takeover's base (it is the engine's pending move); a gesture's own spring back owes no settle"
  - "refollow also serves reversals: tiles go on from where they are, which equals the start rects at p ≈ 0 in a plain follow"
requirements-completed: [GEST-01, GEST-02]
metrics:
  duration: "~65 min"
  started: 2026-10-30T02:27:00Z
  completed: 2026-10-30T03:32:16Z
actuals:
  tokens: 4707
  tasks: 2
  commits: 2
plan_head_before: e09eb76ebb05633028f3ba317a417c5a911df636
plan_head_after: 8db5f865fa60a80dd547286b2ff580d4e6c071fe
---

# Phase 5 Plan 05: Refusals, One-Level Clamp and Gestures During a Move Summary

**Gestures that have nowhere to go now overscroll and spring back. A pan at home, a pinch out at home or a pinch in on a leaf follows the current view's still tile set (`stillMove`) with the rubber-band curve, then springs back. VoiceOver hears the Phase 4 refusal text only when the gesture would have committed, and nothing ever beeps. A gesture taken during a Phase 4 move or settle freezes the stage where it is and follows from there. A commit supersedes the interrupted move. A spring back retargets to that move's tiles and lets it settle exactly once, so `camera.pending` never strands. A taken gesture also ends pick mode.**

## What was built

- **GestureController**
  - `.started` with no target (or no preview) calls `stillMove` and `beginFollow`. The follow uses `follow(hasTarget: false)`, so t is 0 and overscroll runs from p = 0: pinches scale about the pinch point, pans offset along the locked axis.
  - On release a refused gesture always springs back. It calls `announce(refusal.announcement)` only when `release.passedThreshold` is true. The outcome is `.refused(reason)`, and the took line names the reason ("no area right", "nothing to zoom in to").
  - `announce` defaults to `postAnnouncement`. The file contains no "beep" and no retyped refusal strings.
  - The busy-display gate is gone: ZoomController owns the takeover.
  - The first sample of a taken sequence calls `controller.endPick(reason: "gesture")`.
- **ZoomController**
  - `beginFollow` on a busy display:
    - logs "retarget gesture {kind} during {phase}"
    - cancels the reveal timer and freezes the stage
    - stores the newest pending move as `interrupted[uuid]`. That is either the running move or the one queued behind a fade. A gesture's own spring back owes nothing.
  - `run`'s retarget branch drops `interrupted`, because a commit or any newer move makes the old settle stale.
  - `springBack` after a takeover puts the interrupted Active back with phase `.moving` and retargets the stage to its tiles. `resume` then continues it:
    - capturing or moving: `settle(id)` once
    - settling: re-arm the reveal
    - revealing: the fade, then `finishReveal`
  - `frameApplied` also counts read-backs for an interrupted settle.
  - `displaysChanged` and `purge` clear `interrupted`.
- **StagePanel / TileLayer**
  - `freezeAtPresentation()` copies the presentation frame and opacity into the model frame (`TileLayer.freeze`), cancels the window-alpha fade, and bumps `generation`. A spring back's fade and a fade's order-out that were scheduled earlier then do nothing.
  - `refollow(tiles:finishingDropped:)` rebuilds the tile set with each tile at its current frame and records `followFrom`, so the lerp starts there. On a takeover, dropped tiles (the old move's leaving tiles) carry on to their old end off screen. On a reversal they are removed, because they sit at their off-screen start.
  - When the stage is already up, `beginFollow` uses `refollow`.
  - The backdrop is never touched by follow. No new duration literals: the `0.25|0.12` count is still 2.
- **ArrangeController / ZoomInput**
  - Added `endPick(reason:)`, `isPicking` and `ZoomInput.isPicking`.
  - Collapsed panels already hide in `beginFollow` and fade in through `onFollowEnded` or `onRevealed`. After a takeover's spring back they fade in through the resumed move's reveal.
  - `onViewChanged` still fires only from `revealed`, so the status button changes only at a settle.

## Tests

- **VM (Tart pane-test, macOS 15.7.7, display woken by the script):** `scripts/vm-live-test.sh GestureFollowIntegrationTests` ran **13 of 13 passed** after Task 2. After Task 1 it ran 10 of 10.

| Test | Result |
|---|---|
| aPanAtHomeOverscrollsAndSpringsBackSilently | −0.2 W slow at home: `.home`, 0 announcements, 0 beeps, `.refused(.noArea(.right))`, 0 downstream |
| aDecisivePanAtHomeAnnouncesNoArea | −0.5 W: one "No area to the right", 0 beeps |
| aLongPinchGoesExactlyOneLevel | Σ +3.0 at home: view = `gestureTarget(.pinchIn)`, depth 1, `.moved` |
| aPinchInOnALeafAnnouncesNothingToZoomIn | from a leaf, Σ +1.2: "Nothing to zoom in to", view unchanged |
| aGestureDuringAHotkeyMoveRetargetsWithoutStranding | stepOut, then Σ +1.2 at once (display busy): view = pinch-in target from the step-out's target, `camera.pending` empty |
| aSpringBackDuringAMoveLetsThatMoveSettle | stepOut, then Σ +0.1: view = the step-out's target, pending empty, history back ends at the leaf, `.sprangBack` |
| aGestureEndsPickMode | Zoom Out to All Windows → pick on; a taken pinch turns it off |
| 05-04's six cases | all pass, no regression |

- Guest log (`log stream`, alongside the run):
  - "retarget gesture pinch during capturing", then "took pinch #1 … moved to node(n1)"
  - "retarget gesture pinch during moving", then "took pinch #1 … sprang back", then the step-out's "pick mode on" (it settled)
  - "pick mode off: gesture"
  - "took pan #1 … no area right" (twice), "took pinch #1 … nothing to zoom in to"
- VM regression: `ZoomSettleIntegrationTests` 2/2 (run on its own).
- Host, headless: `swift test --filter 'ZoomOffTests|StageFollowTests|TileLayerTests|GestureTapRulesTests'` ran **27 tests in 4 suites, passed**. `scripts/check-no-appkit.sh` OK (45 files).
- No event tap, multitouch device, window or Transom launch ran on the host. The VM was started for the runs and stopped afterwards (`tart stop pane-test`).

## Deviations from Plan

1. **[Rule 1 - Bug] Following from the preview's start rects would jump.** The plan expected `refollow` to rebuild "from current frames", but 05-04's `refollow` called `show(tiles:)`, which puts every tile back at its start rect. The preview's stay tiles also start at the windows' tracked frames, which during a move are the old view's positions. Fix: `StagePanel.refollow` keeps each tile where it is and lerps from there (`followFrom`). A takeover's spring back goes to the interrupted move's end rects through Phase 4's `retarget`, not through `springBack`. Commit 8db5f86.
2. **[Rule 2] Stage completions after a takeover.** Without a fence, a reveal fade's completion orders the stage out mid-follow, and so does a spring back's tile-animation completion (via its fade). Added `generation` in StagePanel. Also added: read-backs during the follow count toward the interrupted settle, and a move queued behind a fade becomes the takeover base, so its pending move can't strand.
3. **[Interpretation] The retarget log line is checked through `log stream`, not inside the test.** The info-level lines aren't persisted, so the test asserts on state (view, `camera.pending` empty, history, outcome). The "retarget gesture pinch during …" lines were read from a guest `log stream` during the run, as Phase 4 UAT did.
4. **[Scope] Small additions outside `files_modified`:** `TileLayer.freeze()`, and `ZoomInput.isPicking` for the pick-mode test.
5. **`post(… warp: false)`** in the test helper lets the gesture start within milliseconds of the hotkey move, instead of after the 300 ms warp settle.

## Known Stubs

None.

## Known limits

- Under Reduce Motion, a takeover in the middle of a crossfade replaces the half-faded tile sets with opaque tiles at the pending target's rects. That is an opacity pop, not a frame jump. Left to UAT item 9.
- `NSAnimationContext` with `duration = 0` is how the reveal fade is cancelled. A takeover during the 120 ms reveal fade was not covered in the VM; only capturing and moving were hit.

## Threat Flags

None. T-05-16: a superseded move either settles once (`resume`, fenced by `interrupted` and the move ID) or is replaced by a newer pending move, and the VM asserts `camera.pending` is empty when idle. T-05-17: every refused gesture logs its reason at default level, even when silent.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Zoom/GestureController.swift, ZoomController.swift, StagePanel.swift, TileLayer.swift, ZoomInput.swift, Sources/TransomMac/ArrangeController.swift, Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift
- FOUND commits: 6ce043a, 8db5f86
