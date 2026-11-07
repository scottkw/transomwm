---
phase: 09-polish-ship
plan: 29
subsystem: engine/close-rule
tags: [D-23, close-rule, macos-27, gap-closure, tdd]
status: complete
requires: [09-25]
provides:
  - "CloseRule ordered-out row (cgOrderedOut): AX -25202 + CG entry offscreen on a shown Space closes (D-23)"
  - "WindowTracker.decide computes cgOrderedOut from onScreen, windowSpaces and displays' currentSpaceID"
  - "TabGroupIntegrationTests logs 'closed window 0 facts:' (not asserted)"
affects: [09-26, 09-27, 09-28]
tech-stack:
  added: []
  patterns: ["two-source close rule extended with a second form of CG evidence, gated on AX -25202"]
key-files:
  created: []
  modified:
    - Sources/TransomEngine/CloseRule.swift
    - Sources/TransomEngine/WindowTracker.swift
    - Tests/TransomEngineTests/CloseRuleTests.swift
    - Tests/TransomEngineTests/CloseScenarioTests.swift
    - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift
    - .planning/phases/09-polish-ship/deferred-items.md
decisions:
  - "D-23: a CG entry present, offscreen and on a Space a display shows counts as CG's 'gone' evidence only when AX answers -25202; no macOS version check"
  - "On macOS 15.7 a kept-alive closed window also stays in the CG list, with an empty Space set, and the existing G-03-9 no-Space row closes it; 09-25's 'the entry leaves the list on 15.7' is corrected"
requirements: [WIN-09, WIN-02, TILE-03, TABS-03, TABS-02]
metrics:
  duration: ~15 min
  completed: 2026-11-07
actuals:
  tokens: 5400    # chars/4 over the realized diff (21626 chars)
  tasks: 3
  commits: 4
plan_head_before: 97cae47c426070c40d85009723f4d0151c62e6b5
plan_head_after: 6506303b7a6a28c7f22ce7d34576541a75b15beb
---

# Phase 9 Plan 29: macOS 27 close of a kept-alive window (D-23) Summary

On macOS 27.2 a window its app closes but keeps alive is now confirmed closed in 0.382 s. `CloseRule` accepts "present in CG, offscreen, on a shown Space" as the second source. The row applies only when AX also answers -25202.

## What changed

- `CloseRule.decide` takes a new `cgOrderedOut: Bool` (between `cgSpacesKnownEmpty` and `isKnownTabMember`). In `(.alive, .invalidElement, true)` the tab-member check still comes first. After that the rule returns `.closed` when `cgSpacesKnownEmpty || cgOrderedOut`, and `.recheck` otherwise. The terminated rows are unchanged. The doc comment now has a D-23 paragraph and a new row in its table.
- `WindowTracker.decide` builds `cgByID` and `shownSpaces` once per call. A window is `orderedOut` only when its shown ID's CG entry exists and is not `onScreen`, and its known Spaces overlap the shown Spaces. Nil Spaces and an empty shown set never count.
- Tests:
  - 5 new `CloseScenarioTests` scenarios, with a `shownSpaceFake()` helper and a `refreshFiveTimes` helper.
  - 8 new `CloseRuleTests` rows named "ordered out".
  - `noSingleSourceEverCloses` now also covers `cgOrderedOut: true`.
- `TabGroupIntegrationTests.closeAndMinimizeCommandsActOnFixtureWindows` prints a `closed window 0 facts:` line. It is logged only and not asserted. The latency assertion is unchanged.

## Live evidence

| Log | Result |
|-----|--------|
| `.build/09-29-red.log` | Before the change, both D-23 scenarios failed (✘) and the 3 guards passed |
| `.build/09-29-engine.log` | 1336 TransomEngineTests passed |
| `.build/09-29-tabgroup-vm27.log` | 7/7 on 27.2. Facts: `AXRole error -25202, in CG list true, onScreen Optional(false), spaces Optional(Set([1])), shown Spaces [1]`. Confirmed in 0.382 s |
| `.build/09-29-tabgroup-vm15.log` | 7/7 on 15.7. Facts: `AXRole error -25202, in CG list true, onScreen Optional(false), spaces Optional(Set([])), shown Spaces [1]`. Confirmed in 0.109 s |
| `.build/09-29-close-vm27.log` / `-vm15.log` | `closeFreezeHideAndQuitAreDecidedByTwoSources` passed on both |
| `.build/09-29-tabs-vm27.log` / `-vm15.log` | TabsIntegrationTests passed on both |
| `.build/09-29-full.log` | Host gate passed: 4 "Test run with … passed" lines, `no-appkit: OK (69 files)` |

Every suite passed on its first run, with no reruns. The 09-25 L46 launch flake did not recur. Afterwards there was no tart process, no VM lock and no host fixture, and both VMs were stopped.

## Deviations from Plan

**1. [Finding, not a code change] The 15.7 facts differ from what the plan expected**
- **Found during:** Task 2.
- **Expected:** the plan, following 09-25's inference, said the 15.7 facts line "should show the entry gone from the CG list".
- **Measured:** on 15.7 the entry is still in the CG list, but its Space set is empty. The existing G-03-9 no-Space row closed it in 0.109 s, the same latency 09-25 measured. 09-25 had measured 27.2 only, and its 15.7 claim was inferred.
- **Why this is not a RULE 0 stop:** the 27.2 facts match 09-25's measurement exactly, 15.7 passed unchanged, and the new row does not decide on 15.7 (an empty set misses the shown Space). The plan's "no OS check" rationale still holds in effect: the row adds evidence only where the old rows rechecked.
- **Recorded:** in the deferred-items 09-29 section as a correction to 09-25.

Task 2 produced only `.build` logs, which are gitignored, so it has no commit of its own.

## Known Stubs

None.

## Not covered (also in deferred-items)

- (a) A native tab group whose app closes the whole group and keeps it alive on macOS 27. The group may stay tracked.
- (b) With the Spaces lookup off, a kept-alive closed window keeps rechecking.
- (c) If Spaces switch before Transom refreshes, a kept-alive closed window keeps rechecking until its Space shows again.

## Commits

- e98bd12 test(09-29): failing scenarios for a closed window kept alive on macOS 27 (D-23)
- 555afce feat(09-29): CloseRule closes a window ordered out on a shown Space once AX says it is gone (D-23)
- 430d689 test(09-29): log the closed window's AX, CG and Space facts; TabGroup passes on macOS 27.2 (D-23)
- 6506303 docs(09-29): record the D-23 close fix and its live evidence

## TDD Gate Compliance

- RED: e98bd12. Both D-23 scenarios failed for the expected reason: no destroy event.
- GREEN: 555afce. 1336 engine tests passed.
- REFACTOR: none needed.

## Self-Check: PASSED

The 6 modified files exist. All 4 commits are ancestors of HEAD. The acceptance greps came back at or above the plan's thresholds: cgOrderedOut 3 in CloseRule and 1 in WindowTracker, D-23 2, currentSpaceID 1, "ordered out" 9, KeptAlive 3, facts line 1, latency assertion 1, isReleasedWhenClosed 3.
