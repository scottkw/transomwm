# Phase 9: Polish & Ship - Research

**Researched:** 2026-11-06
**Domain:** macOS app shipping: Settings and onboarding (AppKit + SwiftUI in `NSHostingController`), `SMAppService`, a GitHub Releases updater ported from Go to Swift, Developer ID signing and notarisation in GitHub Actions, and a Homebrew tap
**Confidence:** HIGH for the updater, signing and release pipeline (local probes and two working sibling pipelines); MEDIUM for onboarding edge cases (translocation and Screen Recording relaunch behaviour, which need VM checks)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Settings window (SHIP-01, SHIP-08)
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

#### Onboarding & launch at login (SHIP-02, SHIP-03)
- **D-05:** The existing setup window grows into steps: Welcome → Accessibility (required) → Screen Recording (optional,
  explains macOS re-asks monthly) → conflicting macOS features (Stage Manager, edge tiling, others found by research),
  each with a button opening the right System Settings pane → Launch at login → Done.
- **D-06:** No prompt loops: ask once, then poll for the grant; if the grant looks stale, offer the existing Reset
  permission step. Never re-prompt automatically.
- **D-07:** Launch at login (`SMAppService.mainApp`) is ticked by default on the last onboarding step; toggle in
  Settings ▸ General.
- **D-08:** App Translocation / running from Downloads or a disk image: before asking for permissions, show "Move
  Transom to Applications" with Move and Quit buttons.

#### Updates & release (SHIP-04, SHIP-05, SHIP-07 dot)
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

#### Menu bar, Report a Problem, carry-overs (SHIP-06, SHIP-07)
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

### Claude's Discretion
- Exact tab contents beyond the listed settings, copy wording, icons for the view controls, and how the conflicting
  macOS features are detected.

### Deferred Ideas (OUT OF SCOPE)
- Submission to homebrew/cask once the repo meets notability thresholds.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SHIP-01 | Settings window covers gaps, appearance, gestures, hotkeys, exclusions, Mission Control replacement, New Windows and Drag to Dock | Pattern 1 (Settings window), Pattern 2 (one store, observed by both the menu and Settings), Pitfall 9 (activation from a URL or CLI), and the `HighlightColor` site list in the Code Examples section |
| SHIP-02 | First-run onboarding walks through permissions and conflicting macOS features | Pattern 5 (onboarding steps as a pure function), Pattern 6 (Move to Applications), the conflicting-features findings (no new `Conflict` case), Pitfalls 5, 6 and 7 |
| SHIP-03 | User can launch Transom at login | Pattern 7 (`SMAppService` wrapper), with the four `Status` cases quoted from Apple's docs |
| SHIP-04 | Update check, notification, and a DMG verified by sha256 and Team ID before it opens | Pattern 3 (updater port), Pattern 4 (in-process verification, probed against the real 0.3.0 DMG), Pitfalls 1–4 |
| SHIP-05 | Developer ID signed, notarised, installable with `brew install --cask` | The Release pipeline and Homebrew tap sections, the committed designated requirement, Pitfalls 1 and 10–14 |
| SHIP-06 | Menu-bar back, forward and saved-view controls, chosen and reordered in Settings | Pattern 8 (status item ordering); behaviour is already fixed by UI-SPEC Surface 4 |
| SHIP-07 | "Report a Problem" and the update dot | Pattern 9 (issue URL encoding), the dot composite in the Code Examples section, quick 261106-bru's sizing rule |
| SHIP-08 | `transom://settings?pane=` opens a Settings pane | Pattern 10 (strict URL parse plus a new `Command` case, following the `toggleExcludeFrontmost` precedent) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Platform**: macOS 14+, Apple Silicon and Intel. Release builds are universal; `scripts/release.sh` already refuses a binary missing `x86_64` or `arm64`.
- **Tech stack**: Swift + SwiftPM; AppKit for overlays; SwiftUI is acceptable for Settings, but only inside `NSHostingController` (UI-SPEC platform rule). No SwiftUI `App`, `Settings` scene or `MenuBarExtra`.
- **Testability**: `TransomModel` and `TransomEngine` must not import AppKit. `scripts/check-no-appkit.sh` runs in CI. Put pure logic there: version compare, release JSON parse, the URL allow-list, onboarding step selection, install-location classification.
- **Private APIs**: each one lives in a single `TransomPrivate` file with a fallback. Phase 9 adds **no** private API. `SecTranslocateCreateOriginalPathForURL` is SPI, so don't use it (see Pattern 6).
- **Legal**: clean room. Loop (GPL-3.0) may be read, never copied. LetsMove is a reference for *behaviour* only.
- **License**: MIT.
- **Stack table**: no Sparkle (user decision; updater is the gifsmith port). `SMAppService.mainApp` for launch at login. `OSLog` subsystem `com.eightabyte.transom`. Keep `swift-tools-version: 6.2`. Don't use Swift 6.4-only syntax, because CI's `macos-26` runner has Swift 6.3.3 (verified in run 42338089975's log).
- **Code conventions**: `swift format`, camelCase, type hints, Swift Testing (`import Testing`).
- **Live tests**: only in the Tart VMs (`scripts/vm-session.sh`, `scripts/vm-live-test.sh`). Never set `TRANSOM_LIVE` on the host.
- **GSD workflow**: edits go through GSD commands. Phase end: README, push, and a PR from the feature branch (user memory).
- **Core principles**: let it crash (no `or {}` silent fallbacks), Chesterton's Fence before deleting, three examples before abstracting.
- **Ponytail**: write the smallest change that fully solves the task. No speculative abstraction (for example, no generic "updater framework").

## Summary

Phase 9 has two halves. One is app work: Settings, onboarding, the login item, view-control status items, Report a Problem, the collapsed label, and the updater's UI and state. The other is release work: version gating, the GitHub Actions release job, the Homebrew tap, and the designated-requirement check. The existing code already provides most of the app-side building blocks. `ConflictController` handles turning features off and restoring them. `PermissionController` and `SetupWindowController` handle polling and reset. `ShortcutsView` becomes the Shortcuts tab. `KeyClosableWindow` and the strict `TransomURL` allow-list are reusable as they are. `scripts/release.sh` already builds, verifies, notarises, staples and checks a universal Developer ID app and DMG.

The updater ports almost line for line from gifsmith. I ran the verification it needs **in-process** on the real `build/Transom-0.3.0.dmg`: `SecStaticCodeCheckValidity` with the requirement `anchor apple generic and certificate leaf[subject.OU] = "S2K7P43927" and notarized` returns `0`, a wrong Team ID returns `-67050`, and a byte-flipped copy returns `-67061`. Transom therefore needs no `codesign`/`spctl` subprocesses. The checks mirror gifsmith's: digest during download, then signature, Team ID and notarisation, then quarantine, then open. Use an ephemeral `URLSession` with no `URLCache`, so the ETag/304 handling stays under our control.

The biggest planning risk is outside the code: **`scottkw/transomwm` is private** (`gh api` reports `"visibility":"private"`). Unauthenticated `releases/latest` returns 404 for a private repo, so the updater would silently report "no release". The cask's download URL fails the same way, and Report a Problem's issue page can't be opened by users. The repo must be public before the 0.9.0 tag. There are also no Actions secrets or `release` environment on transomwm yet. Those values live in gifsmith's `release` environment and can't be copied by API, so a human must set them. Both items need `checkpoint:human-action` tasks.

**Primary recommendation:** Build the updater as pure `TransomEngine` logic (version, release JSON, allow-list, state machine) plus a thin `TransomMac` shell (ephemeral `URLSession`, a delegate-based download with CryptoKit SHA-256, and `SecStaticCode` verification). Make CI call the same `scripts/release.sh` the user runs locally, parameterised by notary profile and DMG name. Gate the tag on a public repo, configured secrets, and a green CI on `macos-26`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Version parse/compare, release JSON validation, download-host allow-list, update state machine | TransomEngine (pure) | — | Deterministic, headless-testable, no AppKit (CLAUDE.md testability rule) |
| `settings?pane=` parse, `SettingsPane` enum, CLI mapping | TransomEngine (`TransomURL`, `CLICommandLine`) | TransomMac (`CommandGate` → open window) | The allow-list already lives in Engine; the window lives in Mac |
| Onboarding step selection, install-location classification (translocated, DMG, Downloads, Homebrew) | TransomEngine (pure functions over paths and flags) | TransomMac (reads the real paths) | Pure inputs → steps; I/O stays in the shell |
| HTTP check, DMG download, SHA-256, `SecStaticCode`, quarantine xattr, `NSWorkspace.open` | TransomMac (`Updates/`) | — | System frameworks and file I/O |
| Settings window, tabs, onboarding window | TransomMac (AppKit window + SwiftUI in `NSHostingController`) | — | UI-SPEC platform rule |
| Launch at login | TransomMac (`SMAppService` wrapper behind a protocol) | — | System service; tests inject a fake |
| Menu-bar dot, view-control status items, menu items | TransomMac (`StatusItemController`, new `ViewControlItems`) | TransomEngine (`ViewSlot`, current-view equality) | Status items are AppKit |
| Report a Problem body | TransomMac/Shell copy types (AppKit-free `nonisolated` enums, like `MenuCopy`) | — | Reuses the Debug lines that already live in Shell copy types |
| Release build, sign, notarise, DMG, sha256 | GitHub Actions + `scripts/release.sh` | Local dry run (same script) | One pipeline, two callers |
| Homebrew cask | `scottkw/homebrew-transom` (separate repo) | transomwm Actions job (bump on publish) | Own tap (D-12) |

## Standard Stack

### Core (all system frameworks; no new package)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation `URLSession` (ephemeral config, `urlCache = nil`) | macOS 14 SDK | `releases/latest` GET with manual `If-None-Match`; DMG download | The only HTTP stack needed; ephemeral keeps Foundation from answering 304s from its own cache and writes no `~/Library/HTTPStorages` |
| CryptoKit `SHA256` (incremental `update(data:)`) | macOS 10.15+ | Digest of the downloaded DMG, streamed in 1 MiB chunks | System, constant memory, matches gifsmith's `sha256.New()` |
| Security `SecStaticCodeCreateWithPath` / `SecRequirementCreateWithString` / `SecStaticCodeCheckValidity` | system | Signature + Team ID + notarisation of the DMG | **Probed this session on the real DMG** (see Pattern 4); replaces gifsmith's `codesign`/`spctl` subprocesses |
| Darwin `setxattr` | system | `com.apple.quarantine` on the verified DMG before opening (gifsmith step) | No subprocess |
| ServiceManagement `SMAppService.mainApp` | macOS 13.0+ | Launch at login, `status`, `openSystemSettingsLoginItems()` | Already chosen in the CLAUDE.md stack table [CITED: developer.apple.com SMAppService JSON] |
| AppKit `NSTabViewController` (`tabStyle = .toolbar`) + `NSHostingController` | macOS 14 SDK | Settings window | UI-SPEC Surface 1 |
| SwiftUI Observation (`@Observable`) | macOS 14.0+ | Make `GapPreference`, `NewWindowsPreference`, `DragToDockPreference` observable without a second store | Floor is 14, so `@Observable` is available; `ExclusionStore` and `PermissionController` stay `ObservableObject` |
| KeyboardShortcuts | 3.1.0 (existing, `exact:` pin) | Shortcuts tab `Recorder` | Already in `Package.swift`; no plugins (checked `.build/checkouts/KeyboardShortcuts/Package.swift`) |

### Release tooling

| Tool | Version | Where | Notes |
|------|---------|-------|-------|
| Xcode | 26.6 default on `macos-26` (also 26.0.1–26.5) [VERIFIED: actions/runner-images macos-26-arm64-Readme.md] | CI release job | `xcode-27` image (Xcode 27.1 default, 27.2 RC) exists as **preview** [VERIFIED: runner-images issue 14404] |
| XcodeGen | 2.46.0 local [VERIFIED: `xcodegen --version`] | CI must install it: **not on the `macos-26` image** (README lists xcbeautify 3.2.1, no XcodeGen) | `brew install xcodegen` then assert `xcodegen --version` = `Version: 2.46.0` |
| notarytool / stapler / hdiutil / codesign | Xcode-bundled | CI + local | `release.sh` already handles the "notarytool exits 0 on Invalid" trap |
| create-dmg | 1.3.0 **installed locally** [VERIFIED: `create-dmg --version`] (CONTEXT said not installed: stale) | Local only; CI uses the `hdiutil` branch (D-11) | `release.sh` picks create-dmg when it's on PATH, so local and CI DMGs differ in window layout only |
| gh | 2.103.3 | Local + runner | Draft release, `--latest` publish |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-process `SecStaticCode` verification | gifsmith's `codesign --verify --strict`, `codesign -dvv` TeamIdentifier line, `spctl -a -t open --context context:primary-signature` via `Process` | Proven in gifsmith CI and works on the Transom DMG (probed: `accepted`, `source=Notarized Developer ID`). It needs a `Runner` seam and text parsing. Use it only if the in-process `notarized` requirement turns out unreliable offline (Open Question 3) |
| Delegate-based `URLSessionDownloadTask` | `URLSession.bytes(for:)` and hash while iterating | `AsyncBytes` yields one byte at a time, so a 20 MB DMG means 20M async iterations. Download-to-file and then chunked hashing is simpler and fast |
| One `release` job calling `release.sh` | gifsmith's two-job split (build with no secrets, sign on a fresh runner) | The split protects secrets from third-party build code. Transom's only dependency is KeyboardShortcuts (exact pin, `Package.resolved` revision `772133d9…`, no plugins), and xcodebuild signs during build, so splitting would mean hand-signing nested code. Keep one job, but gate it with a no-secrets `gate` job and the `release` environment's required reviewer |
| `macos-26` (Xcode 26.6, Swift 6.3.3) for the release job | `xcode-27` (Swift 6.4, matches local) | `macos-26` is GA and is what CI tests on, so what CI tested is what ships. `xcode-27` is preview (capacity and queueing caveats in issue 14404) |

**Installation:** none (no new SwiftPM package). CI adds `brew install xcodegen`.

## Package Legitimacy Audit

No external packages are added in this phase. UI-SPEC Registry Safety says "No new package and no new private API", and every library above is an Apple system framework or the existing pinned KeyboardShortcuts 3.1.0.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none new) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

