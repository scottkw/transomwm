---
phase: 07-tab-groups
plan: 02
subsystem: tiling
tags: [swift, tab-groups, tab-strip, reveal-then-park, d-08, appkit-panels]

requires:
  - phase: 07-tab-groups
    plan: 01
    provides: TabBand, Resolution.hiddenTabs, sized parks, TabAnnouncement, TabCopy, TabGroupIntegrationTests
provides:
  - TabStrip / GroupKey / TabAction / TabSelectSource / PendingReveal / TabGroupState (Arranger+Tabs.swift)
  - ArrangerInput.tab(TabAction, ready:), ArrangerEffect.tabStrips / .raiseStrip
  - Reveal-then-park select with a 1 s read-back deadline and revert
  - D-08 activation of a hidden member with a 1 s per-group focus suppression (Arranger.focusSuppression)
  - TabStripPanels / TabStripView (pooled non-activating strip panels, click on mouse-up)
  - TabCopy: "Tab {i} of {n}", "Couldn't show “{App}”", the three refusals
affects: [07-03, 07-04, 07-05, 07-06, 07-07, 07-08]

actuals:
  tokens: 11877
  tasks: 3
  commits: 5
plan_head_before: 3113508ed1b008c149473afa5d885c0e66a61cd0
plan_head_after: 77f48f36f06d8c6874df3b0a367ddf127137c5d3

tech-stack:
  added: []
  patterns:
    - "A tab switch is engine state: select → setFrame + focus the new member, keep the old as cover, park it on the matching read-back"
    - "Strips are a pure per-display effect sent only on change (the showBlocks pattern); titles carried explicitly (Pitfall 7)"

key-files:
  created:
    - Sources/TransomMac/Overlay/TabStripPanels.swift
  modified:
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift
    - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift

key-decisions:
  - "A reveal waits only when something covers the content rect: if the previous member is parked (camera) or not present, the select applies at once with no deadline"
  - "A second select in the same group while a reveal is pending keeps the original cover as `previous`; a select in another group drops the older pending reveal"
  - "The read-back must be within 2 pt of the content rect last requested (`lastRequested`), size included"
  - "A strip press still feeds a pointer `.down` with no press window (so a stale drag is abandoned), skips `zoomInput.pointerDown` and never resolves a window behind"
  - "TabCopy truncates app names itself (truncatedAppName is idempotent); ArrangeController passes the raw name"
  - "Arranger.parkRequested, lastRequested and nextWake dropped `private` (internal) for Arranger+Tabs.swift"

patterns-established:
  - "Activation runs inside the `.windowFocused` arm before `widen(toShow:)`, so the widen sees the group's leaf"

requirements-completed: []

coverage:
  - id: D1
    description: "Select emits setFrame(new, content) then focus(new), no park of the previous; a read-back within 2 pt parks it at the content size; none by 1 s reverts with beep + couldNotShow; selected-tab click only focuses; paused / not ready beep and change nothing"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabSelectTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "A strip is sent once per change (not on an unchanged replan), again on a title change, with grouping, and hidden on undo"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabSelectTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Clicking the hidden tab on real windows: window 0 reaches the content rect, the content rect is never uncovered at any 50 ms sample, window 1 ends a sliver at the content size (VM)"
    requirement: TABS-02
    verification:
      - kind: integration
        ref: "scripts/vm-live-test.sh TabGroupIntegrationTests (.build/0702-t1-vm.log: Test run with 2 tests in 1 suite passed)"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-08: a focused hidden member is selected (no announcement); echo of the revealed window ignored; 1 s suppression after a selection change, a member going absent, or a member closing; the camera widen runs after the selection"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabActivationTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Selection and refusal copy per the UI-SPEC"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/TabCopyTests.swift"
        status: pass
    human_judgment: false
  - id: D6
    description: "Strip look (fill, border, capsule tabs, icon, middle-truncated title, hover), 120 ms fades, click feel in an inactive app"
    requirement: TABS-02
    verification:
      - kind: manual
        ref: "VM UAT at phase close"
        status: pending
    human_judgment: true
    rationale: "Drawing and fades are not asserted by any test; they need a look on screen"

duration: 10min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 02: Tab strips and tab switching Summary

**Every docked group whose selected member is on screen gets a non-activating strip panel over its 28 pt band; clicking a hidden tab writes and focuses it into the content rect and parks the old member only after the new one reads back within 2 pt (1 s deadline, then revert with "Couldn't show “{App}”"), proved on real windows in the VM; a hidden member focused by ⌘Tab or the Dock becomes the selected tab, guarded by a 1 s per-group suppression.**

## Performance

- **Duration:** about 10 min
- **Started:** 2026-11-02T01:00:55Z
- **Completed:** 2026-11-02T01:11Z
- **Tasks:** 3
- **Files modified:** 8 (836 insertions, 41 deletions)

