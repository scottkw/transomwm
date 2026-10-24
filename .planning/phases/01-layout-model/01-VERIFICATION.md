---
phase: 01-layout-model
verified: 2026-10-24T07:30:37Z
status: passed
score: 55/55 must-haves verified (3 by developer override)
covered_files:
  - ".github/workflows/ci.yml"
  - ".planning/phases/01-layout-model/01-01-PLAN.md"
  - ".planning/phases/01-layout-model/01-01-SUMMARY.md"
  - ".planning/phases/01-layout-model/01-02-PLAN.md"
  - ".planning/phases/01-layout-model/01-02-SUMMARY.md"
  - ".planning/phases/01-layout-model/01-03-PLAN.md"
  - ".planning/phases/01-layout-model/01-03-SUMMARY.md"
  - ".planning/phases/01-layout-model/01-04-PLAN.md"
  - ".planning/phases/01-layout-model/01-04-SUMMARY.md"
  - ".planning/phases/01-layout-model/01-05-PLAN.md"
  - ".planning/phases/01-layout-model/01-05-SUMMARY.md"
  - ".planning/phases/01-layout-model/01-06-PLAN.md"
  - ".planning/phases/01-layout-model/01-06-SUMMARY.md"
  - "Package.swift"
  - "Sources/PaneEngine/WindowSystem.swift"
  - "Sources/PaneModel/DesktopLayer.swift"
  - "Sources/PaneModel/DropZones.swift"
  - "Sources/PaneModel/Geometry.swift"
  - "Sources/PaneModel/IDs.swift"
  - "Sources/PaneModel/LayoutTree.swift"
  - "Sources/PaneModel/Persistence.swift"
  - "Sources/PaneModel/Resolve.swift"
  - "Sources/PaneModel/TreeEdits.swift"
  - "Sources/PaneModel/Undo.swift"
  - "Sources/PaneModel/World.swift"
  - "Tests/PaneModelTests/DesktopLayerTests.swift"
  - "Tests/PaneModelTests/DropZoneTests.swift"
  - "Tests/PaneModelTests/InvariantTests.swift"
  - "Tests/PaneModelTests/LifecycleTests.swift"
  - "Tests/PaneModelTests/NoAppKitTests.swift"
  - "Tests/PaneModelTests/PersistenceTests.swift"
  - "Tests/PaneModelTests/ResolveFuzzTests.swift"
  - "Tests/PaneModelTests/ResolveTests.swift"
  - "Tests/PaneModelTests/ScenarioTests.swift"
  - "Tests/PaneModelTests/SkeletonTests.swift"
  - "Tests/PaneModelTests/TabsTests.swift"
  - "Tests/PaneModelTests/TreeEditTests.swift"
  - "Tests/PaneModelTests/TreeFuzzTests.swift"
  - "Tests/PaneModelTests/UndoTests.swift"
  - "scripts/check-no-appkit.sh"
