---
phase: 01-layout-model
reviewed: 2026-10-24T06:15:30Z
depth: standard
files_reviewed: 28
files_reviewed_list:
  - .github/workflows/ci.yml
  - Package.swift
  - Sources/PaneEngine/WindowSystem.swift
  - Sources/PaneModel/DesktopLayer.swift
  - Sources/PaneModel/DropZones.swift
  - Sources/PaneModel/Geometry.swift
  - Sources/PaneModel/IDs.swift
  - Sources/PaneModel/LayoutTree.swift
  - Sources/PaneModel/Persistence.swift
  - Sources/PaneModel/Resolve.swift
  - Sources/PaneModel/TreeEdits.swift
  - Sources/PaneModel/Undo.swift
  - Sources/PaneModel/World.swift
  - Tests/PaneModelTests/DesktopLayerTests.swift
  - Tests/PaneModelTests/DropZoneTests.swift
  - Tests/PaneModelTests/InvariantTests.swift
  - Tests/PaneModelTests/LifecycleTests.swift
  - Tests/PaneModelTests/NoAppKitTests.swift
  - Tests/PaneModelTests/PersistenceTests.swift
  - Tests/PaneModelTests/ResolveFuzzTests.swift
  - Tests/PaneModelTests/ResolveTests.swift
  - Tests/PaneModelTests/ScenarioTests.swift
  - Tests/PaneModelTests/SkeletonTests.swift
  - Tests/PaneModelTests/TabsTests.swift
  - Tests/PaneModelTests/TreeEditTests.swift
  - Tests/PaneModelTests/TreeFuzzTests.swift
  - Tests/PaneModelTests/UndoTests.swift
  - scripts/check-no-appkit.sh
findings:
  critical: 3
  warning: 7
  info: 7
  total: 17
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-10-24T06:15:30Z
**Depth:** standard
**Files Reviewed:** 28 (the prompt says 15 test files but lists 14 names. All 14 files in `Tests/PaneModelTests/` were reviewed.)
**Status:** issues_found

## Summary

The model is mostly careful. Every edit works on a copy, the water-filling and rounding arguments hold (I traced the floor/remainder bound and the pin monotonicity), decoding is cycle-safe and iterative, and the encoding is deterministic. The defects sit in three places:

1. **Guarantees that only hold in DEBUG.** `assertValid()` is the only post-edit check in `TreeEdits.swift`, and it compiles out in release. Two edit paths really do produce invalid trees: the depth guard checks the wrong node, and a lagging `IDSource` overwrites nodes. In debug builds these trap. In release they commit silently. CI only runs debug, so this is never seen.
2. **Untrusted-file crash.** A saved file with `ids.next` at or near `UInt64.max` decodes and validates. The first edit then hits `preconditionFailure` and kills the process.
3. **Lifecycle vs. undo.** Observed OS state (absent/closed) goes through the same snapshot-undo funnel as user edits. Undo can bring back closed windows, and one conflicting snapshot blocks the desk's whole undo stack.

Every BLOCKER and most WARNINGs were reproduced with a scratch probe package that depends on this repo by path (release and debug builds). WR-06 was shown with a mutation run: making `resolve` ignore weights entirely still passes all 125 tests.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Hostile `ids.next` near `UInt64.max` passes validation, then crashes the process on the first edit

