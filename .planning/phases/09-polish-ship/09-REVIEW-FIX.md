---
phase: 09-polish-ship
fixed_at: 2026-11-07T21:39:15Z
review_path: /Users/ken/dev/transomwm/.planning/phases/09-polish-ship/09-REVIEW.md
iteration: 2
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

<!-- The frontmatter describes iteration 2. Iteration 1 (7 in scope, 7 fixed, fixed_at 2026-11-07T22:30:00Z) follows unchanged below it. -->


# Phase 9: Code Review Fix Report

**Fixed at:** 2026-11-07T22:30:00Z
**Source review:** /Users/ken/dev/transomwm/.planning/phases/09-polish-ship/09-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (WR-01 to WR-07; IN-01 to IN-03 are out of scope for `critical_warning`)
- Fixed: 7
- Skipped: 0

## Fixed Issues

### WR-01: Move to Applications trashes the installed copy before the new copy exists

**Files modified:** `Sources/TransomMac/Onboarding/AppMover.swift`, `Tests/TransomMacTests/AppMoverTests.swift`
**Commit:** d18e1c6
**Applied fix:** `AppMover.copy` now copies the source into a hidden staging folder beside the destination (`.Transom.app.moving-<UUID>`) and strips quarantine there. Only then does it trash any existing destination and rename the staged copy into place. Any failure removes the staging folder and rethrows. A translocated source that is the `/Applications` copy is therefore read in full before it moves. I added two tests. `aFailedCopyLeavesTheInstalledCopyAlone` failed on the old code and passes now. `aFailedTrashRemovesTheStagedCopy` checks that the staging copy is cleaned up.
**Not changed:** the Replace alert wording for the translocated-from-`/Applications` case. "The copy that's there now goes to the Trash" is literally what happens: the quarantined original goes to the Trash and a clean copy of it replaces it. I added no source-equals-destination guard. Paths only match when Transom runs from `/Applications` itself, and then Move is never offered.

### WR-02: Move always targets `/Applications/Transom.app`, so a Debug build replaces the release app

**Files modified:** `Sources/TransomEngine/InstallLocation.swift`, `Sources/TransomMac/Permission/SetupWindowController.swift`, `Tests/TransomEngineTests/InstallLocationTests.swift`
**Commit:** ba39022
**Applied fix:** added the overload `InstallLocation.classify(bundleID:bundlePath:home:)`. It returns `.other` for any bundle ID other than `com.eightabyte.transom`, which is the Release `PRODUCT_BUNDLE_IDENTIFIER` in `xcode/project.yml`. `SetupWindowController`'s default `place:` uses it, so a Debug build or `swift run` never gets the Move step. New test: `onlyTheReleaseBundleIsClassified`.

### WR-03: The Move step has no way past it

**Files modified:** `Sources/TransomMac/Onboarding/OnboardingCopy.swift`, `Sources/TransomMac/Onboarding/OnboardingSteps.swift`, `Tests/TransomMacTests/OnboardingControllerTests.swift`
**Commit:** ddcaccc
**Status:** fixed: requires human verification (UI flow; the button was not checked on screen)
**Applied fix:** the Move step now has a secondary **Not Now** button (`OnboardingCopy.moveNotNowButton`) between Quit and the default **Move to Applications**. It calls `advance()`: on a first run it goes to Welcome, and after completion it goes to Accessibility. Move still comes first and is still the default, as D-08 requires. New test: `notNowOnMoveContinuesToSetup`.
**Not changed:** `.move` still shows after completion (the review's step 2). With Not Now the step can no longer block, and the D-08 comment in `OnboardingFlow` deliberately keeps it. I did not add the `volumeIsInternalKey` check (the review's step 3), so an external drive is still labelled "a disk image", but Not Now now gets past it. The 09-UI-SPEC copy table (line 227) still lists only "Quit · Move to Applications". Update the spec if you keep this button.

### WR-04: The CI "Signing identity unchanged" guard is a substring match

