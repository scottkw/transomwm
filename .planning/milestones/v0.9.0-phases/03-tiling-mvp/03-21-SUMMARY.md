---
phase: 03-tiling-mvp
plan: 21
subsystem: layout-engine
status: complete
tags: [tile-07, g-03-6, desktop-minimum, gap-closure]
gap_closure: true
gap_ids: [G-03-6]
requires:
  - "03-04: Planner.plan sizes the Desktop tile from the present floaters' learned minimums (test 14)"
provides:
  - "Planner.plan: a floater whose minimum would push docked windows out no longer sizes the Desktop tile (baselineUnfit rule)"
affects:
  - "Every Planner.plan caller: planFloatingLostRoom floats only windows with no room even beside a 1x1 Desktop"
  - "D-26 dock refusals (Dock, Finder split, drag drop pre-checks) no longer refuse a dock whose only obstacle is a floater's minimum"
tech-stack:
  added: []
  patterns:
    - "Fast path first, fallback loop only when the first resolve has unfit windows"
key-files:
  created: []
  modified:
    - Sources/PaneEngine/Planner.swift
    - Tests/PaneEngineTests/PlannerTests.swift
    - Tests/PaneEngineTests/ArrangerDesktopTests.swift
    - Tests/PaneEngineTests/ArrangerReflowTests.swift
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift
    - Tests/PaneEngineTests/ArrangerFinderTests.swift
decisions:
  - "T-03-58 (accepted): a floating window too big for the Desktop tile is clamped into it as far as its app allows and may still overlap a docked tile until Phase 4's collapsed tiles (ZOOM-13). Seen in the VM: Safari 574 pt beside docked Notes 642 pt on 1024 pt."
  - "Docked windows win over floaters, at dock time too: a dock refused only because of a floater's minimum is now accepted (same Planner rule, no Arranger change)"
  - "The first resolution is kept when its unfit set is already within baselineUnfit (zero floaters dropped), so a floater is never dropped when dropping cannot help"
  - "Drop order: descending minimum area, ties by WindowIdentity"
metrics:
  duration: "~55 min (code ~15 min, VM ~40 min)"
  completed: 2026-10-27
estimate:
  tokens: 40000
  tasks: 2
actuals:
  tokens: 3200
  tasks: 2
  commits: 3
plan_head_before: 9ad057702ef9b552b1c4167cfc780c77803eb166
plan_head_after: 3f7192274e42045b77cced07b67a2a35ef690070
---

# Phase 3 Plan 21: Desktop minimum ignores floaters too big for the room (G-03-6 part 1) Summary

**`Planner.plan` now drops a floater's minimum from the Desktop tile when it would push docked windows out (`baselineUnfit` rule), so one too-big floating window no longer floats the whole desk. Floaters that fit still widen the Desktop (test 14). Verified in the VM, Pane 0.3.5 (1003).**

## Tasks

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Tracer: Desktop minimum ignores floaters that push docked windows out (RED) | d8e9f2a | PlannerTests.swift, ArrangerDesktopTests.swift |
| 1 | (GREEN) | 7b6ef8f | Planner.swift, ArrangerReflowTests.swift, ArrangerLifecycleTests.swift, ArrangerFinderTests.swift |
| 2 | VM UAT re-check (no source change) | this SUMMARY commit | 03-21-SUMMARY.md |

`3f71922 chore: vm-live-test.sh defaults to ~/.ssh/pane_vm_ed25519` landed on the branch during this run. It is not from this plan, but it is inside the measured `commits: 3`.

## The rule

The first resolve is the same as before: the per-axis maximum of the present floaters' minimums. If its `unfit` is empty, that is the plan, with one resolve. Otherwise Pane resolves once with a 1x1 Desktop to get `baselineUnfit`. Then, while `unfit` is not a subset of `baselineUnfit`, it drops the floater with the largest minimum area (ties by identity) and re-resolves. With no floaters left, the resolution is the baseline, so the loop ends after at most one resolve per floater. Floaters that overlap a tile are clamped into the resulting Desktop rect, as before.

## Tests

- PlannerTests +4 (12 total): oversized floater (Notes 642 beside a 768x692 floater on 1024x688, gap 12: unfit empty, tiles equal the no-floater resolve, floater clamped); a fitting 574 floater still widens the Desktop; mixed 574 + 768 (768 dropped, Desktop 574..<768); baseline unfit (Notes 1100) is still unfit and the floater keeps sizing the Desktop.
- ArrangerDesktopTests +1: a docked at 800 pt, f learns 768 pt: no lost-room notice, a stays docked, and a repeat event writes no frame.
- `swift test --filter "PlannerTests|ArrangerDesktopTests|ArrangerReflowTests"`: 29 tests passed. `swift test`: 470 tests passed (live AX suites skip on the host). `scripts/check-no-appkit.sh`: OK.

## VM re-check G-03-6 (Desktop minimum)

**Setup.** The lock `.build/pane-vm.lock` was taken with `mkdir` and released with `rmdir` (`ls -d` now fails). `scripts/build-debug.sh --release` exited 0. The app was copied with ditto and bumped to 0.3.5 / 1003 (installed: 0.3.4 / 1002). It was re-signed with `Developer ID Application: Ken Scott (S2K7P43927)`, `--options runtime --timestamp`, and the build's own entitlements (`app-sandbox false`). The DR is unchanged (`… leaf[subject.OU] = S2K7P43927`). Pane was quit, the app was copied over with a tar pipe, `codesign --verify --strict` passed in the guest, and Pane was relaunched with `open`. The log showed `permission notTrusted -> probing` then `probing -> ready`. Guest: Tart pane-test 192.168.64.18, macOS 15.7.7. Saved first: /tmp/layout-before-0321.json and /tmp/hints-before-0321.json. Hints: Notes 642, Safari 574, Finder 460, Terminal 165, TextEdit 143 (no Reminders hint).

