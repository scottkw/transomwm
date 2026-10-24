---
gsd_state_version: "1.0"
current_phase: 2
current_phase_name: Window Control
status: executing
stopped_at: Phase 2 UI-SPEC approved
last_updated: "2026-10-24T15:03:20.904Z"
last_activity: 2026-10-24
last_activity_desc: Phase 1 complete, transitioned to Phase 2
state_head: 4bbc50cdd542be45d63ce49b33dd7fee099a5a11
progress:
  total_phases: 9
  completed_phases: 1
  total_plans: 19
  completed_plans: 6
  percent: 11
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-24)

**Core value:** Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, this must still work.
**Current focus:** Phase 2 — Window Control

## Current Position

Phase: 2 (Window Control) — READY TO EXECUTE
Plan: Not started
Status: Ready to execute
Last activity: 2026-10-24 — Phase 1 complete, transitioned to Phase 2

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4: zoom-stage feasibility (settle latency, flicker, WindowServer memory) is unproven; run a spike with measurable criteria first
- Phase 5: gesture input path (MultitouchSupport vs event-tap magnify events) is unverified; spike before building
- Phase 6: SkyLight signatures and Space-UUID stability across reboots/updates are unverified
- ⌥-hotkey restriction on macOS 15.0-15.1: sources conflict; ship a ⌃⌥ fallback regardless (affects Phase 3/4 hotkey defaults)
- Phase 3: confirm notarisation works with dlopen of private frameworks in the minimal pipeline
- Name "Pane": check for existing macOS apps before public release (Phase 9)
- Phase 2 obligation (from Phase 1 review fix c403f45): `World.undo` returns `[WindowRef]?`; the engine must re-query the OS for every returned window and report its real state through `World.apply`
- Phase 2 obligation: OS lifecycle events (open/close/minimise/fullscreen) go through `World.apply`, never `World.edit`, so they stay off the undo stack; `.closed` needs no valid desk key
- Phase 1 work is on branch `gsd/phase-01-layout-model` (main is protected); merging to main is the developer's call

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-24T14:05:29.684Z
Stopped at: Phase 2 UI-SPEC approved
Resume file: .planning/phases/02-window-control/02-UI-SPEC.md
