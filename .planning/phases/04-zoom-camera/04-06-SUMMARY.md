---
phase: 04-zoom-camera
plan: 06
subsystem: zoom
status: complete
tags: [shell, event-tap, pointer-input, keyboardshortcuts, core-animation]
requires:
  - phase: 04-03
    provides: "Arranger.shownLeafRects, leafNode(of:), Navigator.rectTarget / target / ancestors, .zoomTo(_:displayUUID:focus:), .camera(_:displayUUID:focused:pointer:)"
  - phase: 04-04
    provides: "ZoomController (onRevealed, isIdle), StagePanel, TileLayer.cornerRadius"
  - phase: 04-05
    provides: "camera dispatch on the pointer's display, pointerDisplay(), zoomTitleBarDoubleClick preference (ShortcutsModel.doubleClickKey)"
provides:
  - "ZoomTapState + ZoomTapRules (pure consume/pass: ⌘⇧ band, pick click, title-bar double-click, re-post tag, needsWindow)"
  - "InputTap: TapEvent.Kind.zoom(ZoomTapRules.Kind), TapEvent.clickState, setZoomState(_:), tagged re-posts pass untouched"
  - "ZoomInput: publish(), band tracking/target/drawing, temporary Esc streams, ⌘⇧-click re-post, pick mode, title-bar and Desktop double-clicks, stage clicks, reset(reason:)"
  - "PreviewPresenter: showBand(_:target:on:), hideBand(on:), showPickRing(_:radius:on:), hidePickRing(on:)"
  - "PreviewStyle.band / rectTarget / pickRing recipes"
  - "StagePanel.onTileClick, ZoomController.onTileClick"
  - "ArrangeController: zoom(to:displayUUID:focus:), camera(_:displayUUID:focused:pointer:), trackedWindow(cgID:) internal, previews internal read"
  - "ZoomCopy: zoomCanceled and the zoomInput log strings"
affects: [04-07, 04-08]
tech-stack:
  added: []
  patterns:
    - "Zoom tap state published whole behind an OSAllocatedUnfairLock, read by a pure rule in the callback (the green-button pattern)"
    - "Temporary Carbon hotkeys through KeyboardShortcuts.events(for:) task lifetimes: register on start, unregister on cancel"
    - "Pick mode keyed to the camera move id of the zoom-out that made it, so a retargeted move never starts it"
key-files:
  created:
    - Sources/TransomMac/Input/ZoomTapRules.swift
    - Sources/TransomMac/Zoom/ZoomInput.swift
    - Tests/TransomMacTests/ZoomTapRulesTests.swift
  modified:
    - Sources/TransomMac/Input/InputTap.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overlay/PreviewPanel.swift
    - Sources/TransomMac/Overlay/PreviewStyle.swift
    - Sources/TransomMac/Shell/ZoomCopy.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Tests/TransomMacTests/PreviewStyleTests.swift
    - Tests/TransomMacTests/ZoomCopyTests.swift
key-decisions:
  - "Every mouse-down re-decides the zoom swallow, so a lost mouse-up can never trap the next click (T-04-20)"
  - "Clicks (pick, title bar) are taken only unmodified and only when the topmost window at the point is the tile's own"
  - "A tagged re-post returns from the callback before any rule and is not fed to the Arranger"
  - "armed = zoom on && ready && not paused && ZoomController idle; the desk check is a published list of desk display frames"
  - "Desktop double-click is decided on main after the event (never taken); unknown Finder AX roles count as icons, so the failure mode is a missed frame, not a frame while opening an icon"
  - "Pick mode starts only when the reveal's move id matches the Zoom Out to All / One Level dispatch that produced it"
requirements-completed: []
estimate:
  tokens: 100000
  tasks: 3
actuals:
  tokens: 18178
  tasks: 3
  commits: 6
plan_head_before: 1f69712f320d524589622954310d16c660dc92f4
plan_head_after: f7dd57df082f190c56eb91155026bfdd8080e6bc
duration: 14 min
completed: 2026-10-28
---

# Phase 4 Plan 06: Pointer Input for the Camera Summary

