---
phase: 09-polish-ship
verified: 2026-11-08T06:10:00Z
status: human_needed
score: 5/6 roadmap success criteria verified (1 present, behavior-unverified); plan must-haves 09-01..09-30 verified by code and tests except the on-screen and backstop items listed under human_verification
covered_files: [".github/workflows/ci.yml", ".github/workflows/release.yml", ".github/workflows/tap.yml", ".planning/phases/09-polish-ship/09-01-PLAN.md", ".planning/phases/09-polish-ship/09-01-SUMMARY.md", ".planning/phases/09-polish-ship/09-02-PLAN.md", ".planning/phases/09-polish-ship/09-02-SUMMARY.md", ".planning/phases/09-polish-ship/09-03-PLAN.md", ".planning/phases/09-polish-ship/09-03-SUMMARY.md", ".planning/phases/09-polish-ship/09-04-PLAN.md", ".planning/phases/09-polish-ship/09-04-SUMMARY.md", ".planning/phases/09-polish-ship/09-05-PLAN.md", ".planning/phases/09-polish-ship/09-05-SUMMARY.md", ".planning/phases/09-polish-ship/09-06-PLAN.md", ".planning/phases/09-polish-ship/09-06-SUMMARY.md", ".planning/phases/09-polish-ship/09-07-PLAN.md", ".planning/phases/09-polish-ship/09-07-SUMMARY.md", ".planning/phases/09-polish-ship/09-08-PLAN.md", ".planning/phases/09-polish-ship/09-08-SUMMARY.md", ".planning/phases/09-polish-ship/09-09-PLAN.md", ".planning/phases/09-polish-ship/09-09-SUMMARY.md", ".planning/phases/09-polish-ship/09-10-PLAN.md", ".planning/phases/09-polish-ship/09-10-SUMMARY.md", ".planning/phases/09-polish-ship/09-11-PLAN.md", ".planning/phases/09-polish-ship/09-11-SUMMARY.md", ".planning/phases/09-polish-ship/09-12-PLAN.md", ".planning/phases/09-polish-ship/09-12-SUMMARY.md", ".planning/phases/09-polish-ship/09-13-PLAN.md", ".planning/phases/09-polish-ship/09-13-SUMMARY.md", ".planning/phases/09-polish-ship/09-14-PLAN.md", ".planning/phases/09-polish-ship/09-14-SUMMARY.md", ".planning/phases/09-polish-ship/09-15-PLAN.md", ".planning/phases/09-polish-ship/09-15-SUMMARY.md", ".planning/phases/09-polish-ship/09-16-PLAN.md", ".planning/phases/09-polish-ship/09-16-SUMMARY.md", ".planning/phases/09-polish-ship/09-17-PLAN.md", ".planning/phases/09-polish-ship/09-17-SUMMARY.md", ".planning/phases/09-polish-ship/09-18-PLAN.md", ".planning/phases/09-polish-ship/09-18-SUMMARY.md", ".planning/phases/09-polish-ship/09-19-PLAN.md", ".planning/phases/09-polish-ship/09-19-SUMMARY.md", ".planning/phases/09-polish-ship/09-20-PLAN.md", ".planning/phases/09-polish-ship/09-20-SUMMARY.md", ".planning/phases/09-polish-ship/09-21-PLAN.md", ".planning/phases/09-polish-ship/09-21-SUMMARY.md", ".planning/phases/09-polish-ship/09-22-PLAN.md", ".planning/phases/09-polish-ship/09-22-SUMMARY.md", ".planning/phases/09-polish-ship/09-23-PLAN.md", ".planning/phases/09-polish-ship/09-23-SUMMARY.md", ".planning/phases/09-polish-ship/09-24-PLAN.md", ".planning/phases/09-polish-ship/09-24-SUMMARY.md", ".planning/phases/09-polish-ship/09-25-PLAN.md", ".planning/phases/09-polish-ship/09-25-SUMMARY.md", ".planning/phases/09-polish-ship/09-26-PLAN.md", ".planning/phases/09-polish-ship/09-26-SUMMARY.md", ".planning/phases/09-polish-ship/09-27-PLAN.md", ".planning/phases/09-polish-ship/09-27-SUMMARY.md", ".planning/phases/09-polish-ship/09-28-PLAN.md", ".planning/phases/09-polish-ship/09-28-SUMMARY.md", ".planning/phases/09-polish-ship/09-29-PLAN.md", ".planning/phases/09-polish-ship/09-29-SUMMARY.md", ".planning/phases/09-polish-ship/09-30-PLAN.md", ".planning/phases/09-polish-ship/09-30-SUMMARY.md", "README.md", "Sources/TransomEngine/CloseRule.swift", "Sources/TransomEngine/InstallLocation.swift", "Sources/TransomEngine/OnboardingFlow.swift", "Sources/TransomEngine/SettingsPane.swift", "Sources/TransomEngine/TransomURL.swift", "Sources/TransomEngine/UpdateRelease.swift", "Sources/TransomEngine/UpdateState.swift", "Sources/TransomEngine/WindowTracker.swift", "Sources/TransomMac/ArrangeController.swift", "Sources/TransomMac/HighlightColor.swift", "Sources/TransomMac/LoginItem.swift", "Sources/TransomMac/Onboarding/AppMover.swift", "Sources/TransomMac/Onboarding/OnboardingCopy.swift", "Sources/TransomMac/Onboarding/OnboardingSteps.swift", "Sources/TransomMac/Permission/SetupWindowController.swift", "Sources/TransomMac/Settings/ArrangingTab.swift", "Sources/TransomMac/Settings/ExclusionsTab.swift", "Sources/TransomMac/Settings/GeneralTab.swift", "Sources/TransomMac/Settings/MenuBarTab.swift", "Sources/TransomMac/Settings/SettingsCopy.swift", "Sources/TransomMac/Settings/SettingsWindowController.swift", "Sources/TransomMac/Settings/ShortcutsTab.swift", "Sources/TransomMac/Settings/UpdatesTab.swift", "Sources/TransomMac/Settings/ZoomGesturesTab.swift", "Sources/TransomMac/Shell/NoticeCopy.swift", "Sources/TransomMac/Shell/ReportProblem.swift", "Sources/TransomMac/Shell/StatusItemController.swift", "Sources/TransomMac/Shell/ViewControlItems.swift", "Sources/TransomMac/TransomMacApp.swift", "Sources/TransomMac/Updates/DMGDownloader.swift", "Sources/TransomMac/Updates/DMGVerifier.swift", "Sources/TransomMac/Updates/GitHubReleaseClient.swift", "Sources/TransomMac/Updates/UpdateController.swift", "Sources/TransomMac/Updates/UpdateCopy.swift", "scripts/release-version.sh", "scripts/release.sh", "xcode/designated-requirement.txt", "xcode/project.yml"]
covered_digest: "v4:sha256:f5699070590f86dda419d03e735a62601a84e902173bad852a73c36c513ac132"
behavior_unverified: 1
overrides_applied: 1
overrides:
  - must_have: "OverviewIntegrationTests reports results on macOS 27.2 (the test helper no longer exits during overviewOpensPerDisplayAndCloses) and passes on both macOS lines, or a product failure is recorded (D-17)"
    reason: "User decision D-24 (09-CONTEXT): the 27.2 swiftpm-testing-helper exit is test-only, cause unproven, deferred until after the release. No product cause is shown (the real app runs NSApp.run)."
    accepted_by: "Ken Scott (D-24, 09-CONTEXT.md)"
    accepted_at: "2026-11-07T00:00:00Z"
