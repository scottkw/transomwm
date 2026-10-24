---
phase: 01-layout-model
plan: 01
subsystem: layout-model
tags: [swift, swiftpm, swift-testing, codable, value-types]

requires: []
provides:
  - "SwiftPM package Pane (tools 6.2, macOS 14, Swift 6 mode) with PaneModel library and PaneModelTests"
  - "Geometry: Point, Size, Rect (contains/overlaps/isValidGeometry), Axis, Edge, Geometry.maxCoordinate"
  - "IDs: NodeID (bare-number Codable, CodingKeyRepresentable), IDSource, WindowIdentity, WindowRef (identity-only equality, title-free description), WindowState, DeskKey"
  - "LayoutTree flat store with LayoutError, full validate(), validating init and deterministic Codable"
  - "insertRoot / insert(_:at:of:ids:) with D-04 n-ary docking, splitFull/tooDeep/tooManyNodes limits"
  - "resolve(_:in:mins:gap:) by weights with whole-point rounding and gaps (mins/unfit come in 01-03)"
  - "Desk, World(ids:desks:) with cross-desk validation and deterministic Codable"
  - "World.encoded() / World.decode(from:) with schemaVersion 1 and PersistenceError"
affects: [01-02, 01-03, 01-04, 01-05, 01-06, phase-2, phase-3, phase-8]

actuals:
  tokens: 10928
  tasks: 2
  commits: 3
plan_head_before: d3d03bc98e56f2890d1a700a3d5c1cb2aeea38fb
plan_head_after: 273ae67f8c2079707be8737ded787d061146a075

tech-stack:
  added: [Swift Testing]
  patterns:
    - "Edits work on copies of the tree and IDSource and commit both only on success"
    - "Every construction path (init, decode, edit) ends in validate(); DEBUG assertValid() after edits"
    - "Deterministic JSON: sortedKeys plus dictionaries stored as arrays sorted by key"
    - "Iterative traversals with explicit stacks; no recursion over untrusted trees"

key-files:
  created:
    - Package.swift
    - Sources/PaneModel/Geometry.swift
    - Sources/PaneModel/IDs.swift
    - Sources/PaneModel/LayoutTree.swift
    - Sources/PaneModel/TreeEdits.swift
    - Sources/PaneModel/Resolve.swift
    - Sources/PaneModel/World.swift
    - Sources/PaneModel/Persistence.swift
    - Tests/PaneModelTests/SkeletonTests.swift
    - Tests/PaneModelTests/InvariantTests.swift
  modified: []

key-decisions:
  - "Tree depth counts edges from the root (root = depth 0): a 64-split chain is accepted, 65 is rejected with tooDeep(limit: 64)"
  - "LayoutTree root/nodes/states are public internal(set), not private(set), so TreeEdits.swift (a separate file) can write them; read-only outside the module as specified"
  - "WindowRef also conforms to CustomDebugStringConvertible with the title-free text, because String(describing:) of an error payload prefers debugDescription"
  - "NodeID dictionary keys accept canonical decimal only, so \"01\" and \"1\" cannot decode to the same key"
  - "Duplicate state or desk records in JSON are rejected (invariantViolated / deskExists) instead of last-one-wins"
  - "Work committed on new branch gsd/phase-01-layout-model because main is protected and the commit guard refuses it"

patterns-established:
  - "makeWindow(_:title:) in SkeletonTests.swift is the shared test helper for WindowRefs"
  - "Typed throws (throws(LayoutError) / throws(PersistenceError)) on every model API"

requirements-completed: [MODEL-01, MODEL-02, MODEL-04, MODEL-07, MODEL-09]

