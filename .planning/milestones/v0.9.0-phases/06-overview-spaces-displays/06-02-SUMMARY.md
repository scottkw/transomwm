---
phase: 06-overview-spaces-displays
plan: 02
subsystem: spaces
status: complete
tags: [spaces, close-rule, g-03-9, co-visibility, debug-menu, skylight]
requires:
  - phase: 06-01
    provides: "SpacesSnapshot / SpacesProvider.snapshot(); 06-SPIKE.md answers: the G-03-9 ghost answers invalidElement, hidden native tabs report an empty Space set, minimised and ⌘H-hidden windows keep theirs"
provides:
  - "CloseRule.decide(...cgSpacesKnownEmpty:...): G-03-9 rows. Alive + invalidElement + CG present + known-empty Space set closes unless the window is a known tab member. Terminated + CG present + known-empty closes"
  - "WindowTracker passes the fact from context.windowSpaces (nil = unknown, never empty); new terminatedWindowIDs accessor"
  - "AXWindowSystem: terminated rechecks get the Space sets of terminated apps' lingering CG windows; spacesSnapshot (read-only) and visitedSpaces; co-visibility visit 1 s after launch and after each Space change while the lookup is off; spaces-category logs"
  - "CoVisibilitySpaces (Engine, pure): per-display Jaccard >= 0.5 clustering into synthetic IDs from 0x8000_0000_0000_0000, Debug only"
  - "OverviewCopy (TransomMac, AppKit-free) with the S1 spacesLine; Debug submenu S1 line after Multitouch; lookup-off line now 'Spaces lookup: off, using Spaces visited since launch'"
  - "FakeWindowSystem.lingerInCG(_:spaces:) for ghost scenarios"
affects: [06-03, 06-04, 06-05, 06-06]
tech-stack:
  added: []
  patterns:
    - "Known-empty vs unknown Space set: only a non-nil empty set from the lookup counts as 'no Space'; nil never does"
    - "Synthetic co-visibility IDs live only in CoVisibilitySpaces and the AXWindowSystem counter; never a DeskKey, WindowInfo.spaces or layout.json"
key-files:
  created:
    - Sources/TransomEngine/CoVisibilitySpaces.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Tests/TransomEngineTests/CoVisibilitySpacesTests.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
  modified:
    - Sources/TransomEngine/CloseRule.swift
    - Sources/TransomEngine/WindowTracker.swift
    - Sources/TransomTestSupport/FakeWindowSystem.swift
    - Sources/TransomMac/AXWindowSystem.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Tests/TransomEngineTests/CloseRuleTests.swift
    - Tests/TransomEngineTests/CloseScenarioTests.swift
    - Tests/TransomEngineTests/ArrangerSpacesTests.swift
    - Tests/TransomMacTests/MenuCopyTests.swift
key-decisions:
  - "The bounded valid-unlisted row did NOT ship: 06-SPIKE.md A7 shows the ghost answers invalidElement (-25202), so only the invalidElement and terminated rows were added"
  - "A co-visibility visit that joins a Space replaces that Space's window set with the visit's windows, so the cluster follows windows opening and closing instead of growing forever"
  - "The Space shown at launch counts as a visit (lookup off), so 'visited since launch' includes it"
  - "OVER-01 and OVER-04 are not marked complete: this plan only contributes to them (same as 06-01)"
requirements-completed: []
metrics:
  duration: "~12 min"
  started: 2026-10-31T18:02:54Z
  completed: 2026-10-31T18:14:33Z
actuals:
  tokens: 8800
  tasks: 2
  commits: 4
plan_head_before: 7360114dddb8b08e3291f50343d6cf9ccd5f84f4
plan_head_after: 08f079871f758c5cc404e03f7b00d4e7df0549d4
---

# Phase 6 Plan 02: Spaces Runtime Summary

**When a closed window's CG entry lingers with a known-empty Space set (G-03-9), the window now closes and its neighbour reflows. Hidden tabs, minimised windows, hidden windows and the lookup-off case are unchanged. The lookup-off co-visibility map and the S1 Spaces line now appear in the Debug submenu.**

## Accomplishments

- **G-03-9 closed for the running session.** `CloseRule` takes a new `cgSpacesKnownEmpty` fact and has two new rows: an alive app with invalidElement, a CG entry and a known-empty Space set closes (a known tab member still goes `.absent`), and a terminated app's window whose CG entry has a known-empty set closes. No other row changed. `WindowTracker` computes the fact as `inCG && windowSpaces?[shown] == []`, and tab-group `remaining` membership still uses raw CG presence.
- **Live terminated path.** The terminated rechecks used to run with no Space data for terminated apps: the per-app context covered only the observed pid, and `recheckTerminatedSoon` passed nil. `AXWindowSystem.terminatedSpaces` now queries SkyLight only for terminated apps' windows still at layer 0 in the CG list.
- **D-15 co-visibility (Debug only).** `CoVisibilitySpaces` clusters visits per display (Jaccard ≥ 0.5, integer cross-multiplied, largest overlap wins). An empty visit returns the display's last ID unchanged, and `forget(windowID:)` runs on every `windowDestroyed`. `AXWindowSystem` feeds it 1 s after launch and after each Space change, with the latest visit cancelling any pending one, and only while `spacesSnapshot == nil`.
- **Debug lines and logs.** The S1 line ("Spaces: {n} on 1 display", "across {d} displays", ", shared by {d} displays", "{v} visited since launch") sits directly after the Multitouch line. The lookup-off line now reads "Spaces lookup: off, using Spaces visited since launch". The `spaces` logger writes the lookup state at launch and on any on/off change, plus "space {from} → {to} on display {uuid}" for each Space change.

