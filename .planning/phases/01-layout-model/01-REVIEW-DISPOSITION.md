---
phase: 01
review: 01-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "Undo restores a window that is on no desk with whatever lifecycle state its snapshot held"
  - id: WR-02
    severity: warning
    disposition: open
    title: "`apply(.closed)` requires an existing desk key it otherwise ignores; an unknown key throws before the history purge, so undo can still revive the closed window"
  - id: IN-01
    severity: info
    disposition: open
    title: "Weight tolerance mismatch (validate 1e-9 vs. normalise 1e-12) rewrites unrelated splits on any edit (still present)"
  - id: IN-02
    severity: info
    disposition: open
    title: "`resolve` rejects invalid minimums for windows not in the tree (still present)"
  - id: IN-03
    severity: info
    disposition: open
    title: "No-op undo levels: `edit` pushes when nothing changed, and `forget` can turn a snapshot into a copy of the current desk (still present)"
  - id: IN-04
    severity: info
    disposition: open
    title: "`UndoHistory` is not bound to a World (still present)"
  - id: IN-05
    severity: info
    disposition: open
    title: "GitHub Action not pinned to a commit SHA (still present)"
  - id: IN-06
    severity: info
    disposition: open
    title: "`WindowSystem.events` is a unicast `AsyncStream` (still present)"
  - id: IN-07
    severity: info
    disposition: open
    title: "No cap on windows per tab group / per tree (still present)"
  - id: IN-08
    severity: info
    disposition: open
    title: "Bypasses of the no-AppKit gate (still present)"
  - id: IN-09
    severity: info
    disposition: open
    title: "The `LayoutTree` doc comment is slightly inaccurate (still present)"
  - id: IN-10
    severity: info
    disposition: open
    title: "The `edit` closure can replace the ID source freely: a jump makes the saved World unloadable, and a rewind breaks NodeID uniqueness and undo (fixer's edge case (b))"
  - id: CR-01
    severity: critical
    disposition: fixed
    title: "Hostile `ids.next` near `UInt64.max` passes validation, then crashes the process on the first edit"
  - id: CR-02
    severity: critical
    disposition: fixed
    title: "`insert`'s depth guard measures the new leaf, not the subtree that rule 3 pushes one level deeper"
  - id: CR-03
    severity: critical
    disposition: fixed
    title: "A lagging `IDSource` makes `insert` overwrite existing nodes; in release a window is silently dropped from the tree"
  - id: WR-03
    severity: warning
    disposition: fixed
    title: "Observed lifecycle changes go on the user's undo stack, so undo brings back closed windows and overrides OS state"
  - id: WR-04
    severity: warning
    disposition: fixed
    title: "A migration step that produces a non-JSON value crashes the process with an uncaught NSException"
  - id: WR-05
    severity: warning
    disposition: fixed
    title: "The no-AppKit gate (D-23) is easy to bypass"
  - id: WR-06
    severity: warning
    disposition: fixed
    title: "Test gap — `resolve` can ignore split weights entirely and all 125 tests still pass"
  - id: WR-07
    severity: warning
    disposition: fixed
    title: "CI never builds or tests release, so all DEBUG-only invariant enforcement is untested where it matters"
open: 12
total: 20
recorded: 2026-10-24T07:25:20.946Z
---

# Phase 01: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | open | - |
| WR-02 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |
| IN-05 | info | open | - |
| IN-06 | info | open | - |
| IN-07 | info | open | - |
| IN-08 | info | open | - |
| IN-09 | info | open | - |
| IN-10 | info | open | - |
| CR-01 | critical | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| CR-02 | critical | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| CR-03 | critical | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| WR-03 | warning | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| WR-04 | warning | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| WR-05 | warning | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| WR-06 | warning | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |
| WR-07 | warning | fixed | 01-REVIEW-FIX.iter2.md (not in the current review) |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
