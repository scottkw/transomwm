---
status: testing
phase: 02-window-control
source: [02-VERIFICATION.md]
started: 2026-10-25T21:20:07Z
updated: 2026-10-25T21:20:07Z
---

## Current Test

number: 1
name: Accessibility grant flow: `tccutil reset Accessibility com.eightabyte.pane.debug`, then `scripts/run-debug.sh --no-build`; follow the setup window
expected: |
  S1 with a default 'Open System Settings'; the macOS prompt appears exactly once; after enabling 'Pane Debug' the window shows 'Pane is ready' with no click; the glyph changes from exclamationmark.triangle to rectangle.split.2x1
awaiting: user response

## Tests

### 1. Accessibility grant flow: `tccutil reset Accessibility com.eightabyte.pane.debug`, then `scripts/run-debug.sh --no-build`; follow the setup window
expected: S1 with a default 'Open System Settings'; the macOS prompt appears exactly once; after enabling 'Pane Debug' the window shows 'Pane is ready' with no click; the glyph changes from exclamationmark.triangle to rectangle.split.2x1
result: [pending]

### 2. Stale grant form B: copy the app to the scratchpad, re-sign only the copy ad hoc, launch it and click Open System Settings; then Reset Permission
expected: 'Already turned on?' appears after 15 s, not before; 'Resetting permission…' with every button disabled, then 'Turn Pane on again'. Form A (probe -25211) has not been reproduced locally; note if seen
result: [pending]

### 3. Close the setup window while not ready; reopen it from the menu; try Esc and Cmd-W
expected: It never reopens by itself; 'Grant Accessibility Access…' / 'Fix Accessibility Access…' reopens it; Esc and Cmd-W close it except while resetting
result: [pending]

### 4. TCC grant survives a rebuild: grant Pane Debug, rebuild with `scripts/build-debug.sh`, relaunch
expected: No new prompt; tracking starts
result: [pending]

### 5. Menu-bar glyph in light, dark and tinted menu bars; header 'Tracking N windows in M apps'; Debug shows 'Window ID lookup: available' and 'Spaces lookup: available' (and 'Spaces lookup: off, single Space' with `--disable-private=Spaces`)
expected: Glyph legible in every appearance; plausible counts; both Debug lines correct (backstop 02-02, 02-14 D5)
result: [pending]

### 6. Lock and sleep: with 10 windows in several apps and Tracked Windows open, lock (Ctrl-Cmd-Q) for 30 s and unlock; sleep for a minute from the Apple menu and wake; optionally switch users
expected: All 10 rows remain after each cycle; footer briefly shows 'Refreshing after wake · '; nothing moved or forgotten
result: [pending]

### 7. Real kill -STOP: open TextEdit and Safari windows, `kill -STOP <TextEdit pid>`, open a new Safari window and open Pane's menu; then `kill -CONT`
expected: Menu opens instantly; the new Safari window is counted within a second; '1 app not responding' appears within about 7 s; after CONT it clears within about 4 s and TextEdit's windows were never dropped
result: [pending]

### 8. Freeze test (Debug ▸ Freeze “TextEdit” for 10 Seconds…): Return and Esc cancel; Freeze stops it; rows show 'Not responding'; auto-resume after 10 s; Freeze then Quit Pane resumes TextEdit at once; Finder/Pane show 'Freeze Frontmost App (not allowed)'; Release build has no Freeze item
expected: As described in 02-08 SUMMARY human checks 3-6
result: [pending]

### 9. Multi-display Nudge: on the built-in display, Debug ▸ Nudge Focused Window twice on a TextEdit window; attach an external display (or Sidecar) above, then left (and below), and nudge a window on it; unplug and replug while Pane runs
expected: +32/+32 and -64x-64, then an exact restore; the same on the external display in each arrangement; the Display column follows; one displaysChanged then one refresh about 500 ms later on hot-plug
result: [pending]

### 10. Real native tabs: Finder, Terminal and Safari windows with three tabs each (Cmd-T); click between tabs. Then, quickly, Cmd-T followed at once by Ctrl-Shift-Tab; and Cmd-T followed by a click on an older tab. Also Cmd-W on the shown tab
expected: One row per app window; the tab count and shown title follow every action; tab clicks change Title but never add or remove rows; the quick Cmd-T sequences never add a second row or crash Pane (REVIEW-FIX CR-01, WR-01); note which apps report AXTabGroup (Safari may not)
result: [pending]