behavior_unverified_items:
  - truth: "SC3: Transom starts at the next login after the user turns on launch at login"
    test: "Finish onboarding (or Settings > General) with Open Transom at login on, log out or restart, log back in"
    expected: "Transom's menu-bar icon is present without opening the app by hand; Settings > General still shows the toggle on"
    why_human: "Only a fake LoginItemService is exercised by tests (by design: tests must not register the host login item). SMAppService.mainApp.register() is wired but no run, host or VM, has observed a login launch (09-28 guest check not done, D-29)."
human_verification:
  - test: "CI decision: the CI workflow on main is red for the released commit 7c4510a (runs 42442522000 push main, 42445497205 push v0.9.0). Both fail only in CLIListenerTests under the parallel swift test (D-27): 'Transom didn't answer', reply nil after about 6-7 s. The PR run on the identical tree 1fab6f9 passed (42441359049)."
    expected: "User decides: fix in 0.9.1 (serialise CLIListenerTests or widen its client timeout under parallel load) and re-run CI on main, or accept the flake. Until then main shows a red check."
    why_human: "Contradicts the stated 'CI on main is green'; a process decision, not a product defect. The local host gate passes."
  - test: "Settings window (09-01, 09-04..09-10, 09-18 backstops): open Settings (Cmd-,) from the menu-bar icon on macOS 15 and 27, walk all seven toolbar tabs in light and dark"
    expected: "macOS Settings look, the window title follows the tab, every tab fits at 560 pt with no clipping, Zoom & Gestures footers wrap"
    why_human: "Not seen on screen (user skipped UAT, D-29)"
  - test: "Onboarding on a first run (09-19..09-21): Welcome > Accessibility > Screen Recording > macOS window features (when one is on) > Launch at login > Done"
    expected: "Step captions count correctly, Accessibility advances by itself once granted, no permission prompt repeats, Launch at login is ticked by default"
    why_human: "Not seen on screen (user skipped UAT, D-29)"
  - test: "Screen Recording Quit & Reopen on macOS 15 (09-20 backstop)"
    expected: "After granting and accepting Quit & Reopen, onboarding resumes at the step after Screen Recording"
    why_human: "Not seen on screen (user skipped UAT, D-29); backstop truth, presence and unit tests do not count"
  - test: "Move to Applications (09-22 backstop): launch a quarantined copy from the DMG in a VM"
    expected: "The Move step shows first, the app relaunches from /Applications and the permissions then persist"
    why_human: "Not seen on screen (user skipped UAT, D-29); backstop truth"
  - test: "First open of the DMG-installed 0.9.0 in the clean pane-test guest (09-28 Task 3 remainder)"
    expected: "Only macOS's standard first-open confirmation, never 'cannot be opened' / 'unidentified developer'; onboarding starts at Welcome; Settings > Updates > Check for Updates says Transom 0.9.0 is up to date"
    why_human: "Not seen on screen (user skipped UAT, D-29). spctl accepted the DMG and app as Notarized Developer ID (09-28), but the first open itself was never observed"
  - test: "Launch at next login (SC3), see behavior_unverified_items"
    expected: "Transom running after login without a manual open"
    why_human: "Not seen on screen (user skipped UAT, D-29)"
  - test: "Menu-bar glyphs and update dot (09-16, 09-17 backstop): light, dark and tinted menu bars, including the Dell 1x display"
    expected: "Template glyphs crisp at 18 pt; the 6 pt dot reads clearly and does not merge with the fanlight"
    why_human: "Not seen on screen (user skipped UAT, D-29); visual"
  - test: "Menu-bar view controls (09-18 and its .onMove backstop): enable Back, Forward and Saved Views in Settings > Menu Bar, reorder by drag, Move Up/Down and VoiceOver"
    expected: "Items appear left of the Transom icon in Settings order only while zoom is on; the current saved view is filled; drag reorder works inside the grouped Form"
    why_human: "Not seen on screen (user skipped UAT, D-29); backstop truth"
  - test: "Collapsed-block label (09-23 backstop) at real block sizes in a VM"
    expected: "A quarter-width Safari block shows the full card, a thin strip shows icon only, a group shows its count"
    why_human: "Not seen on screen (user skipped UAT, D-29); backstop truth"
  - test: "transom://settings?pane=updates and Report a Problem from the menu"
    expected: "Settings opens on Updates; Report a Problem opens a prefilled GitHub new-issue page with versions and no titles or app names, and the same Details block is on the clipboard"
    why_human: "Not seen on screen (user skipped UAT, D-29); routing and body are unit-tested"
