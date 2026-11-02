---
phase: 07-tab-groups
plan: 03
subsystem: tiling
tags: [swift, tab-groups, tab-strip, spaces, accessibility, appkit-panels]

requires:
  - phase: 07-tab-groups
    plan: 02
    provides: TabStrip, GroupKey, .tabStrips / .raiseStrip, TabStripPanels / TabStripView, TabCopy
provides:
  - TabStripLayout / TabStripButton (Sources/TransomMac/Overlay/TabStripLayout.swift, AppKit-free)
  - TabStripPanels.follow(_:contentBounds:), group(selecting:), the 500 ms backstop, spaceChanged(displayUUID:to:)
  - TabStripView overflow menu, hover/pressed fades, tooltips, VoiceOver tab group
  - Arranger.raisedStrip(of:) (focus of a selected member raises its strip)
  - TabCopy.stripLabel / tabLabel / tabHelp / moreTabs / moreTabsHelp / titleOrApp
  - SavedGroup (integration test helper) is now internal; ArrangeController.tabStripPanels is internal
affects: [07-04, 07-05, 07-06, 07-11]

actuals:
  tokens: 11554
  tasks: 3
  commits: 4
plan_head_before: 88e93e7fc7582f6b687ddf1402a7eb27687585f4
plan_head_after: f16ff19790f7de1350ece727ac06a6050a107d54

tech-stack:
  added: []
  patterns:
    - "Strip geometry is a pure struct in points (TabStripLayout); the view is flipped so its top-left rects apply as is"
    - "A drift is followed only when two backstop ticks agree; a match snaps back at once"
    - "Strips remember the Space they were shown for; a Space change orders them out or fades them back in"

key-files:
  created:
    - Sources/TransomMac/Overlay/TabStripLayout.swift
    - Tests/TransomMacTests/TabStripLayoutTests.swift
    - Tests/TransomMacIntegrationTests/TabStripSpaceIntegrationTests.swift
  modified:
    - Sources/TransomMac/Overlay/TabStripPanels.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/TabCopyTests.swift
    - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift

key-decisions:
  - "Focusing a group's selected member emits .raiseStrip only when no D-08 activation ran (the activation's select already raises)"
  - "The 500 ms backstop follows a drift only when two consecutive ticks see the same drifted strip rect, so a revealed member still at its park for a moment never pulls the strip there; a return to the plan snaps back at once"
  - "Drift is compared on x, y and width only: the strip's frame carries no group height"
  - "leftOnAnotherSpace is asked only of visible panels: ordered-out panels report off the active Space too, and ordering one in brings it to the shown Space (VM: the same panel came back, no replacement)"
  - "TabStripPanels remembers per display the Space its strips were shown for (the engine's currentSpaceID at the .tabStrips effect); a Space change back to it fades the strips in, covering a return while arranging is paused, when the engine sends nothing"
  - "A Space change with no Space ID (Spaces unavailable) does nothing: macOS keeps each strip on its Space, and the engine keeps the same desk"
  - "Tab accessibility press selects with source .click (no separate source for VoiceOver)"

patterns-established:
  - "Accessibility children are nonisolated NSAccessibilityElement subclasses whose press hops with MainActor.assumeIsolated"

requirements-completed: []

coverage:
  - id: D1
    description: "Focusing the selected member raises its strip once; an unchanged replan never raises; a window outside the group raises nothing; an activation raises once"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabActivationTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Strip geometry: button slots, equal titled tabs, icon-only under 96 pt, overflow under 32 pt with the selected tab kept, buttons hidden under 116 pt"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/TabStripLayoutTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "Strip and tab accessibility copy, More Tabs and its help, title or app name"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/TabCopyTests.swift#theStripReadsAsATabGroup"
        status: pass
    human_judgment: false
  - id: D4
    description: "The strip shows only on its group's Space: ordered out on the second desktop, back and on the active Space on the first, same panel reused"
    requirement: TABS-02
    verification:
      - kind: integration
        ref: "scripts/vm-live-test.sh TabStripSpaceIntegrationTests (.build/0703-t3-vm.log: Test run with 1 test in 1 suite passed)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Strip follows the selected window during a drag and an app self-move, returns to the planned frame at rest"
    requirement: TABS-01
    verification:
      - kind: manual
        ref: "VM UAT at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "No test drags a group member live; the poll wiring builds but its feel needs a look on screen"
  - id: D6
    description: "Overflow menu, hover / pressed fades, Increase Contrast, tooltips, VoiceOver reading the strip as a tab group"
    requirement: TABS-02
    verification:
      - kind: manual
        ref: "VM UAT at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "Drawing, menus and VoiceOver output are not asserted by any test"

