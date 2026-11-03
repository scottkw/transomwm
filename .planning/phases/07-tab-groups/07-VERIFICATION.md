---
phase: 07-tab-groups
verified: 2026-11-02T04:16:03Z
status: passed
score: 6/6 roadmap success criteria verified in engine logic and code wiring (host suite re-run by the verifier, 1,663 tests green); live screen behaviour pending the 07-UAT pass; 1 review-fix truth present, behaviour-unverified (CR-01 shell ordering)
covered_files:
  - ".planning/phases/07-tab-groups/07-01-PLAN.md"
  - ".planning/phases/07-tab-groups/07-01-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-02-PLAN.md"
  - ".planning/phases/07-tab-groups/07-02-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-03-PLAN.md"
  - ".planning/phases/07-tab-groups/07-03-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-04-PLAN.md"
  - ".planning/phases/07-tab-groups/07-04-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-05-PLAN.md"
  - ".planning/phases/07-tab-groups/07-05-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-06-PLAN.md"
  - ".planning/phases/07-tab-groups/07-06-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-07-PLAN.md"
  - ".planning/phases/07-tab-groups/07-07-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-08-PLAN.md"
  - ".planning/phases/07-tab-groups/07-08-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-09-PLAN.md"
  - ".planning/phases/07-tab-groups/07-09-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-10-PLAN.md"
  - ".planning/phases/07-tab-groups/07-10-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-11-PLAN.md"
  - ".planning/phases/07-tab-groups/07-11-SUMMARY.md"
  - ".planning/phases/07-tab-groups/07-12-PLAN.md"
  - ".planning/phases/07-tab-groups/07-12-SUMMARY.md"
  - "Sources/TransomEngine/Arranger+Camera.swift"
  - "Sources/TransomEngine/Arranger+Commands.swift"
  - "Sources/TransomEngine/Arranger+Tabs.swift"
  - "Sources/TransomEngine/Arranger.swift"
  - "Sources/TransomEngine/Command.swift"
  - "Sources/TransomEngine/DragSession.swift"
  - "Sources/TransomEngine/ExclusionFilter.swift"
  - "Sources/TransomEngine/Planner.swift"
  - "Sources/TransomEngine/TransomURL.swift"
  - "Sources/TransomEngine/ViewPlanner.swift"
  - "Sources/TransomEngine/WindowSystem.swift"
  - "Sources/TransomMac/AX/AXAppThread.swift"
  - "Sources/TransomMac/AXWindowSystem.swift"
  - "Sources/TransomMac/ArrangeController.swift"
  - "Sources/TransomMac/Input/Hotkeys.swift"
  - "Sources/TransomMac/Overlay/PreviewStyle.swift"
  - "Sources/TransomMac/Overlay/TabStripLayout.swift"
  - "Sources/TransomMac/Overlay/TabStripPanels.swift"
  - "Sources/TransomMac/Overlay/TearOffGhost.swift"
  - "Sources/TransomMac/Overview/OverviewController.swift"
  - "Sources/TransomMac/Shell/CommandMenu.swift"
  - "Sources/TransomMac/Shell/MenuCopy.swift"
  - "Sources/TransomMac/Shell/StatusItemController.swift"
  - "Sources/TransomMac/Shell/TabCopy.swift"
  - "Sources/TransomMac/Zoom/CollapsedPanels.swift"
  - "Sources/TransomMac/Zoom/ShortcutsWindowController.swift"
  - "Sources/TransomMac/Zoom/StagePanel.swift"
  - "Sources/TransomMac/Zoom/TileLayer.swift"
  - "Sources/TransomMac/Zoom/ZoomController.swift"
  - "Sources/TransomMac/Zoom/ZoomInput.swift"
  - "Sources/TransomModel/DesktopLayer.swift"
  - "Sources/TransomModel/DropZones.swift"
  - "Sources/TransomModel/Resolve.swift"
  - "Sources/TransomModel/TabBand.swift"
  - "Sources/TransomModel/TreeEdits.swift"
  - "Sources/TransomModel/World.swift"
  - "Sources/TransomTestSupport/FakeWindowSystem.swift"
  - "Tests/TransomEngineTests/ArrangerDragTests.swift"
  - "Tests/TransomEngineTests/ArrangerTabsTests.swift"
  - "Tests/TransomEngineTests/TransomURLTests.swift"
  - "Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/TabStripSpaceIntegrationTests.swift"
  - "Tests/TransomMacTests/CommandMenuTests.swift"
  - "Tests/TransomMacTests/HotkeyTableTests.swift"
  - "Tests/TransomMacTests/LayoutStoreTests.swift"
  - "Tests/TransomMacTests/OverviewTabInputsTests.swift"
  - "Tests/TransomMacTests/PreviewStyleTests.swift"
  - "Tests/TransomMacTests/ShortcutsModelTests.swift"
  - "Tests/TransomMacTests/TabCopyTests.swift"
  - "Tests/TransomMacTests/TabStripLayoutTests.swift"
  - "Tests/TransomMacTests/TileLayerTests.swift"
  - "Tests/TransomModelTests/LayoutEditTests.swift"
  - "Tests/TransomModelTests/LifecycleTests.swift"
  - "Tests/TransomModelTests/ResolveTests.swift"
  - "Tests/TransomModelTests/ScenarioTests.swift"
  - "Tests/TransomModelTests/TabGroupModelTests.swift"
  - "Tests/TransomModelTests/TabsTests.swift"
  - "Sources/TransomEngine/PendingFocus.swift"
  - "Sources/TransomMac/CloseGroupConfirmation.swift"
  - "Tests/TransomEngineTests/PendingFocusTests.swift"
  - "Tests/TransomMacTests/AppDelegateTests.swift"
  - "Tests/TransomMacTests/CloseGroupConfirmationTests.swift"