---

# Phase 9: Polish & Ship Verification Report

**Phase Goal:** As a new user, I want to install Transom from its signed DMG and be guided through setup, so that it starts at login and keeps itself updated.
**Mode:** mvp (User Story format valid)
**Verified:** 2026-11-08T06:10:00Z
**Status:** human_needed
**Re-verification:** No, initial verification

## User Flow Coverage

| # | Step | Expected | Evidence in codebase / artifacts | Status |
|---|------|----------|----------------------------------|--------|
| 1 | Download the signed DMG | Public latest release with DMG + .sha256 | I queried `releases/latest` without credentials: tag v0.9.0, not draft or prerelease, `Transom-0.9.0-universal.dmg` 10575256 bytes, digest `sha256:73f49423…3b80`, uploaded. The public `.sha256` file holds the same hash. The release body has no "brew". | VERIFIED |
| 2 | DMG is notarised Developer ID | Notarised, stapled, DR unchanged | Release run 42445497219 = success. Its log shows notarytool `status: Accepted` twice, "The staple and validate action worked!" and `source=Notarized Developer ID`. `UpdateRealDMGTests` passed 3/3 on the CI-built DMG. `release.sh` compares `codesign -d -r-` with `xcode/designated-requirement.txt` and stops on any difference (lines 51-53). | VERIFIED |
| 3 | Install opens without a Gatekeeper warning | Only the standard first-open confirmation | spctl in the 15.7.7 guest accepted the DMG and the app (09-28-SUMMARY and deferred-items; I did not re-run it, since no VM sessions are allowed). The first open itself was never observed. | VERIFIED (assessment); the first open was not seen on screen (D-29) |
| 4 | Guided through setup | Onboarding with Move, Welcome, Accessibility, Screen Recording, features, login, Done | `OnboardingFlow.steps/caption/resume` is pure and tested. `SetupWindowController` is wired in `TransomMacApp` with `SystemLoginItem` and `SnapshotCapture.request`. It requests once per click and then polls (D-06). `AppMover` uses `/bin/sh` with argv and no SPI. The OnboardingFlow, OnboardingController and AppMover tests pass. | VERIFIED (automated); not seen on screen (D-29) |
| 5 | Starts at login | Login item registered and the app launches at the next login | `LoginItem.swift` uses `SMAppService.mainApp` register, unregister and status. It is wired into onboarding (`SetupWindowController` line 145) and into General. LoginItemTests use a fake service. No login launch has ever been observed. | PRESENT_BEHAVIOR_UNVERIFIED |
| 6 | Keeps itself updated | Automatic and manual check, notify, verified DMG opened | `UpdateController`: `startAutomatic` (10 s, then 24 h) is called from StatusItemController line 81. `downloadAndOpen` order: size and SHA-256 in the downloader, then `SecStaticCodeCheckValidity` with `anchor apple generic … OU = S2K7P43927 … and notarized`, then quarantine, then open. A failure deletes the file. `GitHubReleaseClient` uses an ephemeral session with no URLCache. The UpdateCheck, Download, Schedule, Menu and State tests pass. | VERIFIED |

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Settings window covers gaps, appearance, gestures, hotkeys, exclusions, Mission Control replacement, New Windows and Drag to Dock | VERIFIED | `SettingsWindowController` is an NSTabViewController with `.toolbar` style and NSHostingController children. `StatusItemController.settingsTabs()` builds all seven panes (general, arranging, zoom, shortcuts, exclusions, menubar, updates) on the shared preference objects (gaps, newWindows, dragToDock, conflicts, gesturePreference, takeover, exclusions). `HighlightColor` is the only reader of `controlAccentColor` (grep: no other file). `ShortcutsWindowController.swift` is gone. The SettingsWindow, SettingsModel and HighlightColor tests pass. |
| 2 | Onboarding covers Accessibility, optional Screen Recording and conflicting features without prompt loops | VERIFIED | `OnboardingFlow.steps` returns `[move?] + welcome, accessibility, screenRecording, features?, launchAtLogin, done`. Screen Recording uses one `request()` per click, then polling (SetupWindowController lines 193-197). OnboardingFlowTests and OnboardingControllerTests pass. The on-screen walk was not seen (D-29). |
| 3 | User can turn on launch at login, and Transom starts at the next login | PRESENT_BEHAVIOR_UNVERIFIED | The toggle and registration are wired (`SMAppService.mainApp`), and the toggle logic is tested with a fake service. The login launch was never exercised. |
| 4 | Updates section: automatic toggle, Check for Updates, notify on newer, DMG opened only after sha256 and Team ID verify | VERIFIED | See flow step 6. `updates.automatic` defaults to true and restarts the schedule when changed. The update dot comes from `showsDot` and `withUpdateDot` in StatusItemController. No UNUserNotification or NSUserNotification anywhere (D-09). The real-DMG verifier passed in CI. |
| 5 | Signed, notarised DMG from the GitHub release installs and opens without Gatekeeper warnings (Homebrew deferred, D-26) | VERIFIED | See flow steps 1-3. README has no `brew install transom` (its only brew mention is xcodegen for contributors). `tap.yml` is kept and runs by hand only, per D-26. |
| 6 | Menu-bar back, forward and saved-view controls (current highlighted), choose and reorder in Settings; Report a Problem; update dot; `transom://settings?pane=` | VERIFIED | `ViewControlItems` dispatches `.camera(.back/.forward)` and draws `{n}.square.fill` for the current view, with `appearsDisabled` while paused. `MenuBarTab` is in the tabs factory. `ReportProblem` opens the issue URL and copies the details block, and `theReportNeverContainsTitlesAppNamesOrBundleIDs` passes. `TransomURL.settings(query:)` maps to `SettingsPane(rawValue:) ?? .general`, with one shared rate-limit key, and is routed through `ArrangeController.refusableEffects` to `openSettings`. The CLI `settings` command, its help line and its 64 exit exist (`CLICopy.settingsTooManyArguments`). The ViewControlItems, ReportProblem, SettingsRoute, TransomURL and UpdateMenu tests pass. |

