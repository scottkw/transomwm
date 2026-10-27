---
status: partial
phase: 02-window-control
source: [02-VERIFICATION.md]
started: 2026-10-25T21:20:07Z
updated: 2026-10-27T22:20:33.174Z
---

## Current Test

[testing complete]

## Tests

### 1. Accessibility grant flow: `tccutil reset Accessibility com.eightabyte.pane.debug`, then `scripts/run-debug.sh --no-build`; follow the setup window
expected: S1 with a default 'Open System Settings'; the macOS prompt appears exactly once; after enabling 'Pane Debug' the window shows 'Pane is ready' with no click; the glyph changes from exclamationmark.triangle to rectangle.split.2x1
result: pass
note: "First run 2026-10-27: issue G-02-1 (window 1x28). Re-run after 02-18 (0378755) in the VM with a fresh Debug build and a reset grant: Set Up Transom opens 480x345 centred, readable, Open System Settings is the default button; it went straight to the Accessibility list (no separate macOS prompt seen); after the user switched Transom Debug on, the window changed to Transom is ready with no click and shrank to 480x253 keeping its top edge, and the glyph changed to the split rectangle. Seen: launched over SSH it opens behind the frontmost app (macOS does not activate an app another process launched); a normal user launch was not tried"

### 2. Stale grant form B: copy the app to the scratchpad, re-sign only the copy ad hoc, launch it and click Open System Settings; then Reset Permission
expected: 'Already turned on?' appears after 15 s, not before; 'Resetting permission…' with every button disabled, then 'Turn Pane on again'. Form A (probe -25211) has not been reproduced locally; note if seen
result: pass
note: "VM, after 02-18: an ad-hoc re-signed copy launched with the stale grant showed only Waiting for access about 10 s after Open System Settings, then the Already turned on? callout with Reset Permission by about 17 s; Reset Permission ended at Turn Transom on again. The Resetting permission state was too brief to capture in a screenshot; form A (-25211) not seen"

### 3. Close the setup window while not ready; reopen it from the menu; try Esc and Cmd-W
expected: It never reopens by itself; 'Grant Accessibility Access…' / 'Fix Accessibility Access…' reopens it; Esc and Cmd-W close it except while resetting
result: pass
note: "VM, after 02-18, not ready: Cmd-W closed the window and it did not reopen in 6 s; the menu showed Accessibility access needed and Grant Accessibility Access..., which reopened it (480x281); Esc closed it. Not checked: Esc and Cmd-W blocked while resetting (the reset is too quick to catch)"

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
result: pass
note: "First run 2026-10-27: issue G-02-10 (stale extra rows). Re-run in the VM after 02-19 (859c77c, 7f764ad) on a fresh Transom Debug: Terminal Cmd-N then Cmd-T (the 28 pt taller tab), Finder group #339 resized to 280 pt then Cmd-T, then on Terminal Cmd-T + Ctrl-Shift-Tab twice and Cmd-W. Tracked Windows: Finder 5 rows for 5 real windows (group #339 shown tab #400, 4 tabs), Terminal 4 rows for 4 real windows (#395 group shown tab #405, 3 tabs); counts match AX. Safari still reports no AXTabGroup. No crash"

### 11. Real Space switches with tab groups, with and without `--disable-private=Spaces`: a Terminal tab group on Space 1 and a same-frame Terminal window (and, separately, a same-frame tab group) on Space 2; switch back and forth; press Cmd-T in the Space 1 window while the twin sits on Space 2, then switch again; also the whole-group close plus immediate switch in behavior_unverified_items. Check `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 5m`
expected: With Space data: one row per real window throughout, and Space switches and Cmd-T never add, remove or duplicate rows. Without Space data: the same, except two same-frame tab groups may share one row (accepted single-Space limit), and no row is ever lost. Log shows 'Spaces: available' or 'Spaces: off'
result: pass
note: "VM after 02-19: Terminal #444 on Space 3 set to the same frame as the Space 1 group (#405 at 423,265 585x399); Cmd-T in the Space 1 group, then Space switches 1-3-1-3-1. With Space data: Terminal 6 rows for 6 real windows (group 4 tabs, twin #444 its own row). Relaunched with --disable-private=Spaces (log Spaces: off) and repeated: 6 rows for 6 windows, group 5 tabs, twin kept, no row lost. Not run: a same-frame tab group (not a single window) as the twin, and the whole-group close plus immediate switch"

### 12. Frame writes and minimum-size hints on real apps via Nudge. First delete `~/Library/Application Support/Pane/min-size-hints.json`, which may hold snap hints learned under the old rule. Then try a Chrome or Electron window (AXEnhancedUserInterface toggled and restored), Terminal or iTerm2, and an app with a real minimum (Notes, Music); open a second window of that app; quit and relaunch Pane
expected: Enhanced UI restored; no terminal cell snap learned; Min Size shows the real minimum about a second after the refused write; the second window starts from it; after relaunch the hint is back; the hints file holds only bundle IDs and sizes. Also watch for the late-applier warning: a busy Chrome/Electron window must not learn its pre-write size as a minimum
result: pass
note: "First run (2026-10-27) started Notes exactly at its minimum, which the learner deliberately ignores (WR-01 unmoved-refusal rule; debug g-02-12), so nothing was learned. Corrected step: start the window 2-32 pt above its minimum on each axis (Notes at 658x340), then one Nudge. Re-run in the VM: Notes read back 642x324, min-size-hints.json held com.apple.Notes 642x324 about 1.5 s later and Min Size showed 642 x 324; after quitting and relaunching Transom Debug the Notes row showed Min Size 642 x 324 again. Not run: Chrome/Electron (not installed), Terminal cell snap, second window. Side note: the Arranger moves a floating window back to its wanted frame on the next re-plan, undoing a Debug Nudge"

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
result: pass
note: "VM by screenshot after 02-18: the Already turned on? callout has even padding (about 20 pt) and the window grows to fit it; Tracked Windows has alternating rows, horizontal scroll and a pinned header; the menu header count matches the footer. Not checked: a long CFBundleName wrap at 480 pt (Transom Debug is short), the reset-failed state (not reproduced), the transient Looking for windows state, truncation tooltips at 720 pt"