**Third-party GitHub Actions:** prefer none beyond `actions/checkout`, `actions/upload-artifact`/`download-artifact` (pinned by SHA, as gifsmith does). Don't add `apple-actions/import-codesign-certs` (storcat) or `softprops/action-gh-release`. gifsmith's inline `security create-keychain …` plus `gh release create` does the same with no extra third-party code in a job holding signing secrets.

## Architecture Patterns

### System Architecture Diagram

```
                          ┌──────────────── App (TransomMac) ────────────────┐
 launch ──► Capabilities ─► InstallLocation.classify(bundlePath) ──► translocated / DMG / Downloads?
                          │        │ yes                                  │ no
                          │        ▼                                      ▼
                          │  Onboarding step 0 (Move) ──copy+strip──► /Applications/Transom.app
                          │        │ quit, wait pid, open copy           Onboarding steps 1..6 (first run)
                          │        ▼                                      │  Accessibility poll (existing reducer)
                          │     (new process)                             │  Screen Recording: 1x request, 1 s preflight poll
                          │                                               │  Conflicts: ConflictController.turnOff
                          │                                               │  Login item: SMAppService.register()
                          │                                               ▼
  menu ▸ Settings… ─┐     │                                        StatusItemController ◄── UpdateController.state
  transom://settings├──► CommandGate ─► Command.settings(pane?) ─► SettingsWindowController(tab)
  transom settings ─┘     │                                               │   (tabs bind to the same preference objects)
                          │                                               ▼
  timer (launch+10 s, 24 h) / "Check for Updates"                    Updates tab
           │                                                              │ Download and Open
           ▼                                                              ▼
  UpdateChecker ──GET releases/latest (If-None-Match)──► api.github.com   UpdateDownloader ──GET asset (≤5 redirects,
   │ 200: parse+validate (Engine)   304: reuse cached body                │   host allow-list)──► github.com → release-assets
   │ 404/draft/prerelease: "no release"                                    ▼
   ▼                                                                temp .part → size == asset.size → SHA-256 == digest
  newer? ──yes──► state .available(v) ──► dot + menu item                 ▼
                                    │ Homebrew Caskroom present?    SecStaticCode(team S2K7P43927 + notarized)
                                    └──yes──► "brew upgrade --cask"       ▼  fail → delete file, error copy
                                                                     setxattr quarantine → NSWorkspace.open(dmg)

 ┌──────────────── Release (GitHub Actions) ────────────────┐
 tag vX.Y.Z ─► gate (no secrets: tag == MARKETING_VERSION, on main, no release, notes exist)
            ─► release job [env: release, reviewer approval]
                 temp keychain ◄─ MACOS_CERT_P12_BASE64/PASSWORD; notary profile ◄─ NOTARY_KEY_*
                 scripts/release.sh  (xcodegen → xcodebuild universal → verify DR vs xcode/designated-requirement.txt
                                      → notarise+staple app → hdiutil DMG → sign → notarise+staple DMG → sha256)
                 swift test --filter UpdateRealDMG (env UPDATE_REAL_DMG) ─► gh release create --draft  DMG + .sha256
 maintainer: gh release edit vX --draft=false --latest ─► `release: published` event
            ─► tap job: compute sha256 of the published asset ─► render Casks/transom.rb ─► push scottkw/homebrew-transom
```

### Recommended Project Structure (new files only)

```
Sources/TransomEngine/
├── UpdateRelease.swift        # ParsedVersion, compare, ReleaseInfo.parse(json:current:), assetName, isAllowedDownload(url:)
├── UpdateState.swift          # UpdateStatus enum + pure transitions (idle/checking/current/available/downloading/verifying/opened)
├── SettingsPane.swift         # enum SettingsPane: String, CaseIterable { general, arranging, zoom, shortcuts, exclusions, menubar, updates }
├── OnboardingFlow.swift       # steps(firstRun:, location:, conflictsActive:, …) -> [OnboardingStep]
└── InstallLocation.swift      # classify(bundlePath:, home:) -> .applications/.translocated/.diskImage/.downloads/.other; isHomebrew(exists:)
Sources/TransomMac/
├── Settings/                  # SettingsWindowController + one SwiftUI view per tab; SettingsCopy
├── Onboarding/                # grown from Permission/SetupView + SetupWindowController; OnboardingCopy; AppMover
├── Updates/                   # UpdateController (ObservableObject, timer), GitHubReleaseClient, DMGDownloader, DMGVerifier; UpdateCopy
├── LoginItem.swift            # protocol LoginItemService { status; register(); unregister() } + SMAppService impl
├── HighlightColor.swift       # HighlightColor.current (override or controlAccentColor)
└── Shell/ViewControlItems.swift, Shell/ReportProblem.swift
scripts/release-version.sh     # tag/version/notes gate (gifsmith pattern)
xcode/designated-requirement.txt
xcode/Assets.xcassets/         # AppIcon.appiconset + TransomTemplate/TransomZoomedTemplate imagesets (from design-template/icons)
packaging/homebrew/transom.rb.template
.github/workflows/release.yml, .github/workflows/tap.yml
docs/releasing.md, docs/macos-beta-checklist.md
```