covered_digest: "v3:sha256:ba9351a03d79642a4036830f91fe5729ed529c9f0de163e8e9f70cf93ba292ae"
behavior_unverified: 0
overrides_applied: 3
human_verification:
  - test: "Accept or reject lifecycle contract change D1 (review fixes 8c5a745 WR-03 and 971a691 WR-01): OS lifecycle reports go through World.apply (no undo level); LayoutTree.setState, Desk.setState and DesktopLayer.setState reject .closed; only World.apply(.closed, ...) closes a window (Desk.close -> tree.remove / desktop.remove) and purges it from every undo snapshot"
    expected: "Developer accepts by adding the two override entries proposed in the report (plan 01-05 truths 5 and 6), or rejects and the two truths become gaps"
    why_human: "Plan 01-05 must_haves say setState(.closed) removes the slot. Current code rejects it on purpose. Intent (only a confirmed close removes a slot, same redistribution as remove) holds and is tested, but changing a locked plan contract is the developer's decision. The fixer flagged both commits 'requires human verification'."
  - test: "Accept or reject undo contract change D2 (review fix ad5ab19 WR-02): an undo whose snapshot cannot be restored (window now on another desk) throws duplicateWindow, leaves the World unchanged, and consumes that snapshot so it cannot block older ones"
    expected: "Developer accepts by adding the override entry proposed in the report (plan 01-04 truth 8), or rejects and the truth becomes a gap"
    why_human: "Plan 01-04 truth 8 says the desk's history stays unchanged. UndoTests.undoThatWouldPutAWindowOnTwoDesksThrowsAndDiscardsOnlyThatSnapshot asserts the opposite on purpose (depth 3 -> 2)."
  - test: "Accept or reject undo signature change D3 (review fix c403f45 WR-01, iteration 3): World.undo returns [WindowRef]? (nil = nothing to undo; otherwise windows brought back from no desk, whose snapshot state may be stale). The caller must re-report each returned window's real state through World.apply"
    expected: "Developer accepts the API and records the caller obligation as an input to Phase 2 engine planning (no Phase 2 plan exists yet, so nothing carries it today)"
    why_human: "Public API change plus a new obligation on a later phase. Fixer flagged it 'requires human verification'. The model cannot know OS state for a window it does not track."
  - test: "Accept or reject the normalisation relaxation (review fix b4e0fe3 WR-01, iteration 1): remove() never throws anything but windowNotFound; a same-axis merge that would exceed maxChildren (100) is skipped, so validate() permits same-axis nesting only in that case"
    expected: "Developer accepts. 01-02-SUMMARY.md still says normalize throws splitFull and that Phase 3 must handle splitFull from remove; that is now false"
    why_human: "Narrows the D-06 invariant ('merge a child split with the same axis') for trees with more than 100 siblings. Fixer flagged it 'requires human verification'."
  - test: "Resolve the six judgment-tier prohibitions (workflow is interactive, auto_advance false): (1) no AppKit/Cocoa/SwiftUI import in PaneModel/PaneEngine; (2) no TrellisWM material or copied prior-art code; (3) no window titles in model error/description strings; (4) resolver never silently drops a window; (5) resolver never returns overlapping rects; (6) absent/fullscreen windows never lose their slot, only an explicit close removes it"
    expected: "Developer confirms each. The verifier's non-authoritative verdict is HOLDS for all six, with the evidence listed in the report's Prohibitions table"
    why_human: "Judgment-tier prohibitions need explicit human resolution in interactive mode (ADR-550 D4). Several have strong deterministic backing (gate script, fuzz properties), but none is a test-tier item."
---

# Phase 1: Layout Model Verification Report

**Phase Goal:** As a Pane developer, I want to edit and resolve a nested tile layout in headless tests, so that every later feature rests on correct geometry.
**Mode:** mvp (user-story goal validated by `user-story.validate`: valid)
**Verified:** 2026-10-24T07:30:37Z at HEAD `c0a36b5`, branch `gsd/phase-01-layout-model`
**Status:** human_needed
**Re-verification:** No. This is the first verification.

The code delivers the phase goal. All 5 ROADMAP success criteria are verified by tests I ran myself (141/141 passing in both debug and release) and by an independent probe I wrote. Status is `human_needed`, not `passed`, for two reasons. First, three plan must-haves are now false as worded, because review fixes changed the contracts on purpose; the developer must accept or reject those changes. Second, the six judgment-tier prohibitions need human sign-off in interactive mode. Nothing is missing or stubbed.

## User Flow Coverage

User story: «As a Pane developer, I want to edit and resolve a nested tile layout in headless tests, so that every later feature rests on correct geometry.»

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Run the tests headless | `swift test` builds PaneModel + PaneEngine with no UI framework, no permissions | I ran `swift test`: exit 0, 141 tests in 14 suites. `swift test -c release -Xswiftc -enable-testing`: exit 0, 141 tests. Only `import Foundation` / `import PaneModel` in Sources | ✓ |
| Edit a nested layout | insert on any edge, remove, reweigh, group into tabs, drop targets → edits | `TreeEdits.swift` (insert rules 1-3, remove, normalize, resizeBoundary, group, selectTab), `DropZones.swift` (applyDrop); TreeFuzzTests 20 seeds × 100 ops; my probe: 6652 edits via `World.edit` across 200 seeds | ✓ |
| Resolve it to geometry | Non-overlapping whole-point rects with gap and minimums; unfit reported, never overlapped | `Resolve.swift` water-filling + unfit selection + maximality pass; ResolveFuzzTests properties P1-P9 over 30 seeds × 20 cases; my probe checked overlap, minimums and "placed ∪ unfit == present" after every edit: 0 failures | ✓ |
| Keep and restore it | Desks keyed by display UUID + Space; JSON round-trip exact; undo every edit | `World.swift`, `Persistence.swift`, `Undo.swift`; ScenarioTests end-to-end; my probe: byte-identical re-encode after every edit and 6652 exact step-by-step undos back to the empty desk | ✓ |
| Outcome: later features rest on correct geometry | Invariants hold under random edits; hostile JSON rejected; AppKit kept out by a gate | `validate()` iterative with depth/node limits; 20-file corrupt corpus; `scripts/check-no-appkit.sh` + NoAppKitTests + CI workflow | ✓ |

