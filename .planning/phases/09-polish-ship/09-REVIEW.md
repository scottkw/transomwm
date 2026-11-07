---
phase: 09-polish-ship
reviewed: 2026-11-07T21:41:55Z
depth: standard
iteration: 3
files_reviewed: 8
files_reviewed_list:
  - .github/workflows/ci.yml
  - Sources/TransomEngine/OnboardingFlow.swift
  - Sources/TransomMac/Onboarding/AppMover.swift
  - Sources/TransomMac/Onboarding/OnboardingSteps.swift
  - Sources/TransomMac/Permission/SetupWindowController.swift
  - Tests/TransomEngineTests/OnboardingFlowTests.swift
  - Tests/TransomMacTests/AppMoverTests.swift
  - Tests/TransomMacTests/OnboardingControllerTests.swift
findings:
  critical: 0
  warning: 0
  info: 10
  total: 10
  necessity: 0
status: issues_found
---

# Phase 9: Code Review Report (iteration 3, final)

**Reviewed:** 2026-11-07T21:41:55Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found (info only; no blockers or warnings)

## Summary

This third review covers the iteration-2 fixes (commits `63c1fb3`, `2650c79`, `cb0525c` and `3ebd2a1`, diff base `b7d44c3`). I read each changed file in full. I also read `OnboardingModel` (whose `current = steps[0]` the `skipMove` fix depends on) and the test helpers.

What I ran:
- The CI guard under `bash --noprofile --norc -eo pipefail`, using BSD `/usr/bin/grep`, against `project.yml` padded to 1.09 MB with the matches near the top.
- `env -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG swift test --filter 'AppMoverTests|OnboardingFlowTests|OnboardingControllerTests'`. Both runs passed: 27 tests in 2 suites, and 8 tests in 1 suite.

`TRANSOM_LIVE` was not set, and nothing touched `/Applications` or the real Trash.

All four iteration-2 warnings are fixed correctly and add no new warning-level defect. The three new findings are info only: one CI portability note (IN-08) and two small gaps in tests and logging (IN-09, IN-10).

### Resolution history

**Round 1** (reviewed at `bc1e553`, fixed in `d18e1c6`..`e3b1025`)

| ID | Finding | Result |
|---|---|---|
| WR-01 | Move trashed the installed copy before the new one existed | Fixed (staging copy). A residual window after the trash became round-2 WR-01. |
| WR-02 | A Debug build could replace the release `Transom.app` | Fixed. `classify(bundleID:...)` only offers Move for `com.eightabyte.transom`. |
| WR-03 | The Move step had no way past it | Fixed (Not Now). This exposed round-2 WR-02 and WR-03. |
| WR-04 | The CI signing guard matched substrings | Fixed (whole-line `-xF`). The `pipefail` defect this introduced became round-2 WR-04. |
| WR-05 | The CI job had no timeout | Fixed. `timeout-minutes: 60`. |
| WR-06 | The tap took prereleases and allowed downgrades | Fixed. The `if:` gate plus the `releases/latest` check (residual: IN-05). |
| WR-07 | `HOMEBREW_TAP_TOKEN` was a repository secret | Fixed in the workflow and docs (`tap` environment). Residual: IN-04. Manual GitHub setup is still pending. |

**Round 2** (reviewed at `b7d44c3`, fixed in `63c1fb3`..`3ebd2a1`)

