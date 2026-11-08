---
phase: 05-gestures
plan: 04
subsystem: zoom
status: complete
tags: [gestures, follow, stage, camera, vm]
requires:
  - "05-02: GestureRecognizer (feed, timeout, follow), previewMove, stillMove, gestureTarget"
  - "05-03: GestureTap samples and sequence ends, GestureController, the timeout timer"
provides:
  - "GestureController: one GestureRecognizer per taken sequence, target and preview per direction, recognizer polled every momentumWait, any open recognizer resolved when the tap ends or drops the sequence; lastGesture (seq, kind, direction, outcome) and the outcome on the took line"
  - "ZoomController .following: beginFollow(_:gesture:), follow(displayUUID:state:anchor:direction:), refollow(_:), springBack(displayUUID:), isFollowing(_:), static followStyle(reduceMotion:), reduceMotion seam, onFollowEnded"
  - "StagePanel beginFollow(tiles:crossfade:), follow(t:scale:anchor:offset:), springBack(fade:completion:), setContents(_:for:), static followRect; TileLayer set(_:) and setSnapshot(_:)"
  - "ArrangeController beginFollow(_:gesture:) and followStage()"
affects: [05-05, 05-06, 05-07, 05-08]
tech-stack:
  added: []
  patterns:
    - "A committed gesture is an ordinary zoomTo: its .cameraMove finds the display .following and takes Phase 4's retarget branch from presentation rects"
    - "A released gesture's judgement is kept until the tap ends the sequence, so its momentum tail starts nothing new"
key-files:
  created:
    - Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift
    - Tests/TransomMacTests/StageFollowTests.swift
  modified:
    - Sources/TransomMac/Zoom/GestureController.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/TileLayer.swift
    - Sources/TransomMac/ArrangeController.swift
    - Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift
key-decisions:
  - "Spring back marks the display .revealing while it animates, so a move asked for meanwhile queues behind the fade exactly as during a reveal, and isIdle stays false"
  - "followStyle's springBackFade is stored per gesture at stage-in (Active.springBackFade) and passed to StagePanel.springBack(fade:); the snap's crossfade is the stage's existing crossfade flag"
  - "A reversal into a refused direction rebuilds the stage from stillMove (start == end) and follows with hasTarget false; the release springs back and logs the refusal"
  - "Late captures during follow come back as one captureAll batch (1 s deadline) and swap in together; per-window swaps only if UAT shows lag (shortcut comment in ZoomController)"
requirements-completed: [GEST-01, GEST-02, GEST-03]
metrics:
  duration: "~15 min"
  started: 2026-10-30T00:16:30Z
  completed: 2026-10-30T00:31:20Z
actuals:
  tokens: 11959
  tasks: 2
  commits: 2
plan_head_before: e929111dcd2b8f2e2deae780d7348d4a00511b98
plan_head_after: a1a29a3e4e5c80fb8714d351c2694300de884967
---

# Phase 5 Plan 04: Live Follow Summary

**A taken ⌥-pinch, ⌥-pan or no-⌥ wallpaper pinch now drives the Phase 4 stage live. GestureController feeds each sample to a per-gesture GestureRecognizer and aims with `gestureTarget` + `previewMove`. The stage orders in at once in a new `.following` phase, and every tile sits at `followRect` (lerp, overscroll scale about the pinch point, or pan offset) inside a CATransaction with actions off. On release it either commits through an ordinary `zoomTo`, whose `.cameraMove` retargets the following stage, then settles and pushes history, or it springs back with no engine call. All six VM scenarios pass.**

## What was built