duration: 10min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 03: Tab strip follows, overflows and stays on its Space Summary

**The strip now follows its selected window (drag poll at display rate, 500 ms CG-bounds backstop), comes front when a member is focused, draws the exact Surface 2 geometry from a pure `TabStripLayout` (titled, icon-only, a `chevron.down` overflow menu, the selected tab kept visible), reads to VoiceOver as a tab group of radio-button tabs, and lives only on its group's Space, which a VM test proves while reusing the same panel.**

## Performance

- **Duration:** about 10 min
- **Started:** 2026-11-02T01:13:40Z
- **Completed:** 2026-11-02T01:24Z
- **Tasks:** 3
- **Files modified:** 11 (553 insertions, 64 deletions)

## Accomplishments
- Engine: `.windowFocused` of a group's selected member appends `.raiseStrip(group)` (`raisedStrip(of:)`); replans never do.
- Shell: `TabStripPanels.follow` places the strip over polled content bounds inside `CATransaction.setDisableActions(true)`; ArrangeController's drag poll calls it when the dragged window is a shown group's selected member. A 500 ms main-actor timer runs only while strips are shown and reads CG bounds only.
- `TabStripLayout` (no AppKit): 20 × 20 button slots, the tab region from 8 pt after the last button to 4 pt before the edge, equal widths, `.titled` / `.iconOnly`, overflow button plus hidden list. Group buttons are passed as `[]` until 07-05 / 07-06.
- `TabStripView` rewritten on the layout: flipped, titled or centred-icon tabs, overflow glyph, one hover layer (labelColor 8%, pressed 16%, × 1.5 with Increase Contrast, 80 ms in / 120 ms out, colour re-resolved in the current appearance), tooltips through `NSViewToolTipOwner`, overflow `NSMenu` below the button with 16 pt icons, choosing one selects with `.overflow`.
- Accessibility: the view is `.tabGroup` "Tab group, {n} windows"; each tab (overflowed ones too) a `.radioButton` with `.tabButtonSubrole`, label, value, help and press; the overflow button a `.button` "More Tabs" with "{k} more tabs".
- Spaces: `spaceChanged(displayUUID:to:)` runs before the replan; `leftOnAnotherSpace` is asked only of visible strips, with the info log "strip for group {node} replaced: left on another Space" (category `tabs`).

## Task Commits

1. **Task 1: Tracer, the strip follows the selected window and comes front on focus** - `681e870` (feat)
2. **Task 2: Strip geometry, overflow, styling, tooltips and accessibility** - `9e33739` (test, RED), `acdb552` (feat, GREEN)
3. **Task 3: Strips belong to their Space, VM test** - `f16ff19` (feat)

## Files Created/Modified
- `Sources/TransomMac/Overlay/TabStripLayout.swift` - pure strip geometry
- `Sources/TransomMac/Overlay/TabStripPanels.swift` - follow, backstop, Space handling, the redrawn view, accessibility, overflow menu
- `Sources/TransomMac/ArrangeController.swift` - bounds closure, follow from the drag poll, `spaceChanged` before the replan, the Space passed to `show`
- `Sources/TransomMac/Shell/TabCopy.swift` - strip, tab and overflow copy
- `Sources/TransomEngine/Arranger.swift`, `Arranger+Tabs.swift` - raise on focus of the selected member
- Tests: `ArrangerTabActivationTests` (+2), `TabStripLayoutTests` (5), `TabCopyTests` (+1), `TabStripSpaceIntegrationTests` (1, VM), `SavedGroup` made internal

