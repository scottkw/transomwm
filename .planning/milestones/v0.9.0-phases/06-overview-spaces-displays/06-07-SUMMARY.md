---
phase: 06-overview-spaces-displays
plan: 07
subsystem: overview
status: complete
tags: [overview, spaces, space-switch, symbolic-hotkeys, snapshots, over-01]
requires:
  - phase: 06-01
    provides: "SymbolicHotKeys.value/isEnabled, SpacesSnapshot, 06-SPIKE Switch method (fn flag required)"
  - phase: 06-06
    provides: "OverviewController, OverviewLayout.item(at:), StagePanel overview overlay, shared snapshot cache"
provides:
  - "SpaceSwitchPlan (Engine, pure): Switch to Desktop n / user move chords / ⌃←⌃→+fn defaults, cgFlags"
  - "SpaceSwitcher: posts chords at .cghidEventTap, waits ≤ 1 s for SkyLight's current Space"
  - "OverviewController.pick(_:) for thumbnails and mini tiles; click vs drag (4 pt); backdrop click dismisses"
  - "Couldn't switch to Desktop {n} / {App} refusal (beep + announcement)"
  - "AXWindowSystem.refresh(app:) so a window on a just-shown Space is cached before focus"
  - "Per-visit background capture (D-03): OverviewController.spaceDidSettle"
affects: [06-08, 06-09, 06-12]
tech-stack:
  added: []
  patterns:
    - "Posted chord: keyDown carries the chord's explicit flags, keyUp carries none (no modifier left down in the HID state)"
    - "Space-change confirmation polls SkyLightSpaces.currentSpace (20 ms) instead of consuming system.events, which only ArrangeController reads"
key-files:
  created:
    - Sources/TransomEngine/SpaceSwitchPlan.swift
    - Sources/TransomMac/SpaceSwitcher.swift
    - Tests/TransomEngineTests/SpaceSwitchPlanTests.swift
    - Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift
  modified:
    - Sources/TransomMac/Overview/OverviewController.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/AXWindowSystem.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
key-decisions:
  - "Posted Space-switch chords keep the fn bit 0x800000 (06-SPIKE 'Switch method'); cgFlags keeps ⇧⌃⌥⌘+fn verbatim from the getter and drops everything else"
  - "keyUp is posted with empty flags: a keyUp carrying ⌃ left key 59 (⌃) reported down in the HID state afterwards (measured in the VM)"
  - "Switch confirmation polls SkyLightSpaces.currentSpace rather than awaiting .spaceChanged (single events reader stays ArrangeController)"
  - "Snapshot eviction on window destroy stays where it already is (ArrangeController → ZoomController.windowClosed → capture.remove on the same shared cache); not duplicated in OverviewController"
requirements-completed: []  # OVER-01 completes when 06-08/06-09 add same-Space and parked picks
duration: ~18min
completed: 2026-10-31
metrics:
  duration: "~18 min"
  started: 2026-10-31T19:25:02Z
  completed: 2026-10-31T19:43:09Z
actuals:
  tokens: 9800
  tasks: 3
  commits: 3
plan_head_before: 1388b8cd8969059c5ac3d95adeee52ed393eee20
plan_head_after: eec9f462b83a4ab741b4c4028950a6576e6785dd
---

# Phase 6 Plan 07: Overview Space Switching Summary

**In the overview, clicking another Space's thumbnail switches to it, and clicking a mini tile switches and then focuses that window. Transom posts the user's own Mission Control chords for this, read from the symbolic-hotkey getter, with the fn bit kept. If the Space hasn't changed after 1 s, Transom beeps and announces "Couldn't switch to Desktop n". Each Space visit is captured once, so other Spaces show real previews.**

## What was built

- **SpaceSwitchPlan (Engine, pure):**
  - If the user has "Switch to Desktop n" (ID 118+n−1) enabled and the target is a desktop with n ≤ 16, it posts that chord once.
  - Otherwise it posts the user's "Move left/right a space" (79/81) |Δ| times.
  - If that hotkey is disabled or the getter is unavailable, it uses ⌃←/⌃→ with fn (0x840000).
  - Δ 0 posts nothing.
  - `cgFlags(nx:)` keeps ⇧⌃⌥⌘ and fn, and drops caps lock, numeric pad and device bits.
