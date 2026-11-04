---
phase: 08-saved-views-urls-persistence
fixed_at: 2026-11-04T02:42:45Z
review_path: .planning/phases/08-saved-views-urls-persistence/08-REVIEW.md
iteration: 1
findings_in_scope: 16
fixed: 15
skipped: 1
status: partial
---

# Phase 8: Code Review Fix Report

**Fixed at:** 2026-11-04T02:42:45Z
**Source review:** .planning/phases/08-saved-views-urls-persistence/08-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 16 (3 critical, 13 warning; the 4 info findings are out of scope)
- Fixed: 15. WR-09 is a partial fix, and 6 fixes change matching or timing, so they need human verification (listed below).
- Skipped: 1 (WR-06, deferred to the ⌘Q host check)

Every in-scope finding was checked against the source. None was wrong. The engine findings that could be tested first (CR-01, CR-02, CR-03, WR-05, WR-07, WR-10) failed their new tests before the fix.

## Verification

| Gate | Where it ran | Result |
|---|---|---|
| `swift test` | The isolated worktree, on the host, with `TRANSOM_LIVE` unset | 226, 432, 100 and 1093 tests across the four test runs, no ✘ on the last 6 full runs. See the flake note below. |
| `scripts/check-no-appkit.sh` | The isolated worktree | OK (62 files) |
| `RematchIntegrationTests` | `pane-test` VM, its own job, built from the worktree | 3 of 3 passed |
| `ViewsIntegrationTests` | `pane-test` VM, its own job, built from the worktree | 2 of 2 passed |
| `scripts/vm-cli-check.sh` (not required; run because WR-12 changed it) | `pane-test` VM, built from the worktree | 15 checks passed, nothing skipped |

The worktree is removed after this run, so these numbers come from the same commits but not from the main checkout's build folder.

After the VM runs, the guest's Application Support folder had its original files and dates, `~/transomcli` was gone, and no Transom Debug or fixture process was left. The guest was on Desktop 1. The VM started stopped and is stopped again.

**Flake:** `FreezeTestTests.itResumesByItself` gives a 50 ms timer a 1 s budget on the main actor.
- It failed on every run while WR-09's first test encoded 16 MB on the main actor. That test now uses a small `saveLimit`.
- It failed once more, in the run that overlapped the VM's shutdown. It then passed 8 of 8 runs alone and 6 of 6 full runs.
- It appears load-sensitive and I did not change it. This run did not establish whether it also fails under load without these fixes.

**Not run:** nothing was run live on this host. The real-reboot UAT is still open, and it should include a second Space.

## Needs human verification

These pass their tests, but the tests can't prove the behaviour is right on real apps: CR-02, CR-03, WR-03, WR-04, WR-05 and WR-10. The questions to check are in each finding below.

## Fixed Issues

### CR-01: Saving a view never schedules a write

**Files modified:** `Sources/TransomEngine/Arranger+Views.swift`, `Tests/TransomEngineTests/ArrangerViewsTests.swift`
**Commit:** a9ad717
**Applied fix:** `saveView` now returns `.save(.debounced)`. `savingTouchesNoWindowOrUndoHistoryAndGoingPushesBackHistory` asserted that no `.save` is sent, which contradicts 08-03's plan line "Saving a view triggers the existing debounced save". I removed that part of the assertion.

### CR-02: Tiles on Spaces that aren't showing expire

**Status:** fixed: requires human verification
**Files modified:** `Sources/TransomEngine/Arranger+Placeholders.swift`, `Sources/TransomEngine/Arranger.swift`, `README.md`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`, `Tests/TransomEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** 597c877
**Applied fix:**
- Deadlines keep running on the clock, but a placeholder only expires, or asks for a wake, while a display shows its desk.
- When its desk comes on screen, by Space notification or by inventory, it gets at least 10 s more. A later deadline is left alone.
- D-12 and D-12a numbers are unchanged for a tile on a shown desk.
- Two tests pinned the old behaviour ("waits then closes") and now state the new contract.

**Check:** a tile on Desktop 2 survives a reboot and is refilled when you go there. The real-reboot UAT covers this.

### CR-03: Matching ignores Spaces

**Status:** fixed: requires human verification
**Files modified:** `Sources/TransomEngine/HintMatcher.swift`, `Sources/TransomEngine/LayoutRestore.swift`, `Sources/TransomEngine/Arranger+Placeholders.swift`, `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/HintMatcherTests.swift`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
**Commit:** 5d2921e
**Applied fix:**
- New rule, `HintMatcher.canFill`. On the desk's own display, a window's known Spaces must hold the desk's Space; unknown or empty Spaces still pass.
- On another display, the desk must be showing, because a frame write lands on the Space that display shows.
- The sole-pair bonus now counts only the windows that fit.
- `rehome` skips a window matched from another display until its first `frameApplied` (`PlaceholderState.arriving`). If the app refuses the move, the window still floats.

