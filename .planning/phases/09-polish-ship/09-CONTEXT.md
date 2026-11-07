# Phase 9: Polish & Ship - Context

**Gathered:** 2026-11-06
**Status:** Ready for planning

<domain>
## Phase Boundary

A new user installs Transom with Homebrew, is guided through setup, and it starts at login and keeps itself updated.
Delivers SHIP-01..08: a Settings window, first-run onboarding, launch at login, a GitHub Releases updater (gifsmith
port), Developer ID signed and notarised releases in an own Homebrew tap, menu-bar view controls, Report a Problem, the
update dot, and `transom://settings?pane=`. Also carries the 08.1 / 8.1.1 D-12 collapsed-block finding and known flaky
tests. Plain macOS behaviour and simple UX throughout (user preference since 8.1.1).

</domain>

<decisions>
## Implementation Decisions

### Settings window (SHIP-01, SHIP-08)
- **D-01:** One Settings window with a toolbar of tabs across the top: General, Arranging, Zoom & Gestures, Shortcuts,
  Exclusions, Menu Bar, Updates. SwiftUI inside `NSHostingController` in an AppKit-owned window (no SwiftUI `Settings`
  scene). The existing Shortcuts window moves in as the Shortcuts tab.
- **D-02:** Gaps, New Windows and Drag to Dock stay in the menu as well; menu and Settings read and write the same
  stored value, so they never disagree.
- **D-03:** Appearance: the highlight colour follows the macOS accent colour by default, with one override colour.
  Nothing more.
- **D-04:** Opened from menu ▸ Settings… (⌘,) and `transom://settings?pane=<tab>` with lowercase tab names
  (`general`, `arranging`, `zoom`, `shortcuts`, `exclusions`, `menubar`, `updates`); an unknown pane opens General.
  Mission Control replacement lives in Settings (SHIP-01).

### Onboarding & launch at login (SHIP-02, SHIP-03)
- **D-05:** The existing setup window grows into steps: Welcome → Accessibility (required) → Screen Recording (optional,
  explains macOS re-asks monthly) → conflicting macOS features (Stage Manager, edge tiling, others found by research),
  each with a button opening the right System Settings pane → Launch at login → Done.
- **D-06:** No prompt loops: ask once, then poll for the grant; if the grant looks stale, offer the existing Reset
  permission step. Never re-prompt automatically.
- **D-07:** Launch at login (`SMAppService.mainApp`) is ticked by default on the last onboarding step; toggle in
  Settings ▸ General.
- **D-08:** App Translocation / running from Downloads or a disk image: before asking for permissions, show "Move
  Transom to Applications" with Move and Quit buttons.

### Updates & release (SHIP-04, SHIP-05, SHIP-07 dot)
- **D-09:** Port gifsmith's `internal/update` (`~/dev/gifsmith/internal/update`, `internal/services/updates.go`):
  daily check of GitHub `releases/latest` with ETag, on by default, toggle plus "Check for Updates" in Settings ▸
  Updates. A newer version shows a dot on the menu-bar icon and an "Update to X…" menu item. No macOS notification.
- **D-10:** Update action downloads the DMG, verifies its sha256 digest and the Developer ID Team ID (S2K7P43927),
  then opens it; the user drags the app in. If Transom was installed by Homebrew, the menu says to run
  `brew upgrade --cask transom` instead of downloading.
- **D-11 (user, revised 2026-11-06):** Releases are built by GitHub Actions on a version tag (`v*`), following
  gifsmith's and storcat's `release.yml`: import the Developer ID `.p12` into a temporary keychain, build the universal
  app, sign, notarise with an App Store Connect API key, build the DMG with `hdiutil` (create-dmg optional, not
  required), staple, verify, and upload to the GitHub release with its sha256. Repo secrets use gifsmith's names:
  `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8_BASE64`.
  `scripts/release.sh` stays for local dry runs (`--build-only` / `--skip-notarize`). CI keeps `swift test` on PRs and
  checks the designated requirement so TCC grants survive updates.
- **D-12:** Own tap `scottkw/homebrew-transom` (pattern of homebrew-storcat), cask modelled on Rectangle's
  (`depends_on macos: :sonoma`, uninstall quit/login_item, zap, livecheck github_latest, no `auto_updates`). First
  public version 0.9.0. homebrew/cask submission later.

