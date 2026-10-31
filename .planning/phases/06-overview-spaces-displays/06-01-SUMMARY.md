---
phase: 06-overview-spaces-displays
plan: 01
subsystem: spaces
status: complete
tags: [spike, spaces, skylight, symbolic-hotkeys, coredock, vm]
requires: []
provides:
  - "SpacesSnapshot.parse (Engine): display grouping by listing array, Main mapping, default:<displayUUID> for empty uuid, type 2 skipped, caps; fixture-tested"
  - "SpacesProvider.snapshot() (TransomMac) with the screensHaveSeparateSpaces / SLSGetSpaceManagementMode cross-check"
  - "SkyLightSpaces.managedDisplaySpaces() and managementMode() as optional symbols under capability .spaces"
  - "SymbolicHotKeys (TransomPrivate): isEnabled / setEnabled / value, SLS names with CGS fallback, capability SymbolicHotKeys"
  - "CoreDock.send(_:) (TransomPrivate) through CoreDockSendNotification, capability CoreDock"
  - "transom-spaces-spike CLI: spaces-dump, hotkeys, takeover-crash, switch, ghost, swipe-check"
  - "06-SPIKE.md: measured answers to A1-A8, swipe verdict (skip → kept), schema decision (schema-2)"
affects: [06-02, 06-03, 06-07, 06-10, 06-11]
tech-stack:
  added: [SkyLight symbolic-hotkey getters/setters (private, dlopen/dlsym), CoreDockSendNotification (private, dlopen/dlsym)]
  patterns:
    - "Spike reads Spaces through the product path (SkyLightSpaces → SpacesProvider → SpacesSnapshot.parse), so the VM run proves shipped code"
    - "Every hotkey-disabling subcommand restores originals in a defer and a SIGINT handler; state-changing probes run only in the VM"
key-files:
  created:
    - Sources/TransomEngine/SpacesSnapshot.swift
    - Sources/TransomMac/SpacesProvider.swift
    - Sources/TransomPrivate/SymbolicHotKeys.swift
    - Sources/TransomPrivate/CoreDock.swift
    - Sources/transom-spaces-spike/main.swift
    - Tests/TransomEngineTests/SpacesSnapshotTests.swift
    - Tests/TransomEngineTests/Fixtures/Spaces/README.md
    - Tests/TransomEngineTests/Fixtures/Spaces/separate-one-display.json
    - Tests/TransomEngineTests/Fixtures/Spaces/spans-main.json
    - Tests/TransomEngineTests/Fixtures/Spaces/empty-uuid.json
    - Tests/TransomEngineTests/Fixtures/Spaces/fullscreen.json
    - .planning/phases/06-overview-spaces-displays/06-SPIKE.md
  modified:
    - Package.swift
    - Sources/TransomPrivate/SkyLightSpaces.swift
    - Sources/TransomPrivate/Capabilities.swift
    - Sources/TransomMac/Displays.swift
    - Tests/TransomMacTests/CapabilitiesTests.swift
key-decisions:
  - "Schema door (user, verbatim): \"schema-2\". layout.json bumps to schema 2; schema-1 files migrate in memory and are saved as 2; a downgraded build refuses to overwrite (T-03-18). 06-03 implements it"
  - "Swipe (user, verbatim): \"skip\" → kept. The four-finger swipe stays with macOS; [swipe kept] copy variant; 06-11 does not create SwipeTakeoverTap.swift"
  - "Takeover ID set is {32, 108, 113}: ⇧F3 (113, key code 160 + shift) still opens Mission Control with 32/108 off, so 06-10 must take it too; 34 (⌃⇧↑) does not and stays untouched"
  - "Posted Space-switch and Mission Control chords need the fn flag 0x800000 (the hotkey's own NX flags, e.g. 0x840000 for ⌃→); without it nothing happens on 15.7.7. Overrides RESEARCH Pattern 3. 06-07 must post with it"
  - "A disabled symbolic hotkey outlives abort() of the process that disabled it and the Dock honours it; 06-10's launch-time restore from stored originals is required"
  - "G-03-9 ghost did not reproduce: the closed Safari window answers invalidElement within 1 s and its CG entry is gone; a hidden native tab reports an empty Space set (minimised and ⌘H-hidden windows keep theirs), so any empty-Space-set ghost rule in 06-02 keeps the tab-member guard"
  - "Space numeric IDs and UUIDs (including the empty Desktop 1 uuid → default:<displayUUID>) were stable across a VM restart; the UUID side table stays the correctness mechanism"
requirements-completed: []
metrics:
  duration: "~2h 21m wall clock (includes the schema/swipe decision checkpoint wait)"
  started: 2026-10-31T15:40:28Z
  completed: 2026-10-31T18:01:38Z
actuals:
  tokens: 24000
  tasks: 3
  commits: 3
plan_head_before: 579c66d94fbfa4fb3b5f34d92632ac68e27974c9
plan_head_after: f7798f9
---

# Phase 6 Plan 01: Spaces Spike Summary

