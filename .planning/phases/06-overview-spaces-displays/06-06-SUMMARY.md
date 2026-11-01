---
phase: 06-overview-spaces-displays
plan: 06
subsystem: overview
status: complete
tags: [overview, stage-panel, spaces-strip, hotkey, url-scheme, shortcuts-window, over-01]
requires:
  - phase: 06-01
    provides: "SpacesSnapshot (spaces per display, current, kind, separateSpaces)"
  - phase: 06-02
    provides: "AXWindowSystem.spacesSnapshot, OverviewCopy"
  - phase: 06-05
    provides: "displays-changed / settling wiring where the overview now interrupts"
provides:
  - "CameraCommand.overview on ⌃⌥⌘A (KeyboardShortcuts name showOverview), routed in the shell; the Arranger faults if it ever gets it"
  - "OverviewLayout (Engine, pure): main area, strip band, thumbnails (clamp, shrink-to-fit, 16 cap), labels, mini tiles, full-screen tiles, empty capsule, item(at:)"
  - "OverviewController: open/dismiss/toggle/interrupt, per-display StagePanels, 120 ms captures through the zoom snapshot cache, temporary Esc, test-visible openPanels and tileCount(display:)"
  - "StagePanel overview overlay: showOverview(_:) / clearOverview()"
  - "Arranger.homeView(on:) for a zoomed display's home tiles and collapsed blocks"
  - "Show Overview in Zoom menu (first), transom://overview, Shortcuts row (first of 45) and Zoom footer"
affects: [06-07, 06-08, 06-09]
tech-stack:
  added: []
  patterns:
    - "The overview reuses ZoomController's capture, cache and tile contents through small internal accessors (one snapshot cache for moves and the overview)"
    - "Live tests that need a Carbon hotkey pump AppKit's queue with NSApp.nextEvent/sendEvent: the test helper runs no NSApplication"
key-files:
  created:
    - Sources/TransomEngine/OverviewLayout.swift
    - Sources/TransomMac/Overview/OverviewController.swift
    - Tests/TransomEngineTests/OverviewLayoutTests.swift
    - Tests/TransomMacIntegrationTests/OverviewIntegrationTests.swift
  modified:
    - Sources/TransomEngine/Command.swift
    - Sources/TransomEngine/Navigator.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/TransomURL.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Input/Hotkeys.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
    - Sources/TransomMac/Shell/CommandMenu.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Tests/TransomEngineTests/ArrangerCameraTests.swift
    - Tests/TransomEngineTests/TransomURLTests.swift
    - Tests/TransomMacTests/HotkeyTableTests.swift
    - Tests/TransomMacTests/ShortcutsModelTests.swift
    - Tests/TransomMacTests/CommandMenuTests.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
key-decisions:
  - "Shrink-to-fit stops at the factor that fits (16 Spaces on 1280×800 → 38.75 pt), with 32 pt only as the floor; the plan's '16 Spaces shrink to 32 pt' bullet is the UI-SPEC's worst-case proof, not the result"
  - "Show Overview's availability lives in Arranger.availability: zoom on and ready, allowed while paused, no pointer display needed"
  - "The overview has its own StagePanel per display (not ZoomController's), sharing ZoomController's snapshot cache and tile contents"
  - "Hidden-Space mini tiles come from Planner.plan over the stored desk (docked) plus present floaters' frames; full-screen Spaces from tracked windows whose Space set holds that Space"
requirements-completed: []  # OVER-01's "clicking a window goes to it" lands in 06-07..06-09 (same as 06-01/06-02)
duration: ~20min
completed: 2026-10-31
metrics:
  duration: "~20 min"
  started: 2026-10-31T18:57:00Z
  completed: 2026-10-31T19:18:00Z
actuals:
  tokens: 19900
  tasks: 3
  commits: 4
plan_head_before: 54ad809e2ded1983fb2fb808f5e751cd942a43cc
plan_head_after: 344780d74046b24b401d4354cb4139295196e4f3
---

# Phase 6 Plan 06: Show Overview Summary

**⌃⌥⌘A (also the Zoom menu and `transom://overview`) opens a stage panel on every display that isn't showing a full-screen Space. Each panel shows that display's current-Space windows moving from where they are into a scaled main area, under a Spaces strip of wallpaper thumbnails with mini tiles and "Desktop n" labels. Show Overview again, Esc, or any interruption closes it. Real windows never move.**

## What was built

