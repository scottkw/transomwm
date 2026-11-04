---
phase: 08-saved-views-urls-persistence
verified: 2026-11-04T03:12:29Z
status: gaps_found
score: 55/71 must-haves verified (2 failed from one root cause, 4 present but behavior-unverified, 10 need a human)
covered_files:
  - ".planning/phases/08-saved-views-urls-persistence/08-01-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-01-SUMMARY.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-02-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-02-SUMMARY.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-03-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-03-SUMMARY.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-04-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-04-SUMMARY.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-05-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-05-SUMMARY.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-06-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-06-SUMMARY.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-07-PLAN.md"
  - ".planning/phases/08-saved-views-urls-persistence/08-07-SUMMARY.md"
  - "Package.swift"
  - "README.md"
  - "Sources/TransomEngine/Arranger+Camera.swift"
  - "Sources/TransomEngine/Arranger+Placeholders.swift"
  - "Sources/TransomEngine/Arranger+Tabs.swift"
  - "Sources/TransomEngine/Arranger+Views.swift"
  - "Sources/TransomEngine/Arranger.swift"
  - "Sources/TransomEngine/CLICommandLine.swift"
  - "Sources/TransomEngine/CLICopy.swift"
  - "Sources/TransomEngine/CLIProtocol.swift"
  - "Sources/TransomEngine/Command.swift"
  - "Sources/TransomEngine/HintMatcher.swift"
  - "Sources/TransomEngine/LayoutFile.swift"
  - "Sources/TransomEngine/LayoutRestore.swift"
  - "Sources/TransomEngine/Navigator.swift"
  - "Sources/TransomEngine/Notice.swift"
  - "Sources/TransomEngine/OverviewLayout.swift"
  - "Sources/TransomEngine/SavedViews.swift"
  - "Sources/TransomEngine/SpaceRekey.swift"
  - "Sources/TransomEngine/TransomURL.swift"
  - "Sources/TransomEngine/WindowSystem.swift"
  - "Sources/TransomFixtureApp/main.swift"
  - "Sources/TransomMac/AppDelegate.swift"
  - "Sources/TransomMac/ArrangeController.swift"
  - "Sources/TransomMac/BootSession.swift"
  - "Sources/TransomMac/CLIListener.swift"
  - "Sources/TransomMac/CommandGate.swift"
  - "Sources/TransomMac/Input/Hotkeys.swift"
  - "Sources/TransomMac/LayoutStore.swift"
  - "Sources/TransomMac/Overlay/NoticeQueue.swift"
  - "Sources/TransomMac/Overlay/PlaceholderPanels.swift"
  - "Sources/TransomMac/Overlay/Toast.swift"
  - "Sources/TransomMac/Overview/OverviewController.swift"
  - "Sources/TransomMac/Shell/MenuCopy.swift"
  - "Sources/TransomMac/Shell/NoticeCopy.swift"
  - "Sources/TransomMac/Shell/StatusItemController.swift"
  - "Sources/TransomMac/Shell/ViewCopy.swift"
  - "Sources/TransomMac/TransomMacApp.swift"
  - "Sources/TransomMac/Zoom/ShortcutsWindowController.swift"
  - "Sources/TransomMac/Zoom/StagePanel.swift"
  - "Sources/TransomMac/Zoom/TileLayer.swift"
  - "Sources/TransomMac/Zoom/ZoomController.swift"
  - "Sources/TransomModel/DesktopLayer.swift"
  - "Sources/TransomModel/World.swift"
  - "Sources/transom-cli/main.swift"
  - "Tests/TransomEngineTests/ArrangerLifecycleTests.swift"
  - "Tests/TransomEngineTests/ArrangerMultiDeskRestoreTests.swift"
  - "Tests/TransomEngineTests/ArrangerPlaceholderTests.swift"
  - "Tests/TransomEngineTests/ArrangerRestoreTests.swift"
  - "Tests/TransomEngineTests/ArrangerTabsTests.swift"
  - "Tests/TransomEngineTests/ArrangerViewsTests.swift"
  - "Tests/TransomEngineTests/CLICommandLineTests.swift"
  - "Tests/TransomEngineTests/CLICopyTests.swift"
  - "Tests/TransomEngineTests/CLIProtocolTests.swift"
  - "Tests/TransomEngineTests/HintMatcherTests.swift"
  - "Tests/TransomEngineTests/OverviewLayoutTests.swift"
  - "Tests/TransomEngineTests/SpaceRekeyTests.swift"
  - "Tests/TransomEngineTests/TransomURLTests.swift"
  - "Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/ViewsIntegrationTests.swift"
  - "Tests/TransomMacTests/AppDelegateTests.swift"
  - "Tests/TransomMacTests/CLIListenerTests.swift"
  - "Tests/TransomMacTests/HotkeyTableTests.swift"
  - "Tests/TransomMacTests/LayoutStoreTests.swift"
  - "Tests/TransomMacTests/MenuCopyTests.swift"
  - "Tests/TransomMacTests/NoticeCopyTests.swift"
  - "Tests/TransomMacTests/NoticeQueueTests.swift"
  - "Tests/TransomMacTests/ShortcutsModelTests.swift"
  - "Tests/TransomMacTests/ViewCopyTests.swift"
  - "Tests/TransomMacTests/ZoomCopyTests.swift"
  - "Tests/TransomModelTests/PersistenceTests.swift"
  - "Tests/TransomModelTests/WorldAdoptTests.swift"
  - "scripts/release.sh"
  - "scripts/vm-cli-check.sh"
  - "xcode/project.yml"
covered_digest: "v4:sha256:f222c61fcee521272564ddb333ca13c49ced09f4579c0602cc478a7d92d99df7"
behavior_unverified: 4
overrides_applied: 0
decision_coverage:
  honored: 18
  total: 20
  not_honored: ["D-10a", "D-12b"]
