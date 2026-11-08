---
phase: 08-saved-views-urls-persistence
plan: 02
subsystem: engine
tags: [persistence, layout-json, hint-matching, relaunch, boot-session, swift-testing, vm-live]

requires:
  - phase: 03-tiling-mvp
    provides: LayoutStore, LayoutRestore identity re-attach, dormant windows, T-03-18 newer-schema guard
  - phase: 06-multi-display
    provides: LayoutFile schema 2 (arrangement, layout sets, Space table)
provides:
  - layout.json schema 3 with window titles, owner-only (0600); schema 2 decodes into the same struct
  - World.refreshingTitles; Arranger.snapshot carries every tracked window's current title
  - HintMatcher (integer weights, threshold 40, greedy assignment, tie matches neither)
  - LayoutRestore.reattach(savedFrames:skipIdentity:) hint-matches unattached saved windows and rekeys them into their tiles
  - SessionRecord.bootSession, BootSession.current()/changed(saved:current:), ArrangerInput.restore(bootChanged:)
  - RematchIntegrationTests (VM live)
affects: [08-03 boot session write and bootChanged wiring in ArrangeController, 08-04 placeholders, saved views remap]

actuals:
  tokens: 16800
  tasks: 3
  commits: 5

plan_head_before: 16945b5e0b01abc4504d14b2a1123746c5282067
plan_head_after: 5c378387b0ea5ce5aae3a585c2544f8d2314276a

tech-stack:
  added: []
  patterns:
    - "Re-matching is one pure table-tested scorer (HintMatcher) called from LayoutRestore; the Arranger only supplies saved frames and logs"
    - "Matched saved refs are rekeyed through a throwaway identity (pid -1) so a reboot-reused ID can never collide mid-rekey"

key-files:
  created:
    - Sources/TransomEngine/HintMatcher.swift
    - Sources/TransomMac/BootSession.swift
    - Tests/TransomEngineTests/HintMatcherTests.swift
    - Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift
  modified:
    - Sources/TransomEngine/LayoutFile.swift
    - Sources/TransomEngine/LayoutRestore.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomMac/LayoutStore.swift
    - Sources/TransomModel/World.swift
    - Sources/TransomModel/DesktopLayer.swift
    - Tests/TransomEngineTests/ArrangerRestoreTests.swift
    - Tests/TransomEngineTests/ArrangerMultiDeskRestoreTests.swift
    - Tests/TransomMacTests/LayoutStoreTests.swift
    - Tests/TransomModelTests/PersistenceTests.swift

key-decisions:
  - "Same rank of creationOrder counts smaller orders (competition rank), so equal orders share a rank: required for the 'identical in every signal is a tie' row; still deterministic for any input order"
  - "HintMatcher returns ties as a Tie struct (score, saved, candidates) instead of [[WindowRef]], so the log can name the tile and the windows"
  - "Hint matching also runs when a known display arrangement's layout set is re-applied (same LayoutRestore path); no test changed behaviour there"
  - "A schema-2 file's in-memory schemaVersion is set to 3 at decode, so saving the loaded contents writes schema 3"
  - "BootSession is nonisolated public (pure sysctl read and a pure comparison)"

patterns-established:
  - "Saved frame for matching = home-view tile from Planner on the desk's display for docked windows, saved floating frame for floaters"
  - "Match log lines carry bundle IDs, window IDs, node IDs and scores only, never titles"

requirements-completed: [VIEW-04]