- **Command path (D-01):** `CameraCommand.overview`, `KeyboardShortcuts.Name.showOverview` on ⌃⌥⌘A. Because it goes through `.camera`, it joins `Hotkeys.zoomNames`, so turning zoom off disables it with the other zoom hotkeys. `dispatchCamera` handles it after the zoom-off guard. Without Accessibility it beeps and announces "Transom needs Accessibility access"; from a URL it only logs. Otherwise it toggles the overview. The Arranger never acts on `.overview`: `camera()` faults if it ever receives it.
- **OverviewLayout (Engine, pure, AppKit-free):**
  - Thumbnails are clamp(visibleFrame.height × 0.12, 64, 112) tall, with the display's aspect, 16 pt apart, in a centred row.
  - When the row doesn't fit visibleFrame.width − 48, every thumbnail shrinks by one factor, never below 32 pt. Only the first 16 Spaces are shown.
  - Band height = 16 + h + 8 + 21 + 16. Each label sits 8 pt below its thumbnail, 21 pt high.
  - Main area: visibleFrame minus the band, inset 24 pt (24 pt on all sides when the strip is hidden). Windows are scaled uniformly and centred, back to front. A zoomed display uses home-view rects.
  - Mini tiles are scaled into their thumbnail. A full-screen Space gets one mini tile that fills its thumbnail. The current thumbnail shows the current windows.
  - When the current Space has no windows, the empty capsule is centred in the main area. It is not an `item(at:)` hit.
  - The strip is hidden when the lookup is off, and drawn only on the main display when Spaces are shared.
- **OverviewController:**
  - Builds inputs from the Arranger. Current-Space windows must be tracked, present, not excluded and on screen, ordered back to front by the CG list. Hidden Spaces use planned desks, and full-screen Spaces use tracked windows' Space sets.
  - Captures through `ZoomController.overviewImages` (same permission check, 120 ms budget and cache). Each tile then uses its capture, else its cached snapshot, else the fallback, or a collapsed block for a home-view collapsed window.
  - Shows the panels, animates them over 250 ms, and fades the strip in.
  - Esc is a temporary `KeyboardShortcuts.events(for: Shortcut(.escape))` stream, cancelled on every close.
  - Dismiss reverses the animation, then fades out over 120 ms; under Reduce Motion it only fades, over 250 ms. Interrupt fades out over 120 ms straight away.
  - Logs `open {trigger}: {d} displays, {n} tiles, {m} snapshots, {k} fallback, {ms} ms` and `dismiss: {reason}` under category `overview`.
- **ArrangeController:**
  - Creates the controller lazily.
  - Interrupts the overview on `.spaceChanged`, `.windowFocused`, `.displaysChanged` (which also drops its panels), `.sessionPaused(true)` and any other command.
  - On open it ends pick mode and hides the collapsed-block panels; on close it fades them back in.
  - Zoom off closes the overview and drops it.
- **StagePanel overlay:**
  - A layer group at `zPosition` 1 holding wallpaper thumbnails (8 pt radius). The current Space gets a 2 pt `labelColor` border at 85%, or 100% with Increase Contrast; the others get a 1 pt separator.
  - Mini tiles (snapshot, else app colour and icon, radius max(2, 12 × scale)).
  - Label capsules (11 pt, semibold for the current Space, middle truncation) and the Body empty capsule in `secondaryLabelColor`.
  - Rebuilt on appearance change; fades in 0→1 on open and out on dismiss.
- **Surfaces (Surface 4):** Zoom ▸ Show Overview is the first item after the header. `transom://overview` is on the whitelist. The Shortcuts window lists Show Overview first of 45 rows, with the footer "With Replace Mission Control on, the Mission Control keys also show the overview." Restore Defaults already resets every `Hotkeys.entries` name.

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 (tracer) | 0f2e29b | Command, hotkey, shell routing, main-area layout, OverviewController, VM live test |
| 2 (tdd) | 5a3cf50 | Full OverviewLayout, homeView, StagePanel overlay, overlay copy |
| 3 (tdd) | fd8ba83 | URL, menu O1 and its availability, Shortcuts row and footer |
| fix | 344780d | Refuse when every display is in full screen (no Esc held with nothing shown) |

## Verification

