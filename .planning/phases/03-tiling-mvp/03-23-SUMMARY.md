---
phase: 03-tiling-mvp
plan: 23
subsystem: engine-restore
status: complete
tags: [safe-06, g-03-8, restore, spaces, gap-closure]
requires: [03-05, 03-07, 03-18, 03-22]
provides:
  - "WindowInventory.liveWindows (layer-0 CG windows of tracked apps, nil = unknown)"
  - "LayoutRestore.isAlive and reattach(_:tracked:live:) keeping live saved windows dormant"
  - "Arranger dormant re-attach on windowCreated, planShown skips untracked windows, pruning, hasDormantWindows"
  - "WindowEvent.liveWindowsChanged from AXWindowSystem; ArrangeController feeds the inventory on it while windows are dormant"
affects: [Arranger restore path, AXWindowSystem sweep, ArrangeController event loop, FakeWindowSystem inventory]
tech-stack:
  added: []
  patterns: ["dormant saved window: kept in its desk while CG has its windowID+pid, re-attached by its first windowCreated"]
key-files:
  created: []
  modified:
    - Sources/PaneEngine/WindowSystem.swift
    - Sources/PaneEngine/LayoutRestore.swift
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/LifecycleSync.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/ArrangeController.swift
    - Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift
    - Tests/PaneEngineTests/ArrangerRestoreTests.swift
    - Tests/PaneEngineTests/LifecycleSyncTests.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "Prune triggers: the dormant window's ID leaves the layer-0 CG list of tracked apps (inventory after the restore), or its app terminates. A paused session, a nil list (unreadable/unknown) or an empty list prunes nothing."
  - "An app relaunch (new pid) still drops its saved windows at restore; re-matching is VIEW-04 (Phase 8)."
  - "T-03-65 accepted: a live window AX never lists on the shown Space keeps a reserved, empty tile until AX lists it, its ID leaves CG, or its app quits."
  - "Fake liveWindows scope = apps the fake tracks (added, not terminated), matching AXWindowSystem's apps-with-a-thread scope (plan-checker advisory applied, no difference left)."
metrics:
  duration: "~20 min"
  completed: 2026-10-27
  tasks: 3
  files: 11
actuals:
  tokens: 5900
  tasks: 3
  commits: 6
plan_head_before: 10e15c5135070006de2fb85c1434708af24c74df
plan_head_after: 94316425dbb17b5817382a1dcbd8b126faf9577e
---

# Phase 3 Plan 23: Hidden-Space desks survive relaunch (G-03-8) Summary

A saved window that is still alive in the layer-0 CG list, with the same windowID and pid, now stays dormant in its desk at restore instead of being closed. Its first `windowCreated` re-attaches it with its real frame seeded as already requested, so showing its Space writes nothing unless its tile changed. A dormant window is pruned when its ID leaves the CG list or its app quits.

## Tasks

| # | Task | Commits |
|---|------|---------|
| 1 | Tracer: dormant saved windows on a hidden Space, re-attached on windowCreated (fresh fake, normal + recovery) | fbfa115 (RED), 7f80cc7 (GREEN) |
| 2 | Prune dormant windows on CG departure or appTerminated; `liveWindowsChanged`, `hasDormantWindows` | 072d2ad (RED), 9360463 (GREEN) |
| 3 | AXWindowSystem `liveWindows` + `.liveWindowsChanged`; ArrangeController feed rule; VM re-check | 812678a, 9431642 |

## What changed

