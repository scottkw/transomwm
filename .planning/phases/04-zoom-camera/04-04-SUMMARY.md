---
phase: 04-zoom-camera
plan: 04
subsystem: zoom
status: complete
tags: [shell, camera, stage, screencapturekit, core-animation, accessibility, vm]
requires:
  - phase: 04-01
    provides: "StagePanel core, SnapshotCapture (the only ScreenCaptureKit file), GO verdict: the SnapshotCache is mandatory"
  - phase: 04-02
    provides: ".cameraMove / .cameraSettle protocol, SettleTracker, ArrangeController's immediate-settle stub (replaced here)"
  - phase: 04-03
    provides: ".zoomTo(_, displayUUID:, focus:) with a defaulted focus, Arranger.leafNode(of:)"
provides:
  - "ZoomController: capture -> show -> 250 ms move -> .cameraSettle -> SettleTracker -> 120 ms reveal, retarget from presentation rects"
  - "ArrangeController(zoomEnabled:) (default false), lazy zoomController, frameApplied/displaysChanged/windowDestroyed forwarding, zoom(to:displayUUID:)"
  - "TransomMacApp passes the zoomEnabled preference (ZoomController.enabledKey, default on)"
  - "TileLayer (snapshot / app-colour fallback), AppColor, SnapshotCache (128 MB LRU) inside SnapshotCapture"
  - "Screen Recording explainer (once ever), silent revoke fallback, capture-failing state, refresh after reveal"
  - "ZoomCopy: explainer, reveal announcements, capture Debug states and log lines"
  - "Public-to-04-05 ZoomController API: captureState, lastSettle, cacheStats, purge(), onRevealed, isIdle"
affects: [04-05, 04-06, 04-07, 04-08]
estimate:
  tokens: 110000
  tasks: 3
actuals:
  tokens: 21000
  tasks: 3
  commits: 5
plan_head_before: 7f069b7cce4633ffd4ed98e81487bd35c5600c51
plan_head_after: 25d67f64d31829a782cb6303f277f6e066f84e1a
tech-stack:
  added: []
  patterns:
    - "One Active record per display (phase capturing/moving/settling/revealing); stale animation completions are ignored by move ID"
    - "beginSettle(displayUUID:moveID:writes:) runs between the engine's settle and system.perform, so the tracker knows every write before it goes out"
    - "TileLayer bounds are centred on (0,0), so a fallback's icon and capsule stay centred while the bounds animate"
    - "Every successful capture goes to the cache inside SnapshotCapture.capture, so late results are kept without extra plumbing"
    - "Live suites that run beside others touch NSApplication.shared first (CGS_REQUIRE_INIT race)"
key-files:
  created:
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Zoom/TileLayer.swift
    - Sources/TransomMac/Zoom/AppColor.swift
    - Sources/TransomMac/Shell/ZoomCopy.swift
    - Tests/TransomMacTests/AppColorTests.swift
    - Tests/TransomMacTests/ZoomCopyTests.swift
    - Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/SnapshotCaptureIntegrationTests.swift
  modified:
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/SnapshotCapture.swift
    - Sources/TransomMac/Displays.swift
    - Sources/TransomMac/Overlay/Toast.swift
    - Sources/TransomMac/Overlay/PreviewPanel.swift
    - Sources/transom-zoom-spike/main.swift
key-decisions:
  - "beginSettle takes the move ID as well as the display (plan said beginSettle(displayUUID:writes:)): a settle answered after a retarget must not attach its writes to the new move"
  - "A move asked for during the 120 ms reveal fade is queued and starts when the fade ends (the retarget rule covers capture, move and settle only)"
  - "The fallback's icon and title capsule are centred as one group, so the UI-SPEC's fit rule (icon + 8 + capsule + 32 tall) leaves 16 pt clearance on each side"
  - "Capture size is min(max(start, end), the window's own frame) x backingScaleFactor; for windows visible at the start that is their current size"
  - "The first move after launch has no shareable-content list yet, so it shows fallbacks; the post-reveal refresh fills the cache (SCShareableContent stays off the critical path, 04-SPIKE G8)"
  - "Requirement IDs ZOOM-01/02/05/07 are shared with 04-05..04-08, so they are deferred, not marked complete here"
