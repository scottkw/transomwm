# Walking Skeleton — Pane

**Phase:** 1
**Generated:** 2026-10-23

## Capability Proven End-to-End

A developer runs `swift test` and sees one window docked beside another, resolved into exact whole-point tile rects with a gap, stored in a desk keyed by display UUID, and round-tripped through versioned JSON byte for byte. The same `swift test` run fails if the model or engine library imports a UI framework.

This phase builds a headless Swift library, not an app. The template's layers map like this: there is **no database, no routing, no UI and no deployment** in Phase 1, and none are invented here. The "full stack" of this phase is: package manifest → value types → tree edit → resolve → World/desk → JSON persistence → tests → no-AppKit check → CI workflow file.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language / toolchain | Swift 6 language mode, `swift-tools-version: 6.2`, `.macOS(.v14)` (D-21) | Builds on GitHub `macos-26` runners (Xcode 26.6) and locally on Xcode 27.1 / Swift 6.4 |
| Build system | One SwiftPM `Package.swift`, no dependencies | `swift build` / `swift test` run headless with no Xcode project; an XcodeGen app wrapper comes in Phase 3 |
| Module layering | `PaneModel` (Foundation only) ← `PaneEngine` (draft `WindowSystem` protocol) ← later `PaneMac`/`PaneApp` (D-22) | Dependency direction is strictly downward; Model and Engine never import AppKit/Cocoa/SwiftUI, so ~70% of logic tests headless |
| Layout data model | Flat value tree: `LayoutTree { root: NodeID?, nodes: [NodeID: Node], states }`, `Node = split(axis, children, weights) \| panel(WindowRef) \| tabs(windows, selected)` (D-01) | Value snapshots give cheap undo, tweens and Codable; whole-tree equality in tests |
| Identity | `NodeID` = monotonic `UInt64` from `IDSource` (D-02); `WindowRef` = identity `{windowID, pid, bundleID}` + hints `{titleHint, axIdentifier?, creationOrder}`, equality by identity only (D-16) | Readable, stable across persistence; hints allow re-matching after relaunch (Phase 8) without a title change splitting one window into two |
| Weights | Normalised fractions per n-ary split, sum 1, clamp ≥ 0.01 (D-04..D-07) | Resolution-independent, which the zoom camera needs |
| Geometry | Own `Point`/`Size`/`Rect` (Double); one global top-left-origin coordinate space in points (D-08, D-09) | No CoreGraphics in the model API; AppKit conversion lives only in PaneMac (Phase 2) |
| Resolve | Pure function `resolve(tree, in:, mins:, gap:)`, min-size water-filling, unfit windows reported instead of overlapping, whole-point rounding (D-10..D-13) | Never-overlap promise holds even when minimums do not fit; Phase 4 shows unfit windows as snapshots |
| Desks | `DeskKey(displayUUID, spaceID?)` → `Desk { tree, desktop: DesktopLayer }` (D-14, D-15) | Per-display and per-Space layouts from day one; `spaceID == nil` means one desk per display |
| Window lifecycle | `present / absent / fullscreen / closed`; only `.closed` removes a slot (D-17) | Lock screen, sleep and slow apps must never collapse a layout (PITFALLS 2) |
| Undo | Transactional `World.edit` funnel pushing a desk snapshot, 50 per desk; history is session state, not persisted (D-18) | Every layout change is undoable; failed edits leave no trace |
| Persistence | JSON with `schemaVersion: 1`, sorted keys and sorted arrays (deterministic bytes), validate on decode, newer version refused, migration chain for older ones, 16 MiB cap (D-19) | Exact round-trip; corrupt files throw instead of crashing; future format changes go through migrations |
| Testing | Swift Testing (`import Testing`), example tests plus seeded hand-rolled fuzz loops | Headless, no TCC permissions needed |
| CI | `scripts/check-no-appkit.sh` (also run inside `swift test` by `NoAppKitTests`) + `.github/workflows/ci.yml` on `macos-26` (D-23) | No git remote yet, so the local script inside `swift test` is the enforced check; the workflow runs once a remote exists |
| Directory layout | `Sources/PaneModel/*.swift`, `Sources/PaneEngine/WindowSystem.swift`, `Tests/PaneModelTests/*.swift`, `scripts/`, `.github/workflows/` | Matches research ARCHITECTURE.md "Recommended Project Structure" |

## Stack Touched in Phase 1

- [x] Project scaffold: `Package.swift`, Swift 6 build, Swift Testing runner (Plan 01)
- [ ] Routing: not applicable. Pane is a menu-bar agent with no routes; `pane://` URL handling starts in Phase 3
- [ ] Database: not applicable. The persistence layer is versioned JSON produced and parsed by `World.encoded()` / `World.decode(from:)`; the real write is the encode and the real read is the decode, both exercised by the skeleton test. Writing the file to Application Support starts in Phase 3
- [ ] UI: not applicable. There is no UI in Phase 1; the "interaction" is a test docking a window via a tree edit, and from Plan 03 a drop-zone hit test standing in for a pointer drop
- [x] Deployment / run command: `swift test` from the repo root is the documented full-stack run; `.github/workflows/ci.yml` runs the same on `macos-26` once a remote exists