gaps:
  - truth: "When an app quits while Transom runs, each of its docked windows keeps its tile as a placeholder instead of closing it (08-04, D-12a); tiles for windows on Spaces not being shown wait on every path and do not expire while their desk is hidden (D-12b)"
    status: partial
    reason: "A docked window that is dormant (on a hidden Space, kept by identity after a Transom restart, not yet visited) closes its tile at once when its app quits, with no placeholder. The tracked case waits; this one does not. The test aDormantWindowIsPrunedWhenItsAppTerminates pins the closing, and README line 57 says the opposite."
    artifacts:
      - path: "Sources/TransomEngine/Arranger.swift"
        issue: "Line 1020, in .appTerminated: `faults += closeDormant { $0.pid == pid }` closes dormant docked windows through the close path"
      - path: "Tests/TransomEngineTests/ArrangerMultiDeskRestoreTests.swift"
        issue: "Line 319, aDormantWindowIsPrunedWhenItsAppTerminates, pins the behaviour D-12a and D-12b rule out"
    missing:
      - "In .appTerminated, hold a dormant docked window of that pid as an .appQuit placeholder, keeping its bundle and title, instead of closing it. Floaters may still close"
      - "Make sure the inventory prune (Arranger.swift:297) can't close the same window first when the CG list loses it before .appTerminated arrives"
      - "Invert the pinning test: the tile stays while its desk is hidden, a relaunched window on that Space fills it, and it expires only after its desk shows"
behavior_unverified_items:
  - truth: "After rebooting the Mac, layouts come back with each window re-matched to its tile, and windows that never return leave a placeholder that expires (roadmap SC3, reboot half)"
    test: "Dock windows on Desktop 1 and Desktop 2, save a view on each, restart the Mac, and let apps reopen. Do it again with a second display's stored arrangement applied. Leave one app closed"
    expected: "Windows return to their own tiles. The Desktop 2 tile waits until you go there, then fills. The closed app's tile shows Waiting for it and closes after 5 min. Saved views land on the same windows"
    why_human: "The engine path is tested (retire, canFill, holdAtLaunch), and the VM covers only a simulated relaunch on one boot. No test reboots anything"
  - truth: "Going to a view on another Space refuses with \"Couldn't switch to Desktop {n}\" and leaves the camera unchanged when the switch isn't done within 1 s (08-03, D-03)"
    test: "Make a Space switch fail, for example with the Mission Control switch shortcut turned off, then press ⌥ and the view's digit"
    expected: "A beep and the announcement; the camera does not move; URL and CLI show nothing on screen"
    why_human: "aViewOnAnotherSpaceSwitchesFirst proves only the success path. No test forces a switch to fail"
  - truth: "Going to a view shown on another display moves that display's camera without moving the pointer, then focuses inside the view (08-03, D-03)"
    test: "With two displays, save a view on the second, put the pointer on the first, press ⌥ and the digit"
    expected: "The second display's camera moves, the pointer stays, and a window inside the view has focus"
    why_human: "The VM has one display. Only the engine half is tested (goingZoomsTheDestinationDisplayNotThePointers)"
  - truth: "Placeholder panels are ordered out when their desk's Space is hidden and re-shown when it returns, replaced if macOS stranded one (08-06, UI-SPEC Surface 2)"
    test: "With a placeholder shown, switch Spaces away and back"
    expected: "It is gone on the other Space and fades back on return, with no stranded panel"
    why_human: "PlaceholderPanels.spaceChanged has no test, and no VM test switches Spaces with a placeholder shown"
coincidental_reliance_items:
  - truth: "An app's relaunch fills its held tiles (08-04)"
    reason: incidental-ordering
    harden: "The hold needs .appTerminated before .windowDestroyed. Nothing enforces that: the live evidence is the fixture's exit(0). If ⌘Q on a real app closes windows first, add the Pitfall 1 rollback (WR-06)"
  - truth: "A placeholder's stage tile can't take a live window's layer (WR-11)"
    reason: undeclared-precondition
    harden: "Within one boot this assumes a dead CG window ID isn't reused, which the fixer did not verify and the test doesn't cover"
human_verification:
  - test: "Before any of these: rebuild with scripts/build-debug.sh (and scripts/release.sh --build-only for the Release check)"
    expected: "The build includes the review fixes up to d3a00be"
    why_human: "The Debug bundle dates from 19:44 and the Release bundle from 18:56 on Nov 3. Both predate every review-fix commit (20:13 onward)"
  - test: "Real keyboard chords: zoom into two windows, press ⇧⌥3, zoom out, press ⌥3; press ⌥7 on an empty slot. Repeat on a non-US input source such as German, and with a display under the pointer that isn't the main one"
    expected: "\"Saved view 3\", then \"View 3\" with the camera back on those windows; a beep and \"No view in slot 7\". The digit keys work by position, and each toast lands on the right display (pointer display when saving, target display when going)"
    why_human: "Live suites dispatch commands, not chords. The non-US truth is a non-inferable backstop (reason: insufficient_spec)"
  - test: "Open a transom://view/N and a transom://save-view/N URL from a shell and from Raycast, Alfred or Shortcuts; also an invalid one such as transom://view/0"
    expected: "The valid ones act with their toasts; the invalid one does nothing and shows nothing"
    why_human: "The parser, gate and dispatch are tested, and URL delivery was proven live for earlier commands, but no run opened a view URL through LaunchServices. Launchers can't run on the host or in the fixture tests"
  - test: "How a placeholder looks: quit an app with docked windows and look at its tile in light and dark, Increase Contrast, a small tile, on the stage and in the overview; also a long app name and the 120 ms fades when it fills and when it expires"
    expected: "A dim app-colour tile with a dashed border, icon and \"Waiting for {App}…\"; the icon and capsule hide in tiny tiles"
    why_human: "No test asserts pixels, and the panel is sharingType .none, so a screenshot may not show it"
  - test: "Space changes with a placeholder shown (see behavior_unverified_items)"
    expected: "As in behavior_unverified_items"
    why_human: "No VM test does this"
  - test: "⌘Q a real app with docked windows while Transom runs: TextEdit, Safari or Terminal, an Electron app, and a document app with a save prompt (WR-06, Assumption A1)"
    expected: "The tiles stay as \"Waiting for {App}…\" for 30 s, and a relaunch within that time puts each window back. If they collapse at once, add the Pitfall 1 rollback"
    why_human: "The fixture quits with exit(0), not AppKit's terminate path. The order can't be settled from the repo"
  - test: "A real Mac reboot with a tile on a second Space, including a stored display arrangement being applied (CR-02, CR-03, D-12b; see behavior_unverified_items)"
    expected: "As in behavior_unverified_items"
    why_human: "Non-inferable backstop (reason: insufficient_spec); only engine tests cover this"
  - test: "Going to a view on another Space when macOS moves focus outside it: save a view of one window on Desktop 2, with other windows there, then go to it from Desktop 1"
    expected: "The camera stays on the saved window; the Phase 4 focus-widen rule doesn't widen it past the view"
    why_human: "The 08-03 risk. The VM test has one window on that Space, so it can't show this"
  - test: "With VoiceOver on, go to a saved view"
    expected: "One line, \"View 3. Showing 2 windows\", once"
    why_human: "The VM test checks the text at the announcement seam, not speech. Non-inferable backstop (reason: insufficient_spec)"
  - test: "The tool in the Release bundle: install it with the README line, run transom save-view 4, transom foo; echo $?, then quit Transom and run transom view 4; echo $?"
    expected: "\"Saved view 4\" on screen; the unknown-command line and 64; \"transom: Transom is not running\" and 2"
    why_human: "The VM check runs the Debug bundle. The Release bundle's signing was inspected, but its tool has run only with help"
  - test: "Going to a view on a real second display, and a Space switch that fails (see behavior_unverified_items)"
    expected: "As in behavior_unverified_items"
    why_human: "The VM has one display, and nothing forces a failed switch"
  - test: "Fixes the fixer flagged for real apps: an app that opens many windows slowly during a relaunch (WR-04, 60 s cap); an app relaunched during the quit lag (WR-05); Float on a re-matched window (WR-10)"
    expected: "60 s suits slow apps; the new window still fills its tile; Float returns the window to its pre-dock frame"
    why_human: "They pass engine tests, but whether the behaviour is right on real apps can't be read from them"
