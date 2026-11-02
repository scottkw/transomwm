---
phase: 07-tab-groups
plan: 05
subsystem: tiling
tags: [swift, tab-groups, accessibility, close-group, minimize-group, ax]

requires:
  - phase: 07-tab-groups
    plan: 04
    provides: TabGroupRef / tabGroup(holding:), floating groups, isHiddenTab
  - phase: 07-tab-groups
    plan: 02
    provides: reveal-then-park select, focus suppression, refusal path
provides:
  - WindowCommand.close / .minimize, routed through ExclusionFilter in AXWindowSystem and FakeWindowSystem
  - AXAppThread.closeWindow (kAXCloseButtonAttribute + kAXPressAction) and minimizeWindow (kAXMinimizedAttribute)
  - CloseQueue + Arranger.closeConfirmation (1 s); TabAction.closeGroup / .minimizeGroup; tabGroup(_ key:)
  - TabAnnouncement.didNotClose / .ended; dissolve detection on member close
  - Close Group (xmark) and Minimize Group (minus) strip buttons
affects: [07-06, 07-07, 07-11]

actuals:
  tokens: 13800
  tasks: 3
  commits: 4
plan_head_before: 05c234da6de7bcffd5a75911e585d3237813fe87
plan_head_after: 9758712f318633c9fe57535cdc3290383eac64b3

tech-stack:
  added: []
  patterns:
    - "Engine sequences multi-step OS actions with a queue in TabGroupState stepped by closeProgress(now:) after every event, read-back and tick; deadline joins nextWake"

key-files:
  created: []
  modified:
    - Sources/TransomEngine/WindowSystem.swift
    - Sources/TransomEngine/ExclusionFilter.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomTestSupport/FakeWindowSystem.swift
    - Sources/TransomMac/AX/AXAppThread.swift
    - Sources/TransomMac/AXWindowSystem.swift
    - Sources/TransomMac/Overlay/TabStripPanels.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomEngineTests/ArrangerDragTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift
    - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift

key-decisions:
  - "closeConfirmation stays 1 s: the VM measured the AX close press to two-source confirmation at 110 ms and 120 ms (A4)"
  - "focusSuppression stays 1 s: in the VM macOS made the hidden same-app window key after Minimize Group and the group stayed minimised (A1, Pitfall 6)"
  - "A stopped Close Group clears its queue; a second click rebuilds it from the group as it is now (selected first, then strip order). The member that stopped it is still the selected one, so it resumes with that member, and nothing stale is kept"
  - "Close Group shows hidden members with a new TabSelectSource.close, which is not announced; a reveal that fails (no read-back in 1 s, or the member not present) stops the queue instead of retrying"
  - "\"Tab group ended\" is not spoken while Close Group runs through the group (the windows vanishing is the feedback, UI-SPEC); the dissolve is still logged"

patterns-established:
  - "Group lookups by key use tabGroup(_ key:) (docked leaf or floating group id); by member use tabGroup(holding:)"

requirements-completed: [TABS-03, TABS-02]

coverage:
  - id: D1
    description: "Close Group: selected first then strip order, each hidden member revealed and read back before its close press; stop with didNotClose after closeConfirmation, second click resumes with that member; second click while closing sends nothing; paused / not ready refused"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerCloseGroupTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "An excluded member's .close is dropped by ExclusionFilter and the window stays open (T-07-14)"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerCloseGroupTests/anExcludedMembersCloseNeverReachesTheSystem"
        status: pass
    human_judgment: false
  - id: D3
    description: "AX close press and minimise act on real fixture windows; close confirmed under closeConfirmation"
    requirement: TABS-03
    verification:
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift#closeAndMinimizeCommandsActOnFixtureWindows (VM)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Minimize Group minimises only the selected member, no strip while absent, hidden member not moved, same-app focus within the suppression keeps it minimised, restore brings back the same tab"
    requirement: TABS-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerMinimizeGroupTests"
        status: pass
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift#minimizeGroupWithTwoWindowsOfOneAppStaysMinimized (VM)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Member closes by any route: right else left neighbour into the content rect, hidden member only drops its tab, docked and floating groups of one dissolve with Tab group ended; copy strings"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabMemberCloseTests; Tests/TransomMacTests/TabCopyTests.swift"
        status: pass
    human_judgment: false
  - id: D6
    description: "Strip buttons: glyphs, hover / pressed circle, tooltips, VoiceOver labels, mouse-up-inside; a real save prompt stopping Close Group"
    requirement: TABS-03
    verification:
      - kind: manual
        ref: "VM UAT at phase close (07-11), UI-SPEC host checklist item 5 (TextEdit unsaved)"
        status: pending
    human_judgment: true
    rationale: "Drawing and a real app's save sheet need eyes; no unit test covers the AppKit view"

duration: 9min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 05: Close Group and Minimize Group Summary

**The strip's Close Group button presses each member's own close button, one at a time: the selected member first, then the rest in strip order. Each hidden member is brought into view before its close, and the run stops with "“{App}” didn't close" at the first window still open after 1 s. Minimize Group minimises only the selected window. In the VM, macOS then made the other window of the same app key and the group stayed minimised. When members close on their own, the group selects a neighbour, drops a hidden member's tab, or dissolves with "Tab group ended".**

