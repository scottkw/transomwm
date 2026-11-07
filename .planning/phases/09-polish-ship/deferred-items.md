# Deferred items, phase 09

## 09-24: carried macOS 27.2 live failures (D-17)

### Views: `aViewOnAnotherSpaceSwitchesFirst`, fixed (test setup)

- **Failure:** on macOS 27.2 it stopped at line 193, "the Arranger never saw Desktop 1" (`.build/09-24-views-vm27-base.log`), as it has since 08. 15.7 passed.
- **Cause, measured:** an SSH-run test process on 27.2 never gets `NSWorkspace.activeSpaceDidChangeNotification`. A temporary probe (not committed) switched Spaces with the product's `SpaceSwitcher`: SkyLight showed every switch, and the probe heard 0 notifications on 27.2 and 2 per round trip on 15.7 (`.build/09-24-probe-vm27.log`, `.build/09-24-probe2-vm27.log`, `.build/09-24-probe-vm15.log`). Running the helper with `sudo launchctl asuser`, calling `NSApp.finishLaunching()`, and setting the `.accessory` policy changed nothing on 27.2. The guest's `Transom Debug.app`, launched in the GUI session, logged `space 1 → 4` and `space 4 → 1` for each of the probe's six switches (`.build/09-24-probe-app-vm27.log`). The product hears the switch; the SSH-run test process does not, so the Arranger in the test never learns of it.
- **Change:** `SpaceChangeRelay` in `ViewsIntegrationTests.swift`. While the test runs, it posts the notification on the test process's workspace center for each SkyLight Space change the system has not announced within 150 ms. On 15.7 the system's notifications balance the count, so it posts nothing. The product's switch-first path, its 500 ms wait for the Arranger and the camera are unchanged and still under test.
- **Result:** passed on macOS 27.2 on the first run (`.build/09-24-views-vm27.log`) and on macOS 15.7 (`.build/09-24-views-vm15.log`).
- **Follow-up for 09-25:** `OverviewSpaceSwitchIntegrationTests` and `TabStripSpaceIntegrationTests` fail on 27.2 in the same way ("the Arranger never sees the second Space"). The relay is the likely setup fix there too.

### Rematch: `aPlaceholderIsClickThroughAndBehindRealWindows`, fixed (test setup)

- **Failure:** on macOS 27.2 the second click did not reach Finder: "did not reach Finder: nil" at line 246 (`.build/09-24-rematch-vm27-base.log`). 15.7 passed.
- **First reading, wrong:** 08-UAT suspected NSWorkspace being stale over SSH, and after Views it looked like the same class. A run that read the frontmost app through Accessibility instead also got nil (`.build/09-24-rematch-vm27-diag.log`; that change was reverted). A probe then showed that a bare desktop click over SSH on 27.2 does make Finder frontmost, and NSWorkspace reports it (`.build/09-24-probe4-vm27.log`). The nil was the bundle-less fixture app, still frontmost.
- **Cause, measured:** a temporary copy of the test with diagnostics (`.build/09-24-probe5-vm27.log`) showed that when `close 1` replies on 27.2, the closed fixture window is still on screen under the click point. The second click landed on it, so the fixture stayed frontmost. Once the window had left the on-screen list, the click went through the placeholder panel to the desktop and Finder became frontmost. The panel was click-through both times.
- **Change:** after `close 1`, the test waits (up to 3 s, required) until that window is gone from the on-screen window list, then clicks. The comment names D-17.
- **Result:** passed on macOS 27.2 on its third run, the first with the fix (`.build/09-24-rematch-vm27.log`), and on macOS 15.7 (`.build/09-24-rematch-vm15.log`).

## 09-25: the other carried macOS 27.2 live failures (D-17, from 08.1.1-18)

### OverviewSpaceSwitch: three tests, fixed (test setup, the 09-24 Views cause)

