---
gsd_state_version: "1.0"
current_phase: 2
current_phase_name: Window Control
status: verifying
stopped_at: Completed 02-13-PLAN.md
last_updated: "2026-10-25T17:07:18.925Z"
last_activity: 2026-10-24
last_activity_desc: Phase 2 execution started
state_head: b13626de3022b03c9239205804d2f1e2b45de46e
progress:
  total_phases: 9
  completed_phases: 1
  total_plans: 19
  completed_plans: 19
  percent: 11
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, this must still work.
**Current focus:** Phase 2 — Window Control

## Current Position

Phase: 2 (Window Control) — EXECUTING
Plan: 13 of 13
Status: Phase complete — ready for verification
Last activity: 2026-10-24 — Phase 2 execution started

Progress: [█░░░░░░░░░] 11%

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 6 | - | - |

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4: zoom-stage feasibility (settle latency, flicker, WindowServer memory) is unproven; run a spike with measurable criteria first
- Phase 5: gesture input path (MultitouchSupport vs event-tap magnify events) is unverified; spike before building
- Phase 6: SkyLight signatures and Space-UUID stability across reboots/updates are unverified
- ⌥-hotkey restriction on macOS 15.0-15.1: sources conflict; ship a ⌃⌥ fallback regardless (affects Phase 3/4 hotkey defaults)
- Phase 3: confirm notarisation works with dlopen of private frameworks in the minimal pipeline
- Name "Pane": check for existing macOS apps before public release (Phase 9)
- Phase 2 obligation (from Phase 1 review fix c403f45): `World.undo` returns `[WindowRef]?`; the engine must re-query the OS for every returned window and report its real state through `World.apply` — MET by 02-04 (`LifecycleSync.undo` → `requery` → `applyRequeried`)
- Phase 2 obligation: OS lifecycle events (open/close/minimise/fullscreen) go through `World.apply`, never `World.edit`, so they stay off the undo stack; `.closed` needs no valid desk key — MET by 02-04 (`LifecycleSync.handle`)
- Phase 1 work is on branch `gsd/phase-01-layout-model` (main is protected); merging to main is the developer's call

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-25T17:07:18.872Z
Stopped at: Completed 02-13-PLAN.md
Resume file: None
