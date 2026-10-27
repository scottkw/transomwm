---
phase: 02-window-control
plan: 19
subsystem: window-tracking
tags: [swift, tab-groups, tabgrouptracker, fake-window-system, gap-closure, G-02-10]
status: complete

requires:
  - phase: 02-window-control
    provides: "02-10/02-14/02-17 TabGroupTracker (slot, Cmd-T opener, room-rule join, orphan handoff, blind-switch refusals) and FakeWindowSystem tab groups"
provides:
  - "TabGroupTracker links a newly shown tab to the tab shown just before it by timing (wentHidden), not CG bounds"
  - "TabGroupTracker groups keep their own hidden members whatever their bounds; the tab shown just before ranks first under the AXTabs cap"
  - "TabGroupTracker timing join: a new tab with room under its AXTabs count joins the group whose shown tab went hidden"
  - "Private origin-and-width tie-break helper TabGroupTracker.nearest(_:to:)"
  - "FakeWindowSystem.newTab(_:in:frame:); selectTab gives the shown tab the group frame; hidden tabs keep their frames; frame writes move only the shown tab"
affects: [phase-02-uat, phase-03-tiling]

actuals:
  tokens: 36000
  tasks: 2
  commits: 6
plan_head_before: a2e3e53a5cfd0ed423694a2b7ce111ab3af50444
plan_head_after: 062d6057fb867c95af4866d9d74cd85a3bcbf0be

tech-stack:
  added: []
  patterns:
    - "Timing evidence over geometry for hidden native tabs: listed at the app's last update, unlisted now, offscreen in the CG list, AX-valid, not on a known other Space; bounds only find candidates and break ties"

key-files:
  created:
    - .planning/phases/02-window-control/tdd/02-19-task1-red.json
    - .planning/phases/02-window-control/tdd/02-19-task2-red.json
  modified:
    - Sources/TransomEngine/TabGroupTracker.swift
    - Sources/TransomTestSupport/FakeWindowSystem.swift
    - Tests/TransomEngineTests/TabScenarioTests.swift
    - Tests/TransomEngineTests/TabGroupTrackerTests.swift
    - Tests/TransomEngineTests/FakeWindowSystemTests.swift

key-decisions:
  - "02-19: on macOS 15.7.7 a hidden tab keeps its CG bounds from when it was hidden (G-02-10), so TabGroupTracker links a shown tab to the tab shown just before it by timing (wentHidden), keeps own members whatever their bounds, and joins a new tab to the group whose shown tab went hidden; bounds stay a candidate finder and a tie-break (slot, then origin and width, then lowest ID)"
  - "02-19: the timing opener and timing join are refused after a blind Space switch (spaceChanged without Space data), like the 02-17 orphan handoff and folds"

patterns-established:
  - "FakeWindowSystem tab groups model stale hidden-tab bounds: a new tab may open at its own frame, a shown tab takes the group frame, hidden tabs keep theirs, and frame writes move only the shown tab"

requirements-completed: [WIN-06, WIN-02, WIN-09]

metrics:
  duration: 8 min
  completed: 2026-10-27
---

# Phase 2 Plan 19: Tab groups with stale hidden-tab bounds stay one row (G-02-10) Summary

**TabGroupTracker now follows a shown tab by timing evidence the OS keeps current (listed last update, hidden now, offscreen in CG, AX-valid, not on a known other Space) instead of 1 pt bounds matches, and groups keep their own hidden members whatever their bounds. Terminal's taller first Cmd-T (E1), Finder's Cmd-T after a resize (E4), Cmd-W and Transom frame writes all stay one row on the fake, in every Space-data mode, with nothing destroyed.**

BASE (recorded before the first commit): `a2e3e53a5cfd0ed423694a2b7ce111ab3af50444`

## Performance

- **Duration:** about 8 min
- **Started:** 2026-10-27T21:03:20Z
- **Completed:** 2026-10-27T21:11Z
- **Tasks:** 2 (Task 1 tracer, Task 2 auto), both TDD
- **Files modified:** 5 source/test files, plus 2 RED records

## Accomplishments

- Fake fidelity. `newTab(_:in:frame:)` opens a tab at its own frame, or else at the frame of the group's shown tab. `selectTab` gives the tab it shows the group frame (debug E2). Hidden tabs keep their frames, and the private `write` moves only the shown tab (debug E4). Before this, no test could see stale hidden-tab bounds.
- Timing opener (Task 1). When no opener is in the slot, a brand-new tab (AXTabs >= 2) takes the standalone that `mayBeOpener`, `wentHidden`, `canBeHiddenTab` and is not on a known other Space. When there are several, the slot match wins, then the smallest |dx| + |dy| + |dwidth|, then the lowest ID (`nearest(_:to:)`). An opener found outside the slot still joins the hidden-tab pool at tier 1.
- Persistent members (Task 2). When v binds an existing group, the group keeps its own members that are not v, are offscreen, AX-valid, `canBeHiddenTab`, and not on a known other Space. They rank at tier 0, ordered previous shown tab first, then slot members, then lowest ID.
- Timing join (Task 2). This runs after the room-rule join and before the orphan handoff, when there is no index and no opener and AXTabs >= 2. The new tab joins a group (not the refused one) whose `shown` went hidden, is not on a known other Space, and has fewer members than v's AXTabs. Ties go through `nearest`, then the lowest leader ID.
- The type doc comment now records the corrected premise (G-02-10) and the residual limits in its `shortcut:` note.