**⌘⇧-drag rectangle zoom through the existing event tap (pure ZoomTapRules, rubber band and accent target preview, Esc cancel via temporary Esc hotkeys, tagged ⌘⇧-click re-post), pick mode after zooming out, stage tile clicks, and title-bar / Desktop double-click framing.**

## Performance

- Duration: about 14 min
- Tasks: 3 of 3 (Task 1 a tracer; its gate re-ran the automated verify and passed before expanding)
- Files: 12 (3 created, 9 modified)

## Task Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | 97c7d4a | test(04-06): add failing ZoomTapRules band sequence tests |
| 1 GREEN | 246a397 | feat(04-06): ⌘⇧-drag rectangle zoom through the event tap |
| 2 RED | 3bcdb15 | test(04-06): add failing band style, cancel copy and Esc-cancel sequence tests |
| 2 GREEN | d283046 | feat(04-06): rubber band and target preview, Esc cancel, ⌘⇧-click re-post |
| 3 RED | ba37391 | test(04-06): add failing pick click and title-bar double-click rule tests |
| 3 GREEN | f7dd57d | feat(04-06): pick mode, stage tile clicks, title-bar and Desktop double-clicks |

## TDD

- Task 1: RED `97c7d4a` (ZoomTapRulesTests failed to compile: no `ZoomTapState` / `ZoomTapRules`), GREEN `246a397` (19 tests in 3 suites pass with GreenButtonHitTests and TopmostWindowTests).
- Task 2: RED `3bcdb15` (ZoomCopy and PreviewStyle members missing; build failed), GREEN `d283046` (28 tests in 4 suites pass). The two new rules tests and ZoomInputGeometryTests already passed at RED, because Task 1 had built that behaviour; they pin it.
- Task 3: RED `ba37391` (5 failing expectations in pick and title-bar tests), GREEN `f7dd57d`.
- Expectation guard: `git diff 97c7d4a^ -- Tests/ | grep -c '^-.*#expect'` printed 0.

## Verification

- Task 1 gate: `swift test --filter "ZoomTapRulesTests|GreenButtonHitTests|TopmostWindowTests"`: 19 tests passed, no ✘.
- Task 2 gate: `swift test --filter "ZoomTapRulesTests|ZoomCopyTests|PreviewStyleTests|ZoomInputGeometryTests"`: 28 tests passed, no ✘.
- Task 3 gate / full suite: `swift test`: 193 + 257 + 46 + 632 = 1128 Swift Testing tests passed, no ✘, ZoomTapRulesTests ran (XCTest bundles: 0, as before). The known FreezeTestTests flake did not fire this run.
- Acceptance greps: `ZoomTapRules.decide` in InputTap.swift 1; `keyDown` in InputTap.swift 0 (mask unchanged); `rectTarget` in ZoomInput.swift 2; `KeyboardShortcuts.events(for:` 1; option+escape lines 0; `eventSourceUserData` 1; `"Zoom canceled"` 1; `addGlobalMonitorForEvents` 1; `frameWindow` 1; `frameDesktop` 1; `onTileClick` in StagePanel.swift 2.
- `scripts/check-no-appkit.sh` passes; ScreenCaptureKit is still imported only in SnapshotCapture.swift.
- Headless only. No live or VM run in this plan.

## Deviations from Plan

### Auto-fixed / adjusted

**1. [Rule 2 - Correctness] `ZoomTapState.deskDisplays` added, `desktopRects` dropped**
- **Found during:** Task 1
- **Issue:** "a desk on the pointer's display" has to be known in the tap at mouse-down, and the pointer moves too often to republish `armed` for it. Desktop double-clicks are never taken, so the tap never needs Desktop rects.
- **Fix:** The state carries the frames of displays whose shown Space has a desk, and the rule checks the press point against them. The Desktop rect is computed on main from `shownLeafRects` only when a passing double-click arrives.
- **Files:** ZoomTapRules.swift, ZoomInput.swift. **Commit:** 246a397, f7dd57d

**2. [Simplification] `TapEvent.Kind.zoom(ZoomTapRules.Kind)` instead of three cases; `Decision.consume(Kind?)`**
- One case carries the rule's own kind, so the callback needs no mapping. The drags and release of a taken click report nothing (`consume(nil)`).
- **Commit:** 246a397