**Score:** 5/6 truths verified (1 present, behavior-unverified)

### Plan must-haves (09-01..09-30), summary

- **09-01..09-23 (product):** I spot-checked the code and wiring for each plan group: settings tabs, URL and CLI, Arranging, Zoom & Gestures, gestures, Mission Control, Exclusions, highlight, General, Updates and its hardening, download and verify, icons, dot, menu, view controls, onboarding, Move, and the collapsed label. Every phase suite passed on the host. No debt markers (TBD/FIXME/XXX) are in phase-modified Sources, scripts, workflows or xcode.
- **Backstop truths:** the 09-17 Report privacy backstop is verified by a passing, wired test. The other backstops (09-01 toolbar look, 09-17 dot legibility, 09-18 `.onMove` and 560 pt fit, 09-20 Quit & Reopen, 09-22 VM Move, 09-23 real block sizes) are `insufficient_spec` and listed under human verification.
- **09-24/25/29/30 (live macOS 27 fixes):** the VM results are taken from SUMMARY and deferred-items log references. I did not run VM sessions, by rule. The host-side engine rows (CloseRuleTests, WindowTracker scenarios) pass in my host run (1345 engine tests). The 09-25 Overview helper exit is PASSED (override, D-24).
- **09-26..09-28 (ship):** MARKETING_VERSION is 0.9.0 and the public release checks above hold. **09-27's "merged to main with CI green":** the PR CI on tree 1fab6f9 was green. The merge commit 7c4510a has the identical tree (`git diff --stat` is empty), but CI on main failed on it twice in CLIListenerTests. This is flagged for a human decision (see Gaps Summary).

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `Sources/TransomMac/Settings/*` (9 files) | VERIFIED | Substantive (74-173 lines each) and wired through `settingsTabs()` |
| `Sources/TransomMac/Updates/*` (5 files) | VERIFIED | Built in TransomMacApp line 96 and started in StatusItemController line 81 |
| `Sources/TransomMac/Onboarding/*`, `Permission/SetupWindowController.swift` | VERIFIED | Wired in TransomMacApp (loginItem, requestScreenRecording, openSettings) |
| `Sources/TransomMac/LoginItem.swift` | VERIFIED | SMAppService.mainApp; used by General and onboarding |
| `Sources/TransomMac/Shell/ViewControlItems.swift`, `ReportProblem.swift` | VERIFIED | Built and used in StatusItemController |
| `Sources/TransomEngine/{OnboardingFlow,SettingsPane,UpdateRelease,UpdateState,InstallLocation,TransomURL}.swift` | VERIFIED | Pure; no AppKit (check-no-appkit OK) |
| `scripts/release.sh`, `scripts/release-version.sh`, `.github/workflows/release.yml` | VERIFIED | The release run used them successfully for v0.9.0 |
| `xcode/designated-requirement.txt` | VERIFIED | Identifier com.eightabyte.transom, OU S2K7P43927 |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| Menu Settings… / `transom://settings` / CLI | SettingsWindowController | `Command.settings(pane)`, then `ArrangeController.refusableEffects`, then `openSettings`, then `showSettings` | WIRED |
| Onboarding Launch at login | SMAppService | `SetupWindowController.loginItem = SystemLoginItem()` and `LoginItemToggle.toggled` | WIRED |
| UpdateController | DMGVerifier | `verify` defaults to `DMGVerifier.check`; open is reached only when `errSecSuccess` and quarantine succeed | WIRED |
| UpdateController status | menu-bar dot | `showsDot(updateStatus)` and `withUpdateDot` | WIRED |
| Settings Menu Bar | ViewControlItems | the `menuBar` preference shared by MenuBarTab and the status items | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| UpdatesTab | release status | `GitHubReleaseClient` to api.github.com `releases/latest` (stubbed URLProtocol in tests) | Yes (the live endpoint returns v0.9.0) | FLOWING |
| ExclusionsTab | excluded apps | `ExclusionStore` | Yes | FLOWING |
| MenuBarTab / ViewControlItems | saved slots | `arrange.arranger.savedViewSlots` | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Host gate | `env -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG swift test` | Four "Test run with" lines passed: 271/26, 607/81, 126/40, 1345/116 (2349 tests); exit 0; no issue recorded | PASS |
| Model/Engine without AppKit | `scripts/check-no-appkit.sh` | `no-appkit: OK (69 files)` | PASS |
| Public release | unauthenticated `releases/latest` and the `.sha256` download | v0.9.0; the digest equals the .sha256 | PASS |
| Release workflow | `gh run view 42445497219` | success, head 7c4510a; notarised and stapled; UpdateRealDMGTests 3/3 | PASS |
| CI on main | `gh run list` and the job logs | 42442522000 and 42445497205 **failure**: CLIListenerTests (`badRequestsAreRejected`, `aCommandCrossesThePortAndExitsZeroSilently`, and others) | FAIL (flake; see gaps summary) |
| Real-DMG tests on the host | (env-gated) | skipped on the host as designed; passed in CI | SKIP |

