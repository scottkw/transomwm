---
phase: quick-261027-gqo
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Sources/PaneEngine/Planner.swift
  - Tests/PaneEngineTests/ArrangerGreenButtonTests.swift
  - Tests/PaneEngineTests/PlannerTests.swift
  - .planning/phases/03-tiling-mvp/deferred-items.md
autonomous: true
requirements: [TILE-06]

estimate:
  tokens: 45000
  raw_tokens: 45000
  tasks: 2
  confidence: low

must_haves:
  truths:
    - "A plain green click on a floating window clamped to the whole Desktop tile (D-33 zoom) docks it: the effects hold a setFrame for it, no .beep, and it leaves the Desktop's floating list"
    - "Dock (green button and the Dock command) at the exact centre of a tile picks that tile's left edge (ties go left, user decision 2026-10-27); off-centre points still pick the nearest edge band as before"
    - "Drag-drop onto a tile's centre is unchanged: Arranger's drag path still maps .tile(_, .center) to no target (Phase 7 tab groups)"
    - "The D-26 no-room refusal of Dock is unchanged: beep + noRoom announce + flashBlocked"
    - "Every existing test stays green; scripts/check-no-appkit.sh passes"
  artifacts:
    - path: "Sources/PaneEngine/Planner.swift"
      provides: "Planner.dockTarget with left-biased exact-centre tie"
      contains: "fx <= 0.5 ? .left : .right"
    - path: "Tests/PaneEngineTests/ArrangerGreenButtonTests.swift"
      provides: "Regression: floater zoomed to the whole Desktop tile docks on a plain green click"
    - path: "Tests/PaneEngineTests/PlannerTests.swift"
      provides: "Unit test: dockTarget at the Desktop tile's exact centre is .tile(.desktop, .edge(.left))"
    - path: ".planning/phases/03-tiling-mvp/deferred-items.md"
      provides: "03-18 green-click item marked resolved"
      contains: "Resolved by quick 261027-gqo"
  key_links:
    - from: "Arranger.process(.greenButton) -> Arranger.dock"
      to: "Planner.dockTarget"
      via: "window centre point"
      pattern: "Planner.dockTarget\\(at: Point\\(x: frame.midX, y: frame.midY\\)"
---

<objective>
Make a plain green click (and the Dock command) on a floating window that exactly fills the Desktop tile always dock, never beep, per the user decision of 2026-10-27: when the window centre is the Desktop tile's centre zone, Dock falls back to the nearest edge zone of that tile, with ties going left. Drag-drop onto a centre is unchanged, and so is the D-26 no-room refusal.

Purpose: TILE-06 promises "floating docks". Deferred item (03-18) in .planning/phases/03-tiling-mvp/deferred-items.md.
Output: one-character tie fix in Planner.dockTarget, two regression tests, deferred item marked resolved.

IMPORTANT, read before starting (planner finding, notice-confusion): the deferred item's diagnosis is stale. Since 03-04, `Planner.dockTarget` (Sources/PaneEngine/Planner.swift, about line 101-110) ALREADY maps any `.tile(id, .center)` hit to the nearest edge band of the same tile, so `Arranger.dock`'s guard `if case .tile(_, .center) = target { return [.beep] }` (Sources/PaneEngine/Arranger.swift, about line 849) is reachable only if `resolution.nodeRects[id]` is missing. What the current code does at the exact centre (fx == fy == 0.5): ties go horizontal, then `fx < 0.5` is false, so it picks `.right`. The only behaviour the user decision changes is that tie: it must pick `.left`. The VM beep from 03-18 (574x326 Desktop tile, 460 pt minimums) was most likely the D-26 no-room refusal (its toast is invisible over VNC, see the 03-22 item), which the 03-19 item tracks and which this task leaves alone. Task 1 starts by confirming at HEAD which way the new test fails.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.claude/CLAUDE.md
@.planning/phases/03-tiling-mvp/deferred-items.md
@Sources/PaneEngine/Planner.swift
@Sources/PaneModel/DropZones.swift
@Tests/PaneEngineTests/ArrangerGreenButtonTests.swift