| ID | Finding | Result (verified this round) |
|---|---|---|
| WR-01 | A rename that failed after the trash deleted the only good copy | **Fixed.** `trashed` is set only after `trash` returns, so the restore on `AppMover.swift:28` runs only for a rename failure. `moveToTrash` returns `resultingItemURL`, so the restore still works if the Trash renamed the item (for example `Transom 2.app`). If the destination was recreated, the restore fails and the old copy stays in the Trash. That is acceptable, because something is then at the destination. The new test covers the I/O-failure path. |
| WR-02 | Not Now dropped onboarding progress | **Fixed.** `skipMove()` resumes the stored step over `steps − {.move}`. The stored key survives a Move launch because `OnboardingModel.init` sets `current = steps[0] == .move`, so `go(to: .move)` writes nothing. I traced four cases: a fresh first run (Welcome), stored `screenRecording` (the step after it), completed `[.move, .accessibility]` (Accessibility, the same as the old `advance()`), and stored `move` after Back (Welcome). `resume` can never return `.screenRecording`, so the `requestScreenRecording` precondition is reached only through the ready-access skip, the same as `advance()`. |
| WR-03 | "Step 1 of 1" with `[.move, .accessibility]` | **Fixed.** The guard is now `numbered.count > 1`. Every first-run list has at least 4 numbered steps, so first-run captions are unchanged. A regression test was added. |
| WR-04 | The CI guard failed falsely under `pipefail` on a large `project.yml` | **Fixed for the runner's grep.** BSD grep with the new form failed 0 of 50 runs on a 1.09 MB file. The old `-q` form failed 20 of 20. The comment's reasoning does not hold for GNU grep (IN-08). |
| IN-06 | An interrupted Move leaves a hidden staging bundle | **Open; the orchestrator accepted it.** Carried below. |

## Info

### IN-01: A pending D-25 tab group skips CloseRule's paused-session guard (carried from round 1)

**File:** `Sources/TransomEngine/WindowTracker.swift:433-439`
**Issue:** `pendingGroups.contains(identity) ? CloseDecision.recheck : CloseRule.decide(...)` returns `.recheck` even when `context.sessionActive` is false. That bypasses CloseRule's first row, "paused → noChange". The effect is limited to extra rechecks, at most 8.
**Fix:** `let decision = !context.sessionActive ? .noChange : pendingGroups.contains(identity) ? .recheck : CloseRule.decide(...)`.

### IN-02: `cgByID` and `shownSpaces` are rebuilt for the same refresh (carried from round 1)

**File:** `Sources/TransomEngine/WindowTracker.swift:74, 382, 425-426`
**Issue:** There are two sources of truth for the D-23 and D-25 inputs.
**Fix:** Pass them into `decide`, or compute them once on `ObservationContext`.

### IN-03: Report a Problem says "from the disk image" for every install outside Homebrew (carried from round 1)

**File:** `Sources/TransomMac/Shell/ReportProblem.swift:50`
**Issue:** `homebrew == false` prints "from the disk image". That includes `swift run`, Debug builds, `~/Applications` copies and copies placed by Move.
**Fix:** Print the `InstallLocation.Place` instead.

### IN-04: The `tap` environment allows `main` with no reviewer, and GitHub auto-creates a missing environment without rules (carried from round 2)

**File:** `.github/workflows/tap.yml:31-33`, `docs/releasing.md:147-149`
**Issue:** `v*` tags are admin-only, but any push to `main` could add `environment: tap` to a job that runs on push. That is safe today only because the maintainer is the only one who can push. Separately, if `tap.yml` runs before `tap` is created, GitHub creates the environment with no deployment rules.
**Fix:** In `releasing.md` step 5, say to check the deployment rules even if `tap` already exists. Then either make the reviewer required or add a `main` branch ruleset.

### IN-05: A prerelease promoted to a full release never updates the cask by itself (carried from round 2)

**File:** `.github/workflows/tap.yml:7, 28`
**Issue:** Promotion fires `release: released`, not `published`, so the cask is not updated until someone dispatches the workflow. The documented flow never creates prereleases.
**Fix:** Add `released` to `types:`. The `releases/latest` check and the no-op on an unchanged diff make a double run harmless. Alternatively, document the manual dispatch.

### IN-06: An interrupted Move leaves a hidden staging bundle in `/Applications` that is never cleaned up (carried from round 2; accepted as open)