### Pattern 1: Settings window = `NSTabViewController(.toolbar)` of `NSHostingController`s
**What:** One `KeyClosableWindow` whose `contentViewController` is an `NSTabViewController` with `tabStyle = .toolbar`. Each `NSTabViewItem` holds `NSHostingController(rootView: TabView().formStyle(.grouped))`, with `sizingOptions = [.preferredContentSize]` (the `SetupWindowController` precedent).
**When:** All seven tabs. `SettingsWindowController.show(pane: SettingsPane?)` is the single entry point for the menu, URL, CLI, onboarding Done, and "Update to…".
**Notes:** The window title follows the selected tab label, and the tab switch resizes the window to the child's preferred size. Both are standard `NSTabViewController` behaviour [ASSUMED], already a UI-SPEC backstop ("VM check: `.toolbar` tab style renders the Settings look and the title follows the tab"). Persist `settings.lastPane` in `tabView(_:didSelect:)`. Map an unknown pane to `.general` in the Engine parser, not in the window.

### Pattern 2: One store, observed by both menu and Settings (D-02)
Make `GapPreference`, `NewWindowsPreference` and `DragToDockPreference` `@Observable` (macOS 14). Keep `onChange`, which `TransomMacApp.run` wires to `ArrangeController` (`gaps.onChange = { gap in Task { await arrangeController.setGap(gap) } }`, TransomMacApp.swift:70). The SwiftUI views take the same instances `StatusItemController` holds. **Do not** use `@AppStorage(GapPreference.key)` in Settings: it writes UserDefaults directly, bypasses `set(_:)` validation and `onChange`, and the menu/engine would never hear the change. `ShortcutsView` already uses `@AppStorage` only for keys read lazily (`zoomTitleBarDoubleClick`, `zoomEnabled`). Keep that only where no `onChange` exists, and route the zoom toggle through the same path as menu ▸ Turn On/Off Zoom (UI-SPEC Tab 3).

### Pattern 3: Updater port (gifsmith → Swift), split pure/impure
| gifsmith (Go) | Transom (Swift) | Tier |
|---|---|---|
| `versionRE` `^v?(0\|[1-9][0-9]{0,5})\.(0\|[1-9][0-9]{0,5})\.(0\|[1-9][0-9]{0,5})$`, `ParseVersion`, `Compare` | `UpdateVersion.parse(_:) -> (Int,Int,Int)?`, `compare` | Engine |
| `sha256RE` `^sha256:([0-9a-f]{64})$` | same regex, or a 64-hex check after a `sha256:` prefix | Engine |
| `DMGAssetName(v)` = `"Gifsmith-" + v + "-arm64.dmg"` | `"Transom-\(v)-universal.dmg"` (UI-SPEC Surface 8). **Built from the validated version, never taken from JSON** | Engine |
| `GitHubAllow`: https only, no userinfo, no `..`; `github.com` + path prefix `/<repo>/releases/download/`; exact hosts `objects.githubusercontent.com`, `release-assets.githubusercontent.com` | same, with repo `scottkw/transomwm` | Engine |
| `Checker.parse`: reject draft/prerelease/bad tag (→ not found); asset `state == "uploaded"`, `1 ≤ size ≤ MaxDMGBytes (200<<20)`, digest matches, URL allowed; else `ErrNotInstallable` | `ReleaseInfo.parse(json:)` with `JSONDecoder`, same rules; body capped at 1 MiB | Engine |
| `Checker.Latest`: headers `Accept: application/vnd.github+json`, `User-Agent`, `If-None-Match` after a 200; 304 → cached body; 404 → not found | `GitHubReleaseClient` on an **ephemeral** session with `urlCache = nil` | Mac |
| `Download`: `.part` with O_EXCL 0600, dir 0700, size must equal, SHA-256 must equal, rename; ≤5 redirects all allow-listed; progress ≤ every 100 ms | `DMGDownloader`: delegate-based `URLSessionDownloadTask` (redirect delegate refuses non-allow-listed hosts), then chunked CryptoKit hash of the temp file, then move | Mac |
| `Verify`: codesign strict, TeamIdentifier, spctl Notarized Developer ID, quarantine xattr `0081;%x;Gifsmith;` | `DMGVerifier`: `SecStaticCode` + requirement (Pattern 4), then `setxattr` `0081;<hex unix time>;Transom;` | Mac |
| `Clean`: remove own `*.dmg`/`*.dmg.part` from the updates dir only | same glob `Transom-*-universal.dmg[.part]` in `~/Library/Caches/com.eightabyte.transom/Updates` | Mac |
| `UpdateService` states `idle\|checking\|current\|available\|downloading\|verifying\|opened`; one operation at a time (`busy`); a failure restores the previous state | `UpdateStatus` enum + `UpdateController` on MainActor; automatic-check failures are logged only (UI-SPEC) | Engine + Mac |
| `RunAutoUpdates(delay, every)` with an injectable `after` | `Task` loop with an injectable `sleep: (Duration) async throws -> Void`; first check ~10 s after launch, then every 24 h, only while `updates.automatic` | Mac |

**Disable the updater** when the bundle ID is not `com.eightabyte.transom` (Debug builds are `com.eightabyte.transom.debug` [VERIFIED: xcode/project.yml:48 `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom.debug`]) or when `CFBundleShortVersionString` is missing (`swift run`). In those cases the Updates tab shows the version line and a disabled Check button. Let it crash for a *malformed* version in a Release bundle (`precondition`). It means a broken build, not a user state.

### Pattern 4: In-process DMG verification (probed)
Probe (scratch Swift tool, this session) on `build/Transom-0.3.0.dmg`:
```
team: 0          (requirement: anchor apple generic and certificate leaf[subject.OU] = "S2K7P43927")
wrongteam: -67050
notarized: 0     (requirement: notarized)
combined: 0      (… = "S2K7P43927" and notarized)
byte-flipped copy: team -67061, notarized -67061
```
The CLI equivalents confirm it: `codesign --verify -R='anchor apple generic and certificate leaf[subject.OU] = "S2K7P43927"'` succeeds and a wrong OU exits 3; `codesign --verify -R="notarized"` succeeds; `spctl -a -t open --context context:primary-signature -vv` prints `accepted` / `source=Notarized Developer ID`. Order: **digest first** (cheap, catches a swapped asset), then `SecStaticCodeCheckValidity(code, [.strictValidate, checkAllArchitectures], requirement)`, then quarantine, then open. On any failure, delete the file (UI-SPEC copy: "…so Transom deleted it. Nothing was opened.").

### Pattern 5: Onboarding as a pure step function
`OnboardingFlow.steps(firstRun: Bool, location: InstallLocation, conflictsActive: Bool) -> [Step]` returns the applicable steps (UI-SPEC: step 0 only when not in Applications; step 4 only with an active conflict; after completion, only `[.accessibility]`). The caption "Step n of total" comes from that array. The window controller keeps `onboarding.completed` and `onboarding.step` (resume after a Screen Recording "Quit & Reopen"). The Accessibility step reuses `PermissionReducer` unchanged: `PermissionController.send(.launched…)`, the 1 s poll, the probe, the reset. Screen Recording is **one** `CGRequestScreenCaptureAccess()` per click, then a 1 s `CGPreflightScreenCaptureAccess()` poll only while step 3 shows. Inject both as closures (Pitfall 5).

### Pattern 6: Move to Applications without SPI
- **Detect:** `Bundle.main.bundlePath` contains `/AppTranslocation/`, or starts with `/Volumes/`, or with `~/Downloads/` (UI-SPEC rule). Apple DTS says there is **no supported way** to find the original path of a translocated app, and `SecTranslocateCreateOriginalPathForURL` is SPI [CITED: developer.apple.com/forums/thread/728725]. Don't use it.
- **Copy:** `FileManager.copyItem(at: Bundle.main.bundleURL, to: /Applications/Transom.app)`. The translocated path is a read-only view of the original, so copying from it works [ASSUMED]. If the target exists, show the UI-SPEC "Replace…" alert, then `FileManager.trashItem` the old copy (never `removeItem`).
- **Strip quarantine on the copy** (`removexattr(… "com.apple.quarantine", XATTR_NOFOLLOW)` over the bundle's file tree). A programmatic copy keeps the quarantine attribute, and a quarantined app not moved by Finder is translocated again [ASSUMED; LetsMove's changelog records "clears the quarantine flag after copying" — CITED: github.com/MacPass/LetsMove]. The app already passed Gatekeeper to be running, so this doesn't bypass the first-launch check.
- **Relaunch:** spawn `/bin/sh -c 'while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2"' sh <pid> /Applications/Transom.app` (paths as argv, never interpolated), then `NSApp.terminate(nil)`. Waiting matters: the old instance holds the CLI `CFMessagePort` name (`CLIListener`: "False when another running instance holds the name (T-08-16)"), and LaunchServices tends to activate a running instance with the same bundle ID instead of launching a new one [ASSUMED].
- UAT backstop already listed: "VM check with a quarantined download".