## Goal Achievement

### ROADMAP Success Criteria (the contract)

| # | Success criterion | Status | Evidence |
|---|-------------------|--------|----------|
| SC1 | `swift test` shows a window inserted beside any tile on any of its four edges and removed again, with every split's child weights summing to 1 and single-child splits collapsing automatically | ✓ VERIFIED | `SkeletonTests.dockOnEdgeSplitsOnItsAxisWithWindowOnThatSide` (all 4 edges), `ScenarioTests.tileEdgeDropIsInsertAtThatEdge`, `TreeEditTests.removingOneOfTwoCollapsesTheSplit` / `collapseMergesSameAxisChildIntoParent`, `TreeFuzzTests.randomEditsKeepEveryInvariant` (asserts weight sum 1 ± 1e-9 and ≥ 2 children after every op). My probe: after `remove(B)` from H[A,B,C], A and C fill the area; after `remove(C)` the split collapses to one panel node. |
| SC2 | For any layout, area and gap size, resolved tile rects never overlap and honour every window's minimum size | ✓ VERIFIED | `ResolveFuzzTests` P1 (no overlap), P2 (inside inset area, whole points), P3 (≥ effective minimum), P4 (placed ∪ unfit == present), P8 (maximality), P9 (weights honoured). The test's own oracle (`need`/`fitsAll`) is independent of `Resolve.swift`. Windows whose minimums cannot fit are reported `unfit` instead of overlapping (D-11). This is the locked user decision, so "honour every minimum" applies to placed windows. |
| SC3 | A desk keyed by display UUID (plus optional Space ID) holds a tiled tree, a floating Desktop layer and tab-group tiles with one selected window; an absent or fullscreen window keeps its reserved slot until it is confirmed closed | ✓ VERIFIED | `DeskKey(displayUUID:spaceID:)` (IDs.swift), `Desk{tree, desktop}` (World.swift), `Node.tabs(windows:selected:)`; `PersistenceTests.nilAndNonNilSpaceOnOneDisplayAreDistinctDesks`; `LifecycleTests.aHiddenWindowKeepsItsSlotAndComesBackToTheSameRects` (nodes unchanged, `.present` gives an identical Resolution); a close goes only through `World.apply(.closed)` (World.swift:121-133). |
| SC4 | Any layout serialises to versioned JSON and round-trips exactly, and every edit can be undone back to the previous layout | ✓ VERIFIED | `PersistenceTests.richWorldRoundTripsExactly` (IDSource 2^53+1, 1/3 weights, nil/non-nil axIdentifier, negative-origin floating frames, byte-identical re-encode); `UndoTests.fiftyOneEditsAllowExactlyFiftyUndos`; `ScenarioTests.dropTabAbsentPresentUndoAndPersist`. My probe: 6652 edits of every kind, each undone to the exact earlier `Desk`. |
| SC5 | `PaneModel` builds and tests without importing AppKit, enforced by a CI check | ✓ VERIFIED | `scripts/check-no-appkit.sh` exits 0 on the real sources (I ran it: "OK (11 files)"), 1 on a `@preconcurrency import AppKit` fixture and 2 on a missing or empty directory (I ran all three). `NoAppKitTests` runs it inside every `swift test`. `.github/workflows/ci.yml` runs it on `macos-26` before debug and release build/test. Known limitation: there is no git remote, so the workflow has never run on GitHub. Per CONTEXT this is accepted; the local `swift test` enforcement is the active gate. |

### Plan must-have truths

Plan 01-03 truth 1 restates SC2 and Plan 01-06 truth 3 restates SC5, so they are folded into those rows. That leaves 50 plan truths plus 5 SCs = 55.