- **GestureController**
  - The first sample of a taken sequence picks the display under it (model top-left coordinates), sizes the recognizer from that display's visibleFrame, and keeps the latch point as the pinch point.
  - `.started` aims the gesture. If there is a preview and the controller is idle, it calls `ArrangeController.beginFollow`. `.progress` follows. `.reversed` re-aims and calls `refollow`, falling back to `stillMove` for a refused direction. `.ended` commits with `controller.zoom(to:displayUUID:)` or springs back.
  - After the commit, if the display is still `.following` (zoomTo was refused at the last moment), the stage springs back so it can't stay up.
  - A `recognizerTimer` polls `timeout(now:)` every `GestureTuning.momentumWait` while a gesture is open (05-02 handoff).
  - `finishFollow` runs when the tap ends the sequence, when the main timer expires it, when a new sequence replaces it, and in `stop`. If the recognizer is still open, it decides at that point. A stage that is up always gets resolved.
  - Outcomes are `moved(target)`, `sprangBack`, `refused(reason)` and `tooSmall`. They are stored in `lastGesture` and added to the took line: "took pan #1: ⌥ held, 13 events, 124 ms, moved to node(n3)".
  - The gesture path never calls `dispatchCamera` or `beep`.
- **ZoomController**
  - New `case following` phase, with `beginFollow`, `follow`, `refollow`, `springBack`, `isFollowing`, the `reduceMotion` seam and `onFollowEnded`.
  - `beginFollow` shows tiles from the snapshot cache or fallback tiles and never waits. It then captures the windows that have no snapshot and swaps them in with `setContents`.
  - When `run()` finds `.following`, it takes the existing retarget branch and logs "retarget gesture pinch home → home during following".
  - `captureStart`'s request building moved into `captureRequests` so follow uses the same capture rules.
- **StagePanel / TileLayer**
  - `followRect` is a pure, nonisolated static.
  - `follow` sets every tile with actions disabled.
  - `springBack(fade:)` either moves the tiles back to their start rects over `moveDuration`, then fades out over `revealFade`, or (Reduce Motion) fades the panel out over `moveDuration`.
  - `setContents` swaps a fallback for a snapshot with a `revealFade` CATransition, and updates the stored tile so a crossfade retarget keeps it.
  - StagePanel gained no new duration literals (the `0.25|0.12` count is 2 before and after).
- **ArrangeController**
  - `beginFollow` hides collapsed panels, starts the follow and re-publishes ZoomInput, like `.cameraMove`. `followStage()` exposes the stage.
  - `onFollowEnded` fades the collapsed panels back in and re-publishes.

## Tests

- **Host, headless:** `swift test --filter StageFollowTests` ran **4 tests, passed**. A mutation check (dropping the anchor scale) made `scalesAboutTheAnchor` fail, then the code was restored. A wider host run (`StageFollowTests|GestureTapRulesTests|ZoomOffTests|TileLayerTests|TransomEngineTests|TransomModelTests`) passed 193 + 27 + 686 tests with no "✘". `scripts/check-no-appkit.sh` is OK (45 files). `import ScreenCaptureKit` still appears only in `SnapshotCapture.swift`.
- **VM (Tart pane-test, macOS 15.7.7, display woken before each run):** `scripts/vm-live-test.sh GestureFollowIntegrationTests` ran **6 of 6 passed**.