### Pattern 7: Launch at login wrapper
`SMAppService.Status` cases [CITED: developer.apple.com …/smappservice/status-swift.enum.json]: `notRegistered`, `enabled`, `requiresApproval` ("registered, but the user needs to take action in System Preferences"), `notFound`. Wrap them in a protocol (`status`, `register()`, `unregister()`, `openSystemSettingsLoginItems()`) so tests never register the host's real login item. Re-read `status` each time General shows and on onboarding step 5. A `requiresApproval` result keeps the toggle on with the warning row (UI-SPEC). Map statuses to the Debug line `Login item: {enabled | not registered | needs approval | not found}`. Register only from `/Applications` (after D-08). A Debug build registers "Transom Debug" separately, which is harmless but should be noted in `docs/releasing.md`.

### Pattern 8: View-control status items
Each enabled control is its own `NSStatusItem(withLength: .squareLength)`. New status items appear to the **left** of existing ones, so recreate them right-to-left from the Settings order on every change. Don't set `autosaveName` (UI-SPEC planner note 6). Glyphs: SF Symbols `chevron.backward`, `chevron.forward`, `{n}.square` / `{n}.square.fill`, `square` / `square.fill` as templates, **at the default symbol configuration**. Quick 261106-bru found a forced 16 pt symbol clipped on a 1x display ("a forced 16 pt image measured 23 x 18 pt and lost its bottom edge", StatusItemController.swift doc comment). Refresh on the existing `arrange.onViewChanged` hook.

### Pattern 9: Report a Problem URL
Build `https://github.com/scottkw/transomwm/issues/new?body=…` with an explicit percent-encoding set: `.urlQueryAllowed` minus `+&=#`. Plain `URLComponents.queryItems` leaves `+` unescaped, and GitHub's form decoding may read it as a space [ASSUMED]. Build the body from pure inputs (versions, counts, capability lines) so the privacy unit test (UI-SPEC) can assert that fixture titles, app names and bundle IDs never appear. Open with `NSWorkspace.shared.open(url)`. Write the Details block to `NSPasteboard.general` as `.string`.

### Pattern 10: `settings` URL/CLI route
`TransomURL.parse` currently rejects every query: `parts.percentEncodedQuery == nil` is a guard condition [VERIFIED: Sources/TransomEngine/TransomURL.swift:88-90]. Add one branch **before** that guard, for host `settings` only. The path must be empty or `/`, and there must be no user, port or fragment. The query must be absent, or exactly one item named `pane`: a value in `SettingsPane.allCases` → that pane; anything else → `.general`; any other key or a second `pane` → reject. Return a new `Command.settings(SettingsPane?)` (nil = last tab). This follows the precedent of `toggleExcludeFrontmost`, a `Command` case the shell handles: `Arranger.swift:391` returns `.fault("… the shell handles it")` and `ArrangeController.refusableEffects` (ArrangeController.swift:651) intercepts it. Adding a `Command` case touches these exhaustive sites: `Arranger.swift:391` and `:926`, `MenuCopy.swift:55`, and possibly `CommandMenu`. Run `swift build` to find any others. `CLICommandLine.parse` maps `settings` / `settings <pane>` to `.send("settings")` / `.send("settings?pane=<pane>")`, well under `CLIProtocol.maxRequestBytes = 256`. More than one argument gives `CLICopy`'s "settings takes at most one argument." with exit 64 (UI-SPEC Surface 6).

### Anti-Patterns to Avoid
- **`@AppStorage` for validated preferences** (Pattern 2): it bypasses validation and `onChange`.
- **Default `URLSession.shared` for the API check**: `URLCache` may revalidate and turn a 304 into a 200 behind our back, so the ETag logic and the "304 without cached body" error branch never run [ASSUMED]. It also writes HTTP storage that the cask's `zap` would need to list.
- **Taking the asset filename or download URL host from JSON unchecked**: gifsmith builds the name from the validated version and allow-lists hosts exactly, never by suffix. Keep both.
- **Calling `SnapshotCapture.isGranted()` / `.request()` from Settings or onboarding code paths that unit tests reach** (Pitfall 5).
- **Re-prompting for Accessibility or Screen Recording on a timer**: D-06. Only a click may prompt.
- **Writing a second copy of preference state in a view model** (D-02).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Code-signature / Team ID / notarisation check | Parsing `codesign -dvv` text | `SecStaticCodeCheckValidity` + `SecRequirementCreateWithString` | Probed: exact status codes for good, wrong team and corrupted |
| SHA-256 | Any custom hashing | CryptoKit `SHA256` incremental | System, constant memory |
| Login item | LaunchAgents plist, `SMLoginItemSetEnabled`, helper app | `SMAppService.mainApp` | CLAUDE.md "What NOT to Use" |
| Finding the pre-translocation path | `SecTranslocateCreateOriginalPathForURL` via dlsym | Ask the user to move; copy from `Bundle.main.bundleURL` | SPI; DTS says unsupported |
| Hotkey recorder in Settings | Custom key capture | Existing `KeyboardShortcuts.Recorder` via `ShortcutsView` | Already built and tested (`ShortcutsModelTests`) |
| Notarisation status check in the release script | `notarytool` exit code | `grep 'status: Accepted'` (already in `release.sh`) | `notarytool submit --wait` exits 0 even for Invalid (release.sh comment; gifsmith `notarize.sh`) |
| Conflict turn-off/restore | New defaults-writing code | `ConflictController.turnOff` / `restore` | Records originals, allow-listed keys, read-back (T-03-44/45) |

**Key insight:** every security-relevant check here already exists, either in Apple's Security framework or in gifsmith's tested Go code. The port is a translation, not a design exercise.

## Conflicting macOS features (Claude's discretion: detection)

Existing coverage [VERIFIED: Sources/TransomEngine/ConflictPolicy.swift:7-9, 17-23]: `case stageManager, edgeTiling, clickWallpaper`, keys `["GloballyEnabled"]`, `["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]`, `["EnableStandardClickToShowDesktop"]`. Edge tiling is gated on macOS 15+ (`osMajor >= 15`, line 35).

Reviewed for new rows (local `defaults read com.apple.WindowManager` on macOS 27.2 shows `AppWindowGroupingBehavior`, `EnableTiledWindowMargins`, `EnableTilingOptionAccelerator`, `HideDesktop`, `StageManagerHideWidgets`, `StandardHideWidgets` besides the existing keys):

| Candidate | Moves windows by itself? | Recommendation |
|---|---|---|
| "Displays have separate Spaces" | No. Transom supports both modes (`SpacesSnapshot.separateSpaces`, OverviewLayout) | No row |
| "Automatically rearrange Spaces based on most recent use" (`com.apple.dock mru-spaces`) | No. It reorders Spaces, not windows, and Transom keys desks by Space ID | No row |
| "Hold ⌥ while dragging to tile" (`EnableTilingOptionAccelerator`) | Only with ⌥ held | Keep Phase 3 D-05: left as the user set it |
| "Tiled windows have margins" (`EnableTiledWindowMargins`) | No; affects macOS tiles only | No row |
| macOS 26/27 additions | None found that move windows automatically [ASSUMED: no source lists new auto-moving features] | No row |

**Recommendation:** don't add a `Conflict` case. The onboarding step shows the three existing rows (UI-SPEC Surface 2, discretion 6). All three live in Desktop & Dock (`x-apple.systempreferences:com.apple.Desktop-Settings.extension`, ConflictController.swift:23).

## Release pipeline (D-11) and Homebrew tap (D-12)

### Current state (verified this session)
- `scottkw/transomwm` visibility: **private**. No releases. No repo or environment secrets. No environments (`gh api …/environments` returned nothing).
- gifsmith's secrets live in the **environment** `release` (protection rules `branch_policy`, `required_reviewers`), not at repo level: `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_ID`, `NOTARY_KEY_P8_BASE64` [VERIFIED: `gh secret list --repo scottkw/gifsmith --env release`].
- `scottkw/homebrew-transom` does not exist [VERIFIED: gh repo view → "Could not resolve"]. `scottkw/homebrew-storcat` exists with `Casks/storcat.rb`.
- CI on `macos-26` currently fails: `swift test` aborts mid-run with no failing-test line (run 42338250336). `ci.yml` was just changed to `swift test --no-parallel` (in progress by the user). Release must not be tagged until CI is green.
- Local: one Developer ID Application identity; `pane-notary` profile works (`notarytool history` OK). Built Release DR:
  `designated => anchor apple generic and identifier "com.eightabyte.transom" and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = S2K7P43927)` [VERIFIED: `codesign -d -r-` on xcode/.xcode-build/Build/Products/Release/Transom.app]

