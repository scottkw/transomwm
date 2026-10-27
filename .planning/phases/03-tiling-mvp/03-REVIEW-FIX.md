---
phase: 03-tiling-mvp
fixed_at: 2026-10-27T01:40:00Z
review_path: .planning/phases/03-tiling-mvp/03-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-10-27T01:40:00Z
**Source review:** .planning/phases/03-tiling-mvp/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (2 critical, 5 warning; the 3 Info findings are out of scope)
- Fixed: 7
- Skipped: 0

## Verification

All checks ran in the **main checkout**. No worktree was used, as the caller asked.

- Headless `swift test` on the host (live suites skip): 923 tests in 4 test runs (193 + 196 + 42 + 492), 0 failures. 62 of them are live AX tests, and they were skipped on the host.
- `scripts/check-no-appkit.sh`: OK (40 files).
- Live run in the Tart VM through the fixed `scripts/vm-live-test.sh 'ArrangeIntegrationTests|ButtonFrameIntegrationTests'`: 7 tests, 6 passed and 1 skipped (fullscreen, which needs opt-in). `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` passed. After the run, Pane was running again in the guest, no PaneFixtureApp was left, and the local lock was released.
- Each fix has a headless test that ran. For WR-01, WR-02 and WR-03, the test was run and seen to fail before the fix.

## Fixed Issues

### CR-01: The green-button fallback now eats clicks meant for menus, context menus and the Dock

**Files modified:** `Sources/PaneMac/CGWindowList.swift`, `Tests/PaneMacTests/TopmostWindowTests.swift`
**Commit:** ae5560e
**Applied fix:** `topmost(at:in:excludingPID:display:)` walks the front-to-back list. It looks through a window above layer 0 only when that window's bounds cover the whole display under the point; this is the macOS 15 Dock overlay from G-03-4. Any other window above layer 0 that contains the point returns nil, so the click is not swallowed. `topmostWindow(at:)` gets the display with `CGGetDisplaysWithPoint` + `CGDisplayBounds`. When the display is unknown, nothing is looked through. New tests cover a layer-101 menu, a small layer-20 Dock tile, and the case where the display is unknown. The G-03-4 test (Dock overlay listed first) still passes. Not done: the review's optional idea of letting Pane's own layer-101 status menu block the swallow. Own-pid windows are still skipped.

### CR-02: A fixed-size window now writes a permanent, grow-only minimum for its whole app

**Files modified:** `Sources/PaneEngine/MinimumSizeLearner.swift`, `Sources/PaneEngine/WindowTracker.swift`, `Sources/PaneEngine/WindowSystem.swift`, `Sources/PaneMac/AXWindowSystem.swift`, `Tests/PaneEngineTests/MinimumSizeLearnerTests.swift`, `Tests/PaneMacTests/MinimumHintsStoreTests.swift`
**Commit:** 5a65a9a
**Applied fix:** Each candidate axis now records whether it came from an unmoved promotion. The learner keeps a second, persistable map, which holds seeds plus axes learned from refusals that moved the window, next to the effective minimum. `WindowInfo` gains `persistableMinimum`. The tracker merges only that value into `bundleHints`, and `AXWindowSystem.emit` reports only that value to `onLearnedMinimum`, which is what writes `min-size-hints.json`. The window keeps its full effective `learnedMinimum`, so G-03-6 behaves as before: a fixed-size window learned from unmoved refusals still floats instead of overlapping. `TooBigDockedWindowTests` and `FrameScenarioTests` still pass. No judgement call that changes G-03-6 was needed. The reset UI for bundle hints that the review suggested was not added.

### WR-01: During a live gap drag, lost-room floats are undone and the notice repeats on every drag event

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerResizeTests.swift`
**Commit:** 58c7984
**Applied fix:** When a live gap move is active, `replan()` first runs a new `floatLostRoom()` on the committed World. This is the same `planFloatingLostRoom` pass that `planShown` runs. It returns the one `.lostRoom` notice, and then the transient live move is planned. The comment at `replan(with:on:)` is updated to match (this covers the WR-01 half of IN-01). New test: a window that loses its room mid-drag floats for real with one notice, and later drag events, a tick and mouse-up give no notice.

### WR-02: The Planner's greedy floater drop removes more floaters than needed, and drops width-only hints last

**Files modified:** `Sources/PaneEngine/Planner.swift`, `Tests/PaneEngineTests/PlannerTests.swift`
**Commit:** a06ff54
**Applied fix:** After the area-ordered drop loop, each dropped floater is tried again, last dropped first. It is kept if the docked windows still fit (unfit stays a subset of the baseline). Two new PlannerTests cases use H[Desktop, Notes, x], where the Desktop's own share (288 pt) is below a 300 pt floater. One covers over-dropping (a 300x600 floater versus a 768x200 one). The other covers a width-only 768x0 hint that sorts last.

### WR-03: `refusalRetried` is never cleared, so a window docked again into the same tile is never retried or learned

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/TooBigDockedWindowTests.swift`
**Commit:** 921b7af
**Applied fix:** `planShown` drops the `refusalRetried` entry of any window that is not in any desk's tree. A window that is floated and later docked back into the same rect therefore gets its one retry again. New test in `RefusalRetryBoundTests`. The review also suggested clearing the entry when a write fits its tile. That part was left out: in the fake, the retry's own honoured write would clear the entry, which breaks the existing T-03-61 "retried once" bound test. It is not needed for the scenario in the finding.

### WR-04: `vm-live-test.sh` says "VM busy" on a fresh checkout

**Files modified:** `scripts/vm-live-test.sh`
**Commit:** 05c9694
**Applied fix:** Added `mkdir -p .build` before `mkdir .build/pane-vm.lock`. The lock path and its behaviour for existing callers are unchanged.

### WR-05: An interrupted VM run leaves Pane quit and fixture apps running in the guest

**Files modified:** `scripts/vm-live-test.sh`
**Commit:** 985b354
**Applied fix:** The remote script defines `cleanup` (kill PaneFixtureApp, relaunch Pane if it was running) as an EXIT trap, plus `trap 'exit 130' HUP INT TERM`. The script uses `ssh -t` so a Ctrl-C or a dropped session reaches the guest. The fixed `sleep 2` after quitting Pane is replaced by polling for up to 5 s, and the run stops with an error if Pane is still running. The rendered remote script parses under both zsh and bash, and shellcheck is clean. The normal path passed in the VM run above. The Ctrl-C and dropped-session paths were not exercised.

---

_Fixed: 2026-10-27T01:40:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