| Plan | Truths | Verified | Uncertain | Notes |
|------|--------|----------|-----------|-------|
| 01-01 | 7 | 7 | 0 | Exact skeleton rects A=(10,10,485,480), B=(505,10,485,480) asserted in `dockResolveStoreAndRoundTrip`. Truth 4: the plain same-axis case is still rejected (`rejectsChildSplitWithParentsAxis`); validate() now also allows same-axis nesting where a merge would pass maxChildren (see human item 4). |
| 01-02 | 9 | 9 | 0 | Proportional redistribution, collapse, merge, tabs → panel under the same NodeID, resizeBoundary leaves other weights bit-identical, 20-seed fuzz. |
| 01-03 | 10 (+1 folded) | 10 | 0 | Exact fit and one point short, touching tiles, empty / single / tiny area, rounding contract (P7), determinism (P6), water-filling 700/300, lifecycle exclusion, maximality (P8), input validation, drop zones. |
| 01-04 | 14 | 13 | 1 | Truth 8 is now false as worded (deviation D2). Truth 5's "returns false" is now `nil` (`[WindowRef]?`). The behaviour it asserts (per-desk depth, empty history changes nothing) is tested in `undoWithEmptyHistoryReturnsNilAndChangesNothing` and `historiesArePerDesk`. |
| 01-05 | 8 | 6 | 2 | Truths 5 and 6 are now false as worded (deviation D1). Truth 8 (end-to-end scenario) passes; lifecycle steps now use `World.apply` instead of `World.edit`, by design (WR-03). |
| 01-06 | 2 (+1 folded) | 2 | 0 | PaneEngine contains only the draft protocol and value types (76 lines, `import PaneModel` only). |

**Score:** 52/55 truths verified (0 present-but-behavior-unverified; 3 uncertain pending a developer decision)

#### Uncertain truths: intentional deviations from review fixes

All three come from post-SUMMARY code review fixes. Each fix is tested, and the fixer flagged each one "requires human verification". The code meets the intent; the literal wording of the plan must-have no longer holds.

**01-05 truth 5: "Only setState(.closed) removes the slot: the window is removed with the same redistribution and collapse as remove(_:)"**
Current code: `LayoutTree.setState(.closed)` throws `invariantViolated` (TreeEdits.swift:136), and `LifecycleTests.closedIsNotAStoredStateSoTheTreeRejectsIt` asserts that. The only close path is `World.apply(.closed, …)` → `Desk.close` → `tree.remove` (World.swift:121-133, 37-44). That path is the same redistribution and collapse, and it also purges undo history. Plan 01-05 key link "TreeEdits.swift setState → remove(_:) via .closed delegates to remove" is therefore wired through `Desk.close`, not `setState`.

**01-05 truth 6: "Desk.setState applies to docked and floating windows alike: … a closed floating window is removed from the DesktopLayer …"**
Current code: `Desk.setState(.closed)` throws (DesktopLayer.swift:42). A floating close goes through `World.apply(.closed)` → `Desk.close` → `desktop.remove`. `UndoTests.closingIsAboutTheWindowNotTheDeskKey` covers a floating window. The rest of the truth (an absent floating window keeps its frame; an unknown window throws `windowNotFound`) is verified in `LifecycleTests.deskSetStateHandlesFloatingWindows`.

**01-04 truth 8: "An undo that would put a window on two desks throws LayoutError.duplicateWindow and leaves the World and that desk's history unchanged"**
Current code: `undo` pops before it validates (World.swift:149), so the World is unchanged but the stale snapshot is consumed. `UndoTests.undoThatWouldPutAWindowOnTwoDesksThrowsAndDiscardsOnlyThatSnapshot` asserts depth 3 → 2, so a bad snapshot cannot block older ones.

**These look intentional.** To accept them, add this to the frontmatter and re-run verification:

