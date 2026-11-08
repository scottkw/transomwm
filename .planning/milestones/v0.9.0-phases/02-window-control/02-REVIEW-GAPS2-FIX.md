---
phase: 02-window-control
fixed_at: 2026-10-27T23:30:00Z
review_path: .planning/phases/02-window-control/02-REVIEW-GAPS2.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 2: Code Review Fix Report (gap closure 02-18, 02-19)

**Fixed at:** 2026-10-27T23:30:00Z
**Source review:** .planning/phases/02-window-control/02-REVIEW-GAPS2.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (CR-01, WR-01, WR-02, WR-03)
- Fixed: 4
- Skipped: 0
- Info items also fixed because each fix is one line: IN-01 and IN-02. IN-03 to IN-06 were left as they are.

Each finding was handled test first. A headless test reproducing the reviewer's probe was added and seen failing, then TabGroupTracker was fixed. Every test, existing and new, passes.

**Verification location:** everything ran in the main checkout (`/Users/ken/dev/transomwm`; isolation none, no worktree). It is reproducible from the tree at `f8932bb`.

## Fixed Issues

### CR-01: The timing opener preempted the slot and timing joins

**Files modified:** `Sources/TransomEngine/TabGroupTracker.swift`, `Tests/TransomEngineTests/TabGroupTrackerTests.swift`, `Tests/TransomEngineTests/TabScenarioTests.swift`
**Commit:** 7dc33a8
**Applied fix:** I used the reviewer's alternative, a single competition, because it also handles edge cases correctly.
- The room-rule (slot) join now runs before any timing link.
- After it, the standalones that went hidden (brand-new tab only) and the groups whose shown tab went hidden compete in one `nearest(_:to:)` call. A bounds match wins, then origin and width, then the lowest ID.
- So a group's own slot beats an unrelated standalone that went hidden in the same refresh.
- The type doc sentence "told apart by the slot" now describes this order.

**Tests:**
- `aCmdTInAGroupIsNeverHandedToAStandaloneThatWentHidden`: P1, all three Space modes.
- `aCmdTInAGroupBesideAMinimizedWindowWhoseReadTimedOutStaysInTheGroup`: P6 at WindowTracker level. The rows are `[[10, 10, 1], [20, 50, 3]]` and stay that way, with nothing destroyed.

**Status:** fixed, requires human verification (logic change; confirm in the VM).

### WR-01: `wentHidden` treated "missing from `visible`" as "unlisted"

**Files modified:** `Sources/TransomEngine/TabGroupTracker.swift`, `Sources/TransomEngine/WindowTracker.swift`, both test files
**Commit:** cec2ec8
**Applied fix:**
- `TabGroupTracker.update` takes a new optional `listed: Set<UInt32>?`: the IDs AXWindows listed, whatever their read result. nil falls back to `visible`'s IDs, so existing callers and tests are unchanged.
- `wentHidden`, `canBeHiddenTab` and `lastListed` now use these IDs. A listed window whose read failed is never a hidden tab, and never a tab that just went hidden.
- **WindowTracker change (required):** one argument at the `update` call, `Set(app.windows.compactMap { $0.listedInAXWindows ? $0.windowID : nil })`. Only WindowTracker sees the reads that failed. TabGroupTracker cannot tell "listed but unread" from "unlisted" any other way. CloseRule is untouched.

**Tests:**
- `aListedWindowWhoseReadFailedIsNeverTakenAsTheOpener`: WindowTracker level. Minimized W at O's frame, and W's read times out in the Cmd-T refresh.
- `aListedWindowWhoseReadFailedIsNeverAHiddenTab`: the `canBeHiddenTab` half. It needs the new parameter, so it cannot fail before the fix. Instead I reverted only the `canBeHiddenTab` line and saw this test fail.

**Status:** fixed, requires human verification.

### WR-02: The orphan handoff still needed a bounds match

**Files modified:** `Sources/TransomEngine/TabGroupTracker.swift`, both test files
**Commit:** 47f11e4
**Applied fix:** The handoff takes a listed window when all of these hold:
- it was an untracked, offscreen entry of the pid at the last refresh;
- its AXTabs count is below the group's tab count at the last update (that count is captured before the members are recounted);
- the Spaces do not differ;
- the group's shown tab and every known member are gone.

Ties go to the group frame nearest the window's previous bounds. The exact `matches` requirement is gone, and the type doc is updated.