### Changes to `scripts/release.sh` [VERIFIED current values: scripts/release.sh:25-31 `version=0.3.0`, `identifier=com.eightabyte.transom`, `team=S2K7P43927`, `signer="Developer ID Application: Ken Scott ($team)"`, `profile=pane-notary`, `dmg="build/Transom-$version.dmg"`]
1. Read the version from `xcode/project.yml` (`MARKETING_VERSION: "0.3.0"`, project.yml:15) instead of the hard-coded `version=0.3.0`. Bump it to `0.9.0` in the plan that cuts the release.
2. `profile="${TRANSOM_NOTARY_PROFILE:-pane-notary}"`, so CI stores its API-key credentials under its own name.
3. DMG name `build/Transom-$version-universal.dmg` (UI-SPEC Surface 8, updater asset name, cask URL). Write `$dmg.sha256` (`shasum -a 256` format) beside it.
4. Compare `codesign -d -r-` against the committed `xcode/designated-requirement.txt` exactly. Today's check is a substring `case`, which wouldn't catch an added clause.
5. Wrap staple/validate in a 5×/20 s retry. gifsmith's `stapler-retry.sh`: "On GitHub's macOS runners the ticket lookup sometimes drops (NSURLError -1005, stapler error 68)".

### `release.yml` shape (adapted from gifsmith, verified file)
- `on: push: tags: ['v[0-9]+.[0-9]+.[0-9]+']` + `workflow_dispatch` (dry run, no release). `permissions: contents: read` at the top. `concurrency: release-${{ github.ref }}`.
- **gate** job (no environment, read-only): checkout `fetch-depth: 0`; `git merge-base --is-ancestor HEAD origin/main`; `scripts/release-version.sh "$TAG"` (tag == `v` + MARKETING_VERSION, `docs/release-notes-X.Y.Z.md` exists); refuse if `gh release view "$TAG"` exists. Pass `$TAG` through `env:`, never `${{ }}` inside `run:` (storcat's comment: git allows `;` and `$` in tag names).
- **release** job (`needs: gate`, `environment: release`, `permissions: contents: write`, `runs-on: macos-26`, `timeout-minutes: 60`):
  1. First step: refuse if any release or draft for `$TAG` exists (`gh api repos/$REPO/releases --paginate`). A read-only token can't see drafts.
  2. `sudo xcode-select -s /Applications/Xcode_26.6.app` (pin; the default moves). `brew install xcodegen` + version assert.
  3. Enable Gatekeeper assessments if disabled (`spctl --status` / `sudo spctl --master-enable`; gifsmith step) so `spctl` and the `notarized` checks mean something.
  4. Keychain + notary profile step, copied from gifsmith: `security create-keychain` / `set-keychain-settings -lut 21600` / `import … -T /usr/bin/codesign` / `set-key-partition-list -S apple-tool:,apple:,codesign:` / `list-keychains -d user -s` / `default-keychain`. Then `xcrun notarytool store-credentials transom-notary --key … --key-id … --issuer … --keychain "$keychain"`. Delete the `.p12` and `.p8` immediately. Assert `security find-identity -v -p codesigning` contains `"Developer ID Application: Ken Scott (S2K7P43927)"`.
  5. `TRANSOM_NOTARY_PROFILE=transom-notary scripts/release.sh`.
  6. `security delete-keychain` before any test compiles.
  7. `UPDATE_REAL_DMG=$PWD/build/Transom-$VERSION-universal.dmg swift test --filter UpdateRealDMGTests` (env-gated test, the gifsmith `TestRealDMG` pattern: accepts the real DMG, rejects a byte-flipped copy).
  8. Push only: `gh release create "$TAG" --draft --verify-tag --title "Transom $VERSION" --notes-file docs/release-notes-$VERSION.md build/Transom-$VERSION-universal.dmg build/Transom-$VERSION-universal.dmg.sha256`.
  9. `if: always()` cleanup of the keychain and key files.
- **Publish (human):** `gh release edit vX.Y.Z --draft=false --latest`. gifsmith's `docs/releasing.md`: "Publishing from the web page alone left v1.0.1 unmarked, and `releases/latest` (which the in-app updater reads) kept returning the previous version."

### Tap bump (`tap.yml`)
- `on: release: types: [published]` + `workflow_dispatch: inputs: tag`. Publishing by the maintainer's own `gh` token fires `release: published`. Events from the default `GITHUB_TOKEN` would not (storcat's `distribute.yml` comment explains why it needed `workflow_run`; here the human publish avoids that).
- Download the published asset and compute its sha256, or read the asset's `digest` (`sha256:<hex>`, exposed by the Releases API since 2025-06-03 [CITED: github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets]). Compare with the `.sha256` asset. Render `packaging/homebrew/transom.rb.template` with `sed`. Push to `scottkw/homebrew-transom` using secret `HOMEBREW_TAP_TOKEN` (storcat's name; a fine-grained PAT with `contents: write` on that one repo).

### Cask (modelled on Rectangle's, verified from Homebrew/homebrew-cask `Casks/r/rectangle.rb`)
```ruby
cask "transom" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"

  url "https://github.com/scottkw/transomwm/releases/download/v#{version}/Transom-#{version}-universal.dmg"
  name "Transom"
  desc "Tiling window manager with nested tiles and a zoomable desk"
  homepage "https://github.com/scottkw/transomwm"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Transom.app"
  binary "#{appdir}/Transom.app/Contents/Helpers/transom"

  uninstall quit:       "com.eightabyte.transom",
            login_item: "Transom"

  zap trash: [
    "~/Library/Application Support/Transom",
    "~/Library/Caches/com.eightabyte.transom",
    "~/Library/Preferences/com.eightabyte.transom.plist",
  ]
end
```
`binary "#{appdir}/…"` inside an app bundle is documented [CITED: docs.brew.sh/Cask-Cookbook]. `CLIProtocol.appBundle(executable:)` already resolves symlinks to find the bundle. No `auto_updates`: the Cookbook says to use it when "the app has an in-app update check that downloads and installs updates". Transom's updater downloads but the user installs, and D-12 locks it off. The `livecheck` form matches storcat's working cask. Install command: `brew install --cask scottkw/transom/transom` (UI-SPEC README copy).

### Name check (D-18)
No Homebrew cask or formula named `transom` [VERIFIED: homebrew-cask `Casks/t/transom.rb` and homebrew-core `Formula/t/transom.rb` both 404]. No Mac App Store Mac app named Transom surfaced. The App Store has an iPad app "Transom Note-Taker for Writers" (Void Media) that can run on Apple silicon Macs [CITED: apps.apple.com/app/id927983947]. GitHub has several recent repos named "transom" that are macOS apps: a clipboard manager (andikanbassey/Transom), a brightness controller (domus-apps/transom), a browser-profile manager (darvid/transom), and a remote-windows tool (aydinmrnv/transom) [VERIFIED: `gh search repos transom`]. That's a naming-collision signal, not a trademark finding, so record it in the D-18 checklist for the user's decision (`checkpoint:decision`). `transomwm.app` is already registered (STATE).

### macOS-beta checklist (D-18) contents
Generate the symbol list from code, not memory. `TransomPrivate` resolves `_AXUIElementGetWindow`, `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSManagedDisplayGetCurrentSpace`, `SLSCopySpacesForWindows`, `SLSGetSpaceManagementMode`, `CGS/SLS{Get,Is,Set}SymbolicHotKey…`, `CoreDockSendNotification`, and the `MTDevice*`/`MTRegisterContactFrameCallback*` family [VERIFIED: grep of string literals in Sources/TransomPrivate]. `Capability` cases are `axWindowID`, `spaces`, `multitouch`, `symbolicHotKeys`, `coreDock`, with `--disable-private=` flags [VERIFIED: Sources/TransomPrivate/Capabilities.swift:5-10]. Checklist: on each beta, launch and read `Capabilities.logReport()` (`log show --predicate 'subsystem == "com.eightabyte.transom" AND category == "private"'`), run each capability's live suite in a Tart VM on the beta, and test the `--disable-private=<name>` fallback for any that fail.

## Common Pitfalls

### Pitfall 1: Private repo breaks every public endpoint
**What goes wrong:** the updater gets 404 from `releases/latest` and treats it as "no published release" (gifsmith `case http.StatusNotFound: return Release{}, false, nil`), so it fails **silently**. The cask URL 404s, and Report a Problem's issue page is inaccessible.
**How to avoid:** make `scottkw/transomwm` public (`checkpoint:human-action`, user decision) before tagging `v0.9.0`. Verify with `curl -s https://api.github.com/repos/scottkw/transomwm/releases/latest | grep tag_name` after publishing. Environments with required reviewers on private repos may need a paid plan [ASSUMED], which is one more reason to go public first.

### Pitfall 2: Release not marked latest
`releases/latest` keeps returning the previous tag unless the publish sets `--latest` (gifsmith lesson, quoted above). Put the exact `gh release edit … --draft=false --latest` command in `docs/releasing.md`.

### Pitfall 3: GitHub rate limit
Unauthenticated: 60 requests/hour per IP. A conditional request's 304 is free **only when authenticated** [CITED: docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api, "the request was made while correctly authorized with an Authorization header"]. One check at launch plus one per day is far below the limit. A 403/429 counts as "Couldn't check for updates" on a manual check and is silent on an automatic one. Don't add a token.

### Pitfall 4: `URLCache` hides the 304
See Anti-Patterns. Use `URLSessionConfiguration.ephemeral`, `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`, and set `If-None-Match` yourself [ASSUMED behaviour of default caching; the ephemeral setup is safe either way].

