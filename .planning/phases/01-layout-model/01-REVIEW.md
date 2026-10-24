---
phase: 01-layout-model
reviewed: 2026-10-24T07:20:23Z
depth: standard
iteration: 3
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
  critical: 0
  warning: 2
  info: 10
  total: 12
status: issues_found
---

# Phase 1: Code Review Report (iteration 3, final)

**Reviewed:** 2026-10-24T07:20:23Z
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

This pass re-reviewed the phase after the iteration-2 fix commits `971a691` (WR-01: a close purges undo history) and `ac3dabc` (WR-02: the ID headroom check runs at load only). It checked that both fixes are correct and complete, looked for regressions they introduced, and assessed the two edge cases the fixer left out of scope.

`swift test` and `swift test -c release -Xswiftc -enable-testing` both pass 139 tests in 14 suites (re-run for this review). Behavioural claims below were reproduced with a scratch probe package in release mode, where `assertValid()` is compiled out. The probe depends on this repo by path, lives in the session scratchpad, and is not part of the repo.

**Prior-fix verification**

| Prior | Verdict | Evidence |
|-------|---------|----------|
| WR-01 (close/undo purge) | **Fixed for the reported sequences, with one remaining hole (see WR-02 below)** | `apply(.closed)` now finds the holder desk itself (`World.swift:123-126`) and always calls `history.forget` after a successful commit (`:132`). The public `LayoutTree.setState` (`TreeEdits.swift:136`), `Desk.setState` (through `DesktopLayer.setState:42`) and `DesktopLayer.setState` reject `.closed`, so a close can no longer be made inside `edit`. `Desk.close` is internal. `UndoHistory.forget`'s `try!` is still safe, because `Desk.close` on a snapshot that holds the window only throws `windowNotFound`. The ScenarioTests flow now goes through `apply`. No regression found in the `.absent`/`.fullscreen`/`.present` paths: they are still desk-scoped and still throw `windowNotFound`. |
| WR-02 (load-only headroom) | **Fixed** | The bound `ids.next <= UInt64.max / 2` is in `World(ids:desks:)` (`World.swift:71`), which is the only constructor that takes an arbitrary `IDSource`, and `init(from:)` routes through it (`:179`). `validate()` no longer checks headroom, so `edit`, `apply` and `undo` stop only where `IDSource.make()` throws. The new corpus case (`.max / 2 + 1`) is rejected as `.invalidLayout`. |

**Assessment of the fixer's out-of-scope edge cases**

- **(a) Undo restores a stale lifecycle state for a window that is on no desk:** confirmed in both directions, and reachable with ordinary user actions (move a window across desks, then Cmd-Z). The result is a visible layout error that lasts until the OS happens to report that window again. Rated **Warning**, see WR-01.
- **(b) Code inside `edit` can push the ID source past the load bound, so the saved World is refused at load:** confirmed (`ids = IDSource(next: .max / 2 + 10)` inside `edit` commits, and the saved bytes then fail `World.decode` with `invalidLayout`). The same hole also allows a *rewind*, which breaks the "NodeIDs are not reused" promise and makes undo snapshots unrestorable. Natural use cannot get there: it would take about 2^63 `make()` calls. It needs either API misuse or a hostile file already at the bound. Rated **Info**, see IN-10.

The 9 earlier Info items (IN-01..IN-09) were out of fix scope. All 9 are still present and listed again below.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Undo restores a window that is on no desk with whatever lifecycle state its snapshot held

**File:** `Sources/PaneModel/World.swift:141-152` (carry-over at lines 144-146), `Sources/PaneModel/World.swift:120-129`
**Issue:** `undo` copies the current lifecycle state onto the snapshot only for windows that are on `key`'s desk right now (`current.state(of: window)`). Take a window that a move and an undo took off every desk. The model has nowhere to record OS facts about it: `apply(.absent/.present, w, on: anyKey)` throws `windowNotFound` (confirmed). When a later undo brings the window back, it keeps the state from the old snapshot, which may be stale. Both directions were reproduced in release:

```
// (1) A minimised window is given a tile: a visible hole.
edit k1: dock a, w     edit k1: remove w     edit k2: insertRoot w      // move w from k1 to k2
apply(.absent, w, on: k2)                                                // user minimises w
undo k2                                                                  // w on no desk
apply(.absent, w, on: k1) -> windowNotFound
undo k1  -> state(w) == .present; resolve gives w x:500 w:500. a gets only half the screen, next to an empty tile.

// (2) A visible window is not tiled.
edit k1: dock a, w     apply(.absent, w, on: k1)     edit k1: remove w   // snapshot holds w as .absent
edit k2: insertRoot w (w is .present, on screen)     undo k2     undo k1
-> state(w) == .absent; resolve gives w no rect, though the window is on screen
```

