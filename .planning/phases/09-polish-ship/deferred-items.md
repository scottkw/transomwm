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