### Pitfall 5: `ZoomOffTests` counts ScreenCaptureKit touches process-wide
`SnapshotCapture.isGranted()` and `.request()` increment `SnapshotCapture.touches` [VERIFIED: Sources/TransomMac/Zoom/SnapshotCapture.swift:28-41], and `ZoomOffTests` asserts `SnapshotCapture.touches == 0, "something in this process touched ScreenCaptureKit"` [VERIFIED: Tests/TransomMacTests/ZoomOffTests.swift:21-22]. Any new unit test in `TransomMacTests` that reaches a Settings or onboarding path calling these would make that test fail depending on test order. **Avoid:** inject `screenRecordingGranted: () -> Bool` and `requestScreenRecording: () -> Bool` closures into onboarding and Settings. Production passes `SnapshotCapture.isGranted`/`request`; tests pass fakes.

### Pitfall 6: Programmatic copy keeps quarantine → translocated again
See Pattern 6. Warning sign: after Move, the new instance's `bundlePath` still contains `/AppTranslocation/` and step 0 shows again (a loop). UAT in the VM with a browser-downloaded (quarantined) DMG.

### Pitfall 7: Screen Recording grant may not show until relaunch
`CGPreflightScreenCaptureAccess()` may keep returning false in the running process after the user grants access. macOS offers "Quit & Reopen" [ASSUMED; no Apple doc found, forum reports are mixed]. UI-SPEC already handles this (Continue never blocked; `onboarding.step` resume). Don't block on the poll, and don't call `CGRequestScreenCaptureAccess()` again.

### Pitfall 8: Two Transom instances
Transom has no single-instance guard. The only effect of a second instance is that its CLI port registration fails. Two instances would both arrange windows. Move to Applications must wait for the old pid (Pattern 6). The "opened" update state tells the user to quit first (UI-SPEC copy).

### Pitfall 9: Settings won't come forward from a URL or CLI under cooperative activation
On macOS 14+, `NSApp.activate()` is a request that the frontmost app (Terminal) may not yield to [ASSUMED]. The existing pattern brings windows forward with `orderFrontRegardless()` (`PermissionController` `.bringWindowForward`). Use `NSApp.activate()` + `makeKeyAndOrderFront` + `orderFrontRegardless()` in `SettingsWindowController.show`. Check this in the UAT step that runs `open "transom://settings?pane=updates"`.

### Pitfall 10: Swift 6.3 (runner) vs 6.4 (local)
CI's `macos-26` image has Apple Swift 6.3.3; local is 6.4.2. The last four commits are 6.3 source-compat fixes (`Void` in closures, `CGFloat` tuples, a local shadowing a method). The release job builds on the runner, so new Phase 9 code must compile on 6.3. Prefer explicit types in closures and tuples. Gate the tag on green CI.

### Pitfall 11: XcodeGen missing on the runner
It isn't in the `macos-26` README, so `scripts/generate.sh` exits 2 ("xcodegen not found"). Install it and assert its version in the job.

### Pitfall 12: sha256 computed before stapling
Stapling the DMG changes its bytes. `release.sh` already prints `shasum` last, after staple and validate. Keep the `.sha256` file write at that point. The tap job hashes the **published** asset.

### Pitfall 13: Designated requirement drift breaks every user's TCC grant
A changed identifier, team, or certificate type makes macOS treat the update as a different app, so Accessibility is lost (PITFALLS.md Pitfall on TCC). Compare against the committed `xcode/designated-requirement.txt` (exact string above) in `release.sh`, which runs locally and in CI. PR CI can't sign (no secrets on PRs), so the check lives in the release path. Add a cheap PR-time guard: `project.yml` still has `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom`, `DEVELOPMENT_TEAM: S2K7P43927` and `CODE_SIGN_IDENTITY: "Developer ID Application"` (grep in CI).

### Pitfall 14: Gatekeeper assessment disabled on runners
gifsmith found `spctl` assessments may be disabled on runners and enables them (`sudo spctl --master-enable`). Without that, the `spctl` line in `release.sh` doesn't prove notarisation.

### Pitfall 15: `FreezeTestTests.itResumesByItself` flake (D-17)
The test sleeps-polls for up to 1 s for a 50 ms resume task [VERIFIED: Tests/TransomMacTests/FreezeTestTests.swift:52-62]. Under full-suite load the MainActor task can start after the deadline. **Fix:** make the resume task observable, e.g. `private(set) var resumeTask: Task<Void, Never>?` (internal), and have the test `await freeze.resumeTask?.value` instead of polling a wall-clock deadline. Deterministic, no product change.

### Pitfall 16: macOS 27 live failures (D-17)
Known since 08.1: `ViewsIntegrationTests.aViewOnAnotherSpaceSwitchesFirst` and `RematchIntegrationTests.aPlaceholderIsClickThroughAndBehindRealWindows` fail on 27.2 and pass on 15.7 ("suspected test setup", 08.1-07-PLAN). 08.1.1-18 deferred four more 27.2 failures: TabGroup close confirmation, OverviewSpaceSwitch ×3, TabStripSpace, Overview helper exit. Research can't settle these from the host. Plan a VM diagnosis task per test (`TRANSOM_VM=pane-test-27 scripts/vm-session.sh …`, one suite per run) with the rule that only test-setup fixes are in scope. A product failure becomes a deviation.

### Pitfall 17: No macOS 14 test target
The floor is macOS 14. GitHub's macOS 14 images were "fully unsupported by November 2nd" [VERIFIED: runner-images announcement], and the local Tart VMs are 15.7 (`pane-test`) and 27.2 (`pane-test-27`). The `.toolbar` tab style, `@Observable`, and `SMAppService` are all 13–14 APIs, so the risk is low, but nothing has run on 14. See Open Question 2.

## Code Examples

### Release JSON → release info (Engine; mirrors gifsmith `parse`)
```swift
// Source: port of ~/dev/gifsmith/internal/update/update.go:160-197 (read this session)
public struct UpdateRelease: Equatable, Sendable {
    public let version: String            // without the leading v
    public let assetName: String          // "Transom-\(version)-universal.dmg", built, never read from JSON
    public let url: URL
    public let size: Int64
    public let sha256: String             // lowercase hex
}
public enum UpdateCheck: Equatable, Sendable { case none, notInstallable(version: String), release(UpdateRelease) }

public enum UpdateFeed {
    public static let repo = "scottkw/transomwm"
    public static let teamID = "S2K7P43927"
    public static let maxDMGBytes: Int64 = 200 << 20
    public static let maxJSONBytes = 1 << 20
    public static func assetName(_ v: String) -> String { "Transom-\(v)-universal.dmg" }

    private struct Raw: Decodable {
        let tag_name: String; let draft: Bool; let prerelease: Bool
        struct Asset: Decodable { let name: String; let size: Int64; let state: String; let browser_download_url: String; let digest: String? }
        let assets: [Asset]
    }

    public static func parse(_ body: Data) throws -> UpdateCheck {
        let raw = try JSONDecoder().decode(Raw.self, from: body)
        guard !raw.draft, !raw.prerelease, UpdateVersion.parse(raw.tag_name) != nil else { return .none }
        let version = raw.tag_name.hasPrefix("v") ? String(raw.tag_name.dropFirst()) : raw.tag_name
        let name = assetName(version)
        guard let a = raw.assets.first(where: { $0.name == name }), a.state == "uploaded",
              (1...maxDMGBytes).contains(a.size), let hex = a.digest.flatMap(sha256Hex),
              let url = URL(string: a.browser_download_url), isAllowedDownload(url)
        else { return .notInstallable(version: version) }
        return .release(UpdateRelease(version: version, assetName: name, url: url, size: a.size, sha256: hex))
    }
}
```

### DMG verification (Mac; probed this session)
```swift
// Source: Security framework; requirement strings probed on build/Transom-0.3.0.dmg (status 0 / -67050 / -67061)
import Security
enum DMGVerifier {
    static let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"S2K7P43927\" and notarized"
    /// errSecSuccess or the Security status; never throws, so the caller maps any non-zero to "didn't pass".
    nonisolated static func check(_ url: URL) -> OSStatus {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else { return status }
        var req: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &req)
        guard status == errSecSuccess, let req else { return status }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), req)
    }
}
```

### Streaming SHA-256 of the downloaded file
```swift
// Source: CryptoKit SHA256 incremental API [ASSUMED API shape; standard since macOS 10.15]
import CryptoKit
nonisolated func sha256Hex(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
```

### Quarantine like a browser download (gifsmith `Verify` last step)
```swift
// Source: ~/dev/gifsmith/internal/update/install.go:140 `flag := fmt.Sprintf("0081;%x;Gifsmith;", now.Unix())`
let value = String(format: "0081;%llx;Transom;", UInt64(Date().timeIntervalSince1970))
let ok = value.withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, 0) } == 0
```

### Update dot composite (UI-SPEC Surface 3: 6 pt dot at (15,3), 1 pt knock-out, template)
```swift
// Source: UI-SPEC planner note 7; AppKit drawing handler [ASSUMED API usage]
func withUpdateDot(_ glyph: NSImage) -> NSImage {
    let canvas = NSSize(width: 18, height: 18)
    let image = NSImage(size: canvas, flipped: true) { rect in
        glyph.draw(in: NSRect(x: (18 - glyph.size.width) / 2, y: (18 - glyph.size.height) / 2,
                              width: glyph.size.width, height: glyph.size.height))
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 11, y: -1, width: 8, height: 8)).fill()   // 8 pt clear, centre (15,3)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 12, y: 0, width: 6, height: 6)).fill()    // 6 pt dot, centre (15,3)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = glyph.accessibilityDescription
    return image
}
```
Check on a 1x display (the DELL) as quick 261106-bru did: the composite must stay at 18 × 18 pt or smaller.

