---
phase: 03-tiling-mvp
plan: 19
subsystem: window-system
status: complete
tags: [tile-09, g-03-5, focus, ax, gap-closure]
gap_closure: true
gap_ids: [G-03-5]
requires:
  - "02-13: AXWindowSystem.focusedWindow(of:) (focusedIdentities first, AXMain fallback)"
provides:
  - "PendingFocus (PaneEngine): per-pid focus hint kept until its window is tracked; hint/resolve/rekey/forget"
  - "AXWindowSystem records no-ID focus hints and resolves them after each refresh's ingest"
affects:
  - "Every hotkey, menu validation and pane:// command (ArrangeController.commandContext reads focusedWindow(of:))"
tech-stack:
  added: []
  patterns:
    - "Pure PaneEngine value for an AXWindowSystem rule, unit-tested headless (SpaceSwitchMarks precedent, 02-17)"
key-files:
  created:
    - Sources/PaneEngine/PendingFocus.swift
    - Tests/PaneEngineTests/PendingFocusTests.swift
  modified:
    - Sources/PaneMac/AXWindowSystem.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "A no-ID focus hint means the app's AXMain window, resolved only from an observation whose AXWindows read succeeded (T-03-54)"
  - "No expiry for an unresolved hint: at most one per pid, replaced by the next focus hint, dropped on app stop (T-03-55)"
  - "focusedWindow(of:), focusedIdentities, the tracker's tab-switch windowFocused and AXAppThread left unchanged, per plan"
metrics:
  duration: "~14 min code + VM run (~45 min wall clock total)"
  completed: 2026-10-26
estimate:
  tokens: 45000
  tasks: 2
actuals:
  tokens: 2300
  tasks: 2
  commits: 2
plan_head_before: b072bdd3b2e6fe0a5cb18d5fad9ec1087f71b689
plan_head_after: d439bd7
---

# Phase 3 Plan 19: Focus hint for newly created windows (G-03-5) Summary

**A focus hint for a window that isn't tracked yet is now kept in a pure `PendingFocus` value until the window settles, then emitted as `windowFocused`. A new window of an app whose docked window was focused becomes the command target, so ⌃⌥⌘D, the menu and pane:// act on it. Verified in the VM, Pane 0.3.3 (1001).**

## What changed

| Task | Name | Commits | Files |
|---|---|---|---|
| 1 | Tracer: a focus hint for a not-yet-tracked window survives until the window is tracked | 8700fa6 (RED), d439bd7 (GREEN) | Sources/PaneEngine/PendingFocus.swift, Tests/PaneEngineTests/PendingFocusTests.swift, Sources/PaneMac/AXWindowSystem.swift |
| 2 | VM UAT re-check of tests 6 and 7 (no source change) | this SUMMARY commit | .planning/phases/03-tiling-mvp/03-19-SUMMARY.md, deferred-items.md |

- `PendingFocus` holds at most one hint per pid: `.window(id)` or `.main` (a hint with no ID). `resolve(pid:mainID:windows:)` matches a same-pid window on `visibleMemberID ?? windowID`. A match consumes the hint and returns it. No match keeps it.
- In `AXWindowSystem`, `handle(_ hint:)` now records every focus hint, including ones with no ID. `refresh(pid:)` resolves the hint after `ingest`. It passes `mainWindowIDs[pid]` only when `observation.listFailure == nil`. A rekey goes through `pendingFocus.rekey`, and `appStopped` calls `forget`. The settle follow-up refresh that ingest already schedules is the one that resolves the new window.

## Verification

- `swift test --filter PendingFocusTests` → `✔ Test run with 9 tests in 1 suite passed`.
- `swift test --filter PaneEngineTests` → `✔ Test run with 457 tests in 50 suites passed`.
- `swift build` OK. `scripts/check-no-appkit.sh` → `no-appkit: OK (40 files)`.
- Acceptance greps: `pendingFocus.removeValue` 0, `PendingFocus` in AXWindowSystem 1, no UI import in PendingFocus.swift, `@Test` count 9.

## TDD Gate Compliance

- RED 8700fa6: the tests failed to compile with `cannot find 'PendingFocus' in scope`, the expected failure for a missing type.
- GREEN d439bd7: 9/9 passed.
- REFACTOR: none needed.

## VM re-check G-03-5

**Setup.** The lock `.build/pane-vm.lock` was taken with `mkdir` and released with `rmdir` (`ls -d` now fails). `scripts/build-debug.sh --release` exited 0. The app was copied with ditto and bumped to 0.3.3 / 1001 (installed was 0.3.2 / 1000). It was re-signed with `Developer ID Application: Ken Scott (S2K7P43927)`, `--options runtime --timestamp`, and the build's own entitlements (`app-sandbox false`). The DR is unchanged (`… leaf[subject.OU] = S2K7P43927`). Pane was quit, the app was copied over with a tar pipe, and `codesign --verify --strict` passed in the guest. It was relaunched with `open`, and the log showed `permission notTrusted -> probing` then `permission probing -> ready`. Guest: Tart pane-test at 192.168.64.18, macOS 15.7.7.

**Exclusions.** `excludedBundleIDs` did not exist before the run (`The domain/default pair … does not exist`), so Finder was not excluded. Nothing needed deleting, and the key is still absent after the run.

**Before (Space 1).** Docked `[Terminal#160, TextEdit#202, TextEdit#578]`. Floating `[finder#546, TextEdit#567, Safari#669, finder#580, finder#731, TextEdit#722]`. The Desktop tile is 12,37 574x326. The layout was saved to the guest at /tmp/layout-before-0319.json.

