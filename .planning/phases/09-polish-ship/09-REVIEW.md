---
phase: 09-polish-ship
reviewed: 2026-11-07T21:22:11Z
depth: standard
files_reviewed: 124
files_reviewed_list:
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - .github/workflows/tap.yml
  - Sources/TransomEngine/Arranger+Views.swift
  - Sources/TransomEngine/Arranger.swift
  - Sources/TransomEngine/CLICommandLine.swift
  - Sources/TransomEngine/CLICopy.swift
  - Sources/TransomEngine/CloseRule.swift
  - Sources/TransomEngine/Command.swift
  - Sources/TransomEngine/InstallLocation.swift
  - Sources/TransomEngine/OnboardingFlow.swift
  - Sources/TransomEngine/SettingsPane.swift
  - Sources/TransomEngine/TransomURL.swift
  - Sources/TransomEngine/UpdateRelease.swift
  - Sources/TransomEngine/UpdateState.swift
  - Sources/TransomEngine/WindowTracker.swift
  - Sources/TransomFixtureApp/main.swift
  - Sources/TransomMac/ArrangeController.swift
  - Sources/TransomMac/ConflictController.swift
  - Sources/TransomMac/DragToDockPreference.swift
  - Sources/TransomMac/GapPreference.swift
  - Sources/TransomMac/GesturePreference.swift
  - Sources/TransomMac/HighlightColor.swift
  - Sources/TransomMac/Input/GestureTapRules.swift
  - Sources/TransomMac/LoginItem.swift
  - Sources/TransomMac/MinimumHintsStore.swift
  - Sources/TransomMac/MissionControlTakeover.swift
  - Sources/TransomMac/NewWindowsPreference.swift
  - Sources/TransomMac/Onboarding/AppMover.swift
  - Sources/TransomMac/Onboarding/OnboardingCopy.swift
  - Sources/TransomMac/Onboarding/OnboardingSteps.swift
  - Sources/TransomMac/Overlay/GapHandlePanels.swift
  - Sources/TransomMac/Overlay/PreviewPanel.swift
  - Sources/TransomMac/Overview/OverviewController.swift
  - Sources/TransomMac/Permission/SetupView.swift
  - Sources/TransomMac/Permission/SetupWindowController.swift
  - Sources/TransomMac/Settings/ArrangingTab.swift
  - Sources/TransomMac/Settings/ExclusionsTab.swift
  - Sources/TransomMac/Settings/GeneralTab.swift
  - Sources/TransomMac/Settings/MenuBarTab.swift
  - Sources/TransomMac/Settings/SettingsCopy.swift
  - Sources/TransomMac/Settings/SettingsWindowController.swift
  - Sources/TransomMac/Settings/ShortcutsTab.swift
  - Sources/TransomMac/Settings/UpdatesTab.swift
  - Sources/TransomMac/Settings/ZoomGesturesTab.swift
  - Sources/TransomMac/Shell/CommandMenu.swift
  - Sources/TransomMac/Shell/FreezeTest.swift
  - Sources/TransomMac/Shell/MenuCopy.swift
  - Sources/TransomMac/Shell/OverviewCopy.swift
  - Sources/TransomMac/Shell/ReportProblem.swift
  - Sources/TransomMac/Shell/StatusItemController.swift
  - Sources/TransomMac/Shell/TabCopy.swift
  - Sources/TransomMac/Shell/ViewControlItems.swift
  - Sources/TransomMac/Shell/ViewCopy.swift
  - Sources/TransomMac/Shell/ZoomCopy.swift
  - Sources/TransomMac/TransomMacApp.swift
  - Sources/TransomMac/Updates/DMGDownloader.swift
  - Sources/TransomMac/Updates/DMGVerifier.swift
  - Sources/TransomMac/Updates/GitHubReleaseClient.swift
  - Sources/TransomMac/Updates/UpdateController.swift
  - Sources/TransomMac/Updates/UpdateCopy.swift
  - Sources/TransomMac/Zoom/CollapsedPanels.swift
  - Sources/TransomMac/Zoom/GestureController.swift
  - Sources/TransomMac/Zoom/StagePanel.swift
  - Sources/TransomTestSupport/FakeWindowSystem.swift
  - Sources/transom-gesture-spike/main.swift
  - Sources/transom-spaces-spike/main.swift
  - Tests/TransomEngineTests/ArrangerViewsTests.swift
  - Tests/TransomEngineTests/CLICommandLineTests.swift
  - Tests/TransomEngineTests/CLICopyTests.swift
  - Tests/TransomEngineTests/CloseRuleTests.swift
  - Tests/TransomEngineTests/CloseScenarioTests.swift
  - Tests/TransomEngineTests/InstallLocationTests.swift
  - Tests/TransomEngineTests/OnboardingFlowTests.swift
  - Tests/TransomEngineTests/TransomURLTests.swift
  - Tests/TransomEngineTests/UpdateFeedTests.swift
  - Tests/TransomEngineTests/UpdateStateTests.swift
  - Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/IntegrationSupport.swift
  - Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/TabStripSpaceIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/TabsIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/ViewsIntegrationTests.swift
  - Tests/TransomMacTests/AppMoverTests.swift
  - Tests/TransomMacTests/CollapsedLabelTests.swift
  - Tests/TransomMacTests/DisplaySettlerTests.swift
  - Tests/TransomMacTests/FreezeTestTests.swift
  - Tests/TransomMacTests/GestureTapRulesTests.swift
  - Tests/TransomMacTests/HighlightColorTests.swift
  - Tests/TransomMacTests/LoginItemTests.swift
  - Tests/TransomMacTests/MinimumHintsStoreTests.swift
  - Tests/TransomMacTests/OnboardingControllerTests.swift
  - Tests/TransomMacTests/OverviewCopyTests.swift
  - Tests/TransomMacTests/ReportProblemTests.swift
  - Tests/TransomMacTests/SettingsModelTests.swift
  - Tests/TransomMacTests/SettingsRouteTests.swift
  - Tests/TransomMacTests/SettingsWindowTests.swift
  - Tests/TransomMacTests/SetupWindowTests.swift
  - Tests/TransomMacTests/StatusGlyphTests.swift
  - Tests/TransomMacTests/TabCopyTests.swift
  - Tests/TransomMacTests/TakeoverMenuTests.swift
  - Tests/TransomMacTests/UpdateCheckTests.swift
  - Tests/TransomMacTests/UpdateDownloadTests.swift
  - Tests/TransomMacTests/UpdateMenuTests.swift
  - Tests/TransomMacTests/UpdateRealDMGTests.swift
  - Tests/TransomMacTests/UpdateScheduleTests.swift
  - Tests/TransomMacTests/ViewControlItemsTests.swift
  - Tests/TransomMacTests/ZoomCopyTests.swift
  - docs/macos-beta-checklist.md
  - docs/release-notes-0.9.0.md
  - docs/releasing.md
  - packaging/homebrew/transom.rb.template
  - scripts/release-version.sh
  - scripts/release.sh
  - xcode/Assets.xcassets/AppIcon.appiconset/Contents.json
  - xcode/Assets.xcassets/Contents.json
  - xcode/Assets.xcassets/TransomTemplate.imageset/Contents.json
  - xcode/Assets.xcassets/TransomTemplate.imageset/TransomTemplate.svg
  - xcode/Assets.xcassets/TransomZoomedTemplate.imageset/Contents.json
  - xcode/Assets.xcassets/TransomZoomedTemplate.imageset/TransomZoomedTemplate.svg
  - xcode/designated-requirement.txt
  - xcode/project.yml