- **Failure:** baseline on macOS 27.2 (`.build/09-25-oss-vm27-base.log`): `pickingAMiniTileOnAnotherSpaceSwitchesThereAndFocusesItsWindow` L114 and `theFirstVisitToASpaceNotYetReadCapturesItsWindows` L155 (`cached` false), `aPanelStrandedOnAnotherSpaceDoesNotHideTheNextOpen` L195 (the Arranger's `currentSpaceID` never became the second Space). The same three as 08.1.1-18.
- **Cause, measured:** all three hang off `AXWindowSystem`'s `activeSpaceDidChangeNotification` observer (the `.spaceChanged` event feeds the Arranger's `currentSpaceID` and the visit capture 1 s later). With `SpaceChangeRelay` counting, the system announced 0 of 8 Space changes to the SSH-run test process on 27.2 (`.build/09-25-oss-vm27.log`: "3 Space changes, 0 announced by the system, 3 posted" and so on) and every one on 15.7 (`.build/09-25-oss-vm15.log`: "4 announced, 0 posted"). Same harness gap as Views in 09-24.
- **Change:** `SpaceChangeRelay` moved from `ViewsIntegrationTests.swift` into `IntegrationSupport.swift` (now two suites use it) and prints its counts at `stop()`. The three tests start one after reading the desktops, with a D-17 comment.
- **Result:** 6/6 passed on macOS 27.2 on the first run with the fix (`.build/09-25-oss-vm27.log`) and on macOS 15.7 (`.build/09-25-oss-vm15.log`), where the relay posted nothing.

### Overview: `overviewOpensPerDisplayAndCloses` helper exit on 27.2, NOT fixed (cause unproven, deviation)

- **Failure:** on macOS 27.2 the swiftpm-testing-helper exits with status 0 during `overviewOpensPerDisplayAndCloses`, before any result line (`.build/09-25-overview-vm27-base.log`), as recorded in 08.1.1-18.
- **Measured:** a temporary diagnostic copy (step markers plus an `atexit` stack print, not committed; `.build/09-25-overview-vm27-diag.log`) reached every step through "escaped", so Esc closed the overview. The exit came afterwards, during the final 400 ms wait or the `frames()` read, and `exit` was called from `swift_task_asyncMainDrainQueue`: the helper's own top-level main run loop had returned. This matches the 06-08 mechanism (an AppKit stop landing on the helper's loop instead of a nested `dispatchAppKitEvents` run). The mouse stayed at (10, 758) throughout.
- **Tried, did not work:** keeping the main thread in the nested pump for the whole 400 ms fade after Esc, on the theory that the Esc keyUp or the key panel's order-out at the end of its fade triggered the stop. The helper still exited with no results (`.build/09-25-overview-vm27.log`). That was the third 27.2 run of the suite (the plan's limit), so the change was reverted and nothing was committed for this test.
- **Not known:** what stops the helper's loop after the close. It may be the `frames()` await, the `offerExplainerAfterOverview` task 370 ms after the close, or the test's end (fixture terminate or ArrangeController release). The next step is a probe with a marker after every await and a `CFRunLoopObserver` on the main loop's exit, in a fresh plan with its own run budget. No product cause is shown: the real app runs `NSApp.run`, which ignores such stops.
- **15.7:** run 1 failed at L46 ("opened" false, the first test taking 16 s right after boot; `.build/09-25-overview-vm15.log`). Run 2 passed 3/3 (`.build/09-25-overview-vm15-2.log`; one attempt before it lost rsync before any test ran, `.build/09-25-overview-vm15-2-rsyncdrop.log`). I read run 1 as a slow first open after boot, but it is only one sample.

### TabStripSpace: `theStripShowsOnlyOnItsGroupsSpace`, fixed (test setup, the 09-24 Views cause)