**Check:** a relaunched app whose window opens on the wrong Space floats there, even with an exact title, and its tile waits.

### WR-01: layout.json stamped with the new boot while holding old-boot IDs

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Sources/TransomEngine/LayoutRestore.swift`, `Sources/TransomEngine/WindowSystem.swift`, `Sources/TransomMac/ArrangeController.swift`, `Tests/TransomEngineTests/ArrangerRestoreTests.swift`
**Commit:** a1c2e63
**Applied fix:** I took a different route from the review's. Instead of holding the old stamp, `.restore` with `bootChanged` now calls `LayoutRestore.retire`.
- Each saved window gets pid -1 and an ID from a reserved range, keeping its bundle and hints. No running window can ever carry that identity, so only `HintMatcher` can bring it back.
- From the first write on, the file names no old-boot window, so stamping this boot is correct.
- Holding the old stamp would have sent every window to hints on each Transom relaunch for as long as a hidden-Space tile waited, which after CR-02 can be days.
- This also removes `skipIdentity` and a reboot's collision close: a tile whose old identity a new window reuses now waits instead of closing.

### WR-02: The boot-session guard covers only the first re-attach

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Sources/TransomEngine/LayoutRestore.swift`, `Tests/TransomEngineTests/ArrangerRestoreTests.swift`
**Commit:** 1677b8f
**Applied fix:** `retire` also covers every stored layout set, with one identity per window across the World and the sets. No `LayoutSet.bootSession` field or schema change was needed. The "very window came back" paths can no longer fire on a reused ID, and a test covers both the event and the inventory path.

### WR-03: The sole-pair bonus alone reaches the threshold

**Status:** fixed: requires human verification
**Files modified:** `Sources/TransomEngine/HintMatcher.swift`, `Sources/TransomEngine/Arranger+Placeholders.swift`, `Tests/TransomEngineTests/HintMatcherTests.swift`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
**Commit:** cf69b38
**Applied fix:** the bonus now applies only when no title is against it: the saved window has no title, the titles agree, or the frames overlap (IoU at least 0.5). Unplaced windows at a launch stay fresh, so a title that settles later can still match. An empty title on both sides, as in schema-2 files, still matches.
**Check:** RESEARCH required "a single-window app whose title changed (sole pair matches)". That still holds when the window reopens at its old frame, but no longer when it opens elsewhere, so a Terminal or browser that does both now loses its tile. I narrowed the review's fix with the frame exception to keep the common case. Please confirm this trade.

### WR-04: The sliding 10 s deadline has no cap

**Status:** fixed: requires human verification
**Files modified:** `Sources/TransomEngine/Arranger+Placeholders.swift`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
**Commit:** cebf185
**Applied fix:** new windows can slide the deadline for at most `launchWaitLimit`, 60 s after the first slide. The 10 s, 5 min and 30 s numbers are unchanged. The slide count restarts when a hidden desk comes on screen.
**Check:** whether 60 s suits apps that open many windows slowly.

### WR-05: `prune` removes a window created before its old window's destroy event

**Status:** fixed: requires human verification
**Files modified:** `Sources/TransomEngine/Arranger+Placeholders.swift`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
**Commit:** 8b2ed7a
**Applied fix:** a window stays fresh while its bundle is quitting. The new test covers this event order.

### WR-07: Title hints go stale, and an empty title can overwrite a good one

**Files modified:** `Sources/TransomModel/World.swift`, `Sources/TransomEngine/Arranger.swift`, `Sources/TransomEngine/Arranger+Placeholders.swift`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
**Commit:** ccc9eb3
**Applied fix:**
- `refreshingTitles` ignores empty titles.
- A real title change on a held window updates `world` and schedules a debounced save.
- `holdForQuit` falls back to the World's title when the window's is empty.

### WR-08: If moving a rejected file aside fails, the next save overwrites it

**Files modified:** `Sources/TransomMac/LayoutStore.swift`, `Tests/TransomMacTests/LayoutStoreTests.swift`
**Commit:** fd6bc2b
**Applied fix:** the copy is named `layout.json.corrupt-<unix seconds>`, so none is replaced. A failed move sets `savingDisabled`. `MinimumHintsStore` has the same pattern; I left it because the finding is about `LayoutStore`.

