---
phase: 01-layout-model
verified: 2026-10-28T02:36:32Z
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
  - "Sources/TransomEngine/WindowSystem.swift"
  - "Sources/TransomModel/DesktopLayer.swift"
  - "Sources/TransomModel/DropZones.swift"
  - "Sources/TransomModel/Geometry.swift"
  - "Sources/TransomModel/IDs.swift"
  - "Sources/TransomModel/LayoutTree.swift"
  - "Sources/TransomModel/Persistence.swift"
  - "Sources/TransomModel/Resolve.swift"
  - "Sources/TransomModel/TreeEdits.swift"
  - "Sources/TransomModel/Undo.swift"
  - "Sources/TransomModel/World.swift"
  - "Tests/TransomModelTests/DesktopLayerTests.swift"
  - "Tests/TransomModelTests/DropZoneTests.swift"
  - "Tests/TransomModelTests/InvariantTests.swift"
  - "Tests/TransomModelTests/LifecycleTests.swift"
  - "Tests/TransomModelTests/NoAppKitTests.swift"
  - "Tests/TransomModelTests/PersistenceTests.swift"
  - "Tests/TransomModelTests/ResolveFuzzTests.swift"
  - "Tests/TransomModelTests/ResolveTests.swift"
  - "Tests/TransomModelTests/ScenarioTests.swift"
  - "Tests/TransomModelTests/SkeletonTests.swift"
  - "Tests/TransomModelTests/TabsTests.swift"
  - "Tests/TransomModelTests/TreeEditTests.swift"
  - "Tests/TransomModelTests/TreeFuzzTests.swift"
  - "Tests/TransomModelTests/UndoTests.swift"
  - "scripts/check-no-appkit.sh"
covered_digest: "v4:sha256:a264115f676b45174fc8b323b7ea7eab179a53e90f5f9821bec53c99fb76ba70"
behavior_unverified: 0
overrides_applied: 3
overrides:
  - must_have: "Only setState(.closed) removes the slot: the window is removed with the same redistribution and collapse as remove(_:)"
    reason: "Review fix 971a691/8c5a745: a close inside World.edit would be undoable, so setState rejects .closed and only World.apply(.closed) closes (Desk.close -> tree.remove, same redistribution) and purges undo history"
    accepted_by: "Ken Scott"
    accepted_at: "2026-10-24T08:09:43-05:00"
  - must_have: "Desk.setState applies to docked and floating windows alike: a closed floating window is removed from the DesktopLayer"
    reason: "Same review fix: floating closes go through World.apply(.closed) -> Desk.close -> DesktopLayer.remove; Desk.setState rejects .closed"
    accepted_by: "Ken Scott"
    accepted_at: "2026-10-24T08:09:43-05:00"
  - must_have: "An undo that would put a window on two desks throws duplicateWindow and leaves the World and that desk's history unchanged"
    reason: "Review fix ad5ab19 (WR-02): the unrestorable snapshot is consumed so it cannot block older undo levels; the World is still unchanged"
    accepted_by: "Ken Scott"
    accepted_at: "2026-10-24T08:09:43-05:00"
re_verification:
  previous_status: passed
  previous_score: 55/55 (3 by developer override)
  reason: "Covered-input fingerprint went stale after quick task 261027-ijh renamed Pane to Transom (Sources/PaneModel -> Sources/TransomModel, PaneEngine -> TransomEngine, Tests/PaneModelTests -> Tests/TransomModelTests)"
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 1: Layout Model Verification Report

**Phase Goal:** As a Pane developer, I want to edit and resolve a nested tile layout in headless tests, so that every later feature rests on correct geometry. (Pane is now Transom; `PaneModel` in the roadmap means `TransomModel`.)
**Mode:** mvp
**Verified:** 2026-10-28T02:36:32Z at HEAD `d023e9c`, branch `gsd/phase-01-layout-model`
**Status:** passed
**Re-verification:** Yes. The previous report (passed, 55/55, 3 by override, 2026-10-24) went stale only because of the Pane → Transom rename. I checked every must-have again against the current Transom paths and module names, not just the renamed ones.