coverage:
  - id: D1
    description: "A relaunched app's windows (new pid, same titles) go back into their own tiles after a Transom relaunch"
    requirement: VIEW-04
    verification:
      - kind: integration
        ref: "scripts/vm-live-test.sh RematchIntegrationTests (Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift#aRelaunchedAppGetsItsTilesBackAfterATransomRelaunch), log .build/0802-t1-vm.log and .build/0802-final-vm.log"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerRestoreTests.swift#aRelaunchedAppsWindowsGoBackToTheirOwnTilesByTitle"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-10 scoring table: titles, normalised titles, AX identifier, frame IoU, rank, sole pair, threshold 40, ties match neither"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/HintMatcherTests.swift#theScoringTable (13 rows, both input orders) and #eachSignalScoresItsWeight"
        status: pass
    human_judgment: false
  - id: D3
    description: "layout.json schema 3 keeps titles, owner-only; schema 2 loads and saves as 3; schema 1 migrates; schema 4 disables saving"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/LayoutStoreTests.swift#titlesAreWrittenAndTheFileIsOwnerOnly, #aSchema3FileRoundTripsItsTitlesAndBootSession, #aSchema2FileLoadsWithEmptyTitlesAndSavesAsSchema3, #aSchema1FileLoadsMigratedAndIsNotSetAside, #aNewerFileIsKeptUntouchedAndNeverOverwritten"
        status: pass
    human_judgment: false
  - id: D4
    description: "Boot-session guard: a changed boot skips identity re-attach, so a reused window ID never claims a tile"
    requirement: VIEW-04
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerRestoreTests.swift#afterABootChangeAWindowReusingASavedIdentityGetsATileOnlyByItsHints; Tests/TransomMacTests/LayoutStoreTests.swift#BootSessionTests"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-11-03
status: complete
---

# Phase 8 Plan 02: Re-match tracer and persistence edges Summary

**layout.json schema 3 keeps window titles (0600), and a pure integer-weighted HintMatcher puts a relaunched app's windows back into their own tiles at launch, with a boot-session guard against reused window IDs; proven live in the Tart VM.**

## Performance

- **Duration:** about 14 min
- **Started:** 2026-11-03
- **Completed:** 2026-11-03
- **Tasks:** 3
- **Files modified:** 14 (4 created, 10 modified)

## Accomplishments

- Tracer: a fixture app relaunched under a new pid gets "Fixture 0" and "Fixture 1" back into their left and right tiles after a fresh `ArrangeController` loads the saved layout (VM run passed twice).
- `HintMatcher`: title +50 / normalised +30, AX identifier +15 / -30, frame IoU >= 0.9 +25 / >= 0.5 +10, same rank +10, sole pair +40, threshold 40. Greedy assignment where an equal-score pair sharing a saved window or candidate is a tie, and a tie matches neither. All weights are `public static let` and locked by tests.
- `LayoutRestore.reattach` runs the identity pass, then the matcher over saved windows that are neither tracked nor alive, against the tracked windows that no saved window holds. Each match rekeys the saved ref to the returning window, so the window keeps its tile. Saved windows that don't match are removed as before.
- `Arranger.snapshot` sets each window's title from the tracked window (`windows[id].window.titleHint`, the latest `WindowInfo` the tracker sent) across the world and every layout set. Untracked refs keep the title they were loaded with.
- The boot-session guard: `SessionRecord.bootSession`, `BootSession.current()` (the `kern.bootsessionuuid` sysctl), `BootSession.changed`, and `.restore(bootChanged:)`. When the boot changed, identity re-attach is skipped and one info line is logged.
- The T-03-17 title redaction helper (`World.withoutTitleHints`) and its test are deleted. D-10 supersedes it.

## Task Commits

1. **Task 1: Tracer, titles in schema 3, hint match, own tiles** - `0cf1078` (feat)
2. **Task 2: HintMatcher scoring table** - `ab4ae9c` (test, RED), `6dc6f86` (feat, GREEN)
3. **Task 3: Persistence edges and boot-session guard** - `23d11ad` (test, RED), `5c37838` (feat, GREEN)

## Files Created/Modified