**File:** `Sources/PaneModel/IDs.swift:48-52`, `Sources/PaneModel/World.swift:60-71`
**Issue:** `IDSource.make()` calls `preconditionFailure("IDSource exhausted")` when `next == UInt64.max`. `World.validate()` only checks that every NodeID is below `ids.next`. It never bounds `ids.next` itself. JSONDecoder decodes the full UInt64 range, so this file decodes cleanly through `World.decode`:
```json
{"desks":[{"desk":{"desktop":{"windows":[]},"tree":{"nodes":{},"states":[]}},"key":{"displayUUID":"D1"}}],"ids":{"next":18446744073709551615},"schemaVersion":1}
```
Then `world.edit(k) { try $0.tree.insertRoot(w, ids: &$1) }` traps. This was reproduced: the release build exits with 133 (SIGTRAP), `IDs.swift:49: Fatal error: IDSource exhausted`. `next = UInt64.max - 1` crashes on the second insert. The file is never repaired, so the app crashes on the first drop of every session. This is exactly the corrupt/hostile-file class (T-01-09) the phase is meant to defend against, and the corpus in `PersistenceTests.swift:71-110` has no case for it.
**Fix:** Make exhaustion a typed error instead of a trap, and reject absurd values at load:
```swift
// IDs.swift
public mutating func make() throws(LayoutError) -> NodeID {
    guard next < UInt64.max else { throw .invariantViolated("IDSource exhausted") }
    defer { next += 1 }
    return NodeID(raw: next)
}
// World.validate()
guard ids.next <= UInt64.max - UInt64(LayoutTree.maxNodes) * 2 else {
    throw .invariantViolated("ID source \(ids.next) is too close to exhaustion")
}
```
Then add `"ids.next = UInt64.max"` to `corruptCorpus` (expect `.invalidLayout`), plus a test that `edit` throws rather than traps.

### CR-02: `insert`'s depth guard measures the new leaf, not the subtree that rule 3 pushes one level deeper

**File:** `Sources/PaneModel/TreeEdits.swift:46-59`
**Issue:** When rule 3 wraps the **root** split (lines 52-53, `next.root = split`), every existing node moves one level deeper. The guard at line 59 checks only `next.depth(of: leaf)`, which is 1. A tree at the depth limit (deepest leaf at 64) whose root is horizontal accepts `insert(_, at: .top, of: root)`. That is exactly what `applyDrop(.layoutEdge(.top))` does (`DropZones.swift:61`), and it produces a 65-deep tree. Reproduced:
- debug: `LayoutTree.swift:169: Fatal error: LayoutTree invariant violated: tooDeep(limit: 64)`. A normal user drop on the display edge crashes the debug app, and it crashes inside `World.edit` too, because `assertValid()` runs before `candidate.validate()`.
- release: `insert` returns normally, and `validate()` afterwards fails with `tooDeep`. The documented "throwing edit leaves no trace / every edit ends valid" guarantee is broken.

`InvariantTests.insertBeyondDepthLimitThrowsAndLeavesTreeUnchanged` (lines 151-166) only docks beside the deepest leaf, so it passes while this path is wrong. (A non-root split target can never reach rule 3, because alternating axes force rule 1 or 2. So the root wrap is the only bad case.)
**Fix:** Before committing, validate the whole candidate instead of the single-node probe. The cost is O(nodes), and `World.edit` already pays it:
```swift
try next.normalize()
try next.validate()   // replaces the nodes.count / depth(of: leaf) guards; throws tooDeep / tooManyNodes
self = next
ids = nextIDs
```
Add a test: a 64-deep chain with a horizontal root, `applyDrop(.layoutEdge(.top))` → `#expect(throws: LayoutError.tooDeep(limit: 64))`, and the tree is unchanged.

### CR-03: A lagging `IDSource` makes `insert` overwrite existing nodes; in release a window is silently dropped from the tree

