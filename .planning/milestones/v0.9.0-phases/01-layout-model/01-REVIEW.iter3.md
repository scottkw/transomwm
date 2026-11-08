---
phase: 01-layout-model
reviewed: 2026-10-24T07:09:21Z
depth: standard
iteration: 2
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
  info: 9
  total: 11
status: issues_found
---

# Phase 1: Code Review Report (iteration 2)

**Reviewed:** 2026-10-24T07:09:21Z
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

This pass re-reviewed the phase after the 10 fix commits `dc69ec2..9f6c2e5`. It checked whether each earlier Critical and Warning fix is correct and complete, and looked for regressions the fixes introduced. The claims below were tested with a scratch probe package that depends on this repo by path, built in release so `assertValid()` is compiled out. The package is in the session scratchpad and is not part of the repo.

**Prior-fix verification**

| Prior | Verdict | Evidence |
|-------|---------|----------|
| CR-01 | Fixed (crash gone), but the headroom check causes a new problem, see WR-02 | `make()` throws, and `ids.next = .max` is rejected at load |
| CR-02 | Fixed | `insert` runs `try next.validate()` on the whole candidate in every build (`TreeEdits.swift:60-63`) |
| CR-03 | Fixed | Both `make()` call sites check for a collision before writing (`TreeEdits.swift:33, 50`) |
| WR-01 | Fixed, no regression found | `validate`'s exception (`LayoutTree.swift:96`) is the exact complement of `normalize`'s merge guard (`TreeEdits.swift:189`), so a normalised tree always validates. Release fuzz: 200,000 random insert/close/group/resize ops starting from nested-overflow trees, with 4,331 nested same-axis states seen. Zero invalid trees, zero throwing ops that left a trace, `resolve` never threw, and every JSON round-trip matched. |
| WR-02 | Fixed | The snapshot is popped before it is validated. The rewritten test checks that the older entries are reachable. |
| WR-03 | **Incomplete**, see WR-01 | `apply` stays off the stack and carries states over, but undo can still bring back a closed window |
| WR-04 | Fixed | The `isValidJSONObject` guard runs before `data(withJSONObject:)` |
| WR-05 | Fixed for the listed cases. Some bypasses remain, see IN-08 | |
| WR-06 | Fixed | The exact case and P9 are correct: P9 skips any split where some child would be pinned, and allows the floor-rounding tolerance |
| WR-07 | Fixed | CI has both release steps |

The 7 earlier Info items (IN-01..IN-07) were out of fix scope. All 7 are still present and listed again below.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Undo can still bring back a closed window: `apply(.closed)` only purges history when some desk currently holds the window

**File:** `Sources/PaneModel/World.swift:108-116`, `Sources/PaneModel/Undo.swift:27-37`, `Sources/PaneModel/World.swift:124-135`
**Issue:** `apply` runs `desk.setState(.closed, …)` first. If the given desk does not hold the window, that throws `windowNotFound`, so `history.forget(window)` (line 115) never runs. `forget` is `internal`, so the engine has no other way to purge a closed window from history. A window is on no desk, while older snapshots still hold it, whenever a user edit took it off a desk without docking it elsewhere. The most natural case is Cmd-Z on the destination desk after a cross-desk move. Reproduced in release:

```
edit A: dock x, W      edit A: remove W      edit B: insertRoot W     // move W from A to B
undo B                                                                // W is now on no desk
apply(.closed, W, on: A) -> windowNotFound    apply(.closed, W, on: B) -> windowNotFound
undo A  -> A.tree.windows == [x, W], state(W) == .present             // closed window is back
```

This is the harm the earlier WR-03 described: `resolve` reserves a tile for a dead window, and Phase 2 will send `setFrame` to it. The commit title ("undo never revives closed windows") and the doc on `apply` (line 106) claim more than the code does. The same hole has a second entry point. `Desk.setState` and `LayoutTree.setState` are still public and can be called inside `edit`. A `.closed` reported that way is pushed onto the stack and never forgotten, so `undo` restores it. That was reproduced too: `edit { setState(.closed, w2) }; undo` gives back `[w1, w2]`. The old scenario test used exactly this pattern. A related gap: the undo carry-over (lines 127-129) only reads states from the current desk. A window that is on no desk comes back with whatever stale state the snapshot had.
**Fix:** Make the purge depend on the window, not on the desk. Then close the bypass:
```swift
/// The OS confirmed `window` is gone: remove it from whichever desk holds it (if any) and from all history.
public mutating func close(_ window: WindowRef, history: inout UndoHistory) throws(LayoutError) {
    var candidate = self
    if let key = desks.first(where: { $0.value.contains(window) })?.key {
        try candidate.desks[key]!.setState(.closed, for: window)
        try candidate.validate()
    }
    self = candidate
    history.forget(window)          // always, even when no desk holds it now
}
```
Route `apply(.closed, …)` through this. Alternatively, have `apply` call `forget` before the `windowNotFound` check when `state == .closed`. Make `World.edit` reject a `change` that lowers any window's lifecycle state, or document loudly that lifecycle must not go through `edit`. Add a test for the move-then-undo-then-close sequence above.