findings:
  critical: 0
  warning: 7
  info: 3
  total: 10
  necessity: 0
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-11-07T21:22:11Z
**Depth:** standard
**Files Reviewed:** 124
**Status:** issues_found

## Summary

Scope was the diff from `24c279f` to HEAD. I read every changed source file and the workflow and release scripts in full. I read test files only to check their reliability: shared stub state, skip gates and serialisation.

**Updater (sound).** `GitHubReleaseClient`, `UpdateFeed`, `DMGDownloader`, `DMGVerifier` and `UpdateController` hold up against the threat model. Hosts are compared exactly, `..` and userinfo are refused, and every redirect is checked against the allow-list, with at most 5. The byte count is capped while downloading. The size and SHA-256 are checked before the move from `.part`. The requirement string pins `anchor apple generic`, the Team ID OU and `notarized`. Quarantine is set before `open`, and a failed check deletes the file. The progress callback cannot undo `.verifying`. I found no defect there.

**TransomURL and CLI settings (sound).** `settings?pane=` parsing is strict. Only a known `SettingsPane` raw value ever reaches the URL. The rate limiter shares one key across all panes.

**ReportProblem (sound).** It carries counts and fixed capability strings only. No titles, app names, bundle IDs or paths leak, and the query encoding removes `+&=#`.

