---
phase: 03-tiling-mvp
plan: 18
subsystem: input
status: complete
tags: [tile-06, tile-19, g-03-4, green-button, event-tap, gap-closure]
gap_closure: true
gap_ids: [G-03-4]
requires:
  - "03-13: green-button swallow in the session tap with the window-0 fallback"
provides:
  - "CGWindowList.topmost(at:in:excludingPID:): pure topmost layer-0 selection over a front-to-back [CGWindowEntry]"
  - "topmostWindow(at:) as a thin live wrapper; InputTap call site unchanged"
affects:
  - "Sources/PaneMac/Input/InputTap.swift (behaviour of the window-0 fallback)"
tech-stack:
  added: []
  patterns:
    - "Pure selection function plus thin live wrapper, so the tap's lookup is unit-tested headless"
key-files:
  created:
    - Tests/PaneMacTests/TopmostWindowTests.swift
  modified:
    - Sources/PaneMac/CGWindowList.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "The tap's window-0 fallback applies the same layer-0 filter as ArrangeController.pressWindow (T-03-52 accepted: another app's non-zero-layer panel over a green button no longer blocks the swallow)"
  - "Arranger, GreenButton.shouldSwallow, the Option rule and D-33 left untouched, per plan"
metrics:
  duration: "~15 min"
  completed: 2026-10-26
estimate:
  tokens: 35000
  tasks: 2
actuals:
  tokens: 1030
  tasks: 2
  commits: 3
plan_head_before: 53d5faab0cc6f32f445757f2191bac014acfb3ad
plan_head_after: afb0f76e61378b9de291650aae9d1ef134fe8fff
---

# Phase 3 Plan 18: Green-button window lookup (G-03-4) Summary

**The tap's window-0 fallback now picks the topmost layer-0 window under the press, so the Dock's full-screen layer-20 window on macOS 15 no longer hides the app window. Plain green-button clicks, both injected and real HID, toggle dock/float in the VM, and macOS never sees them.**

## What changed

- `Sources/PaneMac/CGWindowList.swift`: new pure `static func topmost(at:in:excludingPID:) -> UInt32?`. It returns the first front-to-back entry with `layer == 0`, a pid other than the caller's, `alpha > 0`, and bounds containing the point. `topmostWindow(at:)` is now `onScreenFrontToBack().flatMap { topmost(at:in:excludingPID: getpid()) }`. Its signature is unchanged, so `InputTap.swift` is not edited. The doc comment names the Dock overlay and the T-03-52 trade-off.
- `Tests/PaneMacTests/TopmostWindowTests.swift`: 5 Swift Testing tests, one per behaviour bullet. They cover the Dock layer-20 entry listed first, menu-bar layers 24/25 and an own-pid layer-3 handle listed first, a front layer-0 window of another app winning, alpha-0/own-pid/miss entries being skipped, and nil for no hit or an empty list.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | Failing topmost layer-0 tests | 3ec32b2 | Tests/PaneMacTests/TopmostWindowTests.swift |
| 1 (GREEN) | Pure selection + thin wrapper | 133cbcd | Sources/PaneMac/CGWindowList.swift |
| 2 | VM re-check of UAT test 4 (no source change) | afb0f76 (deferred items only) | .planning/phases/03-tiling-mvp/deferred-items.md |

## TDD Gate Compliance

- RED: `swift test --filter TopmostWindowTests` failed to compile with `type 'CGWindowList' has no member 'topmost'` (3ec32b2).
- GREEN: `✔ Test run with 5 tests in 1 suite passed` (133cbcd).
- REFACTOR: none needed.
- Tracer gate: verify re-run passed (5 tests), then expanded to Task 2.

## Verification

- `swift test --filter TopmostWindowTests`: `Test run with 5 tests in 1 suite passed`
- `swift test --filter GreenButtonHitTests`: `Test run with 5 tests in 1 suite passed`
- `swift test --filter "TopmostWindowTests|GreenButtonHitTests"`: `Test run with 10 tests in 2 suites passed`
- `swift build`: complete. `scripts/check-no-appkit.sh`: `no-appkit: OK (39 files)`
- `grep -c "layer == 0" Sources/PaneMac/CGWindowList.swift` = 1. `grep -c "CGWindowList.topmostWindow" Sources/PaneMac/Input/InputTap.swift` = 1. `grep -c "@Test" Tests/PaneMacTests/TopmostWindowTests.swift` = 5
- `ls -d .build/pane-vm.lock` fails after the task (lock released)

## VM re-check G-03-4

**Setup.** The shared lock `.build/pane-vm.lock` was taken with `mkdir` and released with `rmdir`. `scripts/build-debug.sh --release` exited 0. The app was copied with ditto, bumped to `CFBundleShortVersionString 0.3.2` / `CFBundleVersion 1000` (installed was 0.3.1 / 999), and re-signed with `codesign --force --sign "Developer ID Application: Ken Scott (S2K7P43927)" --options runtime --timestamp --entitlements <the build's own entitlements>`. The designated requirement is still `identifier "com.eightabyte.pane" … leaf[subject.OU] = S2K7P43927`. Pane was quit in the guest, the app was copied over with a tar pipe through `vssh`, and it replaced /Applications/Pane.app and passed `codesign --verify --strict`. It was relaunched as the GUI user. The log showed `permission notTrusted -> probing` and then `permission probing -> ready`, so the grant was kept. Guest: Tart pane-test at 192.168.64.18, macOS 15.7.7.