**File:** `Sources/PaneModel/TreeEdits.swift:29-33, 47-48`, `Sources/PaneModel/LayoutTree.swift:32, 167-171`
**Issue:** `insert` does `next.nodes[leaf] = .panel(window)` (and `next.nodes[split] = …`) without checking that the freshly made ID is unused. The public API takes any `IDSource`, and `IDSource(next:)` is public, so nothing ties the source to the tree outside `World`. Reproduced in release: build H[n1:w1, n2:w2] under n3, then `insert(w3, at: .right, of: n2, ids: &IDSource())`. The call returns successfully with `nodes = [n3: H[n1, n2, n1], n2: w2, n1: w3]`. Window w1 is gone from the nodes but still in `states`, and n1 is listed twice. Only a later explicit `validate()` notices. The type's doc comment says "Every way of building one (init, decoding, edits) ends in `validate()`", but for edits that is DEBUG-only (`assertValid`, lines 167-171). `World.edit` happens to catch it, because World's validate enforces `node.raw < ids.next`. Any standalone `LayoutTree` user (Phase 3 previews, saved views, tests built with `IDSource(next: 10)` as in `TreeEditTests.swift:151`) gets silent data loss.
**Fix:** Refuse colliding IDs, and validate unconditionally (same change as CR-02):
```swift
let leaf = nextIDs.make()
guard next.nodes[leaf] == nil else { throw .invariantViolated("ID source issued \(leaf), which is already in the tree") }
// same guard after `let split = nextIDs.make()`
```
Also fix or drop the doc claim at `LayoutTree.swift:32`, or make the post-edit check run in release.

## Warnings

### WR-01: A confirmed-closed window can be impossible to remove (`setState(.closed)` throws `splitFull`)

**File:** `Sources/PaneModel/TreeEdits.swift:130-131, 183-186`; `Sources/PaneModel/World.swift:21-29`
**Issue:** `.closed` is defined as "removes the slot, exactly as `remove(_:)`", and `remove` refuses when the collapse would merge more than `maxChildren` children. Reproduced: H[50 panels, V[B, H[60 panels]]] followed by `setState(.closed, for: B)` throws `splitFull(n1, limit: 100)`, and B stays `.present`. The OS has already confirmed the window is gone (two sources), but the model cannot drop it. `resolve` keeps reserving a tile for a dead window, and the next phase will issue `setFrame` to it. No API offers a way to recover. The trigger needs more than 100 windows in one desk, so it is unlikely in practice, but it is a hard failure of a contract that must not fail.
**Fix:** Make removal infallible. `maxNodes` already bounds hostile input, so keep `maxChildren` only for user-driven growth (`adding`) and let merges exceed it. Relax `validate`'s child cap to `2...maxNodes`, or to a separate larger bound, so a merged split still round-trips through JSON. Alternatively, when the merge overflows, keep the inner split by not collapsing it (store B's slot as removed and re-parent the remaining child under a fresh split on the other axis).

### WR-02: One un-restorable snapshot permanently blocks a desk's entire undo stack

**File:** `Sources/PaneModel/World.swift:98-108`
**Issue:** If the newest snapshot fails `candidate.validate()` (for example a window that has since moved to another desk), `undo` throws and leaves the history untouched. Every later undo on that desk hits the same snapshot and throws again, so all older entries are unreachable until the conflicting window leaves the other desk. Reproduced: `undo 1/2/3 threw duplicateWindow(window 9 …), depth 3`. `UndoTests.undoThatWouldPutAWindowOnTwoDesksThrowsAndChangesNothing` asserts this behaviour (depth stays 2). The test pins the bug in place rather than catching it.
**Fix:** When a snapshot is no longer valid, discard it (commit `history = nextHistory`) and either report it (`throws` after popping, or return an enum `.restored / .nothing / .discarded(LayoutError)`) or keep popping until a valid snapshot is found. Update the test to expect the stale entry to be consumed.

### WR-03: Observed lifecycle changes go on the user's undo stack, so undo brings back closed windows and overrides OS state

**File:** `Sources/PaneModel/World.swift:80-92, 98-108` (exercised by `Tests/PaneModelTests/ScenarioTests.swift:133, 141, 146-150`)
**Issue:** `edit` is documented as "the one way to change a desk", and it always pushes a full `Desk` snapshot that includes `states`. Lifecycle transitions (absent/fullscreen/closed, which are facts reported by the OS) must therefore go through it, as the scenario test does. Reproduced: dock w1 and w2, then `edit { setState(.closed, for: w2) }`, then `undo` → w2 is back as `.present`, although the window no longer exists. The same applies to sleep/wake churn. Each absent/present flip uses one of the 50 undo levels and evicts real user edits. The user's next Cmd-Z undoes a system event instead of their own edit. Restored snapshots also bring back stale `.present` for windows that are currently absent.
**Fix:** Separate observed state from user intent. Add a validated, history-free mutation for lifecycle events, e.g. `public mutating func apply(_ key: DeskKey, _ change: …) throws(LayoutError)` that commits without `history.push`. In `undo`, carry the current lifecycle facts into the restored snapshot: drop windows that are no longer on the desk, and keep current `absent`/`fullscreen` states.