**CloseRule / WindowTracker, D-23 and D-25.** I traced the new rows against the live-window cases:
- Minimised, hidden and other-Space windows answer AX as valid, so they never reach the "ordered out" row.
- A Cmd-T or Cmd-W in a group rebinds `visibleMemberID` through `tabGroups.update` in the same refresh, before `confirmClosedTabGroups` runs.

I could not build a provable case that closes a live window. The one inconsistency I found is Info only (IN-01).

**Where the defects are.** Most are in the Move-to-Applications onboarding path (WR-01 to WR-03) and in CI/release hardening (WR-04 to WR-07).

**Swift 6.3 hazard (not proven).** The flagged `ViewsIntegrationTests.swift:57` is `FixtureProcess.launch(...)` inside a `@MainActor` test, with no Sendable closure. `IntegrationEnv`'s statics are nonisolated: the test target has no default isolation (`Package.swift:50-52`), and `SpaceChangeRelay.marker` is declared `nonisolated static`. `swift build --build-tests` on the local 6.4.2 toolchain printed no concurrency diagnostics. That build may have been incremental, and I could not check 6.3.3. So I am not reporting it as a finding. Confirm it with the CI log of the next `swift test` run on `macos-26`.

**Not done.** No tests were run, and no live tests were run.

## Warnings

### WR-01: Move to Applications trashes the installed copy before the new copy exists, and the source can be the bundle it just trashed

**File:** `Sources/TransomMac/Onboarding/AppMover.swift:9-18`, `Sources/TransomMac/Permission/SetupWindowController.swift:141-151`
**Issue:**
- **Not atomic.** `copy(from:to:trash:)` first trashes `/Applications/Transom.app`, then runs `copyItem`. If the copy fails part-way (disk full, a permission error on one file, or a read error from an ejecting DMG), the user is left with no Transom in Applications. The failure callout then tells them to drag it there themselves.
- **The source can be the trashed bundle.** `InstallLocation.classify` checks `/AppTranslocation/` before `/Applications/`. Something other than Finder can put a quarantined Transom into `/Applications`: `unzip`, `ditto`, or a cask install that keeps quarantine. That copy runs translocated, so `needsMove` is true. The Replace alert then asks to replace "the Transom in Applications", which is the very bundle that is running. `Bundle.main.bundleURL` is a read-only view of `/Applications/Transom.app`, and that is the bundle `trash` moves away just before `copyItem` reads from it. At best the user gets a misleading "Replace" prompt about their own copy. At worst the copy reads from a moved original and fails, which leaves the WR-01 state above.

**Fix:** finish the copy before touching the destination:
```swift
static func copy(from source: URL, to destination: URL, trash: (URL) throws -> Void) throws {
    let staging = destination.deletingLastPathComponent()
        .appending(path: ".\(destination.lastPathComponent).moving-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: source, to: staging)          // read the source first, whatever it is
    // strip quarantine on `staging` as today
    do {
        if FileManager.default.fileExists(atPath: destination.path) { try trash(destination) }
        try FileManager.default.moveItem(at: staging, to: destination)  // same volume: a rename
    } catch {
        try? FileManager.default.removeItem(at: staging)
        throw error
    }
}
```
Also cover the translocated-from-`/Applications` case. Either skip the Replace alert when the running bundle's version and bundle ID match the destination's, or word the alert so it does not imply that a second copy exists.