## Task Commits

| Task | Commit | Type | Description |
|------|--------|------|-------------|
| 1 RED | 4c2e98b | test | Failing G-03-9 rows and scenarios; `lingerInCG`; decide parameter, not yet used |
| 1 GREEN | 36ab32f | fix | G-03-9 rows, tracker fact, terminated Spaces in AXWindowSystem |
| 2 RED | 754a0a3 | test | Failing co-visibility, S1 and MenuCopy tests, with compile stubs; lookup-off desk test |
| 2 GREEN | 08f0798 | feat | CoVisibilitySpaces, OverviewCopy, AXWindowSystem wiring, Debug S1 line |

RED evidence for both tasks passed `gsd-tools check tdd-red-evidence` (`RED_EVIDENCE_OK`, target_test_failed).

## TDD Gate Compliance

- Task 1: RED `4c2e98b` failed on its target assertions (the table rows, the terminated ghost and the ghost reflow); GREEN `36ab32f`.
- Task 2: RED `754a0a3` failed on its target assertions (stubs returned 0 or ""); GREEN `08f0798`.
- The tracer gate ran in interactive mode with `end-of-phase` and only automated verify, so it was handled by re-running the checks: the Task 1 verify run after GREEN passed 73 tests.

## Verification

- `swift test --filter 'CloseRuleTests|CloseScenarioTests|TabScenarioTests|ArrangerSpacesTests'`: 73 tests passed, no ✘.
- `swift test --filter 'CoVisibilitySpacesTests|ArrangerSpacesTests|OverviewCopyTests|MenuCopyTests'`: 20 + 19 tests passed, no ✘. `scripts/check-no-appkit.sh` OK (47 files).
- Full host `swift test` without TRANSOM_LIVE (live suites stay disabled): 193 + 316 + 75 + 707 tests passed.
- Acceptance greps: `cgSpacesKnownEmpty` appears 4 times in CloseRule and `cgSpacesKnownEmpty:` once in WindowTracker; `case (.alive, .timedOut, _)` is still present; the old MenuCopy string appears 0 times and the new one once; `syntheticBase` appears only in CoVisibilitySpaces.swift; OverviewCopy has no `import AppKit`.
- No live, VM or event-posting run was needed or made.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Terminated rechecks had no Space data live**
- **Found during:** Task 1
- **Issue:** `recheckTerminated` ran with the observed app's `windowSpaces` (other pids only) or with nil (`recheckTerminatedSoon`). In the shipped app the terminated row would never have fired, even though the fake passed.
- **Fix:** `WindowTracker.terminatedWindowIDs` plus `AXWindowSystem.terminatedSpaces(_:)`, which queries only terminated windows still at layer 0 in CG, so the capability's failure counter sees nothing new. Both terminated recheck paths use it.
- **Files modified:** Sources/TransomEngine/WindowTracker.swift, Sources/TransomMac/AXWindowSystem.swift
- **Commit:** 36ab32f

**2. [Placement] The ghost-reflow scenario lives in ArrangerSpacesTests, not CloseScenarioTests**
- Reflow needs the `Harness` and desk helpers, which already live in ArrangerSpacesTests. CloseScenarioTests has the terminated-ghost, hidden-tab and lookup-off scenarios.

**3. [Not duplicated] The D-14 test**
- The existing `ArrangerSpacesTests.aCloseOnAHiddenSpaceIsAppliedAndPlannedOnlyOnReturn` already pins exactly the D-14 behaviour: a close on a hidden Space's desk produces no setFrame, the next plan on return sets frames for the remaining window, and a later refresh sets none. Space 1 is the hidden one there instead of Space 2, which is the mirror case. A copy would add nothing, so only the OVER-04 lookup-off test (`withTheLookupOffEveryWindowIsOnTheDisplaysOneDesk`) was added. D-14 needed no Arranger change.

**4. [Rule 2] The Space shown at launch is fed as a visit**
- Without it, "Spaces: 0 visited since launch" shows until the first switch.

## Known Stubs

None. The Task 2 RED stubs were replaced in 08f0798.

## Deferred / Notes

- `Capability.spaces.fallback` still reads "single Space" in the capability-off log line (Sources/TransomPrivate/Capabilities.swift:16, pinned by CapabilitiesTests). It sits outside this plan's files and the UI-SPEC Debug-line change, so it was left alone. It could say "using Spaces visited since launch" if a later plan wants the two to match.
- The G-03-9 lingering CG entry never reproduced in the VM (06-SPIKE A7). The fix is pinned by the fake scenario, not by a live reproduction.
- `swift format lint` with no config wants 2-space indentation everywhere. The repo has no `.swift-format` file and uses 4 spaces, so new files follow the repo.

## Self-Check: PASSED

- FOUND: Sources/TransomEngine/CoVisibilitySpaces.swift, Sources/TransomMac/Shell/OverviewCopy.swift, Tests/TransomEngineTests/CoVisibilitySpacesTests.swift, Tests/TransomMacTests/OverviewCopyTests.swift
- FOUND commits: 4c2e98b, 36ab32f, 754a0a3, 08f0798 (ancestors of HEAD)