```yaml
overrides:
  - must_have: "Only setState(.closed) removes the slot: the window is removed with the same redistribution and collapse as remove(_:)"
    reason: "Review fix 971a691/8c5a745: a close inside World.edit would be undoable, so setState rejects .closed and only World.apply(.closed) closes (Desk.close -> tree.remove, same redistribution) and purges undo history"
    accepted_by: "{your name}"
    accepted_at: "{ISO timestamp}"
  - must_have: "Desk.setState applies to docked and floating windows alike: a closed floating window is removed from the DesktopLayer"
    reason: "Same review fix: floating closes go through World.apply(.closed) -> Desk.close -> DesktopLayer.remove; Desk.setState rejects .closed"
    accepted_by: "{your name}"
    accepted_at: "{ISO timestamp}"
  - must_have: "An undo that would put a window on two desks throws duplicateWindow and leaves the World and that desk's history unchanged"
    reason: "Review fix ad5ab19 (WR-02): the unrestorable snapshot is consumed so it cannot block older undo levels; the World is still unchanged"
    accepted_by: "{your name}"
    accepted_at: "{ISO timestamp}"
```

### Prohibitions (all judgment tier; interactive mode, so a human must resolve them)

| # | Prohibition | Non-authoritative verdict | Evidence |
|---|-------------|---------------------------|----------|
| 1 | PaneModel/PaneEngine never import AppKit, Cocoa or SwiftUI | HOLDS | Gate script passes on real sources and fails on 11 bypass forms (`NoAppKitTests.violationFails`); only `import Foundation` / `import PaneModel` in Sources. Known gaps in a text gate (block comments, split lines, unlisted modules): review IN-08, Info. |
| 2 | No TrellisWM material in the repo; no copied prior-art code | HOLDS for phase-1 files | No TrellisWM names (e.g. SplitNode, PanelNode, DesktopNode, StagePanel) in Sources or Tests. Note: the root `PLAN.md` (committed at project init, ed1968a, before this phase) lists observed TrellisWM internal type names and module names as a feature spec. It is outside this phase's scope, but the developer should decide whether it fits the clean-room rule's "internal type names" clause. |
| 3 | Model error/description strings never contain window titles | HOLDS | `titleHint` is only stored, never interpolated (grep over Sources); `WindowRef.description`/`debugDescription` omit it; `SkeletonTests.windowRefIdentityIgnoresTitleAndDescriptionHidesIt` checks `String(describing:)` and `String(reflecting:)` of LayoutError. |
| 4 | Resolver never silently drops a window | HOLDS | ResolveFuzzTests P4; my probe checked `placed ∪ unfit == tree.windows` (all present) after 6652 edits. |
| 5 | Resolver never returns overlapping rects | HOLDS | ResolveFuzzTests P1; my probe found no overlap in any leaf pair. |
| 6 | Absent/fullscreen never lose the reserved slot; only an explicit close removes it | HOLDS | `setState` changes `states` only; `LifecycleTests` asserts `tree.nodes` unchanged and an identical Resolution after `.present`; `.closed` is rejected everywhere except `World.apply`. |

### Required Artifacts

`verify.artifacts` passed on all six plans (8+3+3+4+3+5 artifacts, exit 0 for each). Level 2/3 checked by reading every source file:

| Artifact | Status | Details |
|----------|--------|---------|
| `Package.swift` | ✓ VERIFIED | tools 6.2, `.macOS(.v14)`, `[.v6]`, PaneModel + PaneEngine libraries, PaneModelTests; no dependencies |
| `Sources/PaneModel/{Geometry,IDs,LayoutTree,TreeEdits,Resolve,World,Persistence,DesktopLayer,Undo,DropZones}.swift` | ✓ VERIFIED | Substantive (64-240 lines each), no stubs. Every public name from the plan interfaces exists. All are used by tests and by each other (World ↔ Undo, Persistence → World init, DropZones → Resolution) |
| `Sources/PaneEngine/WindowSystem.swift` | ✓ VERIFIED | Draft protocol plus 5 value types; imports PaneModel; compiled by `swift build`/`swift test`. No consumer yet, as planned (Phase 2) |
| `scripts/check-no-appkit.sh` | ✓ VERIFIED | Exit codes 0/1/2 confirmed by running it directly |
| `Tests/PaneModelTests/*.swift` (14 suites) | ✓ VERIFIED | 141 tests, all active |
| `.github/workflows/ci.yml` | ✓ VERIFIED (never run) | `macos-26`, gate, debug and release build/test. No remote exists |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| SkeletonTests | Persistence | `World.decode(from:)` round-trip | ✓ WIRED |
| LayoutTree init/decode | `validate()` | validating init; `insert` validates in every build | ✓ WIRED |
| TreeEdits | `normalize()` / `assertValid()` | every edit | ✓ WIRED |
| Resolve | `LayoutTree.states` | only `.present` windows take part | ✓ WIRED |
| DropZones | `Resolution.nodeRects` | hit test over placed leaf rects | ✓ WIRED |
| World | Undo | `history.push` in edit, `history.pop` in undo, `history.forget` in apply(.closed) | ✓ WIRED |
| Persistence | `World.validate()` / `MigrationChain.standard` | `invalidLayout` mapping; default chain | ✓ WIRED |
| `applyDrop` | `DropZones.target(at:…)` | ScenarioTests feeds the hit-test result into applyDrop at every step (tool could not check: `from` is not a path; checked by hand) | ✓ WIRED |
| TreeEdits `setState` | `remove(_:)` | ".closed delegates to remove" | ⚠ REROUTED. `setState` rejects `.closed`; the link is now `World.apply` → `Desk.close` → `tree.remove` (deviation D1) |
| ScenarioTests | World.edit / undo / encoded | `history:` | ✓ WIRED |
| NoAppKitTests, ci.yml | `check-no-appkit.sh` | Process / workflow step | ✓ WIRED |
| WindowSystem.swift | PaneModel | `import PaneModel` | ✓ WIRED |