covered_digest: "v4:sha256:14e143bb6e06ee474919d7af8ae9d22b09a07350875dd2ca19ebf7e89558e52c"
behavior_unverified: 1
overrides_applied: 0
behavior_unverified_items:
  - truth: "CR-01 (review fix 21f3353): excluding an app (Don't Arrange, or an exclusions list edit) brings its hidden tabs back on screen at the group's content rect, out of their group. The shell must queue the release writes after flipping the app thread to excluded, so no older park lands after them (AXWindowSystem.setExcludedBundleIDs → releaseFramesBeforeExcluding → writeForTermination)"
    test: "Group a TextEdit window (hidden tab) with a Finder window (selected), then choose Don't Arrange for TextEdit from the menu while TextEdit is frontmost (or add it to the exclusions list). Repeat with a floating group"
    expected: "The hidden TextEdit window appears at the group's content rect and is no longer in the group; a two-member group dissolves, so Finder becomes a plain tile or floater with no strip. Nothing is left at the off-screen sliver, including after a quit"
    why_human: "The engine half is tested (ArrangerTabExclusionTests, 2 tests). The write ordering on the AX thread is not: no live suite drives an exclusion change through ArrangeController (ExclusionIntegrationTests uses a bare AXWindowSystem with no hook), which 07-REVIEW-FIX says itself"