Either way, the error lasts until the OS next reports an event for that window. For a minimised window that can be indefinitely. The undo doc comment (lines 135-136) is accurate about windows "still on the desk", but says nothing about this case, so the engine has no way to know it must re-sync. This is the stale-state half of the earlier WR-03/WR-01 concern. The closed-window half is fixed.
**Fix:** The model cannot know the true state of a window it does not track, so it must tell the caller. Make `undo` report which windows it brought back without a current state, so the engine can re-query them:
```swift
/// Windows the restored snapshot holds that no desk held before the undo. Their lifecycle state
/// comes from the snapshot and may be stale; the engine must re-report it through `apply`.
public struct UndoResult { public let restored: Bool; public let revived: [WindowRef] }
```
At minimum, document the contract on `undo` and in the Phase 2 engine plan. Add a test for sequence (1).

### WR-02: `apply(.closed)` requires an existing desk key it otherwise ignores; an unknown key throws before the history purge, so undo can still revive the closed window

**File:** `Sources/PaneModel/World.swift:120-133`
**Issue:** After the WR-01 fix, `.closed` is about the window, not the desk. The `key` argument is not used to find the window (line 124 searches every desk). It is still checked first, though: `guard desks[key] != nil else { throw .deskNotFound(key) }` (line 121). Pass a key that has no desk, and the call throws before `history.forget(window)` (line 132). The window stays in every snapshot. Reproduced in release:

```
edit k1: dock a, w     edit k1: remove w          // w is on no desk; k1's snapshot holds it
apply(.closed, w, on: k2) -> deskNotFound(k2)     // k2 was never added
undo k1  -> k1.contains(w) == true                // the closed window is back
```

This is exactly the case the fix was for: a window that no desk holds. For such a window the engine has no meaningful key to pass. `WindowEvent.windowDestroyed(WindowRef)` (`WindowSystem.swift:47`) carries no desk either. So the engine has to make a key up, for example the current display or Space, and a desk for that key may not exist yet. Then the confirmed close is lost. The test `applyToAnUnknownDeskOrWindowThrowsAndChangesNothing` only covers an unknown key for `.absent`.
**Fix:** Do not let an argument that `.closed` ignores block the purge. Either check the key only for desk-scoped states:
```swift
public mutating func apply(_ state: WindowState, for window: WindowRef, on key: DeskKey, history: inout UndoHistory) throws(LayoutError) {
    var candidate = self
    if state == .closed {
        if let holder = desks.first(where: { $0.value.contains(window) })?.key {
            try candidate.desks[holder]?.close(window)
        }
    } else {
        guard desks[key] != nil else { throw .deskNotFound(key) }
        try candidate.desks[key]?.setState(state, for: window)
    }
    try candidate.validate()
    self = candidate
    if state == .closed { history.forget(window) }
}
```
or split it out as `public mutating func close(_ window: WindowRef, history: inout UndoHistory)` with no key at all, which is the shape the iteration-2 review suggested. Add a test: close a window that no desk holds, with a key that has no desk, then undo.

## Info

### IN-01: Weight tolerance mismatch (validate 1e-9 vs. normalise 1e-12) rewrites unrelated splits on any edit (still present)

**File:** `Sources/PaneModel/LayoutTree.swift:92`, `Sources/PaneModel/TreeEdits.swift:166-167, 206-207`
**Issue:** A decoded file whose weight sums are off by 1e-12 to 1e-9 is accepted. The first edit anywhere then renormalises every such split, which breaks D-07's promise that weights the user did not touch stay bit-identical.
**Fix:** Use one tolerance constant for both checks, or canonicalise weights once at decode.

### IN-02: `resolve` rejects invalid minimums for windows not in the tree (still present)

**File:** `Sources/PaneModel/Resolve.swift:34-38`
**Issue:** One stale NaN or negative minimum for an unrelated window throws `invalidMinimum` and blocks every layout.
**Fix:** Validate only the minimums of present tree windows, inside the candidate loop at lines 59-63.

### IN-03: No-op undo levels: `edit` pushes when nothing changed, and `forget` can turn a snapshot into a copy of the current desk (still present)

**File:** `Sources/PaneModel/World.swift:104-113`, `Sources/PaneModel/Undo.swift:27-37`
**Issue:** `edit(k) { _, _ in }` still uses one undo level. Re-confirmed in this pass: dock a, dock w, then `apply(.closed, w)`. The next `undo` returns `true` and leaves the World unchanged, so the user's Cmd-Z visibly does nothing.
**Fix:** `guard desk != before else { return }` in `edit`. In `undo`, skip and pop snapshots equal to the current desk, or have `forget` drop a snapshot that becomes equal to the one after it.

### IN-04: `UndoHistory` is not bound to a World (still present)

