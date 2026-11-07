---
phase: "9"
slug: "polish-ship"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-11-06"
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (swift test), plus live suites in Tart VMs |
| **Config file** | Package.swift |
| **Quick run command** | `swift test --filter <Suite>` |
| **Full suite command** | `swift test` (four "Test run with" lines pass) + `scripts/check-no-appkit.sh` |
| **Estimated runtime** | ~90 seconds |

---

## Sampling Rate

- **After every task commit:** Run the task's `swift test --filter <Suite>` (log under `.build/09-NN-tK.log`), plus `scripts/check-no-appkit.sh` when TransomEngine changes
- **After every plan wave:** Run `env -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG swift test` (four passed "Test run with" lines, no ✘) + `scripts/check-no-appkit.sh` (each plan's last task)
- **Live suites:** only in the Tart VMs, one suite per `scripts/vm-session.sh` session (09-24, 09-25, 09-28); never `TRANSOM_LIVE` on the host
- **Before `/gsd-verify-work`:** Full host suite green, and green CI on `macos-26` (`swift test --no-parallel`, D-21)
- **Max feedback latency:** 120 seconds per filtered suite (host); VM runs are bounded by `vm-session.sh` (minutes)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Task | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | SHIP-01 | T-09-01 | Tracer, Settings… (⌘,) opens one toolbar-tab Settings window on its Sh | unit | `swift test --filter 'SettingsWindowTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-01-02 | 01 | 1 | SHIP-01 | T-09-01 | Shortcuts lives only in Settings: the window class and the Shortcuts…  | unit | `swift test --filter 'SettingsWindowTests\|ZoomCopyTests\|ShortcutsModelTests'` | ⚠ partly new | ⬜ pending |
| 09-02-01 | 02 | 2 | SHIP-08 | T-09-03 | Tracer, transom://settings?pane=updates reaches showSettings(.updates) | unit | `swift test --filter 'SettingsRouteTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-02-02 | 02 | 2 | SHIP-08 | T-09-03 | The strict parse and the shared rate limit, pinned case by case | unit | `swift test --filter 'TransomURLTests'` | ✅ | ⬜ pending |
| 09-03-01 | 03 | 3 | SHIP-08 | T-09-05 | Tracer, transom settings updates sends a path that parses to .settings | unit | `swift test --filter 'CLICommandLineTests'` | ✅ | ⬜ pending |
| 09-03-02 | 03 | 3 | SHIP-08 | T-09-05 | The App section in transom help, pinned by the contract test | unit | `swift test --filter 'CLICopyTests'` | ✅ | ⬜ pending |
| 09-04-01 | 04 | 4 | SHIP-01 | T-09-06 | Tracer, Gaps chosen in Settings ▸ Arranging is the menu's Gaps value a | unit | `swift test --filter 'SettingsModelTests\|GapPreferenceTests'` | ⚠ partly new | ⬜ pending |
| 09-04-02 | 04 | 4 | SHIP-01 | T-09-06 | New windows, Drag to dock and the Close Group question in Arranging | unit | `swift test --filter 'SettingsModelTests\|NewWindowsPreferenceTests\|DragToDockPreferenceTests'` | ⚠ partly new | ⬜ pending |
| 09-04-03 | 04 | 4 | SHIP-01 | T-09-06 | macOS window features rows and Restore, driven by an observable Confli | unit | `swift test --filter 'SettingsModelTests\|ConflictControllerTests'` | ⚠ partly new | ⬜ pending |
| 09-05-01 | 05 | 5 | SHIP-01 | T-09-08 | Tracer, "Use zoom" in Settings runs the menu's Turn On/Off Zoom path | unit | `swift test --filter 'SettingsModelTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-05-02 | 05 | 5 | SHIP-01 | T-09-08 | The title-bar double-click toggle moves from Shortcuts to Zoom &amp; G | unit | `swift test --filter 'SettingsModelTests\|ShortcutsModelTests'` | ⚠ partly new | ⬜ pending |
| 09-06-01 | 06 | 6 | SHIP-01 | T-09-09 | Tracer, gestures.option off makes the published tap state pass an ⌥ pi | unit | `swift test --filter 'GestureTapRulesTests\|GestureControllerTests'` | ✅ | ⬜ pending |
| 09-06-02 | 06 | 6 | SHIP-01 | T-09-09 | The two Trackpad toggles in Settings, and no gesture tap when both are | unit | `swift test --filter 'SettingsModelTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-07-01 | 07 | 7 | SHIP-01 | T-09-11 | Tracer, the Settings toggle turns the takeover on only after the expla | unit | `swift test --filter 'TakeoverMenuTests'` | ✅ | ⬜ pending |
| 09-07-02 | 07 | 7 | SHIP-01 | T-09-11 | Replace Mission Control leaves the status menu | unit | `swift test --filter 'TakeoverMenuTests\|OverviewCopyTests\|CommandMenuTests'` | ✅ | ⬜ pending |
| 09-08-01 | 08 | 8 | SHIP-01 | T-09-12 | Tracer, the Exclusions tab lists the store and − removes an app everyw | unit | `swift test --filter 'SettingsModelTests\|ExclusionStoreTests'` | ⚠ partly new | ⬜ pending |
| 09-08-02 | 08 | 8 | SHIP-01 | T-09-12 | + adds apps through an Open panel, refusing Transom itself and apps wi | unit | `swift test --filter 'SettingsModelTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-09-01 | 09 | 9 | SHIP-01 | T-09-14 | Tracer, a Custom highlight chosen in Settings ▸ General colours the dr | unit | `swift test --filter 'HighlightColorTests\|PreviewStyleTests'` | ⚠ partly new | ⬜ pending |
| 09-09-02 | 09 | 9 | SHIP-01 | T-09-14 | Rings and gap handles use the highlight too, and redraw when it change | unit | `swift test --filter 'HighlightColorTests\|TileLayerTests\|GapHandleGeometryTests'` | ⚠ partly new | ⬜ pending |
| 09-10-01 | 10 | 10 | SHIP-03, SHIP-01 | T-09-15 | Tracer, "Open Transom at login" registers the app through the login it | unit | `swift test --filter 'LoginItemTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-10-02 | 10 | 10 | SHIP-03, SHIP-01 | T-09-15 | General ▸ Permissions: Accessibility and Screen Recording rows | unit | `swift test --filter 'SettingsModelTests\|ZoomOffTests'` | ⚠ partly new | ⬜ pending |
| 09-10-03 | 10 | 10 | SHIP-03, SHIP-01 | T-09-15 | General ▸ Command-line tool row and the Debug "Login item" line | unit | `swift test --filter 'LoginItemTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-11-01 | 11 | 11 | SHIP-04 | T-09-17 | Tracer, checkNow() fetches releases/latest from a stub server and repo | unit | `swift test --filter 'UpdateCheckTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-11-02 | 11 | 11 | SHIP-04 | T-09-17 | The Updates tab, wired to the app's one UpdateController | unit | `swift test --filter 'UpdateCheckTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-12-01 | 12 | 12 | SHIP-04 | T-09-20 | Tracer, a release Transom can't install is never offered, from the stu | unit | `swift test --filter 'UpdateFeedTests\|UpdateCheckTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-12-02 | 12 | 12 | SHIP-04 | T-09-20 | The state machine: one operation at a time, failures restore, manual e | unit | `swift test --filter 'UpdateStateTests\|UpdateCheckTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-12-03 | 12 | 12 | SHIP-04 | T-09-20 | ETag caching, rate-limit answers and the automatic-check toggle | unit | `swift test --filter 'UpdateCheckTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-13-01 | 13 | 13 | SHIP-04 | T-09-23 | Tracer, Download and Open fetches the asset, checks its digest, verifi | unit | `swift test --filter 'UpdateDownloadTests\|UpdateStateTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-13-02 | 13 | 13 | SHIP-04 | T-09-23 | Every failed check deletes the file and opens nothing; the real DMG pa | unit | `swift test --filter 'UpdateDownloadTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-13-03 | 13 | 13 | SHIP-04 | T-09-23 | The download states in the Updates tab, and the Homebrew branch | unit | `swift test --filter 'UpdateDownloadTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-14-01 | 14 | 14 | SHIP-05 | T-09-27 | Tracer, release.sh --build-only reads the version from project.yml and | script | `scripts/release.sh --build-only` | ✅ | ⬜ pending |
| 09-14-02 | 14 | 14 | SHIP-05 | T-09-27 | The -universal.dmg name and its .sha256, the notary profile variable,  | script | `scripts/release.sh --skip-notarize` | ✅ | ⬜ pending |
| 09-15-01 | 15 | 15 | SHIP-05 | T-09-30 | Tracer, release.yml takes a v tag through the gate to a signed, notari | script | `scripts/release.sh --skip-notarize` | ✅ | ⬜ pending |
| 09-15-02 | 15 | 15 | SHIP-05 | T-09-30 | tap.yml and the cask template, rendered and syntax-checked | static | `ruby YAML parse / ruby -c + required-step greps` | ❌ W0 (created in task) | ⬜ pending |
| 09-15-03 | 15 | 15 | SHIP-05 | T-09-30 | CI identity guard, the D-21 parallel diagnostic, and the release runbo | static | `ruby YAML parse / ruby -c + required-step greps` | ❌ W0 (created in task) | ⬜ pending |
| 09-16-01 | 16 | 16 | SHIP-05 | T-09-35 | Tracer, the Release app is built with the Transom app icon from an ass | script | `scripts/release.sh --build-only` | ✅ | ⬜ pending |
| 09-16-02 | 16 | 16 | SHIP-05 | T-09-35 | The menu-bar glyph is the Transom template, zoomed variant when zoomed | unit | `swift test --filter 'StatusGlyphTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-17-01 | 17 | 17 | SHIP-07, SHIP-04 | T-09-36 | Tracer, a known newer release puts a dot on the icon and an "Update to | unit | `swift test --filter 'UpdateMenuTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-17-02 | 17 | 17 | SHIP-07, SHIP-04 | T-09-36 | The daily automatic check and the Debug "Updates" line | unit | `swift test --filter 'UpdateScheduleTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-17-03 | 17 | 17 | SHIP-07, SHIP-04 | T-09-36 | Report a Problem… opens a prefilled GitHub issue and copies the same d | unit | `swift test --filter 'ReportProblemTests\|MenuCopyTests'` | ⚠ partly new | ⬜ pending |
| 09-18-01 | 18 | 18 | SHIP-06 | T-09-39 | Tracer, turning on Back in Settings ▸ Menu Bar adds a back button left | unit | `swift test --filter 'ViewControlItemsTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-18-02 | 18 | 18 | SHIP-06 | T-09-39 | Saved-view badges with the current view filled | unit | `swift test --filter 'ViewControlItemsTests\|ArrangerViewsTests'` | ⚠ partly new | ⬜ pending |
| 09-18-03 | 18 | 18 | SHIP-06 | T-09-39 | Reorder, Icon only, disabled looks, and all seven Settings tabs | unit | `swift test --filter 'ViewControlItemsTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-19-01 | 19 | 19 | SHIP-02 | T-09-41 | Tracer, a first run walks Welcome → Accessibility → Done and Done reco | unit | `swift test --filter 'OnboardingFlowTests\|SetupWindowTests'` | ⚠ partly new | ⬜ pending |
| 09-19-02 | 19 | 19 | SHIP-02 | T-09-41 | After completion only the Accessibility step opens, and closing early  | unit | `swift test --filter 'OnboardingControllerTests\|SetupWindowTests'` | ⚠ partly new | ⬜ pending |
| 09-20-01 | 20 | 20 | SHIP-02 | T-09-43 | Tracer, the Screen Recording step requests once per click, polls, and  | unit | `swift test --filter 'OnboardingControllerTests\|OnboardingFlowTests\|ZoomOffTests'` | ⚠ partly new | ⬜ pending |
| 09-20-02 | 20 | 20 | SHIP-02 | T-09-43 | Resume after a relaunch, completion on close from step 3, and Done's O | unit | `swift test --filter 'OnboardingControllerTests\|OnboardingFlowTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-21-01 | 21 | 21 | SHIP-02, SHIP-03 | T-09-45 | Tracer, the Launch at login step registers Transom by default and hand | unit | `swift test --filter 'OnboardingControllerTests\|OnboardingFlowTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-21-02 | 21 | 21 | SHIP-02, SHIP-03 | T-09-45 | The macOS window features step, shown only when one is on | unit | `swift test --filter 'OnboardingControllerTests\|OnboardingFlowTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-22-01 | 22 | 22 | SHIP-02 | T-09-47 | Tracer, a disk-image launch puts Move first, and the move copies the b | unit | `swift test --filter 'InstallLocationTests\|OnboardingFlowTests\|AppMoverTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-22-02 | 22 | 22 | SHIP-02 | T-09-47 | The Move step, the Replace alert and the failure callout | unit | `swift test --filter 'AppMoverTests\|OnboardingControllerTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-23-01 | 23 | 23 | ZOOM-13 | T-09-50 | Tracer, a roomy collapsed block shows its title and "Collapsed" under  | unit | `swift test --filter 'CollapsedLabelTests'` | ❌ W0 (created in task) | ⬜ pending |
| 09-23-02 | 23 | 23 | ZOOM-13 | T-09-50 | Smaller blocks fall back to one line, then to the icon alone; Increase | unit | `swift test --filter 'CollapsedLabelTests\|TabCopyTests\|TileLayerTests'` | ⚠ partly new | ⬜ pending |
| 09-24-01 | 24 | 24 | WIN-03, VIEW-01, VIEW-04 | T-09-51 | Tracer, itResumesByItself awaits the resume task and passes 20 runs in | unit | `swift test --filter 'FreezeTestTests'` | ✅ | ⬜ pending |
| 09-24-02 | 24 | 24 | WIN-03, VIEW-01, VIEW-04 | T-09-51 | ViewsIntegrationTests on macOS 27.2: diagnose aViewOnAnotherSpaceSwitc | live (VM) | `VM: vm-session.sh vm-live-test.sh ViewsIntegrationTests` | ✅ | ⬜ pending |
| 09-24-03 | 24 | 24 | WIN-03, VIEW-01, VIEW-04 | T-09-51 | RematchIntegrationTests on macOS 27.2: diagnose aPlaceholderIsClickThr | live (VM) | `VM: vm-session.sh vm-live-test.sh RematchIntegrationTests` | ✅ | ⬜ pending |
| 09-25-01 | 25 | 25 | OVER-01, TABS-02, TABS-03 | T-09-53 | Tracer, OverviewSpaceSwitchIntegrationTests passes on macOS 27.2 with  | live (VM) | `VM: vm-session.sh vm-live-test.sh OverviewSpaceSwitchIntegrationTests` | ✅ | ⬜ pending |
| 09-25-02 | 25 | 25 | OVER-01, TABS-02, TABS-03 | T-09-53 | OverviewIntegrationTests reports on macOS 27.2, and TabStripSpace's st | live (VM) | `VM: vm-session.sh vm-live-test.sh OverviewIntegrationTests` | ✅ | ⬜ pending |
| 09-25-03 | 25 | 25 | OVER-01, TABS-02, TABS-03 | T-09-53 | TabGroupIntegrationTests' close confirmation on macOS 27.2, and the ho | live (VM) | `VM: vm-session.sh vm-live-test.sh TabGroupIntegrationTests` | ✅ | ⬜ pending |
| 09-26-01 | 26 | 26 | SHIP-05, SHIP-04 | T-09-55 | Tracer, version 0.9.0 passes the tag gate and the local dry run builds | script | `scripts/release.sh --skip-notarize` | ✅ | ⬜ pending |
| 09-26-02 | 26 | 26 | SHIP-05, SHIP-04 | T-09-55 | The phase-end README: install, Settings, updates, menu, URL, data and  | static | `grep content checks` | n/a | ⬜ pending |
| 09-26-03 | 26 | 26 | SHIP-05, SHIP-04 | T-09-55 | The macOS-beta checklist and the name-check record, then the full host | static | `grep content checks` | n/a | ⬜ pending |
| 09-27-01 | 27 | 27 | SHIP-05 | T-09-57 | Confirm the public contracts before they become one-way | manual | `checkpoint (human)` | n/a | ⬜ pending |
| 09-27-02 | 27 | 27 | SHIP-05 | T-09-57 | Merge to main, go public, configure the release environment, secrets a | manual | `checkpoint (human)` | n/a | ⬜ pending |
| 09-27-03 | 27 | 27 | SHIP-05 | T-09-57 | Check the GitHub setup and the dry run through the API, and run the D- | remote check | `gh api / curl read-only checks` | n/a | ⬜ pending |
| 09-28-01 | 28 | 28 | SHIP-05, SHIP-04, SHIP-03 | T-09-60 | Tag v0.9.0, approve the release job, and publish the draft as latest | manual | `checkpoint (human)` | n/a | ⬜ pending |
| 09-28-02 | 28 | 28 | SHIP-05, SHIP-04, SHIP-03 | T-09-60 | Check the public release, its digest and the tap cask end to end | static | `ruby YAML parse / ruby -c + required-step greps` | ❌ W0 (created in task) | ⬜ pending |
| 09-28-03 | 28 | 28 | SHIP-05, SHIP-04, SHIP-03 | T-09-60 | Install with Homebrew in a clean VM and check Gatekeeper, the designat | live (VM) | `VM: vm-session.sh (guest brew install + spctl)` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

No separate Wave 0 plan: each new suite is created by the task that first needs it (tracer or `tdd="true"` task), so no task runs without an automated check.

- [ ] Engine: `OnboardingFlowTests`, `InstallLocationTests`, `UpdateFeedTests`, `UpdateStateTests` (+ `settings` cases in `TransomURLTests`, `CLICommandLineTests`, `CLICopyTests`, `currentViewSlot` cases in `ArrangerViewsTests`)
- [ ] Mac: `SettingsWindowTests`, `SettingsRouteTests`, `SettingsModelTests`, `HighlightColorTests`, `LoginItemTests`, `UpdateCheckTests`, `UpdateDownloadTests`, `UpdateRealDMGTests` (env-gated on `UPDATE_REAL_DMG`), `UpdateMenuTests`, `UpdateScheduleTests`, `ReportProblemTests`, `StatusGlyphTests`, `ViewControlItemsTests`, `OnboardingControllerTests` (DEBUG), `AppMoverTests`, `CollapsedLabelTests`
- [ ] Stub `URLProtocol` for every network test (no test reaches GitHub); throwaway `UserDefaults(suiteName:)` for every preference test
- [ ] No framework install: Swift Testing via SwiftPM

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Settings toolbar look and title follow the tab on macOS 15 and 27 | SHIP-01 | Visual, system-drawn | VM screen share: open Settings, click each tab |
| Every tab fits at 560 pt in light and dark; `.onMove` reorder works in the grouped Form | SHIP-01, SHIP-06 | Visual and drag | Host UAT checklist items 1-2 (09-18 human-check) |
| Update dot legible on light, dark and tinted menu bars; template glyph crisp on the 1x DELL | SHIP-07, SHIP-05 | Visual | Host UAT with a known newer release (09-16, 09-17) |
| Move to Applications from a quarantined DMG download relaunches from /Applications and keeps permissions | SHIP-02 | Gatekeeper translocation needs a real download | VM: download the DMG in Safari, open, Move, grant Accessibility, relaunch (09-22 backstop) |
| Screen Recording "Quit & Reopen" resumes onboarding after the Screen Recording step | SHIP-02 | System prompt flow | VM on macOS 15 (09-20 backstop) |
| Transom starts at the next login with "Open Transom at login" on | SHIP-03 | Needs a real logout/login | VM after the brew install (09-28 human-check) |
| `brew install --cask scottkw/transom/transom` opens without a Gatekeeper warning | SHIP-05 | Gatekeeper dialogs are visual | VM after publish (09-28 human-check; spctl/DR automated) |
| Collapsed label at real block sizes | ZOOM-13 (D-16) | Real window sizes | VM / host checklist item 5 (09-23) |
| Report a Problem opens a new-issue page with no titles or app names | SHIP-07 | Needs the public repo and a browser | Host checklist item 4 (09-28); privacy pinned by `ReportProblemTests` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies (only the 09-27/09-28 human checkpoints have none; each is followed by an automated check task)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s per filtered host suite
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** {pending / approved YYYY-MM-DD}