human_verification:
  - test: "Before any pass: rebuild the Debug app with scripts/build-debug.sh"
    expected: "The build under test includes the six review-fix commits (21f3353, 107248d, 490a471, 91a74fd, c1dc174, 2a2c5b0)"
    why_human: "The signed app named in 07-UAT ('Build under test', binary dated Nov 1 21:33) predates every review-fix commit (21:4x-22:10). 07-UAT also names HEAD 8a8973a; it should name 02e55b5 or later"
  - test: "07-UAT section 1, host checklist items 1-5 (Finder onto docked TextEdit with the dwell; click tabs; tear off onto the Desktop; Safari multi-tab as one member; Close Group with unsaved TextEdit)"
    expected: "As written in each 07-UAT item"
    why_human: "Real apps (Finder, TextEdit, Safari save sheets and native tabs), a real pointer and visual checks. Item 1 is also the only live proof of SC5's cross-app grouping: every VM suite uses windows of one fixture process"
  - test: "07-UAT section 2, VM checks V1-V13, run one at a time in the Tart VM by the orchestrator. Also re-run TabGroupIntegrationTests and TabStripSpaceIntegrationTests after the review fixes (07-REVIEW-FIX reports a 5/5 TabGroupIntegrationTests pass after the fixes, but its log was not kept; the .build/0712-vm-*.log passes predate the fixes)"
    expected: "As written in each 07-UAT item; both suites pass"
    why_human: "SC1 dwell-to-group by drag, SC2 tab click, SC4 tear-off and Esc, SC6 context menu tracking from a never-active panel (RESEARCH A3), kill -9 relaunch, Restore All + Undo and lock/unlock need posted pointer gestures or session events that the live suites do not post"
  - test: "WR-02 behaviour (review fix 490a471 + 2a2c5b0, flagged 'requires human verification' in 07-REVIEW-FIX): (a) ⌘M the selected window of a docked two-app group, then restore it from the Dock; (b) Minimize Group on a group holding two windows of one app, then click the minimised member's tab before restoring it; (c) with that group minimised, ⌘Tab to the app"
    expected: "(a) The right (else left) neighbour is selected at once, and the tile and strip stay; when the minimised window comes back from the Dock it is focused and selected (D-08). (b) The group stays minimised and no invisible window holds keyboard focus; the tab beeps and says \"Couldn't show …\" until the window is restored from the Dock. (c) Focus never lands on a parked window. Confirm this is the behaviour you want"
    why_human: "This changes what the user sees when a selected member goes absent. The engine tests pin the rules, but whether the UX is right is a product decision"
  - test: "Cross-app floating group (SC5): on the Desktop tile, drag a floating Finder window onto the middle of a floating TextEdit window, hold about half a second and release; click each tab; drag the group by Finder's title bar"
    expected: "A floating group at TextEdit's old frame with Finder selected; tabs swap in place; the strip follows the drag"
    why_human: "07-UAT host item 1 covers only a docked cross-app group, and V1 uses fixture windows from one process. The engine side passes (membersFromDifferentAppsGroupDockedAndFloating)"
  - test: "07-UAT section 3, hardware backstops B1-B3 on the MacBook Air (strip follows a quick drag with no gap; no wallpaper flash over 10 cross-app switches; VoiceOver reads the strip as a tab group, with Close Tab and Move Out of Group in the actions rotor)"
    expected: "As written in each 07-UAT item"
    why_human: "Frame-level visual timing and screen reader output"
  - test: "CR-01 exclusion of a hidden tab (see behavior_unverified_items)"
    expected: "As in behavior_unverified_items"
    why_human: "The shell write ordering has no live test"
---

# Phase 7: Tab Groups Verification Report

**Phase Goal:** As a Mac user, I want to group windows from any apps into one tabbed tile, so that related windows share space without overlapping.
**Mode:** mvp (user story form)
**Verified:** 2026-11-02T04:16:03Z
**Status:** human_needed. No truth failed and no blocker was found. Every success criterion is built, wired and covered by passing engine tests, but each one also has a live screen half that only the 07-UAT pass can show.
**Re-verification:** No, initial verification

## User Flow Coverage

| # | Step of the user story | Expected | Evidence in codebase | Status |
|---|---|---|---|---|
| 1 | Drag a window onto the middle of another and rest there | After 400 ms within 16 pt, the preview turns into a group outline with a band; release groups the two | `DragSession.groupDwell = 400 ms`, `groupRest = 16` (`DragSession.swift:135-137`); `Arranger.swift:1513` `settleGroup` → `decideGroup` (`Arranger+Tabs.swift:176`); release → `commitGroup` (`Arranger.swift:1715`). Floating target: `floatingGroupTarget` / `commitFloatingGroup` | ✓ VERIFIED (logic); live drag in UAT 1 / V-checks |
| 2 | One tab strip over the group, nothing overlapping | Strip in the top band, members in the content rect, hidden members parked | `TabBand` (32 pt band) in `Resolve.swift:165` (`hiddenTabs`); `Planner.swift:75` parks; replan parks loop (`Arranger.swift:2025-2044`) → `.park(size:)` → `AXWindowSystem.swift:244` writes `parkedFrame` (a frame write, not a minimise); strips via `.tabStrips` → `TabStripPanels.show` | ✓ VERIFIED |
| 3 | Switch, close, minimise, dock/float and leave the group | Tab click reveals, then parks; group buttons act on the group; tear-off and the context menu take a member out | `TabStripView.mouseUp` → `onAction(.select)` → `ArrangeController.tabAction` → `Arranger.tab` (`Arranger+Tabs.swift:425`); buttons → `.closeGroup/.minimizeGroup/.toggleGroupFloat`; `rightMouseDown` → NSMenu → `.closeTab/.moveOut`; strip press → `PointerEvent.pressTab` → `pressTab`/`tearOff` (`Arranger.swift:1414,1426`) | ✓ VERIFIED (logic); live in UAT |
| 4 | Windows from any apps, docked or floating | The same rules for any pids, in the tree and on the Desktop layer | `FloatingTabGroup` sidecar in `DesktopLayer.swift` (optional `groups` key); the engine has no per-app branch; `membersFromDifferentAppsGroupDockedAndFloating` passes | ✓ VERIFIED (logic); live cross-app in UAT 1 + floating item |

