---
phase: 02-window-control
plan: 14
subsystem: window-tracking
tags: [skylight, spaces, private-api, dlsym, native-tabs, tab-groups, fake-window-system, capability-registry]

requires:
  - phase: 02-window-control
    provides: TabGroupTracker and WindowTracker (02-10), the capability registry and CapabilitySession (02-11), FakeWindowSystem (02-03)
provides:
  - SkyLightSpaces, a read-only per-window Space lookup reached through dlopen/dlsym, nil when unavailable
  - Capability.spaces ("Spaces"), forceable off, degradable, single-Space fallback
  - ObservationContext.windowSpaces, which carries Space data into PaneEngine without AppKit
  - Space-aware TabGroupTracker with the ambiguity rule, Cmd-T rule, rebind gate and orphan handoff
  - WindowTracker fold guard (a fold is destroyed only after two unchanged refreshes)
  - FakeWindowSystem Space modelling (showSpace, Spaces on/off, hidden-tab Space reporting, newTab)
  - Debug menu line "Spaces lookup: available" / "Spaces lookup: off, single Space"
affects: [phase-03-tiling, phase-06-spaces, phase-07-tabs]

actuals:
  tokens: 16000    # chars/4 over the realized diff (64150 chars, TDD evidence excluded); the changed files total ~56000
  tasks: 3
  commits: 6
plan_head_before: 7e492da2c66184dc00f42e3b4523e6d7bda0a6d9
plan_head_after: 66ddc1d244eef6e77dc16f1359de98b2a0db867c

tech-stack:
  added: []
  patterns:
    - "Second PanePrivate shim after AXWindowID: one static-let dlopen/dlsym closure into optional @convention(c) pointers, isLoaded feeds CapabilitySession"
    - "Per-capability fallback phrase (Capability.fallback) in the switch-off log"
    - "Scenario tests take (spacesAvailable, hiddenTabsReportSpace) arguments and check two safety invariants after every refresh"

key-files:
  created:
    - Sources/PanePrivate/SkyLightSpaces.swift
    - Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift
  modified:
    - Sources/PanePrivate/Capabilities.swift
    - Sources/PaneEngine/WindowSnapshot.swift
    - Sources/PaneEngine/TabGroupTracker.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Tests/PaneEngineTests/TabScenarioTests.swift
    - Tests/PaneEngineTests/TabGroupTrackerTests.swift
    - Tests/PaneMacTests/CapabilitiesTests.swift
    - Tests/PaneMacTests/MenuCopyTests.swift
    - .planning/phases/02-window-control/02-UI-SPEC.md
    - .planning/ROADMAP.md

key-decisions:
  - "02-14: Live macOS 27 reports an empty Space set for a hidden native tab, so the unknown-Space ambiguity rule is what keeps a same-slot group on another Space out"
  - "02-14: A folded window listed as its group's shown tab still counts toward the fold guard (a shown-tab change resets it to 1), so a merged tab never stays tracked twice"
  - "02-14: The room-rule join also skips a group whose bound Space differs from the new tab's (same check as the rebind gate)"
  - "02-14: A window folded in earlier stays a hidden-tab candidate of its group until the fold guard decides it, even though it was not listed last refresh"

patterns-established:
  - "Space data is optional end to end: nil in ObservationContext means single-Space behaviour, and every rule that reads it degrades to the pre-02-14 ranking plus the Cmd-T rule"

requirements-completed: [WIN-06, WIN-09, SAFE-05]