- **Failure:** baseline on macOS 27.2 at L61, "a strip stayed ordered in on the second desktop" (`.build/09-25-strip-vm27-base.log`).
- **Cause, measured:** the strip is ordered out by `tabStripPanels.spaceChanged`, which runs on `AXWindowSystem`'s `.spaceChanged` event, the same notification path. The relay counted "2 Space changes, 0 announced by the system, 2 posted" on 27.2 (`.build/09-25-strip-vm27.log`) and "2 announced, 0 posted" on 15.7 (`.build/09-25-strip-vm15.log`).
- **Change:** the test starts a `SpaceChangeRelay`, with a D-17 comment.
- **Result:** passed on macOS 27.2 on the first run with the fix and on macOS 15.7.

### TabGroup: `closeAndMinimizeCommandsActOnFixtureWindows` on 27.2, NOT fixed (product gap on macOS 27, deviation)

Resolved in 09-29 (D-23).

- **Failure:** on macOS 27.2 the close of window 0 is never confirmed: `closed` false and latency 3.03 s at L200-201 (`.build/09-25-tabgroup-vm27-base.log`). On 15.7 it confirms in 0.109 s (`.build/09-25-tabgroup-vm15.log`).
- **Measured:** two temporary probe copies of the test (not committed; `.build/09-25-tabgroup-vm27-diag.log`, `.build/09-25-tabgroup-vm27-diag2.log`) sampled both sources every 150 to 500 ms for up to 6 s after the 3 s wait. Before the press, AX listed both windows (43 not minimised, 56 minimised) and CG had 43 on screen. After the press, 43 left AX's window list (only the minimised 56 remained) and left the screen. But it **stayed in the full CG window list** for the whole 8.5 s: layer 0, alpha 1, unchanged bounds, and SkyLight still put it on Space 1. The tracker kept 43 `present`.
- **Cause:** the fixture keeps closed windows alive (`isReleasedWhenClosed = false`, a strong reference in `entries`). On 27.2 a closed but retained NSWindow keeps its window-server window, ordered out, in the CG list; 15.7 drops it. The product's two-source rule (`CloseRule`: AX gone AND CG absent, or CG present with a known-empty Space set) therefore never closes it: the decision is `recheck` (or `noChange` if the cached element still answers valid but unlisted; not measured), and both keep the old state. This also explains the Rematch finding in 09-24 (the window leaves the on-screen list, not the full list).
- **Why not a test-setup fix:** real AppKit and SwiftUI apps commonly keep closed windows (window controllers, `isReleasedWhenClosed = false`). On macOS 27 Transom would keep such a closed window tracked and tiled, and Close Group would stop on its 1 s confirmation. Making the fixture release its windows would hide that. Changing `CloseRule` (for example treating "AX gone, CG present but off screen" as closed) is a product decision outside this test-only plan; it needs care because minimised, hidden and other-Space windows are also off screen (those answer AX as valid).
- **Runs:** 27.2 used its three (base, diag, diag2). 15.7 once, unchanged.
- **Also seen on 15.7, out of scope:** `aTabDraggedOutWithNoWindowUnderPointerLeavesTheGroup` failed at L46 (`ids.count == 2`): the fixture's launch reported fewer than two windows in `SavedGroup.start`, before any product logic ran. It passed on 27.2 in the baseline. One sample; not investigated.

## 09-29: macOS 27 close of a window its app keeps alive (D-23), fixed (product)

- **Cause:** on macOS 27.2 a closed window its app retains stays in the full CG list, offscreen, on its Space, so `CloseRule` rechecked it forever (see the 09-25 TabGroup entry above).
- **Change:** a new `cgOrderedOut` input to `CloseRule.decide`: the CG entry is present and not `onScreen`, and the window's Spaces are known and include a Space some display shows now (`currentSpaceID`). `WindowTracker.decide` computes it per window from the CG entry, `context.windowSpaces` and `context.displays`. It counts only when AX answers -25202 (`invalidElement`), after the tab-member check; nil Spaces or no shown Space never count. No OS check.
- **Live facts** (the logged `closed window 0 facts:` line, read after the confirmation wait):
  - 27.2 (`.build/09-29-tabgroup-vm27.log`): `AXRole error -25202, in CG list true, onScreen Optional(false), spaces Optional(Set([1])), shown Spaces [1]`; close confirmed in 0.382 s (under `Arranger.closeConfirmation`, 1 s). Matches 09-25's measurement.
  - 15.7 (`.build/09-29-tabgroup-vm15.log`): `AXRole error -25202, in CG list true, onScreen Optional(false), spaces Optional(Set([])), shown Spaces [1]`; confirmed in 0.109 s, as in 09-25. Correction to 09-25's "15.7 drops it": on 15.7 the entry also stays in the CG list, but with an empty Space set, so the existing G-03-9 no-Space row closes it. The new row does not decide anything there (the empty set misses the shown Space).