### `HighlightColor` sites to switch (UI-SPEC planner note 3)
`NSColor.controlAccentColor` appears at exactly four places [VERIFIED: grep this session]: `Zoom/StagePanel.swift:267`, `Zoom/CollapsedPanels.swift:78`, `Overlay/GapHandlePanels.swift:37`, `Overlay/PreviewPanel.swift:492` (`case .accent: .controlAccentColor`, the `PreviewStyle.ColorRole.accent` resolver that covers every drop and result preview).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SMLoginItemSetEnabled` / helper login apps | `SMAppService.mainApp` | macOS 13 | Three calls; the `requiresApproval` state must be shown |
| Downloading the asset to compute sha256 | Releases API `digest` field (`sha256:…`) | 2025-06-03 | The updater trusts the API digest + signature; the tap job can read it too |
| `--no-quarantine` casks | Gatekeeper must pass (Homebrew 5) | 2025–2026 | Notarised + stapled DMG required (STACK.md) |
| `codesign`/`spctl` subprocess checks | `SecStaticCode` + requirement including `notarized` | long-standing; probed here | No subprocess or text parsing in the app |

**Deprecated/outdated in this repo:**
- `release.sh`'s hard-coded `version=0.3.0` and DMG name `Transom-$version.dmg`: superseded by MARKETING_VERSION and `Transom-$version-universal.dmg`.
- CONTEXT's "`create-dmg` is not installed yet": it is installed now (1.3.0). CI still uses `hdiutil` per D-11.
- CONTEXT lists `xcode/ci.yml`, which does not exist. CI is `.github/workflows/ci.yml`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Copying from the translocated `Bundle.main.bundleURL` yields a complete, valid bundle | Pattern 6 | Move step fails; fallback copy already says "drag it yourself". VM UAT backstop exists |
| A2 | A programmatic copy keeps quarantine and would be translocated again unless stripped | Pattern 6, Pitfall 6 | Without stripping: relaunch loop at step 0. With stripping when unneeded: harmless |
| A3 | LaunchServices activates a running same-bundle-ID instance instead of launching the new path | Pattern 6, Pitfall 8 | If wrong, waiting for the pid is just a short delay |
| A4 | Default `URLSession` caching can turn 304 into 200 transparently | Pitfall 4 | None: the ephemeral, no-cache setup is correct either way |
| A5 | `NSTabViewController(.toolbar)` propagates the tab title and resizes per child `preferredContentSize` | Pattern 1 | Manual title and size handling in `tabView(_:didSelect:)`; UI-SPEC VM backstop |
| A6 | `CGPreflightScreenCaptureAccess` may need a relaunch after a grant | Pitfall 7 | UI-SPEC already never blocks; low |
| A7 | Cooperative activation can keep Settings behind Terminal for URL/CLI opens | Pitfall 9 | Cosmetic; `orderFrontRegardless` mitigates |
| A8 | `+` in a GitHub `?body=` is read as a space unless encoded | Pattern 9 | Garbled issue text; unit test on the encoder |
| A9 | Environments with required reviewers need a paid plan on private repos | Pitfall 1 | Only matters if the repo stays private, which already blocks release |
| A10 | No macOS 26/27 feature beyond the three conflicts moves windows by itself | Conflicting features | A missed conflict would show only as a UAT finding; the recipe for adding a row is fixed in UI-SPEC |
| A11 | The `notarized` requirement in `SecStaticCodeCheckValidity` passes offline for a stapled DMG | Pattern 4 | If it needs a network lookup, an offline user gets a verify failure. The DMG is downloaded online, so low risk; Open Question 3 |
| A12 | CryptoKit `SHA256` incremental API and the `NSImage(size:flipped:drawingHandler:)` usage as sketched | Code Examples | Compile errors caught at once |

## Open Questions (RESOLVED)

1. **When does the repo go public, and who sets the secrets?**
   - What we know: the repo is private; the five secret names are fixed (D-11); gifsmith's values can't be copied by API.
   - Recommendation: one `checkpoint:human-action` before the release plan. Make the repo public, create environment `release` (required reviewer `scottkw`, deployment refs `main` + `v*`), set the five secrets there (`base64 -i cert.p12 | gh secret set MACOS_CERT_P12_BASE64 --env release --repo scottkw/transomwm`), create `scottkw/homebrew-transom`, add `HOMEBREW_TAP_TOKEN`, and add the tag ruleset (gifsmith "Release tags: maintainer only"). Then run a `workflow_dispatch` dry run.
   - **RESOLVED (D-19):** the repo stays private until the v0.9.0 release; 09-27 is the human checkpoint that makes it public and sets up the `release` environment, five secrets, tap and `HOMEBREW_TAP_TOKEN`.
2. **macOS 14 coverage.**
   - What we know: no macOS 14 runner and no 14 VM.
   - Recommendation: optional UAT item. Pull `ghcr.io/cirruslabs/macos-sonoma-vanilla` into Tart for one smoke run (install the DMG, onboarding, Settings), or accept the risk explicitly at verify time.
   - **RESOLVED:** no macOS 14 VM for 0.9.0. The floor is claimed from the deployment target and the APIs' availability (all ≤14.0, checked in research); the risk is accepted and stated in the release notes. A Sonoma Tart smoke run is optional, not in this phase.
3. **Does the in-process `notarized` requirement work offline?**
   - What we know: it passes online on a stapled DMG.
   - Recommendation: the release job's env-gated `UpdateRealDMGTests` runs online. Add a VM UAT with networking off after download, or drop `and notarized` and keep only the team requirement plus Gatekeeper at first launch (quarantine is set).
   - **RESOLVED:** keep `and notarized` (09-13). The check runs immediately after the download, so the Mac is online whenever it runs; offline there is no download to verify. A failure fails closed (nothing is opened).
4. **Release job runner: `macos-26` or `xcode-27`?**
   - Recommendation: `macos-26` (GA, matches PR CI). Revisit when `xcode-27` leaves preview.
   - **RESOLVED:** `macos-26` (09-15), matching PR CI.
5. **Build number.** `CURRENT_PROJECT_VERSION: "1"` (project.yml:16) is shown in "Transom {version} ({build})".
   - Recommendation: leave it manual (bump with the version) unless the user wants `GITHUB_RUN_NUMBER`. It doesn't affect the DR.
   - **RESOLVED:** manual, bumped with the version (09-26 sets `CURRENT_PROJECT_VERSION: "2"` for 0.9.0).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / Swift (local) | builds, tests | ✓ | Xcode 27.2, Swift 6.4.2 | — |
| XcodeGen (local) | `generate.sh` | ✓ | 2.46.0 | — |
| XcodeGen (runner) | release job | ✗ on `macos-26` image | — | `brew install xcodegen` |
| create-dmg | local DMG layout | ✓ | 1.3.0 | `hdiutil` branch (CI) |
| xcbeautify (local) | log readability | ✗ | — | `build-debug.sh` already falls back to raw output |
| Developer ID Application identity | signing | ✓ (1 identity) | S2K7P43927 | — |
| notarytool profile `pane-notary` | local notarise | ✓ | — | — |
| Tart + VMs | live tests, UAT | ✓ | tart 2.40.1; `pane-test` (15.7), `pane-test-27` (27.2) | no macOS 14 VM (Open Q 2) |
| gh CLI | releases, secrets | ✓ | 2.103.3 | — |
| Homebrew | tap install UAT | ✓ | 7.0.12 | — |
| GitHub repo public | updater, cask, issues | ✗ (private) | — | **none: blocking for release** |
| `release` environment + 5 secrets on transomwm | release job | ✗ | — | **none: human action** |
| `scottkw/homebrew-transom` + `HOMEBREW_TAP_TOKEN` | tap bump | ✗ | — | manual cask commit for 0.9.0 |
| Green CI on `macos-26` | tag gate | ✗ (aborts mid `swift test`) | Swift 6.3.3 | user is fixing (`--no-parallel`) |

**Missing dependencies with no fallback:** public repo; `release` environment + secrets; green CI. All are human or ongoing, so the release plan must sit behind checkpoints.
**Missing with fallback:** XcodeGen on the runner (install it); the tap repo (a manual first commit is possible).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) via SwiftPM, 4 test targets (Model, Engine, Mac, MacIntegration) |
| Config file | `Package.swift` (no separate config) |
| Quick run command | `swift test --filter <SuiteName>` (e.g. `swift test --filter TransomURLTests`) |
| Full suite command | `swift test --no-parallel` (matches the updated `ci.yml`), then `swift build -c release && swift test -c release -Xswiftc -enable-testing` |
| Live suites | VM only: `TRANSOM_VM=pane-test-27 scripts/vm-session.sh scripts/vm-live-test.sh <Suite>` (never `TRANSOM_LIVE` on the host) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SHIP-01 | Each preference written from Settings fires the same `onChange` as the menu; tab list and order | unit | `swift test --filter SettingsModelTests` | ❌ Wave 0 |
| SHIP-01 | `HighlightColor.current`: override parse (`#RRGGBB`), invalid value removed, system default | unit | `swift test --filter HighlightColorTests` | ❌ Wave 0 |
| SHIP-02 | `OnboardingFlow.steps` for first run, translocated, DMG, Downloads, conflicts none/some, post-completion | unit | `swift test --filter OnboardingFlowTests` | ❌ Wave 0 |
| SHIP-02 | `InstallLocation.classify` and `isHomebrew` | unit | `swift test --filter InstallLocationTests` | ❌ Wave 0 |
| SHIP-02 | Screen Recording requested at most once per click (fake closures count calls) | unit | `swift test --filter OnboardingControllerTests` | ❌ Wave 0 |
| SHIP-03 | Login item toggle maps each `Status` to UI state; register error leaves it off (fake service) | unit | `swift test --filter LoginItemTests` | ❌ Wave 0 |
| SHIP-03 | Starts at next login | manual | VM UAT: enable, log out and in (or reboot), Transom running | manual-only |
| SHIP-04 | Version parse/compare (gifsmith `update_test.go` cases ported) | unit | `swift test --filter UpdateVersionTests` | ❌ Wave 0 |
| SHIP-04 | Release JSON: draft, prerelease, bad tag, missing asset, bad digest, oversize, disallowed host | unit | `swift test --filter UpdateFeedTests` | ❌ Wave 0 |
| SHIP-04 | State machine: busy guard, failure restores previous, available → dot | unit | `swift test --filter UpdateStateTests` | ❌ Wave 0 |
| SHIP-04 | Real DMG accepted, byte-flipped rejected | env-gated | `UPDATE_REAL_DMG=build/Transom-0.9.0-universal.dmg swift test --filter UpdateRealDMGTests` | ❌ Wave 0 |
| SHIP-05 | DR equals committed file; universal; notarised; stapled | script | `scripts/release.sh --skip-notarize` (local), full in CI | ✅ (extend) |
| SHIP-05 | `brew install --cask scottkw/transom/transom` opens with no Gatekeeper warning | manual | VM UAT after first publish | manual-only |
| SHIP-06 | View-control order → status-item creation order; current slot filled; icon only | unit | `swift test --filter ViewControlItemsTests` | ❌ Wave 0 |
| SHIP-07 | Report body contains versions, never fixture titles, app names or bundle IDs; URL encoding of `+&=#` | unit | `swift test --filter ReportProblemTests` | ❌ Wave 0 |
| SHIP-08 | `settings`, `?pane=` each value, bad pane → general, extra key/second pane/path/fragment rejected; CLI `settings [pane]`, >1 arg exit 64; help line ≤ 72 columns | unit | `swift test --filter TransomURLTests` / `CLICommandLineTests` / `CLICopyTests` | ✅ (extend) |
| D-16 | Collapsed label fit: full / line 1 / icon only | unit | `swift test --filter CollapsedLabelTests` | ❌ Wave 0 |
| D-17 | `itResumesByItself` deterministic | unit | `swift test --filter FreezeTestTests` (run 20× in a loop) | ✅ (fix) |