### Data-Flow Trace (Level 4)

Not applicable in the UI sense: nothing renders. The equivalent trace is resolve output → drop target → edit → resolve. ScenarioTests and my probe drive it with real resolved rects, not hand-written targets.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full suite, debug | `swift test` | exit 0, 141 tests / 14 suites, 0 `✘` | ✓ PASS |
| Full suite, release (assertValid compiled out) | `swift test -c release -Xswiftc -enable-testing` | exit 0, 141 tests | ✓ PASS |
| No-AppKit gate | `bash scripts/check-no-appkit.sh` | `no-appkit: OK (11 files)`, exit 0 | ✓ PASS |
| Gate fails closed | script on a `@preconcurrency import AppKit` fixture / empty dir / missing dir | exit 1 / 2 / 2 | ✓ PASS |
| Independent falsification probe (scratch package in the session scratchpad, depends on the repo by path, release build) | 200 seeds × 40 hit-test-driven ops (drops of every target kind, removes, resizes) through `World.edit`, random areas with negative and fractional origins, gaps 0-30, random minimums; after each op: weights, overlap, minimums, no dropped window, exact JSON + byte-identical re-encode; then undo every step | `failures: 0 edits: 6652 editsWithTabs: 3026 undosChecked: 6652` | ✓ PASS |

Each behavior-dependent truth (state transitions: lifecycle, undo LIFO/cap/per-desk, transactional edit, ID source never rewound, close purges history) has a named passing test. I confirmed each in the saved output of both full runs.

### Probe Execution

Step 7c: no `scripts/*/tests/probe-*.sh` exist and no plan declares one. Not applicable.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| MODEL-01 | 01, 02 | Nested splits, fractional sizes sum to 1 | ✓ SATISFIED | validate() weight checks; normalize clamp; TreeFuzzTests |
| MODEL-02 | 01, 02, 05 | Insert beside any tile on four edges | ✓ SATISFIED | insert rules 1-3; 4-edge tests; applyDrop |
| MODEL-03 | 02 | Remove gives space back, single-child splits collapse | ✓ SATISFIED | remove + normalize; TreeEditTests |
| MODEL-04 | 01, 03 | Rects with gaps and minimums, no overlap | ✓ SATISFIED | resolve; ResolveFuzzTests P1-P9 |
| MODEL-05 | 04 | Floating Desktop layer per desk | ✓ SATISFIED | DesktopLayer; DesktopLayerTests |
| MODEL-06 | 02, 05 | Tab group tile with one selected | ✓ SATISFIED | group/selectTab; TabsTests; tabs resolve to one rect |
| MODEL-07 | 01, 04, 06 | Desks keyed by display UUID + optional Space | ✓ SATISFIED | DeskKey; distinct nil/non-nil Space desks |
| MODEL-08 | 01, 03, 05, 06 | Lifecycle states; absent keeps reserved slot | ✓ SATISFIED | states; LifecycleTests; World.apply (see D1) |
| MODEL-09 | 01, 04 | Versioned JSON, exact round-trip | ✓ SATISFIED | schemaVersion 1, newer refused, migration chain, corpus, byte-identical |
| MODEL-10 | 04 | Every layout change undoable | ✓ SATISFIED | World.edit funnel + undo; 50-level cap; probe 6652/6652 |