- **Logs (all first runs, no reruns):**
  - `.build/09-29-red.log`: the two D-23 scenarios failed before the change; the three guards passed.
  - `.build/09-29-engine.log`: TransomEngineTests 1336 tests passed.
  - `.build/09-29-tabgroup-vm27.log`: TabGroupIntegrationTests 7/7 passed on 27.2.
  - `.build/09-29-tabgroup-vm15.log`: TabGroupIntegrationTests 7/7 passed on 15.7 (the 09-25 L46 launch flake did not recur).
  - `.build/09-29-close-vm27.log`, `.build/09-29-close-vm15.log`: CloseIntegrationTests passed on both.
  - `.build/09-29-tabs-vm27.log`, `.build/09-29-tabs-vm15.log`: TabsIntegrationTests passed on both.
  - `.build/09-29-full.log`: host gate, four passed "Test run with" lines; `scripts/check-no-appkit.sh` OK.
- **Not covered (not measured):**
  - (a) A whole native tab group its app closes and keeps alive on macOS 27. Its hidden members could linger in the CG list too, and `decide`'s remaining-members check cannot tell them from live hidden tabs by CG alone, so the group may stay tracked. Resolved in 09-30 (D-25).
  - (b) With the Spaces lookup off, a kept-alive closed window keeps rechecking, as before.
  - (c) A kept-alive closed window whose Space no display shows any more by the time Transom refreshes (Spaces switched first) keeps rechecking until that Space shows.

## 09-30: macOS 27 close of a whole native tab group its app keeps alive (D-25), fixed (product)

- **Cause:** a group whose app closes every tab and keeps them alive stays in the CG list. `CloseRule`'s tab-member row (`invalidElement` + in CG + known tab member) answered `.state(.absent)`, and `decide`'s remaining-members check kept the group while any member was in the CG list, so its tile stayed.
- **Measured facts** (fixture `close-group`, `TabsIntegrationTests.aNativeTabGroupItsAppClosesWholeAndKeepsAliveLeaves`; logs `.build/09-30-tabs-vm27-measure.log`, `.build/09-30-tabs-vm15-measure.log`):
  - 27.2 live, selected tab: `tab group facts: live id=67 ax=0 listed=true inCG=true onScreen=Optional(true) spaces=Optional(Set([1])) shown=[1]`
  - 27.2 closed+3s: `id=65 ax=-25202 listed=false inCG=true onScreen=Optional(false) spaces=Optional(Set([])) shown=[1]`, `id=66` the same, `id=67 ax=-25202 listed=false inCG=true onScreen=Optional(false) spaces=Optional(Set([1])) shown=[1]`; `tab group tracked: closed+3s windows=1 state=…absent tabCount=Optional(3)`. Matches the `KeptAliveShape` row "27.2: shown ordered out, hidden no Space".
  - 27.2 `cmd-w facts: next tab listed after 0 ms`.
  - 15.7 live, selected tab: `tab group facts: live id=73 ax=0 listed=true inCG=true onScreen=Optional(true) spaces=Optional(Set([1])) shown=[1]`
  - 15.7 closed+3s: `id=71`, `id=72` and `id=73` all `ax=-25202 listed=false inCG=true onScreen=Optional(false) spaces=Optional(Set([])) shown=[1]`; `windows=1`. Matches "15.7: all on no Space".
  - 15.7 `cmd-w facts: next tab listed after 0 ms`.
  - S5: 15.7 also kept the group before the fix; the D-25 test failed on both macOS lines.
  - 27.2 timing (first proof run): `closed+0 id=67 … onScreen=Optional(true)`. CG orders the shown tab out after AX reports it gone, so the first refresh after the close did not see the group closed, decided it absent and asked for no follow-up refresh (5 s sweep).