- **SpaceSwitcher:**
  - Computes Δ from the display's ordered Spaces, using SkyLight's live current Space.
  - Waits up to 500 ms for mouse buttons and modifier keys to be released.
  - Posts from a `.hidSystemState` source at `.cghidEventTap`.
  - Polls the display's current Space for up to 1 s.
  - Logs (category `spaces`): `switch to space {sid} via keys …` and `switch to space {sid} failed after 1 s`.
  - Hotkeys are only read. `setEnabled` is never called.
- **StagePanel:**
  - The content view now reports left and right presses on release: where the press went down (global) and how far it travelled.
  - The second click of a double-click is not reported, and ⌘/⌥ modifiers are ignored, so each click acts once as a plain click.
- **OverviewController:**
  - `click(at:travel:)`: a press that travels 4 pt or more does nothing. Otherwise it hit-tests with `OverviewLayout.item(at:)`. A miss is a backdrop click and dismisses (Surface 1).
  - `pick(_:)`:
    - Current Space's thumbnail: dismisses.
    - Current Space's mini tile: dismisses, then focuses the window.
    - Another Space's thumbnail or mini tile: the stage fades out (120 ms interrupt), the switch runs, then the mini tile's window is focused. If the switch fails, `onSwitchFailed` gets the Surface 2 text.
    - Main-area tiles: left to 06-08/06-09.
  - Logs `pick space {sid}` and `pick window {id} on space {sid} (switch space)`.
- **Focus after the switch (ArrangeController):** `system.refresh(app:)` re-reads the app, because AX lists the window only once its Space shows (06-SPIKE). Then `perform([.focus])` runs the existing AXMain + AXRaise + activate + AXFrontmost fallback.
- **Per-visit capture (D-03):**
  - ArrangeController sends each `.spaceChanged` to `spaceDidSettle` when zoom is on. Each display has its own cancel-latest 1 s task, and a Space already captured on this visit is skipped.
  - The capture runs only if that display still shows the Space and a CG on-screen list exists. It covers the display's current-Space on-screen tiles at main-area size × scale, through `overviewImages` (permission check, concurrency 4, 2 s budget), into the shared cache.
  - Logs `space {sid} captured {n} windows after visit`.
  - Mini tiles already used `cachedSnapshot`, else the app-colour + icon block (06-06).
- **Copy:** `OverviewCopy.couldNotSwitch(desktop:)` → "Couldn't switch to Desktop 2"; `couldNotSwitch(app:)` → "Couldn't switch to Safari".

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 (tracer) | 7cebe99 | Thumbnail pick → SpaceSwitcher → Space change, StagePanel release reporting, VM live test |
| 2 (tdd) | 723b4a3 | Full SpaceSwitchPlan (11 tests), mini-tile picks with focus, refusal copy, keyUp flags fix |
| 3 | eec9f46 | Per-visit background capture into the shared snapshot cache |

## Verification

- **Task 1 tracer gate:** `swift build --build-tests` passed, and `scripts/vm-live-test.sh OverviewSpaceSwitchIntegrationTests` passed (1 test; switched in 818 ms from the pick). The gate (interactive, end-of-phase, automated-only verify) reused that run, which was on the committed code.
- **Task 2:** `SpaceSwitchPlanTests|OverviewCopyTests` passed 11 + 8 tests with no ✘. The VM suite passed 2 tests:
  - thumbnail pick: 740 ms from pick to Space change, `onSwitchFailed` never called
  - mini-tile pick: the window was on the second desktop and the fixture answered "frontmost none" before the pick; after it, "frontmost index=0"
  - after each switch, no modifier key is reported down
- **Task 3:** `swift build` passed. `NoScreenCaptureTests|TileLayerTests|OverviewLayoutTests` passed 3 + 17 tests. The VM suite was re-run with a visit-capture check: Screen Recording is granted in the guest, and the visited window's snapshot reached the cache within 4 s. It passed.
- **Full host unit suites:** Model 193, Mac 338 and Engine 764 tests passed.
- `scripts/check-no-appkit.sh`: OK (51 files). The guest ended on Desktop 1 every run.
- **Acceptance greps:**
  - SpaceSwitcher `cghidEventTap`: 1
  - SpaceSwitcher `.flags = `: 1
  - `SLSManagedDisplaySetCurrentSpace`: none
  - SpaceSwitchPlan `0x80_0000`: 1 (named and **kept**, see deviation 1)
  - SpaceSwitchPlanTests `@Test`: 11
  - SpaceSwitcher `setEnabled`: none
  - OverviewController `captured`: 8
  - `hiddenSpaceWindows` lines containing `capture`: 0
  - OverviewController `remove(`: **0** (see deviation 3)