All 10 IDs appear in plan frontmatter and map to Phase 1 in REQUIREMENTS.md. No orphaned requirements.

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| SkeletonTests | 01,02,04,07,09 | 7 (+4 cases) | 0 | No | Value (exact rects, bytes) | ✓ |
| InvariantTests | 01 | 16 | 0 | No | Value (typed errors) | ✓ |
| TreeEditTests / TreeFuzzTests | 01,02,03,06 | 22 / 1 (20 seeds) | 0 | No | Value + property | ✓ |
| ResolveTests / ResolveFuzzTests | 04,08 | 21 / 1 (30 seeds) | 0 | No; the oracle is written separately from Resolve.swift | Value + property | ✓ |
| DropZoneTests | 02 (D-20) | 8 | 0 | No | Value | ✓ |
| DesktopLayerTests | 05 | 11 | 0 | No | Value | ✓ |
| UndoTests | 10 | 20 | 0 | No | Behavioral (multi-step) | ✓ |
| PersistenceTests | 09 | 15 (+20 corpus) | 0 | No; fixtures are hand-built JSON | Value (bytes, typed errors) | ✓ |
| TabsTests / LifecycleTests | 06, 08 | 7 / 10 | 0 | No | Value + behavioral | ✓ |
| ScenarioTests | 02,06,08,09,10 | 7 | 0 | No | Behavioral end-to-end | ✓ |
| NoAppKitTests | SC5 | 5 (+16 cases) | 0 | No | Status (exit codes) with fail-first fixtures | ✓ |

**Disabled tests on requirements:** 0. **Circular patterns detected:** 0. **Insufficient assertions:** 0.

### Decision Coverage

`check.decision-coverage-verify` reported: "No trackable decisions in CONTEXT.md." (skipped, non-blocking). CONTEXT lists decisions as unnumbered bullets; the plans number them D-01..D-23. Spot checks against code: D-01, D-02, D-04, D-05, D-06 (with the maxChildren relaxation, human item 4), D-07, D-08, D-09, D-10-D-13, D-14, D-15, D-16, D-17, D-18 (limit 50), D-19, D-20 (0.25 / 24 pt), D-21, D-22 and D-23 are all present.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (all phase files) | - | `TBD` / `FIXME` / `XXX` | none found | No debt-marker blocker |
| `scripts/check-no-appkit.sh` | 13 | `shortcut:` deferral (text match cannot see transitive imports) | ℹ Info | Known and documented; same as review IN-08 |
| `Sources/PaneModel/Undo.swift` | 33 | `try!` in `forget` | ℹ Info | Justified inline: a snapshot that holds the window can only throw `windowNotFound`, and it was checked just before |
| `Sources/PaneModel/LayoutTree.swift` | 160 | `preconditionFailure` in `assertValid` | ℹ Info | DEBUG only, by design (D-03) |
| `.planning/phases/01-layout-model/01-02-SUMMARY.md` | 40, 146, 178 | Stale: says normalize throws `splitFull` and that Phase 3 must handle `splitFull` from `remove` | ⚠ Warning | Now false (b4e0fe3): `remove` throws only `windowNotFound`. A later planner reading the SUMMARY would plan for an error that cannot happen |
| `.planning/phases/01-layout-model/01-05-SUMMARY.md` | 76, 121 | Stale: says `setState(.closed)` removes the slot on LayoutTree/Desk | ⚠ Warning | Now rejected; close only through `World.apply` |
| `.planning/phases/01-layout-model/01-04-SUMMARY.md` | 128 | Stale: undo with empty history "returns false" | ℹ Info | Now returns `nil` (`[WindowRef]?`); `World.apply` is not mentioned in any SUMMARY |
| SUMMARY test counts | various | 20 / 37 / 64 / 97 / 101 / 125 tests | ℹ Info | HEAD has 141 |
| `.planning/phases/01-layout-model/01-REVIEW-DISPOSITION.md` | 6-13, 95-96 | WR-01 and WR-02 (iteration 3) recorded `open` | ℹ Info | 01-REVIEW-FIX.md shows both fixed (c403f45, b2c7489), and I confirmed both tests pass. The disposition record should say `fixed`. The 10 Info findings (IN-01..IN-10) stay open by design (fix scope was critical+warning) |

