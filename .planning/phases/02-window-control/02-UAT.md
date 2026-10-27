---
status: partial
phase: 02-window-control
source: [02-VERIFICATION.md]
started: 2026-10-25T21:20:07Z
updated: 2026-10-27T19:35:00-05:00
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing paused - 5 blocked: 2, 3, 17 on G-02-1; 11 on G-02-10; 9 on the second display. Gaps G-02-1, G-02-10, G-02-12 to diagnose]

## Tests

### 1. Accessibility grant flow: `tccutil reset Accessibility com.eightabyte.pane.debug`, then `scripts/run-debug.sh --no-build`; follow the setup window
expected: S1 with a default 'Open System Settings'; the macOS prompt appears exactly once; after enabling 'Pane Debug' the window shows 'Pane is ready' with no click; the glyph changes from exclamationmark.triangle to rectangle.split.2x1
result: issue
reported: "No setup window..." (VM, Transom Debug 0.3.0 after the rename, launched with no grant: CGWindowList shows Transom Debug#69 at 511,355 sized 1x28 — a title bar with no content — plus the status item showing the warning glyph)
severity: major

### 2. Stale grant form B: copy the app to the scratchpad, re-sign only the copy ad hoc, launch it and click Open System Settings; then Reset Permission
expected: 'Already turned on?' appears after 15 s, not before; 'Resetting permission…' with every button disabled, then 'Turn Pane on again'. Form A (probe -25211) has not been reproduced locally; note if seen
result: blocked
blocked_by: other
reason: "Needs a usable setup window; blocked by G-02-1 (window opens at 1x28)"

### 3. Close the setup window while not ready; reopen it from the menu; try Esc and Cmd-W
expected: It never reopens by itself; 'Grant Accessibility Access…' / 'Fix Accessibility Access…' reopens it; Esc and Cmd-W close it except while resetting
result: blocked
blocked_by: other
reason: "Needs a usable setup window; blocked by G-02-1 (window opens at 1x28)"

### 4. TCC grant survives a rebuild: grant Pane Debug, rebuild with `scripts/build-debug.sh`, relaunch
expected: No new prompt; tracking starts
result: pass
note: "Claude-driven in the VM: rebuilt Transom Debug, reinstalled, relaunched (pid 1109); trusted launch, no setup window, tracking began and layout.json was written within 4 s. Test 1 side note: a manual grant in System Settings was picked up without a relaunch"

### 5. Menu-bar glyph in light, dark and tinted menu bars; header 'Tracking N windows in M apps'; Debug shows 'Window ID lookup: available' and 'Spaces lookup: available' (and 'Spaces lookup: off, single Space' with `--disable-private=Spaces`)
expected: Glyph legible in every appearance; plausible counts; both Debug lines correct (backstop 02-02, 02-14 D5)
result: pass
note: "Claude-driven in the VM via screenshots: split-rectangle glyph visible in light and dark menu bars; header Tracking 9 windows in 2 apps; Option-click Debug submenu shows Window ID lookup: available, Spaces lookup: available, Event tap: running; with --disable-private=Spaces it shows Spaces lookup: off, single Space. macOS 15 has no separate tinted menu bar, not checked"

### 6. Lock and sleep: with 10 windows in several apps and Tracked Windows open, lock (Ctrl-Cmd-Q) for 30 s and unlock; sleep for a minute from the Apple menu and wake; optionally switch users
expected: All 10 rows remain after each cycle; footer briefly shows 'Refreshing after wake · '; nothing moved or forgotten
result: pass
note: "VM, Claude-driven lock (Ctrl-Cmd-Q at 20:13:28) and user unlock after about 60 s: log shows session paused: locked or asleep, then session resumed after a full refresh 6 s after unlock; the menu still reads Tracking 16 windows with the same 16 on-screen windows. Not run: sleep and wake (a sleeping VM may not wake over SSH) and switch users"

### 7. Real kill -STOP: open TextEdit and Safari windows, `kill -STOP <TextEdit pid>`, open a new Safari window and open Pane's menu; then `kill -CONT`
expected: Menu opens instantly; the new Safari window is counted within a second; '1 app not responding' appears within about 7 s; after CONT it clears within about 4 s and TextEdit's windows were never dropped
result: pass
note: "Claude-driven in the VM: kill -STOP TextEdit, Cmd-N in Safari; the menu opened at once with Tracking 11 windows in 3 apps and 1 app not responding; after kill -CONT the line was gone within 4 s and the count stayed 11 (TextEdit windows kept)"

### 8. Freeze test (Debug ▸ Freeze “TextEdit” for 10 Seconds…): Return and Esc cancel; Freeze stops it; rows show 'Not responding'; auto-resume after 10 s; Freeze then Quit Pane resumes TextEdit at once; Finder/Pane show 'Freeze Frontmost App (not allowed)'; Release build has no Freeze item
expected: As described in 02-08 SUMMARY human checks 3-6
result: pass
note: "Claude-driven in the VM via screenshots: the Freeze dialog defaults to Cancel; Return and Esc both cancel (TextEdit stays S); Freeze stops it (T); Tracked Windows rows show orange Not responding badges and the footer 5 not responding; it resumes by itself; Freeze then Quit Transom left TextEdit running (S) within 0.5 s; with Finder frontmost the item reads Freeze Frontmost App (not allowed); the Release build has no Freeze item. Not checked: the Transom-frontmost wording (an accessory app is rarely frontmost). Seen in passing: the dialog shows a generic app icon, since Transom has no icon yet"

### 9. Multi-display Nudge: on the built-in display, Debug ▸ Nudge Focused Window twice on a TextEdit window; attach an external display (or Sidecar) above, then left (and below), and nudge a window on it; unplug and replug while Pane runs
expected: +32/+32 and -64x-64, then an exact restore; the same on the external display in each arrangement; the Display column follows; one displaysChanged then one refresh about 500 ms later on hot-plug
result: blocked
blocked_by: physical-device
reason: "The Tart VM has one virtual display; needs the host with the DELL (deferred with the Phase 3 second-display re-checks in STATE.md)"

### 10. Real native tabs: Finder, Terminal and Safari windows with three tabs each (Cmd-T); click between tabs. Then, quickly, Cmd-T followed at once by Ctrl-Shift-Tab; and Cmd-T followed by a click on an older tab. Also Cmd-W on the shown tab
expected: One row per app window; the tab count and shown title follow every action; tab clicks change Title but never add or remove rows; the quick Cmd-T sequences never add a second row or crash Pane (REVIEW-FIX CR-01, WR-01); note which apps report AXTabGroup (Safari may not)
result: issue
reported: "Claude-driven in the VM: after opening Terminal, Safari and Finder windows and pressing Cmd-T twice in each, then on Terminal Cmd-T + Ctrl-Shift-Tab twice and Cmd-W, Transom reports Tracking 15 windows in 4 apps while 13 exist (AX and CGWindowList agree). Finder shows two rows for one tab group: stale #20 (2 tabs) plus #213 (4 tabs) while the shown tab is #214; Terminal shows #203, a stale #206 (no tab group) and #208 (4 tabs) while the group's shown tab is #219. The extra rows never cleared (checked again after a minute). Safari reports no AXTabGroup (tabs column empty), as the test anticipated. Transom did not crash"
severity: major

### 11. Real Space switches with tab groups, with and without `--disable-private=Spaces`: a Terminal tab group on Space 1 and a same-frame Terminal window (and, separately, a same-frame tab group) on Space 2; switch back and forth; press Cmd-T in the Space 1 window while the twin sits on Space 2, then switch again; also the whole-group close plus immediate switch in behavior_unverified_items. Check `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 5m`
expected: With Space data: one row per real window throughout, and Space switches and Cmd-T never add, remove or duplicate rows. Without Space data: the same, except two same-frame tab groups may share one row (accepted single-Space limit), and no row is ever lost. Log shows 'Spaces: available' or 'Spaces: off'
result: blocked
blocked_by: other
reason: "Builds on native tab tracking, which fails in test 10 (G-02-10); re-run after that fix"

### 12. Frame writes and minimum-size hints on real apps via Nudge. First delete `~/Library/Application Support/Pane/min-size-hints.json`, which may hold snap hints learned under the old rule. Then try a Chrome or Electron window (AXEnhancedUserInterface toggled and restored), Terminal or iTerm2, and an app with a real minimum (Notes, Music); open a second window of that app; quit and relaunch Pane
expected: Enhanced UI restored; no terminal cell snap learned; Min Size shows the real minimum about a second after the refused write; the second window starts from it; after relaunch the hint is back; the hints file holds only bundle IDs and sizes. Also watch for the late-applier warning: a busy Chrome/Electron window must not learn its pre-write size as a minimum
result: issue
reported: "Claude-driven in the VM: deleted the hints file (only the old Pane one existed), shrank Notes #234 with AX to find its real minimum (642x324), then Debug > Nudge Focused Window. Notes moved +32,+32 but kept 642x324 (the size write was refused), yet the Min Size column stayed blank and no Application Support/Transom/min-size-hints.json was written, so nothing was learned. Not run: Chrome/Electron (not installed in the VM), Terminal cell snap, second window and relaunch, which all depend on learning"
severity: major

### 13. Exclusions in the real UI: Don't Arrange “TextEdit”, then Never Arrange submenu, then Nudge with TextEdit frontmost, then Nudge with System Settings frontmost
expected: Checkmark; 'Excluded' badge; submenu lists and removes it; 'No apps excluded' when empty; 'Nudge Focused Window (app excluded)' and '(no window)' are shown disabled
result: pass
note: "Claude-driven in the VM via screenshots: Ctrl-Opt-Cmd-E on TextEdit put a checkmark on Don't Arrange \"TextEdit\"; Never Arrange listed TextEdit; Tracked Windows showed Excluded badges and footer 5 excluded; Debug showed Nudge Focused Window (app excluded) disabled; clicking TextEdit in Never Arrange removed it (No apps excluded, checkmark gone); with System Settings frontmost Debug showed Nudge Focused Window (no window) disabled"

### 14. Signed app, private lookup: run Pane Debug for 10 minutes of normal use across several apps (open and close windows, switch tabs and Spaces), then `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 15m`. Then relaunch with `scripts/run-debug.sh --no-build --disable-private=AXWindowID` (and once with `--disable-private=AXWindowID,Bogus`), open and close windows, and watch Tracked Windows and the Debug menu
expected: No 'AXWindowID failed 5 times' line in normal use, and Debug still shows 'Window ID lookup: available'. With the flag: 'Window ID lookup: off, matching by frame' in menu and footer; rows show 'by frame', appear and disappear normally and never duplicate; the log has the capability report and an error line for 'Bogus'
result: pass
note: "Claude-driven in the VM: about 30 min of use across Finder, Safari, Terminal, TextEdit, Notes and System Settings (tabs, freezes, relaunches) logged only the capability report, never AXWindowID failed 5 times. With --disable-private=AXWindowID,Bogus: log AXWindowID: off plus E unknown --disable-private name ignored: Bogus; Debug menu and footer read Window ID lookup: off, matching by frame; Cmd-N, Cmd-W, Cmd-N in TextEdit gave 6 rows for 6 real windows, no duplicates. Rows whose frame matched one CG window show its real ID (fallback match); the two same-frame windows show by frame"

### 15. Corpus review before pushing publicly (SECURITY T-02-08): read every JSON in Tests/PaneEngineTests/Fixtures/AXDumps (`git log -p -- Tests/PaneEngineTests/Fixtures/AXDumps`), especially libreoffice_start_center and android_studio_welcome; then set confirmedBy to 'developer'
expected: No title, path, URL or account name; every label matches the window. All 11 cases currently read confirmedBy 'executor-proposed'
result: pass
note: "Claude scanned all 12 fixtures (11 old plus safari_pip): no free-text strings at all (titles redacted), no path, URL or account name, every label matches its window; the developer confirmed on 2026-10-27 and all 12 now read confirmedBy developer; ClassifierCorpusTests pass"

### 16. Picture-in-picture capture (backstop 02-03): play a video in Safari or Chrome, enter PiP, `swift run pane-dump --app com.apple.Safari --list`, then capture with `--label neverDock --family native --case safari_pip`; run `swift test --filter ClassifierCorpusTests`
expected: The PiP case is labelled neverDock and classifies neverDock
result: pass
note: "Claude-driven in the VM: Safari played Apple's bipbop HLS sample and entered PiP via webkitSetPresentationMode; on macOS 15 the PiP window belongs to com.apple.PIPAgent (AXSystemFloatingWindow, layer 19), not Safari, so it was captured with transom-dump --app com.apple.PIPAgent --window 0 --label neverDock --family native --case safari_pip (title redacted, confirmedBy executor-proposed). swift test --filter ClassifierCorpusTests: 12 cases, every case classifies to its label"

### 17. UI-REVIEW visual items: GroupBox callout inner padding (12 pt vs about 2x); Tracked Windows table background and alternating rows; long CFBundleName wraps at 480 pt in the setup window; the 'Looking for windows…' font; reset-failed state with duplicated 'Open System Settings' buttons and callouts B and E at once; menu header vs footer counts and missing loading state; table behaviour at 720 pt (horizontal scroll, pinned header, middle-truncated titles with tooltips)
expected: Confirm or file each against 02-UI-REVIEW.md Top 3 fixes and needs_human_review items
result: blocked
blocked_by: other
reason: "The setup-window items (GroupBox callout padding, long CFBundleName wrap at 480 pt, reset-failed duplicated buttons and callouts B and E) need a usable setup window; blocked by G-02-1. Checked in the VM by screenshot: the Tracked Windows table has alternating rows on a plain background and scrolls horizontally with a pinned header at 960 pt; the menu header (Tracking 16 windows in 5 apps) matches the footer (16 windows, 5 apps). Not seen: the transient Looking for windows state, title truncation tooltips at 720 pt"

### 18. Prohibition review (judgment tier, non-authoritative LLM verdicts in the report): confirm no TrellisWM material and no code copied from AeroSpace, Amethyst, yabai or Loop (Loop is GPL-3.0; the SkyLight shim must be an independent reimplementation)
expected: Developer confirms clean-room status
result: pass
note: "Developer confirmed clean-room status on 2026-10-27"

## Summary

total: 18
passed: 10
issues: 3
pending: 0
skipped: 0
blocked: 5

## Gaps

- gap_id: G-02-1
  truth: "With no Accessibility grant, launch opens a readable Set Up window with a default Open System Settings button"
  status: failed
  reason: "User reported: No setup window... (CGWindowList: the window exists at 1x28 pt, centred, content never sized it)"
  severity: major
  test: 1
  artifacts: []
  missing: []

- gap_id: G-02-10
  truth: "A native tab group is one tracked window: new tabs, tab switches and Cmd-W change its title and tab count but never add or leave extra rows"
  status: failed
  reason: "Claude-driven VM run: Tracking 15 windows while 13 exist; Finder keeps stale #20 beside the 4-tab group (#213 shown as its id, real shown tab #214); Terminal keeps stale #206 beside the 4-tab group (#208 shown, real #219); never cleared"
  severity: major
  test: 10
  artifacts: []
  missing: []

- gap_id: G-02-12
  truth: "A refused frame write teaches Transom the window's real minimum: Min Size shows it about a second later and min-size-hints.json stores it per bundle"
  status: failed
  reason: "Claude-driven VM run: Nudge on Notes at its 642x324 minimum moved it but the size was refused; Min Size stayed blank and no hints file was written"
  severity: major
  test: 12
  artifacts: []
  missing: []