**(a) Too-big floater, Space 2 (1024 pt display).** Notes 150 was docked with ⌃⌥⌘D. Its tile was `370 37 642 664`, with the Desktop on the left at 12..358. A new Safari window was opened on Space 2 with a new guest helper, `/tmp/axpress com.apple.Safari File "New Window"`, which presses the menu item through AX. `osascript` timed out with -1712. 642 + 574 + gaps do not fit in 1024 pt.

| | Notes 150 | Safari 1356 | Reminders 693 | layout.json (Space 2 desk) |
|---|---|---|---|---|
| after dock | `370 37 642 664` | — | `12 25 768 692` | docked [Notes#150], floating [reminders#693] |
| after new Safari | `370 37 642 664` | `12 200 574 224` | `12 25 768 692` | docked [Notes#150], floating [reminders#693, Safari#1356] |
| +4 s | `370 37 642 664` | `12 200 574 224` | `12 25 768 692` | unchanged |

Notes stayed docked, nothing was floated for lost room (layout.json has no tree change), and frames were stable. Safari was clamped to the Desktop's left edge (x 12). It refuses to go below 574 wide, so it overlaps Notes' tile behind Notes (screenshot g21d). That is the accepted T-03-58 cost. Under the old rule, Safari's 574 pt minimum would have sized the Desktop and Notes would have floated. Reminders has no learned minimum yet (03-22's job), so it stays floating and overlapping, as in UAT.

**(b) Test 14 regression, Space 1.** Before: TextEdit 202/578 and Terminal 160 docked, and Safari 669 floating pins the Desktop at 574 (TextEdit 578 at x 598). This was unchanged after the relaunch on the new build. Safari 669 was minimized with a new guest helper, `/tmp/axmin Safari 669 1`. The Desktop shrank to Finder's 460: TextEdit 578 `484 37 143 326`, Terminal `639 37 375 659`. A new Safari window was opened (`axpress … "New Window"`), and Safari 1368 floated inside the Desktop at `12 139 574 224`. The Desktop column widened back to 574: TextEdit 578 `598 37 143 326`, Terminal `753 37 256 659`. Test 14's widening is kept.

**Restore.** Safari 1368 and 1356 were closed with `/tmp/axclose`, and Safari 669 was unminimized. Pane was quit. Reminders was set back to `191 25 768 692`, and the floating TextEdit 722/567 (clamped to 460 while the Desktop was small) back to `12 37 574 326`, all with `/tmp/axset`. /tmp/layout-before-0321.json was copied back, and Pane was relaunched (`probing -> ready`). Every Space 1 frame matches "Before". layout.json's `world` compares equal to the saved copy. `min-size-hints.json` is byte-identical (`cmp`). The gap is 12. Notes 150 is floating on Space 2 at `370 37 642 664`, as found. The installed app is now 0.3.5 (1003) with this fix.

The full Reminders scenario (UAT test 15) is re-checked by 03-22 once Pane can learn Reminders' minimum.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Three Arranger tests encoded the cascade that G-03-6 removes**
- **Found during:** Task 1 GREEN
- **Issue:** In each of these tests, the no-room case came only from a floater's minimum. `windowsLosingRoomInOneReplanGiveOneNotice` expected a floated window's 760 pt minimum to push c (700) out too, which is the G-03-6 cascade. `aDockWithoutRoomIsRefusedAndChangesNothing` (two 1000 pt windows) and `aFinderWindowThatWouldLeaveAWindowWithoutRoomFloatsWithABeep` (f's 700 pt floater) expected a D-26 refusal caused only by the other window floating.
- **Fix:** Each test now uses a genuine no-room case, so it keeps its intent (one notice for several windows, a D-26 dock refusal). a and c are 1430 pt, wider than the 1424 pt inner area. w1 is 1500 pt. The Finder window n is 1450 pt beside a's 200. Each test has a comment pointing to G-03-6.
- **Files modified:** ArrangerReflowTests.swift, ArrangerLifecycleTests.swift, ArrangerFinderTests.swift (none were in the plan's `files_modified`)
- **Commit:** 7b6ef8f

**2. Behaviour consequence (documented, not a code change):** the D-26 dock pre-checks call `Planner.plan`. A dock refused only because of a floater's minimum is therefore now accepted, and the floater is clamped (T-03-58). This follows the plan's binding truth ("Planner.plan never reports a docked window unfit that would fit with the Desktop at its own 1x1 minimum"). Keeping the old refusal would have made every dock refused on a desk holding one too-big floater.

### VM process notes

- My first focus click (690,48) landed on Reminders, so Reminders was docked. I undid it with ⌃⌥⌘Z. The undo put Notes at `-374 40` (off-screen left), and a Dock press on it then did nothing, probably because its centre was off the display. I moved Notes back with `/tmp/axset` and the dock worked. Both events predate this plan's code path. They are noted here only as observations.
- Right after switching to Space 1 with ⌃←, one `/tmp/frames` read showed transient frames (the TextEdits at `0 25 1024 688`). The next read, after the Space animation, was normal.

## Known Stubs

None.

## Threat Flags

None. No new surface: the change is pure layout in PaneEngine.

## Self-Check: PASSED

- FOUND: Sources/PaneEngine/Planner.swift (`baselineUnfit` x2, no AppKit import)
- FOUND: d8e9f2a, 7b6ef8f (ancestors of HEAD)
- PlannerTests `@Test` count 12; `.build/pane-vm.lock` absent