## Accomplishments
- Engine: `TabStrip` per shown display from `planShown` (selected member in `plan.frames`, so none for camera-parked, collapsed, absent or fullscreen groups), sent only on change; live titles carried in `titles`.
- Engine: `select(_:via:ready:now:)` (no undo step) → `.perform([setFrame(new), focus(new)])` with the previous member left out of parks; `.frameApplied` within 2 pt ends the reveal and parks it; `tick` past the deadline reverts, beeps and announces. The deadline is in `nextWake`.
- Engine: D-08 activation in the `.windowFocused` arm before the widen; suppression set on every selection change and on a member going absent or closed; expired entries pruned on tick.
- Shell: `TabStripPanels` (pool, `.normal` level, `[.stationary, .ignoresCycle]`, tooltips while inactive, `sharingType = .none`, `leftOnAnotherSpace` check on every reused panel) and `TabStripView` (strip fill and border, equal capsule tabs, 16 pt icon from a per-pid cache, middle-truncated title, hover fill, click on mouse-up under 4 pt travel). ArrangeController handles `.tabStrips` / `.raiseStrip`, `tabAction(_:)`, and keeps strip presses out of window drags.
- `TabCopy` speaks the selection and refusals.

## Task Commits

1. **Task 1: Tracer, strip appears and a tab click swaps windows** - `f9f694f` (feat)
2. **Task 2: D-08 activation with the focus-fight guard** - `11b32c4` (test, RED), `d5c4369` (feat, GREEN)
3. **Task 3: Copy for selection and refusals** - `370c410` (test, RED), `77f48f3` (feat, GREEN)

## Files Created/Modified
- `Sources/TransomEngine/Arranger+Tabs.swift` - tab types, select / reveal / revert / activation / suppression, `tabStrips`, `showStrips`
- `Sources/TransomEngine/Arranger.swift` - `.tab` input, `.tabStrips` / `.raiseStrip` effects, `tabs` state, planShown hooks, frameApplied / tick / nextWake / forget / rekey hooks, activation in `.windowFocused`
- `Sources/TransomMac/Overlay/TabStripPanels.swift` - strip panels and view
- `Sources/TransomMac/ArrangeController.swift` - strip effects, `tabAction`, strip press routing
- `Sources/TransomMac/Shell/TabCopy.swift` - new announcements
- Tests: `ArrangerTabSelectTests` (8), `ArrangerTabActivationTests` (6), `TabCopyTests` (+7 cases), `TabGroupIntegrationTests` (shared `SavedGroup` setup + the selection test)

## Decisions Made
See `key-decisions` in the frontmatter. The main ones: a reveal waits only when something covers the content rect; the read-back is compared with the last requested content rect; TabCopy owns app-name truncation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] Strip presses still feed a pointer `.down`, without a press window**
- **Found during:** Task 1
- **Issue:** the plan said a strip press "returns without creating a pointer event". Skipping the `.down` entirely would leave a stale drag (lost mouse-up) un-abandoned.
- **Fix:** on a strip press, `pressWindow` is not resolved (nil) and `zoomInput.pointerDown` is skipped; the `.down` still reaches the Arranger, which abandons any stale drag and starts no session.
- **Files modified:** Sources/TransomMac/ArrangeController.swift
- **Commit:** f9f694f

**2. [Rule 3 - Blocking] TabCopy stand-in so Task 1 compiled**
- **Found during:** Task 1
- **Issue:** the new `TabAnnouncement` cases broke `TabCopy`'s exhaustive switch.
- **Fix:** an empty-string stand-in in Task 1, replaced by the real copy in Task 3.
- **Commit:** f9f694f, replaced in 77f48f3

**3. [Rule 1 - Bug] Pending reveal kept valid across close and rekey**
- **Found during:** Task 1
- **Fix:** `forget` drops a pending reveal that names the closed window; `.windowRekeyed` re-points it.
- **Files modified:** Sources/TransomEngine/Arranger.swift
- **Commit:** f9f694f

### Scope notes
- Task 3's strip fade (new group fades in over 120 ms after the perform, removed strip fades out, selection swaps at once) was built in Task 1's panel. Task 3 changed copy only.
- A ⌘⇧ press on a strip is still taken by the tap's zoom rule before any controller code sees it, so the rubber band can start there. It is a camera gesture that does not target a window, as on any other window. No Phase 3 window drag starts.
- `leftOnAnotherSpace` runs on every reused panel, pooled ones included (hard rule). If macOS reports ordered-out panels as off the active Space (Pitfall 8, assumed), pooled panels get replaced with a log notice instead of reused. That is harmless churn, to check in 07-03's Space VM test.
- No group buttons, overflow, accessibility element or drag following yet (07-03).
- Activation while paused is silently ignored. Only explicit tab actions beep.
- No info log when a focus is suppressed (the engine has no debug-level effect).

**Total deviations:** 3 auto-fixed (1 missing critical, 1 blocking, 1 bug)
**Impact on plan:** none on scope.

## Issues Encountered
None. Host: `swift test` 844 + 372 + 198 + 89 tests passed (`.build/0702-t3.log`), `scripts/check-no-appkit.sh` OK. VM: `scripts/vm-live-test.sh TabGroupIntegrationTests`, "Test run with 2 tests in 1 suite passed" (`.build/0702-t1-vm.log`). Nothing live ran on the host.

## User Setup Required
None.

## Next Phase Readiness
- 07-03 can build on `TabStrip`, `TabStripPanels` (buttons, overflow, accessibility, following, Space handling) and `.raiseStrip`.
- `TabAction` has only `.select`. Close, move out and group-wide actions come later.

## Self-Check: PASSED
