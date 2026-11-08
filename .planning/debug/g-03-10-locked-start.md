---
status: diagnosed
trigger: "G-03-10 (SAFE-06 / CR-03): Pane started while the screen is locked; after unlock ('session resumed after a full refresh') the shown Space 1 desk lost all 3 docked tiles (Terminal 160, TextEdit 202, TextEdit 578 became floating, frames unmoved); hidden Space 41 desk kept"
created: 2026-10-27T00:00:00Z
updated: 2026-10-27T00:45:00Z
goal: find_root_cause_only
audit_acknowledged:
  milestone: v0.9.0
  at: 2026-11-08
  status: diagnosed
---

## Current Focus

bug_class: Bohrbug (deterministic: every start while locked; headless repro fails every run, its unlocked control passes)
hypothesis: CONFIRMED (H1). A start while locked consumes the initial sweep without observing anything, so the post-resume full refresh is a non-initial sweep and WindowTracker withholds every window for its 250 ms settle. The first unpaused inventory, which ArrangeController feeds on .sessionPaused(false) because awaitsRestore, passes the CR-03 guard with windows [] and a full CG list; reattach then removes every saved window on the shown Space (hidden-Space ones survive as dormant via the isAlive filter), and the settle refresh 250 ms later admits them as new floaters at their current (old tile) frames.
next_action: none (goal find_root_cause_only); hand back ROOT CAUSE FOUND

reasoning_checkpoint:
  hypothesis: "Shown-Space saved windows are removed because the restore runs on the first unpaused inventory after a locked start, and that inventory tracks no window: AXWindowSystem spent its only initial sweep (sweep(initial: true)) while paused, observing nothing, and the post-resume refreshAll is sweep(initial: false), so WindowTracker.ingest withholds every first-seen window for settleDelay"
  confirming_evidence:
    - "Code: AXWindowSystem.start sets initialRefreshComplete = true after a sweep whose every refresh returned at `guard !paused` (AXWindowSystem.swift:131-132, 324); sessionDidResume runs refreshAll() -> sweep(initial: false) then sets sessionPaused = false (564-569); WindowTracker.ingest withholds old == nil && !initialSweep windows (WindowTracker.swift:120-128)"
    - "Headless probe (new fake locked during its first refreshAll, then unlock + refreshAll, then the inventory): resumed inventory tracked=[] live=[1@[1], 3@[2]]; after restore A1 docked [] (saved docked [1]), A2 docked [3]; settle refresh -> A1 floating [1], frame unchanged. Same probe unlocked: passes"
    - "Differential: same locked start, but the inventory fed only after the 300 ms settle refresh (tracked=[1]) -> world == saved. The only difference is whether window 1 was tracked at the restore instant"
    - "VM symptom matches the predicted split exactly: shown Space 1 emptied, hidden Space 41 kept, Space 1 windows floating at unmoved frames, no log line (reattach removal and admit log nothing)"
  falsification_test: "If the restore ran on an inventory that already tracked the Space 1 windows (or ran while still paused), world would equal saved; the probe shows tracked=[] at the restore and world != saved, and feeding after the settle makes it pass"
  fix_rationale: "The CR-03 guard trusts `initialRefreshComplete` to mean every app's first answer is in the tracker. After a locked start it is true although nothing was observed and the next sweep is not initial. Making the first unpaused full sweep the initial one (and initialRefreshComplete true only after it) puts every window in the tracker in the same sweep, before .sessionPaused(false), so the existing restore guard waits correctly"
  blind_spots: "Not reproduced live on the VM (needs a locked screen; the VM run already shows the symptom). Not checked: a lock that starts AFTER the initial sweep but before the first inventory is fed; apps whose post-unlock AX reads fail (would also leave them untracked -> same removal); a slow app whose settle follow-up lands before .sessionPaused(false) (it would be tracked and survive, so partial survival is possible live)"
  candidate_causes:
    - "code (AXWindowSystem): the initial sweep is consumed while paused; post-resume sweep is non-initial (confirmed)"
    - "code (WindowTracker): settle withholding of first-seen windows outside the initial sweep (confirmed contributor; correct on its own)"
    - "code (Arranger/LayoutRestore): reattach closes untracked shown-Space windows; CR-03 guard does not check that windows are tracked (confirmed contributor)"
    - "environment: synthetic IDs / _AXUIElementGetWindow failing while locked (eliminated)"
    - "environment: currentSpaceID unknown while locked (eliminated)"
    - "code: events placing windows while pendingRestore waits (eliminated)"
  and_gate: "yes: needs (a) the initial sweep spent while paused, (b) the tracker's settle withholding on a non-initial sweep, and (c) reattach removing untracked windows on a shown Space with the restore firing on the first unpaused inventory. Remove any one and the shown desk survives (the differential shows removing (b)'s effect at the restore instant is enough). Not caught (d): the CR-03 test hand-blanks an inventory of a fake whose initial sweep ran unlocked"

## Symptoms

