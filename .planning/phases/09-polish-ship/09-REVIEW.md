---
phase: 09-polish-ship
reviewed: 2026-11-07T21:33:45Z
depth: standard
iteration: 2
files_reviewed: 11
files_reviewed_list:
  - .github/workflows/ci.yml
  - .github/workflows/tap.yml
  - Sources/TransomEngine/InstallLocation.swift
  - Sources/TransomMac/Onboarding/AppMover.swift
  - Sources/TransomMac/Onboarding/OnboardingCopy.swift
  - Sources/TransomMac/Onboarding/OnboardingSteps.swift
  - Sources/TransomMac/Permission/SetupWindowController.swift
  - Tests/TransomEngineTests/InstallLocationTests.swift
  - Tests/TransomMacTests/AppMoverTests.swift
  - Tests/TransomMacTests/OnboardingControllerTests.swift
  - docs/releasing.md
findings:
  critical: 0
  warning: 4
  info: 7
  total: 11
  necessity: 0
status: issues_found
---

# Phase 9: Code Review Report (iteration 2)

**Reviewed:** 2026-11-07T21:33:45Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

This is the second review. It covers the fixes for WR-01 to WR-07 (commits `b6f7825`..`e3b1025`, diff base `bc1e553`). I read each changed file in full, along with `OnboardingFlow.swift` and `xcode/project.yml`, which the fixed code depends on. I ran the CI signing guard under `bash -eo pipefail` against the real `project.yml` and against padded copies. I did not run the test suite or any live tests, and I did not set `TRANSOM_LIVE`.

### Round-1 findings and how they were resolved

| ID | Round-1 finding | Result |
|---|---|---|
| WR-01 | Move trashed the installed copy before the new one existed | **Mostly fixed.** The copy is staged first. One window is still open: the rename fails after the trash has succeeded. See WR-01 below. |
| WR-02 | A Debug build could replace the release `Transom.app` | **Fixed.** `classify(bundleID:...)` returns `.other` for any bundle except `com.eightabyte.transom`, so Move is never offered. |
| WR-03 | The Move step had no way past it | **Fixed.** Not Now calls `advance()`. The new path exposes two smaller defects (WR-02, WR-03 below). |
| WR-04 | The CI signing guard matched substrings | **Fixed** for the substring case. The new pipeline can fail falsely under `pipefail` once the file grows (WR-04 below). |
| WR-05 | The CI job had no timeout | **Fixed.** `timeout-minutes: 60`. |
| WR-06 | The tap took prereleases and allowed downgrades | **Fixed.** The `if:` gate plus the `releases/latest` equality check. A prerelease that is later promoted is not picked up automatically (IN-05). |
| WR-07 | `HOMEBREW_TAP_TOKEN` was a repository secret | **Fixed in the workflow and docs.** The `tap` environment is limited to `main` and `v*`. Creating `v*` tags is admin-only through the existing tag ruleset (releasing.md step 4). There is a residual note about `main` with no reviewer (IN-04). The manual setup on GitHub is still pending. |
| IN-01..IN-03 | Info | Carried unchanged below. |

**Verified sound:**
- The AppMover staging copy, the quarantine strip on the staged tree (`XATTR_NOFOLLOW`, so framework symlinks are not followed), and the rename within one folder.
- The translocated-from-`/Applications` case: the source is read in full before the trash moves it.
- The relaunch argv quoting.
- The tap `if:` expression, which short-circuits for dispatch.
- `TAG` reaches the script only through `env`, never as a `${{ }}` splice.
- For a `release` event the run's ref is `refs/tags/<tag>`, which the `v*` deployment rule allows.

## Warnings

### WR-01: A rename that fails after a successful trash deletes the only good copy

**File:** `Sources/TransomMac/Onboarding/AppMover.swift:14-27`
**Issue:** One `do`/`catch` covers every step. If `trash(destination)` succeeds and the `moveItem(at: staging, to: destination)` on line 23 then throws, the `catch` on line 25 deletes `staging`. That leaves no Transom in `/Applications`: the old copy is in the Trash and the new one has been deleted. This is the round-1 WR-01 end state again, only through a narrower window.