| Test | Result |
|---|---|
| anOptionPinchInPastHalfZoomsOneLevel | view = the precomputed `gestureTarget(.pinchIn)` (node(n1), contains window 0's leaf), back stack ends `.home`, 0 downstream, window 0 at its view-plan x/width within 2 pt, outcome `.moved` |
| anOptionPinchOutPastHalfGoesHome | from node(leaf): view = `gestureTarget(.pinchOut)` (home on this tree), back stack ends node(leaf) |
| aShortPinchSpringsBackWithoutASettle | Σ +0.2, slow: still home, `lastSettle` unchanged, idle within 1 s, outcome `.sprangBack`, no history |
| anOptionPanPastAThirdMovesToTheNeighbour | 0.4 W with momentum: view = the `Navigator.pan` neighbour, 0 downstream, outcome `.moved` after the momentum tail |
| aShortPanSpringsBack | 0.1 W toward a real neighbour, slow: view unchanged, outcome `.sprangBack` |
| aNoOptionPinchOnWallpaperZooms | no ⌥ on bare wallpaper: view moved in (GEST-03) |

- Guest log (Task 1 acceptance): "took pinch #1: ⌥ held, 12 events, 106 ms, moved to node(n1)", followed by "settle 5 ms: 1 writes, 2 parked". There are also sprang back, pan moved and wallpaper lines.
- VM regression, each suite run on its own: `GestureTapIntegrationTests` 12/12, `ZoomSettleIntegrationTests` 2/2.
- No tap, multitouch device, window or Transom launch ran on the host. The VM was started with `tart run pane-test` and stopped at the end. No fixtures were left over.

## Deviations from Plan

1. **[Rule 1 - Bug] The momentum tail overwrote a committed pan's outcome.** Found in the guest log during Task 2: "took pan … too small" after a pan that moved. The release cleared `follow`, so the momentum samples started a new judgement for the same sequence. Fix: a released follow is kept (`ended = true`) until the tap ends the sequence. The pan test now asserts `.moved` after the tail. Commit a1a29a3.
2. **[Rule 2] A stage can't be left up.** Three cases were added. `stop(reason:)` resolves an open follow (access lost would otherwise leave an opaque, click-taking panel over the screen). A zoomTo refused at release springs the stage back. A reversal into a refused direction rebuilds from `stillMove` instead of keeping the stale preview's tiles.
3. **[Interpretation] API shapes.**
   - `beginFollow(_:gesture:)` reads Reduce Motion through `followStyle(reduceMotion: reduceMotion())` itself, rather than taking `crossfade:` from GestureController. It also carries the gesture kind for the UI-SPEC retarget line.
   - `follow` takes the gesture `direction`, not the axis: the recognizer's axis is private, and the direction implies it.
   - `springBack` takes `fade:` from the per-gesture style.
   - `LastGesture.direction` is optional (a too-small gesture has none), and it also records `seq` and `kind`.
4. **[Test environment] The wallpaper test falls back to any bare wallpaper on the display.** In the VM, TextEdit, Notes and Finder windows (not fixtures) cover the whole Desktop tile, and the live-test rules forbid touching real apps. The test searches the Desktop tile first, then the display. In this run it pinched at (8, 24), the bare strip under the menu bar. GEST-03's rule ("bare wallpaper") is what is tested. The Desktop-tile case specifically is left to UAT.
5. **Task 2 code landed in Task 1's commit.** Spring back, the capture swap and Reduce Motion were written with the follow path, so commit 08ec703 holds them. Commit a1a29a3 holds the headless tests, the extra VM tests and the fix. `Downstream` in GestureTapIntegrationTests is now internal so the new suite can reuse it.
6. **VM suites can't share a run.** Running `GestureFollow|ZoomSettle|GestureTap` in one filter ran the suites in parallel, and their taps took each other's synthetic events (6 failures). Each suite passes when run on its own. Future gates should run event-posting suites one per `vm-live-test.sh` call.

## Known Stubs

None. A refused gesture with no stage (overscroll on a refusal) and a gesture taken during a move (E-03) are plan 05-05's by design. In both cases the gesture is consumed, no stage appears, and the log records the refusal.

## Threat Flags

None. T-05-13: one CATransaction per sample, no capture await before stage-in, no AX in follow. T-05-14: writes happen only through `zoomTo`/settle, and a spring back writes nothing (`lastSettle` unchanged in the VM). T-05-15: only the in-memory SnapshotCapture cache is used.

## Notes for later plans

- 05-05: `GestureController.apply(.started)` is where a refusal (`gesture.refusal`) or a busy controller (`zoomController?.isIdle == false`) currently ends with no stage. `ZoomController.beginFollow` returns false when the display is busy. Overscroll with no target can reuse `stillMove` + `refollow` + `follow(hasTarget: false)`, which reversals already use.
- 05-06: `lastGesture` (seq, kind, direction, outcome) is ready for "Last gesture: …".
- 05-07: multitouch pinch samples can go through the same `feed(_:seq:)` path once they are mapped to `GestureSample`.

## Self-Check: PASSED

- FOUND: Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift, Tests/TransomMacTests/StageFollowTests.swift, Sources/TransomMac/Zoom/GestureController.swift, Sources/TransomMac/Zoom/ZoomController.swift, Sources/TransomMac/Zoom/StagePanel.swift
- FOUND commits: 08ec703, a1a29a3