**Before** (Space 1). layout: docked `[Terminal#160, TextEdit#202, TextEdit#578]`, floating `[finder#546, TextEdit#567, Safari#669, finder#580, finder#731, TextEdit#722]`. Frames: 202 `12 375 729 326`, 578 `598 37 143 326`, 160 `753 37 256 659`, 722/567 `12 37 574 326`. layout.json was saved to the guest at /tmp/layout-before-0318.json.

Green-button centre = frame origin + (54, 14), from the AX offset 46,6 16x16. Pane's log was streamed at debug level (`subsystem BEGINSWITH "com.eightabyte.pane"`) around each press.

| Check | Command | Before | After | Log |
|---|---|---|---|---|
| (a) injected plain click, docked 202 | `/tmp/g4run.sh … "echo click 66 389 \| /tmp/injx"` | 202 docked, `12 375 729 326` | 202 **floating** `12 375 574 326`. Neighbour 578 reflowed `598 37 143 326` → `598 37 143 664` | no Pane line at all (swallowed) |
| (b) injected plain click, floating 202 | same, click 66 389 | 202 floating | 202 **docked** (layout `[Terminal#160, TextEdit#578, TextEdit#202]`), `12 375 574 326` in the slot below the Desktop tile | no Pane line |
| (c) real HID click via VNC (`vnc.py "click 66 389"`), docked 202 | VNC pointer | 202 docked | 202 **floating**, `12 375 574 326` | no press line |
| (c') HID click again, floating 202 | VNC | floating | **docked** | not captured (log quoting error) |
| (c'') HID click again, docked 202 | VNC + `/tmp/logfor.sh` | docked | **floating** | stream contained only the "Filtering" header |
| control: HID title-bar click 300,389 | VNC | | no change | `drag] start com.apple.TextEdit window 202 (CG 0, member 202) at 300.0,389.0`, so the stream does capture press lines and HID presses still report CG 0 |
| (d1) Option-click, floating 202 | `/tmp/g4opt.sh 66 389` | `12 375 574 326` | +0.3 s and +3 s: `12 37 574 664` (zoom clamped into the Desktop tile, D-33), still floating | `start … window 202 (CG 202, member 202) at 66.0,389.0`. The fallback now resolves **202**, where diagnosis saw CG 7 |
| (d2) Option-click, docked 578 | `oclick 652 51`, frames every ~0.19 s | `598 37 143 664` | `341 31 522 676` → `0 25 1024 688` (native zoom) → `598 37 143 664` back on its tile ~0.55 s after the click. Still docked | `start … window 578 (CG 578, member 578) at 652.0,51.0` (passed through) |
| (e1) minimise / restore, docked 578 | `click 690 48`, `key m 46` (⌘M), then `/tmp/unmin TextEdit` (AX `AXMinimized=false`) | `598 37 143 664`, Terminal `753 37 256 659` | minimised: `min true`, Terminal reflowed to `598 37 417 659`. Restored: 578 `598 37 143 664`, Terminal `753 37 256 659`, still docked | |
| (e2) fullscreen / exit, docked 578 | `key cm 3` (⌃⌘F) twice | `598 37 143 664` | fullscreen: `fs true`, `0 0 1024 768`. Exit: `fs false`, `598 37 143 664`, still docked | |

(a), (b) and (c) produced no fullscreen frame (0,0 1024x768) for the clicked window. Before this fix the same plain press logged `start … window 202 (CG 7 …)` and 202 went full screen (.planning/debug/g-03-4-green-button.md).

**Restore.** Pane was quit, /tmp/layout-before-0318.json was copied back to layout.json, and Pane was relaunched. Space 1 is back exactly: 202 `12 375 729 326`, 578 `598 37 143 326`, and the same docked and floating lists. The installed app is now 0.3.2 (build 1000) with this fix. Helper /tmp/unmin was added in the guest and /tmp/logfor.sh in the guest and scratchpad.

## Deviations from Plan

### Observations (not fixed, logged to deferred-items.md)

**1. A plain green click on a floating window that exactly fills the Desktop tile does nothing.** Option-click put 202 at `12 37 574 664`, which is the whole Desktop tile. A plain green click at 66,51 then left it floating, and so did a press with the event's window field preset to 202 (`/tmp/wclick 66 51 202`). That was not a pass-through: no press line was logged and there was no fullscreen. The lookup is not the cause. The cause is `Arranger.dock`, which targets the window's centre. That point is the Desktop tile's centre, so the target is `.tile(_, .center)` and dock beeps (tab groups are Phase 7, Arranger.swift:671). This conflicts with TILE-06's "floating docks" in this one case, and Option-click followed by a plain click leads straight to it. The Arranger was out of this plan's scope ("do not change …"), so it was logged, not fixed.

**2. Space 2's docked windows are dropped on every relaunch.** layout.json had a second desk (spaceID 41) with Notes#150 and reminders#693 docked, and both apps were running. After each of the two Pane relaunches in this run, that desk's docked list was empty. This is a clean repro of the 03-UAT.md test-17 note. It was not restored, because Pane drops it again on launch.

Otherwise the plan was executed as written.

## Known Stubs

None.

## Human check (end of phase)

Click the green button of a docked window by hand, then of a floating window that does not fill the Desktop tile, then Option-click. Expected: docked floats, floating docks, neither goes full screen, and Option-click zooms and returns (D-33). Note observation 1 above if the floating window fills the Desktop tile.

## Self-Check: PASSED

- FOUND: Sources/PaneMac/CGWindowList.swift, Tests/PaneMacTests/TopmostWindowTests.swift
- FOUND commits: 3ec32b2, 133cbcd, afb0f76