**3. [Simplification] No `moveStarted` / `revealed` in-progress flag**
- `armed` reads `ZoomController.isIdle`, and `publish()` runs after `.cameraMove`, after each reveal and after `displaysChanged`. A move whose display disappears therefore cannot leave input disarmed for good.
- **Commit:** 246a397

**4. [Rule 2 - Safety] Band and pick state reset when the tap goes down or zoom turns off**
- `ZoomInput.reset(reason:)` runs from `stopTap`, from the watchdog's take-down and from Turn Off Zoom. A passing mouse-down also ends a band whose release was lost. No Esc hotkey can outlive its band or pick mode (T-04-20, T-04-22).
- **Commits:** d283046, f7dd57d

**5. [Design choice] Pick mode is keyed to the move id**
- Instead of remembering "the last command", `dispatchCamera` records the `.cameraMove` id that Zoom Out to All / One Level produced. Only that move's reveal starts pick mode, so a retarget or a refused zoom-out never starts it.
- **Commit:** f7dd57d

**6. [Rule 1 - Latency] Desktop double-click check runs in its own task**
- Finder's AX hit test (0.25 s timeout) runs detached and off the tap reader, so it never holds up the Arranger's view of the press.
- **Commit:** f7dd57d

**7. [Scope] Pick tiles cover docked windows only**
- Collapsed blocks get their panels in 04-07, so the CG topmost-window check cannot match them yet. Their clicks pass through for now (marked with a `shortcut:` comment in ZoomInput.revealed).

**8. [Addition] Clicks are taken only unmodified**
- Pick clicks and title-bar double-clicks require no ⌘⇧⌃⌥. A modified click always passes (⌘⇧ is the band). This is the conservative reading; the UI-SPEC is silent on modifiers for title-bar double-clicks.

**9. [Addition] PreviewStyle gains the band, target and ring recipes**
- `PreviewStyle.swift` was not in `files_modified`. The recipes went there so PreviewStyleTests cover them, and so they share the existing Increase Contrast rule (refactored into `contrasted(_:)`).

## Known Stubs

- `Sources/TransomMac/Zoom/ZoomInput.swift` `revealed(displayUUID:move:)`: collapsed blocks are not pick targets until 04-07 adds their panels (`shortcut:` comment). Intentional, and 04-07 resolves it.

## Notes for later plans and UAT

- **RESEARCH A4 is not observed yet.** No desktop-icon AX role was recorded, because this plan ran headless only. `ZoomInput.isDesktopItem` treats only AXScrollArea, AXGroup, AXWindow and AXApplication as wallpaper. The debug log line "desktop double-click hit {role} / {subrole}" records the real roles in VM UAT (`log stream --level debug --predicate 'category == "zoomInput"'`).
- UAT backstops still open: ⌘⇧-click on a Safari link opens a new tab (re-post); a double-click on a desktop icon opens it without framing; a double-click on bare wallpaper in the Desktop tile frames the Desktop.
- Not yet checked live:
  - the stage's first-click delivery (`acceptsFirstMouse` on a never-key non-activating panel)
  - whether a CGEvent posted at `.cgSessionEventTap` passes back through Transom's own session tap, so that the tag matters
  - the global `.mouseMoved` monitor for the hover ring
- 04-07: `ZoomTapState.pickTiles` is keyed by CG window. A collapsed-block panel can call into `ZoomInput` (via a `pickClick`-style entry point) when clicked in pick mode.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: input-injection | Sources/TransomMac/Zoom/ZoomInput.swift | Synthetic mouse down/up posted to the session (already in the plan's register as T-04-21; mitigated by tag + exact point and flags) |
| threat_flag: ax-read | Sources/TransomMac/Zoom/ZoomInput.swift | New AX hit test of Finder at a point on a Desktop double-click, with a per-element 0.25 s timeout, off main and off the tap |

## Self-Check: PASSED

- Files: ZoomTapRules.swift, ZoomInput.swift, ZoomTapRulesTests.swift and this SUMMARY exist.
- Commits: 97c7d4a, 246a397, 3bcdb15, d283046, ba37391, f7dd57d are all ancestors of HEAD.
