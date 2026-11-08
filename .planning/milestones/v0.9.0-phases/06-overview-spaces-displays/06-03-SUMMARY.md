---
phase: 06-overview-spaces-displays
plan: 03
subsystem: persistence
status: complete
tags: [layout-json, schema-2, migration, spaces, space-uuid, arrangements]
requires:
  - phase: 06-01
    provides: "SpacesSnapshot uuidByID/idByUUID (empty macOS uuid parsed as default:<displayUUID>); 06-SPIKE.md Schema decision = schema-2"
provides:
  - "LayoutFile schema 2: arrangement (ArrangementID), layoutSets ([LayoutSet], sorted), spaces ([SavedSpace], sorted), spaceMap, maxLayoutSets = 16, validate() throws(LayoutFileError)"
  - "LayoutFileV1 (schema-1 decode shape, optional wantedFrames) with migrated() -> LayoutFile"
  - "SpaceRekey.table(for:uuids:) and SpaceRekey.rekey(_:saved:current:) -> Result(world, rekeyed, unmatched, quarantined)"
  - "ArrangementID (sorted unique display UUIDs, isUnknown, isNormalised, shortHash = first 4 hex of FNV-1a 64 over UUIDs joined by ','), LayoutSet, SavedSpace"
  - "LayoutStore: version 1 migrates, 2 decodes, >2 newerVersion (untouched, saving off); validate() failures are invalidEntry and set aside; layout sets saved without titles"
  - "ArrangeController: re-keys the saved World before .restore and logs the migration line; write() stores the Space table, the current arrangement and the loaded layoutSets"
affects: [06-04, 06-05, 06-06, 08]
tech-stack:
  added: []
  patterns:
    - "Versioned decode switch: an old schema decodes through its own frozen shape (LayoutFileV1) and converts; the current schema decodes directly"
    - "Re-key by rebuilding through World(ids:desks:) after computing every target, never mutating desks in place"
key-files:
  created:
    - Sources/TransomEngine/Arrangements.swift
    - Sources/TransomEngine/SpaceRekey.swift
    - Tests/TransomEngineTests/SpaceRekeyTests.swift
    - Tests/TransomEngineTests/ArrangementsTests.swift
    - Tests/TransomMacTests/LayoutFileV1Fixture.swift
  modified:
    - Sources/TransomEngine/LayoutFile.swift
    - Sources/TransomMac/LayoutStore.swift
    - Sources/TransomMac/ArrangeController.swift
    - Tests/TransomMacTests/LayoutStoreTests.swift
key-decisions:
  - "Schema option implemented: schema-2 (user, 2026-10-31). World.currentSchemaVersion stays 1; only the LayoutFile envelope is 2"
  - "Re-key table at restore = live uuidByID overlaid by the file's spaces table (file wins): one path covers a migrated schema-1 file (empty table, same-login assumption) and a v2 desk whose ID had no UUID when saved"
  - "Space table at write = the loaded table overlaid by live uuidByID (live wins), filtered to IDs desks use, so a dormant desk keeps the UUID it was loaded with"
  - "Schema 2 requires every key (synthesized Decodable); wantedFrames is optional only in LayoutFileV1"
  - "A second desk aiming at an already-claimed key is quarantined, like a stale ID equal to a live Space's"
  - "OVER-04 and OVER-06 are not marked complete: this plan contributes; 06-04 adds arrangement switching"
requirements-completed: []
duration: ~30min
completed: 2026-10-31
actuals:
  tokens: 10500
  tasks: 2
  commits: 2
plan_head_before: 4ccfd9ce5a974ceb37499c99f19673a226d7e203
plan_head_after: 11645b8c35b74c11fa53147a40c1351e00511902
---

# Phase 6 Plan 03: layout.json Schema 2 and Space-UUID Re-key Summary

