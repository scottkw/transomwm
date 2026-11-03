---
status: resolved
trigger: "Phase 7 VM UAT bugs: (1) activating an app whose focused window is already a group's hidden member (⌘Tab, open -a, Dock) gives Transom no focus event, so D-08 and the strip raise never run; (2) open \"transom-debug://next-tab\" (no -g) is refused \"not in a tab group\" because macOS activates Transom to deliver the URL. Optional: N2 should count parked members (V7)."
created: 2026-11-02
updated: 2026-11-02
---

## Current Focus

bug_class: Bohrbug (deterministic)
hypothesis: confirmed (see Resolution)
next_action: none; host hardware items 1-5 and B1-B3 in 07-UAT.md remain for the user
reasoning_checkpoint:
  hypothesis: "Bug 1: no code path turns NSWorkspace.didActivateApplication into .windowFocused, so an activation that keeps the app's focused window (a parked hidden tab) never reaches Arranger.activated/raisedStrip. Bug 2: commandContext() reads NSWorkspace.frontmostApplication, which is Transom when `open` activates it to deliver the URL, and Transom's own pid has no tracked focused window."
  confirming_evidence:
    - "VM red run: fixture app activated with its parked window key, window stayed at 1023,687 and selected stayed 1 (.build/0714-vm-red.log)"
    - "Guest watcher: `open` (no -g) activates Transom Debug before the URL is handled (activated Transom Debug at .355, select at .374)"
    - "Code: AXWindowSystem.handle hints only kAXFocusedWindowChanged/kAXMainWindowChanged; commandContext pid = frontmostApplication"
  falsification_test: "If the activation hook were not the cause, the VM test would stay red with it enabled; if Bug 2 were elsewhere, `open` (no -g) would still refuse with the fix. Both went green."
  fix_rationale: "Adds the missing event source (activation → PendingFocus → the same .windowFocused path, so D-08 and the 1 s suppression apply unchanged) and gives URL commands the app the user was in, not Transom."
  blind_spots: "Dock click and `open -a` not re-run (same NSWorkspace activation path as ⌘Tab); a real hardware ⌘Tab not tried; macOS 14 and 27 not tried (VM is 15.7.7)."
  candidate_causes:
    - "code: missing activation → focus path (confirmed)"
    - "environment: macOS sends no focused-window change on activation when the focused window stays the same (OS behaviour, the trigger; not changeable)"
    - "config: none (no setting gates focus observation)"
  and_gate: "yes for Bug 1 — the OS sends no AX focus notice on such an activation AND Transom had no other source; fixed on the Transom side. Bug 2: no, one cause."

## Symptoms

expected: (1) ⌘Tab / `open -a` / Dock click to the app of a hidden tab selects that tab (D-08) and its window fills the content rect; clicking a group's window from another app raises its strip. (2) `open "transom-debug://next-tab"` with a group's window focused selects the next tab, as `open -g` does.
actual: (1) the app becomes frontmost but its window stays parked at the 1 pt sliver (1023,689) as AXMain/key; no log line, no select; the strip stays covered (V1 cross-app click). (2) log "refused next tab: not in a tab group"; Transom Debug becomes frontmost.
errors: none (silent); (2) logs "refused next tab: not in a tab group"
reproduction: VM (Tart pane-test, macOS 15.7.7). (1) group of two fixture windows from different fixture apps; select the other app's tab; ⌘Tab to the hidden member's app. (2) focus a group member; `open "transom-debug://next-tab"`.
started: Phase 7 (tab groups are new); found in the VM UAT run 2026-11-02 (07-UAT.md V1, V3, V13)

## Eliminated

- hypothesis: optional N2 fix is a few lines
  evidence: Notice.crashRecovered has only `unplaced` (windows the saved layout did not hold); N2 never had a rescued/parked count, even in Phase 4 ("also brings parked windows back", no count). Counting parked members needs a new Notice field, new N2 copy (a copy decision the UAT left to the user), NoticeQueue and test updates — skipped
  timestamp: 2026-11-02