- **WindowSystem.swift**: `WindowInventory.liveWindows: [CGWindowEntry]?` (last init parameter, default nil). `WindowEvent.liveWindowsChanged`.
- **LayoutRestore.swift**: `isAlive(_:in:)` matches a non-synthetic identity against a layer-0 entry with the same windowID and pid. `reattach(_:tracked:live: = [])` keeps a saved window that is tracked or alive. `unplaced` is unchanged.
- **Arranger.swift**:
  - The restore passes `inventory.liveWindows ?? []` through and keeps the home frames of live identities.
  - `wakeDormant(_:)` runs on `windowCreated` of a window that has no `windows` entry but sits on a desk. It applies the real state, seeds `lastRequested` if the window is docked or records the floating frame if it is present, then calls `rehome`. A failure is reported as a `.fault`.
  - `planShown` sends no setFrame or park to an untracked window: the excluded filter is now `isExcluded == false`.
  - `hasDormantWindows`.
  - `closeDormant(where:)` goes through `forget` and `LifecycleSync.handle(.windowDestroyed)`. It is called from the post-restore inventory (only when not paused and the list is known and non-empty) and from `.appTerminated`.
  - `.liveWindowsChanged` returns `[]`.
- **LifecycleSync.swift**: `.liveWindowsChanged` is added to the no-op list.
- **FakeWindowSystem.inventory()**: `liveWindows` holds the `inCGList`, layer-0 windows of added, non-terminated apps, sorted by id. It is nil while locked.
- **AXWindowSystem**: each sweep keeps the layer-0 entries of its optionAll snapshot whose pid has a thread. The list is nil while paused or when the snapshot fails. A change in the ID set against the previous non-nil set emits `.liveWindowsChanged`, never for the first set. `inventory()` reports nil while `sessionPaused`.
- **ArrangeController**: `feed = true` on `.liveWindowsChanged` while `arranger.hasDormantWindows`.

## TDD Gate Compliance

- **Task 1 RED (fbfa115):** `swift test --filter ArrangerMultiDeskRestoreTests` at HEAD behaviour ran 4 tests and failed 3 with 18 issues.
  - `aDeskOnASpaceNotShownAtRelaunchKeepsItsWindowsInTheirTiles` failed for both `.normal` and `.recovery`: `world == first.saved` was false, and `world[deskA2]?.tree.windows == [ref(3)]` was false (Space 2 desk empty, window 3 removed).
  - `aDormantWindowWhoseTileChangedIsWrittenOnceToItsNewTile` failed: `desk.tree.windows == [ref(3)]`.
  - The rewritten `twoDisplaysWithTwoSpacesEach…` failed on `world == saved` and on every hidden-desk `deskKey` check.
  - `aSavedWindowWhoseAppRelaunchedIsRemoved` passed at RED. That is expected: it pins the VIEW-04 boundary.
- **Task 1 GREEN (7f80cc7):** `ArrangerMultiDeskRestoreTests|ArrangerRestoreTests|ArrangerSpacesTests` ran 36 tests and all passed. The full `swift test` passed: 193 + 196 + 42 + 496.
- **Task 2 RED (072d2ad):** this was a compile failure, not a behavioural one. The tests use `WindowEvent.liveWindowsChanged` and `Arranger.hasDormantWindows`, which did not exist yet (`type 'WindowEvent' has no member 'liveWindowsChanged'`).
- **Task 2 GREEN (9360463):** the five-suite filter ran 75 tests and all passed. The full suite passed: 193 + 196 + 42 + 502.
- **REFACTOR:** none needed.

## Verification

- Full `swift test`: 193 + 196 + 42 + 502 tests passed. `scripts/check-no-appkit.sh` reported OK (40 files).
  - In one full run, `FreezeTestTests/itResumesByItself` alone failed. This is the known timing flake. Re-run alone it passed (1 test), and the next full run passed.
- Acceptance greps:
  - `liveWindows`: WindowSystem 5, FakeWindowSystem 3, AXWindowSystem 7.
  - `isAlive` in LayoutRestore: 3.
  - `harness.arranger = Arranger()`: 0.
  - Removed `#expect` lines since 10e15c5: 0.
  - `hasDormantWindows` in Arranger: 1.
  - `liveWindowsChanged`: 1 each in WindowSystem, LifecycleSync, LifecycleSyncTests and ArrangeController.