**File:** `Sources/PaneModel/Undo.swift:7-24`, `Sources/PaneModel/World.swift:141-152`
**Issue:** Histories are keyed only by `DeskKey`, so after a reload or a replaced World, a stale history can restore a foreign snapshot.
**Fix:** Stamp each history with a World generation token, or document that callers must clear the history on reload.

### IN-05: GitHub Action not pinned to a commit SHA (still present)

**File:** `.github/workflows/ci.yml:12`
**Issue:** `actions/checkout@v5` is a mutable tag.
**Fix:** Pin it to the full commit SHA, with the version in a comment.

### IN-06: `WindowSystem.events` is a unicast `AsyncStream` (still present)

**File:** `Sources/PaneEngine/WindowSystem.swift:73`
**Issue:** If more than one consumer iterates the stream, events are split between them unpredictably.
**Fix:** Document "single consumer", or expose `func makeEventStream() -> AsyncStream<WindowEvent>`.

### IN-07: No cap on windows per tab group / per tree (still present)

**File:** `Sources/PaneModel/LayoutTree.swift:102-107`, `Sources/PaneModel/TreeEdits.swift:102-114`
**Issue:** `.tabs` only checks `>= 2`. A 16 MB hostile file, or repeated `group` calls, can put tens of thousands of windows in one node.
**Fix:** Add a `maxTabs` (or a per-tree `maxWindows`) limit, checked in `validate` and `group`.

### IN-08: Bypasses of the no-AppKit gate (still present)

**File:** `scripts/check-no-appkit.sh:14`
**Issue:** These still compile and pass the gate: `/* x */ import AppKit`, `import` and `AppKit` on separate lines, and UI modules not on the list (`AVKit`, `MapKit`, `QuickLookUI`, `SwiftUICore`). The gate guards against accidental imports, not hostile ones.
**Fix:** Do the module-trace upgrade the script already notes (`-Xswiftc -emit-loaded-module-trace`, then fail if the trace lists AppKit/SwiftUI for PaneModel/PaneEngine).

### IN-09: The `LayoutTree` doc comment is slightly inaccurate (still present)

**File:** `Sources/PaneModel/LayoutTree.swift:31-33`
**Issue:** It says "the other edits add no nodes". `insertRoot` adds a node and `group` adds a window, and both rely only on `assertValid` (DEBUG). Both are safe today, but for other reasons than the one the comment gives.
**Fix:** Change it to "the other edits cannot break an invariant (insertRoot only runs on an empty tree; group rejects duplicates) and check it in debug builds".

### IN-10: The `edit` closure can replace the ID source freely: a jump makes the saved World unloadable, and a rewind breaks NodeID uniqueness and undo (fixer's edge case (b))

**File:** `Sources/PaneModel/World.swift:104-113`, `Sources/PaneModel/World.swift:70-73`, `Tests/PaneModelTests/UndoTests.swift:152-155`
**Issue:** `edit` passes `&candidate.ids` as `inout`, and `IDSource(next:)` is public, so the closure can assign any source. `World.validate()` only checks that existing node IDs are below `ids.next`. Reproduced in release:
- Jump: `edit { ids = IDSource(next: .max / 2 + 10); dock(a) }` commits. `encoded()` succeeds, and `World.decode` then refuses the bytes with `invalidLayout("ID source … is too close to exhaustion")`. An engine that treats `invalidLayout` as "start fresh" would then overwrite the user's layout.
- Rewind: dock a and b on k1 (`next = 4`), clear k1, then `edit(k2) { ids = IDSource(); dock(w) }` commits (`next = 2`). Then `undo(k1)` throws `node n3 is not below the ID source's next value 2`, and that snapshot is consumed. This breaks `undo`'s documented promise (line 137: "`ids` is never rewound, so NodeIDs are not reused").
- A related, hostile-only path: a file at exactly `.max / 2` loads, and after one ordinary edit the saved file is refused at the next launch (confirmed). This is the accepted price of a load-only bound, and much milder than the iteration-2 soft-brick.

Ordinary use cannot reach any of these: it would take about 2^63 `make()` calls. So this is Info. Still, the test `aWorldAtTheLoadHeadroomBoundStillEditsUntilTheIDSourceRunsOut` (UndoTests.swift:152-155) uses `ids = IDSource(next: .max - 2)` inside `edit`, which treats the misuse as supported behaviour.
**Fix:** In `edit`, require the closure to draw from the source, not replace it. One edit never legitimately needs more than `2 * maxNodes` IDs:
```swift
let issued = candidate.ids.next &- ids.next
guard candidate.ids.next >= ids.next, issued <= UInt64(LayoutTree.maxNodes) * 2 else {
    throw .invariantViolated("edit replaced the ID source instead of drawing from it")
}
```
Rewrite the headroom test to build its near-exhausted World through an internal, `@testable`-only initializer that skips the load bound (`World(ids:desks:)` itself rejects such values), not by assigning `ids` inside `edit`.

---

_Reviewed: 2026-10-24T07:20:23Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