The phase goal still holds after the rename and after Phases 2 and 3 changed `TransomModel` (20 commits since the 2026-10-24 sign-off, most importantly D-24: the Desktop is now a real tile in every desk). All 5 roadmap success criteria and all 10 MODEL requirements hold. I confirmed them with a model test run of my own (193 tests in 20 suites, 0 failures) and an independent probe of my own run on desks shaped as they are today. The three developer overrides from 2026-10-24 are carried forward because the code they accepted is unchanged in substance.

## Path mapping (plans and summaries → current tree)

| Plan/summary path | Current path |
|---|---|
| `Sources/PaneModel/*.swift` | `Sources/TransomModel/*.swift` (same 10 files, plus Phase 3's `Neighbours.swift`, `Snap.swift`) |
| `Sources/PaneEngine/WindowSystem.swift` | `Sources/TransomEngine/WindowSystem.swift` |
| `Tests/PaneModelTests/*.swift` | `Tests/TransomModelTests/*.swift` (same 14 suites, plus 6 later-phase suites) |
| `scripts/check-no-appkit.sh` (defaults `Sources/PaneModel Sources/PaneEngine`) | same file, defaults now `Sources/TransomModel Sources/TransomEngine` |
| `PaneModel` / `PaneEngine` products | `TransomModel` / `TransomEngine` in `Package.swift` |

No `Pane`, `PaneModel` or `PaneEngine` identifier is left in `Sources/TransomModel`, `Sources/TransomEngine`, `Tests/TransomModelTests`, the gate script or the workflow.

## User Flow Coverage

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Run the tests headless | `swift test` builds TransomModel and TransomEngine with no UI framework or permissions | `swift test --filter TransomModelTests`: exit 0, 193 tests in 20 suites, 0 `✘`. The only imports in Sources/TransomModel and Sources/TransomEngine are `import Foundation` (15) and `import TransomModel` (21) | ✓ |
| Edit a nested layout | Insert on any edge, remove, reweigh, group into tabs, drop targets → edits | `TreeEdits.swift` (insertRoot, insert, remove, group, selectTab, setState, resizeBoundary), `DropZones.swift` (target, applyDrop); TreeFuzzTests 20 seeds; my probe: 6912 edits through `World.edit` | ✓ |
| Resolve it to geometry | Non-overlapping, whole-point rects with gap and minimums; windows that cannot fit are reported unfit, never overlapped | `Resolve.swift`; ResolveFuzzTests 30 seeds; my probe: 20,736 resolves on desk-shaped trees (Desktop tile visible or hidden), 0 failures | ✓ |
| Keep and restore it | Desks keyed by display UUID + Space; exact JSON round-trip; undo every edit | `World.swift`, `Persistence.swift`, `Undo.swift`; my probe: byte-identical re-encode after every edit, 6912 undos back to the new-desk state | ✓ |
| Outcome: later features rest on correct geometry | Invariants hold under random edits; hostile JSON is rejected; AppKit is kept out | `validate()` limits, corrupt corpus, `check-no-appkit.sh` + NoAppKitTests. Phases 2 and 3 already build on this model (TransomEngine `Arranger`, `LayoutFile`, etc.) | ✓ |

## Goal Achievement

### ROADMAP Success Criteria (the contract)

| # | Success criterion | Status | Evidence |
|---|---|---|---|
| SC1 | `swift test` shows a window inserted beside any tile on any of its four edges and removed again, every split's weights summing to 1, single-child splits collapsing | ✓ VERIFIED | Passing in my run: `SkeletonTests.dockOnEdgeSplitsOnItsAxisWithWindowOnThatSide` (4 cases), `ScenarioTests.tileEdgeDropIsInsertAtThatEdge` (4), `TreeEditTests.removingOneOfTwoCollapsesTheSplit`, `collapseMergesSameAxisChildIntoParent`, `TreeFuzzTests.randomEditsKeepEveryInvariant` (20 seeds). My probe checked weight sum 1 ± 1e-9, ≥ minWeight and ≥ 2 children after every edit, including inserts beside the Desktop tile: 0 failures |
| SC2 | For any layout, area and gap, resolved rects never overlap and honour every placed window's minimum | ✓ VERIFIED | `ResolveFuzzTests.resolvedLayoutsNeverOverlapAndHonourMinimums` (30 seeds) passes. Its fuzzed trees are raw trees with no Desktop tile (see the comment in its `need` oracle), so I also probed desk-shaped trees: 200 seeds × 40 ops, random areas with negative and fractional origins, gaps 0-30, random window minimums and a random `desktopMinimum`. Across 20,736 resolves (8,241 with the Desktop hidden, 57,122 unfit reports) there were 0 overlaps, 0 rects outside the inset area, 0 non-integer rects, 0 placed windows below their minimum, 0 dropped windows, and the visible Desktop always got a rect. Unfit instead of overlap is the locked D-11 decision |
| SC3 | Desk keyed by display UUID (+ optional Space) holds a tiled tree, a floating Desktop layer and tab tiles with one selected; absent/fullscreen keeps the slot until confirmed closed | ✓ VERIFIED | `DeskKey(displayUUID:spaceID:)` (IDs.swift), `Desk{tree, desktop}` (World.swift), `Node.tabs(windows:selected:)`. Passing: `PersistenceTests.nilAndNonNilSpaceOnOneDisplayAreDistinctDesks`, `LifecycleTests.aHiddenWindowKeepsItsSlotAndComesBackToTheSameRects` (2 cases), `TabsTests.*`. `.closed` is rejected by `LayoutTree.setState` (TreeEdits.swift:150) and `DesktopLayer.setState` (DesktopLayer.swift:42); the only close path is `World.apply(.closed)` (World.swift:184-200) |
| SC4 | Any layout serialises to versioned JSON and round-trips exactly; every edit can be undone | ✓ VERIFIED | Passing: `PersistenceTests.richWorldRoundTripsExactly`, `UndoTests.fiftyOneEditsAllowExactlyFiftyUndos`, `ScenarioTests.dropTabAbsentPresentUndoAndPersist`. My probe: `World.decode(encoded())` equal and byte-identical after every edit; then 6912 step-by-step undos, each restoring the exact earlier tree nodes and root, ending at `LayoutTree.withDesktop()` on every seed |
| SC5 | TransomModel (roadmap: `PaneModel`) builds and tests without importing AppKit, enforced by a CI check | ✓ VERIFIED (warning) | I ran `bash scripts/check-no-appkit.sh`: "no-appkit: OK (40 files)", exit 0. Fail-closed checks: a `@preconcurrency import AppKit` fixture gives exit 1, an empty dir 2, a missing dir 2. `NoAppKitTests` (passing) runs the script inside every `swift test`, and `.github/workflows/ci.yml` runs it as its first step. **Warning:** a GitHub remote now exists (`scottkw/transomwm`), but the CI workflow is `disabled_manually` (`gh workflow list`). The developer decided this on 2026-10-28 because of an undiagnosed runner crash, recorded in STATE.md along with how to re-enable it. CONTEXT accepted the local `swift test` gate as enough when there was no remote. That gate is still active, so enforcement today is the same as at the 2026-10-24 sign-off |

### Plan must-have truths

As before, Plan 01-03 truth 1 restates SC2 and Plan 01-06 truth 3 restates SC5, so both are folded into those rows: 50 plan truths + 5 SCs = 55.

| Plan | Truths | Verified | By override | Notes for this re-check |
|---|---|---|---|---|
| 01-01 | 7 | 7 | 0 | `dockResolveStoreAndRoundTrip` still asserts A=(10,10,485,480), B=(505,10,485,480) on a raw tree. Its World half now builds the desk beside the Desktop tile (D-24) and still checks `"schemaVersion":1`, equality and byte-identical re-encode. InvariantTests is unchanged apart from the module rename. `windowRefIdentityIgnoresTitleAndDescriptionHidesIt` passes |
| 01-02 | 9 | 9 | 0 | `removeRedistributesShareProportionally`, `removingTheLastWindowEmptiesTheTree` (raw tree; on a desk, removing the last docked window leaves the Desktop alone: `DesktopLeafTests.removingTheLastDockedWindowLeavesTheVisibleDesktopAlone`), tab removals, the resize tests, 20-seed fuzz. Phase 3 added `setWeights` and its tests; no phase-1 assertion was weakened |
| 01-03 | 10 (+1 folded) | 10 | 0 | The ResolveTests and DropZoneTests names match every truth (exact fit / one point short, touching tiles, empty / single / tiny area, rounding, determinism, water-filling, lifecycle exclusion, maximality, input validation, drop bands). `resolve` gained a defaulted `desktopMinimum:` parameter; the plan signature still compiles at every call site |
| 01-04 | 14 | 13 | 1 (truth 8) | `undoWithEmptyHistoryReturnsNilAndChangesNothing`, `historiesArePerDesk`, `throwingChangeCommitsNothingAndConsumesNoIDs`, `undoNeverRewindsTheIDSource`, migration and corrupt-corpus tests, `oversizedInputIsRejectedBeforeParsing` all pass. `World.edit` is now `reflow` + `history.push`, and `reflow` keeps the transactional contract (World.swift:157-172) |
| 01-05 | 8 | 6 | 2 (truths 5, 6) | Truth 8 (end-to-end scenario): under D-24 a new desk is the Desktop tile alone, not an empty tree, so the scenario drops A on the Desktop's left band and undoes three times back to "Desktop tile alone". The intent (hit-test-driven drops through `World.edit`, lifecycle via `World.apply`, undo back to the new desk, byte-identical JSON at every step) holds. The `.emptyLayout` mapping is still tested on a raw tree (`emptyLayoutDropBecomesTheRootOnlyOnAnEmptyTree`) |
| 01-06 | 2 (+1 folded) | 2 | 0 | Truth 1: `swift build` compiles TransomEngine, and `WindowSystem.swift` still declares `WindowSystem`, `WindowEvent`, `WindowCommand`, `WindowInventory`, `WindowInfo`, `DisplayInfo` with only `import TransomModel`. The "only content" clause bounded Phase 1's scope; Phase 2 and 3 plans own the 27 engine files added since, so it is not a phase-1 regression. Truth 2: gate exit codes 0/1/2, confirmed by running the script |

**Score:** 55/55 truths verified (52 directly, 3 PASSED (override); 0 present-but-behavior-unverified)

#### Overrides carried forward (basis re-checked)

| Must-have | Override still valid? | Evidence at HEAD |
|---|---|---|
| 01-05 truth 5: only `setState(.closed)` removes the slot | Yes | `LayoutTree.setState` still throws `invariantViolated` for `.closed` (TreeEdits.swift:150); `LifecycleTests.closedIsNotAStoredStateSoTheTreeRejectsIt` passes; the close path is `World.apply(.closed)` → `Desk.close` → `tree.remove` + `history.forget` |
| 01-05 truth 6: `Desk.setState` closes a floating window | Yes | `DesktopLayer.setState` rejects `.closed` (DesktopLayer.swift:42); `deskSetStateHandlesFloatingWindows` and `closingIsAboutTheWindowNotTheDeskKey` pass |
| 01-04 truth 8: unrestorable undo leaves history unchanged | Yes | `undo` still pops before it validates (World.swift:238), so the World is unchanged and the snapshot is consumed; `undoThatWouldPutAWindowOnTwoDesksThrowsAndDiscardsOnlyThatSnapshot` passes |

The D3 obligation from sign-off (`World.undo -> [WindowRef]?` means the caller must re-query and `apply`) is recorded as MET by Phase 2 plan 02-04 in STATE.md:275.

### Prohibitions (judgment tier; developer-resolved 2026-10-24, evidence re-checked)

| # | Prohibition | Verdict | Evidence at HEAD |
|---|---|---|---|
| 1 | TransomModel/TransomEngine never import AppKit, Cocoa or SwiftUI | HOLDS | Gate OK on 40 files; only Foundation/TransomModel imports; `NoAppKitTests.violationFails` passes |
| 2 | No TrellisWM material; no copied prior-art code | HOLDS | No `Trellis`, `SplitNode`, `PanelNode`, `DesktopNode`, `StagePanel` in Sources or Tests |
| 3 | Model errors/descriptions never contain window titles | HOLDS | `titleHint` is stored only and never interpolated in Sources/TransomModel; the description test passes; Phase 3 added `withoutTitleHints()` and `TitleRedactionTests` |
| 4 | Resolver never silently drops a window | HOLDS | ResolveFuzzTests P4; my probe: placed ∪ unfit == present, disjoint, on every resolve |
| 5 | Resolver never returns overlapping rects | HOLDS | ResolveFuzzTests P1; my probe: 0 overlaps across all leaf rects, Desktop tile included |
| 6 | Absent/fullscreen never lose the slot; only an explicit close removes it | HOLDS | `setState` changes `states` only; `.closed` is rejected everywhere except `World.apply` |

The developer confirmed all six on 2026-10-24 (see Human Sign-off). Their basis is unchanged, so no new human resolution is needed.

### Required Artifacts

| Artifact | Status | Details |
|---|---|---|
| `Package.swift` | ✓ VERIFIED | tools 6.2, `.macOS(.v14)`, `[.v6]`, `TransomModel` + `TransomEngine` libraries, `TransomModelTests`. `TransomModel` has no dependencies; KeyboardShortcuts (Phase 3) is used only by TransomMac |
| `Sources/TransomModel/{Geometry,IDs,LayoutTree,TreeEdits,Resolve,World,Persistence,DesktopLayer,Undo,DropZones}.swift` | ✓ VERIFIED | Present and substantive; every public name from the plan interfaces exists (`insertRoot`, `insert`, `remove`, `group`, `selectTab`, `setState`, `resizeBoundary`, `resolve`, `DropZones.target`, `applyDrop`, `encoded`, `decode(from:)`, `decode(from:migrations:)`, `MigrationChain`, `UndoHistory`, `World.edit/undo/apply`) |
| `Sources/TransomEngine/WindowSystem.swift` | ✓ VERIFIED | Protocol and value types present; wired: consumed by TransomMac `AXWindowSystem` and the engine (Phase 2) |
| `scripts/check-no-appkit.sh` | ✓ VERIFIED | Run directly: 0 / 1 / 2 |
| `Tests/TransomModelTests/*.swift` (the 14 phase-1 suites) | ✓ VERIFIED | All pass in my run |
| `.github/workflows/ci.yml` | ✓ VERIFIED (disabled on GitHub) | `macos-26`, gate first, then debug and release build/test. See SC5 warning and the release-build warning below |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| SkeletonTests | Persistence | `World.decode(from:)` round-trip | ✓ WIRED |
| LayoutTree init/decode | `validate()` | validating init; edits end with `assertValid()` | ✓ WIRED |
| TreeEdits | `normalize()` / `assertValid()` | remove and resizeBoundary | ✓ WIRED |
| Resolve | `LayoutTree.states` | only `.present` windows take part (Resolve.swift candidates loop) | ✓ WIRED |
| DropZones | `Resolution.nodeRects` | hit test over placed leaf rects | ✓ WIRED |
| World | Undo | `history.push` in edit, `history.pop` in undo, `history.forget` in apply(.closed) | ✓ WIRED |
| Persistence | `World.validate()` / `MigrationChain.standard` | `invalidLayout` mapping; default chain | ✓ WIRED |
| `applyDrop` | `DropZones.target(at:…)` | ScenarioTests feeds each hit-test result into applyDrop | ✓ WIRED |
| TreeEdits `setState` | `remove(_:)` | ".closed delegates to remove" | ✓ PASSED (override): rerouted through `World.apply` → `Desk.close` → `tree.remove` |
| ScenarioTests | World.edit / undo / encoded | `history:` | ✓ WIRED |
| NoAppKitTests, ci.yml | `check-no-appkit.sh` | Process / workflow step | ✓ WIRED |
| WindowSystem.swift | TransomModel | `import TransomModel` | ✓ WIRED |

### Data-Flow Trace (Level 4)

Nothing in this phase renders. The equivalent chain, resolve output → hit test → edit → resolve, is driven with real resolved rects by ScenarioTests. Downstream, TransomEngine uses `resolve` to produce real frames.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Model suite, debug | `swift test --filter TransomModelTests` | exit 0, 193 tests / 20 suites, 0 `✘`; all 20 named phase-1 tests checked by name in the saved output | ✓ PASS |
| Full suite (orchestrator, once) | `swift test` | 564 tests in 54 suites pass; the one intermittent `FreezeTestTests.itResumesByItself` flake is in Phase 2 | ✓ PASS (not re-run) |
| No-AppKit gate | `bash scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)`, exit 0 | ✓ PASS |
| Gate fails closed | script on AppKit fixture / empty dir / missing dir | exit 1 / 2 / 2 | ✓ PASS |
| Independent probe (scratchpad `probe/main.swift`, compiled `-O` with Sources/TransomModel/*.swift, so `assertValid` is compiled out and the release path is exercised) | 200 seeds × 40 ops on a `World` desk: inserts on random edges of random leaves (Desktop included), removes, resizes, Desktop hide/show, absent/fullscreen/present via `apply`; after each: SC1 invariants, 3 random resolves with SC2 checks, exact and byte-identical JSON; then undo every step | `failures: 0 edits: 6912 resolves: 20736 desktopHiddenResolves: 8241 unfitReported: 57122 undos: 6912` | ✓ PASS |
| Model suite, release | `swift test -c release -Xswiftc -enable-testing --filter TransomModelTests` | Build failed in `Tests/TransomMacTests/SetupWindowTests.swift:34`: `overrideStateForTesting` is debug-only since Phase 2 fix 7b9e8fe. TransomModel itself compiled; the test bundle did not link | ? SKIP (blocked by a Phase 2 test file; the probe above covers the release-mode model path) |

### Probe Execution

Step 7c: no `scripts/*/tests/probe-*.sh` exists and no phase-1 plan declares one. Not applicable.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| MODEL-01 | 01, 02 | Nested splits, fractional sizes summing to 1 | ✓ SATISFIED | validate() weight checks; TreeFuzzTests; probe |
| MODEL-02 | 01, 02, 05 | Insert beside any tile on any of four edges | ✓ SATISFIED | insert; 4-edge tests; applyDrop |
| MODEL-03 | 02 | Remove gives space back, single-child splits collapse | ✓ SATISFIED | remove + normalize; TreeEditTests |
| MODEL-04 | 01, 03 | Rects with gaps and minimums, no overlap | ✓ SATISFIED | resolve; ResolveFuzzTests; probe on desk-shaped trees |
| MODEL-05 | 04 | Floating Desktop layer per desk | ✓ SATISFIED | DesktopLayer; DesktopLayerTests |
| MODEL-06 | 02, 05 | Tab group tile with one selected | ✓ SATISFIED | group/selectTab; TabsTests |
| MODEL-07 | 01, 04, 06 | Desks keyed by display UUID + optional Space | ✓ SATISFIED | DeskKey; distinct nil/non-nil Space desks |
| MODEL-08 | 01, 03, 05, 06 | Lifecycle states; absent keeps the reserved slot | ✓ SATISFIED | states; LifecycleTests; World.apply |
| MODEL-09 | 01, 04 | Versioned JSON, exact round-trip | ✓ SATISFIED | schemaVersion 1, newer refused, migration chain, corpus, byte-identical |
| MODEL-10 | 04 | Every layout change undoable | ✓ SATISFIED | World.edit + undo; 50-level cap; probe 6912/6912 |

All 10 IDs appear in plan frontmatter and map to Phase 1 in REQUIREMENTS.md (lines 10-19, 156-165). No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (all covered files) | - | `TBD` / `FIXME` / `XXX` | none found | No debt-marker blocker |
| `scripts/check-no-appkit.sh` | 13 | `shortcut:` deferral (a text match cannot see transitive imports) | ℹ Info | Known and documented (review IN-08) |
| GitHub `CI` workflow | - | `disabled_manually` | ⚠ Warning | Developer decision 2026-10-28, recorded in STATE.md with the re-enable command. The no-AppKit gate is still enforced by every local `swift test` |
| `Tests/TransomMacTests/SetupWindowTests.swift` | 34 | Calls the debug-only `PermissionController.overrideStateForTesting` (Phase 2 fix 7b9e8fe) | ⚠ Warning (outside Phase 1 scope) | `swift test -c release -Xswiftc -enable-testing`, the last step of `ci.yml`, no longer builds. Phase 1 added that step so assertValid-free model behaviour is tested. Fix belongs to Phase 2: wrap the test in `#if DEBUG` or relax the seam's guard. Must be fixed before CI is re-enabled, or CI fails on that step even once the runner crash is solved |
| `.planning/ROADMAP.md` | 29, 38 | Phase 1 goal and SC5 still say "Pane developer" / `PaneModel` | ℹ Info | The rename did not touch the roadmap text; meaning is unambiguous |
| `ResolveFuzzTests.swift` | 30 | Fuzz trees hold no Desktop tile | ℹ Info | Desk-shaped trees are not property-fuzzed in the suite; my probe covered them (0 failures). Worth adding a Desktop-tile variant to the fuzz test |
| Phase 1 SUMMARY files | various | Old `Pane*` paths, old test counts, pre-review statements (setState(.closed), splitFull) | ℹ Info | Historical records; superseded by this report and the 2026-10-24 sign-off |

### Human Verification Required

None. The three contract overrides and six judgment-tier prohibitions were resolved by the developer on 2026-10-24. Their basis is unchanged at HEAD, and nothing new requires a human decision.

### Gaps Summary

No gaps. After the Pane → Transom rename and the Phase 2/3 changes to `TransomModel`, every must-have still holds against the current files and module names. That rests on my own model test run, the gate script run directly, and an independent probe of desk-shaped layouts, the shape Phase 3 introduced. Two warnings are outside Phase 1's deliverable, but both touch its CI artifact, and both must be resolved before re-enabling CI. First, the workflow is disabled on GitHub. Second, its release-test step no longer builds because of Phase 2's debug-only test seam.

---

_Verified: 2026-10-28T02:36:32Z_
_Verifier: Claude (gsd-verifier)_

## Human Sign-off (2026-10-24, carried forward)

On 2026-10-24 the developer accepted all the human-verification items of the original verification:

- **D1 lifecycle contract** (8c5a745, 971a691): accepted. Plan 01-05 truths 5 and 6 overridden.
- **D2 undo contract** (ad5ab19): accepted. Plan 01-04 truth 8 overridden.
- **D3 `World.undo -> [WindowRef]?`** (c403f45): accepted. The Phase 2 obligation is now MET by 02-04 (STATE.md).
- **Normalisation relaxation** (b4e0fe3): accepted. `closingAWindowWhoseMergeWouldPassMaxChildrenKeepsTheChildSplitNested` and `sameAxisNestingIsRejectedWhenTheMergeWouldFit` pass at HEAD.
- **Six judgment-tier prohibitions**: confirmed HOLDS. Re-checked above.
