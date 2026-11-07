---
phase: 09-polish-ship
plan: 30
subsystem: engine
tags: [tabs, close-rule, macos-27, d-25, gap-closure]
status: complete
requires: [09-26, 09-29]
provides:
  - "WindowTracker.closingGroups: D-25 confirmation of a whole native tab group closed and kept alive"
  - "Fixture commands close-keep and close-group"
  - "Live tests aNativeTabGroupItsAppClosesWholeAndKeepsAliveLeaves and closingTheShownTabOfAKeptAliveGroupKeepsTheGroup"
affects: [09-27, 09-28]
tech-stack:
  added: []
  patterns: ["pending group = .recheck without CloseRule, so needsQuickRecheck schedules the confirming refresh"]
key-files:
  created: []
  modified:
    - Sources/TransomEngine/WindowTracker.swift
    - Sources/TransomEngine/CloseRule.swift
    - Sources/TransomFixtureApp/main.swift
    - Sources/TransomTestSupport/FakeWindowSystem.swift
    - Tests/TransomMacIntegrationTests/TabsIntegrationTests.swift
    - Tests/TransomEngineTests/CloseScenarioTests.swift
    - .planning/phases/09-polish-ship/deferred-items.md
    - docs/release-notes-0.9.0.md
decisions:
  - "D-25: a tab group closed whole and kept alive is confirmed when its shown tab answers -25202, no tab is listed or on screen, a member lingers in CG, its last Spaces include a shown Space and the app is not hidden, twice settleDelay apart; then its shown tab is decided as a non-member"
  - "D-25 (orchestrator option 1): while a tab of such a group is still on screen (27.2 orders the shown tab out after AX reports it gone) the group is pending with no clock started, so a quick recheck follows"
metrics:
  duration: "~75 min"
  completed: 2026-11-07
estimate:
  tokens: 80000
  tasks: 3
actuals:
  tokens: 10000
  tasks: 3
  commits: 6
plan_head_before: 9768f7c4aa78a2438ac2e79d1caf8323a7e1259c
plan_head_after: 2a421b3ab21de47b9644930a363b2e718e9fbbdb
---

# Phase 9 Plan 30: D-25 native tab group closed whole and kept alive Summary

When an app closes a whole native tab group and keeps the windows alive, Transom now frees the group's tile on both macOS 27.2 (0.67 s) and 15.7 (0.39 s). The rule is a two-refresh group confirmation in `WindowTracker`, built on AX -25202 for the shown tab, with no tab listed or on screen, and on the CG and Space facts.

## Tasks

| Task | Commit | What |
|------|--------|------|
| 1 | 4dd012b | Fixture `close-keep` / `close-group`; live D-25 test with `tab group facts:` lines; live Cmd-W guard with `cmd-w facts:` |
| 2 RED | 42a9d47 | `KeptAliveTabGroupTests`: 6 shape rows + other-Space scenario fail; 5 guards pass |
| 2 GREEN | 21ef9a2 | `closingGroups` / `confirmClosedTabGroups`; `decide` gets `pendingGroups` / `closedGroups`; CloseRule doc |
| 2b RED | 583b620 | `aKeptAliveTabGroupStillOnScreenAtTheFirstRefreshIsRechecked` fails (no quick recheck, state absent); fake passthrough `needsQuickRecheck` |
| 2b fix | bec97fa | Still-on-screen look = pending without a clock |
| 3 | 2a421b3 | deferred-items 09-30 record, 09-29 (a) resolved; release-notes Fixes bullet |

## Measured shapes (Task 1, for Task 2)

- 27.2 at closed+3s: the shown tab 67 shows `ax=-25202 listed=false inCG=true onScreen=Optional(false) spaces=Optional(Set([1]))`. The hidden tabs show `inCG=true onScreen=false spaces=Set([])`. Matching row: "27.2: shown ordered out, hidden no Space".
- 15.7 at closed+3s: all three tabs show `ax=-25202 listed=false inCG=true onScreen=Optional(false) spaces=Optional(Set([]))`. Matching row: "15.7: all on no Space".
- Live control on both VMs: exactly one tab listed, with `ax=0`. Cmd-W: the next tab was listed after 0 ms on both.
- Stop rule S1 to S6 held. S5: 15.7 also kept the group before the fix.

## Deviations from Plan

### Auto-fixed / orchestrator-approved

**1. [Checkpoint, orchestrator chose option 1] 27.2 needed a follow-up refresh**
- **Found during:** Task 3, first 27.2 Tabs proof (`.build/09-30-tabs-vm27.log`). Latency was 3.07 s with `state=absent`.
- **Issue:** `closed+0` showed the shown tab still `onScreen=Optional(true)`. The first refresh did not see the group as closed, so CloseRule's tab-member row decided it absent, which asks for no recheck. Nothing then refreshed the app until the 5 s sweep. 15.7 already passed (0.37 s).
- **Fix:** a group that looks closed except for a tab still on screen is now pending with no clock started. Its decision is `.recheck`, so a refresh comes `settleDelay` later. The clock starts at the first refresh where every condition holds. The scenario was written first and failed first (`.build/09-30-red2.log`).
- **Commits:** 583b620 (RED), bec97fa (fix).

**2. [Rule 3] `FakeWindowSystem.needsQuickRecheck(pid:)`**
- A one-line passthrough, so the new scenario can assert that the tracker asks for the follow-up refresh. The file is test support and is outside the plan's file list. Commit 583b620.

**3. [Rule 3] The test method `aKeptAliveTabGroupClosesOnceAfterTheSettleDelay` is `fileprivate`**
- Its argument type `KeptAliveShape` is file-private, as the plan specifies.

**4. [Rule 3] In the fake, a released row also clears `listedInAX`**
- The fake's `close` keeps `listedInAX` true. A released window is not in AXWindows, so the `nil` rows of `KeptAliveShape` call `close` and then clear `listedInAX` and `onScreen` through `update`.

**5. Live run accounting**
- `.build/09-30-tabs-vm27-2.log` never reached the tests (SSH connect timed out at boot), so it was rerun into `-3`, which passed.
- 15.7 Tabs ran a third time (`-2`) so the final code has its own 15.7 proof.

## Live / host evidence

- 27.2: Tabs `.build/09-30-tabs-vm27-3.log` 3/3 passed (0.673 s); TabGroup 7/7; Close passed.
- 15.7: Tabs `.build/09-30-tabs-vm15-2.log` 3/3 passed (0.388 s); TabGroup 7/7 (no L46 flake); Close passed.
- Host: `.build/09-30-full.log` has four passed "Test run with" lines (271, 602, 126, 1344) and `no-appkit: OK`.

## Not covered

These are recorded in deferred-items.md:
- (a) a group on a Space no display shows waits until that Space shows;
- (b) with the Spaces lookup off, a closed group stays tracked;
- (c) a hidden app's group waits until the app is shown;
- (d) Cmd-W timing is assumed under 250 ms (measured 0 to 19 ms);
- (e) a native fullscreen group was not measured;
- (f) a tab still on screen more than about 2 s after the close waits for the 5 s sweep.

## Known Stubs

None.

## Self-Check: PASSED

- All six commits are ancestors of HEAD: 4dd012b, 42a9d47, 21ef9a2, 583b620, bec97fa, 2a421b3.
- The modified files exist, and the logs named above exist in `.build/`.