### WR-04: A migration step that produces a non-JSON value crashes the process with an uncaught NSException

**File:** `Sources/PaneModel/Persistence.swift:51-59`
**Issue:** `JSONSerialization.data(withJSONObject:)` raises an Objective-C `NSInvalidArgumentException` for invalid objects, and Swift `do/catch` cannot catch it. Reproduced with a step that sets `object["stamp"] = Date()`: `*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'Invalid type in JSON write (__NSTaggedDate)'`. A buggy migration then crashes every launch while loading the user's file, instead of returning `.corrupt`.
**Fix:**
```swift
try migrations.migrate(&object, from: version, to: currentSchemaVersion)
guard JSONSerialization.isValidJSONObject(object) else {
    throw PersistenceError.corrupt("migration to schema \(currentSchemaVersion) produced a non-JSON value")
}
```

### WR-05: The no-AppKit gate (D-23) is easy to bypass

**File:** `scripts/check-no-appkit.sh:11`
**Issue:** The regex requires the module name to be followed by whitespace, `.`, or end-of-line, allows only attributes without arguments, and anchors to the start of the line. All of these compile and pass the check (verified, exit 0):
- `import AppKit;`
- `@_spi(Private) import AppKit`
- `import Foundation; import AppKit` (second import on the same line)

Umbrella frameworks that re-export AppKit (`import WebKit`, `import Quartz`, `import Carbon`) also pass, so the "headless-testable" property is not actually enforced.
**Fix:** At minimum, extend the regex to `(^|;)[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+(…)?(AppKit|Cocoa|SwiftUI|WebKit|Quartz|Carbon)([^A-Za-z0-9_]|$)` and add those lines to `NoAppKitTests.violationFails`. For a robust check, build with `-Xswiftc -emit-loaded-module-trace` and fail if the trace for PaneModel/PaneEngine lists AppKit. That also catches transitive imports.

### WR-06: Test gap — `resolve` can ignore split weights entirely and all 125 tests still pass

**File:** `Tests/PaneModelTests/ResolveTests.swift:151-161`, `Tests/PaneModelTests/ResolveFuzzTests.swift:80-104` (code: `Sources/PaneModel/Resolve.swift:156`)
**Issue:** Mutation run: replacing `share[i] = free * parts[i].weight / weight` with an equal share (`free / unpinnedCount`) gives `✔ Test run with 125 tests in 14 suites passed`. Every exact-rect assertion uses equal weights (0.5/0.5 or thirds). The only unequal-weight resolve test (`resolveIsDeterministicAndLaysChildrenOutInOrder`, 0.3/0.7 and 0.6/0.4) only checks adjacency. The fuzz properties P1-P8 never compare sizes against weights. The core layout behaviour, honouring the user's weights, has no test.
**Fix:** Add an exact case and a fuzz property:
```swift
@Test func unequalWeightsSplitTheLengthProportionally() throws {
    let r = try resolve(try pair(weights: [0.3, 0.7]), in: wide, mins: [:], gap: 0)
    #expect(r.windowRects[a] == Rect(x: 0, y: 0, width: 300, height: 500))
    #expect(r.windowRects[b] == Rect(x: 300, y: 0, width: 700, height: 500))
}
```
In the fuzz test, for every split where no child is pinned (each length > its min), check `|length_i - weight_i/Σw · available| <= 1` for non-last children.

### WR-07: CI never builds or tests release, so all DEBUG-only invariant enforcement is untested where it matters