The `[outcome]` clause, "related windows share space without overlapping", holds in the model: a group plans exactly one written frame (the selected member at the content rect), and every other member gets a park (`aTwoMemberGroupPlans…`, `hiddenMembersParkAtTheContentSize`, VM `aSavedGroupReformsWithTheHiddenMemberParkedAtTheContentSize`).

## Goal Achievement

### Observable Truths (roadmap contract)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Dropping a window on the middle of another and pausing groups them under one tab strip that follows the group as it moves and resizes | ✓ VERIFIED (logic + wiring) | Dwell: `ArrangerTabsTests` (`aCentreHeldFor400msGroupsWithTheDraggedWindowSelected`, `aReleaseInACentreBeforeTheGroupDwellIsTheMissWithNoBeep`, `aMoveOfMoreThan16ptInsideTheCentreRestartsTheGroupDwell`, `aDropOnAGroupAddsTheWindowAsTheLastSelectedTab`), floating: `ArrangerFloatingTabsTests` (7). Follow: any press on a tracked window starts a session that polls CG bounds (`Arranger.swift:1436-1439`), and `ArrangeController.pollDragFrame` calls `tabStripPanels.follow` on every poll (`:509`). The 500 ms backstop `checkDrift` handles moves made by the app. A resize replans and re-sends strip frames. Floating group moves: `movingTheSelectedMemberMovesTheWholeGroup`. The visual follow is UAT B1 |
| 2 | Clicking a tab switches the visible window; the others stay hidden (not minimised) | ✓ VERIFIED | `select` writes and focuses the new member, and the previous one parks only on the read-back (`revealed`, origin within 2 pt, size within the refusal margin after WR-01). Timeout reverts and refocuses. Hidden = `.park` frame write, never `.minimize`. Tests: `ArrangerTabSelectTests` (7), `ArrangerTabRevealToleranceTests` (3), `ArrangerTabActivationTests` (D-08), VM `selectingTheHiddenTabRevealsItBeforeTheOtherParks` (passed in 07-12). Click-path wiring: `mouseUp` < 4 pt travel → `.select` |
| 3 | The group's close, minimise and dock/float buttons act on the whole group | ✓ VERIFIED (with the D-06/D-07 reading of "minimise") | Close Group: `closeQueue` presses AX close on each member in turn (`kAXCloseButtonAttribute` + `kAXPressAction`, `AXAppThread.swift:247-250`), revealing hidden members first and stopping at a member still open after 1 s. Minimise: only the selected member is minimised and the hidden ones stay parked, so the whole group leaves the screen and comes back with the same tab (`ArrangerMinimizeGroupTests` 5, VM `minimizeGroupWithTwoWindowsOfOneAppStaysMinimized`). Dock/Float: `toggleGroupFloat` → `floatGroup` (`removeLeaf` + `addGroup`, one `World.edit`) / `dockGroup`. Tests: `ArrangerCloseGroupTests` (6), `ArrangerWholeGroupTests` (11), `ArrangerWholeGroupDragTests` (7), VM `closeAndMinimizeCommandsActOnFixtureWindows` |
| 4 | Dragging a tab out of the strip makes it its own window again | ✓ VERIFIED (logic + wiring) | Tap: a press on a strip window number → `tabStripPanels.member(atWindowNumber:)` → `PointerEvent.pressTab` (`ArrangeController.swift:406-427`); leaving the strip → `tearOff`; release → `releaseTearOff` (dock / group / float at the clamped landing frame / cancel over the source strip). Esc: temporary Carbon hotkeys only during the tear-off (`listenForTearOffEscape`). Tests: `ArrangerTearOffTests` (4), `ArrangerTearOffReleaseTests` (7), `ArrangerTearOffCancelTests` (2). Live gestures are V4-V6 and UAT 3 |
| 5 | Tab groups work for windows from different apps, both docked and floating on the Desktop tile | ✓ VERIFIED (logic) | `membersFromDifferentAppsGroupDockedAndFloating`; `FloatingTabGroup` validation and decode (`TabGroupModelTests`, `FloatingTabGroupModelTests`, `LayoutStoreTests`); `aDockedWindowDroppedOnAFloaterGroupsOnTheDesktop`. ⚠️ Every live suite uses one fixture process, so a real cross-app group has only been shown by engine tests. UAT host item 1 (docked) and the added floating item close this |
| 6 | Right-clicking a tab offers close and move-out | ✓ VERIFIED (logic + wiring) | `rightMouseDown` / ⌃-click → `contextMenu` builds an NSMenu with exactly `TabCopy.closeTab`, `TabCopy.moveOut` → `.closeTab(member)` / `.moveOut(member, via: .menu)`. The tap never tears off on ⌃-click (`!maskControl`). VoiceOver: `NSAccessibilityCustomAction`s (`TabStripPanels.swift:245-249`). Tests: `ArrangerTabsMoveOutTests` (8), `ArrangerTabsCloseTabTests` (5). Menu tracking from a never-active panel is Assumption A3, UAT V10 |