## Evidence

- timestamp: 2026-11-02
  checked: knowledge base (.planning/debug/knowledge-base.md)
  found: one entry (safari-toolbar-drag-no-dock), unrelated
  implication: no known-pattern candidate

- timestamp: 2026-11-02
  checked: AXWindowSystem.handle(_:) (L569-575), AppRegistry, ArrangeController activation observer (startWatchdog)
  found: focus is hinted only for kAXFocusedWindowChangedNotification / kAXMainWindowChangedNotification. AppRegistry's didActivateApplication only (re)starts app threads; ArrangeController's only ends pick mode / interrupts the overview / ticks the watchdog. No path turns an activation into .windowFocused
  implication: an activation that keeps the app's focused window (hidden tab = its key window) never reaches Arranger.activated (D-08) or raisedStrip (V1, V3 confirmed by code)

- timestamp: 2026-11-02
  checked: Arranger .windowFocused (Arranger.swift ~L877) and activated()/raisedStrip (Arranger+Tabs.swift ~L537-565)
  found: engine already selects a hidden member on .windowFocused (unless pendingReveal or within focusSuppression 1 s) and raises the selected member's strip
  implication: fix belongs in the shell (event source), not the engine; the 1 s suppression stays as is because activation-sourced events take the same .windowFocused path

- timestamp: 2026-11-02
  checked: PendingFocus + refresh(): a no-ID hint resolves through AXMain read on the app's own AXAppThread (global AX timeout 1 s), after a 75 ms debounced refresh
  found: reusing that path gives "read the activated app's focused window off main with the existing timeout" for free; AX hint + activation within the debounce collapse into one hint
  implication: fix = PendingFocus.activated(pid:) + schedule refresh; dedup the rare case where the refresh runs between the two notices (same window, <500 ms, activation on either side)

- timestamp: 2026-11-02
  checked: ArrangeController.commandContext() (L519) and dispatch(_:from:) / dispatchCamera
  found: focused = system.focusedWindow(of: NSWorkspace.frontmostApplication.pid); with Transom frontmost (no thread for its own pid) it is nil → tab commands refuse "not in a tab group". Camera .frameWindow from a URL has the same flaw
  implication: Bug 2 root cause confirmed by code; fix = URL source uses the last non-Transom frontmost pid when Transom itself is frontmost

- timestamp: 2026-11-02
  checked: VM red run, new test with the AXWindowSystem hook disabled (.build/0714-vm-red.log)
  found: fixture 0 became frontmost with its parked window key ("frontmost index=0"), yet window 0 stayed at 1023,687 500x642 and the group kept selected 1
  implication: reproduces V3 exactly with fixtures; the missing activation → focus path is the cause (AND-gate: no — one missing event source)

- timestamp: 2026-11-02
  checked: VM green run, whole TabGroupIntegrationTests with the hook (.build/0714-vm-TabGroupIntegrationTests.log)
  found: "Test run with 6 tests in 1 suite passed after 14.044 seconds"; the new test passed in 3.1 s; minimizeGroupWithTwoWindowsOfOneAppStaysMinimized (WR-02, suppression path) still passes
  implication: fix 1 verified live; the 1 s suppression path unaffected

- timestamp: 2026-11-02
  checked: host full swift test after fix 1 (.build/0714-host-full-fix1.log); scripts/check-no-appkit.sh
  found: 219 + 390 + 94 + 966 tests passed, exit 0; PendingFocusTests ran (14 tests); no-appkit OK (55 files)
  implication: no host regression

- timestamp: 2026-11-02
  checked: VM regression suites after fix 2 (.build/0714-vm-TabStripSpaceIntegrationTests.log, .build/0714-vm-FocusParkIntegrationTests.log)
  found: "Test run with 1 test in 1 suite passed after 2.292 seconds"; "Test run with 2 tests in 1 suite passed after 2.261 seconds"
  implication: SavedGroup refactor and focus path unaffected