### Human Verification Required

This is a foundation phase with no user-facing UI, so there are no manual UAT steps. The items below are decisions only the developer can make. Each is a contract change or a judgment-tier prohibition.

#### 1. Lifecycle contract change D1 (close only via World.apply)

**Test:** Review World.swift:115-133 and TreeEdits.swift:126-139. Decide whether OS lifecycle reports should bypass undo, and whether only `World.apply(.closed)` should be able to close a window.
**Expected:** Accept by adding the first two overrides above (plan 01-05 truths 5 and 6), or reject and they become gaps.
**Why human:** A locked plan contract changed on purpose; the fixer flagged it.

#### 2. Undo contract change D2 (unrestorable snapshot is consumed)

**Test:** Review World.swift:136-163 and `UndoTests.undoThatWouldPutAWindowOnTwoDesksThrowsAndDiscardsOnlyThatSnapshot`.
**Expected:** Accept by adding the third override above (plan 01-04 truth 8), or reject.
**Why human:** The plan said history stays unchanged; it no longer does.

#### 3. Undo signature change D3 (`[WindowRef]?` plus a caller obligation)

**Test:** Review the `undo` doc comment (World.swift:136-146).
**Expected:** Accept, and carry "re-query and `apply` the real state of every window `undo` returns" into Phase 2 engine planning. Nothing records it there today.
**Why human:** New public API obligation on a later phase.

#### 4. Normalisation relaxation (same-axis nesting allowed only past maxChildren)

**Test:** Review TreeEdits.swift:159-199 and LayoutTree.swift:95-98.
**Expected:** Accept. Also correct 01-02-SUMMARY.md, which still promises `splitFull` from `remove`.
**Why human:** Narrows a locked D-06 invariant for trees with more than 100 siblings.

#### 5. Judgment-tier prohibitions (6)

**Test:** Confirm each row of the Prohibitions table. For #2, also decide whether the pre-phase root `PLAN.md` (TrellisWM internal type and module names) is acceptable under the clean-room rule.
**Expected:** All confirmed.
**Why human:** Interactive mode needs human resolution of judgment-tier prohibitions.

### Gaps Summary

No gaps. Nothing is missing, stubbed or unwired. All 5 ROADMAP success criteria and all 10 MODEL requirements are met by code I read, tests I ran in both build configurations, and an independent probe. The three uncertain truths have one root cause: post-execution review fixes changed lifecycle and undo contracts on purpose (D1, D2). The code still meets the intent of the original truths, so the fix is a developer decision (overrides), not new code. If the developer rejects any of those changes, re-run verification and the matching truth becomes a gap. Housekeeping, not blocking: refresh the stale statements in 01-02, 01-04 and 01-05 SUMMARY, and mark WR-01/WR-02 `fixed` in 01-REVIEW-DISPOSITION.md.

---

_Verified: 2026-10-24T07:30:37Z_
_Verifier: Claude (gsd-verifier)_

## Human Sign-off (2026-10-24)

The developer reviewed the human-verification items and accepted all of them:

- **D1 lifecycle contract** (8c5a745, 971a691): accepted. Plan 01-05 truths 5 and 6 are overridden: only `World.apply(.closed, ...)` closes a window and purges it from undo history.
- **D2 undo contract** (ad5ab19): accepted. Plan 01-04 truth 8 is overridden: an unrestorable snapshot is consumed so it cannot block older undo levels.
- **D3 `World.undo -> [WindowRef]?`** (c403f45): accepted. Obligation carried to Phase 2 in STATE.md: the engine must re-query the OS for every window `undo` returns and report it through `World.apply`.
- **Normalisation relaxation** (b4e0fe3): accepted. 01-02-SUMMARY.md's note that Phase 3 must handle `splitFull` from `remove` is superseded.
- **Six judgment-tier prohibitions**: confirmed HOLDS. For prohibition (2), the root `PLAN.md` was scrubbed of TrellisWM internal type and module names, and the planning docs that had adopted any of those names now use neutral ones (`AXWindowSystem`, `ZoomCurve`, `MarqueeZoom`, `TabBarOverlay`).

The fingerprint was recomputed with `verification.fingerprint` after those doc renames.