requirements-completed: []
coverage:
  - id: D1
    description: "A zoom to one of three docked windows animates on the stage, writes once at settle, reveals after the read-backs, and zooming home puts every window back"
    requirement: ZOOM-07
    verification:
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift#zoomToOneWindowAndBackHome (VM)"
        status: pass
    human_judgment: false
  - id: D2
    description: "App colour: dominant hue bucket, filters, monochrome and empty fallbacks, per-bundle cache"
    requirement: ZOOM-05
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/AppColorTests.swift#AppColorTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "SnapshotCache: 128 MB LRU of decoded bytes, recency on read, remove and purge"
    requirement: ZOOM-05
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/AppColorTests.swift#SnapshotCacheTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Explainer copy, reveal announcements with explicit plurals, capture Debug states and log lines"
    requirement: ZOOM-05
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/ZoomCopyTests.swift#ZoomCopyTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Live captures: requested pixel size, parked window answers within 1.1 s, captureAll within 120 + 50 ms"
    requirement: ZOOM-05
    verification:
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/SnapshotCaptureIntegrationTests.swift (VM)"
        status: pass
    human_judgment: false
  - id: D6
    description: "ScreenCaptureKit only in SnapshotCapture.swift"
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/NoScreenCaptureTests.swift"
        status: pass
    human_judgment: false
  - id: D7
    description: "Fallback tile legibility across pale, dark and saturated app colours, light and dark mode (UI-SPEC backstop)"
    requirement: ZOOM-05
    verification:
      - kind: manual_procedural
        ref: "VM UAT with Screen Recording denied (04-08 / verify-work)"
        status: unknown
    human_judgment: true
  - id: D8
    description: "Reduce Motion crossfade with no tile moving or scaling (UI-SPEC backstop)"
    verification:
      - kind: manual_procedural
        ref: "VM UAT with TRANSOM_STAGE_CAPTURABLE=1 and Reduce Motion on"
        status: unknown
    human_judgment: true
duration: 29min
completed: 2026-10-28
---

# Phase 4 Plan 04: Shell Camera (Stage, Snapshot Cache, Settle) Summary

**Zoom now works on screen in the VM: each `.cameraMove` captures the visible windows (4 at a time, 120 ms budget), shows a stage with a tile exactly over every window, animates it for 250 ms, feeds `.cameraSettle`, waits for every read-back + 50 ms (cap 1500 ms) and fades out over 120 ms. Tiles are fresh snapshots, cached snapshots or app-colour fallbacks. Screen Recording is asked for at most once, and a revoke falls back silently.**

## Performance

- **Duration:** 29 min (2026-10-28T14:44Z to 15:13Z)
- **Tasks:** 3 (Task 1 tracer, Tasks 2 and 3 RED then GREEN)
- **Files:** 8 created, 8 modified

## Accomplishments

- **ZoomController** (`Sources/TransomMac/Zoom/ZoomController.swift`). One `StagePanel` per display, made on first use. There is one `Active` record per display, with phase capturing, moving, settling or revealing.
  - A move arriving during capture, move or settle retargets the stage from the tiles' presentation rects.
  - A move arriving during the reveal fade waits for the fade to end.
  - `beginSettle` starts a `SettleTracker` and a `WakeTimer` at `revealAt()`. `frameApplied` re-arms the timer.
  - Logs (category `camera`, all `.public`, no titles): "move …", "settle {ms} ms: {w} writes, {p} parked, {u} unparked, 0 collapsed", the cap line and the over-budget line.
- **ArrangeController**:
  - `init(..., zoomEnabled: Bool = false)` feeds `.zoomEnabled(true)` after the first inventory, and only when the flag is on.
  - The `zoomController` is lazy, so with zoom off no stage or capture object exists.
  - The engine's settle effects go through `beginSettle` before `system.perform`.
  - `frameApplied`, `displaysChanged` and `windowDestroyed` are forwarded to the controller.
  - `public func zoom(to:displayUUID:)`.
  - If a `.cameraMove` arrives with zoom off, it logs a fault and settles at once.
- **TransomMacApp** passes the `zoomEnabled` preference (default on).
- **TileLayer and StagePanel**:
  - Snapshots are drawn aspect-fill and top-anchored.
  - Fallbacks have the app colour, a 12 pt radius and a 1 pt `separatorColor` border. The icon is `min(64, shorter side − 32)` and hidden below 16 pt. The title capsule is Body text, `byTruncatingMiddle`, with 8/4 padding and a `windowBackgroundColor` fill, and shows only when it fits.
  - Colours are re-resolved on an appearance change and on `systemColorsDidChangeNotification`.
  - The crossfade is chosen from `accessibilityDisplayShouldReduceMotion` at each move start.
- **AppColor** follows the UI-SPEC recipe exactly and caches one colour per bundle ID.
- **SnapshotCache** (inside SnapshotCapture.swift):
  - An LRU of `w*h*4` bytes, capped at `128 * 1024 * 1024`.
  - Every successful capture, late ones included, lands in it.
  - A window's entry is dropped when the window closes.
  - The refresh after each reveal re-reads the shareable content, prunes windows that are gone and re-captures the visible windows at their new size.