**The production Spaces read path (SkyLight → SpacesProvider → SpacesSnapshot.parse) is proven in the macOS 15.7.7 VM, the takeover needs hotkeys {32, 108, 113}, posted switch chords must carry the fn flag, disabled hotkeys survive a crash, and the user chose layout.json schema 2 and kept the four-finger swipe with macOS.**

## What was built

- `SpacesSnapshot.parse` (Engine, no AppKit): groups each Space under the display whose `Spaces` array lists it, maps `Main` to the main display, keys an empty uuid as `default:<displayUUID>`, skips type-2 and unknown types, drops ID 0, caps at 16 Spaces per display and 32 displays. Pinned by four fixtures plus foreign-`Display Identifier` and malformed-entry tests.
- `SpacesProvider.snapshot()`: reads `SkyLightSpaces.managedDisplaySpaces()`, the menu-bar screen's UUID and `NSScreen.screensHaveSeparateSpaces`, cross-checked with `SLSGetSpaceManagementMode`.
- `SymbolicHotKeys` and `CoreDock` shims, each in one TransomPrivate file through dlopen/dlsym, behind new capabilities `SymbolicHotKeys` ("Mission Control keys unchanged") and `CoreDock` ("beep instead of Mission Control").
- `transom-spaces-spike` with six subcommands; all state-changing ones refuse to run outside a VM (`kern.hv_vmm_present`).

## Spike findings later plans depend on

| Finding | Value | Used by |
|---|---|---|
| F2 symbols on 15.7.7 | 25 of 25 resolve | all |
| Takeover ID set | **32, 108, 113** (113 = ⇧F3, Carbon: key code 160 + shiftKey). 34 not taken | 06-10 |
| Abort persistence (A2) | Disabled state outlives `abort()`; Dock honours it until restored | 06-10 |
| CoreDock (A3) | `com.apple.expose.awake` opens Mission Control with 32/108 off; a second send closes it | 06-10 |
| Carbon on freed chords | ⌃↑ and key code 160 both fire after the disable | 06-10 |
| Switch method (A4) | Posted ⌃→/⌃← switch in 542-658 ms **only with fn flag 0x800000**; activation-only switch ~400 ms regardless of `AppleSpacesSwitchOnActivate` | 06-07 |
| AX after switch | Window on the other Space is not AX-listed before, listed after; focus 3 ms (indicative) | 06-07 |
| G-03-9 ghost (A7) | invalidElement (-25202) for 30 s, CG entry gone within 1 s, not reproduced in 2 runs → CloseRule `(.alive, .invalidElement, false) → .closed` | 06-02 |
| Hidden windows' Spaces | Minimised [3], ⌘H-hidden [3], hidden native tab **[]** | 06-02 |
| Reboot diff (A8) | IDs 1, 3 and UUIDs `""`, `7AE365C9-…` unchanged; current resets to Desktop 1 | 06-03 |
| Swipe (D-05) | skip → kept | 06-11 |
| Schema decision | schema-2 | 06-03 |

Not covered: macOS 14 (VM is 15.7.7), multi-display behaviour of posted chords and `Main` in spans mode (hardware checklist items 6 and 7), a captured type-4 full-screen dictionary (fixture stays synthetic).

## Task Commits

1. **Task 1: Tracer, spaces-dump in the VM** - `2970efd` (feat)
2. **Task 2: Capability tests (RED)** - `e725c32` (test)
3. **Task 2: SymbolicHotKeys/CoreDock shims, spike subcommands, VM runs, 06-SPIKE.md (GREEN)** - `f7798f9` (feat)
4. **Task 3: Schema and swipe decision** - recorded in 06-SPIKE.md, committed with this SUMMARY

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 1 - Bug] Harness Space-switch cleanup lacked the fn flag.** The end-of-run "back to Desktop 1" post sent ⌃← without 0x800000, so it did nothing; fixed in `main.swift` (f7798f9). The guest stayed on Desktop 2 until the reboot diff reset it.
2. **[Rule 3 - Blocking] Mission Control closed with a posted Escape** after each "did it open" probe, so later probes start from a closed state.
3. **[Rule 3 - Blocking] `CoreDockSendNotification` name appears in `main.swift`'s spaces-dump dlsym table** (the F2 symbol-resolution list). The plan's acceptance said only `CoreDock.swift` mentions it; the spike only checks the symbol resolves, product code reaches it only through `CoreDock`.
4. **[Rule 3 - Blocking] `Displays.displayID` / uuid helper changed from private to internal** so `SpacesProvider` can reuse it (Sources/TransomMac/Displays.swift, 2970efd).
5. **[Plan fact] VM Spaces are IDs 1 and 3**, not 1 and 41 as the plan said; all runs used 1 and 3.
6. **[Gap] Not captured:** a type-4 full-screen dictionary (fixture synthetic) and which post (with or without fn) fired the Carbon chords.
7. **[Housekeeping] A stray bash process from an earlier run was killed** (not node).
8. **[Rule 3 - Blocking] The VM was restarted under a background task** (`tart run --no-graphics pane-test`) for the reboot diff, as the plan's scripts expect.

## Known Stubs

None. swipe-check was built but deliberately not run (user chose "skip").

## Self-Check: PASSED