### Sampling Rate
- **Per task commit:** the touched suite's `swift test --filter …`, plus `scripts/check-no-appkit.sh` when Engine changes.
- **Per wave merge:** `swift test --no-parallel`.
- **Phase gate:** full suite green on the host **and** green on GitHub `macos-26` CI before `/gsd-verify-work`. Release dry run (`workflow_dispatch`) green before the `v0.9.0` tag.

### Wave 0 Gaps
- [ ] Engine tests: `UpdateVersionTests`, `UpdateFeedTests`, `UpdateStateTests`, `OnboardingFlowTests`, `InstallLocationTests`, `SettingsPane` cases in `TransomURLTests`
- [ ] Mac tests: `SettingsModelTests`, `HighlightColorTests`, `LoginItemTests`, `OnboardingControllerTests`, `ViewControlItemsTests`, `ReportProblemTests`, `CollapsedLabelTests`, `UpdateRealDMGTests` (env-gated, skipped by default)
- [ ] Test fixtures: one real `releases/latest` JSON (from gifsmith's shape, re-cut for Transom names) under `Tests/TransomEngineTests/Fixtures/`
- [ ] No framework install needed

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No user accounts; the updater sends no credentials |
| V3 Session Management | no | — |
| V4 Access Control | yes (CI) | `release` environment with required reviewer; tag ruleset; secrets only in the release job; fine-grained tap PAT scoped to one repo |
| V5 Input Validation | yes | Strict `transom://settings` parse (one `pane` key, allow-listed values); release JSON size cap 1 MiB, version regex, asset name built from version, size bounds, digest regex; UserDefaults values validated (`appearance.highlight`, `menuBar.items`) as `GapPreference` does |
| V6 Cryptography | yes | CryptoKit SHA-256; Security framework code-signing validation. Never hand-roll |
| V10 Malicious Code / V14 Config | yes | Hardened runtime, forbidden entitlements check (`release.sh`), DR pinned to a committed file, pinned actions by SHA, no third-party actions in the signing job |
| V12 Files | yes | Download into an app-owned cache dir (0700) via `.part` (0600), `basename` check on the asset name, own-glob-only cleanup, trash (not delete) on Replace |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered or swapped DMG (MITM, compromised CDN) | Tampering | HTTPS + exact host allow-list on every redirect + size == asset size + SHA-256 == API digest + `SecStaticCode` team + notarized requirement; delete on any failure |
| Malicious release JSON (huge, path traversal in name, foreign URL) | Tampering / DoS | 1 MiB cap; name built from the validated version; URL host and path allow-list |
| Hostile `transom://settings?…` from a web page | Spoofing / DoS | Strict parse, no free text reaches UI, existing 1/s rate limit; opening Settings is the only effect |
| Report a Problem leaking window titles or app names | Information disclosure | Body built only from versions, counts and capability lines; privacy unit test with fixture titles |
| Signing secrets exfiltrated in CI | Elevation / Disclosure | Environment + reviewer, keychain deleted before tests compile, `.p12`/`.p8` removed immediately, `persist-credentials: false`, tag passed via `env:` |
| Move-to-Applications command injection | Tampering | `/bin/sh -c '…' sh <pid> <path>` with argv, no string interpolation; Replace moves to Trash |
| Stripping quarantine from arbitrary files | Elevation | Only on Transom's own fresh copy, after this process passed Gatekeeper |
| Stale conflict writes | Tampering | Existing allow-listed keys and originals (T-03-44/45) unchanged |

## Sources

### Primary (HIGH confidence)
- Local code read this session: `Sources/TransomEngine/{TransomURL,ConflictPolicy,Command,CLICommandLine,CLIProtocol}.swift`, `Sources/TransomMac/{ConflictController,TransomMacApp,AppDelegate,CommandGate,CLIListener,GapPreference,ExclusionStore,WindowManagerSettings}.swift`, `Permission/*`, `Shell/{StatusItemController,ConflictCopy,FreezeTest}.swift`, `Zoom/{ShortcutsWindowController,SnapshotCapture}.swift`, `xcode/project.yml`, `scripts/{release,build-debug,generate}.sh`, `.github/workflows/ci.yml`, `Tests/TransomMacTests/{ZoomOffTests,FreezeTestTests}.swift`
- gifsmith: `internal/update/{update,install,real_darwin_test}.go`, `internal/services/updates.go`, `.github/workflows/release.yml`, `docs/releasing.md`, `scripts/{stapler-retry,verify-release,notarize,release-version}.sh`
- storcat: `.github/workflows/{release,distribute}.yml`, `packaging/homebrew/storcat.rb.template`; `scottkw/homebrew-storcat` `Casks/storcat.rb`
- Homebrew/homebrew-cask `Casks/r/rectangle.rb` (via gh api)
- actions/runner-images `macos-26-arm64-Readme.md`, `xcode-27-arm64-Readme.md`, issue 14404
- Local probes: `codesign -d -r-` (DR), `SecStaticCodeCheckValidity` on `build/Transom-0.3.0.dmg` (0 / -67050 / -67061), `codesign --verify -R`, `spctl -a -t open`, `defaults read com.apple.WindowManager`, `gh api` visibility/secrets/environments
- Apple: developer.apple.com tutorials JSON for `SMAppService` and `SMAppService.Status`

### Secondary (MEDIUM confidence)
- https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api (conditional requests and rate limit)
- https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/ (asset `digest`)
- https://docs.brew.sh/Cask-Cookbook (`binary` in app bundle, `auto_updates`, `zap trash:`)
- https://developer.apple.com/forums/thread/728725 (no supported original-path API for translocation)
- https://github.com/MacPass/LetsMove (clears quarantine after copying)

### Tertiary (LOW confidence)
- Screen Recording relaunch reports: https://github.com/CapSoftware/Cap/issues/1722, https://developer.apple.com/forums/thread/818415
- App Store name search: https://apps.apple.com/app/id927983947

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. System frameworks only; verification probed on the real artefact.
- Updater port: HIGH. Line-by-line source is available, and its CI patterns are proven.
- Release pipeline: HIGH for the steps (two working sibling pipelines plus the existing `release.sh`); MEDIUM for runner specifics (Gatekeeper, stapler flakiness), which are already mitigated in gifsmith.
- Onboarding (translocation, Screen Recording relaunch): MEDIUM. Behaviour is assumed and backed by VM UAT backstops.
- Pitfalls: HIGH for the repo-visibility, ZoomOff counter, DR and Swift 6.3 items (verified); MEDIUM elsewhere.

**Research date:** 2026-11-06
**Valid until:** 2026-12-06 (runner images and Xcode defaults move monthly; re-check `macos-26` Xcode default before the tag)