## Decisions Made
See `key-decisions` in the frontmatter. The main ones: the backstop needs two agreeing ticks before it follows a drift; only visible strips are checked for stranding; strips remember their Space so a paused return still shows them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Layout behaviour bullet 2 used numbers that overflow**
- **Found during:** Task 2
- **Issue:** "Width 200, 4 tabs, 3 buttons → icon-only" contradicts the UI-SPEC formula: the tab region is 116 pt, so each tab is 26 pt, which is overflow.
- **Fix:** the test uses width 300 (51 pt tabs, icon-only); the overflow case is covered by bullet 3.
- **Files modified:** Tests/TransomMacTests/TabStripLayoutTests.swift
- **Commit:** 9e33739

**2. [Rule 1 - Bug] A Space change with no new strips would have lost them**
- **Found during:** Task 3
- **Issue:** the engine sends no strips while paused (`planShown` returns nothing), so ordering strips out on a Space change would leave them out on return, and after resume too (the engine's `shownStrips` would be unchanged).
- **Fix:** `TabStripPanels` remembers the Space each display's strips were shown for and fades them back in when that Space returns; a change with no Space ID does nothing.
- **Files modified:** Sources/TransomMac/Overlay/TabStripPanels.swift, Sources/TransomMac/ArrangeController.swift
- **Commit:** f16ff19

**3. [Rule 1 - Bug] The 07-02 open point: pooled strips replaced on every Space change**
- **Found during:** Task 3
- **Issue:** `onShownSpace` checked every reused panel, including ordered-out pooled ones, which report off the active Space.
- **Fix:** only visible panels are checked. The VM test printed `same panel reused=true` after switching away and back.
- **Commit:** f16ff19

**4. [Rule 3 - Blocking] Existing echo test asserted no `.raiseStrip`**
- **Found during:** Task 1
- **Issue:** `aFocusOfTheRevealedWindowIsAnEchoAndSelectsNothing` used "no `.raiseStrip`" as a stand-in for "did not select again"; focusing the now-selected member raises its strip by the new rule.
- **Fix:** the test now checks for no commands, no announcement and an unchanged selection.
- **Commit:** 681e870

**5. [Rule 2 - Missing critical] `raise` skips strips that are out for a Space change**
- **Found during:** Task 3
- **Issue:** a focus event that arrives just before the Space change would `orderFrontRegardless` a strip onto the wrong Space.
- **Commit:** f16ff19

### Scope notes
- Group buttons are not drawn yet: `TabStripLayout` supports them, and the view passes `[]` (a `shortcut:` comment) until 07-05 adds Close / Minimize and 07-06 Float / Dock.
- Right-click context menu (Surface 4) and accessibility custom actions (Close Tab, Move Out of Group) are later plans.
- The strip follows only through the drag poll and the backstop. There is no per-frameApplied follow; an engine replan's `.tabStrips` only arrives when the frame changes.
- The hover fill is a sublayer above the drawn tab, so it tints the title slightly (8% / 16% labelColor).

**Total deviations:** 5 auto-fixed (3 bugs, 1 blocking, 1 missing critical)
**Impact on plan:** none on scope.

## Issues Encountered
None. Host: `swift test` 846 + 378 + 198 + 90 tests passed (`.build/0703-t3.log`), `scripts/check-no-appkit.sh` OK. VM: `TabStripSpaceIntegrationTests` "Test run with 1 test in 1 suite passed" (`.build/0703-t3-vm.log`), and `TabGroupIntegrationTests` re-run "Test run with 2 tests in 1 suite passed" (`.build/0703-tabgroup-vm.log`). Nothing live ran on the host.

## User Setup Required
None.

## Next Phase Readiness
- 07-05 / 07-06 pass `buttons` into `TabStripLayout` (via the view's `layout`) and draw and hit-test `buttonRects`.
- Lock / unlock stranding remains a 07-11 UAT item.

## Self-Check: PASSED
