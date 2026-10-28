---
phase: "1"
slug: "layout-model"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-24"
---

# Phase 1 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Saved layout file → `World.decode` | The persisted JSON can be edited by any local process or by the user; it is untrusted input | Layout tree, desk keys, window identities and hints (bundle IDs, pids, window IDs, title hints) |
| Engine/app → `PaneModel` edit API | Phase 2+ code calls edits with NodeIDs and OS-reported window data that may be stale | NodeIDs, WindowRefs, rects, minimum sizes |
| Repository → GitHub Actions (`ci.yml`) | CI runs repository code on a hosted runner | Source code; no secrets |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-01-01 | Tampering / DoS | `LayoutTree`/`World` decoding, `validate()` | medium | mitigate | `World.init(ids:desks:)` (the load path) runs `validate()`: node count capped at `maxNodes` 4096 before traversal, depth capped at `maxDepth` 64, iterative traversal with a visited set, typed errors (`LayoutTree.swift:43-79`, `World.swift:67-83`) | closed |
| T-01-02 | Information disclosure | `WindowRef.description`/`debugDescription`, `LayoutError` | low | mitigate | Descriptions print windowID/pid/bundleID only; `debugDescription` mirrors `description`, so error payloads never include title hints (`IDs.swift`) | closed |
| T-01-03 | Elevation of privilege | `.github/workflows/ci.yml` | low | mitigate | `permissions: contents: read`; no secrets; only first-party `actions/checkout@v5` (major-version pin; SHA pin noted as review IN finding) | closed |
| T-01-04 | Tampering | `remove`, `resizeBoundary` | low | mitigate | Stale/invalid NodeIDs, indices and non-finite deltas throw typed errors on a working copy; committed tree unchanged (`TreeEdits.swift`) | closed |
| T-01-05 | Denial of service | `normalize()` | low | mitigate | Iterative (`while collapseOrMergeOnce()` + explicit stack), no recursion; merge skipped past `maxChildren` so it always terminates (`TreeEdits.swift:163-217`) | closed |
| T-01-06 | Tampering / DoS | `resolve(_:in:mins:gap:)` | medium | mitigate | Non-finite/negative/out-of-range area, gap and minimums rejected before arithmetic (`Resolve.swift`, `isFinite` checks) | closed |
| T-01-07 | Denial of service | unfit selection loop | low | mitigate | Bounded by `maxNodes`; each iteration removes one window, so it terminates (`Resolve.swift`) | closed |
| T-01-08 | Tampering | `World.decode(from:migrations:)` | medium | mitigate | All decoding via validating initialisers; `MigrationChain`; `isValidJSONObject` check after migration (review WR-04); 17-item corrupt-file corpus in `PersistenceTests` throws instead of crashing | closed |
| T-01-09 | Denial of service | `World.decode` | low | mitigate | Inputs over `World.maxEncodedBytes` (16 MiB) rejected before parsing | closed |
| T-01-10 | Tampering / data loss | schema version gate | medium | mitigate | `newerVersion` thrown for a newer `schemaVersion`; never partially decoded or overwritten | closed |
| T-01-11 | Tampering | `World.undo` | low | mitigate | Undo validates the candidate World and refuses (`duplicateWindow`) a restore that would put a window on two desks. Updated by accepted review fix WR-02 (ad5ab19): the refused snapshot is consumed so it cannot block older levels | closed |
| T-01-12 | Tampering | `LayoutTree.applyDrop` | low | mitigate | Stale NodeID throws `nodeNotFound` through the transactional edits; nothing committed (`DropZones.swift`, `TreeEdits.swift`) | closed |
| T-01-13 | Denial of service (layout loss) | lifecycle state changes | medium | mitigate | Absent/fullscreen keep their slot; only `World.apply(.closed)` removes a slot and purges undo history (review fixes 8c5a745, 971a691, b2c7489, accepted at verification). Two-source close confirmation is a Phase 2 obligation (WIN-09) | closed |
| T-01-SC | Tampering (supply chain) | package installs | low | accept | `Package.swift` has zero dependencies; nothing to legitimacy-check | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01-01 | T-01-SC | No third-party packages in Phase 1; revisit when Sparkle and KeyboardShortcuts are added (Phase 4/9) | planner (T-01-SC disposition) | 2026-10-24 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-24 | 14 | 14 | 0 | /gsd-secure-phase 1 (orchestrator, ASVS L1 grep-depth; register authored at plan time, so no auditor spawn per short-circuit rule) |

Evidence base: Phase 1 code review (3 iterations, 14 fix commits) and verification (`01-VERIFICATION.md`, passed with developer sign-off) independently exercised T-01-01, -08, -10, -11 and -13 with reproductions and regression tests.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-24
