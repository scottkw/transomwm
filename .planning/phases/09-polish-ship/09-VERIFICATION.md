---
phase: 09-polish-ship
verified: 2026-11-08T07:20:00Z
status: passed
score: 5/6 roadmap success criteria verified (1 present, behavior-unverified, waived under D-29); plan must-haves 09-01..09-30 verified by code and tests except the on-screen and backstop items listed under waived_items
covered_files: [".github/workflows/ci.yml",".github/workflows/release.yml",".github/workflows/tap.yml",".planning/phases/09-polish-ship/09-01-PLAN.md",".planning/phases/09-polish-ship/09-01-SUMMARY.md",".planning/phases/09-polish-ship/09-02-PLAN.md",".planning/phases/09-polish-ship/09-02-SUMMARY.md",".planning/phases/09-polish-ship/09-03-PLAN.md",".planning/phases/09-polish-ship/09-03-SUMMARY.md",".planning/phases/09-polish-ship/09-04-PLAN.md",".planning/phases/09-polish-ship/09-04-SUMMARY.md",".planning/phases/09-polish-ship/09-05-PLAN.md",".planning/phases/09-polish-ship/09-05-SUMMARY.md",".planning/phases/09-polish-ship/09-06-PLAN.md",".planning/phases/09-polish-ship/09-06-SUMMARY.md",".planning/phases/09-polish-ship/09-07-PLAN.md",".planning/phases/09-polish-ship/09-07-SUMMARY.md",".planning/phases/09-polish-ship/09-08-PLAN.md",".planning/phases/09-polish-ship/09-08-SUMMARY.md",".planning/phases/09-polish-ship/09-09-PLAN.md",".planning/phases/09-polish-ship/09-09-SUMMARY.md",".planning/phases/09-polish-ship/09-10-PLAN.md",".planning/phases/09-polish-ship/09-10-SUMMARY.md",".planning/phases/09-polish-ship/09-11-PLAN.md",".planning/phases/09-polish-ship/09-11-SUMMARY.md",".planning/phases/09-polish-ship/09-12-PLAN.md",".planning/phases/09-polish-ship/09-12-SUMMARY.md",".planning/phases/09-polish-ship/09-13-PLAN.md",".planning/phases/09-polish-ship/09-13-SUMMARY.md",".planning/phases/09-polish-ship/09-14-PLAN.md",".planning/phases/09-polish-ship/09-14-SUMMARY.md",".planning/phases/09-polish-ship/09-15-PLAN.md",".planning/phases/09-polish-ship/09-15-SUMMARY.md",".planning/phases/09-polish-ship/09-16-PLAN.md",".planning/phases/09-polish-ship/09-16-SUMMARY.md",".planning/phases/09-polish-ship/09-17-PLAN.md",".planning/phases/09-polish-ship/09-17-SUMMARY.md",".planning/phases/09-polish-ship/09-18-PLAN.md",".planning/phases/09-polish-ship/09-18-SUMMARY.md",".planning/phases/09-polish-ship/09-19-PLAN.md",".planning/phases/09-polish-ship/09-19-SUMMARY.md",".planning/phases/09-polish-ship/09-20-PLAN.md",".planning/phases/09-polish-ship/09-20-SUMMARY.md",".planning/phases/09-polish-ship/09-21-PLAN.md",".planning/phases/09-polish-ship/09-21-SUMMARY.md",".planning/phases/09-polish-ship/09-22-PLAN.md",".planning/phases/09-polish-ship/09-22-SUMMARY.md",".planning/phases/09-polish-ship/09-23-PLAN.md",".planning/phases/09-polish-ship/09-23-SUMMARY.md",".planning/phases/09-polish-ship/09-24-PLAN.md",".planning/phases/09-polish-ship/09-24-SUMMARY.md",".planning/phases/09-polish-ship/09-25-PLAN.md",".planning/phases/09-polish-ship/09-25-SUMMARY.md",".planning/phases/09-polish-ship/09-26-PLAN.md",".planning/phases/09-polish-ship/09-26-SUMMARY.md",".planning/phases/09-polish-ship/09-27-PLAN.md",".planning/phases/09-polish-ship/09-27-SUMMARY.md",".planning/phases/09-polish-ship/09-28-PLAN.md",".planning/phases/09-polish-ship/09-28-SUMMARY.md",".planning/phases/09-polish-ship/09-29-PLAN.md",".planning/phases/09-polish-ship/09-29-SUMMARY.md",".planning/phases/09-polish-ship/09-30-PLAN.md",".planning/phases/09-polish-ship/09-30-SUMMARY.md","README.md","Sources/TransomEngine/CLIProtocol.swift","Sources/TransomEngine/CloseRule.swift","Sources/TransomEngine/InstallLocation.swift","Sources/TransomEngine/OnboardingFlow.swift","Sources/TransomEngine/SettingsPane.swift","Sources/TransomEngine/TransomURL.swift","Sources/TransomEngine/UpdateRelease.swift","Sources/TransomEngine/UpdateState.swift","Sources/TransomEngine/WindowTracker.swift","Sources/TransomMac/ArrangeController.swift","Sources/TransomMac/HighlightColor.swift","Sources/TransomMac/LoginItem.swift","Sources/TransomMac/Onboarding/AppMover.swift","Sources/TransomMac/Onboarding/OnboardingCopy.swift","Sources/TransomMac/Onboarding/OnboardingSteps.swift","Sources/TransomMac/Permission/SetupWindowController.swift","Sources/TransomMac/Settings/ArrangingTab.swift","Sources/TransomMac/Settings/ExclusionsTab.swift","Sources/TransomMac/Settings/GeneralTab.swift","Sources/TransomMac/Settings/MenuBarTab.swift","Sources/TransomMac/Settings/SettingsCopy.swift","Sources/TransomMac/Settings/SettingsWindowController.swift","Sources/TransomMac/Settings/ShortcutsTab.swift","Sources/TransomMac/Settings/UpdatesTab.swift","Sources/TransomMac/Settings/ZoomGesturesTab.swift","Sources/TransomMac/Shell/NoticeCopy.swift","Sources/TransomMac/Shell/ReportProblem.swift","Sources/TransomMac/Shell/StatusItemController.swift","Sources/TransomMac/Shell/ViewControlItems.swift","Sources/TransomMac/TransomMacApp.swift","Sources/TransomMac/Updates/DMGDownloader.swift","Sources/TransomMac/Updates/DMGVerifier.swift","Sources/TransomMac/Updates/GitHubReleaseClient.swift","Sources/TransomMac/Updates/UpdateController.swift","Sources/TransomMac/Updates/UpdateCopy.swift","Sources/transom-cli/main.swift","Tests/TransomMacTests/CLIListenerTests.swift","Tests/TransomMacTests/NoticeCopyTests.swift","scripts/release-version.sh","scripts/release.sh","xcode/designated-requirement.txt","xcode/project.yml"]
covered_digest: "v4:sha256:b8fc5596bd90bda97cec453c3e771965e1e73e87b44d6f147caa05d91c413523"
behavior_unverified: 1
overrides_applied: 1
overrides:
  - must_have: "OverviewIntegrationTests reports results on macOS 27.2 (the test helper no longer exits during overviewOpensPerDisplayAndCloses) and passes on both macOS lines, or a product failure is recorded (D-17)"
    reason: "User decision D-24 (09-CONTEXT): the 27.2 swiftpm-testing-helper exit is test-only, cause unproven, deferred until after the release. No product cause is shown (the real app runs NSApp.run)."
    accepted_by: "Ken Scott (D-24, 09-CONTEXT.md)"
    accepted_at: "2026-11-07T00:00:00Z"