I kept the "every known member gone" requirement. The reviewer's list leaves it out, but when a group still has a known member in the new tab's slot, the room join already takes the tab. Keeping it also stops a listed member and a non-member from both binding to one group in a single refresh.

**Existing test changed (deliberately):**
- The `"outside the slot"` case of `aWindowWithoutFormerTabEvidenceNeverTakesTheIdentity` asserted the bounds premise that G-02-10 disproved and that this finding removes. I deleted that case.
- In its place: `aFormerTabOutsideTheSlotStillTakesTheIdentity` (positive) and `aWindowWithAsManyTabsAsTheGroupNeverTakesTheIdentity` (the new tab-count negative). The `orphanHandoff` helper gained a `listedTabs` parameter, default 1.
- All other cases of that test are unchanged and pass.

**Tests:**
- `cmdWOnAGroupFirstSeenWithStaleHiddenTabsKeepsItsIdentity`: P2, tracker level.
- `cmdWAfterARelaunchKeepsTheGroupsIdentity`: P2T, WindowTracker level. Rows `[[219, 216, 2]]`, created `[219]`, nothing destroyed.

**Status:** fixed, requires human verification.

### WR-03: A stale sweep CG list with a taller first Cmd-T left a permanent extra row

**Files modified:** `Sources/TransomEngine/TabGroupTracker.swift`, both test files
**Commit:** eae0286
**Applied fix:**
- `wentHidden` is split into `leftAX` (listed at the last update, unlisted now, in the CG list, AX-valid, no blind switch) plus "offscreen".
- When the CG list is stale (the new tab is missing from it), the timing opener accepts `leftAX` alone, as the slot filter already did.

**Tests:**
- `aTallerNewTabMissingFromAStaleCGListStillTakesItsOpener`: P3, tracker level.
- `aTallerCmdTSeenWithAStaleSweepCGListStaysOneWindow`: P3T. It is `cmdTSeenWithAStaleSweepCGListStaysOneWindow` with a 28 pt taller new tab. Rows `[[10, 40, 2]]`, created `[10]`, nothing destroyed.

**Status:** fixed, requires human verification.

### IN-01: `overrideStateForTesting` was compiled into release builds

**Files modified:** `Sources/TransomMac/Permission/PermissionController.swift`
**Commit:** 7b9e8fe
**Applied fix:** I wrapped it in `#if DEBUG`. `SetupWindowTests` still compiles and passes in the debug test build. `swift build -c release` also succeeds.

### IN-02: `makeWindow()` was not idempotent

**Files modified:** `Sources/TransomMac/Permission/SetupWindowController.swift`
**Commit:** f8932bb
**Applied fix:** `if let window { return window }` at the top of `makeWindow()`.

## Not fixed (Info, by instruction)

- **IN-03** (`waitFor` loop in SetupWindowTests), **IN-05** (`withKnownIssue` for the known-limit scenario) and **IN-06** (sort-key caching): none is a one-line fix.
- **IN-04** (require confirmed Spaces for the timing links after a Space switch): a design change, out of scope.

## Residual limits

- The orphan handoff uses each group's tab count from its last update. If a group was not rebound in that update (its shown tab's read failed), that count is its member count, which can be lower than AXTabs. A Cmd-W in the very next refresh may then miss the handoff. That falls back to the pre-fix result (destroy plus create) and loses no window.
- A group that still knows a hidden member, where that member is not in the new shown tab's slot (the group was resized after the sweep), followed by Cmd-W onto a stale non-member tab: there is still no handoff. I did not build this case.
- The orphan handoff no longer needs bounds, so it can misattribute in one new case. A window on another Space with fewer tabs than the group, that becomes listed in the same refresh as the group closes, can take the group's identity. This only happens without Space data and without the Space-switch notification. It is the same class as the documented single-Space `shortcut:` and never loses a window.

## Gates

- `swift build`: Build complete.
- `env -u TRANSOM_LIVE swift test`: all runs passed, with no ✘. Swift Testing runs: 564 tests in 54 suites (554 before), 200 in 31, 193 in 20 and 42 in 20. The XCTest harness lines report 0 XCTest tests, as at baseline.
- `scripts/check-no-appkit.sh`: `no-appkit: OK (40 files)`.
- Not touched: CloseRule.swift. WindowTracker.swift has only the one-argument change for WR-01 above.
- Headless only: TRANSOM_LIVE was never set, and no app, fixture or VM was launched. UAT 10 and 11 in the VM are still to be re-run by the orchestrator.

---

_Fixed: 2026-10-27T23:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