---

# Phase 8: Saved Views, URLs & Persistence Verification Report

**Phase Goal:** As a power user, I want to save views to hotkeys and run Transom from transom:// URLs, so that my layouts and automations survive restarts.
**Mode:** mvp (user story form, valid per `/^As a .+, I want to .+, so that .+\.$/`)
**Verified:** 2026-11-04T03:12:29Z, at HEAD `ea14775`
**Status:** gaps_found. One gap: after a Transom restart, a tile on a hidden Space closes at once when its app quits. Nearly everything else is built, wired and tested; the live items below still need a human.
**Re-verification:** No, initial verification

## User Flow Coverage

| # | Step of the user story | Expected | Evidence in codebase | Status |
|---|---|---|---|---|
| 1 | Save the current view to a slot | ⇧⌥{n}, URL or CLI stores the desk and the window identities, then schedules a save | `Hotkeys.swift:151` table → `Navigator.camera` (`Navigator.swift:191`) → `Arranger+Views.swift:7` `saveView`, `.save(.debounced)` | ✓ VERIFIED (engine, VM dispatch); real chord: human |
| 2 | Return to it, also from another Space | Switch first, then zoom to the smallest node holding the saved windows | `ArrangeController.dispatch` → `viewSwitch` → `switchSpace` → `decide(afterSwitch:)` → `goView` → `zoomTo` | ✓ VERIFIED (VM at HEAD); second display and failed switch: human |
| 3 | The view survives layout changes and restarts | Identities, remapped on rekeys, matches and fills; `views` in layout.json | `remapViews` (`Arranger.swift:721-722, 961`, `Arranger+Placeholders.swift`); `LayoutFile.views`; `SpaceRekey.table(views:)` | ✓ VERIFIED (VM at HEAD, `aViewSurvivesASplitAMoveAndARelaunch`) |
| 4 | Run Transom from `transom://` URLs | Strict allow-list, one limiter per slot, same commands | `TransomURL.parse` → `CommandGate` → `dispatch(from: .url)` | ✓ VERIFIED (logic); live view URLs: human |
| 5 | Run the same commands from the bundled `transom` tool | Non-zero exits with messages | `transom-cli` → CFMessagePort → `CLIListener` → `CommandGate` → `answerCLI` | ✓ VERIFIED (VM on the built bundle) |
| 6 | Layouts survive restarts: Transom relaunch | Each window back in its tile; waiters leave a placeholder that expires | `LayoutRestore.reattach`, `HintMatcher`, `holdAtLaunch`, `expirePlaceholders` | ✓ VERIFIED (VM at HEAD) |
| 7 | Layouts survive restarts: app relaunch while Transom runs | Docked tiles held, then filled | `holdForQuit`, `fillPlaceholders`, `World.adopt` | ✗ PARTIAL: tracked windows work (VM, fixture only). A dormant tile on a hidden Space closes at once (see Gaps). Real ⌘Q: human |
| 8 | Layouts survive restarts: Mac reboot | As step 6, with a boot guard | `BootSession.changed` → `.restore(bootChanged:)` → `LayoutRestore.retire` | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED: engine tests only |

The `[outcome]` clause, "my layouts and automations survive restarts", holds for automations and for a Transom relaunch. For a reboot it is engine-tested only. For step 7 it has one real hole.

## Goal Achievement

### Observable Truths

Live evidence named "VM at HEAD" is from this verifier's own runs at `ea14775` (see Behavioral Spot-Checks).

**Roadmap contract**

| # | Truth | Status | Evidence |
|---|---|---|---|
| SC1 | Save to slots 1-9, return with a hotkey, still right after layout changes and a Transom restart | ✓ VERIFIED (chord: human) | `ArrangerViewsTests` (26 tests); VM at HEAD `aViewSurvivesASplitAMoveAndARelaunch`. The test requires a new common node after the split and move, then a fresh controller on the same store |
| SC2 | `open transom://…` etc. run commands; unknown ones rejected with no side effect | ✓ VERIFIED (live view URLs: human) | `TransomURLTests` (`theViewCommandsParse`, `malformedViewURLsAreRejected`, `eachSlotIsLimitedSeparately`), `CLIListenerTests.urlsAndTheCLIShareALimiter`. URL delivery proven live in 07-UAT |
| SC3 | After a Transom relaunch or a reboot, layouts come back re-matched; non-returning windows leave an expiring placeholder | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Transom relaunch half VERIFIED: VM at HEAD `aRelaunchedAppGetsItsTilesBackAfterATransomRelaunch`. Reboot half: engine only (`afterABootChange…`, `aStoredSetsHiddenTileWaitsAndFillsWhenItsSpaceShows`) |
| SC4 | The bundled tool runs every URL command and exits non-zero with a message | ✓ VERIFIED | `.build/0807-t1-vm.log`, 15 checks on the signed bundle through a symlink. `git log 610d718..HEAD` shows no change to the tool, gate, listener or parser, and only a comment in `ArrangeController`. `CLICommandLine` accepts the same table the URL parser uses, and each command has a help line (`CLICopyTests:58`). The VM ran `zoom-out`, `step-in`, `view` and `save-view`; the others rest on that shared table |