- **Permissions and accessibility**:
  - The grant is checked at every move start and logged the first time and on every change. A revoke is logged once per session and falls back silently.
  - Three consecutive failures while granted set `captureState = .failing` and log once. Any success clears it.
  - The modeless explainer shows once ever, after a reveal and never during a move or drag. The flag is saved when it appears. "Not Now" re-activates the previously frontmost app.
  - Every reveal is announced through `postAnnouncement`.

## API for 04-05 / 04-06

`ZoomController` is internal and reached as `ArrangeController.zoomController` (nil until the first move):
- `captureState: CaptureState` (`.previews`, `.noPermission`, `.failing`). It reflects the last move start and reads `.noPermission` before any move. Map it to `ZoomCopy.capturePreviews` / `captureNoPermission` / `captureFailing`.
- `lastSettle: (ms: Int, windows: Int)?`, which is nil before the first settle.
- `cacheStats: (windows: Int, bytes: Int)`.
- `purge()`: empties the cache and tears down every stage. Call it on Turn Off Zoom.
- `onRevealed: ((displayUUID, CameraMove) -> Void)?` and `isIdle`.
- `ZoomController.enabledKey` (`"zoomEnabled"`) and `explainerShownKey` (`"zoomPreviewExplainerShown"`).

## Settle times seen in the VM (3 fixture windows, write path only)

| Run | Zoom in | Zoom home |
|---|---|---|
| Task 1 runs | 77, 6, 1243\*, 7 ms | 27, 49, 17, 7 ms |
| Task 3 runs | 21, 5, 12, 6, 102, 29 ms | 172, 8, 5, 36, 88, 47 ms |

\* The 1243 ms run happened while the VM's SSH session reported a `visibleFrame` that includes the menu bar. The zoomed window was planned under the menu bar, macOS pushed it down 17 pt, and its read-back came late. Every other settle was under 200 ms.

Captures in the VM: `captureAll` of 6 fixture windows returned 1–4 images within the budget (131–138 ms of wall time, under the 170 ms test bound). A parked window captured whole in about 38 ms.

## Task Commits

1. **Task 1 (tracer): stage camera moves end to end**: `74b675c` (feat)
2. **Task 2: tiles, cache, Reduce Motion**: RED `20e7147` (test), GREEN `a880579` (feat)
3. **Task 3: explainer, refresh, announcements**: RED `bbf9e93` (test), GREEN `25d67f6` (feat)

## TDD

- **Task 2 RED (`20e7147`):** the build failed with "cannot find 'RGBA'" / "cannot find 'SnapshotCache'". **GREEN:** 14/14 (AppColorTests 8, SnapshotCacheTests 6), then 16 with NoScreenCaptureTests.
- **Task 3 RED (`bbf9e93`):** the build failed with "cannot find 'ZoomCopy'". **GREEN:** 21 tests in 4 suites on the `ZoomCopyTests|AppColorTests|NoScreenCaptureTests` filter.
- Tracer gate: the Task 1 `<verify>` (full headless suite plus the VM ZoomSettle suite) passed before expansion.

## Verification

- Full headless `swift test`: 193 + 221 + 46 + 630 = **1090 Swift Testing tests passed**, with no "✘". FreezeTestTests passed in this run too.
- Task 2 filter: 16 tests in 3 suites passed. Task 3 filter: 21 tests in 4 suites passed.
- VM, `scripts/vm-live-test.sh "SnapshotCaptureIntegrationTests|ZoomSettleIntegrationTests"`: 4 tests in 2 suites passed in 3 consecutive runs after the final fix, with no skips.
- `scripts/check-no-appkit.sh`: OK (44 files). NoScreenCaptureTests passes.
- Acceptance greps:
  - `zoomController` in ArrangeController: 6
  - `zoomEnabled` in TransomMacApp: 1
  - `SettleTracker` in ZoomController: 3
  - `byTruncatingMiddle`: 1
  - `128 \* 1024 \* 1024`: 1
  - `presentation()` in StagePanel: 2
  - `accessibilityDisplayShouldReduceMotion` in StagePanel: 1
  - Hex literals in TileLayer/AppColor: 0 / 0
  - The explainer string in ZoomCopy: 1
  - `import AppKit` in ZoomCopy: 0
  - `explainerShownKey` in ZoomController: 3
  - `privacy: .public` in ZoomController: 13, with 0 on any line containing `title`