- Live regression in the VM, through `scripts/vm-live-test.sh`, one suite at a time:
  - SpacesIntegrationTests: 2 tests passed.
  - QuitRestoreIntegrationTests: 2 tests passed.
  - LiveTrackingTests: 6 tests passed.
  - No exact-event expectation tripped on the new event.

## VM re-check G-03-8 (test 17)

**Setup.**
- The lock `.build/pane-vm.lock` was taken with `mkdir` and released with `rmdir`. `ls -d` fails afterwards.
- `scripts/build-debug.sh --release` exited 0. The app was copied with ditto and bumped from the installed 0.3.6 / 1004 to **0.3.7 / 1005**.
- It was re-signed with `Developer ID Application: Ken Scott (S2K7P43927)`, `--options runtime --timestamp`, and `bump/ent.plist`, which is identical to the build's entitlements. The DR is unchanged (`… leaf[subject.OU] = S2K7P43927`).
- The guest's layout and hints were saved to /tmp/layout-before-0323.json and /tmp/hints-before-0323.json (md5 `621565f2…`). Pane was quit, the app was installed with a tar pipe, and `codesign --verify --strict` passed in the guest.
- After `open`, the log showed `permission notTrusted -> probing`, then `probing -> ready`. Guest: Tart pane-test 192.168.64.18, display Spaces [1, 41].

**Space 2 setup.**
- At the start, the Space 41 desk was empty (dropped by the earlier builds).
- I showed Space 41 (⌃→). After the settle delay, Pane admitted Notes#150 and reminders#693 as floating.
- I clicked Notes and pressed ⌃⌥⌘D. Space 41 was then `docked ['Notes#150'] floating ['reminders#693:present']`. **Notes' recorded tile was `370 37 642 664`.**
- I showed Space 1 again. Space 1 frames: Finder 580 `12 158 460 326`, Finder 731 `167 37 460 447`, Terminal 160 `794 37 221 659`, TextEdit 578 `639 37 143 447`, Safari 669 `12 139 574 224`, Finder 546 `12 37 460 326`, TextEdit 202 `12 496 770 205`, TextEdit 722/567 `12 37 143 326`.

**Clean cycle (`/tmp/cycle.sh g38clean`, from Space 1).** Relaunched at 02:09:16.