**08-01: saved views (13)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | ⇧⌥{n} stores desk + identities (pending target; home), no NodeID or rect | ✓ VERIFIED | `savingThenGoingBackZoomsToTheSavedWindows`, `savingDuringAMoveSavesItsTarget`; `SavedView` has neither field |
| 2 | ⌥{n} zooms to the LCA, joins history, no undo step | ✓ VERIFIED | `aLaterLayoutChangeStillTargets…`, `savingTouchesNoWindowOrUndoHistoryAndGoingPushesBackHistory` |
| 3 | Saved / Replaced, no clear command | ✓ VERIFIED | `savingOverAUsedSlotReplacesItWithoutConfirmation`; `grep clear-view Sources` is empty; `SavedViews` has no removal |
| 4 | Empty slot beeps + N16 | ✓ VERIFIED | `goingToAnEmptySlotBeepsWithN16` |
| 5 | All gone → N17 home, slot kept; display gone N18; empty view N19 | ✓ VERIFIED | `everySavedWindowClosed…`, `everySavedWindowGoneOnADisconnectedDisplay…`, `savingAViewWithNoWindows…` |
| 6 | Some gone → smallest node holding the rest, no notice | ✓ VERIFIED | `oneSavedWindowClosedGoesToTheSurvivorsLeaf…` |
| 7 | Moved windows → desk with most, ties to saved | ✓ VERIFIED | `theDeskHoldingMostSavedWindows…` |
| 8 | N13/14/15 brief class | ✓ VERIFIED | `NoticeQueueTests`, `NoticeCopyTests`; on-screen look is a human item |
| 9 | Toasts on the target / pointer display | ? UNCERTAIN | Notices carry the display, `displayUUID(of:)` returns it. Where it lands is a human item |
| 10 | Saved Views Shortcuts section after Zoom | ✓ VERIFIED | `ShortcutsModelTests`, `ShortcutsWindowController.swift:18-20,72` |
| 11 | 18 names are zoom names; chords released with zoom off | ✓ VERIFIED | `HotkeyTableTests`; `zoomNames` derives from `.camera` |
| 12 | Works by key position on a non-US layout (backstop) | ? UNCERTAIN (`insufficient_spec`) | `ViewChords.digits` are ANSI key codes; presence doesn't qualify. Human item |
| 13 | 15.0 / 15.1 chord rule by unit test (backstop) | ✓ VERIFIED | `HotkeyTableTests:129` parameterised faked versions. Never run on 15.0 itself, which the truth doesn't ask |

**08-02: re-matching on relaunch (5)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Returning windows matched by persisted hints at ≥ 40 into their own tiles | ✓ VERIFIED | VM at HEAD; `HintMatcherTests.theScoringTable`, `eachSignalScoresItsWeight`. Weights locked |
| 2 | Ties match neither, log a line | ✓ VERIFIED | `aTwoWayTieMatchesNeither`, `aTieAtLaunchLeavesTheTilesWaitingAndTheWindowsFloating`, `Arranger.matchLog` |
| 3 | Schema 3, 0600, titles refreshed, private in logs | ✓ VERIFIED | `titlesAreWrittenAndTheFileIsOwnerOnly`, `refreshingTitles` in `snapshot`; no log call interpolates `titleHint`; `WindowRef.description` omits titles |
| 4 | Schema 2 / 1 load; newer untouched | ✓ VERIFIED | `aSchema2FileLoads…`, `aSchema1FileLoadsMigrated…`, `aNewerFileIsKeptUntouched…` |
| 5 | Boot change: no identity re-attach | ✓ VERIFIED | Now via `LayoutRestore.retire` (WR-01): `ArrangerRestoreTests:158-266`. Shell wiring `ArrangeController.swift:217`. Real reboot: human |

**08-03: persistence and going across Spaces (11)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Views in layout.json, saved debounced, schema 2 gives none | ✓ VERIFIED | `savingAViewSchedulesASave` (CR-01), `savedViewsRoundTripSortedBySlot` |
| 2 | Survives splits, moves, rekeys, re-match | ✓ VERIFIED | `aWindowRekeyRewrites…`, `aRelaunchMatchRewrites…`, `aSavedViewFollowsTheFilledPlaceholder`, VM at HEAD |
| 3 | Desk follows its Space via the UUID table | ✓ VERIFIED | `SpaceRekeyTests.theTableListsTheSpacesOfSavedViews`, `aViewsDeskIsRekeyedWithTheSameMapping` |
| 4 | Another Space: switch first; refuse after 1 s | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Success path VM at HEAD. Refusal path has code (`switchSpace`), no test |
| 5 | Another display: camera moves there, pointer stays, focus inside | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `goingZoomsTheDestinationDisplayNotThePointers`, `goingFocusesTheMostRecent…`. VM has one display |
| 6 | macOS's transition, then the move; no spinner | ✓ VERIFIED | `aViewOnAnotherSpaceSwitchesFirst` asserts Space, then the camera settles |
| 7 | Joined VoiceOver line | ? UNCERTAIN | Seam proven: VM asserts one line with prefix "View 4. Showing". Speech: human |
| 8 | Saved views Debug line | ✓ VERIFIED | `ViewCopyTests`, `StatusItemController.swift:386` |
| 9 | Survives split, move, relaunch (backstop) | ✓ VERIFIED | VM at HEAD; also `.build/0803-t3-vm.log`, `0805-vm.log`, `0807-ViewsIntegrationTests.log` |
| 10 | Desktop 2 reached from Desktop 1 (backstop) | ✓ VERIFIED | Same logs |
| 11 | VoiceOver reads it once (backstop) | ? UNCERTAIN (`insufficient_spec`) | Human item |