- No existing `#expect` was removed or rewritten.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A stale settle could attach its writes to a retargeted move**
- **Found during:** Task 1
- **Issue:** `beginSettle(displayUUID:writes:)` cannot tell an old move's settle from the current one's. After a retarget, the old settle (which the engine answers with nothing) would have started the tracker for the new move.
- **Fix:** the signature is `beginSettle(displayUUID:moveID:writes:)`, and it acts only for the current move in phase `.moving`. Stale animation completions are ignored the same way.
- **Commit:** 74b675c

**2. [Rule 1 - Bug] A move during the reveal fade would have been hidden by the fade's completion**
- **Found during:** Task 1
- **Issue:** `fadeOut`'s completion orders the panel out. A new `show` during the fade would be ordered out with it.
- **Fix:** a move that arrives while revealing is queued and starts when the fade ends (at most 120 ms).
- **Commit:** 74b675c

**3. [Rule 3 - Blocking] Small additions outside the plan's file list**
- `Displays.screen(uuid:)`, to make a stage on the right screen.
- `ToastPresenter.bringFront()` and `PreviewPresenter.bringFront()`, for the `bringNoticesFront` closure.
- `transom-zoom-spike/main.swift`: one line now swaps a tile's start and end through the public vars, because `StageTile` no longer exposes `image`/`fill`. Its public `init(id:start:end:image:fill:)` is kept for the spike.
- **Commits:** 74b675c, a880579

**4. [Rule 1 - Test environment] VM SSH-session geometry and a CoreGraphics init race in the live suites**
- **Issue 1:** in the guest's SSH session, `NSScreen.visibleFrame` sometimes includes the 25 pt menu bar and sometimes doesn't, and it can switch mid-run. The engine then re-plans in the new area, which is correct. The test's exact `visibleFrame`/tile comparisons failed because of this, not because of product behaviour.
- **Fix 1:** horizontal geometry is still checked exactly. Vertical checks use the Arranger's current visible frame and allow macOS to push a window down by up to 32 pt.
- **Issue 2:** once, `Assertion failed: (did_initialize), CGS_REQUIRE_INIT` killed the run when both new suites started together in a process with no NSApplication.
- **Fix 2:** both suites touch `NSApplication.shared` in `init`. After that, 3/3 runs were clean.
- **Commits:** 74b675c, 25d67f6

**5. [Test precision] The zoomed window fills `visibleFrame` less resolve's 8 pt outer gap**
- The plan said "within 2 pt of the visibleFrame". 04-02 already records that the stay tile ends at the visibleFrame inset by the 8 pt gap, so the test checks that.

---

**Total deviations:** 2 correctness fixes, 1 group of small blocking additions, 2 test-environment adaptations. **Impact:** none on scope.

## Known Stubs

- `Sources/TransomMac/Zoom/ZoomController.swift`, the settle log line and `finishReveal`: the collapsed count is always 0. The engine does not expose the collapsed windows of a view yet. Nothing feeds `camera.collapsible` before 04-07, so 0 is currently correct. 04-07 must pass the view's collapsed count to `ZoomCopy.revealAnnouncement` and the settle log. Both places are marked `shortcut:`.
- `captureState` reads `.noPermission` until the first move. 04-05's Debug line should treat "no move yet" as unknown, or call a fresh preflight.

## Threat Flags

None new. T-04-13:
- Snapshots stay in memory: the cache is an LRU capped at 128 MB.
- A window's entry is removed when it closes or is gone from the shareable list.
- `purge()` exists for zoom off.
- No image or title is logged or written.

T-04-15: the explainer flag is saved when the alert appears, and there is no re-prompt path. T-04-16: the 120 ms budget, 1 s per-capture timeout and concurrency 4 are unchanged, and failures count toward `.failing`.

## Next Phase Readiness

- 04-05 can build the Debug line and Turn Off Zoom (`purge()` plus `.zoomEnabled(false)`) on the API above.
- 04-06 drives pointer input through `zoom(to:displayUUID:)`.
- Production now creates `ArrangeController` with zoom on by default. No shipped trigger sends a camera move yet (hotkeys and menu come in 04-05). At home every window is in view, so widening never fires.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Zoom/ZoomController.swift, Sources/TransomMac/Zoom/TileLayer.swift, Sources/TransomMac/Zoom/AppColor.swift, Sources/TransomMac/Shell/ZoomCopy.swift, Tests/TransomMacTests/AppColorTests.swift, Tests/TransomMacTests/ZoomCopyTests.swift, Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift, Tests/TransomMacIntegrationTests/SnapshotCaptureIntegrationTests.swift
- FOUND commits on HEAD: 74b675c, 20e7147, a880579, bbf9e93, 25d67f6
- Measured commits: `git rev-list --count 7f069b7..HEAD` = 5

---
*Phase: 04-zoom-camera*
*Completed: 2026-10-28*