coverage:
  - id: D1
    description: "Window B docked right of A in 1000x500 with gap 10 resolves to A=(10,10,485,480), B=(505,10,485,480)"
    requirement: MODEL-04
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#dockResolveStoreAndRoundTrip()"
        status: pass
    human_judgment: false
  - id: D2
    description: "One-desk World encodes with \"schemaVersion\":1, decodes equal and re-encodes byte-identically"
    requirement: MODEL-09
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#dockResolveStoreAndRoundTrip()"
        status: pass
    human_judgment: false
  - id: D3
    description: "Docking on each edge splits on the matching axis with the window on that side; same-axis docking adds an n-ary sibling at 1/(n+1)"
    requirement: MODEL-02
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#dockOnEdgeSplitsOnItsAxisWithWindowOnThatSide(edge:)"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#dockingBesideSameAxisSiblingAddsNarySibling()"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#dockingBesideSameAxisSplitAddsItsFirstChild()"
        status: pass
    human_judgment: false
  - id: D4
    description: "Duplicate window insert throws duplicateWindow, unknown target throws nodeNotFound; tree and IDSource unchanged"
    requirement: MODEL-02
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#badInsertThrowsAndLeavesTreeAndIDsUnchanged()"
        status: pass
    human_judgment: false
  - id: D5
    description: "WindowRef equality/hash ignore titleHint; description and error text never contain the title"
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#windowRefIdentityIgnoresTitleAndDescriptionHidesIt()"
        status: pass
    human_judgment: false
  - id: D6
    description: "Negative-origin rects are valid geometry and resolve with negative coordinates"
    requirement: MODEL-04
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#negativeOriginIsValidAndResolves()"
        status: pass
    human_judgment: false
  - id: D7
    description: "Every listed invariant violation (hand-built or decoded) is rejected with a typed LayoutError; inserts cannot exceed depth 64 or 4096 nodes"
    requirement: MODEL-01
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/InvariantTests.swift (13 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D8
    description: "DeskKey(displayUUID:spaceID:) keys World desks"
    requirement: MODEL-07
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/SkeletonTests.swift#dockResolveStoreAndRoundTrip()"
        status: pass
    human_judgment: false

duration: 6min
completed: 2026-10-24
status: complete
---

# Phase 1 Plan 01: Layout Model Walking Skeleton Summary

**Swift 6 package with a flat, validated `LayoutTree`. You can dock a window on any edge (n-ary on the same axis), resolve the tree into whole-point rects with gaps, store it in a `DeskKey`-keyed `World`, and round-trip it through deterministic `schemaVersion: 1` JSON. Every malformed tree is rejected with a typed `LayoutError`.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-10-24T04:48:22Z
- **Completed:** 2026-10-24T04:54:07Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- End-to-end path: insertRoot(A) → insert(B, at: .right) → resolve → World → encoded() → decode(from:) → byte-identical re-encode
- Docking rules from D-04: a sibling for a same-axis parent, first or last child for a same-axis split target, otherwise wrap in a 0.5/0.5 split. None of them creates a same-axis child split
- The full invariant checker counts nodes first, then walks the tree iteratively with a visited set and a depth limit, so hostile JSON cannot recurse or loop (T-01-01)
- Persisted JSON is deterministic: sorted keys, states and desks as sorted record arrays, NodeIDs as bare numbers and decimal-string object keys
- `swift test`: 20 tests in 2 suites pass (SkeletonTests 7, InvariantTests 13). No warnings, and release builds too

## Task Commits

1. **Task 1: Walking skeleton (tracer)** - `8c96748` (feat)
2. **Task 2: Full invariant checker** - RED `cca1d9c` (test), GREEN `273ae67` (feat); no refactor needed

## TDD Gate Compliance (Task 2)

- **RED** (`cca1d9c`): 13 tests written against the partial Task 1 `validate()`. Ran `NO_COLOR=1 swift test --filter InvariantTests`: exit 1, 12 failed, 1 passed. The classifier (`check tdd-red-evidence`, swift-testing adapter) returned `RED_EVIDENCE_OK` / `target_test_failed` for target `rejectsChainDeeperThanLimit()`.
- **Semantic assessment:** the target ran and failed on its planned `#expect(throws: LayoutError.tooDeep(limit: 64))` assertion ("an error was expected but none was thrown"). All 12 failures are assertion failures for invariants the Task 1 checker lacked. One `Caught error: .duplicateWindow` follows directly from the over-deep insert wrongly succeeding, and one `Issue.record` is the cyclic JSON decoding when it should not. The build succeeded, with no crash and no load or fixture faults. The one passing test is the valid-tree acceptance case.
- **GREEN** (`273ae67`): full `validate()` plus the insert limits. `swift test`: 20/20 pass.
- **REFACTOR:** none needed.

## Files Created/Modified
- `Package.swift` - package Pane: PaneModel library and PaneModelTests, tools 6.2, macOS 14, Swift 6 mode, no dependencies
- `Sources/PaneModel/Geometry.swift` - Point/Size/Rect, Axis, Edge, coordinate-space doc
- `Sources/PaneModel/IDs.swift` - NodeID, IDSource, WindowIdentity, WindowRef, WindowState, DeskKey
- `Sources/PaneModel/LayoutTree.swift` - Node, LayoutError, LayoutTree with validate(), accessors, Codable
- `Sources/PaneModel/TreeEdits.swift` - insertRoot, insert, the n-ary adding helper
- `Sources/PaneModel/Resolve.swift` - Resolution and resolve() by weights
- `Sources/PaneModel/World.swift` - Desk, World with validation and Codable
- `Sources/PaneModel/Persistence.swift` - PersistenceError, encoded(), decode(from:)
- `Tests/PaneModelTests/SkeletonTests.swift` - 7 skeleton tests plus the shared `makeWindow` helper
- `Tests/PaneModelTests/InvariantTests.swift` - 13 invariant and limit tests

## Decisions Made
- **Depth semantics:** depth counts edges from the root (root = 0). maxDepth 64 accepts a 64-split chain and rejects 65, and `chain(splits: 64)` is tested as accepted to pin this down.
- **Encoded shape** (costly to change later): `{"desks":[{"desk":{"tree":{"nodes":{"<id>":{"panel":{"_0":{...}}}|{"split":{...}}},"root":N,"states":[{"state":..,"window":{..}}]}},"key":{...}}],"ids":{"next":N},"schemaVersion":1}`. Node uses synthesised enum Codable, so a panel payload sits under `_0`.
- **Branching:** HEAD was `main`. `git.base-branch --is-protected main` returned true and no `git.allow_default_branch_commits` override is set, so the per-commit guard would refuse. I created `gsd/phase-01-layout-model` (the configured `phase_branch_template`) before the first commit. All plan commits are on that branch. `main` is still at `d3d03bc`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `private(set)` on LayoutTree storage would block edits in TreeEdits.swift**
- **Found during:** Task 1
- **Issue:** `<interfaces>` says `public private(set) var root/nodes/states`, but the plan also puts the edits in a separate file (TreeEdits.swift), and Swift's `private(set)` is file-scoped.
- **Fix:** `public internal(set)`. The public API is unchanged (read-only outside PaneModel).
- **Files modified:** Sources/PaneModel/LayoutTree.swift
- **Committed in:** 8c96748

**2. [Rule 2 - Missing critical] Title leak through error descriptions**
- **Found during:** Task 1
- **Issue:** `String(describing:)` / `String(reflecting:)` of a `LayoutError` payload uses `debugDescription`, so the synthesised one would print `titleHint` (T-01-02).
- **Fix:** WindowRef also conforms to `CustomDebugStringConvertible` with the same title-free text. A test asserts that both forms leave the title out.
- **Files modified:** Sources/PaneModel/IDs.swift, Tests/PaneModelTests/SkeletonTests.swift
- **Committed in:** 8c96748

**3. [Rule 2 - Missing critical] Ambiguous or duplicate JSON keys and records**
- **Found during:** Task 1
- **Issue:** decoding could silently collapse `"01"` and `"1"` node keys, or duplicate state or desk records (last one wins).
- **Fix:** NodeID keys accept canonical decimal only. Duplicate state records throw `invariantViolated` and duplicate desk records throw `deskExists`, both wrapped as the DecodingError's `underlyingError` so Persistence maps them to `.invalidLayout`.
- **Files modified:** Sources/PaneModel/IDs.swift, LayoutTree.swift, World.swift
- **Committed in:** 8c96748

**4. [Rule 1 - Bug prevention] Failed insert must not consume NodeIDs**
- **Found during:** Task 1
- **Issue:** a throwing insert after `ids.make()` would advance the caller's IDSource.
- **Fix:** the edits copy `ids` too and commit it only on success. Tested (`ids == idsBefore`).
- **Committed in:** 8c96748

**5. [Rule 3 - Blocking] Swift Testing argument literal too complex to type-check**
- **Found during:** Task 2 (RED)
- **Issue:** inline tuple arrays in `@Test(arguments:)` failed with "unable to type-check this expression in reasonable time".
- **Fix:** moved them into typed file-scope constants `malformedSplits` and `malformedTabs`.
- **Committed in:** cca1d9c

---

**Total deviations:** 5 auto-fixed (2 blocking, 2 missing critical, 1 bug prevention)
**Impact on plan:** all were needed for correctness, security or compiling. No scope creep, and the public names and signatures match `<interfaces>`.

## Known Limitations (intentional, owned by later plans)
- `Sources/PaneModel/TreeEdits.swift:64`: the n-ary rule scales sibling weights by n/(n+1) with no clamp. A hand-built sibling near `minWeight` (for example 0.01 next to 0.99) can drop below it, and `assertValid()` would then trap in DEBUG. Plan 01-02's `normalize()` adds the clamp and makes `insert` call it. Inserts alone (equal 1/k weights) never hit this.
- `resolve` ignores `mins` and never fills `unfit`. Plan 01-03 adds water-filling, unfit reporting, lifecycle exclusion and input validation.
- `insertRoot` has no tooDeep/tooManyNodes check, because it only runs on an empty tree (1 node, depth 0) and cannot exceed either limit.
- `PersistenceError.tooLarge` is declared but unused until Plan 01-04 adds the 16 MiB cap.

## Issues Encountered
None beyond the deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plans 01-02 to 01-05 can build on these types and signatures unchanged. Plan 01-06 adds the PaneEngine target to Package.swift.
- The orchestrator should note the branch: work is on `gsd/phase-01-layout-model`, not `main`.

## Self-Check: PASSED
- All 10 key files exist on disk
- Commits 8c96748, cca1d9c, 273ae67 are ancestors of HEAD; `check evaluation-scope --plan 01-01 --commits-only` resolved all 3
- Plan verification: `swift build` exit 0; `swift test` exit 0 with 20 tests in 2 suites passed and no `✘`; `grep -rhE "^import " Sources/PaneModel | sort -u` prints only `import Foundation`
- All acceptance criteria of Tasks 1 and 2 re-run: PASS

---
*Phase: 01-layout-model*
*Completed: 2026-10-24*