**File:** `Sources/TransomMac/Onboarding/AppMover.swift:13-14`
**Issue:** `.Transom.app.moving-<UUID>` is hidden in Finder, and each attempt uses a new UUID. A force quit, crash or power loss during `copyItem` leaves a full-size hidden bundle behind. The fixer deferred this. Removing siblings by prefix could delete a second instance's in-flight staging copy, and switching to `.itemReplacementDirectory` changes the staging design. The orchestrator accepted it as open.
**Fix (for a later decision):** Stage in `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)`. That folder is on the same volume (so the final step is still a rename) and the system cleans it up.

### IN-07: The CI guard checks only that a line exists, so a per-config override passes (carried from round 2)

**File:** `.github/workflows/ci.yml:38-41`
**Issue:** A `CODE_SIGN_IDENTITY: "Apple Development"` added under `targets.Transom.settings.configs.Release` would change the Release build, and the base lines would still satisfy the guard. `release.sh`'s designated-requirement check is the real gate.
**Fix:** Read the resolved Release values (for example with `yq`), and check that no target or config overrides the base values.

### IN-08: The `pipefail` fix depends on BSD grep. GNU grep stops at the first match when stdout is `/dev/null`

**File:** `.github/workflows/ci.yml:37-40`
**Issue:** The new comment says "No -q: grep must read all of sed's output". That is true for macOS's `/usr/bin/grep` (BSD grep 2.6.0-FreeBSD, verified: 0 of 50 failures on a 1.09 MB file). It is false for GNU grep. Since 2.27, GNU grep detects that stdout is `/dev/null` (`dev_null_output` in `grep.c`) and sets `done_on_match`, so it exits at the first match exactly as `-q` does. `sed` then gets SIGPIPE and `pipefail` reports the round-2 false error again.

On `macos-26` the unprefixed `grep` is BSD, so nothing fails today. Two things would bring the bug back: a larger `project.yml` (over about 16 KB), and GNU grep ahead of `/usr/bin` on `PATH` (Homebrew `gnubin`, or moving the job to `ubuntu-latest`). Because the comment states the mechanism as a general rule, a later edit is likely to trust it.
**Fix:** Remove the pipe, so SIGPIPE cannot happen with any grep:
```bash
trimmed=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' xcode/project.yml)
for want in ...; do
  grep -qxF -- "$want" <<<"$trimmed" || { echo "::error::xcode/project.yml no longer has the line $want"; exit 1; }
done
```
Alternatively, keep the pipe but correct the comment to say "BSD grep (the macOS runner)".

### IN-09: `skipMove()`'s skip of Accessibility when access is ready is untested

**File:** `Sources/TransomMac/Permission/SetupWindowController.swift:122-124`, `Tests/TransomMacTests/OnboardingControllerTests.swift:35-61`
**Issue:** Both new `skipMove` tests run with `.notTrusted` or `.probing`, so the `phase == .ready` branch never runs. That branch is reachable: on a first run with stored `accessibility`, the user may have granted access in System Settings and then relaunched from the disk image. It is the only `skipMove` path that reaches `.screenRecording`, and with it the `requestScreenRecording` precondition.
**Fix:** Add a test. Store `accessibility`, use `permission(.ready)` and `place: .diskImage`, and wire the screen-recording fakes as `onScreenRecording` does. Call `decideAtLaunch()` then `skipMove()`, and expect `.screenRecording`.

### IN-10: A failed restore after a failed rename is silent

**File:** `Sources/TransomMac/Onboarding/AppMover.swift:28`
**Issue:** `try? FileManager.default.moveItem(at: trashed, to: destination)` discards the restore error. `OnboardingModel.copyForMove` logs only the rename error. If the restore also fails, the installed copy stays in the Trash, but the log does not say so or give the path. The user sees only "Couldn't move Transom…", and a bug report from `log collect` cannot explain where the old copy went.
**Fix:** `do { try FileManager.default.moveItem(at: trashed, to: destination) } catch { Logger(subsystem: "com.eightabyte.transom", category: "onboarding").error("restore failed; old copy left at \(trashed.path, privacy: .public): \(error.localizedDescription, privacy: .public)") }`.

---

_Reviewed: 2026-11-07T21:41:55Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 3 (final)_