layout.json moves to schema 2 (the user's choice), adding a Space-UUID table, the current display arrangement and the stored layout sets. Schema-1 files now decode through a frozen `LayoutFileV1` shape and migrate in memory instead of being set aside. Saved desks move to their Space's current ID before restore. A desk whose Space is gone stays dormant, or is quarantined if its old ID now belongs to a different live Space.

## What was built

- **Arrangements.swift**: `ArrangementID` sorts and de-duplicates the display UUIDs. `[]` means unknown. It has a stable 4-hex FNV-1a `shortHash` (`["A","B"]` gives `fa6c`). Also adds `LayoutSet` (arrangement, world, lastUsed) and `SavedSpace` (id, uuid).
- **LayoutFile.swift**: `schemaVersion = 2` with `arrangement`, `layoutSets` and `spaces`, all sorted in `init`, so equal contents give equal bytes. Also adds `spaceMap`, `maxLayoutSets = 16` and `validate()`. `validate()` rejects: an unsorted or duplicated arrangement, more than 16 sets, layout sets not sorted by unique arrangement, Space IDs not sorted and unique, and an empty Space uuid. `LayoutFileV1.migrated()` copies the frames exactly as stored, so the existing duplicate-frame checks still catch duplicates.
- **SpaceRekey.swift**: `table(for:uuids:)` builds the Space table. `rekey` moves matched desks, keeps unmatched desks dormant and quarantines collisions. It computes every target first and then rebuilds the World through `World(ids:desks:)`.
- **LayoutStore.swift**: the version switch is 1 → `LayoutFileV1.migrated()`, 2 → direct decode, >2 → `newerVersion` (unchanged rule). It then runs `validate()`, and a failure becomes `.invalidEntry` and the file is set aside. The 16 MiB cap still applies to the whole file before decoding.
- **ArrangeController.swift**: `rekeyed(_:)` runs before `.restore` and logs `layout.json migrated: {n} desks re-keyed by Space UUID, {u} unmatched kept dormant`, plus one error line per quarantined desk. With the Spaces lookup off, the desks keep their saved IDs and that is logged. `write()` now records `spaces`, `arrangement` (from `Displays.current()`) and the loaded `layoutSets`.
- **Fixture**: `LayoutFileV1Fixture.json` was captured from the HEAD (4ccfd9c) encoder through a scratch test that was then deleted. It has desks on Spaces 3 and 4, one docked window, one floating window, one home frame and one wanted frame.

## Verification

- Task 1 gate `swift test --filter 'LayoutStoreTests|SpaceRekeyTests'`: 10 + 3 tests passed, no ✘. The tracer gate was re-run before expanding.
- Task 2 gate `swift test --filter 'SpaceRekeyTests|ArrangementsTests|LayoutStoreTests|PersistenceTests'`: 15 + 11 + 12 tests passed, no ✘. `scripts/check-no-appkit.sh` passed (49 files).
- Full unit suites `--filter 'TransomEngineTests|TransomModelTests|TransomMacTests'`: 193 / 319 / 719 tests passed. The integration target compiled, but none of its tests ran (no live runs).
- Acceptance greps: no `version == LayoutFile.schemaVersion` left, `LayoutFileV1` ×2 in LayoutStore, `schemaVersion = 2`, `currentSchemaVersion = 1` kept, the fixture has `"schemaVersion" : 1` ×2, `maxLayoutSets = 16`, `quarantined` ×7, 8 `@Test` in SpaceRekeyTests.

## TDD Gate Compliance

- Task 1 RED: the new tests failed to compile because `SpaceRekey` did not exist yet. GREEN came in commit 9012695.
- Task 2 RED: the 3 SpaceRekey unmatched/quarantine tests failed with 4 issues. GREEN came in 11645b8. The LayoutStore schema-2 rejection tests passed at RED because `validate()` was written in Task 1 (deviation 1).
- Tests and implementation were committed together for each task (one commit per task), not as separate `test(...)` commits.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Security] Layout sets are saved without window titles**
- **Found during:** Task 1
- **Issue:** `save` stripped titles only from `world`, so worlds inside `layoutSets` would have written titles to disk (T-03-17).
- **Fix:** `save` also strips `titleHint` from every layout set's World.
- **Files modified:** Sources/TransomMac/LayoutStore.swift
- **Commit:** 9012695

**2. [Rule 2 - Validation] An empty Space uuid is rejected on load**
- **Found during:** Task 1
- **Issue:** The plan requires that an empty uuid is never stored, but nothing on the load side enforced it.
- **Fix:** `validate()` rejects a `spaces` entry with an empty uuid, and a test covers it.
- **Commit:** 9012695 (rule), 11645b8 (test)

### Other adjustments

1. `validate()` and its LayoutStore wiring were written in Task 1, not Task 2, so Task 2's LayoutStore rejection tests were green at RED. The SpaceRekey RED was real.
2. ArrangeController reads `system.spacesSnapshot` (AXWindowSystem's cached `SpacesProvider.snapshot()`, refreshed at start and on every Space or display change) instead of calling SkyLight again.
3. `LayoutFile.init` takes `spaces: [SavedSpace]` instead of a dictionary, because that is the type `SpaceRekey.table` returns.
4. Schema 2 decodes with the synthesized decoder, so `wantedFrames` is required there. The existing "file from before wanted frames" test now builds a schema-1 file, which is what such a file really is.
5. The migration log line is written on every load with the lookup on (once per launch), not only when migrating from schema 1. `rekeyed` counts desks whose key actually changed.
6. If `SpaceRekey.rekey` throws (unreachable for a decoded World), the controller logs an error and restores the saved World unchanged, so the next write cannot replace the layout with an empty one.

## Known Stubs

- `ArrangeController.write()` passes `layoutSets` through unchanged (a `shortcut:` comment). This is intentional, as the plan specifies. 06-04 hands the sets to the Arranger and adds the switching rules.

## Notes for later plans

- Quarantined desks are dropped from the restored World, so the next save no longer contains them. They belong to a deleted Space whose ID macOS reused, so nothing can show them. The error log line is the only record.
- A desk's Space keeps its original display. If a UUID matches a Space that has moved to another display, the desk follows the ID but keeps its old `displayUUID`. Display moves are 06-04's arrangement work.

## Self-Check: PASSED

- FOUND: Sources/TransomEngine/Arrangements.swift, Sources/TransomEngine/SpaceRekey.swift, Tests/TransomEngineTests/SpaceRekeyTests.swift, Tests/TransomEngineTests/ArrangementsTests.swift, Tests/TransomMacTests/LayoutFileV1Fixture.swift
- FOUND: 9012695, 11645b8 (ancestors of HEAD)