- timestamp: 2026-11-02
  checked: real-app guest check, rebuilt Transom Debug (sha1 ff9b4638…) in /Applications of the guest, Desktop 2, fixtures fa (A) / fb (B), floating group n30 formed by a drag with an 800 ms rest; log .build/0714-vm-check/transom.log; activations from a throwaway NSWorkspace watcher
  found: (Bug 2) B focused, `open "transom-debug://next-tab"` (no -g): "group n30: select window 4335 … via url, 4 ms", no refusal; repeated with the watcher: "activated Transom Debug pid=25832" at .355, then the select of 4340 "via url, 5 ms" and fb activated at .380 — the URL arrived with Transom frontmost and acted on the previous app. (Bug 1) ⌘Tab (synthetic) from fb to fa, whose key window was the parked A: "activated TransomFixtureApp pid=25802" at .461, "select window 4335 … via activation, 6 ms" at 41.552, A at 40,112 320x200 (content rect), B parked at 1023,687. (V1) third fixture C raised over the strip (CG: C, A, strip); a click on A's uncovered part gave CG order strip, A, C
  implication: both bugs fixed in the shipped app path; V1's strip raise works through the same activation path

- timestamp: 2026-11-02
  checked: guest state after cleanup
  found: Transom Debug quit, fixtures/log stream/watcher gone; layout.json, min-size-hints.json and com.eightabyte.transom.debug defaults cmp-equal to the pre-run backups; previous /Applications/Transom Debug.app restored (sha1 52c7fc84…); back on Desktop 1 (TextEdit Untitled 2-5, Finder windows on screen); a left Control key state (59) left by the synthetic ⌃←/⌃→ was cleared with a flagless key-up, `mods` shows none held
  implication: guest left as found

## Resolution

root_cause: "Bug 1: AXWindowSystem turned only kAXFocusedWindowChanged / kAXMainWindowChanged into focus hints, and macOS sends neither when an activation (⌘Tab, Dock, `open -a`, a cross-app click on the app's already-focused window) keeps the app's focused window; so Arranger never got .windowFocused and D-08 selection / strip raise never ran; Bug 2: ArrangeController.commandContext() took the focused window of NSWorkspace.frontmostApplication, which is Transom itself once LaunchServices activates it to deliver a URL, and Transom's own pid is never tracked"
fix: "5a48451: AXWindowSystem observes NSWorkspace.didActivateApplication → PendingFocus.activated(pid:) + debounced refresh; the hint resolves through AXMain read on the app's AX thread; an activation and the AX notice of one change make one windowFocused (pending AX hint wins; repeat within 500 ms with an activation on either side dropped; another app's unresolved activation dropped). bdd2d22: AXWindowSystem.lastOtherFrontmostPID (last non-Transom app to become frontmost, seeded at start); commandContext(from: .url) uses it when Transom is frontmost (ArrangeController.commandPID); hotkeys/menu unchanged"
verification: "Host full swift test 219+391+94+966 passed (.build/0714-host-full-fix2.log), check-no-appkit OK; PendingFocusTests 14 (5 new), AppDelegateTests.aURLActsOnTheAppFrontmostBeforeTransom; VM TabGroupIntegrationTests new test red without the hook, then 6/6 passed; VM TabStripSpaceIntegrationTests 1/1, FocusParkIntegrationTests 2/2; real Debug app in the guest: `open` (no -g) next-tab selects via url, ⌘Tab selects the hidden member via activation, cross-app click raises the covered strip"
oracle_type: specified (UI-SPEC Surface 3 D-08 and Surface 7 URL rules; tests assert the selected tab, the shown/parked frames and the chosen pid)
guardrail_verdict: accepted (failing-first VM test, unit tests kill the dedup/selection mutants, minimal diffs, no deletions)
files_changed: [Sources/TransomEngine/PendingFocus.swift, Sources/TransomMac/AXWindowSystem.swift, Sources/TransomMac/ArrangeController.swift, Tests/TransomEngineTests/PendingFocusTests.swift, Tests/TransomMacTests/AppDelegateTests.swift, Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift]