### 11. Real Space switches with tab groups, with and without `--disable-private=Spaces`: a Terminal tab group on Space 1 and a same-frame Terminal window (and, separately, a same-frame tab group) on Space 2; switch back and forth; press Cmd-T in the Space 1 window while the twin sits on Space 2, then switch again; also the whole-group close plus immediate switch in behavior_unverified_items. Check `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 5m`
expected: With Space data: one row per real window throughout, and Space switches and Cmd-T never add, remove or duplicate rows. Without Space data: the same, except two same-frame tab groups may share one row (accepted single-Space limit), and no row is ever lost. Log shows 'Spaces: available' or 'Spaces: off'
result: [pending]

### 12. Frame writes and minimum-size hints on real apps via Nudge. First delete `~/Library/Application Support/Pane/min-size-hints.json`, which may hold snap hints learned under the old rule. Then try a Chrome or Electron window (AXEnhancedUserInterface toggled and restored), Terminal or iTerm2, and an app with a real minimum (Notes, Music); open a second window of that app; quit and relaunch Pane
expected: Enhanced UI restored; no terminal cell snap learned; Min Size shows the real minimum about a second after the refused write; the second window starts from it; after relaunch the hint is back; the hints file holds only bundle IDs and sizes. Also watch for the late-applier warning: a busy Chrome/Electron window must not learn its pre-write size as a minimum
result: [pending]

### 13. Exclusions in the real UI: Don't Arrange “TextEdit”, then Never Arrange submenu, then Nudge with TextEdit frontmost, then Nudge with System Settings frontmost
expected: Checkmark; 'Excluded' badge; submenu lists and removes it; 'No apps excluded' when empty; 'Nudge Focused Window (app excluded)' and '(no window)' are shown disabled
result: [pending]

### 14. Signed app, private lookup: run Pane Debug for 10 minutes of normal use across several apps (open and close windows, switch tabs and Spaces), then `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 15m`. Then relaunch with `scripts/run-debug.sh --no-build --disable-private=AXWindowID` (and once with `--disable-private=AXWindowID,Bogus`), open and close windows, and watch Tracked Windows and the Debug menu
expected: No 'AXWindowID failed 5 times' line in normal use, and Debug still shows 'Window ID lookup: available'. With the flag: 'Window ID lookup: off, matching by frame' in menu and footer; rows show 'by frame', appear and disappear normally and never duplicate; the log has the capability report and an error line for 'Bogus'
result: [pending]

### 15. Corpus review before pushing publicly (SECURITY T-02-08): read every JSON in Tests/PaneEngineTests/Fixtures/AXDumps (`git log -p -- Tests/PaneEngineTests/Fixtures/AXDumps`), especially libreoffice_start_center and android_studio_welcome; then set confirmedBy to 'developer'
expected: No title, path, URL or account name; every label matches the window. All 11 cases currently read confirmedBy 'executor-proposed'
result: [pending]

### 16. Picture-in-picture capture (backstop 02-03): play a video in Safari or Chrome, enter PiP, `swift run pane-dump --app com.apple.Safari --list`, then capture with `--label neverDock --family native --case safari_pip`; run `swift test --filter ClassifierCorpusTests`
expected: The PiP case is labelled neverDock and classifies neverDock
result: [pending]

### 17. UI-REVIEW visual items: GroupBox callout inner padding (12 pt vs about 2x); Tracked Windows table background and alternating rows; long CFBundleName wraps at 480 pt in the setup window; the 'Looking for windows…' font; reset-failed state with duplicated 'Open System Settings' buttons and callouts B and E at once; menu header vs footer counts and missing loading state; table behaviour at 720 pt (horizontal scroll, pinned header, middle-truncated titles with tooltips)
expected: Confirm or file each against 02-UI-REVIEW.md Top 3 fixes and needs_human_review items
result: [pending]

### 18. Prohibition review (judgment tier, non-authoritative LLM verdicts in the report): confirm no TrellisWM material and no code copied from AeroSpace, Amethyst, yabai or Loop (Loop is GPL-3.0; the SkyLight shim must be an independent reimplementation)
expected: Developer confirms clean-room status
result: [pending]

## Summary

total: 18
passed: 0
issues: 0
pending: 18
skipped: 0
blocked: 0

## Gaps