coverage:
  - id: D1
    description: "Read-only SkyLight Spaces lookup via dlopen/dlsym, never linked; shown tab and standard window share one Space live, hidden tab reports none"
    requirement: SAFE-05
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift#aShownTabAndAStandardWindowShareOneSpaceAndTheHiddenTabNeverReportsAnother()"
        status: pass
      - kind: other
        ref: "grep -rn SkyLight Package.swift xcode/project.yml (prints nothing)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Capability.spaces: in the capability report, --disable-private=Spaces parsed, own fallback phrase"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/CapabilitiesTests.swift#disablePrivateTakesOnlyKnownNames, everyCapabilityIsReported, eachCapabilityNamesItsOwnFallback"
        status: pass
    human_judgment: false
  - id: D3
    description: "Cross-Space twins never taken as hidden tabs with Space data; Cmd-T right in both modes (C2, C7, ambiguity rule)"
    requirement: WIN-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TabGroupTrackerTests.swift#cmdTTakesTheWindowThatBecameItsTabNotATwinOnAnotherSpace, aBrandNewTabLeadsANewGroupWithTheStandaloneItCameFrom, noUnknownSpaceCandidateIsTakenWhileAKnownOtherSpaceWindowSharesTheSlot"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/TabScenarioTests.swift#SpaceTabScenarioTests (C2, C5, C7 and variants, all three modes)"
        status: pass
    human_judgment: false
  - id: D4
    description: "No live window reported destroyed through a fold or a closed shown tab (fold guard, orphan handoff, rebind gate)"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/TabScenarioTests.swift#FoldGuardTests, mergingTwoTrackedWindowsLeavesOneGroupAndReportsTheOtherGone, aNewWindowInTheSlotOfAClosedGroupNeverInheritsIt"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/TabGroupTrackerTests.swift#aFormerTabOfAGroupWithNoMemberLeftTakesItsIdentity, aWindowWithoutFormerTabEvidenceNeverTakesTheIdentity, rebind gate cases"
        status: pass
    human_judgment: false
  - id: D5
    description: "Debug menu shows the Spaces lookup state"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MenuCopyTests.swift#spacesItemNamesTheSpacesLookupState()"
        status: pass
      - kind: other
        ref: "scripts/build-debug.sh (exit 0)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Real Spaces and real native tabs (Finder, Terminal, Safari): Space switches and Cmd-T never add, remove or duplicate Tracked Windows rows; the Debug line flips with --disable-private=Spaces"
    requirement: WIN-06
    verification: []
    human_judgment: true
    rationale: "Real Spaces cannot be created or switched from automation, and real apps' tab implementations differ (end-of-phase human UAT, the human-check in Task 3)"

duration: 23min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 14: Spaces-aware Native Tab Groups Summary

**A read-only SkyLight Spaces lookup (dlopen/dlsym, capability `Spaces`) keeps a same-frame window on another Space out of a tab group. A Cmd-T rule, a two-refresh fold guard, a rebind gate and an evidence-based orphan handoff mean a wrong fold or a closed shown tab never reports a live window destroyed, with or without Space data.**

## Performance

- **Duration:** 23 min
- **Started:** 2026-10-25T19:12:17Z
- **Completed:** 2026-10-25T19:35:04Z
- **Tasks:** 3
- **Files modified:** 16 (plus 4 TDD evidence records)

## Accomplishments

- `SkyLightSpaces` in its own PanePrivate file. It reaches `SLSMainConnectionID` and `SLSCopySpacesForWindows` (selector 0x7) only through `dlopen` and `dlsym`, makes one call per window, reads only CFNumbers, drops 0 and caps each window at 16 Spaces. An all-NULL batch counts one failure, and any answer counts one success. Nothing links SkyLight.
- `Capability.spaces` ("Spaces") appears in the launch log and the Debug menu, and `--disable-private=Spaces` forces it off. Five failed batches switch it off for the session. Each capability now logs its own fallback ("matching by frame", "single Space").
- With Space data, TabGroupTracker never takes a candidate known to be on another Space. It also never takes a candidate of unknown Space while a window known to be on another Space shares the frame slot. Own members and the Cmd-T window are exempt.
- The Cmd-T rule works in both modes: a shown tab that was not in the previous layer-0 CG list takes the tracked standalone window listed last refresh, and leads a new group with it.
- Rebind gate: a listed member that is not the group's shown tab rebinds the group only if the shown tab is gone or the AXTabs counts agree, and never across known different Spaces.
- Orphan handoff: when a group's shown tab and every known member are gone (out of the CG list, or AX-invalid), the group's identity passes only to a former tab. A former tab is listed, not yet reported, was offscreen in the group's slot at the last refresh, and is not known to be on another Space.
- Fold guard in WindowTracker: a folded window is reported destroyed only on the second consecutive refresh with the same shown tab.
- FakeWindowSystem models Spaces: `showSpace`, `setSpacesAvailable`, `setHiddenTabsReportSpace`, `tabGroup(…, space:)`, `newTab(_:in:)`, and groups by `tabGroupID`. The reviewer's C1-C7 and S4-S6 are committed tests that run in three modes and check two safety invariants after every refresh.