### 18. Prohibition review (judgment tier, non-authoritative LLM verdicts in the report): confirm no TrellisWM material and no code copied from AeroSpace, Amethyst, yabai or Loop (Loop is GPL-3.0; the SkyLight shim must be an independent reimplementation)
expected: Developer confirms clean-room status
result: pass
note: "Developer confirmed clean-room status on 2026-10-27"

## Summary

total: 18
passed: 17
issues: 0
pending: 0
skipped: 0
blocked: 1

## Gaps

- gap_id: G-02-1
  truth: "With no Accessibility grant, launch opens a readable Set Up window with a default Open System Settings button"
  status: resolved
  resolved_by: "02-18-PLAN.md"
  resolved_at: "2026-10-27"
  reason: "User reported: No setup window... (CGWindowList: the window exists at 1x28 pt, centred, content never sized it)"
  severity: major
  test: 1
  root_cause: "SetupWindowController.makeWindow() sets hosting.sizingOptions = [.intrinsicContentSize], which never sizes an NSWindow; the window keeps the empty 1x28 frame from NSWindow(contentViewController:) and is centred at that size. Reproduced line-for-line in the VM; [.preferredContentSize] sizes it (480x353) and follows state changes"
  artifacts:
    - path: "Sources/TransomMac/Permission/SetupWindowController.swift"
      issue: "line 44 sizingOptions = [.intrinsicContentSize]"
  missing:
    - "Use hosting.sizingOptions = [.preferredContentSize]"
    - "Regression test: after makeWindow() and layoutIfNeeded() the content size equals hosting.view.fittingSize, is non-zero, and follows a state change"
  debug_session: ".planning/debug/g-02-1-setup-window-1x28.md"

- gap_id: G-02-10
  truth: "A native tab group is one tracked window: new tabs, tab switches and Cmd-W change its title and tab count but never add or leave extra rows"
  status: resolved
  resolved_by: "02-19-PLAN.md"
  resolved_at: "2026-10-27"
  reason: "Claude-driven VM run: Tracking 15 windows while 13 exist; Finder keeps stale #20 beside the 4-tab group (#213 shown as its id, real shown tab #214); Terminal keeps stale #206 beside the 4-tab group (#208 shown, real #219); never cleared"
  severity: major
  test: 10
  root_cause: "TabGroupTracker.update links hidden tabs to a group only by exact CG bounds (slot/matches); on macOS 15.7.7 a hidden native tab keeps the frame it had when hidden, so after the group resizes (Terminal's tab bar adds 28 pt; a resized Finder tab) the opener/join/handoff/fold rules miss, the new tab starts its own group and nothing retires the old ID (CloseRule .noChange, leaders never folded). Reproduced live (E1 Terminal, E4 Finder); the fake gives every tab the group frame, so no test saw it"
  artifacts:
    - path: "Sources/TransomEngine/TabGroupTracker.swift"
      issue: "bounds-only hidden-tab check feeds opener, join, handoff and fold; group leaders never treated as standalone"
    - path: "Sources/TransomEngine/WindowTracker.swift"
      issue: "fold and close decisions keep the leftover ID"
    - path: "Sources/TransomTestSupport/FakeWindowSystem.swift"
      issue: "tabGroup/newTab put every tab at the group's current frame"
  missing:
    - "Link a newly shown tab to the tab shown just before it by timing (listed last update, unlisted now, offscreen in CG, AX-valid, not on another known Space), letting a group leader qualify; keep bounds only as a tie-break and for other hidden members"
    - "Fallback when two windows of one app hide in the same refresh: match origin and width"
    - "Fake: new tab at its own frame, hidden tabs keep their last shown frame; scenario tests for E1 and E4"
  debug_session: ".planning/debug/g-02-10-tab-group-stale-rows.md"

- gap_id: G-02-12
  truth: "A refused frame write teaches Transom the window's real minimum: Min Size shows it about a second later and min-size-hints.json stores it per bundle"
  status: failed
  reason: "Claude-driven VM run: Nudge on Notes at its 642x324 minimum moved it but the size was refused; Min Size stayed blank and no hints file was written"
  severity: major
  test: 12
  note: "Closed without a code change: wrong test setup, test 12 passes with the corrected step"
  root_cause: "Not a defect: the test started Notes exactly at its minimum; MinimumSizeLearner deliberately ignores an unmoved refusal (WR-01, CR-02). Learning, Min Size and the hints file work when the window starts 2-32 pt above its minimum (verified live, survives relaunch)"
  artifacts: []
  missing:
    - "None in code; test 12's step was corrected in this file"
  debug_session: ".planning/debug/g-02-12-minimum-not-learned.md"
