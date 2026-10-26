---
status: diagnosed
trigger: "G-03-5: with TextEdit window A docked, focused TextEdit windows B/C cannot be docked with Ctrl-Opt-Cmd-D; menu treats docked A as frontmost. split-finder with Finder 546 already open did not dock/track new Finder 580; Hide Desktop left floating Finder 546 on screen."
created: 2026-10-26T15:00:00-05:00
updated: 2026-10-26T15:50:00-05:00
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (deterministic: a window created while its app already has a remembered focused window)
hypothesis: CONFIRMED - the focus change to a NEW window is dropped, so AXWindowSystem.focusedIdentities[pid] keeps the previously focused (docked) window and focusedWindow(of:) returns it, never consulting AXMain.
next_action: none (goal find_root_cause_only); hand to plan-phase --gaps
known_pattern_candidate: none (KB holds only safari-toolbar-drag-no-dock, unrelated)
reasoning_checkpoint:
  hypothesis: "focusedWindow(of:) returns stale docked A because the AX focus hint for a new window B is lost (no cached element -> windowID nil; or pendingFocus consumed while B sits in the tracker's 250 ms settle pending set), and focusedIdentities wins over the AXMain fallback"
  confirming_evidence:
    - "VM: TextEdit 202 docked + focused, Cmd-N -> 722 (AX focused 'Untitled 5', tracked floating in layout.json); Ctrl-Opt-Cmd-D does nothing"
    - "VM: click 202 then click 722 (focus hints now name cached, tracked windows), Ctrl-Opt-Cmd-D -> 722 docks immediately"
  falsification_test: "if 722 had still failed to dock after the focus round-trip, the cause would be identity collapse or element equality, not lost focus"
  candidate_causes:
    - "code: lost focus event for new windows in AXWindowSystem (confirmed)"
    - "data: shared axIdentifier _NS:34 collapsing identities (eliminated: axIdentifier is never matched on)"
    - "config: Finder on the Never Arrange list (confirmed, explains the test-7 Finder half only)"
  and_gate: "no for G-03-5 itself; test 7's Finder symptoms are a separate, independent cause (exclusion), not a contributing condition"

## Symptoms

expected: Dock A, open B, Undo leaves B floating and dockable; keyboard and menu commands act on the app's focused (frontmost) window (CR-01).
actual: With TextEdit window A docked, focused TextEdit windows B and C ("Untitled 3", AX focused window confirmed via AX helper) cannot be docked with Ctrl-Opt-Cmd-D (nothing happens); the Pane status menu shows Dock greyed / Float enabled as if docked A were frontmost. Not Undo-specific: fresh window C fails too. Test 7: with Finder 546 open/floating, pane://split-finder opened Finder 580 but neither docked nor tracked it (never entered layout.json). Hide Desktop parked floating TextEdit windows but left floating Finder 546 on screen. split-finder worked earlier when Finder had no other window.
errors: none reported
reproduction: VM pane-test (macOS 15.7.7, Pane 0.3.1). Dock TextEdit A; open TextEdit B; focus B; Ctrl-Opt-Cmd-D.
started: observed in phase 3 UAT (HEAD 5d83032 build)
lead: layout.json TextEdit windows all appear to share axIdentifier `_NS:34`.

## Eliminated

- hypothesis: distinct windows of one app collapse into one because they share axIdentifier `_NS:34`
  evidence: WindowRef ==/hash use `identity` (windowID, pid, bundleID) only (Sources/PaneModel/IDs.swift:102-106). axIdentifier is read in WindowTracker.swift:144 and copied in World.withoutTitleHints / rekey, and nowhere else in Sources: no matching, lookup or restore code reads it. Shared `_NS:34` is cosmetic.
  timestamp: 2026-10-26T15:10:00-05:00

## Evidence

- timestamp: 2026-10-26T15:05:00-05:00
  checked: command dispatch path (ArrangeController.commandContext / dispatch; StatusItemController menu availability)
  found: Both read `system.focusedWindow(of: frontmostPid)`. AXWindowSystem.focusedWindow (AXWindowSystem.swift:278-282) returns `focusedIdentities[pid]` whenever that identity is still tracked; `mainWindowIDs[pid]` (AXMain from the latest observation) is used only when focusedIdentities[pid] is nil or untracked.
  implication: Once any window of an app has been named by a windowFocused event, the only way the "focused window" changes is another windowFocused event. A stale entry for docked A wins over the correct AXMain fallback.

- timestamp: 2026-10-26T15:08:00-05:00
  checked: how windowFocused is produced (AXAppThread.installObserver callback, AXWindowSystem.handle(hint), AXWindowSystem.refresh lines 324-330, WindowTracker.ingest lines 118-128, 183)
  found: (1) The AX focus hint's windowID is looked up in the thread's element cache (`me.windows.first { CFEqual(...) }`, AXAppThread.swift:119); a brand-new window is not in the cache yet, so the hint carries windowID nil and handle() records no pendingFocus. (2) Even when a pendingFocus ID exists, refresh() does `pendingFocus.removeValue(forKey: pid)` and emits windowFocused only if a TRACKED window matches; a new window is withheld in `pending` for settleDelay (250 ms) and is absent from sortedWindows(), so the focus is consumed and dropped. (3) When the new window later settles, the tracker emits windowCreated only (WindowTracker.swift:174-180); the only other windowFocused source is a tab switch (line 183).
  implication: The focus change to a new window B/C is lost, focusedIdentities[TextEdit] keeps docked A, so focusedWindow(of: TextEdit) = A until the user moves focus to another already-tracked window. Dock on A is unavailable (already docked) -> beep/nothing, menu shows Dock greyed / Float enabled.