- **Change:** `WindowTracker.closingGroups` (`confirmClosedTabGroups`). A group looks closed when its shown tab answers -25202, no tab of it is listed in AXWindows, a member is still in the CG list, its Spaces at its last listing include a Space a display shows, the app is not hidden and AXWindows did not fail. With no tab on screen as well, the look starts a clock and is confirmed once it still holds `settleDelay` (250 ms) later. With a tab still on screen (27.2), the group is pending with no clock started. A pending group's decision is `.recheck` (no CloseRule, so `needsQuickRecheck` brings the next refresh). Once confirmed, the shown tab goes to `CloseRule` with `isKnownTabMember` false and closes on its own CG evidence (absent, no Space, or ordered out), and `remaining` is empty, so the group is destroyed once. `CloseRule` is unchanged apart from its doc (D-25 paragraph and table row).
- **Logs:**
  - `.build/09-30-tabs-vm27-measure.log`, `.build/09-30-tabs-vm15-measure.log`: the measurement (RED on both; the Cmd-W guard and the tab-switch test passed).
  - `.build/09-30-red.log`: all six shape rows and the other-Space scenario failed before the change; the five guards passed.
  - `.build/09-30-tabs-vm27.log`: first proof on 27.2 failed (latency 3.07 s, `windows=1`, `state=absent`), with the timing above. `.build/09-30-tabs-vm15.log`: 15.7 passed with that first change (0.370 s).
  - `.build/09-30-red2.log`: the new scenario `aKeptAliveTabGroupStillOnScreenAtTheFirstRefreshIsRechecked` failed before the on-screen recheck (no quick recheck requested, state absent).
  - `.build/09-30-engine.log`: TransomEngineTests 1344 tests passed.
  - `.build/09-30-tabs-vm27-2.log`: rerun that never reached the tests (`ssh: connect … Operation timed out` at boot).
  - `.build/09-30-tabs-vm27-3.log`: TabsIntegrationTests 3/3 passed on 27.2; group gone in 0.673 s; `cmd-w facts: next tab listed after 19 ms`.
  - `.build/09-30-tabs-vm15-2.log`: TabsIntegrationTests 3/3 passed on 15.7 with the final code; 0.388 s; `cmd-w facts: next tab listed after 1 ms`.
  - `.build/09-30-tabgroup-vm27.log`, `.build/09-30-tabgroup-vm15.log`: TabGroupIntegrationTests 7/7 passed on both (the 15.7 L46 launch flake did not recur).
  - `.build/09-30-close-vm27.log`, `.build/09-30-close-vm15.log`: CloseIntegrationTests passed on both.
  - `.build/09-30-full.log`: host gate, four passed "Test run with" lines; `scripts/check-no-appkit.sh` OK.
- **Not covered (not measured):**
  - (a) A group closed while its Space is not shown waits until that Space shows.
  - (b) With the Spaces lookup off, a closed group stays tracked.
  - (c) A group closed while its app is hidden waits until the app is shown.
  - (d) The 250 ms confirmation assumes AppKit lists the next tab sooner after a Cmd-W (measured: 0 ms and 19 ms on 27.2, 0 ms and 1 ms on 15.7).
  - (e) A native fullscreen tab group closed whole was not measured.
  - (f) A shown tab that stays on screen in CG for more than about 2 s after the close (8 quick rechecks) waits for the 5 s sweep.