The rename can fail if something recreates `/Applications/Transom.app` between the trash and the rename. Examples are a second Transom instance, a `brew install --cask` running at the same moment, or MDM. It can also fail with an I/O error. The user then sees "Couldn't move Transom. Drag it to the Applications folder yourself". The installed copy can be recovered from the Trash, so this is not permanent data loss, but the cleanup code is what creates the bad state. No test covers a rename failure after the trash.
**Fix:** Delete the staged copy only while the destination is still untouched. Once the trash has succeeded, put the old copy back:
```swift
static func copy(from source: URL, to destination: URL, trash: (URL) throws -> URL?) throws {
    let staging = ...
    do {
        try FileManager.default.copyItem(at: source, to: staging)
        // strip quarantine as today
    } catch { try? FileManager.default.removeItem(at: staging); throw error }
    var trashed: URL?
    if FileManager.default.fileExists(atPath: destination.path) {
        do { trashed = try trash(destination) } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }
    do {
        try FileManager.default.moveItem(at: staging, to: destination)
    } catch {
        if let trashed { try? FileManager.default.moveItem(at: trashed, to: destination) }  // restore the installed copy
        try? FileManager.default.removeItem(at: staging)
        throw error
    }
}
// moveToTrash: var out: NSURL?; try FileManager.default.trashItem(at: url, resultingItemURL: &out); return out as URL?
```
Add a test in which the trash closure succeeds, then places a file at `destination` so that the rename fails. The test should expect the original to be restored.

### WR-02: Not Now drops onboarding progress, so a relaunch mid-setup starts again at Welcome

**File:** `Sources/TransomMac/Onboarding/OnboardingSteps.swift:84`, `Sources/TransomMac/Permission/SetupWindowController.swift:61,107-115`, `Sources/TransomEngine/OnboardingFlow.swift:28-29`
**Issue:**
- **What happens.** `resume` always returns `.move` when Move is in the steps. That is intended. But Not Now calls plain `advance()`, which goes to `next(after: .move)`, and that is always `.welcome`. The stored `onboarding.step` is ignored, even though it is still intact: `go(to: .move)` at launch is a no-op because `current` is already `.move`, so nothing overwrites it.
- **Common case.** A user on a disk image or Downloads copy picks Not Now, reaches Screen Recording and grants it. macOS then asks to "Quit & Reopen". On relaunch they land on Move, click Not Now, and start again at Welcome. `resume` exists specifically to skip past Screen Recording after this relaunch.
- **Why it is new.** This path was unreachable before the WR-03 fix. A copy that needed Move could never get past Move.

**Fix:** Give Not Now its own action, which resumes the stored step among the steps after Move:
```swift
func skipMove() {
    let rest = Array(model.steps.drop { $0 == .move })
    go(to: OnboardingFlow.resume(stored: defaults.string(forKey: Self.stepKey), in: rest))
}
```
Wire it with `Button(OnboardingCopy.moveNotNowButton, action: skipMove)`. Keep the "skip Accessibility when ready" rule from `advance()` if `rest[0] == .accessibility`. Add a test: stored `screenRecording`, first run, `place: .diskImage`, skip Move, then expect `.features` or `.launchAtLogin`.

### WR-03: After completion, the lone Accessibility step shows "Step 1 of 1" when Move comes before it

**File:** `Sources/TransomEngine/OnboardingFlow.swift:20-24`
**Issue:**
- **The contract.** The doc comment says the lone Accessibility step shown after completion has no caption. The guard checks `steps.count > 1`, not the numbered count.
- **The bug.** With `needsMove`, the completed steps are `[.move, .accessibility]`. `steps.count` is 2, `numbered` is `[.accessibility]`, and `caption` returns `(1, 1)`. `SetupView` then renders "Step 1 of 1" (`OnboardingSteps.swift:170`).
- **Why it shows now.** It became visible with WR-03's Not Now: Settings ▸ General ▸ Set Up / Fix, or the menu's Grant / Fix, then Not Now. Before that fix, the Accessibility step could not be reached in that list. `OnboardingFlowTests` checks `caption(for: .accessibility, in: [.accessibility]) == nil` but not the `[.move, .accessibility]` case.

**Fix:** `guard numbered.count > 1, let index = numbered.firstIndex(of: step) else { return nil }`. Add `#expect(OnboardingFlow.caption(for: .accessibility, in: [.move, .accessibility]) == nil)`.

### WR-04: The new CI guard fails with a false error under `pipefail` once `project.yml` passes about 16 KB

**File:** `.github/workflows/ci.yml:37-40`
**Issue:**
- **Why it fails.** `defaults.run.shell: bash` makes GitHub run steps with `bash --noprofile --norc -eo pipefail`. In `sed ... | grep -qxF`, `grep -q` exits at the first match. If `sed` still has output to write, it then gets SIGPIPE, exits 141, and `pipefail` turns the pipeline into a failure. The `||` branch then prints "xcode/project.yml no longer has the line …", even though the line is there.
- **Measured locally** (BSD sed, 100 runs each, `bash -eo pipefail`):

  | `project.yml` size | Result |
  |---|---|
  | 3.5 KB (today) | 0 failures |
  | 16.4 KB | 0 failures |
  | 29 KB | 100 of 100 failed |
  | 161 KB | 300 of 300 failed |