re_verification:
  previous_status: human_needed
  previous_score: 5/6 (1 present, behavior-unverified)
  gaps_closed:
    - "CI on main green: run 42450262773 (CI, push main, head a48b926) concluded success with parallel tests; the CLIListenerTests timing flake is fixed by d6934c3 and 41276d8"
    - "Stale takeoverCrashed notice copy (previous Warning) now points to Settings > Zoom & Gestures > Use the Mission Control keys for the overview, matching SettingsCopy.useMissionControlKeys and the Zoom & Gestures tab title"
  gaps_remaining: []
  regressions: []
behavior_unverified_items:
  - truth: "SC3: Transom starts at the next login after the user turns on launch at login"
    test: "Finish onboarding (or Settings > General) with Open Transom at login on, log out or restart, log back in"
    expected: "Transom's menu-bar icon is present without opening the app by hand; Settings > General still shows the toggle on"
    why_human: "Only a fake LoginItemService is exercised by tests (by design). SMAppService.mainApp.register() is wired but no run has observed a login launch. Not seen on screen (waived, D-29)."
waived_items:
  # Waived by the user's D-29 decision (skip on-screen UAT), applied by the orchestrator to every former human_verification item.
  # Each is recorded as NOT SEEN ON SCREEN, never as passed. Anything found in use goes into 0.9.1.
  - test: "Settings window (09-01, 09-04..09-10, 09-18 backstops): all seven toolbar tabs, light and dark, macOS 15 and 27, 560 pt fit"
    result: "not seen on screen (waived, D-29)"
  - test: "Onboarding first run (09-19..09-21): Welcome > Accessibility > Screen Recording > features > Launch at login > Done"
    result: "not seen on screen (waived, D-29)"
  - test: "Screen Recording Quit & Reopen resume on macOS 15 (09-20 backstop)"
    result: "not seen on screen (waived, D-29)"
  - test: "Move to Applications from a quarantined DMG copy (09-22 backstop)"
    result: "not seen on screen (waived, D-29)"
  - test: "First open of the DMG-installed 0.9.0 in the clean pane-test guest (09-28 Task 3 remainder): standard first-open confirmation only, onboarding at Welcome, Updates says up to date"
    result: "not seen on screen (waived, D-29); spctl accepted DMG and app as Notarized Developer ID"
  - test: "Launch at next login (SC3)"
    result: "not seen on screen (waived, D-29); see behavior_unverified_items"
  - test: "Menu-bar glyphs and update dot on light, dark and tinted menu bars and the Dell 1x display (09-16, 09-17 backstop)"
    result: "not seen on screen (waived, D-29)"
  - test: "Menu-bar view controls and reordering incl. .onMove and VoiceOver (09-18 backstop)"
    result: "not seen on screen (waived, D-29)"
  - test: "Collapsed-block label at real block sizes (09-23 backstop)"
    result: "not seen on screen (waived, D-29)"
  - test: "transom://settings?pane=updates and Report a Problem from the menu"
    result: "not seen on screen (waived, D-29); routing and report body are unit-tested"