### WR-02: Move always targets `/Applications/Transom.app`, so a Debug build replaces the release app

**File:** `Sources/TransomMac/Permission/SetupWindowController.swift:142`
**Issue:** The destination is hard-coded. A Debug build (`Transom Debug.app`, bundle ID `com.eightabyte.transom.debug`) that runs from `~/Downloads`, `/Volumes/...` or a translocated path gets the Move step too. On confirm it trashes the user's release `Transom.app` and installs the Debug build under the release name, with a different bundle ID. That has two effects:
- The release app's Accessibility grant no longer matches anything.
- `UpdateController.isEnabled` turns the updater off for that bundle.

`/usr/local/bin/transom`, created by the documented `ln -sf`, then points at the Debug helper.

**Fix:** derive the name from the running bundle, and only offer Move for the release bundle ID:
```swift
let destination = URL(fileURLWithPath: "/Applications").appending(path: Bundle.main.bundleURL.lastPathComponent)
```
Alternatively, set `needsMove = false` when `Bundle.main.bundleIdentifier != "com.eightabyte.transom"`.

### WR-03: The Move step has no way past it, so the Accessibility step cannot be reached from an external volume or `~/Downloads`

**File:** `Sources/TransomMac/Onboarding/OnboardingSteps.swift:62-85`, `Sources/TransomEngine/OnboardingFlow.swift:12-16`, `Sources/TransomEngine/InstallLocation.swift:14`, `Sources/TransomMac/Permission/SetupWindowController.swift:75-82`
**Issue:**
- **No exit.** The Move step offers only Quit and Move to Applications. `steps(...)` always puts `.move` first, even after completion, giving `[.move, .accessibility]`. `show()` keeps the current step, which is `.move`. Settings ▸ General's Set Up / Fix button and the menu's Grant / Fix item also open on Move. A user whose copy cannot or should not move is stuck: there is no Continue or Not Now. That includes copies on any external drive (`/Volumes/` is classified as a disk image, so the copy shows "a disk image" for a real drive) and a copy where Move fails (for example, a standard account that cannot write `/Applications`). They can never reach the Accessibility step or its Reset flow from Transom's UI. Without Accessibility, Transom does nothing.
- **Missed cases.** The classifier also cannot tell a mounted DMG from an external drive.

**Fix:**
1. Add a secondary "Not Now" button that calls `advance()`, so Move stays first and stays the default.
2. Leave `.move` out of `steps(completed: true, ...)`. That way the post-completion Fix / Grant path always lands on Accessibility.
3. If the spec must keep `/Volumes/`, check `URLResourceKey.volumeIsReadOnlyKey` or `volumeIsInternalKey`, so only read-only or disk-image volumes count as `.diskImage`.

### WR-04: The CI "Signing identity unchanged" guard is a substring match, and the debug and cli lines satisfy it

**File:** `.github/workflows/ci.yml:33-37`
**Issue:** `grep -qF -- 'PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom' xcode/project.yml` also matches `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom.debug` (line 52) and `...transom.cli` (line 78). If the Release line (line 57) changed to a different ID, the guard would still pass. The comment says that change would cost every user their Accessibility grant, and this guard is meant to catch it.
**Fix:** anchor the match to the whole line:
```bash
grep -qE '^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]*com\.eightabyte\.transom[[:space:]]*$' xcode/project.yml \
  || { echo "::error::Release PRODUCT_BUNDLE_IDENTIFIER changed"; exit 1; }
```
Anchoring the other two checks the same way also stops a commented-out line from satisfying them. Better still, read `targets.Transom.settings.configs.Release.PRODUCT_BUNDLE_IDENTIFIER` with `yq`.

### WR-05: The CI test job has no `timeout-minutes`

**File:** `.github/workflows/ci.yml:21-22`
**Issue:** The `test` job has `runs-on: macos-26` and no job-level `timeout-minutes`. The comment at lines 39-41 records a parallel run that "exits early with no message" on the runner. A hung `swift test` (a deadlocked suite, or a helper waiting on a run loop, as in the 09-25 Overview note) would hold a macOS runner for the 6-hour default. `release.yml` and `tap.yml` both set timeouts.
**Fix:** add `timeout-minutes: 60` (or a measured value) under `jobs.test`.