## Task Commits

1. **Task 1, fake fidelity:** `3514f43` test(02-19): fake hidden tabs keep their own frame (G-02-10)
2. **Task 1, RED:** `df24856` test(02-19): failing E1 scenario and timing-opener unit cases (G-02-10)
3. **Task 1, GREEN:** `859c77c` feat(02-19): link a Cmd-T tab to its opener by timing, not bounds (G-02-10)
4. **Task 2, RED:** `a473a1a` test(02-19): failing E4, Cmd-W and frame-write scenarios; member persistence and timing join cases (G-02-10)
5. **Task 2, GREEN:** `7f764ad` feat(02-19): groups keep stale-bounds members and follow a shown tab by timing (G-02-10)
6. **Known-limit trace (plan-checker advisory 1):** `062d605` test(02-19): pin the timing-opener misattribution limit and its recovery (G-02-10)

## TDD Gate Compliance

- Task 1: `test(02-19)` df24856 comes before `feat(02-19)` 859c77c. In `tdd/02-19-task1-red.json`, E1 fails in all three modes with `[[10, 10, 1], [40, 40, 2]]`, (a), (b) and (e) fail, and the controls (c) and (d) pass.
- Task 2: `test(02-19)` a473a1a comes before `feat(02-19)` 7f764ad. In `tdd/02-19-task2-red.json`, E4 and the frame-write scenario fail in all modes with `[[10, 40, 2], [50, 50, 3]]`, Cmd-W fails, (f) and (g) fail, and the controls (h), (i) and (j) plus the fake write case pass. The `write` change broke no pre-existing test.

## Verification

- `swift test --filter "TabScenarioTests|SpaceTabScenarioTests|FoldGuardTests|TabGroupTrackerTests|FakeWindowSystemTests|WindowTrackerTests"`: 110 tests in 8 suites passed (before the trace test).
- `swift build && env -u TRANSOM_LIVE swift test`: all runs passed. "Test run with 554 tests in 53 suites" (534 at BASE, so 20 new tests), plus 193, 200 and 42 in the other runs. No "✘". Integration suites stayed gated off.
- `scripts/check-no-appkit.sh`: `no-appkit: OK (40 files)`.
- `grep -c "frame: Rect? = nil" Sources/TransomTestSupport/FakeWindowSystem.swift` = 1. `grep -c wentHidden Sources/TransomEngine/TabGroupTracker.swift` = 3. `grep -c G-02-10 Sources/TransomEngine/TabGroupTracker.swift` = 4.
- `git diff "$BASE"..HEAD --stat -- Sources/TransomEngine/CloseRule.swift Sources/TransomEngine/WindowTracker.swift` is empty.
- Plan-checker advisory 2: `git diff "$BASE"..HEAD -- Tests/ | grep '^-.*#expect'` printed **nothing**. `git diff "$BASE"..HEAD -- Tests/ | grep '^-' | grep -v '^---'` is empty as well, so the Tests/ diff removes or edits no line at all. CR-01 (`aMemberWhoseTabCountChangedStillRebindsItsGroupWhileTheShownTabIsStillThere`), WR-01 (`aNewTabMissingFromAStaleCGListStillTakesTheWindowItWasOpenedFrom`, `cmdTSeenWithAStaleSweepCGListStaysOneWindow`) and D1/D2 (`cmdTAndASwitchToTheLeaderInOneRefreshStayOneGroup`, `cmdTAndASwitchToAnotherTabInOneRefreshStayOneGroup`) are unchanged and pass.

## Deviations from Plan

**1. [Rule 2 - test hygiene] The E1 scenario binds `rows` before each `#expect`**
- **Found during:** Task 1 RED
- **Issue:** `#expect(await summary(fake) == ...)` prints `<not evaluated>` for the async side, so the RED record could not show the two-row summary that the acceptance criteria ask for.
- **Fix:** each new scenario stores `let rows = await summary(fake)` and then expects on `rows`. This affects only new tests; no existing test was touched.
- **Commit:** df24856 (and a473a1a for the Task 2 scenarios)

**2. [Plan-checker advisory 1] Added the known-limit scenario `knownLimitAWindowLeavingTheSpaceWithACmdTCanBeTakenAsItsOpener`**
- **Why:** to confirm the misattribution recovery path against the final code, not by reasoning alone (see Known limits). It passes in all three modes and asserts that nothing is destroyed.
- **Commit:** 062d605