---

# Phase 9: Polish & Ship Verification Report

**Phase Goal:** As a new user, I want to install Transom from its signed DMG and be guided through setup, so that it starts at login and keeps itself updated.
**Mode:** mvp (User Story format valid)
**Verified:** 2026-11-08T07:20:00Z
**Status:** passed (with the D-29 waiver; on-screen items are recorded as not seen, not as passed)
**Re-verification:** Yes, after the CI flake fix (d6934c3, 41276d8; PRs #11 and #12)

## Re-verification delta

| Change | Check | Result |
|--------|-------|--------|
| `CLIProtocol.timeoutEnvironmentKey = "TRANSOM_CLI_TIMEOUT"` (d6934c3) | `CLIProtocol.timeout` is still `2`; the key is a new constant only | VERIFIED |
| `transom-cli/main.swift` reads the env var | `environment[key].flatMap(TimeInterval.init) ?? CLIProtocol.timeout`: unset or non-numeric falls back to the 2 s default; the same value is used for send and reply | VERIFIED, default kept |
| `CLIListenerTests` | the spawned tool gets `TRANSOM_CLI_TIMEOUT=30` (line 34); the in-process bad-request send uses 30/30 (41276d8). Only the test files set the key (grep) | VERIFIED |
| `NoticeCopy.takeoverCrashed` | now "Turn on Settings ▸ Zoom & Gestures ▸ Use the Mission Control keys for the overview…"; matches `SettingsCopy.useMissionControlKeys` (line 73) and the `.zoom` tab title "Zoom & Gestures" (line 114). `NoticeCopyTests.takeoverCrashedIsN10` updated | VERIFIED; previous Warning closed |
| main vs reviewed tree | `git diff --stat 41276d8 origin/main -- Sources Tests scripts .github xcode` is empty (a48b926 is the PR #12 merge) | VERIFIED |

Note (Info): the env hook is read by the shipped CLI too, not only under tests. It only changes how long the user's own `transom` invocation waits, so it carries no risk.

## User Flow Coverage

| # | Step | Expected | Evidence | Status |
|---|------|----------|----------|--------|
| 1 | Download the signed DMG | Public latest release with DMG + .sha256 | `releases/latest` (unauthenticated): v0.9.0, `Transom-0.9.0-universal.dmg`, the digest equals the public `.sha256` (previous run) | VERIFIED |
| 2 | DMG is notarised Developer ID | Notarised, stapled, DR unchanged | Release run 42445497219 success: notarytool Accepted, stapled, `source=Notarized Developer ID`; UpdateRealDMGTests 3/3 in CI; `release.sh` checks the DR against `xcode/designated-requirement.txt` | VERIFIED |
| 3 | Install opens without a Gatekeeper warning | Only the standard first-open confirmation | spctl in the 15.7.7 guest accepted DMG and app (09-28) | VERIFIED (assessment); first open not seen on screen (waived, D-29) |
| 4 | Guided through setup | Move, Welcome, Accessibility, Screen Recording, features, login, Done | `OnboardingFlow` is pure and tested; `SetupWindowController` is wired in `TransomMacApp`; one request per click, then polling (D-06) | VERIFIED (automated); not seen on screen (waived, D-29) |
| 5 | Starts at login | App launches at the next login | `LoginItem.swift` uses `SMAppService.mainApp`, wired into onboarding and General; tests use a fake service | PRESENT_BEHAVIOR_UNVERIFIED; not seen on screen (waived, D-29) |
| 6 | Keeps itself updated | Automatic and manual check, notify, verified DMG opened | `UpdateController.startAutomatic` (10 s, then 24 h) from StatusItemController; size and SHA-256, then `SecStaticCodeCheckValidity` with Team ID + notarized, then quarantine, then open; failure deletes the file | VERIFIED |

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Settings window covers gaps, appearance, gestures, hotkeys, exclusions, Mission Control replacement, New Windows, Drag to Dock | VERIFIED | Seven-pane toolbar `SettingsWindowController` built by `settingsTabs()` on shared preferences; Settings tests pass |
| 2 | Onboarding covers Accessibility, optional Screen Recording and conflicting features without prompt loops | VERIFIED | `OnboardingFlow.steps`; single request then polling; OnboardingFlow/Controller tests pass |
| 3 | User can turn on launch at login, and Transom starts at the next login | PRESENT_BEHAVIOR_UNVERIFIED (waived, D-29) | Toggle and `SMAppService.mainApp` registration wired and tested with a fake; the login launch was never observed |
| 4 | Updates: automatic toggle, Check for Updates, notify on newer, DMG opened only after sha256 and Team ID verify | VERIFIED | Flow step 6; `updates.automatic` defaults true; update dot via `showsDot`; no user notifications (D-09) |
| 5 | Signed, notarised DMG from the GitHub release installs and opens without Gatekeeper warnings (Homebrew deferred, D-26) | VERIFIED | Flow steps 1-3; README has no `brew install transom`; `tap.yml` manual only |
| 6 | Menu-bar back/forward/saved-view controls, choose and reorder in Settings; Report a Problem; update dot; `transom://settings?pane=` | VERIFIED | ViewControlItems, MenuBarTab, ReportProblem (privacy test passes), `TransomURL.settings` routed to `openSettings`; CLI `settings` command |

**Score:** 5/6 truths verified (1 present, behavior-unverified, waived under D-29)

### Plan must-haves (09-01..09-30)

- **09-01..09-23 (product):** code and wiring spot-checked per plan group in the previous run; unchanged except the notice copy fix above. No TBD/FIXME/XXX in phase-modified files.
- **Backstop truths:** 09-17 Report privacy backstop verified by a passing test. The other backstops are `insufficient_spec` and are in `waived_items` (not seen on screen, D-29).
- **09-24/25/29/30:** VM results from SUMMARY/deferred-items (no VM sessions by rule); host engine rows pass. 09-25 Overview helper exit is PASSED (override, D-24).
- **09-26..09-28 (ship):** MARKETING_VERSION 0.9.0 and the public release checks hold. **09-27 "merged to main with CI green":** now true. CI run 42450262773 on main (a48b926) concluded success.

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `Sources/TransomMac/Settings/*` | VERIFIED | Substantive, wired via `settingsTabs()` |
| `Sources/TransomMac/Updates/*` | VERIFIED | Built in TransomMacApp, started in StatusItemController |
| `Sources/TransomMac/Onboarding/*`, `Permission/SetupWindowController.swift` | VERIFIED | Wired in TransomMacApp |
| `Sources/TransomMac/LoginItem.swift` | VERIFIED | SMAppService.mainApp; used by General and onboarding |
| `Sources/TransomMac/Shell/{ViewControlItems,ReportProblem,NoticeCopy}.swift` | VERIFIED | Used in StatusItemController; notice copy corrected |
| `Sources/TransomEngine/{OnboardingFlow,SettingsPane,UpdateRelease,UpdateState,InstallLocation,TransomURL,CLIProtocol}.swift` | VERIFIED | Pure; no AppKit (check-no-appkit OK) |
| `Sources/transom-cli/main.swift` | VERIFIED | 2 s default kept; test-only override via env |
| `scripts/release.sh`, `scripts/release-version.sh`, `.github/workflows/{ci,release}.yml` | VERIFIED | Used for v0.9.0; CI green on main |
| `xcode/designated-requirement.txt` | VERIFIED | com.eightabyte.transom, OU S2K7P43927 |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| Menu Settings… / `transom://settings` / CLI | SettingsWindowController | `Command.settings(pane)` > `ArrangeController.refusableEffects` > `openSettings` | WIRED |
| Onboarding Launch at login | SMAppService | `SetupWindowController.loginItem = SystemLoginItem()` | WIRED |
| UpdateController | DMGVerifier | `verify` defaults to `DMGVerifier.check`; open only after `errSecSuccess` and quarantine | WIRED |
| UpdateController status | menu-bar dot | `showsDot(updateStatus)` and `withUpdateDot` | WIRED |
| Settings Menu Bar | ViewControlItems | shared `menuBar` preference | WIRED |
| transom-cli | CLIListener | CFMessagePort, timeout = env override or `CLIProtocol.timeout` (2 s) | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| UpdatesTab | release status | `GitHubReleaseClient` > api.github.com `releases/latest` | Yes (live v0.9.0) | FLOWING |
| ExclusionsTab | excluded apps | `ExclusionStore` | Yes | FLOWING |
| MenuBarTab / ViewControlItems | saved slots | `arrange.arranger.savedViewSlots` | Yes | FLOWING |

### Behavioral Spot-Checks (this run)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Host gate | `env -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG swift test` | Four passing "Test run with" lines: 271/26, 607/81, 126/40, 1345/116 (2349 tests); exit 0; no ✘ lines; CLIListenerTests suite passed | PASS |
| Model/Engine without AppKit | `scripts/check-no-appkit.sh` | `no-appkit: OK (69 files)` | PASS |
| CI on main | `gh run view 42450262773 --repo scottkw/transomwm` | CI, push, main, head a48b9262, status completed, conclusion success, job `test` success | PASS |
| Main tree = verified tree | `git diff --stat 41276d8 origin/main -- Sources Tests scripts .github xcode` | empty | PASS |
| Release workflow | `gh run view 42445497219` (previous run) | success, notarised and stapled, UpdateRealDMGTests 3/3 | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` is declared by the phase. Not applicable.

### Requirements Coverage

| Requirement | Source plans | Status | Evidence |
|-------------|--------------|--------|----------|
| SHIP-01 | 09-01, 09-04..09-09 | SATISFIED | SC1 |
| SHIP-02 | 09-19..09-22 | SATISFIED (automated); not seen on screen (D-29) | SC2 |
| SHIP-03 | 09-10, 09-21 | SATISFIED for the toggle; next-login launch not seen (waived, D-29) | SC3 |
| SHIP-04 | 09-11..09-13, 09-17 | SATISFIED | SC4 |
| SHIP-05 (amended, D-26) | 09-14, 09-15, 09-26..09-28 | SATISFIED | SC5 |
| SHIP-06 | 09-18 | SATISFIED (automated) | SC6 |
| SHIP-07 | 09-16, 09-17 | SATISFIED (automated) | SC6 |
| SHIP-08 | 09-02, 09-03 | SATISFIED | SC6 |

No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Sources/TransomMac/Shell/NoticeCopy.swift` | 40 | Stale "Replace Mission Control in the Transom menu" copy | Closed | Fixed in d6934c3 |
| `Sources/TransomMac/Shell/OverviewCopy.swift` | 68 | `shortcutsZoomFooter` is defined but never read, and still says "With Replace Mission Control on" | Info | Dead copy; 0.9.1 cleanup |
| `Sources/transom-cli/main.swift` | 34 | `TRANSOM_CLI_TIMEOUT` is honoured outside tests | Info | User-controlled wait only; default 2 s unchanged |
| none | none | TBD / FIXME / XXX in phase-modified files | none | none found |

### Waived On-Screen Items (D-29)

D-29 (09-CONTEXT.md line 112) skips the host on-screen UAT. Per the caller, the user's waiver also covers the guest first open and launch at next login (SC3). All ten former human-verification items are listed in `waived_items` and are recorded as **not seen on screen (waived, D-29)**. None is recorded as passed. SC3 stays PRESENT_BEHAVIOR_UNVERIFIED in `behavior_unverified_items` and is not counted in the score.

### Gaps Summary

No gaps. Both reasons for the previous `human_needed` are resolved:

1. **CI on main:** run 42450262773 on a48b926 succeeded with parallel tests. The fix only widens the CLI wait inside the tests (env hook plus 30 s for the in-process send). The shipped tool keeps its 2 s default.
2. **On-screen and login items:** waived by D-29 and recorded as not seen.

The previous Warning, the stale crash notice copy, is fixed. One Info item, the dead `shortcutsZoomFooter`, remains for 0.9.1.

---

_Verified: 2026-11-08T07:20:00Z_
_Verifier: Claude (gsd-verifier)_