| | session | Space 1 desk | Space 41 desk |
|---|---|---|---|
| a | cleanExit false | docked [Terminal#160, TextEdit#202, TextEdit#578, finder#731] floating [finder#546, TextEdit#567, Safari#669, finder#580, TextEdit#722] | docked [Notes#150] floating [reminders#693] |
| b | cleanExit true | identical | docked [Notes#150] floating [reminders#693] |
| c | cleanExit false, recoveryLaunch false | identical | **docked [Notes#150] floating [reminders#693]** |

- The `world` JSON was equal in a, b and c (a==b True, b==c True). Before this plan, c was `docked [] floating []`.
- After showing Space 41, Notes was at **`370 37 642 664`** (same as recorded) and still docked. layout.json's Space 41 desk was unchanged. Showing Space 1 again gave the same Space 1 frames as before (diff empty).

**Crash cycle (`/tmp/cycle.sh g38kill kill`).** Relaunched at 02:10:08.

| | session | Space 41 desk |
|---|---|---|
| a | cleanExit false | docked [Notes#150] floating [reminders#693] |
| b | **cleanExit false** (SIGKILL) | docked [Notes#150] floating [reminders#693] |
| c | **recoveryLaunch true** | **docked [Notes#150] floating [reminders#693]** |

- The Space 1 desk was identical in a, b and c, and the `world` JSON was equal in all three.
- After showing Space 41, Notes was at **`370 37 642 664`**, docked, and the desk was unchanged.
- **Live-docked proof:** I moved Notes with `/tmp/axset Notes 150 300 100 642 600`. Three seconds later Pane had put it back at `370 37 642 664`. That correction is only made for a window that is tracked and docked, so the dormant entry had really re-attached.

**Prune.**
- Script Editor did not work. `make new document` produced two windows with subrole `AXDialog`, offscreen and with no Space, so Pane would never admit them. I quit Script Editor (`quit saving no`) and used **TextEdit** instead, closing the document by name. TextEdit also has windows on Space 1, which is why I closed by name and not "document 1".
- Both osascript paths raised a guest Automation consent prompt ("sshd-keygen-wrapper wants access to control …"). I clicked Allow in the test VM.
- On Space 41, `make new document` gave "Untitled 6", window 2018, `AXStandardWindow` on Space 41. Pane admitted it as floating: `floating ['reminders#693', 'TextEdit#2018']`.
- I showed Space 1 and ran `/tmp/cycle.sh g38prune`, relaunched at 02:15:35. In c, Space 41 still read docked [Notes#150] floating [reminders#693, TextEdit#2018], so 2018 was dormant.
- Prune timeline:
  - 02:15:54: `close document "Untitled 6" saving no`, sent from Space 1.
  - `/tmp/spaceprobe TextEdit`: 0 entries for id 2018, so it left the CG list.
  - 02:15:57: 2018 was gone from layout.json, **3 s after the close** (one sweep, the liveWindowsChanged feed and the debounced save). Space 41 was `docked ['Notes#150'] floating ['reminders#693:present']`.
- No fault and no "not tracked" log line appeared in the last 3 minutes.
- The CG path was exercised live. The appTerminated path is covered only headlessly.

**Restore.**
- Script Editor is not running.
- `min-size-hints.json` is byte-identical to /tmp/hints-before-0323.json (`cmp`), so nothing needed restoring.
- Notes is left docked on Space 41, Reminders floating there, and Pane 0.3.7 (1005) running.
- The Space 1 frames match the start.
- The older TextEdit documents "Untitled 2–5" were there before this run and were left alone.

## Deviations from Plan

### Auto-fixed / adjusted

**1. [Rule 3 - Blocking] Prune step used TextEdit, not Script Editor**
- **Found during:** Task 3, step 8.
- **Issue:** Script Editor's AppleScript documents came up as `AXDialog`, offscreen and with no Space, so Pane never admits them.
- **Fix:** I used TextEdit's "Untitled 6" (standard window, Space 41) and closed it by name, since TextEdit also has Space 1 windows. The plan allowed another app.

**2. Guest Automation consent granted**
- **Found during:** Task 3, step 8.
- **Issue:** The plan-prescribed `osascript` control of Script Editor and TextEdit raised TCC Automation prompts in the guest.
- **Fix:** I clicked Allow in the VM only. The test VM now lets sshd-keygen-wrapper control Script Editor and TextEdit.

**3. The LayoutRestore unit test went in ArrangerRestoreTests.swift**
- **Why:** That file is not in `files_modified`. It is where the existing `LayoutRestore.reattach` test lives. Only additions were made there (0 removed `#expect`).

**4. Task 2 RED was a compile failure**
- **Why:** The new tests need `liveWindowsChanged` and `hasDormantWindows`, which did not exist yet.

## Known Stubs

None.

## Threat surface

No new surface beyond the plan's threat model.
- T-03-62: mitigated by `isAlive`, which matches the exact ID and pid and never a synthetic ID, and by `planShown` skipping untracked windows.
- T-03-63: mitigated by the paused, nil and empty guards. AXWindowSystem reports nil while paused, and tests pin the locked, unknown and empty cases.
- T-03-64 and T-03-65 are accepted as planned.

## Self-Check: PASSED

- All 11 modified files exist.
- Commits fbfa115, 7f80cc7, 072d2ad, 9360463, 812678a and 9431642 are ancestors of HEAD.
- No STATE.md or ROADMAP.md edits.
