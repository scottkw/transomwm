# Phase 1: Layout Model - Context

**Gathered:** 2026-10-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the Swift package and the pure-Swift `PaneModel` library: a nested, value-typed tile layout that can be edited (insert at an edge, remove, reweigh, group into tabs), resolved into non-overlapping rects with gaps and minimum sizes, hit-tested for drop zones, organised into desks keyed by display + Space, serialised to versioned JSON, and undone. All of it is verified headless by `swift test`. Also a compiled-but-empty `PaneEngine` target holding a first draft of the async `WindowSystem` protocol, and a check that Model/Engine never import AppKit. No AX, no windows, no UI.

</domain>

<decisions>
## Implementation Decisions

### Tree & edits
- Flat value tree: `struct LayoutTree { root: NodeID?; nodes: [NodeID: Node] }`, `enum Node { split(axis, children, weights), panel(WindowRef), tabs(windows, selected) }`
- `NodeID` is a monotonic `UInt64` from an ID source, not a UUID
- Edits are `mutating` methods that throw a typed `LayoutError` on bad input; `validate()` checks every invariant and runs after every edit in tests/debug
- Docking on the same axis as the parent split adds a sibling (n-ary); the new child gets `1/(n+1)`, others scaled by `n/(n+1)`
- Removing a window redistributes its share proportionally among all siblings (i3-style)
- Normalisation after every edit: collapse single-child splits, merge a child split with the same axis as its parent, renormalise weights to sum 1 and clamp ≥ ε
- Gap-drag reweighing moves weight only between the two children either side of the boundary

### Geometry & resolve
- Pane's own `Rect`/`Size`/`Point` (Double, Codable, Equatable) in PaneModel; no CoreGraphics types in the model API
- One global coordinate space: top-left origin, points (Accessibility convention). AppKit conversion lives only in PaneMac (later phase)
- `resolve(tree, in: Rect, mins: [WindowRef: Size], gap:)` uses min-size water-filling (pin below-min children, share remainder by weight, repeat)
- Never overlap: when minimums can't fit, windows that can't fit are reported as **unfit** (no rect) and the rest share the space. Later phases show unfit windows as snapshots ("represented")
- One gap value, applied between tiles and around the outer edge
- Rects are rounded to whole points; the last child in a split absorbs the rounding remainder

### Desks, window states & persistence
- `DeskKey(displayUUID: String, spaceID: UInt64?)`; `World` maps DeskKey → Desk
- A Desk holds a tiled `LayoutTree` plus a floating `DesktopLayer` (windows + their frames in desk coordinates)
- `WindowRef` = runtime identity `{ windowID, pid, bundleID }` plus persisted match hints `{ titleHint, axIdentifier?, creationOrder }`
- Window lifecycle states: present, absent, fullscreen, closed. Absent/fullscreen keep their slot in the tree but are excluded from resolve (neighbours fill in temporarily) and return to the same spot; only `closed` removes the slot
- Undo: every edit pushes a snapshot of that desk; 50 levels per desk
- JSON with `schemaVersion: 1`; a newer version fails to load with a clear error; older versions migrate step by step through a migration chain
- Drop zones: outer 25% band of a tile → dock on that edge; centre 50% → tab group; display edge bands → dock beside the whole layout. Values are constants, tuned later in UAT

### Package & tooling
- Single `Package.swift`, `swift-tools-version: 6.2`, `.macOS(.v14)`, Swift 6 language mode
- Targets now: `PaneModel` (Foundation only), `PaneEngine` (depends on PaneModel; contains only the draft `WindowSystem` async protocol and its event/command types), `PaneModelTests` using Swift Testing
- CI check: a script that fails if `Sources/PaneModel` or `Sources/PaneEngine` imports AppKit/Cocoa/SwiftUI, plus a GitHub Actions workflow running it and `swift test` on `macos-26`

### Claude's Discretion
- Exact file split inside `Sources/PaneModel`
- Test style (example-based vs small hand-rolled property/fuzz loops) as long as invariants are covered broadly
- ε value for weight clamping and the exact drop-zone constants

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- None: greenfield. No Swift code exists yet.

### Established Patterns
- Research ARCHITECTURE.md "Recommended Project Structure" and "Pattern 1/2" specify the shapes above; follow them.
- Prior art for normalisation rules: AeroSpace (MIT). Read for ideas, write fresh code.

### Integration Points
- Phase 2 implements `WindowSystem` in PaneMac and consumes `WindowRef`, `DeskKey`, lifecycle states
- Phase 3 consumes `resolve`, drop-zone hit-testing and undo
- Phase 4 consumes the `unfit` result for the represented state

</code_context>

<specifics>
## Specific Ideas

- Clean-room rule: no TrellisWM material. AeroSpace/Amethyst/yabai are MIT prior art, fine to study.
- Success criterion 5 needs the no-AppKit check enforced by CI; there's no git remote yet, so the workflow file plus a local script that `swift test`/CI both run is enough.

</specifics>

<deferred>
## Deferred Ideas

- Saved views storage in `World` (Phase 8)
- Learned-minimum persistence per bundleID (Phase 2/3, once the Reconciler exists)

</deferred>