## Performance

- **Duration:** about 9 min
- **Started:** 2026-11-02T01:45:52Z
- **Completed:** 2026-11-02T01:55Z
- **Tasks:** 3
- **Files modified:** 14 (528 insertions, 33 deletions)

## Measured values (A1, A4)

| Value | Measured in the VM | Final constant |
|---|---|---|
| AX close press to two-source close confirmation | 110 ms, 120 ms (two runs) | `Arranger.closeConfirmation` = 1 s (unchanged) |
| Same-app focus shift after Minimize Group | fixture `frontmost index=1` before, `index=0` (the hidden window) after; group stayed minimised over 2 s | `Arranger.focusSuppression` = 1 s (unchanged) |

## Accomplishments
- Two new commands: `WindowCommand.close` and `.minimize`. On each app's AX thread they run as jobs that press `kAXCloseButtonAttribute` or set `kAXMinimizedAttribute`, and failures are logged by identity only. `ExclusionFilter` drops both for excluded apps before any AX call, and the fake closes or minimises a window and refreshes its app.
- `CloseQueue` is stepped by `closeProgress(now:)` after every event, reveal read-back and tick. Its deadline joins `nextWake`. A reveal that fails stops the queue, so it never retries in a loop.
- `minimizeGroup` sends `.minimize(selected)` and sets the group's focus suppression. The existing participation rule hides the strip and keeps the slot while the window is absent.
- The Arranger now compares the closing window's group before and after `LifecycleSync`. A group left with one window gets "Tab group ended" and the log line `group N: dissolved, W keeps the tile|frame`.
- Strip buttons: `xmark` / `minus` glyphs in `secondaryLabelColor` (`labelColor` on hover or press) with the 8% / 16% circle fill. They act on mouse-up inside the button, and dragging off cancels the press. Tooltips and VoiceOver `.button` elements are added, and Close Group's help reads "Closes all {n} windows in this tab group".
- `TabCopy`: `didNotClose` truncates the app name with `MenuCopy.truncatedAppName`. Also added: `ended`, `closeGroup`, `minimizeGroup`, `closeGroupHelp(_:)`.

## Task Commits

1. **Task 1: Tracer, Close Group end to end (engine, AX, shell, VM)** - `22aed32` (feat)
2. **Task 2: Minimize Group, restore, same-app focus (VM)** - `f94187c` (test)
3. **Task 3: Members closing on their own** - `a7e9044` (test, RED), `9758712` (feat, GREEN)

## Verification
- Host: `swift test` full suite green, with 881 + 379 + 213 + 92 tests in four test runs and no failures. `scripts/check-no-appkit.sh` OK.
- VM: `scripts/vm-live-test.sh TabGroupIntegrationTests` printed "Test run with 4 tests in 1 suite passed". The re-run of the minimise test with frontmost logging printed "1 test passed". Nothing live ran on the host.
- Tracer gate: Task 1's `<verify>` (host filter + VM, 3 tests passed) passed before the later tasks started.

## Deviations from Plan

1. **[Rule 3 - Blocking] Exhaustive switches on `WindowCommand`.** `ZoomController.written` and a test helper in `ArrangerDragTests` gained the two new cases. Files: `Sources/TransomMac/Zoom/ZoomController.swift`, `Tests/TransomEngineTests/ArrangerDragTests.swift`. Commit `22aed32`.
2. **TabCopy strings landed in Task 1, their tests in Task 3.** `TabCopy.announcement` is an exhaustive switch, and Task 1's buttons need the labels, so it would not compile otherwise.
3. **`minimizeGroup` engine action landed in Task 1, with the button.** Task 2 had no RED stage of its own: its engine tests were written against an action that already existed and passed at once, apart from one wrong expectation (next item). Task 2's commit is test-only.
4. **Engine fact found while writing Task 2's tests.** While the selected member is absent, the planner drops the hidden member's `parkRequested` entry, so `isParked(b)` is false. No command moves the window, so it stays parked on screen, and on restore it is parked again. The test checks that no command moves b instead of checking `isParked`. This behaviour came from 07-01/07-04's participation rule and was left as it is.
5. **VM close check uses the inventory only.** The fixture's `list` keeps a window closed through its close button, because its entry stays `open`. So the closed window is detected by `system.windowInfo(ref) == nil` (two-source close), not by the fixture list.
6. **Stopped queue is cleared rather than kept** (see key decisions). The behaviour matches the plan and the acceptance test.

## Known Stubs
- `TabStripView.label` / `press` return nothing for `.floatGroup` / `.dockGroup`. Those buttons are not shown until 07-06 adds them (`shortcut:` comment on `buttons`).

## Threat Flags
None. T-07-13 is mitigated: only the window's own close button is pressed, hidden members are shown first, and the run stops at the first window still open. T-07-14 is mitigated by `ExclusionFilter` and covered by an engine test. T-07-15 is mitigated by the suppression and the VM test.

## Self-Check: PASSED