### WR-09: Nothing caps the saved file's size (partial fix)

**Files modified:** `Sources/TransomMac/LayoutStore.swift`, `Tests/TransomMacTests/LayoutStoreTests.swift`
**Commit:** c15b1a3
**Applied fix:** `save` refuses to write over the cap and keeps the last good file. That is the part that prevents the data loss, at a few lines. `LayoutStore` gained a `saveLimit` parameter so the test doesn't encode 16 MB on the main actor.
**Not applied:** truncating titles. It would need the same truncated form in `HintMatcher` and at capture, which is out of proportion to how unlikely 16 MB of titles is. If it ever happens, saves fail with a log line and the last good layout stays.

### WR-10: Re-matched windows lose their saved wanted and home frames

**Status:** fixed: requires human verification
**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Sources/TransomEngine/Arranger+Placeholders.swift`, `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`
**Commit:** dd3dff9
**Applied fix:** both frames follow a match, at launch and in the fill path, and a tile that waits after a quit keeps them. Each map is rebuilt in one pass, so a reused ID can't chain. `homeFrames` is now `internal(set)` so the placeholder extension can write it.
**Check:** Float on a re-matched window returns it to its pre-dock frame.

### WR-11: A placeholder's stage tile uses its dead window ID

**Files modified:** `Sources/TransomMac/Zoom/StagePanel.swift`, `Tests/TransomEngineTests/ArrangerRestoreTests.swift`
**Commit:** 321a45f
**Applied fix:** this needed no separate ID space. The finding's premise is a dead ID from an earlier boot matching a live one, and after WR-01 those placeholders carry retired IDs, clear of live and synthetic IDs. The commit adds a test and corrects the comment. Within one boot it relies on a dead CG window ID not being reused, which I did not verify; the test doesn't cover that case.

### WR-12: `vm-cli-check.sh` can delete the guest's data and report success with skips

**Files modified:** `scripts/vm-cli-check.sh`
**Commit:** 91cc622
**Applied fix:**
- `support_saved` is set only after a checked `ditto`, so a failed backup exits with the folder untouched.
- A failed restore keeps the backup and prints where it is.
- Cleanup waits for the process to exit, then force-kills if needed, before it restores.
- The early exit for an already running Transom Debug removes `~/transomcli` itself. It doesn't use the trap, because that app isn't this run's to quit.
- The run starts with an empty support folder, so slot 7 is known to be empty.
- Skips are counted, and any skip exits 1.

The script ran in the VM and restored the guest's files.

### WR-13: `release.sh` can ship a stale helper

**Files modified:** `scripts/release.sh`
**Commit:** 44b4a89
**Applied fix:** the built Release `.app` is removed before building. `build-debug.sh` is unchanged, since debug builds aren't shipped. Checked with `bash -n` only: a full release build was not run.

### Also committed

`afcc5d3` (`docs(08)`) adds two `shortcut:` comments for known limits, listed under Open risks below.

## Skipped Issues

### WR-06: The quit hold depends on `.appTerminated` arriving first

**File:** `Sources/TransomEngine/Arranger+Placeholders.swift:134-136`, `Sources/TransomEngine/CloseRule.swift:56`
**Reason:** deferred to the ⌘Q host check, as the UI-SPEC and 08-04 direct. The repo can't settle the event order in real apps. The VM run printed `["appTerminated", "windowDestroyed 86", "windowDestroyed 87"]` again, but that is the fixture's `exit(0)`. The rollback isn't small: it needs a timed list of closed refs and a way to put a closed window back in its tree position, so it is not the small, order-safe fix that would justify doing it now.
**Original issue:** if an app closes its windows while its process is still alive, `CloseRule` returns `.closed` and the tile closes before `.appTerminated` arrives, so D-12a fails with no recovery.
**To check:** ⌘Q on real apps, including an Electron app and a document app with a save prompt.

## Open risks

- **Stored arrangements still close unmatched windows.** When a stored display arrangement is applied, its unmatched windows close, per 08-04's decision that this path is not a launch. After a reboot its windows are retired, so a tile on a hidden Space of a stored set closes when that arrangement is applied. Neither CR-02 nor the review covers this path; the fix would be to hold those tiles as placeholders.
- **A placeholder on a Space that no longer exists waits for good.** It is unseen and stays in layout.json, like the dormant desk it is on (`shortcut:` comment in `Arranger+Placeholders.swift`).
- **A window that never gets a title and opens elsewhere loses a lone tile.** This follows from WR-03 (`shortcut:` comment in `HintMatcher.swift`).

---

_Fixed: 2026-11-04T02:42:45Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