New guest helpers (sources are in the scratchpad):
- `/tmp/axmenu` opens Pane's status menu through AX and prints each item's enabled flag.
- `/tmp/axfront x y w h` sets the frontmost app's AX focused window frame without changing focus.
- `/tmp/axclose <bundle> <ids>` presses a window's AX close button.
- `/tmp/plog19.sh` shows the Pane log.

**Focus pinning.** Each run first clicks a tracked floating TextEdit window, then docked A = 202. Both clicks send focus hints that name tracked windows, so `focusedIdentities[TextEdit] = 202` before ⌘N. Without the fix, that stale entry is the command target.

| Check | Steps | Result |
|---|---|---|
| (d) menu, control | pin focus on 202, `/tmp/axmenu` | AX focus "Untitled 2" (202). **Dock Window disabled, Float Window ENABLED** (A is docked) |
| (d) menu, new B | ⌘N, 0.9 s, `/tmp/axmenu` | AX focus "Untitled 6" (971). **Dock Window ENABLED, Float Window disabled**. Without the fix this read would still be the control row |
| (a) dock B ~0.7 s after creation | pin focus on 202, ⌘N, 0.45 s, `axfront 12 37 200 150`, 0.25 s, ⌃⌥⌘D (Finder and Safari hidden, see note) | B = **992 docked**: layout `[Terminal#160, TextEdit#202, TextEdit#578, TextEdit#992]`, frame `12 37 241 157` |
| (b) dock C | pin focus on 992 then 202, ⌘N, 0.7 s, ⌃⌥⌘D (no AX move) | C = **998 docked**: layout `[…, TextEdit#992, TextEdit#998]`, frame `167 206 143 157` |
| (c) Undo case (CR-01) | focus floating 722, ⌃⌥⌘D (A = 722 docks at `12 206 241 157`), ⌘N (B = 1008), 0.7 s, ⌃⌥⌘Z | 722 **floating** again, 1008 floating. Menu for 1008: Dock ENABLED / Float disabled. ⌃⌥⌘D → **1008 docked**, 722 stays floating. The stale focus would have docked 722 |

**Note on room (D-26).** The first two ⌃⌥⌘D presses on a new window (937, 978) were refused with Dock Window enabled. The cause was room, not focus. The Desktop tile's minimum is the per-axis maximum of its present floating windows' minimums (Planner.plan). With floating Finder windows (460 pt minimum) and Safari in the 574x326 Desktop tile, no split fits. Two things show this. With Finder and Safari hidden (⌘H, windows `absent`), the Desktop tile reflowed to 12,37 241x326 and the same sequence docked B. And the menu already named the new window as the target in each refused case. The refusal is silent (beep, no log line), so it is logged in deferred-items.md.

**Test 7 (no exclusions).**

| Check | Result |
|---|---|
| `open pane://toggle-desktop` | `desktopHidden [True]`. Finder 546/580/731, Safari 669 and TextEdit 567/722 parked at `1023 661` / `1023 685`; docked windows took the area (578 `12 37 494 326`, 160 `518 37 494 659`). A second toggle brought everything back to its exact frames with `desktopHidden [False]` |
| `open pane://split-finder` with Finder windows 546/580/731 open | Float All (⌃⌥⇧⌘F) first, so the Desktop tile was the whole area; focus on floating 202. With Safari present, new Finder 1014 was admitted **floating** (D-26: Safari's minimum leaves no room in either half). With Safari hidden, new Finder **1017 docked**: layout docked `['finder#1017']`, frame `518 37 494 664` |
| `open pane://restore` after a toggle-desktop park | Every parked window came back (1014 `41 66 460 326`, 202 `12 375 494 326`, …) and `desktopHidden [False]` |
| `open pane://restore?x=1` | log `[com.eightabyte.pane:url] rejected a URL`; no change |

**Restore.** The test windows were closed (TextEdit 937/971/978/992/998/1008 with the red button; Finder 1014/1017 through AX). Finder and Safari were unhidden. Pane was quit, /tmp/layout-before-0319.json was copied back to layout.json, and Pane was relaunched (`permission probing -> ready`). Floating TextEdit 722/567 were put back at `12 37 574 326` through AX. The final layout and every frame match "Before" exactly. The installed app is now 0.3.3 (build 1001) with this fix.

## Deviations from Plan

### Test-procedure adjustments (no code change)

**1. [Rule 3 - Blocking] Gave the Desktop tile room before the dock checks**
- **Found during:** Task 2 (a)
- **Issue:** In the VM desk, D-26 refuses every dock of a new window into the Desktop tile, because of floating Finder and Safari minimums. Step 3(a) could not show a dock, whichever window was focused.
- **Fix:** Hid Finder and Safari for (a)–(c). Used a discriminating menu read (d) as the direct focus check. For split-finder, ran Float All and hid Safari. Everything was restored afterwards.
- **Files modified:** none (VM state only, restored)

**2. [Rule 2 - Missing check] Pinned focus on docked A before each ⌘N**
- **Found during:** Task 2 (a)
- **Issue:** Right after a Pane relaunch `focusedIdentities` is empty, and `focusedWindow(of:)` falls back to AXMain. That would pass even without the fix.
- **Fix:** Each run first sends two focus changes between tracked windows, so A is the remembered focus. The control menu read confirms it.

Step 2's `defaults delete` was a no-op: the key was already absent.

## Known Stubs

None.

## Threat Flags

None. The change only narrows which window a focus hint can name (same pid, tracked, AXMain from a successful read only), as T-03-54 requires.

## Self-Check: PASSED