**08-04: placeholder lifecycle (10)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | App quit: **each** docked window keeps its tile | ✗ FAILED (partial) | Tracked windows: `quitThenRelaunchRefillsBothTiles`, `aQuitTileOnAHiddenSpaceWaitsUntilItsSpaceShows`, VM. Dormant docked windows: `Arranger.swift:1020` closes the tile, and `aDormantWindowIsPrunedWhenItsAppTerminates` passes and pins it. Real ⌘Q also open (WR-06) |
| 2 | Relaunch fills via the same matcher; views follow | ✓ VERIFIED (coincidental-reliance) | VM at HEAD `quitAndRelaunchRefillsBothTiles`, order `["appTerminated", "windowDestroyed 143", "windowDestroyed 144"]` |
| 3 | Expiry: 30 s, 10 s sliding, 5 min, no undo step | ✓ VERIFIED | `aQuitExpiresThirtySecondsLater…`, `aLaunchSwitchesToTenSeconds…`, `aSavedWindowWhoseAppNeverOpens…`, `newWindowsSlide…AtMostAMinute` (WR-04 caps the slide at 60 s) |
| 4 | ⌘W closes at once | ✓ VERIFIED | `closingADockedWindowWhoseAppKeepsRunningClosesItsTileAtOnce` |
| 5 | Launch placeholders, floaters to expiry, ties | ✓ VERIFIED | `aDockedSavedWindowStillUnattachedHoldsItsTile`, `aFloatingSavedWindowIsKeptUntilExpiryWithoutATile` |
| 6 | Inventories never close one; deadlines on the wake clock | ✓ VERIFIED | `anInventoryNeverClosesAPlaceholder`; `nextWake` has `earliestPlaceholderDeadline`. By CR-02 a hidden one is off the clock until shown; on a Space that no longer exists it waits unseen (`shortcut:`) |
| 7 | Filled: written to tile, no undo step | ✓ VERIFIED | `quitThenRelaunch…`, `aMatchWhilePausedIsWrittenAtResume`, `WorldAdoptTests` (8) |
| 8 | Tab members | ✓ VERIFIED | `aHiddenMemberMatchedBeforeExpiry…`, `aHiddenMemberUnmatchedAtExpiryIsDropped`, `aGroupWhoseMembersAllWaitKeepsItsLeaf` |
| 9 | Tie: tile waits, windows float | ✓ VERIFIED | `aTieAtRelaunchFillsNothingAndTheWindowsFloat` |
| 10 | Fixture quit and relaunch (backstop) | ✓ VERIFIED | VM at HEAD |

**08-05: URLs and the tool (10)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | View URLs; every other form rejected, unlogged | ✓ VERIFIED | `malformedViewURLsAreRejected`; byte compare in `TransomURL.slot(digit:)`; "rejected a URL" has no contents |
| 2 | Per-slot limit shared by URL and CLI | ✓ VERIFIED | `eachSlotIsLimitedSeparately`, `urlsAndTheCLIShareALimiter`; one `CommandGate` (`TransomMacApp.swift:105`) |
| 3 | `transom <command>` forms, same parser, silent exit 0 | ✓ VERIFIED | `aCommandCrossesThePortAndExitsZeroSilently`; VM `save-view 4`, `view 4` |
| 4 | Not running: exit 2, never launches | ✓ VERIFIED | `noListenerExitsTwoAndSaysSo`; VM before launch and after quit; no `NSWorkspace`, `LSOpen` or `Process(` in main.swift |
| 5 | Usage and refusal messages, exit codes | ✓ VERIFIED | `CLICommandLineTests`, `CLIProtocolTests`, VM |
| 6 | Waits 2 s, then "didn't answer" | ✓ VERIFIED (logic) | `CLIProtocol.timeout` passed as both timeouts; statuses −1..−5 map to the message (`CLIProtocolTests:48`). No test hangs a listener |
| 7 | Empty slot via CLI | ✓ VERIFIED | `anEmptySlotRepliesItsToastText`; VM `view 7` |
| 8 | Rejected URL does nothing | ✓ VERIFIED | `AppDelegate.application(_:open:)`, `badRequestsAreRejected` |
| 9 | Help text, ≤ 72 cols, one line per command | ✓ VERIFIED | `CLICopyTests`; `.build/debug/transom-cli help` here: exit 0, 69 columns at most, ASCII |
| 10 | Release bundle carries the signed tool; Debug talks to Debug | ? UNCERTAIN | Debug proved (A3, VM). Release inspected: `Contents/Helpers/transom`, hardened runtime, timestamp, team S2K7P43927, x86_64 and arm64. Its tool never ran against an app, and the bundle predates the fixes |

**08-06: placeholder drawing (11)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Drawn at its rect with the recipe | ? UNCERTAIN | Rect within 2 pt: VM. Colours, dash, icon, capsule: human |
| 2 | Click-through, non-activating, behind real windows | ✓ VERIFIED | `aPlaceholderIsClickThroughAndBehindRealWindows` (see the first-run note in Behavioral Spot-Checks) |
| 3 | Sibling view, no hover ring or double-click | ✓ VERIFIED | `PlaceholderView` in `PlaceholderPanels.swift` has no mouse handling and hosts `TileLayer` |
| 4 | 120 ms fades, no spinner | ? UNCERTAIN | 0.12 in code; no test measures it |
| 5 | Filled: fades after the write | ? UNCERTAIN | Next list omits it (`aFilledPlaceholderLeavesTheNextList…`); the fade is visual |
| 6 | App not installed fallback | ✓ VERIFIED | `ViewCopyTests`; `PlaceholderLook` nil path |
| 7 | Long app name, clearance rule | ? UNCERTAIN | Truncation in `ViewCopy`; clearance and the kept accessibility label are visual or AX, and untested |
| 8 | Waiting Debug line between the others | ✓ VERIFIED | `StatusItemController.swift:386-388` |
| 9 | Stage and overview; panel out on camera move and hidden Space | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `aCameraMoveCarriesPlaceholdersApartFromTiles`, `aPlaceholderIsDrawnButNeverCountedOrSelected`. `spaceChanged` is untested |
| 10 | Untracked refs never fault (Pitfall 8) | ✓ VERIFIED | Shown-desk section of `ArrangerPlaceholderTests` |
| 11 | Click reaches Finder; a window opened over it stays above (backstop) | ✓ VERIFIED | Same test; two 0807 logs and `.build/0808-verify-vm-Rematch-2.log` |