- **Impact.** The file is 3,534 bytes today, so the defect is latent. It fails closed, but the message points the maintainer at the wrong cause.

**Fix:** Let `grep` read all of its input. Drop `-q` and discard the output; I checked this passes 100 of 100 times on the 161 KB file and still exits 1 for a missing line:
```bash
sed 's/^[[:space:]]*//; s/[[:space:]]*$//' xcode/project.yml | grep -xF -- "$want" >/dev/null \
  || { echo "::error::xcode/project.yml no longer has the line $want"; exit 1; }
```
Alternatively, use `grep -qxF -- "$want" <(sed ...)`. `pipefail` does not cover a process substitution.

## Info

### IN-01: A pending D-25 tab group skips CloseRule's paused-session guard (carried from round 1)

**File:** `Sources/TransomEngine/WindowTracker.swift:436-441`
**Issue:** `pendingGroups.contains(identity) ? CloseDecision.recheck : CloseRule.decide(...)` returns `.recheck` even when `context.sessionActive` is false. That bypasses CloseRule's first row, "paused → noChange". The effect is limited to extra rechecks, at most 8.
**Fix:** `let decision = !context.sessionActive ? .noChange : pendingGroups.contains(identity) ? .recheck : CloseRule.decide(...)`.

### IN-02: `cgByID` and `shownSpaces` are rebuilt for the same refresh (carried from round 1)

**File:** `Sources/TransomEngine/WindowTracker.swift:381, 429-431`
**Issue:** This creates two sources of truth for the D-23 and D-25 inputs.
**Fix:** Pass them into `decide`, or compute them once on `ObservationContext`.

### IN-03: Report a Problem says "installed from the disk image" for every install outside Homebrew (carried from round 1)

**File:** `Sources/TransomMac/Shell/ReportProblem.swift:50`
**Issue:** `homebrew == false` prints "from the disk image". That includes `swift run`, Debug builds, copies in `~/Applications`, and copies moved by Move.
**Fix:** Print the `InstallLocation.Place` instead.

### IN-04: The `tap` environment allows `main` with no reviewer, and GitHub auto-creates a missing environment without rules

**File:** `.github/workflows/tap.yml:31-33`, `docs/releasing.md:147-149`
**Issue:**
- **No reviewer on `main`.** `v*` tags are admin-only through the ruleset, but `main` has no branch rule in these docs. Any push to `main` can add `environment: tap` to a job in `ci.yml`, which runs on every push, and read the token. Today only the maintainer can push, so this is a note, not a finding.
- **Auto-created environment.** If `tap.yml` runs before the maintainer creates `tap`, GitHub creates the environment itself with no deployment rules. A later `gh secret set --env tap` would then store the token in an unprotected environment.

**Fix:** In `releasing.md` step 5, say "check the deployment rules even if `tap` already exists". Either make the reviewer required, or add a `main` branch ruleset (restrict pushes, require PRs).

### IN-05: A prerelease promoted to a full release never updates the cask by itself

**File:** `.github/workflows/tap.yml:6-7, 28`
**Issue:** The job now skips prereleases. Promoting a prerelease fires `release: released` (and `edited`), not `published`, so the cask stays where it was until someone dispatches the workflow by hand. The documented flow never creates prereleases, so nothing breaks today.
**Fix:** Add `released` to `types:`. The `releases/latest` check and the unchanged-diff no-op already make a double run harmless. Alternatively, note the manual dispatch in `releasing.md`.

### IN-06: An interrupted Move leaves a hidden staging bundle in `/Applications` that is never cleaned up

**File:** `Sources/TransomMac/Onboarding/AppMover.swift:12-13`
**Issue:** `.Transom.app.moving-<UUID>` is hidden in Finder, and each attempt uses a new UUID. A force quit, crash or power loss during `copyItem` leaves a full-size hidden bundle that nothing removes.
**Fix:** Before copying, remove any `.\(name).moving-*` siblings. Alternatively, stage in `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)`, which is on the same volume and in a folder the system cleans up.

### IN-07: The CI guard checks only that a line exists, so a per-config override passes

**File:** `.github/workflows/ci.yml:37-40`
**Issue:** `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` are base settings (`project.yml:18-19`). If someone added `CODE_SIGN_IDENTITY: "Apple Development"` under `targets.Transom.settings.configs.Release`, the Release build would change and the base lines would still satisfy the guard. `release.sh`'s designated-requirement check is the real gate, so this is defence in depth only.
**Fix:** Read the resolved Release values, for example `yq '.targets.Transom.settings.configs.Release.PRODUCT_BUNDLE_IDENTIFIER'`, and also check that no target or config overrides the base values.

---

_Reviewed: 2026-11-07T21:33:45Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