### WR-02: A World whose `ids.next` is at the new headroom bound loads, then rejects every edit

**File:** `Sources/PaneModel/World.swift:66-69` (used by `edit` at line 99)
**Issue:** The CR-01 fix put the load-time sanity bound (`ids.next <= UInt64.max - 2*maxNodes`) in `World.validate()`. `edit` runs that same check on every candidate. A file whose `ids.next` is anywhere in the last few thousand values below the bound passes `World.decode`. After that, the first edit that consumes enough IDs to cross the bound throws, and so does every edit after it. Reproduced: `next = UInt64.max - 8192` decodes successfully, and then the very first `insertRoot` throws `invariantViolated("ID source 18446744073709543424 is too close to exhaustion")`. The process no longer crashes, but a hostile or corrupt file now leaves the app unable to edit layouts. The user can only recover by deleting the file, and the error tells them nothing useful. The earlier review suggested this bound as a gate that rejects the file at load, not as a runtime limit. Using the same number for both turns a rejection into a soft-brick.
**Fix:** Keep the two checks apart. At load (in `init(from:)` / `World(ids:desks:)`), require generous headroom, for example `ids.next <= UInt64.max / 2`, which no real session can approach. During edits, rely only on `make()` throwing at `UInt64.max`. For example, add a `validate(requiringHeadroom: Bool)` parameter that only the load paths set. Add a corpus case at the bound to show such a file is rejected, plus a test that an edit at the bound still succeeds.

## Info

### IN-01: Weight tolerance mismatch (validate 1e-9 vs. normalise 1e-12) rewrites unrelated splits on any edit (still present)

**File:** `Sources/PaneModel/LayoutTree.swift:92`, `Sources/PaneModel/TreeEdits.swift:164-167, 205-207`
**Issue:** A decoded file whose weight sums are off by 1e-12 to 1e-9 is accepted. The first edit anywhere then renormalises every such split, which breaks D-07's promise that weights the user did not touch stay bit-identical.
**Fix:** Use one tolerance constant for both checks, or canonicalise weights once at decode.

### IN-02: `resolve` rejects invalid minimums for windows not in the tree (still present)

**File:** `Sources/PaneModel/Resolve.swift:34-38`
**Issue:** One stale NaN or negative minimum for an unrelated window throws `invalidMinimum` and blocks every layout.
**Fix:** Validate only the minimums of present tree windows, inside the candidate loop at lines 59-63.

### IN-03: No-op undo levels: `edit` pushes when nothing changed, and `forget` can turn a snapshot into a copy of the current desk (still present, with a new path)

**File:** `Sources/PaneModel/World.swift:93-102`, `Sources/PaneModel/Undo.swift:27-37`
**Issue:** `edit(k) { _, _ in }` still uses one undo level. New with WR-03's fix: dock w1, dock w2, then `apply(.closed, w2)`. `forget` leaves the newest snapshot (w1 only) equal to the current desk, so the next Cmd-Z visibly does nothing (reproduced: the undo returns `true` and `world == before`).
**Fix:** `guard desk != before else { return }` in `edit`. In `undo`, skip and pop snapshots equal to the current desk, or have `forget` drop a snapshot that becomes equal to the one after it.

### IN-04: `UndoHistory` is not bound to a World (still present)

**File:** `Sources/PaneModel/Undo.swift:7-25`, `Sources/PaneModel/World.swift:124-135`
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

### IN-08: Bypasses of the no-AppKit gate that remain after the WR-05 fix

**File:** `scripts/check-no-appkit.sh:14`
**Issue:** These lines compile (checked with `swiftc -typecheck`) and pass the gate (exit 0):
- `/* x */ import AppKit` (a block comment before the import)
- `import` on one line and `AppKit` on the next
- umbrella or UI modules not on the list: `AVKit`, `MapKit`, `QuickLookUI`, `SwiftUICore`

The script's `shortcut:` comment already admits that a text match cannot see transitive imports. This gate guards against accidental imports, not hostile ones, so this is Info.
**Fix:** Do the module-trace upgrade the script already notes (`-Xswiftc -emit-loaded-module-trace`, then fail if the trace lists AppKit/SwiftUI for PaneModel/PaneEngine). It closes all of these at once.

### IN-09: The `LayoutTree` doc comment is slightly inaccurate after CR-03

**File:** `Sources/PaneModel/LayoutTree.swift:31-33`
**Issue:** It says "the other edits add no nodes". `insertRoot` adds a node, and `group` adds a window, and both rely only on `assertValid` (DEBUG). Both happen to be safe: `insertRoot` only runs on an empty tree, and `group` rejects duplicates. Still, the stated reason is wrong, and a future edit could rely on it.
**Fix:** Change it to "the other edits cannot break an invariant (insertRoot only runs on an empty tree; group rejects duplicates) and check it in debug builds", or call `validate()` unconditionally in `group` as well.

---

_Reviewed: 2026-10-24T07:09:21Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
