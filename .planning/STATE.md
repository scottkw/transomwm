---
gsd_state_version: "1.0"
current_phase: 4
current_phase_name: Zoom Camera
status: executing
stopped_at: Completed 04-06-PLAN.md
last_updated: "2026-10-28T15:48:03.799Z"
last_activity: 2026-10-27
last_activity_desc: Phase 4 execution started
state_head: f7dd57df082f190c56eb91155026bfdd8080e6bc
progress:
  total_phases: 9
  completed_phases: 3
  total_plans: 59
  completed_plans: 57
  percent: 33
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, this must still work.
**Current focus:** Phase 4 — Zoom Camera

## Current Position

Phase: 4 (Zoom Camera) — EXECUTING
Plan: 7 of 8
Status: Ready to execute
Last activity: 2026-10-27 — Phase 4 execution started

Progress: [███░░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 51
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 6 | - | - |
| 3 | 26 | - | - |
| 2 | 19 | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 1 P01 | 6 min | 2 tasks | 10 files |
| Phase 1 P02 | 5 min | 2 tasks | 3 files |
| Phase 01 P03 | 7 min | 3 tasks | 5 files |
| Phase 01 P04 | 7 min | 3 tasks | 7 files |
| Phase 01 P06 | 2min | 2 tasks | 5 files |
| Phase 01 P05 | 5 min | 3 tasks | 8 files |
| Phase 2 P01 | 14 min | 3 tasks | 22 files |
| Phase 2 P02 | 6 min | 2 tasks | 11 files |
| Phase 2 P03 | 14 min | 3 tasks | 28 files |
| Phase 2 P04 | 4 min | 2 tasks | 4 files |
| Phase 2 P05 | 9 min | 3 tasks | 12 files |
| Phase 2 P06 | 10 min | 2 tasks | 13 files |
| Phase 2 P07 | 10 min | 2 tasks | 9 files |
| Phase 2 P08 | 10 min | 3 tasks | 13 files |
| Phase 2 P09 | 19 min | 3 tasks | 16 files |
| Phase 2 P10 | 11 min | 2 tasks | 9 files |
| Phase 2 P11 | 10 min | 2 tasks | 14 files |
| Phase 2 P12 | 10 min | 2 tasks | 12 files |
| Phase 2 P13 | 11 min | 3 tasks | 16 files |
| Phase 2 P14 | 23 min | 3 tasks | 16 files |
| Phase 2 P15 | 8 min | 2 tasks | 10 files |
| Phase 2 P16 | 19 min | 3 tasks | 16 files |
| Phase 2 P17 | 8 min | 2 tasks | 9 files |
| Phase 3 P01 | 9 min | 2 tasks | 17 files |
| Phase 03 P02 | 6min | 3 tasks | 7 files |
| Phase 03 P03 | 5min | 2 tasks | 7 files |
| Phase 03 P04 | 27min | 3 tasks | 16 files |
| Phase 3 P05 | 8 min | 2 tasks | 12 files |
| Phase 3 P06 | 20 min | 2 tasks | 13 files |
| Phase 3 P07 | 11 min | 2 tasks | 15 files |
| Phase 3 P08 | 17min | 2 tasks | 16 files |
| Phase 03 P09 | 9min | 2 tasks | 17 files |
| Phase 03 P10 | 13 min | 3 tasks | 17 files |
| Phase 3 P11 | 26 min | 3 tasks | 21 files |
| Phase 03 P12 | 13min | 3 tasks | 16 files |
| Phase 3 P13 | 17 min | 3 tasks | 21 files |
| Phase 3 P14 | 13 min | 3 tasks | 22 files |
| Phase 03 P15 | 10 min | 2 tasks | 15 files |
| Phase 3 P16 | 11 min | 3 tasks | 19 files |
| Phase 03 P17 | 13h wall (checkpoint wait) | 3 tasks | 3 files |
| Phase 03 P25 | 30min | 3 tasks | 7 files |
| Phase 03 P26 | 5 min | 2 tasks | 7 files |
| Phase 02 P18 | 6min | 1 tasks | 3 files |
| Phase 2 P19 | 8 min | 2 tasks | 7 files |
| Phase 4 P01 | 8h 34m | 3 tasks | 12 files |
| Phase 04 P02 | 15 min | 2 tasks | 8 files |
| Phase 4 P03 | 92 min | 3 tasks | 8 files |
| Phase 4 P04 | 29 min | 3 tasks | 16 files |
| Phase 04 P05 | 9min | 3 tasks | 13 files |
| Phase 04 P06 | 14 min | 3 tasks | 12 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Keep PLAN.md's 9 phases and order; apply research scope moves (display UUID/coords and native-tab detection into Phase 2; crash restore, edge-tiling detection and a minimal signed + notarised pipeline into Phase 3)
- Roadmap: Phase 3 is the first usable release, gated on TILE-10 (tiling works with zoom and Screen Recording off)
- Roadmap: WIN-07 (fullscreen tile return) mapped to Phase 3, where tiles exist; Phase 2 only detects fullscreen state
- Roadmap: SAFE-03 in Phase 3 registers `pane://` with `restore` only; Phase 8 (VIEW-03) generalises URL commands
- Roadmap: SAFE-04 (all three conflicting macOS features) lands in Phase 3; Phase 9 onboarding (SHIP-02) surfaces it on first run
- Roadmap: User chose basic layout restore in Phase 3 (SAFE-06, same window IDs); VIEW-04 narrowed to reboot/app-relaunch re-matching in Phase 8
- [Phase 1]: Tree depth counts edges from the root (root = 0); maxDepth 64 accepts a 64-split chain, rejects 65
- [Phase 1]: LayoutTree storage is public internal(set) so TreeEdits.swift can write it; read-only outside PaneModel
- [Phase 1]: Persisted World JSON: sortedKeys, states/desks as sorted record arrays, NodeID as bare number / decimal key; duplicate records rejected
- [Phase 1]: Phase 1 commits live on branch gsd/phase-01-layout-model because main is protected
- [Phase 1]: normalize() throws splitFull when a same-axis merge would exceed maxChildren; the edit rolls back
- [Phase 1]: normalize() leaves already-normalised weights bit-identical, so resizeBoundary can call it and keep D-07
- [Phase 01]: resolve never changes stored weights; unfit windows are chosen greedily (largest minimum on the violated axis, ties to larger NodeID then identity) and re-admitted in removal order wherever they fit
- [Phase 01]: Drop zones: tile centre is [0.25, 0.75] on both axes; layout edge is < 24 pt from the area edge; constants tuned in Phase 3 UAT
- [Phase 01]: Desk edits go through transactional World.edit; undo validates the restored World and never rewinds IDSource
- [Phase 01]: UndoHistory is session-only (not Codable); 50 Desk snapshots per desk
- [Phase 01]: Version-1 files decode original bytes; older files migrate via MigrationChain through JSONSerialization (precision caveat above 2^53)
- [Phase 01]: 01-06: PaneEngine value types have explicit public inits so Phase 2 modules can construct them; WindowEvent/WindowCommand are Equatable, Sendable
- [Phase 01]: 01-06: no-AppKit guardrail is scripts/check-no-appkit.sh, run by NoAppKitTests in every swift test and by CI on macos-26
- [Phase 01]: group(_:into:) checks duplicate identity before target, matching insert; floating-into-tree duplicates are caught by World.edit validation
- [Phase 01]: Lifecycle setState changes states only; .closed delegates to remove; DesktopLayer refuses to store .closed (two-source close contract documented for Phase 2)
- [Phase 2]: AXAppThread.init returns once the run loop exists; AX observer registration (IPC) happens on the thread afterwards so a hung app never blocks main
- [Phase 2]: WindowTracker keeps a window's known kind while it is absent (minimised/hidden subrole reads AXDialog)
- [Phase 2]: Fixture stdin protocol: a command's window lines precede its ok/error line; launch reads windows via list; stdin EOF quits the fixture
- [Phase 2]: XcodeGen rewrites Pane.entitlements on every generate, so project.yml declares app-sandbox=false under entitlements.properties
- [Phase 2]: Manual Developer ID signing of Debug works with no profile; target scheme: {} makes xcodebuild -scheme Pane resolve (A4 confirmed)
- [Phase 2]: StatusItemController consumes AXWindowSystem.events; a second consumer must fan the stream out
- [Phase 2]: FakeWindowSystem's first refreshAll() is the initial sweep; later new windows wait out the 250 ms settle, so fake scenarios must advance(by:) and refresh again
- [Phase 2]: Classifier: provisional kinds (first seen minimised/hidden/under a sheet) are replaced in full at the first reliable observation; disabled-button stickiness applies only to reliable dockable windows
- [Phase 2]: Corpus finding: org.libreoffice.script joined fullscreenButtonOptional (Start Center labelled dockable, no fullscreen button); developer to confirm in UAT
- [Phase 2]: AXSnapshotReader and CGWindowList are public so pane-dump records the exact live snapshot
- [Phase 2]: LifecycleSync is the only path from OS lifecycle events into the World (World.apply only); .closed uses a placeholder DeskKey since apply ignores it
- [Phase 2]: Undo runs LifecycleSync.undo -> requery (windowInfo nil = .closed) -> applyRequeried; windowCreated is not a lifecycle fact (placement is Phase 3)
- [Phase 2]: 02-05: a trusted launch waits for its AX probe before deciding to show Set Up Pane, so a working grant never flashes the window
- [Phase 2]: 02-05: the permission probe treats only -25211 as stale; -25204 retries; any other AX answer counts as success
- [Phase 2]: AppRegistry.onStop carries (pid, terminated) so appTerminated is emitted only for a quit, not for a policy change
- [Phase 2]: refreshAll() re-reads displays and re-checks app eligibility before refreshing; the 5 s sweep and the 500 ms display refresh go through it
- [Phase 2]: The AX hint loop starts only after the initial sweep; apps running at start() get threads but no appLaunched
- [Phase 2]: 02-07: a degraded app is probed by its own 2 s loop, not the 5 s sweep, so a resumed app recovers within about 2 s
- [Phase 2]: 02-07: observe() times the whole job, so one SIGSTOPped job (~2 s) degrades an app at once; production detection is at most the 5 s sweep plus about 2 s
- [Phase 2]: 02-07: one in-flight AX job per pid with one coalesced follow-up; refreshes for a degraded app are dropped
- [Phase 2]: 02-08: Tracked Windows gets inventories via StatusItemController.onInventory; system.events keeps one reader
- [Phase 2]: 02-08: ExclusionStore is an ObservableObject; onChange is left for Plan 13 enforcement
- [Phase 2]: 02-08: Tracked Windows footer segments after apps count rows (windows)
- [Phase 2]: 02-08: NSAlert has no hasDestructiveAction; Freeze button carries it, Esc mapped to Cancel by a local key monitor
- [Phase 2]: 02-08: a frozen app is resumed on willTerminate and by resumeRecordedPID() at every launch
- [Phase 2]: 02-09: a known window's state comes only from CloseRule; a new window starts from its snapshot
- [Phase 2]: 02-09: a .recheck triggers a follow-up refresh after 250 ms, at most 8 in a row (WindowServer drops a closed window ~0.3 s after AX reports -25202)
- [Phase 2]: 02-09: windows that left AXWindows stay in the AXAppThread element cache while tracked, so each refresh probes them
- [Phase 2]: 02-09: a quit app's windows are rechecked every 250 ms for 5 s, then after every refresh
- [Phase 2]: 02-09: A3 confirmed on macOS 27 while locked: CGSSessionScreenIsLocked = 1, frontmost com.apple.loginwindow
- [Phase 2]: 02-09: PaneFixtureApp frees a closed NSWindow; a kept NSWindow keeps its CG entry
- [Phase 2]: 02-10: A native tab group is one tracked window under its first-seen tab's identity; visibleMemberID (set on every window) names the shown tab and is what Phases 3-4 must address
- [Phase 2]: 02-10: Close decisions go through the shown tab; a group survives a closed tab while any member is still in the CG list and is destroyed only with its last member
- [Phase 2]: 02-11: capability session state is a CapabilitySession instance (Capabilities.session shared); tests build their own so they never switch the lookup off for integration tests in the same process
- [Phase 2]: 02-11: synthetic CG presence is one-to-one; windows AX lists this refresh claim same-bounds CG entries first, so the closed one of two identical synthetic windows closes
- [Phase 2]: 02-11: in fallback mode a cached AX element keeps its ID and source for its cache life; synthetic IDs are session-only
- [Phase 2]: 02-12: A frame write the app did not answer (-25204) goes back in its slot and the drain stops; record() sets drainEnabled = shouldRefresh(pid), giving one retry, a pause while degraded, and a flush on recovery
- [Phase 2]: 02-12: The fixture minsize:WxH spec sets NSWindow.minSize (frame minimum), so a refused size reads back exactly WxH
- [Phase 2]: 02-12: applyFrameResult leaves displayUUID to the refresh that the AX moved notification triggers (the tracker has no displays there)
- [Phase 2]: 02-13: Exclusion is enforced in WindowSystem.perform via ExclusionFilter.admit (both systems); excluded windows stay tracked with isExcluded true
- [Phase 2]: 02-13: Per-bundle minimum hints persist in ~/Library/Application Support/Pane/min-size-hints.json; a bad file is rejected whole, logged and moved aside as .corrupt
- [Phase 2]: 02-13: Bundle hints seed only newly reported windows and learning only raises them; hints are keyed by exact bundle ID, unbundled keys never stored
- [Phase 2]: 02-13: Nudge Focused Window is in every build; focusedWindow(of:) uses the latest windowFocused, else the AXMain visible window
- [Phase 2]: 02-14: Spaces data comes from a read-only SkyLight lookup (SkyLightSpaces, capability Spaces); nil in ObservationContext.windowSpaces means single-Space behaviour
- [Phase 2]: 02-14: Live macOS 27 reports an empty Space set for a hidden native tab, so an unknown-Space candidate is never taken while a known other-Space window shares the frame slot
- [Phase 2]: 02-14: A folded window is destroyed only after two consecutive refreshes with the same shown tab; a group whose tabs are all gone hands its identity only to a former tab (offscreen in its slot last refresh)
- [Phase 2]: 02-14: Without Space data two same-frame tab groups on two Spaces may be one tracked window (accepted override); no live window is destroyed and no ID is tracked twice
- [Phase 2]: 02-15: A refused size is learned only above a 32 pt margin and only after a refresh at least 1 s later still sees the window there (margin against grid snaps, time against late appliers)
- [Phase 2]: 02-15: In-session bundle hints live in WindowTracker (per-axis max on learn); onLearnedMinimum fires from emit for every learned growth
- [Phase 2]: 02-15: A due minimum candidate that no refresh decided is dropped at that pid's next refresh, so no app is refreshed every second forever
- [Phase 2]: 02-16: A lookup success counts only for real lookups (new elements and re-checks of fallback IDs); a cached axPrivate element is never looked up again, so a lookup that really broke mid-session still switches off
- [Phase 2]: 02-16: A lookup failure counts towards switching AXWindowID off at most once per listed element; the element the lookup names owns its ID and a frame-matched holder is re-identified and re-keyed
- [Phase 2]: 02-16: Phase 3 obligation: WindowEvent.windowRekeyed(from:to:) is not applied by LifecycleSync; Phase 3 re-points desk WindowRefs from from to to.window
- [Phase 2]: 02-16: A first lookup failure of a new element never takes an offscreen-only frame match; identityPending refreshes the app after the settle delay
- [Phase 2]: 02-17: 'the hidden-tab fold or merge' is one rule, a tracked standalone window taken as a hidden tab; the room-rule join and the Cmd-T opener are not refused in a flagged update
- [Phase 2]: 02-17: a Space-switch mark is consumed only by a full AXWindows answer whose reads began at or after the notification; a notification during the reads flags that update and the next one
- [Phase 2]: 02-17: with Space data a flagged update resolves exactly as an unflagged one; the flag only matters in single-Space fallback
- [Phase 3]: Desktop tile uses reserved NodeID.desktop (raw 0); World requires ids.next >= 1 so it is never minted
- [Phase 3]: resolve: a desktopMinimum too big for the area makes every docked window unfit and gives the Desktop the whole area (no throw)
- [Phase 03]: 03-02: rotate on a nested split flips every axis from the root, so Rotate is its own inverse (D-32)
- [Phase 03]: 03-02: resizeBoundary delegates to resizeBetween(i, i+1) and now validates in every build
- [Phase 03]: 03-03: A rekey onto an ID a desk already holds closes the old ID; a rekey to the same ID is a no-op
- [Phase 03]: 03-03: World.edit = World.reflow + history push; OS facts and automatic floats use reflow/recordFloatingFrame, never edit
- [Phase 03]: 03-04: Dock uses the planned (clamped) frame of a just-clamped window, else its floating frame
- [Phase 03]: 03-04: lastRequested is pruned to planned windows, so a window returning from minimise or fullscreen gets its tile rect rewritten
- [Phase 03]: 03-04: Undo with no focused window acts on the main display's visible desk
- [Phase 03]: 03-04: Live fullscreen test is opt-in (PANE_LIVE_FULLSCREEN=1) because native fullscreen switches Spaces
- [Phase 3]: WindowTracker emits windowChanged after CloseRule state events, so a fullscreen window never looks present on a foreign Space
- [Phase 3]: A display change reaches the Arranger as a new inventory (ArrangeController feeds .inventory after .displaysChanged)
- [Phase 3]: Re-home: a present window whose display or known non-empty Spaces leave its desk floats on its home desk via World.reflow, no undo step
- [Phase 3]: Lost-room floating repeats until every docked window fits (a floated minimum sizes the Desktop tile); one lostRoom notice per re-plan
- [Phase 3]: Echo rule: a move or resize within 2 pt of the last frameApplied is never answered; a floating window's echo frame is still recorded
- [Phase 3]: Docked windows moved by their app return to their tile at most once per second via ArrangerEffect.wake and ArrangerInput.tick
- [Phase 3]: NoticeQueue is generic over QueueableNotice (isCrashNotice, merged(with:)), used as NoticeQueue<Notice>
- [Phase 3]: 03-07: Every input that changes the World emits .save(.debounced) (World diff in Arranger.handle); layout.json is written 0.5 s after the latest
- [Phase 3]: 03-07: A pending restore ignores events and incomplete inventories and is what snapshot returns; the first complete inventory re-attaches by identity (non-synthetic only) and writes only tiles more than 0.5 pt off
- [Phase 3]: 03-07: layout.json is rejected whole and set aside on any doubt; a newer schema is kept and disables saving; titles are never written; file is 0600
- [Phase 3]: 03-08: replan is the only place parks are sent, each window once, with its home frame recorded and .save(.now) emitted before the perform that parks it (D-16)
- [Phase 3]: 03-08: a parked window's moves are not recorded and it is never re-homed; float, re-home and new windows onto a hidden Desktop show it first (D-31)
- [Phase 3]: 03-08: focus and raise run as tasks off the effect loop; focus is AXMain+AXRaise on the app thread, then activate, with an AXFrontmost fallback after 200 ms
- [Phase 03]: 03-09: nextWake includes the Finder deadline, since the shell keeps a single wake
- [Phase 03]: 03-09: a Finder window opened on another display leaves that Desktop (reflow) and docks on the target desk
- [Phase 03]: 03-10: Hotkeys and command menu items share one dispatch closure; CommandMenu builds each item once and takes its shortcut name from Hotkeys.entries
- [Phase 03]: 03-10: Arranger.availability(_:context:) is the one rule for greying and beeping; paused disables Arrange items, only Resume acts; Stage Manager alone cannot be resumed
- [Phase 03]: 03-10: While any PauseReason is set the Arranger records facts but sends no window command; Resume re-sends only tiles whose windows moved
- [Phase 03]: 03-10: Excluded windows are filtered from the plan in the Arranger (no frame, park or minimum); a docked window that becomes excluded floats at its frame via World.reflow
- [Phase 3]: 03-11: one drop decision per held 150 ms hover, applied exactly on mouse-up; with none, the miss rules; the pressed window is never written, corrected or rehomed before mouse-up
- [Phase 3]: 03-11: the window-under-pointer field is 0 at the session tap, so the press window comes from the topmost on-screen tracked window (CGWindowList.onScreenFrontToBack)
- [Phase 3]: 03-11: the app starts the event tap after tracking starts and stops it when access leaves .ready; a 2 s watchdog re-enables it or invalidates it when a trial tap is refused
- [Phase 03]: 03-12: Move to neighbour docks on the neighbour's near edge, but past a sibling in the same split (the near edge there is its own slot), taking its place
- [Phase 03]: 03-12: Every keyboard tree command (move, swap, grow/shrink, balance, rotate, flip) dry-runs and refuses with beep + blocked flash when a window would lose its room
- [Phase 03]: 03-12: Arrange All / Float All act on the focused window's desk or the main display's, stay enabled with nothing focused; a newer N4/N5 replaces the visible one
- [Phase 3]: Green-button press with no window in the event: one CG on-screen list read in the tap callback finds the topmost window, so a covered button is never taken (03-13)
- [Phase 3]: A press with no pointer travel whose frame changed (option-zoom, title-bar double-click) is answered at mouse-up as the app's own change (D-33)
- [Phase 3]: Edge resize and gap drag share BoundaryMove/boundaryChange: points to weight through the split length, cut to what the shrinking side can give before its minimum, so weights match the screen
- [Phase 3]: Gap handles are sent per display only when they change; hidden while paused, during a window drag and on a Space change
- [Phase 3]: Recovery and crash-loop launches show hidden Desktop tiles holding parked windows (no undo step), so the first plan does not park rescued windows again
- [Phase 3]: A rescued window goes to its saved desk's display, else its nearest; survivedMinute written 60 s into a recovery launch and cancelled by a clean quit
- [Phase 3]: Restore All shows hidden Desktops holding windows as one undo step per desk and acts while paused; SAFE-03 waits for pane://restore (plan 15)
- [Phase 03]: Quit restore: a non-docked window with a home frame counts as parked even when not stranded (park corner can show on a neighbouring display); it goes home on the display holding its home frame's centre
- [Phase 03]: A URL-sourced command that cannot act is silent on both refusal paths: availability and the Arranger's own beep effects
- [Phase 03]: pane-debug:// in Debug and pane:// in Release via PANE_URL_SCHEME merged from xcode/Pane-Info.plist; outside the bundle every URL is rejected
- [Phase 3]: 03-16: Recorded WindowManager originals are JSON [String: PrefValue] under windowManagerOriginals; only allow-listed keys with a boolean or absent survive load
- [Phase 3]: 03-16: A non-boolean WindowManager value is never written over; Turn Off skips that key
- [Phase 3]: 03-16: Conflict alerts are modeless NSAlerts (no runModal); presentAlert nil means no alert UI in unit tests
- [Phase 3]: 03-16: Restore macOS Window Settings is a plain status-menu item, not a Command (no hotkey, no Arranger rule)
- [Phase 03]: 03-17: 0.3.0 clean-Mac install check done in a fresh Tart VM (macOS 15.7.7) instead of the host, by user choice; DMG steps hand-finished after the release.sh hdiutil fallback failed
- [Phase 03]: 03-17: 0.3.0 DMG sha256 ee940af0c6badf8f16e2a4124f4083507d6c775dc45eeee2c9fa4028a0dc5761 stays local; nothing published until the Transom rename
- [Phase 03]: 03-12 move rule approved by user 2026-10-26: when a window and its neighbour share a parent split, move swaps them ([a|b|Desktop], b moves left -> H[b,a,Desktop]); across a split boundary the near-edge insert stands
- [Phase 03]: 03-25: per-window wantedFrames (user actions only, kept while docked) plan floaters; floaterFloors cut boundary drags only; Float/green button use Planner.floatFrame (pre-dock frame or 90% centred)
- [Phase 03]: 03-26: wanted frames are an optional layout.json key; schemaVersion stays 1, older files load with none
- [Phase 03]: 03-26: at re-attach a floater moved >2 pt while Pane was off keeps its real frame; a stranded saved wanted frame is dropped
- [Phase 02]: 02-18: the setup window uses sizingOptions [.preferredContentSize] and one setContentSize(fittingSize) before centring; preferredContentSize alone sizes the window only after a run-loop turn on macOS 27, too late for the centring code
- [Phase 2]: 02-19: on macOS 15.7.7 a hidden tab keeps its CG bounds from when it was hidden (G-02-10), so TabGroupTracker links a shown tab to the tab shown just before it by timing (wentHidden), keeps own members whatever their bounds, and joins a new tab to the group whose shown tab went hidden; bounds only find candidates and break ties
- [Phase 2]: 02-19: the timing opener and timing join are refused after a blind Space switch (spaceChanged without Space data), like the 02-17 orphan handoff and folds
- [Phase 4]: Spike verdict GO with conditions: G4 crossfade stalls accepted as VM noise, no host run
- [Phase 4]: SnapshotCache is mandatory in 04-04 (only about 6 of 15 captures land inside 120 ms in the VM)
- [Phase 4]: sharingType .none does not hide the stage from system screen recording on macOS 15.7; it only keeps it out of Transom's own snapshots
- [Phase 4]: ZOOM-07 500 ms is the write path only: first AX write to last read-back; capture budget and animation are separate
- [Phase 04]: 04-02: Gap handles show only on displays at the home view; a zoomed display gets none
- [Phase 04]: 04-02: LayoutTree.subtree(at:) lives in TransomEngine (ViewPlanner.swift), model unchanged
- [Phase 04]: 04-02: ViewPlanner applies the collapse pass to any planned view, .home included; empty set = Planner.plan exactly
- [Phase 4]: 04-03: one cameraStep resolver feeds camera() and cameraAvailable(), so greyed items and refused hotkeys agree
- [Phase 4]: 04-03: PendingMove.kind (.navigate/.back(n)/.forward(n)) applies history only at settle; a second Back during a pending one goes on from it
- [Phase 4]: 04-03: frame toggles compare against the current view (pending target while pending); Frame Focused Window acts on the pointer display
- [Phase 4]: 04-03: widening covers docked windows and floaters outside the view; unparkedNew is cleared per desk at settle
- [Phase 4]: 04-04: beginSettle takes the move ID; a settle answered after a retarget never attaches to the new move
- [Phase 4]: 04-04: a move during the 120 ms reveal fade is queued until the fade ends
- [Phase 4]: 04-04: fallback icon and title capsule centred as one group; capture size min(max(start,end), own frame) x scale
- [Phase 4]: 04-04: ZOOM-01/02/05/07 deferred to later phase-4 plans (shared IDs)
- [Phase 04]: 04-05: camera commands bypass the availability gate so refusals beep and announce; URL refusals stay silent
- [Phase 04]: 04-05: zoom hotkeys are disabled at launch in TransomMacApp (not in start()) and menuDidClose keeps them off while zoom is off
- [Phase 04]: 04-05: Turn Off Zoom waits only for displays whose move home started, with a 3 s fallback; ArrangeController owns ZoomController.onRevealed
- [Phase 04]: 04-05: ZOOM-08/09/10/11/01/02/04 deferred to phase end (shared IDs with 04-06..04-08)
- [Phase 04]: 04-06: every mouse-down re-decides the zoom swallow, so a lost mouse-up never traps the next click
- [Phase 04]: 04-06: pick clicks and title-bar double-clicks are taken only unmodified and only on the tile's own topmost window
- [Phase 04]: 04-06: pick mode is keyed to the zoom-out move id; collapsed blocks become pickable in 04-07
- [Phase 04]: 04-06: Desktop double-click decided on main after the event; unknown Finder AX roles count as icons (A4 unverified)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 261027-gqo | green click on a full-Desktop floater docks left | 2026-10-27 | 18d2d04 | [261027-gqo-green-click-on-a-floater-filling-the-des](./quick/261027-gqo-green-click-on-a-floater-filling-the-des/) |
| 2 | Log refusal announcements so the no-room dock refusal is not silent (03-19) | 2026-10-27 | 307834b | — |
| 3 | Log every notice before queuing its toast (03-22) | 2026-10-27 | 7e2b0a9 | — |
| 261027-ijh | Rename Pane to Transom (code 221fd39, docs 0d33bba) | 2026-10-27 | 0d33bba | [261027-ijh-rename-the-app-from-pane-to-transom-acro](./quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/) |
| 5 | Write a comprehensive README.md for Transom | 2026-10-27 | 739295b | — |
| 6 | Add the MIT LICENSE file | 2026-10-27 | fb0e29b | — |

### Pending Todos

- Re-check on the first Transom build (deferred from Phase 3 by the user, 2026-10-27): UAT 16 (Hide Desktop on one display parks safely) and the display half of UAT 17 (two displays x two Spaces relaunch, clean and kill -9, plus a cross-display drag while a window is dormant, WR-04) on the DELL; in the VM, pre-dock frames survive a relaunch, and a Dock tile over a docked window's green button owns the click. Also Phase 2 UAT 9 (deferred by the user, 2026-10-27): multi-display Nudge on the DELL, with the external display above, left and below, the Display column following, and one displaysChanged then one refresh about 500 ms after a hot-plug.
- Phase 2 leftovers for the same re-check: in the VM, UAT 11's whole-group close followed at once by a Space switch (the only live evidence for 02-17 truth 2) and UAT 17's long-CFBundleName wrap. FrameWriteIntegrationTests passed 5/5 in the VM on 2026-10-28 (incl. aRefusedSizeIsReadBackAndLearned).
- CI is disabled (user, 2026-10-28: `gh workflow disable CI`; re-enable with `gh workflow enable CI`). Before re-enabling, fix the failure: the last runs on `macos-26` (e.g. run 40620416102) aborted mid-way through `swift test` with no failing-test line, so the test process probably crashed on the runner; not diagnosed. All 999 tests pass locally.

### Blockers/Concerns

- Phase 4: zoom-stage feasibility (settle latency, flicker, WindowServer memory) is unproven; run a spike with measurable criteria first
- Phase 5: gesture input path (MultitouchSupport vs event-tap magnify events) is unverified; spike before building
- Phase 6: SkyLight signatures and Space-UUID stability across reboots/updates are unverified
- ⌥-hotkey restriction on macOS 15.0-15.1: sources conflict; ship a ⌃⌥ fallback regardless (affects Phase 3/4 hotkey defaults)
- Phase 3: notarisation with dlopen of private frameworks — MET 2026-10-27 (build/Pane-0.3.0.dmg accepted and stapled; rebuild as Transom before release)
- Name: resolved 2026-10-27, renamed to Transom (quick 261027-ijh); transomwm.app registered
- Phase 2 obligation (from Phase 1 review fix c403f45): `World.undo` returns `[WindowRef]?`; the engine must re-query the OS for every returned window and report its real state through `World.apply` — MET by 02-04 (`LifecycleSync.undo` → `requery` → `applyRequeried`)
- Phase 2 obligation: OS lifecycle events (open/close/minimise/fullscreen) go through `World.apply`, never `World.edit`, so they stay off the undo stack; `.closed` needs no valid desk key — MET by 02-04 (`LifecycleSync.handle`)
- Phase 1 work is on branch `gsd/phase-01-layout-model` (main is protected); merging to main is the developer's call

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-28T15:48:03.440Z
Stopped at: Completed 04-06-PLAN.md
Resume file: None

## Deferred Verification

| Phase | State | Resume |
|-------|-------|--------|
| 2 | verification_deferred_human | /gsd-verify-work 2 |

Phase 2 automated verification: human_needed (144/150, no gaps, 02-VERIFICATION.md). 18 hands-on items in 02-UAT.md. Lead chose on 2026-10-25 to defer UAT and continue with Phase 3.

## Rename to Transom (done 2026-10-27)

Decided 2026-10-25, done 2026-10-27 by quick 261027-ijh: app Transom (`com.eightabyte.transom`, `.transom.debug`, `transom://`), Transom* modules, TRANSOM_* env vars, Application Support/Transom (no migration), GitHub repo scottkw/transomwm. Kept on purpose: keychain profile `pane-notary`, Tart VM `pane-test` and key `pane_vm_ed25519`. Past phase artifacts keep the old names as history.

Still to do:
- Move ~/dev/panewm to ~/dev/transomwm and copy the Claude project memories.
- Install a Transom build in the VM (it still has /Applications/Pane.app); the new bundle ID needs a fresh Accessibility grant in the VM and on the host.
- Rebuild and notarise the DMG as build/Transom-0.3.0.dmg before any tester or public 0.3.0 release.