## Live result: hidden tab Space

**The live test saw the empty-set branch.** On macOS 27.0.1, `SLSCopySpacesForWindows` returns no Space for the fixture's hidden native tab. The shown tab and the standard window report the same single Space. SpacesIntegrationTests printed `the hidden tab reported no Space (empty set)` in all three live runs. So on this OS the ambiguity rule, not the exclusion rule, is what keeps hidden tabs apart.

## Task Commits

1. **Task 1: Tracer, Space data reaches TabGroupTracker** - `89c2f3b` (test, RED), `a6789b8` (feat, GREEN)
2. **Task 2: fallback rule, fold guard and the Space scenario matrix** - `e80d2a2` (test, RED), `46947f7` (feat, GREEN)
3. **Task 3: Debug menu line, UI-SPEC and ROADMAP note** - `ae80cc9` (test, RED), `66ddc1d` (feat, GREEN)

## TDD Gate Compliance

Each task has a `test(02-14)` commit before its `feat(02-14)` commit. All four RED records returned `RED_EVIDENCE_OK`, and each failed on its planned assertions against compiling stubs.
- `tdd/02-14-task1-red.json` and `tdd/02-14-task1-live-red.json`. The two new `parseDisabled` rows passed at RED because the stub already declared `Capability.spaces`. `aShownTabSeenBeforeKeepsTheUsualRanking` (the guard that S4 is unchanged) passed by design.
- `tdd/02-14-task2-red.json`. The C2/C5/C7 basics and switch variants passed on the Task 1 code, which had already fixed them. So, per the acceptance criterion, C2, C5 and C7 were also run against the pre-plan TabGroupTracker (7e492da, with the new parameters stubbed) in a scratch copy, and every C2, C5 and C7 test failed there.
- `tdd/02-14-task3-red.json`.

## Verification

- `swift test --skip PaneMacIntegrationTests`: 408 tests pass (383 before the plan). The output contains `spacesAvailable → false` 19 times.
- `caffeinate -d -i swift test --filter PaneMacIntegrationTests`: 23 tests pass, and SpacesIntegrationTests and TabsIntegrationTests both ran. The one skip is the existing two-display test. Afterwards `pgrep -fl PaneFixtureApp` printed nothing.
- `scripts/check-no-appkit.sh` OK. `scripts/build-debug.sh` exits 0 (signed, satisfies its designated requirement).
- `grep -rn SkyLight Package.swift xcode/project.yml` prints nothing, and there is no `@_silgen_name` anywhere.
- Live runs: 3 in total (RED, Task 1 GREEN, the full integration suite), each wrapped in `caffeinate -d -i` after a lock check. Fixture windows only.

## Known limits

- **Single-Space fallback (accepted).** Without Space data (the capability is off, forced off or missing), two same-frame tab groups of one app on two Spaces (C5) may be tracked as one window. The project lead accepted this on 2026-10-25 (single-Space fallback), and it is recorded as an override in 02-VERIFICATION.md. Even in that mode, no live window is reported destroyed and no window ID is tracked under two identities. The C5 tests assert both in that mode.
- **Incomplete membership with Space data.** A hidden tab of unknown Space is never taken while a window known to be on another Space shares its frame slot. Such a group's membership can stay incomplete until a tab switch shows and confirms the tab. `visibleMemberID` and `tabCount` (from AXTabs) are unaffected.
- **Plan-check advisory: race without Space data.** If the user switches Spaces in the same update as a whole-group close, an untracked same-frame twin from the other Space can pass the former-tab evidence rule and inherit the group's identity. This needs a race. With Space data the twin's known Space rules it out.

