---
phase: "3"
slug: "tiling-mvp"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-25"
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (toolchain bundled), as in Phases 1–2 |
| **Config file** | none (SwiftPM); CI: `.github/workflows/ci.yml` |
| **Quick run command** | `swift test --filter 'PaneModelTests|PaneEngineTests'` (measured 4.2 s incremental, 234 tests at research time) |
| **Full suite command** | `swift test && swift test -c release -Xswiftc -enable-testing` |
| **Trusted integration** | `swift test --filter PaneMacIntegrationTests` (auto-skips without AX trust, `IntegrationSupport.swift:8`); run under `caffeinate -d -i` |
| **Guardrails** | `scripts/check-no-appkit.sh` (PaneModel/PaneEngine AppKit-free); `NoScreenCaptureTests` (TILE-10) |
| **Build checks** | `scripts/build-debug.sh` (signed Debug app + designated requirement); `scripts/release.sh --build-only` / `--skip-notarize` (plan 17) |
| **Estimated runtime** | ~5 seconds (quick), ~150 seconds (full, including the release-mode run) |

Test types: **unit** = pure PaneModel/PaneEngine functions and PaneMac value types. **fake** = `Arranger` + `FakeWindowSystem` scenarios with synthetic pointer events and an injected clock. **live-fixture** = `PaneMacIntegrationTests` against `PaneFixtureApp` with real AX, touching fixture windows only (AXWindowSystem `appFilter` admits only the fixture pid). **manual** = human UAT, collected from each task's `<human-check>` at end of phase.

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter 'PaneModelTests|PaneEngineTests'` plus `scripts/check-no-appkit.sh`
- **After every plan wave:** Run `swift test && swift test -c release -Xswiftc -enable-testing`, plus `caffeinate -d -i swift test --filter PaneMacIntegrationTests` from a trusted terminal
- **Before `/gsd-verify-work`:** Full suite green (integration suite run, not skipped), `scripts/build-debug.sh` verified, `scripts/release.sh` run once successfully (plan 17 checkpoint), and the manual rows below signed off
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | TILE-07, TILE-15 | T-03-01, T-03-02 | Decoded trees hold `.desktop` only under NodeID.desktop; IDSource never mints it | unit | `swift test --filter "DesktopLeafTests|PersistenceTests"` | ❌ W0 (DesktopLeafTests) | ⬜ pending |
| 03-01-02 | 01 | 1 | TILE-15 | T-03-01 | Hide refused with nothing docked; desk fixtures migrated, no invariant test deleted | unit | `swift test --filter 'PaneModelTests|PaneEngineTests'` | ✅ | ⬜ pending |
| 03-02-01 | 02 | 2 | TILE-11, TILE-12 | T-03-04 | rotate iterative within maxDepth; every edit validates | unit | `swift test --filter LayoutEditTests` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 2 | TILE-13, TILE-05 | T-03-03 | Weights clamped at minWeight | unit | `swift test --filter "LayoutEditTests|NeighbourTests"` | ❌ W0 | ⬜ pending |
| 03-02-03 | 02 | 2 | TILE-14 | — | N/A | unit | `swift test --filter SnapTests` | ❌ W0 | ⬜ pending |
| 03-03-01 | 03 | 2 | SAFE-06 | T-03-05 | Rekey onto a held ID closes the old one; World validated before commit | unit | `swift test --filter "WorldRekeyTests|LifecycleSyncTests"` | ❌ W0 (WorldRekeyTests) | ⬜ pending |
| 03-03-02 | 03 | 2 | TILE-07, TILE-09 | T-03-06 | Floating frames isValidGeometry-checked | unit | `swift test --filter 'PaneModelTests|PaneEngineTests'` | ✅ | ⬜ pending |
| 03-04-01 | 04 | 3 | TILE-03, TILE-07 | T-03-07, T-03-08 | Every command through `perform` (ExclusionFilter.admit); 0.5 pt write threshold | fake + live-fixture | `swift test --filter "PlannerTests|ArrangerLifecycleTests"` and `caffeinate -d -i swift test --filter ArrangeIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-04-02 | 04 | 3 | TILE-09, TILE-10 | T-03-10 | KeyboardShortcuts pinned `exact: "3.1.0"` + committed Package.resolved; no ScreenCaptureKit | unit + build | `swift test --filter "ArrangerLifecycleTests|HotkeyTableTests|NoScreenCaptureTests"` and `scripts/build-debug.sh` | ❌ W0 | ⬜ pending |
| 03-04-03 | 04 | 3 | TILE-20, WIN-07 | — | Session pause emits no commands | fake + live-fixture | `swift test --filter ArrangerLifecycleTests` and `caffeinate -d -i swift test --filter ArrangeIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-05-01 | 05 | 4 | WIN-07 | T-03-11 | SkyLight via dlopen/dlsym only; nil fallback | fake + live-fixture | `swift test --filter ArrangerSpacesTests` and `caffeinate -d -i swift test --filter SpacesIntegrationTests` | ❌ W0 / ✅ (extend) | ⬜ pending |
| 03-05-02 | 05 | 4 | WIN-07, TILE-03 | T-03-12 | Re-home only on known disjoint Space sets | unit + fake | `swift test --filter "ArrangerSpacesTests|TrackerDisplayTests|ArrangerLifecycleTests"` | ✅ (extend) | ⬜ pending |
| 03-06-01 | 06 | 5 | TILE-03 | T-03-14 | Toast shows app names only, click-through, never activates | fake + unit + live-fixture | `swift test --filter "ArrangerReflowTests|NoticeQueueTests|NoticeCopyTests"` and `caffeinate -d -i swift test --filter ArrangeIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-06-02 | 06 | 5 | TILE-07 | T-03-13 | App-move correction at most once per second | fake | `swift test --filter "ArrangerReflowTests|ArrangerLifecycleTests|ArrangerSpacesTests"` | ❌ W0 | ⬜ pending |
| 03-07-01 | 07 | 6 | SAFE-06 | T-03-16 | Re-attach by exact identity; synthetic IDs never matched | fake + live-fixture | `swift test --filter ArrangerRestoreTests` and `caffeinate -d -i swift test --filter ArrangeIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-07-02 | 07 | 6 | SAFE-06 | T-03-15, T-03-17, T-03-18 | layout.json size cap, version probe, validated decode, set-aside, newer schema untouched, no titles, 0600 | unit (temp dir) | `swift test --filter "LayoutStoreTests|PersistenceTests"` | ❌ W0 (LayoutStoreTests) | ⬜ pending |
| 03-08-01 | 08 | 7 | TILE-15 | T-03-19, T-03-20 | `.save(.now)` before any park; excluded apps never parked | fake + live-fixture | `swift test --filter "ArrangerDesktopTests|HotkeyTableTests"` and `caffeinate -d -i swift test --filter FocusParkIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-08-02 | 08 | 7 | TILE-09, TILE-13 | T-03-21 | Focus AX work on the app's own thread | fake + live-fixture | `swift test --filter "ArrangerFocusTests|HotkeyTableTests"` and `caffeinate -d -i swift test --filter FocusParkIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-09-01 | 09 | 8 | TILE-17 | T-03-22, T-03-23 | AX press only; no Apple Events or automation entitlement | unit + fake + live-fixture | `swift test --filter "ArrangerFinderTests|MenuPressTests|HotkeyTableTests"` and `caffeinate -d -i swift test --filter MenuPressIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-09-02 | 09 | 8 | TILE-17 | T-03-24 | Only a new Finder window before the deadline docks | fake | `swift test --filter "ArrangerFinderTests|NoticeCopyTests"` | ❌ W0 | ⬜ pending |
| 03-10-01 | 10 | 9 | TILE-09 | T-03-26 | Command items built once (no observer growth) | unit + build | `swift test --filter "CommandMenuTests|MenuCopyTests|CommandTests"` and `scripts/build-debug.sh` | ❌ W0 | ⬜ pending |
| 03-10-02 | 10 | 9 | TILE-08, TILE-04 | T-03-25, T-03-27 | Gap allow-list; paused emits no commands | unit + fake | `swift test --filter "ArrangerPauseTests|GapPreferenceTests|HotkeyTableTests|MenuCopyTests"` | ❌ W0 | ⬜ pending |
| 03-10-03 | 10 | 9 | TILE-18 | T-03-20 | Excluded windows float and are never written | fake | `swift test --filter "ArrangerExclusionTests|ExclusionScenarioTests|HotkeyTableTests"` | ❌ W0 / ✅ | ⬜ pending |
| 03-11-01 | 11 | 10 | TILE-01 | T-03-28, T-03-29 | Tap mask has no keyboard events; callback copies and returns; no AX in the tap | fake + live-fixture | `swift test --filter "DragSessionTests|ArrangerDragTests"` and `caffeinate -d -i swift test --filter InputTapIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-11-02 | 11 | 10 | TILE-01, TILE-02, TILE-11, TILE-10 | T-03-31 | Panels non-activating, click-through, sharingType .none | fake + unit | `swift test --filter "ArrangerDragTests|DragSessionTests|PreviewStyleTests"` | ❌ W0 | ⬜ pending |
| 03-11-03 | 11 | 10 | TILE-01 | T-03-30 | Tap invalidated on Accessibility revocation | unit + live-fixture | `swift test --filter MenuCopyTests` and `caffeinate -d -i swift test --filter InputTapIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-12-01 | 12 | 11 | TILE-13, TILE-14 | — | N/A | fake + live-fixture | `swift test --filter "ArrangerCommandTests|HotkeyTableTests|CommandMenuTests"` and `caffeinate -d -i swift test --filter ArrangeIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-12-02 | 12 | 11 | TILE-11, TILE-12, TILE-13, TILE-14 | T-03-33 | Unique names and chords, no reserved keys | fake + unit | `swift test --filter "ArrangerCommandTests|HotkeyTableTests|CommandMenuTests"` | ❌ W0 | ⬜ pending |
| 03-12-03 | 12 | 11 | TILE-16 | T-03-32 | Arrange All / Float All are single undo steps | fake + unit | `swift test --filter "ArrangerCommandTests|NoticeCopyTests|HotkeyTableTests"` | ❌ W0 | ⬜ pending |
| 03-13-01 | 13 | 12 | TILE-06, TILE-19 | T-03-34, T-03-35, T-03-36 | Swallow only inside cached rects, never with ⌥ or while paused | unit + fake + live-fixture | `swift test --filter "GreenButtonHitTests|ArrangerGreenButtonTests|ClassifierCorpusTests"` and `caffeinate -d -i swift test --filter ButtonFrameIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-13-02 | 13 | 12 | TILE-05 | — | N/A | fake | `swift test --filter "ArrangerResizeTests|ArrangerDragTests|DragSessionTests"` | ❌ W0 | ⬜ pending |
| 03-13-03 | 13 | 12 | TILE-05 | — | Handles never activate Pane | unit + fake | `swift test --filter "GapHandleGeometryTests|ArrangerResizeTests"` | ❌ W0 | ⬜ pending |
| 03-14-01 | 14 | 13 | SAFE-02 | T-03-38, T-03-39 | Stranded windows on-screen before any layout work; destinations clamped | unit + fake + live-fixture | `swift test --filter "RecoveryTests|ArrangerRestoreTests|NoticeCopyTests|NoticeQueueTests"` and `caffeinate -d -i swift test --filter RecoveryIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-14-02 | 14 | 13 | SAFE-02 | T-03-37 | Crash loop starts paused | unit + fake | `swift test --filter "RecoveryTests|ArrangerRestoreTests|NoticeCopyTests|ArrangerPauseTests"` | ❌ W0 | ⬜ pending |
| 03-14-03 | 14 | 13 | SAFE-03 | T-03-39 | Restore All works while paused | fake + unit | `swift test --filter "ArrangerRestoreTests|NoticeCopyTests|HotkeyTableTests"` | ❌ W0 | ⬜ pending |
| 03-15-01 | 15 | 14 | SAFE-01 | T-03-42, T-03-43 | Bounded termination writes; cleanExit only after the restore | unit + live-fixture | `swift test --filter RecoveryTests` and `caffeinate -d -i swift test --filter QuitRestoreIntegrationTests` | ❌ W0 | ⬜ pending |
| 03-15-02 | 15 | 14 | SAFE-03, TILE-15, TILE-17 | T-03-40, T-03-41 | Strict three-command parser, rate limit, silent rejection | unit + build | `swift test --filter PaneURLTests` and the `plutil -p` check on the built Debug app | ❌ W0 | ⬜ pending |
| 03-16-01 | 16 | 15 | SAFE-04, TILE-08 | T-03-44, T-03-47 | Allow-listed keys only; tests never touch the real domain | unit (injected store, test domain) | `swift test --filter "ConflictPolicyTests|WindowManagerSettingsTests|ConflictCopyTests"` | ❌ W0 | ⬜ pending |
| 03-16-02 | 16 | 15 | SAFE-04 | T-03-44, T-03-45 | Originals recorded once; restore deletes absent keys | unit | `swift test --filter "ConflictPolicyTests|NoticeCopyTests"` | ❌ W0 | ⬜ pending |
| 03-16-03 | 16 | 15 | SAFE-04 | T-03-46 | Modeless alerts, deferred during drags | unit + build | `swift test --filter "ConflictPolicyTests|ConflictCopyTests"` and `scripts/build-debug.sh` | ❌ W0 | ⬜ pending |
| 03-17-01 | 17 | 16 | TILE-10 | T-03-48, T-03-49, T-03-51 | Secure timestamp, strict codesign, no extra entitlements, designated requirement unchanged | build | `bash -n scripts/release.sh && scripts/release.sh --build-only` | ❌ W0 | ⬜ pending |
| 03-17-02 | 17 | 16 | TILE-10 | T-03-48 | Signed, verified DMG | build | `scripts/release.sh --skip-notarize && hdiutil verify build/Pane-0.3.0.dmg` | ❌ W0 | ⬜ pending |
| 03-17-03 | 17 | 16 | TILE-10 | T-03-48, T-03-50 | Notarised and stapled; credentials only in the keychain | manual (blocking checkpoint) | `spctl -a -vvv -t exec <app>` and `xcrun stapler validate build/Pane-0.3.0.dmg` after the human run | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Each plan creates its own test files in its first (RED) commit; these are the shared fixtures and tools the suites need:

- [ ] `Package.swift`: KeyboardShortcuts 3.1.0 (`exact:`) on PaneMac and PaneMacTests; `Package.resolved` committed (plan 04)
- [ ] `FakeWindowSystem`: `setFullscreen` (plan 04), current Space per display with `spaceChanged` (plan 05), `userMove` with no `frameApplied` (plan 06), `park`/`focus`/`raise` in `perform` (plan 08)
- [ ] `PaneFixtureApp` stdin commands `fullscreen <i>`, `exit-fullscreen <i>` (plan 04) and `frontmost` (plan 08); a File ▸ New Window ⌘N menu (plan 09)
- [ ] `PersistenceTests.swift` fixture helpers emit the Desktop node (plan 01)
- [ ] Temporary-directory helper for `LayoutStoreTests`, reusing the `MinimumHintsStoreTests` `Directory` pattern (plan 07)
- [ ] Injectable `PreferencesStore` and the test-only CFPreferences domain `com.eightabyte.pane.tests.windowmanager` (plan 16)
- [ ] `brew install create-dmg` and `xcrun notarytool store-credentials pane-notary` (human, plan 17 checkpoint)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Native title-bar drag reaches the tap; `event.location` is top-left (A1, A16) | TILE-01 | Needs a real drag in a real session | Plan 11 Task 1 human-check: drag TextEdit to the left edge with tap logging on |
| Drop preview states, appearance variants, Reduce Motion, capture exclusion | TILE-01, TILE-02, TILE-11 | Visual | Plan 11 Task 2 human-check |
| Tap off after Accessibility revocation; clicks keep working | TILE-01 | TCC changes need the user | Plan 11 Task 3 human-check |
| Real green-button click toggles; ⌥-click zooms natively (D-33) | TILE-06, TILE-19 | Real button clicks | Plan 13 Task 1 human-check |
| Gap-handle hover and cursor with another app frontmost (A5) | TILE-05 | Cursor behaviour of an inactive app | Plan 13 Task 3 human-check |
| ⌃⌥⌘D/F/Z and every other chord in a real session; chords disabled while the menu is open | TILE-09 | Global hotkeys need real key presses | Plans 04 Task 2, 10 Task 3, 12 Task 3 human-checks |
| VoiceOver: VO-⌘-H still works with Pane's ⌃⌥⌘ chords | TILE-09 | Assistive technology | Plan 10 Task 3 human-check; on failure apply the UI-SPEC Accessibility fallback in a gap-closure plan |
| Menu sections, Debug only with ⌥, paused glyph dimming | TILE-08 | Visual | Plan 10 Task 3 human-check |
| Real minimise and fullscreen with real apps | TILE-20, WIN-07 | Real animations and Space transitions | Plan 04 Task 3 human-check |
| Real Space switches, fullscreen Spaces, `--disable-private=Spaces` | WIN-07 | Real Spaces | Plan 05 Task 2 human-check |
| Toast styling and VoiceOver announcement | TILE-03 | Visual / assistive | Plan 06 Task 1 human-check |
| Quit and relaunch with apps running restores tiles | SAFE-06 | Real relaunch of the signed app | Plan 07 Task 1 human-check |
| Hide/show Desktop, focus neighbour with real apps | TILE-15, TILE-09 | Real activation under cooperative activation | Plan 08 Task 2 human-check |
| Finder split with real Finder (A12), Finder relaunch, no Automation prompt | TILE-17 | Real Finder and TCC | Plan 09 Task 2 human-check |
| Arrange All / Float All and every layout command with real apps | TILE-11..TILE-14, TILE-16 | Real windows | Plan 12 Task 3 human-check |
| `kill -9` recovery (N2) and a crash loop (N3); Restore All from the menu | SAFE-02, SAFE-03 | Real force-quits of the signed app | Plan 14 Tasks 1 and 3 human-checks |
| ⌘Q, `killall`, quit with a frozen app restore parked windows | SAFE-01 | Real quit paths | Plan 15 Task 1 human-check |
| `open pane-debug://…` routing, rejection and rate limit | SAFE-03, TILE-15, TILE-17 | LaunchServices | Plan 15 Task 2 human-check |
| Real Stage Manager / edge tiling / click wallpaper Turn Off and Restore (A11), alert with docking still working | SAFE-04 | Real WindowManager settings and System Settings | Plan 16 Task 3 human-check |
| Notarised 0.3.0 installs, keeps the Accessibility grant, tiles with Screen Recording denied | TILE-10 | Notary credentials and a real install | Plan 17 Task 3 checkpoint |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