**Score:** 6/6 roadmap truths verified in logic and wiring (1 review-fix truth present, behaviour-unverified: CR-01 shell ordering. The UI-SPEC backstops in 07-12 are `verification: backstop` items and wait on 07-UAT).

### Plan must-haves (checked by plan)

| Plan | Result | Notes |
|---|---|---|
| 07-01 dwell, band, sized parks, Group preview | ✓ | Dwell/rest constants, `TabBand`, `Resolve.hiddenTabs`, `Planner.dockTarget` never groups (keyboard Dock), undo tests |
| 07-02 strip + click-to-switch, D-08, D-09 | ✓ | Non-activating `StripPanel` (`canBecomeKey/Main false`, `.nonactivatingPanel`); Pitfall 4 guard (`onStrip` skips `pointerDown` and the window press); `visibleMemberID` for native tabs (live: UAT 4) |
| 07-03 follow, ordering, Space, overflow, VoiceOver | ✓ with Info | `follow`, 500 ms `checkDrift` (CG only), `leftOnAnotherSpace` replacement, `.tabGroup`/radio roles. IN-06: `fadeIn` uses `orderFrontRegardless`, so a strip re-shown after a Space switch or the stage can come up over an overlapping floating window (see Anti-Patterns) |
| 07-04 floating groups, persistence, validation | ✓ | `decodeIfPresent(groups) ?? []` is the documented default; empty list not written; `DesktopLayer.validate` cases tested |
| 07-05 Close/Minimize Group, member close, dissolve | ✓ | As truth 3; `anExcludedMembersCloseNeverReachesTheSystem` |
| 07-06 whole-group moves | ✓ | WR-03 changed "re-homing … moves the whole group" to display moves only; a Space move takes the selected member out alone (`movingTheSelectedMemberToAnotherSpace…`). This narrows the 07-06 truth for a correctness reason (AX can't move windows across Spaces) |
| 07-07 tear-off | ✓ | As truth 4 |
| 07-08 context menu, custom actions | ✓ | As truth 6 |
| 07-09 tab commands | ✓ | `Hotkeys.swift:56-57,109-111`, `TransomURL.swift:18`, `CommandMenu.swift:65`; `ArrangerTabCommandTests`, `HotkeyTableTests`, `TransomURLTests`, `ShortcutsModelTests` |
| 07-10 quit, Restore All, crash relaunch | ✓ | `restorePlan()` now shared by quit restore and the CR-01 release (`ArrangeController.swift:978`); `dissolveAllGroups` called from `restoreAll`; `ArrangerTabSafetyTests` (13); VM `quitPlacesEveryGroupMemberAtTheContentRect` |
| 07-11 stage and overview | ✓ | `CameraMove.strips` → `ZoomController.swift:524`; `ArrangerTabStageTests`, `ArrangerTabCollapsedBlockTests`, `TileLayerTests`, `OverviewTabInputsTests` |
| 07-12 gate | ✓ with caveat | Gate artefacts exist; the signed Debug build and the VM logs predate the review fixes (see Human Verification) |

### Required Artifacts

`gsd-tools verify.artifacts` passed for every plan (07-01 5/5, the others 2/2 or 1/1).

| Artifact | Status | Details |
|---|---|---|
| `Sources/TransomEngine/Arranger+Tabs.swift` | ✓ VERIFIED | 1,048 lines; every entry point is called from `Arranger.swift` (event, tick, pointer, release) |
| `Sources/TransomMac/Overlay/TabStripPanels.swift` | ✓ VERIFIED | 621 lines; owned by `ArrangeController` (`:69`), `onAction` and `bounds` wired (`:147,150`) |
| `Sources/TransomMac/Overlay/TabStripLayout.swift`, `TearOffGhost.swift` | ✓ VERIFIED | Used by the strip view and by `.tearOffGhost` effects |
| `Sources/TransomModel/TabBand.swift`, `DesktopLayer.swift` groups, `TreeEdits` leaf moves | ✓ VERIFIED | Used by Resolve, Planner, Arranger |
| `Sources/TransomMac/Shell/TabCopy.swift` | ✓ VERIFIED | Strings used by the strip, announcements and the menu |
| `Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift`, `TabStripSpaceIntegrationTests.swift` | ✓ VERIFIED | Skip on the host as intended; VM passes logged in `.build/0712-vm-*.log` |

### Key Link Verification

`verify.key-links` reported most links as "source file not found" because the plans put a symbol after the path in `from:`, which is a format problem, not missing code. Each link was checked by hand:

| From | To | Via | Status |
|---|---|---|---|
| Replan (`planShown`) | AX writes | `.perform([.setFrame/.park])` → `AXWindowSystem.perform` → `enqueueFrame` | ✓ WIRED |
| Engine `.tabStrips` | strip panels | `ArrangeController.run` → `tabStripPanels.show(…, space:)` | ✓ WIRED |
| `pollDragFrame` | strip follow | `tabStripPanels.group(selecting:)` → `follow(_:contentBounds:)` | ✓ WIRED |
| Strip buttons / tabs / context menu | engine | `onAction` → `tabAction` → `.tab(action, ready:)` → `Arranger.tab` | ✓ WIRED |
| Close queue | AX close press | `.close` → `AXAppThread.closeWindow` (close button `AXPress`) | ✓ WIRED |
| Strip press | tear-off | `handle(TapEvent)` → `PointerEvent.pressTab` → `pressTab` / `tearOff` | ✓ WIRED |
| Hotkeys / URLs / menu | `Command.tabs` | `Hotkeys` table, `TransomURL` whitelist, `CommandMenu` Tabs submenu → `.tab(.command…)` | ✓ WIRED |
| Quit restore | member frames | `restoreForTermination` → `arranger.restorePlan()` | ✓ WIRED |
| Restore All | dissolve | `Arranger+Commands.restoreAll` → `dissolveAllGroups()` | ✓ WIRED |
| `CameraMove.strips` | stage | `ZoomController` builds strip layers from `move.strips` | ✓ WIRED |
| Exclusion change | release writes | `ExclusionStore.onChange` → `setExcludedBundleIDs` → `releaseFramesBeforeExcluding` → `Arranger.releaseFrames(forExcluding:)` | ✓ WIRED (ordering not live-tested) |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| Strip tabs | `TabStrip.members`, titles | `Arranger.tabStrips(desk:plan:)` from the World's `.tabs` leaves and `FloatingTabGroup`s; titles from tracked `titleHint` | Yes | ✓ FLOWING |
| Strip position at rest | `strip.frame` | `TabBand.strip` of the planned group rect | Yes | ✓ FLOWING |
| Strip position while moving | CG bounds | `dragPoller` (drag) and `bounds` closure (500 ms backstop) | Yes | ✓ FLOWING |
| Debug "Tab groups" line | `tabGroupCounts()` | every desk's docked and floating groups | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full host suite (run once by the verifier, at HEAD 02e55b5 with the review fixes) | `env -u TRANSOM_LIVE swift test` | 219 + 390 + 93 + 961 = 1,663 Swift Testing tests passed, exit 0; live suites skipped on the host ("needs a process with the Accessibility grant") | ✓ PASS |
| Tab filter gate proves tests ran | `swift test --filter 'ArrangerTab\|ArrangerTearOff\|TabGroupModelTests\|TabStripLayoutTests\|TabCopyTests'` | "Test run with 145 tests in 26 suites passed", "26 tests in 4 suites", "12 tests in 3 suites" | ✓ PASS |
| Review-fix suites | in the full run | `ArrangerTabExclusionTests`, `ArrangerTabRevealToleranceTests`, `ArrangerTabSpaceRehomeTests`, `ArrangerTabDragParkTests`, `ArrangerMinimizeGroupTests` all passed | ✓ PASS |
| Engine and model import no AppKit | `scripts/check-no-appkit.sh` | `no-appkit: OK (55 files)` | ✓ PASS |
| VM suites (07-12, before the review fixes) | `.build/0712-vm-*.log` | TabGroupIntegrationTests 5, TabStripSpaceIntegrationTests 1, QuitRestoreIntegrationTests 3, FocusParkIntegrationTests 2, TabsIntegrationTests 1, all passed | ✓ PASS (pre-fix) |
| VM TabGroupIntegrationTests after the fixes | 07-REVIEW-FIX | "5 tests in 1 suite passed" reported; no log kept | ? reported only; re-run in the VM |

The verifier ran no live test, overlay panel, tap, AX write or window-opening code on the host.

### Probe Execution

None declared for this phase (no `scripts/*/tests/probe-*.sh`). Step 7c: not applicable.

### Requirements Coverage

| Requirement | Source plans | Description | Status | Evidence |
|---|---|---|---|---|
| TABS-01 | 07-01..04, 07-10..12 | Centre drop + pause groups under one strip | ✓ SATISFIED (logic) / ? live UAT 1 | Truth 1 |
| TABS-02 | 07-02..05, 07-09, 07-10, 07-12 | Click a tab switches; others hidden | ✓ SATISFIED (logic + VM) / ? live click V2, UAT 2 | Truth 2 |
| TABS-03 | 07-05, 07-06, 07-12 | Close, minimise, dock/float act on the whole group | ✓ SATISFIED (logic + VM) / ? UAT 5 | Truth 3 |
| TABS-04 | 07-07..09, 07-12 | Tab dragged out becomes its own window | ✓ SATISFIED (logic) / ? V4-V6, UAT 3 | Truth 4 |
| TABS-05 | 07-01, 07-04, 07-06, 07-10..12 | Different apps, docked or floating | ✓ SATISFIED (logic) / ? live cross-app | Truth 5 |
| TABS-06 | 07-08, 07-09, 07-12 | Right-click offers close and move-out | ✓ SATISFIED (logic) / ? V10 menu tracking | Truth 6 |

All six IDs are claimed by plans and none is orphaned. Bookkeeping: REQUIREMENTS.md still shows TABS-02, 03, 04 and 06 unchecked/Pending and TABS-01, 05 Complete. Update them after the UAT pass. 07-VALIDATION.md is still `status: draft`, `nyquist_compliant: false`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (all 57 phase source and test files) | — | TBD / FIXME / XXX / TODO / HACK | none found | — |
| `Sources/TransomMac/Overlay/TabStripPanels.swift` | 567-574 | IN-06 open: `fadeIn` → `orderFrontRegardless` on every re-show | ⚠️ Warning | After a Space switch or a stage reveal, a strip can come up over a floating window that overlaps the group's band. This weakens the 07-03 rule "a floating window raised over a group covers its strip" on that path. UAT V1 tests only the steady state |
| `Sources/TransomEngine/Arranger.swift` | 833-842 | IN-02 open: `closeQueue`, `tearPress`, `tearing` and `minimizing` are not rekeyed | ℹ️ Info | Close Group count can be one off after a rekey; nothing is lost |
| `Sources/TransomEngine/Arranger+Tabs.swift` | 816 | IN-01 open: a tear-off into another group doesn't announce its source group ending | ℹ️ Info | VoiceOver users miss "Tab group ended" on that path |
| `Sources/TransomEngine/Arranger.swift` | 332 | IN-03 open: `.command(.tabs)` hard-codes `ready: true` | ℹ️ Info | No current caller is affected; shell routes go through `.tab(.command, ready:)` |
| `Sources/TransomModel/Resolve.swift`, `DesktopLayer.swift` | 84, 177 | IN-04 / IN-05 open | ℹ️ Info | Unfit-victim ranking for groups; member frames of a hand-edited layout.json not checked against the content rect |
| `Sources/TransomModel/DesktopLayer.swift` | 215 | IN-07: schema stays 2 with `groups` | ℹ️ Info | Downgrading to an older build mis-reads groups. Record this before the first public release |
| `Sources/TransomMac/Overlay/TabStripPanels.swift` | 336 | `shortcut:` context menu uses `popUp(positioning:at:in:)` (A3) | ℹ️ Info | UAT V10 decides; the fix route is documented |
| `Sources/TransomMac/Zoom/StagePanel.swift` | 27 | `shortcut:` strip IDs flip the top bit | ℹ️ Info | Listed in 07-UAT Known gaps |

### Human Verification Required

These are the frontmatter items, in the order to run them:

1. **Rebuild first** (`scripts/build-debug.sh`). The app named in 07-UAT predates all six review-fix commits.
2. **07-UAT section 1, host items 1-5** (user, host).
3. **07-UAT section 2, V1-V13** (orchestrator, Tart VM, one at a time), plus a post-fix re-run of `TabGroupIntegrationTests` and `TabStripSpaceIntegrationTests`.
4. **WR-02 behaviour:** ⌘M on the selected member selects a neighbour; Minimize Group with two windows of one app stays minimised with no invisible key window; a minimised member's tab says "Couldn't show". The user should confirm this is the behaviour they want.
5. **Cross-app floating group** (SC5): Finder dropped onto a floating TextEdit window.
6. **07-UAT section 3, B1-B3** (MacBook Air).
7. **CR-01:** Don't Arrange on an app whose window is a hidden tab, docked and floating.

### Gaps Summary

There are no blocking gaps. All six success criteria have real, wired code behind them and passing behavioural engine tests. The host suite was re-run here after the review fixes: 1,663 tests, 0 failures. Phase 7's VM suites passed before the fixes. Status is `human_needed` for four reasons:
- Each criterion has a live half (drag dwell, strip clicks, tear-off, context menu tracking, real cross-app windows) that only the 07-UAT pass can show.
- The CR-01 shell write ordering has no live test.
- WR-02 changed visible behaviour and needs a product decision.
- The signed build and the VM logs predate the review fixes.

Accepted known gaps, not counted:
- There is no keyboard or VoiceOver way to form a group (UI-SPEC unresolved item; candidate for Phase 8's URL/CLI "group with"; Phase 8's roadmap does not list it yet).
- Multi-display tab checks are deferred because there is no external display.
- macOS 14 is untested; evidence comes from the VM (15.7.7) and the host (27.2).

---

_Verified: 2026-11-02T04:16:03Z_
_Verifier: Claude (gsd-verifier)_

## Human Verification Result (2026-11-03)

Host checks on macOS 27.2 (MacBook Air, one display), Debug build; VM run V1-V16 in 07-UAT.md:
- Items 1, 2, 4 and backstops B1, B2: pass.
- Item 3 (tab drag-out): failed first. Hardware events leave the window-under-pointer field 0 at the session tap, so a strip press was never recognised (the VM harness had filled the field). Fixed by c35449d (the strip is hit-tested under the pointer); VM `TabGroupIntegrationTests` 7/7; host re-check pass.
- Item 5 (Close Group with a save prompt): Close Group stopped at the prompt and left the rest open after the answer. By user decision it now confirms first ("Do not show this again") and continues once the prompt is answered with Save or Delete; Cancel stops (693d989, docs 66c3a73; D-06 clarified). Host re-check pass.
- B3 VoiceOver: pass (group announced; tabs read app, title, position after VO-Shift-Down; Close Tab and Move Out in the actions).
- Earlier VM bugs fixed by 5a48451 (app activation selects the hidden tab) and bdd2d22 (URL commands use the app frontmost before Transom).

Accepted gaps are listed in 07-UAT.md "Known gaps". Status: **passed**.

_Verified: 2026-11-03_