## Out of Scope (Deferred to Later Slices)

- Any AppKit, Accessibility, window movement, overlays or UI (Phases 2-3)
- `PaneEngine` implementation (Reconciler, Planner, sessions, camera) and a `PaneEngineTests` target; Phase 1 has only the draft `WindowSystem` protocol
- `FakeWindowSystem` and `MacWindowSystem` (Phase 2)
- Writing layouts to disk, debounced saves, crash restore (Phase 3) and restart/reboot re-matching (Phase 8)
- Saved views storage in `World` (Phase 8, deferred in CONTEXT.md)
- Learned-minimum persistence per bundleID (Phase 2/3, deferred in CONTEXT.md)
- Tuning drop-zone constants (UAT in Phase 3)
- Signing, XcodeGen app wrapper, notarisation (Phase 3)

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without changing its architectural decisions:

- Phase 2: Window Control — `MacWindowSystem` implements `WindowSystem`; real windows become `WindowRef`s with lifecycle states
- Phase 3: Tiling MVP — drag-to-dock uses `DropZones` + `applyDrop`, frames come from `resolve`, undo from `World.undo`, first on-disk layouts via `World.encoded()`
- Phase 4: Zoom Camera — unfit windows become the represented state; camera targets are `NodeID`s
- Phase 5: Gestures — drive the Phase 4 camera
- Phase 6: Overview, Spaces & Displays — desks keyed by `DeskKey` with real Space IDs
- Phase 7: Tab Groups — UI over `Node.tabs`, `group`, `selectTab`
- Phase 8: Saved Views, URLs & Persistence — re-matching through `WindowRef` hints, migrations through `MigrationChain`
- Phase 9: Polish & Ship

## Artifacts this phase produces (all plans)

- **Files:** `Package.swift`; `Sources/PaneModel/{Geometry,IDs,LayoutTree,TreeEdits,Resolve,DropZones,World,DesktopLayer,Undo,Persistence}.swift`; `Sources/PaneEngine/WindowSystem.swift`; `Tests/PaneModelTests/{SkeletonTests,InvariantTests,NoAppKitTests,TreeEditTests,TreeFuzzTests,ResolveTests,ResolveFuzzTests,DropZoneTests,DesktopLayerTests,UndoTests,PersistenceTests,TabsTests,LifecycleTests,ScenarioTests}.swift`; `scripts/check-no-appkit.sh`; `.github/workflows/ci.yml`
- **Types:** `Point`, `Size`, `Rect`, `Geometry`, `Axis`, `Edge`, `NodeID`, `IDSource`, `WindowIdentity`, `WindowRef`, `WindowState`, `DeskKey`, `Node`, `LayoutError`, `LayoutTree`, `Resolution`, `DropZone`, `DropTarget`, `DropZones`, `FloatingWindow`, `DesktopLayer`, `Desk`, `World`, `UndoHistory`, `MigrationChain`, `PersistenceError`; PaneEngine: `WindowSystem` (protocol), `WindowEvent`, `WindowCommand`, `WindowInventory`, `WindowInfo`, `DisplayInfo`
- **Functions:** `IDSource.make()`; `LayoutTree.init(root:nodes:states:)`, `validate()`, `node(_:)`, `parent(of:)`, `windows`, `leaf(containing:)`, `state(of:)`, `insertRoot(_:ids:)`, `insert(_:at:of:ids:)`, `remove(_:)`, `resizeBoundary(in:after:by:)`, `group(_:into:)`, `selectTab(_:)`, `setState(_:for:)`, `applyDrop(_:window:ids:)`; `resolve(_:in:mins:gap:)`; `DropZones.target(at:in:tree:resolution:)`; `DesktopLayer.add/remove/setFrame/setState/frame(of:)/contains/validate`; `Desk.validate()`, `Desk.contains(_:)`, `Desk.setState(_:for:)`; `World.init(ids:desks:)`, `validate()`, `addDesk(_:)`, `edit(_:history:_:)`, `undo(_:history:)`, `encoded()`, `decode(from:)`, `decode(from:migrations:)`; `MigrationChain.migrate(_:from:to:)`; `UndoHistory.depth(for:)`
- **Constants:** `LayoutTree.minWeight = 0.01`, `maxDepth = 64`, `maxNodes = 4096`, `maxChildren = 100`; `Geometry.maxCoordinate = 1_000_000`; `World.currentSchemaVersion = 1`, `World.maxEncodedBytes = 16 MiB`; `UndoHistory.limit = 50`; `DropZones.edgeBandFraction = 0.25`, `DropZones.displayEdgeBand = 24`