**Files modified:** `.github/workflows/ci.yml`
**Commit:** b6f7825
**Applied fix:** each line of `project.yml` is now trimmed and matched whole with `grep -qxF`. The `.debug` and `.cli` IDs and commented-out lines no longer satisfy the check. I tested it against the real `project.yml` (passes), a copy with the Release ID changed (fails) and a copy with `DEVELOPMENT_TEAM` commented out (fails).

### WR-05: The CI test job has no `timeout-minutes`

**Files modified:** `.github/workflows/ci.yml`
**Commit:** bd8fafa
**Applied fix:** added `timeout-minutes: 60` to `jobs.test`.

### WR-06: `tap.yml` publishes prereleases and allows cask downgrades

**Files modified:** `.github/workflows/tap.yml`, `docs/releasing.md`
**Commit:** 43c6afe
**Applied fix:** added `if: github.event_name == 'workflow_dispatch' || !github.event.release.prerelease` to the job, so a published prerelease skips cleanly. The verify step also refuses any tag that is not `releases/latest`. That endpoint never returns a prerelease, so a dispatch can't push a prerelease or an older tag either. `docs/releasing.md` explains this.
**Note:** this depends on the documented publish step `gh release edit --draft=false --latest`. If `releases/latest` lagged behind the publish event, the run would fail loudly, and you can re-run it with dispatch.

### WR-07: `HOMEBREW_TAP_TOKEN` is a repository secret

**Files modified:** `.github/workflows/tap.yml`, `docs/releasing.md`
**Commit:** 983e2bf
**Applied fix:** added `environment: tap` to the `cask` job. `docs/releasing.md` now says to create the `tap` environment, limited to `main` and tags matching `v*` (a release runs on its tag, a dispatch on `main`), with an optional reviewer. The token is set with `gh secret set ... --env tap`, and any old repository-level copy is deleted.
**Manual follow-up:** someone has to create the `tap` environment and move the secret on GitHub. Until then, `tap.yml` runs without the token, and the tap checkout will fail.

## Verification

All gates ran in the isolated worktree (`.claude/worktrees/rf-09-*`, branch `gsd-reviewfix/09-*`). The commits were then fast-forwarded onto `gsd/phase-01-layout-model`, so the same tree is now in the main checkout.
- `env -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG swift test` printed four "Test run with" lines, all passed: 271, 605, 126 and 1345 tests.
- `scripts/check-no-appkit.sh` printed `no-appkit: OK (69 files)`.
- Both workflow files parse as YAML (Ruby `YAML.load_file`).
- Toolchain: local Swift 6.4. No Swift 6.4-only syntax was added, but the 6.3 CI run has not happened yet.
- No live tests were run, and nothing was copied into `/Applications` or trashed outside temporary directories.

---

_Fixed: 2026-11-07T22:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

---

# Iteration 2

**Fixed at:** 2026-11-07T21:39:15Z
**Source review:** /Users/ken/dev/transomwm/.planning/phases/09-polish-ship/09-REVIEW.md (iteration 2)
**Iteration:** 2

**Summary:**
- Findings in scope: 4 (WR-01 to WR-04; IN-01 to IN-07 are out of scope for `critical_warning`)
- Fixed: 4
- Skipped: 0

## Fixed Issues

### WR-01: A rename that fails after a successful trash deletes the only good copy