## TDD Gate Compliance

- **Task 2 RED:** the test build failed to compile: `OverviewCopy` had no `couldNotSwitch`, and `SpaceSwitchPlan.cgFlags` didn't exist yet. The Task 1 plan ignored hotkeys, so the user-chord, Switch-to-Desktop and disabled cases would also have failed.
- **Task 2 GREEN:** 723b4a3. As in 06-04..06-06, tests and implementation went into one commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] fn bit kept, not stripped (06-SPIKE.md "Switch method")**
- **Issue:** the plan and RESEARCH Pattern 3 / Pitfall 7 say to post without 0x800000. The spike measured that on macOS 15.7.7, ⌃→ with 0x40000 switches nothing, while with 0x840000 it switches in about 570 ms.
- **Fix:**
  - `cgFlags` keeps the hotkey's own ⇧⌃⌥⌘+fn bits, and the defaults are ⌃←/⌃→ + fn.
  - The tests are inverted: Δ +2 with 81 = (124, 0x840000) gives two chords of 124 / 0x840000, and `cgFlags(0x960000)` = 0x960000.
  - A `cgFlags` test now checks that caps lock, numeric pad and device bits are dropped.
  - The host's 0x940000 (which includes 0x100000) is posted as the getter reports it. Whatever WindowServer registered is what gets matched.
- **Commits:** 7cebe99, 723b4a3

**2. [Rule 1 - Bug] keyUp posted with empty flags**
- **Found during:** Task 2. VM thumbnail picks took about 1350 ms instead of about 750 ms.
- **Issue:** after a keyUp still carrying ⌃, the HID state reported key 59 (⌃) as down. The post-on-release wait (T-06-19) then always ran to its 500 ms cap, and ⌃ may look stuck system-wide. A `.privateState` source behaved the same.
- **Fix:** the keyDown keeps the chord's explicit flags (Pitfall 7) and the keyUp has none. The switch still lands (557 ms direct). The live test now asserts that no modifier key is down after each switch. The wait reads modifier key state rather than `flagsState`.
- **Files:** Sources/TransomMac/SpaceSwitcher.swift, the integration test
- **Commit:** 723b4a3

**3. [Clarification] Eviction on window destroy not duplicated (acceptance grep `remove(` in OverviewController = 0)**
- ArrangeController already handles `.windowDestroyed` by calling `zoomController?.windowClosed`, which calls `capture.remove(id)`. That is the one cache the overview and the visit capture use (06-06 decision). A second forwarding into OverviewController would remove the same entry twice. The must-have ("evicted when the window is destroyed") holds through the existing path.

**4. [Clarification] Switch confirmation polls SkyLight**
- The plan says to await the display's `.spaceChanged`. Only ArrangeController consumes `system.events`, so SpaceSwitcher polls `SkyLightSpaces.currentSpace(displayUUID:)` every 20 ms for 1 s instead. This is the same source `Displays` uses for `.spaceChanged`.

**5. [Rule 3] Space IDs are not hardcoded in the live test**
- The plan names Space 41. The guest has Spaces 1 and 3 (06-01), so the test takes the main display's first and second desktops from the live snapshot.

**6. [Rule 2] Backdrop click dismisses; focus refresh added**
- A click that hits no item dismisses (UI-SPEC Surface 1 Dismiss row). Without this, the new click path would silently swallow it.
- `AXWindowSystem.refresh(app:)` (one line) runs before the focus. The AX element of a window on a just-shown Space is cached only by a refresh, and the next sweep would come about 500 ms later.

## Known Stubs

None. Main-area tile picks (`.tile`) return without acting: they are 06-08 (same Space) and 06-09 (parked) work, as planned.

## Notes for later plans / UAT

- A4 (multi-display) is still unverified. A posted chord may act on the display under the pointer. Pointer picks are safe. A keyboard pick across displays (06-08) that sees no change reports "Couldn't switch" (hardware checklist item 7).
- 06-12 UAT should confirm that ⌃ never feels stuck after a strip switch. Deviation 2 fixed what the HID state reports; nobody typed in the VM run.

## Threat Flags

None beyond the register. T-06-19: chords come only from the getter or the ⌃←/→ defaults, with explicit keyDown flags, posted after release, never text keys, and the flag mask is tested. T-06-20: visit captures cover only current-Space on-screen windows, with zoom on and Screen Recording granted, and nothing is captured without a CG on-screen list. T-06-21: the cache is memory only and evicted on destroy (existing path).

## Self-Check: PASSED