### Probe Execution

No `scripts/*/tests/probe-*.sh` is declared by the phase. Step 7c: not applicable.

### Requirements Coverage

| Requirement | Source plans | Status | Evidence |
|-------------|--------------|--------|----------|
| SHIP-01 | 09-01, 09-04..09-09 | SATISFIED | SC1 |
| SHIP-02 | 09-19..09-22 | SATISFIED (automated) | SC2; not seen on screen |
| SHIP-03 | 09-10, 09-21 | SATISFIED for the toggle; next-login launch unverified | SC3 |
| SHIP-04 | 09-11..09-13, 09-17 | SATISFIED | SC4 |
| SHIP-05 (amended, D-26) | 09-14, 09-15, 09-26..09-28 | SATISFIED | SC5 |
| SHIP-06 | 09-18 | SATISFIED (automated) | SC6 |
| SHIP-07 | 09-16, 09-17 | SATISFIED (automated) | SC6; the issue URL answers 302 (09-28) |
| SHIP-08 | 09-02, 09-03 | SATISFIED | SC6 |

No orphaned requirements. REQUIREMENTS.md still shows SHIP-01..08 as `[ ]` / Pending. The orchestrator should update them.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Sources/TransomMac/Shell/NoticeCopy.swift` | 40 | Stale copy: the `.takeoverCrashed` notice says "Choose Replace Mission Control in the Transom menu", but 09-07 removed that menu item. It is now Settings > Zoom & Gestures > "Use the Mission Control keys for the overview". | Warning | On a rare path, the user is pointed at a menu item that no longer exists. Fix in 0.9.1. |
| `Sources/TransomMac/Shell/OverviewCopy.swift` | 68 | `shortcutsZoomFooter` is defined but never read, and still says "With Replace Mission Control on" | Info | Dead copy |
| none | none | TBD / FIXME / XXX in phase-modified files | none | none found |

### Human Verification Required

These are listed in the frontmatter `human_verification`. Every on-screen, visual and backstop item is recorded as **not seen on screen (user skipped UAT, D-29)**, not as passed:

1. CI decision: main is red on 7c4510a (CLIListenerTests under parallel tests).
2. Settings window look and 560 pt fit, light and dark, macOS 15 and 27.
3. Onboarding walk-through on a first run.
4. Screen Recording Quit & Reopen resume (macOS 15).
5. Move to Applications from a quarantined DMG.
6. First open of the DMG-installed 0.9.0: Gatekeeper, onboarding, and Updates "up to date".
7. Launch at next login (SC3).
8. Glyphs and update dot on light, dark and tinted menu bars, and on the Dell 1x display.
9. Menu-bar view controls and reordering.
10. Collapsed-block label at real sizes.
11. `transom://settings?pane=updates` and Report a Problem on screen.