**08-07: installed CLI and README (5)**

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Installed bundle through a symlink gives every exit code | ✓ VERIFIED | `.build/0807-t1-vm.log`, 15 PASS lines |
| 2 | Plain-SSH reach measured | ✓ VERIFIED | `A2 plain-ssh exit=0`, guest 15.7.7 |
| 3 | README documents every surface | ✓ VERIFIED | Lines 55-57, 89-90, 97-102, 263, 293 |
| 4 | Real reboot (backstop) | ? UNCERTAIN (`insufficient_spec`) | Human item |
| 5 | CLI exit codes end to end in the VM (backstop) | ✓ VERIFIED | As 1 |

**CONTEXT decisions added after the plans**

| # | Truth | Status | Evidence |
|---|---|---|---|
| D-10a | A lone window with a changed title matches only near its old frame | ✓ VERIFIED | `HintMatcher.score` (`noTitleAgainst`), table rows at `HintMatcherTests:61-73`, `aLoneTileIsNotTakenAgainstTheTitleEvidence` |
| D-12b | Hidden-desk tiles wait on every path | ✗ FAILED (partial) | Launch, tracked quit and stored-arrangement paths wait (`aQuitTileOnAHiddenSpace…`, `aStoredSetsHiddenTile…`). The dormant quit path doesn't (same root cause as 08-04 truth 1) |

**Score:** 55/71 verified; 4 present but behavior-unverified; 10 uncertain, routed to a human; 2 failed, from one root cause.

### Required Artifacts

`gsd-tools verify.artifacts`: 08-01 6/6, 08-02 6/6, 08-03 4/4, 08-04 3/3, 08-05 7/7, 08-06 3/3, 08-07 2/2.

| Artifact | Status | Details |
|---|---|---|
| `Sources/TransomEngine/Arranger+Views.swift`, `SavedViews.swift` | ✓ VERIFIED | Called from `Navigator.camera`; views round-trip in `LayoutFile` |
| `Sources/TransomEngine/HintMatcher.swift`, `LayoutRestore.swift` | ✓ VERIFIED | Called at launch, on a stored arrangement and on fill |
| `Sources/TransomEngine/Arranger+Placeholders.swift` | ✓ VERIFIED | Hooks in `Arranger.swift` events, tick and `nextWake` |
| `Sources/TransomModel/World.swift` (`adopt`, `refreshingTitles`) | ✓ VERIFIED | Fill and snapshot paths |
| `Sources/TransomMac/Overlay/PlaceholderPanels.swift` | ✓ VERIFIED | Owned by `ArrangeController` (`:77`, `:827`) |
| `Sources/TransomMac/CLIListener.swift`, `CommandGate.swift`, `BootSession.swift` | ✓ VERIFIED | Wired in `TransomMacApp.swift:105-107`, `ArrangeController.swift:217,1178` |
| `Sources/transom-cli/main.swift`, `xcode/project.yml` `transom-tool` | ✓ VERIFIED | Built into both bundles at `Contents/Helpers/transom` |
| `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift`, `ViewsIntegrationTests.swift` | ✓ VERIFIED | Skip on the host, pass in the VM |

### Key Link Verification

`verify.key-links` reported most as "Source file not found" because the plans put a symbol after the path in `from:` (a format problem, as in Phase 7). Each was checked by hand:

| From | To | Via | Status |
|---|---|---|---|
| `Hotkeys.entries` | `Navigator.camera` | `.camera(.view/.saveView)` through `Hotkeys.register` → `dispatch` | ✓ WIRED |
| `goView` | `zoomTo` | `Arranger+Views.swift`, last line | ✓ WIRED |
| `Notice.isBrief` | `NoticeQueue.post` | `briefDuration`, drop behind crash | ✓ WIRED |
| `Arranger.snapshot` | `LayoutStore.save` | `refreshingTitles` → `write` | ✓ WIRED |
| First inventory | `LayoutRestore.reattach` | `savedFrames`, `shownDesks` | ✓ WIRED |
| `LayoutRestore` | `World.rekey` | Through throwaway identities | ✓ WIRED |
| `snapshot` / `.restore` | `write` / load | `views: snapshot.views`; `.restore(…, views:)` | ✓ WIRED |
| `.windowRekeyed`, matches | `remapViews` | `Arranger.swift:721-722, 961` | ✓ WIRED |
| go-view flow | `SpaceSwitcher.switchTo` | `switchSpace` | ✓ WIRED |
| `.appTerminated` / `.windowDestroyed` | `holdForQuit` | `quitting` | ⚠️ PARTIAL: `.windowDestroyed` only; the dormant branch at `:1020` closes |
| Fill | `World.adopt` | `fillPlaceholders` | ✓ WIRED |
| `.tick` | `LifecycleSync` | `expirePlaceholders` | ✓ WIRED |
| `transom-cli` | `CLIListener` | `CFMessagePortSendRequest` on `<bundle ID>.cli` | ✓ WIRED |
| `CLIListener`, `AppDelegate` | `CommandGate` | One instance | ✓ WIRED |
| `CommandGate` | `decide(_:from: .cli)` | `answerCLI`; the `decide:` closure in `TransomMacApp.swift` (the tool's automatic check looked for `.cli` in the wrong file) | ✓ WIRED |
| `project.yml` | `Contents/Helpers/transom` | `transom-tool`, `subpath: Contents/Helpers` | ✓ WIRED |
| `planShown` | `run(_:)` | `.placeholders` (`Arranger.swift:2160`, `ArrangeController.swift:826`) | ✓ WIRED |
| `ArrangeController` | `PlaceholderPanels.show` | `:827` | ✓ WIRED |
| `CameraMove` | `StagePanel` | `move.placeholders` via `ZoomController` | ✓ WIRED |
| `vm-cli-check.sh` | Helper | Symlink in the guest | ✓ WIRED |
| README | Install line | `ln -sf` at line 102 | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| View toasts | `slot`, `displayUUID` | The command, the display routed to | Yes | ✓ FLOWING |
| Debug "Saved views" | `savedViewSlots` | `camera.savedViews` | Yes | ✓ FLOWING |
| Debug "Waiting for windows" | `placeholderCount` | `placeholders.table` + World | Yes | ✓ FLOWING |
| Placeholder tile | `PlaceholderTile.frame` | Plan rects in `planShown` | Yes | ✓ FLOWING |
| Placeholder label, icon | `PlaceholderLook` | `NSRunningApplication` / `NSWorkspace` | Yes | ✓ FLOWING |
| layout.json titles | `titleHint` | `windows[…].window.titleHint` at snapshot, `refreshingTitles` on change | Yes | ✓ FLOWING |
| CLI reply | Reply text | `decide` → `cliReply` | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full host suite, once, at HEAD | `env -u TRANSOM_LIVE swift test` → `.build/0808-verify-swift-test.log` | 226 + 432 + 100 + 1095 = **1,853** Swift Testing tests, no ✘, exit 0. Live suites skipped on the host. `FreezeTestTests.itResumesByItself` passed this run. The last logged run (`0807-swift-test.log`) predated the review fixes, so a new run was needed | ✓ PASS |
| Engine and model import no AppKit | `scripts/check-no-appkit.sh` | `no-appkit: OK (62 files)` | ✓ PASS |
| The gap, one named test | `swift test --skip-build --filter ArrangerMultiDeskRestoreTests/aDormantWindowIsPrunedWhenItsAppTerminates` | Passes, which confirms the tile closes | ✓ reproduces the gap |
| VM at HEAD: Rematch, run 1 (right after the VM booted, guest load about 20) | `scripts/vm-live-test.sh RematchIntegrationTests` → `.build/0808-verify-vm-Rematch.log` | 2 of 3. `aPlaceholderIsClickThrough…` failed at line 246: the click reached the window behind the panel, then "did not reach Finder: nil" | ✗ FAIL |
| VM at HEAD: Rematch, run 2, same boot | → `.build/0808-verify-vm-Rematch-2.log` | 3 of 3. Order `["appTerminated", "windowDestroyed 143", "windowDestroyed 144"]` | ✓ PASS |
| VM at HEAD: Views | → `.build/0808-verify-vm-ViewsIntegrationTests.log` | 2 of 2 | ✓ PASS |
| VM at HEAD: QuitRestore (regression) | → `.build/0808-verify-vm-QuitRestoreIntegrationTests.log` | 3 of 3 | ✓ PASS |
| VM at HEAD: Recovery (regression) | → `.build/0808-verify-vm-RecoveryIntegrationTests.log` | 2 of 2 | ✓ PASS |
| VM at HEAD: TabGroup (Phase 7 regression) | → `.build/0808-verify-vm-TabGroupIntegrationTests.log` | 7 of 7 | ✓ PASS |
| Tool on the bundle, reported by the fixer | 08-REVIEW-FIX | 15 checks, no log kept. Earlier logged run: `.build/0807-t1-vm.log`, 15 PASS, A2 exit 0 | ? reported; logged run stands, chain unchanged |
| Help on the built tools | `transom-cli help`, bundled `transom help` | Exit 0, 69 columns at most, ASCII. Help only on the host | ✓ PASS |
| Helper signing | `codesign -dv`, `lipo -archs` | Debug: runtime, team, arm64. Release: runtime, timestamp, team, x86_64 and arm64 | ✓ PASS |
| Release script | `bash -n` | OK; the full release build was not run | ? syntax only |

Why the VM ran although logs existed: no log at HEAD was on disk, because the fixer's runs went with its worktree and QuitRestore, Recovery (one fixer run) and TabGroup had no post-fix log. I ran one suite at a time. Transom wasn't running in the guest, so nothing was quit; its layout.json date was unchanged; no fixture or `~/transomcli` remained. The suite that visits Desktop 2 returns to Desktop 1 as its last step and passed, and I didn't read the Space directly afterwards. `pane-test` was started by this run and is stopped again.

The first-run failure repeats a pattern: `.build/0807-RematchIntegrationTests.log` also failed on a fresh boot, at another line, which 610d718 attributed to the click point. Here the Finder half failed once under fresh-boot load, then passed. I didn't establish the cause. Treat this test's Finder half as load-sensitive on a fresh boot.

Nothing live ran on the host: no chords, taps, panels, URL opens, AX writes or window-opening code. The user's real layout.json and defaults were not touched.

### Probe Execution

No `scripts/*/tests/probe-*.sh` declared or present. Step 7c: not applicable.

### Requirements Coverage

| Requirement | Source plans | Description | Status | Evidence |
|---|---|---|---|---|
| VIEW-01 | 08-01, 08-03 | Save to slots 1-9, return with a hotkey | ✓ SATISFIED (logic + VM) / ? real chords | SC1 |
| VIEW-02 | 08-03 | Survive layout changes and restarts | ✓ SATISFIED (VM) / ? reboot | 08-03 truths 1-3, 9 |
| VIEW-03 | 08-05, 08-07 | Commands from URLs | ✓ SATISFIED (logic) / ? live view URLs | SC2 |
| VIEW-04 | 08-02, 08-04, 08-06, 08-07 | Layouts persist across reboots and relaunches, re-matched | ✗ PARTIAL | Transom and tracked-app relaunch proven in the VM; the dormant tile gap; reboot and real ⌘Q open |
| VIEW-05 | 08-05, 08-07 | Bundled CLI, non-zero on errors | ✓ SATISFIED (VM) / ? Release bundle | SC4 |

All five IDs are claimed by plans and none is orphaned. REQUIREMENTS.md marks all five Complete; VIEW-04 is ahead of this evidence.

### Decision Coverage

The gate reports 18 of 20 honored, with D-10a and D-12b not found in shipped artifacts. It is a substring check and doesn't change status. Reading the code: D-10a is honored, and D-12b is honored except on the dormant quit path (see Gaps).

```json
{"honored": 18, "total": 20, "not_honored": ["D-10a", "D-12b"]}
```

### Test Quality Audit

| Test file | Linked req | Active | Skipped | Circular | Assertion level | Verdict |
|---|---|---|---|---|---|---|
| `ArrangerViewsTests` | VIEW-01, 02 | 26 | 0 | no | Behavioral | ✓ |
| `ArrangerPlaceholderTests` | VIEW-04 | 53 @Test | 0 | no | Behavioral | ✓ |
| `HintMatcherTests` | VIEW-04 | 6 @Test + table | 0 | no: hand-written rows, weights by name | Value | ✓ |
| `WorldAdoptTests` | VIEW-04 | 8 | 0 | no | Value | ✓ |
| `CLIListenerTests` | VIEW-03, 05 | 16 | 0 | no: spawns the built tool on a private port | Behavioral | ✓ |
| `ViewsIntegrationTests` | VIEW-01, 02 | 2 | host only | no | Behavioral | ✓ |
| `RematchIntegrationTests` | VIEW-04 | 3 | host only | no | Behavioral | ✓ with the first-run note |
| `ArrangerMultiDeskRestoreTests.aDormantWindowIsPruned…` | none | 1 | 0 | no | Value | ⚠️ Pins behaviour D-12a and D-12b rule out. It predates them |

**Disabled tests on requirements:** 0. **Circular patterns detected:** 0. **Insufficient assertions:** 0. Host skips are the `TRANSOM_LIVE` gate, by design.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (75 phase source, test and script files, plus README) | — | TBD / FIXME / XXX / TODO / HACK | none found | — |
| `Sources/TransomEngine/Arranger.swift` | 1020 | `closeDormant { $0.pid == pid }` on app quit | 🛑 Blocker | The gap. A hidden tile is lost, against D-12a, D-12b and README line 57 |
| `Sources/TransomEngine/Arranger+Placeholders.swift` | 7 | `shortcut:` a placeholder on a Space that no longer exists waits for good | ⚠️ Warning | Unseen and harmless on screen, but stays in layout.json; "no permanent hole" holds only for what shows |
| `.planning/.../08-REVIEW-FIX.md` Open risks | — | A stored arrangement closes unmatched windows on shown desks at once | ⚠️ Warning | After a reboot this can include a tile whose app hasn't opened yet. D-12b covers hidden desks only, and 08-04 chose this. Check in the reboot item |
| UI-SPEC logging table | — | No `match` category; match, placeholder and engine view lines log under `arrange` | ℹ️ Info | Lines exist; `log show` needs a different filter than the spec says |
| `Sources/TransomEngine/CLIProtocol.swift` | 33 | IN-01 open: `exitCode(sendStatus:)` ignores status | ℹ️ Info | App quitting mid-call says "didn't answer" (1), not "not running" (2) |
| `Sources/TransomMac/LayoutStore.swift` | 75-76 | IN-02 open: 0600 applied after publish | ℹ️ Info | Brief default mode on a new file; `~/Library` is normally private |
| `Sources/TransomEngine/Arranger+Placeholders.swift` | 11 | IN-03 open: `origin` barely read; launch placeholders log no "shown" line | ℹ️ Info | UI-SPEC table partly unmet |
| `Sources/transom-cli/main.swift` | 28 | IN-04 open: `TRANSOM_CLI_PORT` in release | ℹ️ Info | No new access; undocumented in the README |
| `Sources/TransomEngine/HintMatcher.swift` | 27 | `shortcut:` a window that never gets a title and opens elsewhere loses a lone tile | ℹ️ Info | Follows D-10a |
| `Sources/TransomMac/ArrangeController.swift` | 726 | `shortcut:` a second view during a switch posts its own chords | ℹ️ Info | Rapid presses may race |
| Bookkeeping | — | `08-VALIDATION.md` is `status: draft`, `nyquist_compliant: false`; UI-SPEC ends "Approval: pending" with `status: approved`; ROADMAP Phase 8 unchecked | ℹ️ Info | Tidy after the UAT |

### Human Verification Required

These are the frontmatter items, in order. They don't replace the gap below.

1. **Rebuild first.** Debug and Release bundles predate every review fix.
2. **Real chords**, a non-US layout, and toasts on the right display.
3. **`transom://view/N` and `save-view/N`** from a shell and a launcher. Added by this verifier: no run opened a view URL.
4. **How a placeholder looks**, and its fades.
5. **Space changes with a placeholder shown.**
6. **⌘Q of a real app with docked windows** (WR-06, A1). The fixture exits with `exit(0)`.
7. **A real Mac reboot** with a tile on a second Space, including a stored arrangement (CR-02, CR-03, D-12b).
8. **Going to a view on another Space when macOS moves focus outside it** (08-03).
9. **VoiceOver's joined line.**
10. **The tool in the Release bundle.**
11. **A second display, and a failed Space switch.** Added by this verifier: neither has a live test.
12. **WR-04, WR-05 and WR-10 on real apps**, as the fixer asked.

### Gaps Summary

One gap blocks the status, with one root cause behind two truths.

**A dormant docked tile closes when its app quits.** After Transom restarts, windows on Spaces not yet visited are kept by identity but aren't tracked (dormant). If the app of such a window quits, `Arranger.swift:1020` closes the tile through the close path, with no placeholder, no 30 s wait and no fill on relaunch. The window then floats when it returns, and any saved view loses it at the next save.

This contradicts 08-04's truth ("each of its docked windows keeps its tile"), D-12a, D-12b ("wait on every path") and README line 57 ("A tile on a Desktop you aren't on waits until you go there"). The case with the same tile *tracked* does wait (`aQuitTileOnAHiddenSpaceWaitsUntilItsSpaceShows`), so the behaviour depends on whether you visited that Desktop since Transom started, which a user can't see.

08-04's SUMMARY records this as a decision ("still closes on its app's quit, as its existing test requires"), made before D-12b existed. The D-12b fix covered only stored arrangements. Later phases don't cover it (Phase 9 is Settings, onboarding and shipping), so nothing is deferred.

**This might be accepted rather than fixed.** If you want the current behaviour, because this is rare and the window is reachable anyway, add this to the frontmatter:

```yaml
overrides:
  - must_have: "When an app quits while Transom runs, each of its docked windows keeps its tile as a placeholder instead of closing it (08-04, D-12a); tiles for windows on Spaces not being shown wait on every path and do not expire while their desk is hidden (D-12b)"
    reason: "{why a dormant tile on a hidden Space may close when its app quits}"
    accepted_by: "{name}"
    accepted_at: "{ISO timestamp}"
```

README line 57 should then say so.

Other truths aren't failures: 4 are present and wired without a test of their behaviour, and 10 can only be judged by a person. If the gap is closed or overridden, the status becomes `human_needed`, not `passed`.

---

_Verified: 2026-11-04T03:12:29Z_
_Verifier: Claude (gsd-verifier)_