**Files modified:** `Sources/TransomMac/Onboarding/AppMover.swift`, `Tests/TransomMacTests/AppMoverTests.swift`
**Commit:** 63c1fb3
**Applied fix:** The `trash` closure now has the type `(URL) throws -> URL?` and returns where the old copy went. `moveToTrash` passes `resultingItemURL` to get that location. If the rename throws after the trash has succeeded, the `catch` moves the trashed copy back to `destination` and then removes the staged copy. I kept the single `do`/`catch` rather than the review's three blocks, because `trashed` is only set once the trash has succeeded. New test: `aFailedRenameAfterTheTrashRestoresTheInstalledCopy`. Its fake trash deletes the staged copy, so the rename fails, and the test checks that the installed copy's marker file is back and nothing else is left behind.
**Remaining limit:** If something recreates `/Applications/Transom.app` between the trash and the rename (the review's example), the restore fails for the same reason. The old copy then stays in the Trash, where the user can still recover it. The original error is the one thrown.

### WR-02: Not Now drops onboarding progress, so a relaunch mid-setup starts again at Welcome

**Files modified:** `Sources/TransomMac/Permission/SetupWindowController.swift`, `Sources/TransomMac/Onboarding/OnboardingSteps.swift`, `Tests/TransomMacTests/OnboardingControllerTests.swift`
**Commit:** cb0525c
**Status:** fixed: requires human verification (step-flow logic; the button was not checked on screen)
**Applied fix:** Added `skipMove()`. It runs `OnboardingFlow.resume(stored:in:)` over the steps with Move removed, and skips Accessibility when access is already ready, the same rule `advance()` uses. `OnboardingView` gets a `skipMove` closure, and Not Now now calls it. `notNowOnMoveContinuesToSetup` now calls `skipMove()`. New test: `notNowOnMoveResumesTheStoredStep` stores `screenRecording`, launches from a disk image with no conflicting features, expects Move, then expects Launch at login after Not Now.

### WR-03: After completion, the lone Accessibility step shows "Step 1 of 1" when Move comes before it

**Files modified:** `Sources/TransomEngine/OnboardingFlow.swift`, `Tests/TransomEngineTests/OnboardingFlowTests.swift`
**Commit:** 2650c79
**Applied fix:** The caption guard now checks `numbered.count > 1` instead of `steps.count > 1`. Added `caption(for: .accessibility, in: [.move, .accessibility]) == nil` to `afterCompletionOnlyAccessibilityShows`.

### WR-04: The new CI guard fails with a false error under `pipefail` once `project.yml` passes about 16 KB

**Files modified:** `.github/workflows/ci.yml`
**Commit:** 3ebd2a1
**Applied fix:** Changed `grep -qxF` to `grep -xF ... >/dev/null`, so `grep` reads all of `sed`'s output. The whole-line match is unchanged, and a one-line comment explains why there is no `-q`. I checked it under `bash --noprofile --norc -eo pipefail`: the real `project.yml` passes, a 209 KB padded copy passed 50 of 50 runs, and a copy with `DEVELOPMENT_TEAM` changed exits 1 with the error. The workflow still parses as YAML.

## Not Fixed (out of scope)

### IN-06: An interrupted Move leaves a hidden staging bundle in `/Applications`

**File:** `Sources/TransomMac/Onboarding/AppMover.swift:12-13`
**Reason:** This is not a one-liner. Removing old `.Transom.app.moving-*` siblings takes a loop that deletes files in `/Applications` by name prefix, and it could remove a staging copy that a second running instance is still writing. Moving the staging copy to `.itemReplacementDirectory` changes where it is staged and adds its own cleanup. Both are left for a human decision.

## Verification

The fixes were made and checked in the isolated worktree (`.claude/worktrees/rf-09-90060-*`, branch `gsd-reviewfix/09-90060`). There I ran the targeted suites for each fix: `AppMoverTests` (8 tests), `OnboardingFlowTests` (8) and `OnboardingControllerTests` (19), all passing. The commits were then fast-forwarded onto `gsd/phase-01-layout-model` and the worktree and temporary branch were removed. The **host gate ran in the main checkout** on that tree:
- `env -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG swift test` exited 0 and printed four passing "Test run with" lines: 271, 607, 126 and 1345 tests. 607 is 605 plus the two new TransomMac tests.
- `scripts/check-no-appkit.sh` printed `no-appkit: OK (69 files)`.
- Toolchain: local Swift 6.4. The changes use no 6.4-only syntax (`NSURL?` inout for `trashItem`, a typed `filter` closure), but they have not been built with 6.3.
- No live tests were run, and `TRANSOM_LIVE` was not set. The tests used temporary directories and a fake trash only, so nothing touched `/Applications` or the real Trash. Nothing was pushed.

---

_Fixed: 2026-11-07T21:39:15Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