### Gaps Summary

No code or artifact gap blocks the user story. The DMG is public, notarised and verified. Setup, the login toggle and the updater are implemented, wired and unit-tested, and the host gate is green (2349 tests, four passing run lines, no-appkit OK).

The status is **human_needed**, not passed, for two reasons:

1. **CI on main is red, which contradicts the stated fact.** The CI workflow failed on main twice for the released commit 7c4510a: the push to main (42442522000) and the push of v0.9.0 (42445497205). Both failures are in `CLIListenerTests`: the CLI round trip times out ("Transom didn't answer") under the parallel test run that D-27 restored. The PR run on the identical tree passed. This is a timing flake in the test, not a product defect. D-29 does not cover it, so it needs the user's decision: fix in 0.9.1 (serialise the suite or widen its timeout) and re-run CI on main, or accept it.
2. **SC3's "starts at the next login" has never been exercised.** Tests use a fake login item, and the guest login check in 09-28 was not run (D-29).

If the user confirms that D-29 waives the on-screen items, including the guest first-open and login checks, and accepts or fixes the CI flake, the phase can be marked passed. A further 0.9.1 item is the stale `takeoverCrashed` notice copy.

---

_Verified: 2026-11-08T06:10:00Z_
_Verifier: Claude (gsd-verifier)_