**3. Unit case (j) is a control on 41 only**
- (j) builds a three-tab group 10/40/41. 41 is then listed with AXTabs 1 while offscreen (minimized) and at different bounds. The test asserts 41 is never kept and never bound. It does not assert that 10 is kept, because then it would fail before the fix and stop being a control, as the plan wants (j) to be.

No change to CloseRule or WindowTracker. No Rule 4 stop.

## Known limits

- **Blind Space switch.** A Cmd-T or a tab switch in the same update as a Space switch without Space data is linked only through the slot. `wentHidden` is false when `blindSwitch` holds, so the timing opener, timing join and persistence evidence do not apply. A stale-bounds tab there can still leave a row until the app relaunches. This is rare and errs the safe way: no merge, no destroy. Unit cases (c) and (h) cover it.
- **Two windows going hidden in one refresh.** They are told apart by the slot, then by origin and width, then by the lowest ID. A same-app window that leaves the current Space in the same refresh as a brand-new tab, other than by a Space switch, can be taken as its opener (or, through the timing join, its group). That misattributes an identity; it never loses a window.
- **Recovery after a timing-link misattribution (advisory 1, confirmed against the final code by `knownLimitAWindowLeavingTheSpaceWithACmdTCanBeTakenAsItsOpener`):**
  - Setup: W (5) and O (10) are standalone at the same frame. W is moved to Space 2 in the same refresh as Cmd-T in O opens 40, 28 pt taller.
  - Without Space data, both went hidden at the same origin and width, so W (lowest ID) becomes the opener and leader: `[[5, 40, 2], [10, 10, 1]]`. O stays a standalone row, as before this plan.
  - When W comes back as a single window (AXTabs 1), `update` line 111 (`group.members.subtract(listedSingles.subtracting([group.leader.windowID, group.shown]))`, the "line ~97" of the advisory) keeps W as leader. W ranks first (it leads a group) and rebinds the group through its membership. With AXTabs 1 its cap is 0, so the group becomes {W} with tabCount 1. Then 40 is no longer a member and finds no room join (empty slot) and no timing join (W is listed). With no orphan handoff, it founds a fresh identity: `[[5, 5, 1], [10, 10, 1], [40, 40, 2]]`, created `[5, 10, 40]`, destroyed `[]`. The advisory's description holds: nothing is destroyed.
  - With Space data, W is known to be on Space 2, so O is the opener: `[[5, 5, 1], [10, 40, 2]]` throughout.
  - Not pinned in the test, but traced once in a scratch run (no Space data): when O's tab is later shown, it room-joins group 40 and O's standalone identity is folded (one `windowDestroyed(10)` after the two-refresh fold guard). Its tab stays tracked as the visible member of identity 40. For the one refresh before the fold completes, window ID 10 is both identity 10's ID and identity 40's visible member, which trips the scenario helper's two-identities check. That transient belongs to the existing fold/heal path (debug E2). The pre-fix E1 RED run showed the same check firing at its `selectTab(10)` step. It only occurs after a misattribution.
- **Timing join without Space data.** The timing join does not require a brand-new tab. Without Space data and without a Space-switch notification (already a documented limit: "a notification that reaches main only after the update that already saw the new Space protects nothing"), a never-seen tab group shown by the switch could join the group whose shown tab the switch hid. This is covered by the existing single-Space `shortcut:`. It merges identities and never destroys a window.
- **Merge All Windows** across windows of different frames is not covered by the timing rules. It was not observed live.

## Hand-off: VM re-check (not run by the executor)

The orchestrator should re-run UAT tests 10 and 11 in the Tart VM (macOS 15.7.7) with a fresh Debug build, using the debug file's E1 steps (Terminal Cmd-N, then Cmd-T) and E4 steps (resize Finder's shown tab with /tmp/axset, then Cmd-T), plus the UAT 10 sequence (Cmd-T twice, Cmd-T with Ctrl-Shift-Tab, Cmd-W). Expected: the "Tracking N windows" header and Tracked Windows match AX and CGWindowList, with one row per tab group. Test 11 was blocked on this gap. Nothing here was run on the host: TRANSOM_LIVE was never set, and no app or fixture was launched.

## Issues Encountered

None.

## Next Phase Readiness

G-02-10 is closed in code and on the fake. The live confirmation is the VM re-check above. Phase 3 tiles can rely on one tracked identity per tab group through Cmd-T, tab switches, Cmd-W and Transom frame writes.

## Self-Check: PASSED

- FOUND: Sources/TransomEngine/TabGroupTracker.swift, Sources/TransomTestSupport/FakeWindowSystem.swift, the three test files, tdd/02-19-task1-red.json, tdd/02-19-task2-red.json
- FOUND commits: 3514f43, df24856, 859c77c, a473a1a, 7f764ad, 062d605 (all ancestors of HEAD)