### Menu bar, Report a Problem, carry-overs (SHIP-06, SHIP-07)
- **D-13:** Back, forward and saved-view controls are off by default; Settings ▸ Menu Bar has a checklist to enable and
  drag to reorder them. They appear as small status items beside the Transom icon.
- **D-14:** Saved views show as number badges 1–9; the current view is filled, others outlined; an "icon only" option
  hides the numbers.
- **D-15:** Report a Problem opens a prefilled GitHub issue (Transom version, macOS version, capability states; never
  window titles or app names) and copies the same details to the clipboard.
- **D-16:** Collapsed blocks (08.1 UAT, 8.1.1 D-12) get a label with the app icon, window title and window count so
  they do not read as minimised windows; planner/UI-spec decides the style.
- **D-17:** Fix the carried flaky tests: macOS 27 Rematch and Views live failures (pre-date 08.1.1, baseline 475030e)
  and `FreezeTestTests.itResumesByItself` (1 s deadline flakes under full-suite load).
- **D-18:** Before release, check the name "Transom" against existing macOS apps; add a macOS-beta compatibility
  checklist for the private APIs.

- **D-19 (user, 2026-11-06, after research):** The repo `scottkw/transomwm` stays private until the v0.9.0 release;
  a human checkpoint just before tagging makes it public and sets up the `release` environment, the five secrets,
  `scottkw/homebrew-transom` and `HOMEBREW_TAP_TOKEN` (RESEARCH open question 1).
- **D-20 (user, 2026-11-06):** Keep the name Transom (no Homebrew cask clash; several unrelated GitHub repos share it).
- **D-21 (2026-11-06):** CI runs tests with `--no-parallel` (shortcut: the parallel run exits early on the runner's
  Swift 6.3.3 only); find the cause or revisit when the runner has Swift 6.4 (part of D-17).

- **D-22 (user, 2026-11-07):** GitHub Actions is paused by the account spending limit on this private repo. Wait: no
  CI until the repo goes public at v0.9.0 (09-27), when macOS minutes are free. Until then the full host `swift test`
  after each plan is the gate; 09-27 runs CI (and the D-21 parallel diagnostic) once the repo is public.

### Claude's Discretion
- Exact tab contents beyond the listed settings, copy wording, icons for the view controls, and how the conflicting
  macOS features are detected.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/TransomMac/Permission/` (PermissionController, PermissionProbe, SetupView, SetupWindowController, TCCReset):
  the current permission window and reset flow to grow into onboarding.
- `Sources/TransomMac/Zoom/ShortcutsWindowController.swift`, `ShortcutsModel`: KeyboardShortcuts recorders, becomes a tab.
- Preferences: `GapPreference`, `NewWindowsPreference`, `DragToDockPreference`, `ExclusionStore`,
  `MissionControlTakeover`, `WindowManagerSettings`.
- `Shell/StatusItemController.swift` (menu-bar icon), `Shell/CommandMenu.swift`, `Shell/MenuCopy.swift`.
- `TransomEngine/TransomURL.swift` + CLI allow-list: add `settings?pane=`.
- `scripts/release.sh` (0.3.0 pipeline: Developer ID build, notarise, DMG), `xcode/project.yml`, `xcode/ci.yml`.
- Developer ID Application: Ken Scott (S2K7P43927) installed; `pane-notary` notarytool profile works; `create-dmg`
  is not installed yet (`brew install create-dmg`).

### Established Patterns
- SwiftUI only inside `NSHostingController`; Model/Engine never import AppKit (`scripts/check-no-appkit.sh`).
- Every command reachable from menu, hotkey, `transom://` and CLI (Phase 8 D-06).
- Live tests only in Tart VMs (`scripts/vm-session.sh`, `vm-live-test.sh`); never TRANSOM_LIVE on the host.

### Integration Points
- AppDelegate / TransomMacApp startup (onboarding gate, launch-at-login, update check timer).
- Status item (dot, view controls, Settings… and Report a Problem items).

</code_context>

<specifics>
## Specific Ideas

- Updater is the gifsmith design, no Sparkle.
- User prefers plain macOS behaviour and simple UX; new menu-bar controls stay off by default.

</specifics>

<deferred>
## Deferred Ideas

- Submission to homebrew/cask once the repo meets notability thresholds.

</deferred>