## Decisions Made

- A folded identity that is listed as its group's shown tab still counts toward the fold guard, and a change of shown tab resets the count to 1. The plan says folded windows "not listed this refresh". Read literally, a merged tab that is selected would stay tracked twice, so "listed" is read as listed on its own. A window listed on its own leaves the group, so it is no longer folded.
- A window folded in earlier stays a hidden-tab candidate of its group, even when it was not listed last refresh. Without this, the fold guard's second refresh could never see the fold (the merge test caught it).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] The room-rule join also checks Spaces**
- **Found during:** Task 2
- **Issue:** The plan applies the Space check only to the membership rebind. A new tab with N tabs could still join a same-slot group on another Space through the room rule when that group had a free slot and an unknown-Space hidden member.
- **Fix:** The room rule skips a group whose bound Space set is known to differ from the new tab's.
- **Files modified:** Sources/PaneEngine/TabGroupTracker.swift
- **Committed in:** 46947f7

**2. [Rule 1 - Bug] AX-invalid windows are never hidden-tab candidates, and an invalid shown tab counts as gone in the rebind gate**
- **Found during:** Task 2
- **Issue:** In C5 (b), the closed tab 30 is still in the CG list. It would have counted as "still offscreen" and blocked 31's rebind (AXTabs 1 against 2), or been taken back as a hidden tab.
- **Fix:** `gone()` (out of the CG list, or in `invalid`) is used in both the gate and the orphan test, and candidates leave out `invalid`.
- **Committed in:** 46947f7

**3. [Scope note] Where the fold guard tests live**
- The WindowTracker-level fold guard tests are in `Tests/PaneEngineTests/TabScenarioTests.swift` (suite `FoldGuardTests`) rather than WindowTrackerTests.swift, to stay inside the plan's file list. The `WindowTrackerTests` verify filter still covers WindowTrackerTests.

**4. [Minor] Membership at handoff**
- When the orphan handoff binds a former tab, the group's member set is rebuilt by the normal rule (shown tab plus hidden tabs). The AX-invalid closed tab therefore leaves the member set at once, not when it leaves the CG list. This has no observable effect: CloseRule decides the group through the new shown tab, and C5 (b) shows no state change and no create or destroy.

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug) and 2 scope notes. **Impact:** all are inside TabGroupTracker and the tests; no scope creep.

## Issues Encountered

None.

## Human UAT (end of phase)

Real Spaces and native tabs (the Task 3 human-check):
1. Finder, Terminal and Safari with three tabs each (Cmd-T); click between tabs.
2. Put a same-frame Terminal window on a second Space and switch back and forth. Press Cmd-T in the Space 1 window while the twin sits on Space 2, then switch again.
3. Relaunch with `scripts/run-debug.sh --no-build --disable-private=Spaces` and open the Debug menu. Check `log show --predicate 'subsystem == "com.eightabyte.pane" AND category == "private"' --last 5m`.

Expected: one Tracked Windows row per real window. Tab clicks change only the title. Space switches and Cmd-T never add, remove or duplicate rows. Debug shows "Spaces lookup: available", and "Spaces lookup: off, single Space" with the flag. The log has "Spaces: available" or "Spaces: off". Note which apps report AXTabGroup.

## User Setup Required

None.

## Next Phase Readiness

- Gaps 1 and 2 (WIN-06, WIN-09) are closed in code and in tests. 02-15 and 02-16 remain for gaps 3-5.
- Phase 6 builds its `SpacesProvider` on `SkyLightSpaces` (ROADMAP note added).

## Self-Check: PASSED

- FOUND: Sources/PanePrivate/SkyLightSpaces.swift, Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift
- FOUND commits: 89c2f3b, a6789b8, e80d2a2, 46947f7, ae80cc9, 66ddc1d (`evaluation-scope` resolved them on this branch)
- All task acceptance criteria and plan-level verification commands re-run and passing, as listed above

---
*Phase: 02-window-control*
*Completed: 2026-10-25*
