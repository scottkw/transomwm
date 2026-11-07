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