- `Sources/TransomEngine/HintMatcher.swift` - scorer, weights, greedy assignment with the tie rule
- `Sources/TransomEngine/LayoutRestore.swift` - identity pass, then hint matching; returns matches and ties
- `Sources/TransomEngine/Arranger.swift` - saved frames for the matcher, match/tie/unmatched info lines, title refresh in the snapshot, `bootChanged`
- `Sources/TransomEngine/LayoutFile.swift` - schema 3, `SessionRecord.bootSession`
- `Sources/TransomMac/LayoutStore.swift` - decodes 2 and 3 and writes titles, still 0600
- `Sources/TransomMac/BootSession.swift` - the `kern.bootsessionuuid` read and the pure `changed` rule
- `Sources/TransomModel/World.swift` - `refreshingTitles`; redaction helper removed
- `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift` - VM live tracer

## Decisions Made

See `key-decisions` in the frontmatter. The main one is how "same rank" is computed. The plan said to rank by creationOrder and then identity. That makes ranks always distinct, so the required "identical in every signal" row could never tie. Counting smaller orders instead gives equal orders equal ranks. It is still independent of input order.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] LayoutStoreTests' title test inverted in Task 1, not Task 3**
- **Found during:** Task 1
- **Issue:** Task 1's verify gate runs `LayoutStoreTests`. With redaction gone, `titlesAreNeverWritten` and the schema-2 string checks fail.
- **Fix:** Inverted the title test to `titlesAreWrittenAndTheFileIsOwnerOnly` and moved the schema-literal checks from 2 to 3 (the newer-file test now uses schema 4) in Task 1. Task 3 added the new schema cases.
- **Committed in:** `0cf1078`

**2. [Rule 1 - Bug] Saved schema-2 contents would be written back as schema 2**
- **Found during:** Task 1
- **Issue:** The decoded struct kept `schemaVersion = 2`, so `store.save(store.contents!)` would write a schema-2 file that holds titles.
- **Fix:** Decode sets `contents.schemaVersion = LayoutFile.schemaVersion`.
- **Committed in:** `0cf1078`, tested by `aSchema2FileLoadsWithEmptyTitlesAndSavesAsSchema3`

**3. [Rule 1 - Bug] Reused identities could collide while rekeying**
- **Found during:** Task 1 (needed for Task 3's `skipIdentity`)
- **Issue:** With identity skipped, a returning window can carry another saved window's identity. A plain `rekey` would then close the saved window instead of moving it.
- **Fix:** Unmatched saved windows are closed first. Matches are then rekeyed through a throwaway identity (pid -1).
- **Committed in:** `0cf1078`

**4. [Rule 1 - Contract change] Existing test rewritten to the new contract**
- `ArrangerMultiDeskRestoreTests.aTabGroupShownUnderAnotherTabAtRelaunchIsNotKeptTwice`: the saved group leader (now a hidden tab) used to be removed, and the group floated. Under the sole-pair rule the group now gets its docked tile back under its new leader. The test still checks the CR-01 point: the group is docked once and never also floating. The doc comment of `aSavedWindowWhoseAppRelaunchedIsRemoved` was updated too. That window is on a hidden Space and untracked, so nothing re-matches it.

**5. [Discretion] `ties` is `[HintMatcher.Tie]`, not `[[WindowRef]]`** - the log needs the score and which refs are saved and which are candidates.

---

**Total deviations:** 5 (2 bugs, 1 blocking test order, 1 contract test rewrite, 1 API shape). No scope creep.

## Issues Encountered

None. Both VM runs passed on the first try.

## Known Stubs

None.

## User Setup Required

None.

## Next Phase Readiness

- 08-03 Task 1: write `bootSession: BootSession.current()` in `ArrangeController.write` and pass `bootChanged: BootSession.changed(saved:current:)` into `.restore`. The engine path is already tested.
- 08-04: unmatched docked saved windows are still removed in `LayoutRestore.reattach`. That loop is where placeholders go.
- VM logs: `.build/0802-t1-vm.log` (Task 1 gate) and `.build/0802-final-vm.log` (re-run on the final code).

## Self-Check: PASSED