Interfaces (already in the code, do not re-read the files just for these):
- `Planner.dockTarget(at: Point, desk: Desk, area: Rect, resolution: Resolution) -> DropTarget?` is Dock-only (callers: `Arranger.dock`, and a refused-dock test in Tests/PaneEngineTests/ArrangerDragTests.swift line ~408 that uses an off-centre floater). The drag path calls `DropZones.target` directly and maps `.tile(_, .center)` to nil (Arranger.swift ~1165). Do not touch `DropZones.target`.
- `DropTarget.tile(NodeID, DropZone)`, `DropZone.edge(Edge) | .center`, the Desktop tile's node is `.desktop`.
- `Arranger.process(.greenButton(w))` routes a floating window to `.command(.dock, focused: w)` -> `dock(_:)`.
- Test helpers in Tests/PaneEngineTests/ArrangerLifecycleTests.swift: `Harness.started()` (w1 at frame1, w2 at frame2, display `visible = Rect(x: 0, y: 25, width: 1440, height: 875)`, gap 8), `harness.send(_:)`, `harness.fake.update(id) { $0.frame = ... }`, `harness.refresh()`, `harness.frame(w)`, `setFrames(effects)`, `inside(_:_:)`.
- Existing D-33 clamp test to model the setup on: `afterAnOptionZoomAcrossATileAFloatingWindowIsClampedIntoTheDesktop` in ArrangerGreenButtonTests.swift (lines ~117-130): dock w1, ⌥-press w2's green button, zoom w2 to `visible`, refresh, mouse-up, and the clamped frame equals the Desktop rect.
- PlannerTests has `dockTargetAtTheDesktopsCentreUsesTheNearestEdgeBand` (midX-10 and midY+10, both off-centre); a `desk()` helper and an `area` constant exist there.
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Green click on a floater filling the Desktop tile docks, ties go left (RED then GREEN)</name>
  <files>Tests/PaneEngineTests/ArrangerGreenButtonTests.swift, Tests/PaneEngineTests/PlannerTests.swift, Sources/PaneEngine/Planner.swift</files>
  <behavior>
    - ArrangerGreenButtonTests, new test `aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt`: dock w1, ⌥-zoom w2 across w1's tile so the clamp leaves w2 at exactly the Desktop rect (assert `await harness.frame(w2) == desktopRect`, where desktopRect comes from `Planner.plan(desk:area: visible, gap: 8, mins: [:]).desktopRect`, so the setup really is "fills the Desktop tile"). Then `harness.send(.greenButton(w2))` with no modifiers: the effects contain no `.beep`, `setFrames(effects)[w2]` is non-nil, `world[key]?.desktop.contains(w2) == false`, history depth for key grows by one, and w2's new frame is left of the new Desktop tile (`w2Frame.maxX <= newDesktopRect.minX`) because the exact-centre tie goes left.
    - PlannerTests, new test `dockTargetAtTheDesktopsExactCentreGoesLeft`: `Planner.dockTarget(at: Point(x: desktop.midX, y: desktop.midY), ...) == .tile(.desktop, .edge(.left))`.
    - Existing `dockTargetAtTheDesktopsCentreUsesTheNearestEdgeBand` and `dockTargetInTheDesktopsRightEdgeBandIsItsRightEdge` stay green unchanged.
  </behavior>
  <action>
    RED. Add the two tests from the behavior block. Model the zoom setup on the existing D-33 clamp test (same pointer helpers, `greenButton(of: frame2)`, `[.option]`, `press: w2`). Run the filtered suites and record in the SUMMARY which way the new Arranger test fails at HEAD. Expected: no beep, w2 docks, but to the RIGHT of the Desktop (only the left-of-Desktop expectation fails), and the PlannerTests one returns `.edge(.right)`. If instead the effects contain `.beep`: find which guard in `Arranger.dock` returns it before changing anything. If it is the D-26 path (`.announce(Self.noRoom)` present), stop and report: the user said the no-room refusal stays as it is. If it is the `.tile(_, .center)` guard or the `frame`/`dockTarget` nil guard, fix that root cause so the user decision holds (Dock falls back to the nearest Desktop-tile edge, ties left), and do not delete the guard (Chesterton's Fence: it stays as a defensive check for a missing node rect). Commit the RED tests with only explicit paths: `git add Tests/PaneEngineTests/ArrangerGreenButtonTests.swift Tests/PaneEngineTests/PlannerTests.swift`, message `test(quick-261027-gqo): green click on a floater filling the Desktop tile docks, ties go left`.
    GREEN, per the user decision (2026-10-27: centre falls back to the nearest edge zone by the window centre's offset, ties go left). In `Planner.dockTarget`'s horizontal branch, change the comparison `fx < 0.5` to `fx <= 0.5`. Leave the vertical branch's `fy < 0.5` alone: it only runs when `min(fy, 1 - fy) < min(fx, 1 - fx) <= 0.5`, so fy is never 0.5 there. Update the doc comment above `dockTarget` to say that an exact-centre tie picks the left edge. Do NOT change `DropZones.target` (the drag path keeps `.center` -> no target), the Arranger drag code, or the D-26 refusal in `Arranger.dock`. Update the trailing comment on Arranger.swift's `.center` guard only if the RED step showed it is reachable; otherwise leave Arranger.swift untouched.
    If any EXISTING test fails after GREEN because it pinned the old exact-tie `.right`, stop and report it. Do not edit it: the user asked that every existing test stays green, and that test would conflict with the decision.
    Commit with explicit paths: `git add Sources/PaneEngine/Planner.swift` (plus Arranger.swift only if it changed), message `fix(quick-261027-gqo): Dock at a tile's exact centre docks on its left edge`. Every commit message ends with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage .planning/config.json, .planning/state.json or .planning/milestone.lock; never use `git add -A` or `git add .`.
    Headless only: never set PANE_LIVE=1, never launch Pane or PaneFixtureApp, no Tart VM.
  </action>
  <verify>
    <automated>rm -f .build/q.log && swift build && swift test --filter "ArrangerGreenButtonTests|PlannerTests|ArrangerCommandTests|ArrangerDragTests" > .build/q.log 2>&1; ! grep -q "✘" .build/q.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/q.log && test "$(grep -v '^ *///' Sources/PaneEngine/Planner.swift | grep -c 'fx <= 0.5 ? .left : .right')" = 1</automated>
  </verify>
  <done>Both new tests failed at HEAD (failure mode recorded in the SUMMARY) and pass after the fix. The filtered suites pass with no ✘. Planner.dockTarget has the left-biased tie (gate baseline at HEAD: 0 matches, after: 1). DropZones.swift and the drag and D-26 paths are unchanged. Two commits, with only the listed paths staged.</done>
</task>

<task type="auto">
  <name>Task 2: Full headless suite, AppKit gate, mark the deferred item resolved</name>
  <files>.planning/phases/03-tiling-mvp/deferred-items.md</files>
  <action>
    Run the full headless `swift test` (PANE_LIVE unset) and `scripts/check-no-appkit.sh`; both must pass. Then edit the 03-18 bullet in .planning/phases/03-tiling-mvp/deferred-items.md ("A plain green click on a floating window that exactly fills the Desktop tile does nothing (beep)"). Do not delete its text. Append an indented line in the same style as the existing "**Resolved by 03-23 (G-03-8):**" note, starting `**Resolved by quick 261027-gqo (2026-10-27):**`. Write it in plain sentences, saying:
    - Dock never returns the centre zone for a tile. `Planner.dockTarget` has fallen back to the nearest edge band since 03-04.
    - At the exact centre that fallback used to pick the right edge. Per the user decision it now picks the left edge.
    - The new regression test is `ArrangerGreenButtonTests.aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt`.
    - Drag-drop onto a centre is unchanged.
    - The VM beep with 460 pt minimums is the D-26 no-room refusal, which the 03-19 item tracks. Adjust this sentence if Task 1's RED step found a different beep source, and name that source instead.
    Commit with an explicit path: `git add .planning/phases/03-tiling-mvp/deferred-items.md`, message `docs(quick-261027-gqo): mark the 03-18 green-click deferred item resolved`, ending with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage .planning/config.json, .planning/state.json or .planning/milestone.lock.
  </action>
  <verify>
    <automated>swift test > .build/full.log 2>&1; ! grep -q "✘" .build/full.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/full.log && scripts/check-no-appkit.sh && grep -c "Resolved by quick 261027-gqo" .planning/phases/03-tiling-mvp/deferred-items.md</automated>
  </verify>
  <done>The full headless suite passes with no ✘, and check-no-appkit exits 0. The deferred item carries a resolution note (gate baseline at HEAD: 0, after: 1) that states the real root cause and the D-26 caveat. The commit stages only deferred-items.md.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| none new | Pure engine geometry change. The green-button press already passes T-03-34's guards (pause, dockable, not excluded, has a desk) before it reaches dock |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-gqo-01 | Denial of service | Arranger.dock at the exact tile centre | low | mitigate | Dock still runs the D-26 room check before it commits, so the new left-edge target cannot leave a window without room. The regression test and the existing aRefusedKeyboardDockFlashesTheBlockedPreview cover this |
| T-gqo-SC | Tampering | npm/pip/cargo installs | low | accept | No package installs in this plan; Package.swift is not touched |
</threat_model>

<verification>
- `rm -f .build/q.log && swift build && swift test --filter "ArrangerGreenButtonTests|PlannerTests|ArrangerCommandTests|ArrangerDragTests" > .build/q.log 2>&1; ! grep -q "✘" .build/q.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/q.log`
- Full headless `swift test` passes; `scripts/check-no-appkit.sh` exits 0
- `git diff HEAD~3 --stat` lists only Planner.swift, the two test files, deferred-items.md (and Arranger.swift only if Task 1's RED step justified it)
</verification>

<success_criteria>
- A plain green click on a floating window that exactly fills the Desktop tile docks it on the Desktop tile's left edge, and nothing beeps
- The Dock command behaves identically, since it is the same code path
- Drag-drop centre behaviour, DropZones, and the D-26 refusal are unchanged
- Every existing test is green, and the deferred item is marked resolved with an accurate root cause
</success_criteria>

<output>
Create `.planning/quick/261027-gqo-green-click-on-a-floater-filling-the-des/261027-gqo-SUMMARY.md` when done
</output>