- **Task 1 tracer gate:** `swift build --build-tests` passed, and `scripts/vm-live-test.sh OverviewIntegrationTests` passed in the VM (1 test). It opened a panel on every display with ≥ 2 tiles on the main display, the fixture frames didn't change, toggling closed it, and Esc closed it. The tracer feedback gate (interactive, end-of-phase, automated-only verify) re-ran the verify end to end and it passed before expanding. The VM suite was re-run after Task 2 with the strip drawn and passed.
- **Task 2 gate:** `OverviewLayoutTests|OverviewCopyTests`: 17 + 7 tests passed, no ✘. `check-no-appkit.sh` OK (50 files).
- **Task 3 gate:** `TransomURLTests|HotkeyTableTests|ShortcutsModelTests|CommandMenuTests|MenuCopyTests`: 52 + 6 tests passed, no ✘.
- **Full unit suites:** Model 193, Mac 337 and Engine 753 tests passed.
- **Acceptance greps:**
  - Command.swift `overview`: 2
  - Hotkeys.swift `"showOverview"`: 1
  - ArrangeController.swift `case .overview`: 1
  - InputTap.swift `keyDown`: 0
  - OverviewLayoutTests `@Test`: 17
  - OverviewLayout.swift `import AppKit`: 0
  - OverviewCopy.swift "No windows on this desktop": 1
  - TransomURL.swift `"overview"`: 1
  - Footer string across the three files: 1
  - ShortcutsModelTests `45`: 4

## TDD Gate Compliance

- **Task 2 RED:** OverviewCopyTests didn't compile (`OverviewCopy` had no `desktopLabel` / `fullScreenLabel`), and OverviewLayoutTests needed APIs that didn't exist yet. GREEN is 5a3cf50.
- **Task 3 RED:** ShortcutsModelTests didn't compile (no `ShortcutsModel.zoomFooter`). In the Engine tests, the `overview` URL and the availability-while-paused tests failed (4 issues). GREEN is fd8ba83.
- As in 06-04 and 06-05, each task's tests and implementation went into one commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] HotkeyTableTests updated in Task 1, not Task 3**
- Adding the hotkey entry (Task 1) broke the 44-entry table tests, so the tracer commit updated them to 45. The ShortcutsModelTests stayed red between 0f2e29b and fd8ba83 (two tests: rows ≠ entries, and ⌃⌥⌘A no longer free). Task 3 fixed them as its RED/GREEN step.

**2. [Rule 1 - Correctness] Show Overview availability added to `Arranger.availability`**
- Without this, the menu item would always be greyed out, because the camera availability path needs a camera step and a display. Show Overview now needs zoom and access only and stays enabled while paused (Surface 1 Availability).

**3. [Rule 2 - Missing] `Arranger.homeView(on:)` (Engine)**
- `homeTiles()` leaves out collapsed windows. The must-have "collapsed windows as Phase 4 collapsed blocks" needs the home plan's `collapsed` rects, so this small public accessor was added, with a test.

**4. [Clarification] The 16-Space shrink result**
- The plan's behaviour bullet says 16 Spaces on 1280×800 "shrink to 32 pt". The UI-SPEC rule ("shrinks by the same factor down to a 32pt height") gives 38.75 pt there. The test asserts one size, one row, ≥ 32 pt and ≤ 1232 pt wide. A separate test covers the 32 pt floor on an 800 pt display.

**5. [Rule 3] The live test pumps AppKit's queue for Esc**
- The first VM run passed everything except Esc. Carbon hotkey events aren't delivered in the test helper because it runs no NSApplication. After posting Esc, the test now pumps events with `NSApp.nextEvent`/`sendEvent`. The real app runs NSApplication, so production behaviour is unchanged.

**6. [Rule 1 - Bug] Every display in full screen**
- **Found during:** writing this summary
- **Issue:** with no display able to have a panel, `open` still set `isOpen` and registered the Esc hotkey, so Esc was taken while nothing was shown.
- **Fix:** `open` returns false before changing any state. ArrangeController then beeps and announces "The overview isn't available in full screen" (from a URL it only logs, Surface 1 Availability), and fades the collapsed panels back in. Mac unit suite (337) and the VM suite re-run green.
- **Commit:** 344780d

**7. [Note] VoiceOver fallback**
- The Phase 3 "disable letter chords while VoiceOver runs" fallback was conditional on UAT and has no code in the repo, so there is nothing for ⌃⌥⌘A to join. Once that fallback lands, ⌃⌥⌘A is a letter chord and belongs in it.

## Known Stubs

None. Full-screen Space labels are empty (no capsule) when none of the tracked windows reports that Space.

## Deferred to later plans (as planned)

Later plans: strip clicks and Space switching (06-07), keyboard selection and the selection ring (06-08), picking windows including parked ones on a zoomed display (06-09), and the Mission Control takeover keys (06-10, 06-11). Gesture disarm while open, the Screen Recording explainer after close, windows opening or closing while open, and background per-visit capture are not in this plan.

## Threat Flags

None. T-06-16: the URL uses the existing whitelist and rate limit and only shows UI. T-06-17: the overview panels are Phase 4 `StagePanel`s with `sharingType = .none`, and snapshots stay in memory only. T-06-18: the Esc stream is cancelled on every close path (dismiss, interrupt, toggle, display change, zoom off), and the VM test closes by toggle and by Esc.

## Self-Check: PASSED