### WR-06: `tap.yml` publishes prereleases to the cask and lets a dispatch move the cask back to an older version

**File:** `.github/workflows/tap.yml:5-12, 39-58`
**Issue:**
- **Prereleases.** `release: types: [published]` also fires for a release that is marked prerelease. The job does not check `github.event.release.prerelease`, so publishing a vX.Y.Z prerelease makes it the cask version for every `brew upgrade`. The app's own updater ignores prereleases (`UpdateFeed.parse`), so the two channels disagree.
- **Downgrades.** `workflow_dispatch` accepts any published tag. Re-running it for an older tag rewrites `Casks/transom.rb` to the older version and pushes it, with no check against the current cask or `releases/latest`.

**Fix:** gate the job, and check that the tag is the latest release:
```yaml
jobs:
  cask:
    if: github.event_name == 'workflow_dispatch' || !github.event.release.prerelease
```
```bash
latest=$(gh api "repos/$REPO/releases/latest" --jq .tag_name)
[ "$latest" = "$TAG" ] || { echo "::error::$TAG is not releases/latest ($latest)"; exit 1; }
```

### WR-07: `HOMEBREW_TAP_TOKEN` is a repository secret, not an environment secret

**File:** `.github/workflows/tap.yml:60-65`, `docs/releasing.md:142-147`
**Issue:** The signing secrets sit behind the `release` environment and its required reviewer. The tap token, which can push to `scottkw/homebrew-transom` and so change what every `brew install` downloads, is a plain repository secret. Any workflow file on any branch can reference it, and a `workflow_dispatch` of `tap.yml` from any branch runs that branch's `tap.yml`. One pushed branch with an edited workflow (`ci.yml` runs on every push) can read it. This is weaker than the protection the docs describe for the signing keys.
**Fix:** move the token into an environment, for example `tap`, that allows only `v*` tags (deployment branch/tag rule) and optionally has a required reviewer. Add `environment: tap` to the `cask` job, and update `docs/releasing.md` to match.

## Info

### IN-01: A pending D-25 tab group skips CloseRule's paused-session guard

**File:** `Sources/TransomEngine/WindowTracker.swift:436-441`
**Issue:** `pendingGroups.contains(identity) ? CloseDecision.recheck : CloseRule.decide(...)` returns `.recheck` even when `context.sessionActive` is false. CloseRule's first row ("paused → noChange") is the documented contract. The effect is limited to extra quick rechecks, capped at 8 through `rechecks`, but the bypass is not stated in the CloseRule table.
**Fix:** `let decision = !context.sessionActive ? .noChange : pendingGroups.contains(identity) ? .recheck : CloseRule.decide(...)`. Or skip the group-close look entirely while the session is inactive.

### IN-02: `cgByID` and `shownSpaces` are rebuilt for the same refresh

**File:** `Sources/TransomEngine/WindowTracker.swift:381, 429-431`
**Issue:** `refresh` already builds `cgByID` (line 74) and passes it to `confirmClosedTabGroups`. `decide` then rebuilds both `cgByID` and `shownSpaces` from `context`. They are the same values, but there are now two sources of truth for the D-23 and D-25 inputs.
**Fix:** pass `cgByID` and `shownSpaces` into `decide`, or compute them once on `ObservationContext`.

### IN-03: Report a Problem says "installed from the disk image" for every non-Homebrew install

**File:** `Sources/TransomMac/Shell/ReportProblem.swift:50`
**Issue:** `homebrew == false` prints "from the disk image". That includes `swift run`, Debug builds, `~/Applications` copies, and an app moved by WR-01 from a translocated cask install. Bug reports may then point triage at the DMG path when it was never used.
**Fix:** print the `InstallLocation.Place` instead, for example `installed: applications | other | homebrew`.

---

_Reviewed: 2026-11-07T21:22:11Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
