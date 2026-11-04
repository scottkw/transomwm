# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## safari-toolbar-drag-no-dock — an app's windows "never dock by drag" (Safari, unified toolbar); not reproducible
- **Date:** 2026-10-26
- **Error patterns:** drag to dock, no preview, stays floating, Safari, unified toolbar, title bar drag, TextEdit works
- **Root cause(s):** unknown; not reproducible at bb67b5d. Most likely the first report came from a session whose tap was not running (WR-02, tracking started only after a relaunch) or from drops outside every drop zone
- **Fix:** none needed; drag logging kept at debug level (`log stream --level debug --predicate 'subsystem == "com.eightabyte.pane" AND category == "drag"'`): one press line (session or why not, AX and CG start frames) and one release line (kind, travel, dragged events, polls, first/last CG, decision, preview)
- **Files changed:** Sources/PaneEngine/DragSession.swift, Sources/PaneMac/ArrangeController.swift (diagnostics only)
- **Why not caught:** no gate existed for this class: live drags are human UAT, and the first report had no log to tell "no session" from "miss" from a misclassification
- **Recurrence guard:** the "drag" debug log above. Read it before changing the drag classifier; first confirm the tap is running (permission -> ready in the log) and that the press logged a "start" line
---


## tab-focus-and-url — app activation gave no focus event (hidden tab stayed parked); tab URLs refused when `open` activates Transom
- **Date:** 2026-11-02
- **Error patterns:** ⌘Tab, Dock click, open -a, app activation, no focused-window change, hidden tab stays parked, invisible key window, strip not raised, cross-app click, refused next tab: not in a tab group, open without -g, URL activates Transom, frontmostApplication is Transom
- **Root cause(s):** AXWindowSystem made focus hints only from kAXFocusedWindowChanged / kAXMainWindowChanged, which macOS doesn't send when an activation keeps the app's focused window; commandContext() read the focused window of NSWorkspace.frontmostApplication, which is Transom itself once LaunchServices activates it to deliver a URL
- **Fix:** NSWorkspace.didActivateApplication → PendingFocus.activated(pid:) resolved through AXMain on the app's refresh (deduped against the AX notice); URL dispatches use AXWindowSystem.lastOtherFrontmostPID when Transom is frontmost (ArrangeController.commandPID)
- **Files changed:** Sources/TransomEngine/PendingFocus.swift, Sources/TransomMac/AXWindowSystem.swift, Sources/TransomMac/ArrangeController.swift, Tests/TransomEngineTests/PendingFocusTests.swift, Tests/TransomMacTests/AppDelegateTests.swift, Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift
- **Why not caught:** no gate existed for this class: live tests focused windows through Transom's own AX focus path (which does send AX notices) and dispatched URLs in-process, never via a real activation or `open`
- **Recurrence guard:** VM TabGroupIntegrationTests.activatingTheAppOfAHiddenMemberSelectsIt (AXFrontmost activation, red without the hook); PendingFocusTests activation/dedup cases; AppDelegateTests.aURLActsOnTheAppFrontmostBeforeTransom. Any new "focused window" consumer must ask whether activation and Transom-frontmost cases reach it
---

## sigterm-quit-hang — SIGTERM and killall left the app alive for minutes: terminate called inside the main queue while its reply waited on that queue
- **Date:** 2026-11-04
- **Error patterns:** pkill -TERM, killall, SIGTERM, app stays alive, no exit, nested run loop, _shouldTerminate, terminateLater, handleSIGTERM, DispatchSource, main queue, __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__, cleanExit false, shutdown -r, ⌘Q works, menu Quit works
- **Root cause(s):** the SIGTERM source (queue .main) calls NSApp.terminate from inside a main-queue drain; applicationShouldTerminate returned .terminateLater and left restore, writeCleanExit and the reply to a main-queue block, which AppKit's wait does not service from inside that queue
- **Fix:** applicationShouldTerminate does the bounded work itself and returns .terminateNow; no wait, for any caller of terminate
- **Files changed:** Sources/TransomMac/AppDelegate.swift, Sources/TransomMac/AXWindowSystem.swift, Tests/TransomMacTests/AppDelegateTests.swift, Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift, Tests/TransomMacIntegrationTests/IntegrationSupport.swift, scripts/vm-live-test.sh, scripts/vm-quit-check.sh
- **Why not caught:** no gate existed for this class: the unit test called the delegate directly, live tests call the restore in-process, and nothing quit the real app by signal
- **Recurrence guard:** OutsideQuitIntegrationTests (scripts/vm-quit-check.sh) and AppDelegateTests.quittingRestoresThenWritesTheCleanExitBeforeAnswering. Any AppKit wait entered from a DispatchQueue.main block, Task or signal source cannot be answered by a later main-queue block. Real logout and loginwindow restart behave as the quit Apple Event, not SIGTERM
---