- timestamp: 2026-10-26T15:20:00-05:00
  checked: Arranger.availability (Arranger.swift:396-439)
  found: .dock needs the focused window on a Desktop layer and present; .float needs it in a tree. With focused = docked A: Dock false (beep), Float true.
  implication: exactly the reported menu state "Dock greyed / Float enabled" and "Ctrl-Opt-Cmd-D does nothing".

- timestamp: 2026-10-26T15:25:00-05:00
  checked: VM state now (defaults read com.eightabyte.pane; layout.json via $S/lay; /tmp/frames)
  found: `excludedBundleIDs = ("com.apple.finder")`. layout.json desk 1: docked Terminal#160, TextEdit#202; floating finder#546, TextEdit#567, TextEdit#578, Safari#669. Finder 580 is on screen but in no desk.
  implication: Finder is on the Never Arrange list. Arranger.admit refuses excluded windows (Arranger.swift:609), takeFinderWindow needs the new window on a Desktop layer (Arranger.swift:796-797), and Hide Desktop's park loop skips excluded windows (Arranger.swift:1290, D-29). Excluded 546 stays in the desktop layer because release() keeps it there. That reproduces every test-7 Finder symptom (580 not docked, not in layout.json, still counted by the Tracked Windows model which lists excluded rows; 546 not parked) without any identity bug. Test 7's Finder half looks like a leftover Don't Arrange on Finder (from test 6 or a stray Ctrl-Opt-Cmd-E), not G-03-5. Debug-level logs are not persisted, so when it was set cannot be read back.

- timestamp: 2026-10-26T15:35:00-05:00
  checked: VM reproduction (Pane 0.3.1, pid 3259). TextEdit activated, clicked docked 202 (AX focus "Untitled 2"), Cmd-N
  found: new window 722 "Untitled 5" is AX-focused and is tracked (layout.json floating TextEdit#722:present). Ctrl-Opt-Cmd-D: no frame changes, layout unchanged.
  implication: reproduces G-03-5 without Undo; the window is tracked, so it is focus resolution, not tracking.

- timestamp: 2026-10-26T15:37:00-05:00
  checked: discriminating test: click 202 (tracked), click 722 (tracked, element now cached), Ctrl-Opt-Cmd-D
  found: 722 docks at once (598,37 143x326; layout docked Terminal#160, TextEdit#202, TextEdit#722).
  implication: CFEqual element matching and window identity work for 722; only its creation-time focus was lost. Confirms the root cause; identity collapse and element-equality hypotheses are refuted.

- timestamp: 2026-10-26T15:45:00-05:00
  checked: test-7 Finder half: quit Pane (Apple Event quit), `defaults delete com.eightabyte.pane excludedBundleIDs`, relaunch (pid 3696)
  found: finder#580 enters layout.json as floating at once; Pane clamps the Finder windows into the Desktop tile (126,37); Ctrl-Opt-Cmd-H parks Finder 546/580/731 at (1023,661) and shows them again. pane://split-finder opened Finder 731 and admitted it floating, but did not dock it: the focused window was docked TextEdit 722 whose tile is 143pt wide, below Finder's 460pt minimum, so D-26 refused (expected behaviour, not this bug).
  implication: test 7's Finder symptoms were the Finder exclusion, not G-03-5. VM state changed: Finder no longer excluded, TextEdit 722 docked, Finder 731 open.

- timestamp: 2026-10-26T15:48:00-05:00
  checked: history and tests
  found: focusedWindow(of:) was added in 10cfe52 (02-13) for the Debug-menu Nudge, then reused for every command and menu validation in phase 3 (ArrangeController.commandContext, StatusItemController.swift:276). It is not part of the WindowSystem protocol, so FakeWindowSystem and every Arranger test bypass it; the only test is the live NudgeIntegrationTests with a single fixture window, which takes the AXMain fallback.
  implication: why not caught: no test opens a second window of an app after a focus event.

## Resolution

root_cause: AXWindowSystem never records focus moving to a newly created window. The AX focus hint for a new window carries windowID nil (AXAppThread.swift:119 only matches elements already in the cache, and the new one is not cached yet), and even a hint with an ID is consumed by refresh() (AXWindowSystem.swift:326, pendingFocus.removeValue) while the window still sits in WindowTracker's 250 ms settle `pending` set, so no windowFocused is emitted; when the window settles the tracker emits only windowCreated. focusedWindow(of:) (AXWindowSystem.swift:278-282) returns focusedIdentities[pid] whenever it is still tracked and consults the correct AXMain (mainWindowIDs) only when it is not, so the previous (docked) window stays "focused" until the user moves focus between two already-tracked windows. Every hotkey, menu validation and pane:// command reads it through ArrangeController.commandContext. Test 7's Finder symptoms are a separate cause: com.apple.finder was on the Never Arrange list.
fix:
verification:
files_changed: []