expected: Starting Pane while the screen is locked keeps every saved desk once the screen is unlocked (SAFE-06, CR-03)
actual: VM, Pane 0.3.8 (HEAD 9c6727d code). Saved layout: Space 1 desk docked [Terminal#160, TextEdit#202, TextEdit#578] + floaters; Space 41 (hidden) docked [Notes#150], floating [Reminders#693, Calculator#2352]. Launched while locked: log 'permission ready', then '[ax] session paused: locked or asleep'; layout.json kept (only launch metadata). ~8 min later unlock: '[ax] session resumed after a full refresh', nothing else logged. Space 1 desk docked [], Terminal/TextEdit 202/578 floating 'present', frames never moved. Space 41 desk unchanged and correct.
errors: none logged
reproduction: VM pane-test: Space 1 shown, quit Pane cleanly; Ctrl-Cmd-Q lock; launch Pane while locked; wait; unlock; read layout.json
started: first VM check of the CR-03 locked-start path (08d5f30)

## Eliminated

- hypothesis: windows are placed by another event path (windowCreated / place()) while pendingRestore waits, so reattach sees them as already tracked "unplaced" and floats them
  evidence: Arranger.process(.event) returns [] while pendingRestore != nil (Arranger.swift:244); while locked AXWindowSystem.refresh returns at `guard !paused` so no windowCreated exists; the probe's post-resume refresh emits 0 events and the resumed inventory tracks []. The windows are removed by reattach first and admitted as new only afterwards
  timestamp: 2026-10-27T00:40Z

- hypothesis: reattach removes them because they are tracked under synthetic IDs (_AXUIElementGetWindow failing while locked)
  evidence: nothing is observed at all while paused (refresh guard), so nothing is tracked under any ID before the unlock; the probe uses axPrivate IDs throughout and still fails with tracked=[]. The windows are missing from `real` because they are not tracked, not because of their ID source
  timestamp: 2026-10-27T00:40Z

- hypothesis: displays' currentSpaceID is unknown or wrong while locked, so the shown Space is misjudged
  evidence: refreshAll re-reads displays before the resume inventory, and Arranger keeps the previous Space on nil. An unknown shown set would make `live` keep the Space 1 entries (spaces disjoint from an empty set), i.e. keep them dormant, the opposite of the symptom. The observed split (Space 1 lost, Space 41 kept) requires shown = {1}
  timestamp: 2026-10-27T00:40Z

- hypothesis: the restore ran while still paused / on the launch inventory
  evidence: the CR-03 guard holds on the paused launch inventory (probe: awaitsRestore=true after it), and AXWindowSystem keeps sessionPaused true until refreshAll finished; layout.json was untouched while locked (VM)
  timestamp: 2026-10-27T00:40Z

## Evidence

- timestamp: 2026-10-27T00:10Z
  checked: KB (.planning/debug/knowledge-base.md) and sibling g-03-8-hidden-space-relaunch.md
  found: no KB match on locked/restore; G-03-8 is the same reattach() removal path (a saved window not tracked at the restore instant is closed unless isAlive in the CG list)
  implication: candidate: something makes the shown Space's windows untracked at the instant the waiting restore finally runs

- timestamp: 2026-10-27T00:15Z
  checked: Sources/PaneMac/AXWindowSystem.swift start() (~89-139), sweep (~291-317), refresh(pid:) (~321-345), sessionDidPause/Resume (~544-571), inventory() (~148-154)
  found: start(): gate.evaluate() pauses (locked) -> sweep(initial: true): liveWindows = nil (paused) and every refresh(pid:) returns at `guard !paused` (no observation reaches the tracker); initialRefreshComplete = true regardless. sessionDidResume: after 1.5 s quiet, refreshAll() -> sweep(initial: false), then sessionPaused = false and yield .sessionPaused(false). No later sweep is ever run with initial: true.
  implication: the only refresh with initialSweep true happened while locked and observed nothing; the first real observation of every window is a non-initial one.

- timestamp: 2026-10-27T00:17Z
  checked: Sources/PaneEngine/WindowTracker.swift ingest lines 120-128
  found: `if old == nil, !context.initialSweep { ... guard context.now >= firstSeen + settleDelay else { pending[identity] = firstSeen; continue } }` -> a window first seen outside the initial sweep is withheld (not in `windows`, no windowCreated) until a refresh at least settleDelay (250 ms) later; ingest then schedules that follow-up refresh (AXWindowSystem.ingest hasPendingWindows -> schedule after settleDelay).
  implication: right after the post-resume full refresh, tracker.sortedWindows() is EMPTY although the CG list (liveWindows) is full.

- timestamp: 2026-10-27T00:19Z
  checked: Sources/PaneMac/ArrangeController.swift start() event loop lines 121-139; Arranger.process(.inventory) lines 199-235
  found: on the .sessionPaused(false) event the loop reads inventory() and feeds it because awaitsRestore. That inventory passes the CR-03 guard (initialRefreshComplete true, sessionPaused false, liveWindows non-empty). real = {} (no tracked windows). shown = {1}; `live` keeps only CG entries whose spaces are disjoint from shown (Space 41 windows). reattach(..., live:) then closes every saved window that is neither in real nor alive in that filtered list: Terminal 160, TextEdit 202/578 (Space 1). Notes 150 / Reminders 693 / Calculator 2352 (Space 41) are kept dormant. pendingRestore = nil, so the restore never runs again.
  implication: exactly the observed split (shown Space emptied, hidden Space kept). The later windowCreated events (after the 250 ms settle) go through handle(.windowCreated) -> admit() as new windows, which floats them on their desk's Desktop without moving them ("floating present, frames unmoved"), and nothing is logged (reattach removal and admit log nothing).

- timestamp: 2026-10-27T00:35Z
  checked: headless probe, temporary Tests/PaneEngineTests/ZZG0310ProbeTests.swift (moved to scratchpad g310/; output in scratchpad g310/probe-output.txt). Session 1: window 1 docked on Space 1, window 3 docked on Space 2, back to Space 1. Relaunch on a NEW FakeWindowSystem, Space 1 shown, setLocked(true) before its first refreshAll (= AXWindowSystem.start's sweep while paused), .restore(saved), launch inventory, then setLocked(false) + refreshAll (= post-resume full refresh) + inventory (= ArrangeController's feed on .sessionPaused(false)), then advance 300 ms + refresh (= the settle follow-up). `swift test --filter ZZG0310`: 2 tests, 3 cases ran
  found: locked=true: launch inventory paused=true tracked=[] -> awaitsRestore=true; post-resume refresh events 0; resumed inventory paused=false tracked=[] live=[1@[1], 3@[2]]; after restore A1 docked [] floating [], A2 docked [3] (dormant); settle refresh -> A1 docked [] floating [1], window 1 frame unchanged (its old tile, 8,33 708x859). Two expectations fail (world == saved; A1 docked [1]). locked=false (control): launch inventory tracked=[1], world == saved, passes
  implication: deterministic headless reproduction of the VM symptom, including "hidden Space kept", "shown Space docked windows come back floating" and "frames unmoved"

- timestamp: 2026-10-27T00:38Z
  checked: differential probe lockedStartRestoresIfFedAfterTheSettleRefresh: same locked start, but the settle refresh (windowCreated 1) runs before the inventory is fed
  found: inventory tracked=[1]; after restore A1 docked [1], A2 docked [3]; world == saved; passes
  implication: the only factor is that the shown-Space windows are not yet tracked at the restore instant; the CG list, Spaces, IDs and lock state are otherwise identical

- timestamp: 2026-10-27T00:42Z
  checked: why CR-03's test misses it: Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift aRestoreWaitsForAnUnlockedSessionAndANonEmptyCGList (~412-436), relaunched() (~45-58); FakeWindowSystem.refreshAll (391) and inventory() (404)
  found: relaunched() runs the new fake's first refreshAll UNLOCKED, so window 1 is tracked by the initial sweep. The locked case then hand-blanks a copy of that inventory (sessionPaused true, windows [], liveWindows nil) and follows it with the fake's real inventory, which already tracks window 1. It never models a locked initial sweep followed by a non-initial post-resume sweep. The fake itself can model it (refreshAll sets initialSweepDone even while locked, like AXWindowSystem), but no test locks it before the first refreshAll (only setLocked uses: ArrangerMultiDeskRestoreTests:315 mid-session, CloseScenarioTests:57 after the initial sweep). The fake's inventory also hard-codes initialRefreshComplete: true. AXWindowSystem's start-while-locked/resume path has no headless test
  implication: the test checks the Arranger guard against a hand-made blind inventory, not the shape of the first usable inventory a locked start really produces


root_cause: "AND of three code facts. (1) AXWindowSystem.start() runs its only initial sweep (sweep(initial: true), AXWindowSystem.swift:131) while the session gate is paused: every refresh(pid:) returns at `guard !paused` (324), so the tracker observes nothing, yet initialRefreshComplete is set true (132). On unlock, sessionDidResume runs refreshAll() = sweep(initial: false) (564) and then ends the pause and yields .sessionPaused(false) (567-569). (2) In that non-initial sweep WindowTracker.ingest withholds every first-seen window for settleDelay (WindowTracker.swift:120-128), so the tracker is still empty when the pause ends. (3) ArrangeController feeds the inventory on .sessionPaused(false) because awaitsRestore (ArrangeController.swift:131); it passes the CR-03 guard (Arranger.swift:211: initialRefreshComplete, not paused, CG list non-empty) with windows [], so real = [] (215); `live` keeps only CG entries on Spaces not shown (220); reattach (225, LayoutRestore.swift:22) closes every saved window of the shown Space and keeps the hidden Space's as dormant. pendingRestore is cleared (212), so it never retries. 250 ms later the settle refresh reports those windows as windowCreated and admit() (Arranger.swift:712) floats them at their current (old tile) frames; nothing is logged. CR-03's test missed it because it hand-blanks an inventory from a fake whose initial sweep ran unlocked, then feeds an inventory that already tracks the shown-Space window."
fix: ""
verification: ""
files_changed: []