**File:** `.github/workflows/ci.yml:15-16`; `Sources/PaneModel/LayoutTree.swift:167-171`
**Issue:** `swift build` / `swift test` run in debug only, so `assertValid()` is always active in CI. CR-02 and CR-03 behave differently in release (silent invalid commit vs. trap), and no pipeline ever sees the release behaviour. The suite therefore cannot detect "the edit committed an invalid tree".
**Fix:** Add `swift build -c release` and `swift test -c release -Xswiftc -enable-testing` (needed for `@testable import`) to CI. Better still, apply the CR-02 fix (unconditional `try next.validate()` before commit) so the two configurations behave the same.

## Info

### IN-01: Weight tolerance mismatch (validate 1e-9 vs. normalise 1e-12) rewrites unrelated splits on any edit

**File:** `Sources/PaneModel/LayoutTree.swift:91`, `Sources/PaneModel/TreeEdits.swift:159-163, 202-204`
**Issue:** `validate` accepts weights summing to within 1e-9, but `isNormalised` requires 1e-12. `normalize()` scans **every** split. A decoded or migrated file with slop between 1e-12 and 1e-9 is accepted, then the first insert/remove/resize anywhere renormalises those splits. That breaks D-07's "every other weight bit-identical" for the resized split and silently changes splits the user never touched.
**Fix:** Use one tolerance constant for both checks, or canonicalise weights once at decode/init so later edits are bit-stable.

### IN-02: `resolve` rejects invalid minimums for windows that are not in the tree

**File:** `Sources/PaneModel/Resolve.swift:34-38`
**Issue:** Minimums for windows outside the tree are documented and tested as ignored (`minimumsForWindowsOutsideTheTreeAreIgnored`). An invalid one (NaN or negative) for such a window still throws `invalidMinimum`, so one stale learned-minimum entry for an unrelated window blocks every layout.
**Fix:** Validate only the minimums of present tree windows, inside the candidate loop.

### IN-03: `World.edit` pushes an undo snapshot even when the change is a no-op

**File:** `Sources/PaneModel/World.swift:83-92`
**Issue:** `edit(k) { _, _ in }` uses one undo level, and the user then has to press undo once with nothing visibly happening.
**Fix:** `guard desk != before else { return }` before `history.push`.

### IN-04: `UndoHistory` is not bound to a World

**File:** `Sources/PaneModel/Undo.swift:7-25`, `Sources/PaneModel/World.swift:98-108`
**Issue:** Histories are keyed only by `DeskKey`. After a reload or a replaced World, an old history can restore a foreign snapshot over a desk, and it passes `validate()` whenever IDs happen to be below `ids.next`.
**Fix:** Stamp each history with a World generation token, or have callers clear the history on reload. Document whichever you choose.

### IN-05: GitHub Action not pinned to a commit SHA

**File:** `.github/workflows/ci.yml:12`
**Issue:** `actions/checkout@v5` is a mutable tag.
**Fix:** Pin to the full commit SHA, with the version in a comment.

### IN-06: `WindowSystem.events` is a unicast `AsyncStream`

**File:** `Sources/PaneEngine/WindowSystem.swift:72-76`
**Issue:** If more than one consumer iterates `events` (reconciler and UI, for example), events are split between them unpredictably. The draft protocol doesn't say there must be a single consumer.
**Fix:** Document "single consumer", or expose a factory (`func makeEventStream() -> AsyncStream<WindowEvent>`).

### IN-07: No cap on windows per tab group / per tree

**File:** `Sources/PaneModel/LayoutTree.swift:100-105`
**Issue:** `maxNodes` bounds nodes, but one `.tabs` node can hold an unlimited number of windows (only `>= 2` is checked). A 16 MB hostile file can put tens of thousands of windows in one tab group. That undermines the stated purpose of the hostile-input limits, and several O(windows × nodes) paths (`leaf(containing:)`, the victim loop in `resolve`) then scale with it.
**Fix:** Add `maxTabs` (e.g. 100) checked in `validate` and `group`, or a `maxWindows` limit per tree.

---

_Reviewed: 2026-10-24T06:15:30Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
