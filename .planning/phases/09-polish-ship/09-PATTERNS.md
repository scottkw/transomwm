# Phase 9: Polish & Ship - Pattern Map

**Mapped:** 2026-11-06
**Files analyzed:** 38 (new + modified)
**Analogs found:** 33 / 38

All analog paths below are git-tracked in this repo. gifsmith paths (`~/dev/gifsmith/...`) are an external sibling repo, cited only as the port source mandated by D-09/D-11 (read and translate; it is MIT and the user's own code).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Sources/TransomEngine/SettingsPane.swift` (new) | model (enum) | transform | `Sources/TransomEngine/ConflictPolicy.swift` (`Conflict: String, CaseIterable`) | exact |
| `Sources/TransomEngine/TransomURL.swift` (mod: `settings?pane=`) | utility (parser) | request-response | itself, lines 85-107 | exact |
| `Sources/TransomEngine/Command.swift` (mod: `.settings(SettingsPane?)`) | model | — | `case toggleExcludeFrontmost` (line 15) | exact |
| `Sources/TransomEngine/Arranger.swift` (mod: :391, :890, :926) | service | — | `toggleExcludeFrontmost` handling | exact |
| `Sources/TransomEngine/CLICommandLine.swift` (mod) | utility (parser) | transform | itself, lines 13-18 (`view`/`save-view` arg branch) | exact |
| `Sources/TransomEngine/CLICopy.swift` (mod) | copy | — | `takesNoArgument` (line 18) | exact |
| `Sources/TransomEngine/UpdateRelease.swift` (new) | model + parser | transform | `ConflictPolicy.swift` (pure enum of statics) + gifsmith `internal/update/update.go` | role-match |
| `Sources/TransomEngine/UpdateState.swift` (new) | reducer | event-driven | `Sources/TransomEngine/PermissionReducer.swift` | role-match |
| `Sources/TransomEngine/OnboardingFlow.swift` (new) | pure function | transform | `ConflictPolicy.active(values:osMajor:)` | role-match |
| `Sources/TransomEngine/InstallLocation.swift` (new) | pure function | transform | `ConflictPolicy` | role-match |
| `Sources/TransomMac/Settings/SettingsWindowController.swift` (new) | controller (window) | request-response | `Sources/TransomMac/Zoom/ShortcutsWindowController.swift` lines 100-124 + `Permission/SetupWindowController.swift` 40-65 | exact |
| `Sources/TransomMac/Settings/*TabView.swift` (7 new SwiftUI views) | component | CRUD (prefs) | `ShortcutsView` (ShortcutsWindowController.swift 59-98) | exact |
| `Sources/TransomMac/Settings/SettingsCopy.swift` (new) | copy | — | `Sources/TransomMac/Shell/MenuCopy.swift` | exact |
| `Sources/TransomMac/GapPreference.swift`, `NewWindowsPreference.swift`, `DragToDockPreference.swift` (mod: `@Observable`) | store | CRUD | `GapPreference.swift` itself | exact |
| `Sources/TransomMac/HighlightColor.swift` (new) | store/utility | CRUD | `GapPreference.swift` (validated UserDefaults + log-and-replace) | role-match |
| 4 accent sites (StagePanel:267, CollapsedPanels:78, GapHandlePanels:37, PreviewPanel:492) (mod) | component | — | — (swap `NSColor.controlAccentColor` → `HighlightColor.current`) | n/a |
| `Sources/TransomMac/Onboarding/*` (grown from `Permission/SetupView.swift`, `SetupWindowController.swift`) | controller + component | event-driven (poll) | `Permission/SetupWindowController.swift`, `PermissionController.swift` 50-70 | exact |
| `Sources/TransomMac/Onboarding/OnboardingCopy.swift` (new) | copy | — | `MenuCopy.swift` / `Shell/ConflictCopy.swift` | exact |
| `Sources/TransomMac/Onboarding/AppMover.swift` (new) | service | file-I/O + process | `Permission/TCCReset.swift` (Process launch) | role-match |
| `Sources/TransomMac/LoginItem.swift` (new) | service (protocol + impl) | request-response | `TCCReset` (static seam) / `GapPreference(defaults:)` (injection) | partial |
| `Sources/TransomMac/Updates/UpdateController.swift` (new) | controller (ObservableObject) | event-driven + timer | `Permission/PermissionController.swift` (`@Published state`, `pollTask` loop) | exact |
| `Sources/TransomMac/Updates/GitHubReleaseClient.swift` (new) | service | request-response (HTTP) | — | none |
| `Sources/TransomMac/Updates/DMGDownloader.swift`, `DMGVerifier.swift` (new) | service | file-I/O + streaming | — (RESEARCH Code Examples) | none |
| `Sources/TransomMac/Updates/UpdateCopy.swift` (new) | copy | — | `MenuCopy.swift` | exact |
| `Sources/TransomMac/Shell/StatusItemController.swift` (mod: dot, Settings…, Report, update items, remove Shortcuts…/Replace MC) | controller | event-driven | itself (`updateGlyph` 264-277, `gapsMenuItem` 215-232) | exact |
| `Sources/TransomMac/Shell/ViewControlItems.swift` (new) | controller (status items) | event-driven | `StatusItemController.swift` lines 26, 66-70, 264-277 | exact |
| `Sources/TransomMac/Shell/ReportProblem.swift` (new) | utility (pure body builder) | transform | `MenuCopy.swift` (nonisolated enum) | role-match |
| `Sources/TransomMac/Shell/MenuCopy.swift`, `ViewCopy.swift`, `TabCopy.swift` (mod) | copy | — | themselves | exact |
| `Sources/TransomMac/ArrangeController.swift` (mod :651 intercept `.settings`) | controller | request-response | `toggleExcludeFrontmost` branch lines 650-654 | exact |
| `Sources/TransomMac/Zoom/CollapsedPanels.swift` (mod: label card, D-16) | component (layer view) | — | itself (`CollapsedBlockView`, lines 15-80) + `TileLayer` capsule | exact |
| `Sources/TransomMac/Shell/FreezeTest.swift` (mod: expose `resumeTask`) | service | — | itself line 18 | exact |
| `Sources/TransomMac/TransomMacApp.swift` (mod: wiring) | config/bootstrap | — | itself lines 39-91 | exact |
| `Tests/TransomEngineTests/{SettingsPane,UpdateVersion,UpdateFeed,UpdateState,OnboardingFlow,InstallLocation}Tests.swift` | test | — | `Tests/TransomEngineTests/ConflictPolicyTests.swift`, `TransomURLTests.swift` | exact |
| `Tests/TransomMacTests/{HighlightColor,LoginItem,SettingsModel,ViewControlItems,ReportProblem,CollapsedLabel,OnboardingController,UpdateRealDMG}Tests.swift` | test | — | `Tests/TransomMacTests/GapPreferenceTests.swift` | exact |
| `Tests/TransomMacTests/FreezeTestTests.swift` (mod :52-62) | test | — | itself | exact |
| `scripts/release.sh` (mod) | script | batch | itself | exact |
| `scripts/release-version.sh` (new) | script | batch | `~/dev/gifsmith/scripts/release-version.sh` (external) + `scripts/release.sh` header/`fail()` style | role-match |
| `.github/workflows/release.yml`, `tap.yml` (new) | config (CI) | batch | `.github/workflows/ci.yml` + `~/dev/gifsmith/.github/workflows/release.yml` (external) | role-match |
| `xcode/designated-requirement.txt`, `xcode/Assets.xcassets`, `xcode/project.yml` (mod) | config | — | `xcode/project.yml` | partial |
| `packaging/homebrew/transom.rb.template` | config | — | none in repo (RESEARCH cask block) | none |
| `docs/releasing.md`, `docs/macos-beta-checklist.md` | docs | — | none | none |

## Pattern Assignments

### `SettingsWindowController.swift` (controller, request-response)

**Analog:** `Sources/TransomMac/Zoom/ShortcutsWindowController.swift` lines 100-124 (window lifecycle) combined with `Sources/TransomMac/Permission/SetupWindowController.swift` lines 40-65 (sizing).

Imports (ShortcutsWindowController.swift 1-4):
```swift
import AppKit
import KeyboardShortcuts
import SwiftUI
import TransomEngine
```

Single-window show + frame autosave (ShortcutsWindowController.swift 101-124):
```swift
@MainActor final class ShortcutsWindowController {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: ShortcutsView())
        hosting.sizingOptions = []
        let window = KeyClosableWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = ZoomCopy.shortcutsWindowTitle
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 640))
        ...
        if !window.setFrameUsingName("Shortcuts") { window.center() }
        window.setFrameAutosaveName("Shortcuts")
```
Adapt: `contentViewController` becomes an `NSTabViewController` (`tabStyle = .toolbar`) of `NSHostingController`s; `styleMask [.titled, .closable]`; autosave `"Settings"`; `show(pane: SettingsPane?)` selects the tab, persists `settings.lastPane` in `tabView(_:didSelect:)`; add `orderFrontRegardless()` after `makeKeyAndOrderFront` (Pitfall 9). Child hosting controllers use `sizingOptions = [.preferredContentSize]` per SetupWindowController.swift 45-47:
```swift
// The hosting controller publishes SwiftUI's size as preferredContentSize, which the window applies,
// so its height follows each state's content (G-02-1).
hosting.sizingOptions = [.preferredContentSize]
```
Reuse `KeyClosableWindow` (SetupWindowController.swift 79-93) as-is for Esc/⌘W.

Destructive confirmation (Move step "Replace…") copies `confirmRestoreDefaults` (ShortcutsWindowController.swift 128-148): `hasDestructiveAction`, empty key equivalent on destructive, Cancel holds Return, Esc monitor mapped to Cancel.

Delete after migration: the `shortcutsWindow` lazy var (StatusItemController.swift:39) and `openShortcuts` (:374).

---

### Settings tab views (component, CRUD on prefs)

**Analog:** `ShortcutsView` (ShortcutsWindowController.swift 59-98).

Form/section/footer recipe (lines 81-90):
```swift
Section {
    Toggle(ZoomCopy.doubleClickToggle, isOn: $doubleClick).disabled(!zoomEnabled)
} header: {
    Text(ZoomCopy.mouseSection)
} footer: {
    Text(zoomEnabled ? ZoomCopy.doubleClickFooterOn : ZoomCopy.doubleClickFooterZoomOff)
        .font(.subheadline).foregroundStyle(.secondary)
}
...
.formStyle(.grouped)
```
`@AppStorage` is allowed ONLY for lazily read keys with no `onChange` (as lines 60-61 do for `zoomEnabled`, `zoomTitleBarDoubleClick`). For Gaps / New Windows / Drag to Dock, bind to the shared `@Observable` preference instance and write through `set(_:)` (RESEARCH Pattern 2). Shortcuts tab = `ShortcutsView` minus the Mouse section (lines 81-88 move to the Zoom & Gestures tab).

---

### `GapPreference` / `NewWindowsPreference` / `DragToDockPreference` (store, CRUD) — modify to `@Observable`

**Analog:** `Sources/TransomMac/GapPreference.swift` (whole file, 37 lines):
```swift
@MainActor final class GapPreference {
    static let key = "gap"
    static let allowed: [Double] = [0, 4, 8, 12, 16, 24]
    static let defaultValue: Double = 8
    private(set) var value: Double
    var onChange: ((Double) -> Void)?
    private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")
    ...
    func set(_ value: Double) -> Bool {
        guard Self.allowed.contains(value) else { return false }
        self.value = value
        defaults.set(value, forKey: Self.key)
        onChange?(value)
        return true
    }
}
```
Add `@Observable` (import Observation); keep `onChange` (wired at TransomMacApp.swift:70 `gaps.onChange = { gap in Task { await arrangeController.setGap(gap) } }`). Mark `defaults`/`logger`/`onChange` `@ObservationIgnored`.

### `HighlightColor.swift` (store, CRUD)
Same file shape as `GapPreference`: `static let key = "appearance.highlight"`, init(defaults:), invalid value → `logger.error(...)` + `defaults.removeObject` (the line 24-25 log-and-replace pattern), `static var current: NSColor` returning override or `.controlAccentColor`. Replace the four `NSColor.controlAccentColor` sites:
- `Sources/TransomMac/Zoom/StagePanel.swift:267`
- `Sources/TransomMac/Zoom/CollapsedPanels.swift:78`
- `Sources/TransomMac/Overlay/GapHandlePanels.swift:37`
- `Sources/TransomMac/Overlay/PreviewPanel.swift:492` (`case .accent: .controlAccentColor`)

---

### `SettingsPane.swift` (Engine enum)

**Analog:** `Sources/TransomEngine/ConflictPolicy.swift` line 7:
```swift
public enum Conflict: String, CaseIterable, Codable, Sendable {
    case stageManager, edgeTiling, clickWallpaper
}
```
→ `public enum SettingsPane: String, CaseIterable, Sendable, Hashable { case general, arranging, zoom, shortcuts, exclusions, menubar, updates }`. Must be `Hashable` because `Command` keys `TransomURLRateLimiter.lastAdmitted: [Command: ...]` (TransomURL.swift:119).

### `TransomURL.swift` (modify)

**Analog:** itself, lines 87-100. The query guard is on line 90 (`parts.percentEncodedQuery == nil`). Add a `settings` branch before that guard: same scheme/user/password/port/fragment checks, path empty or `/`, query absent or exactly one `pane` item; bad value → `.general`; other keys or 2nd `pane` → nil. Add help line in the tuple table (lines 39-83) as section `"App"`, `("App", "settings", "[pane]", "Open Settings, at a pane if one is named")`, placed after the "Arrange" rows.

Existing parse shape to mirror:
```swift
guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
    parts.percentEncodedUser == nil, parts.percentEncodedPassword == nil, parts.port == nil,
    parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil, let host = parts.percentEncodedHost
else { return nil }
```

### `CLICommandLine.swift` (modify)
Mirror the `view`/`save-view` argument branch (lines 13-18):
```swift
for name in ["view", "save-view"] where first == name || first.hasPrefix(name + "/") {
    let slots = (first == name ? [] : [String(first.dropFirst(name.count + 1))]) + arguments.dropFirst()
    guard slots.count <= 1 else { return .usage(CLICopy.tooManyArguments) }
    ...
    return .send("\(name)/\(slot)")
}
```
→ `if first == "settings"`: >1 extra arg → `.usage(CLICopy.settingsTooManyArguments)` (new string "transom: settings takes at most one argument."), else `.send("settings")` / `.send("settings?pane=\(arg)")`. New CLICopy string goes next to `takesNoArgument` (CLICopy.swift:18).

### `Command.swift` + exhaustive sites (modify)
Precedent `toggleExcludeFrontmost` — add `case settings(SettingsPane?)` and handle each site:
- `Sources/TransomEngine/Arranger.swift:391`: `case (.toggleExcludeFrontmost, _): return [.fault("toggleExcludeFrontmost reached the Arranger; the shell handles it")]`
- `Sources/TransomEngine/Arranger.swift:890` (`if command == .toggleExcludeFrontmost { return true }`) and `:926`
- `Sources/TransomMac/Shell/MenuCopy.swift:55` (`case .toggleExcludeFrontmost: dontArrangeFallback`)
- `Sources/TransomMac/ArrangeController.swift:651` intercept:
```swift
if command == .toggleExcludeFrontmost {
    if let exclusions, Self.toggleExclusion(of: NSWorkspace.shared.frontmostApplication, in: exclusions) { return [] }
    return [.beep]
}
```
→ `if case .settings(let pane) = command { openSettings?(pane, source); return [] }`. Run `swift build` to surface any other exhaustive switch.

---

### `UpdateRelease.swift`, `UpdateState.swift`, `OnboardingFlow.swift`, `InstallLocation.swift` (Engine pure logic)

**Analog for style:** `ConflictPolicy.swift` 14-71 — `public enum` namespace of `public static func`s over value inputs, doc comment per function naming the decision ID, no Foundation beyond what's needed, no AppKit (`scripts/check-no-appkit.sh`). Example:
```swift
public static func active(values: [String: PrefValue], osMajor: Int) -> Set<Conflict> {
    func value(_ key: String) -> PrefValue { values[key] ?? .absent }
    ...
}
```
**Port source:** `~/dev/gifsmith/internal/update/update.go` (versionRE, `parse` 160-197, `GitHubAllow`) and `update_test.go` (port test cases). RESEARCH "Code Examples" has the Swift `UpdateFeed.parse` sketch — use it.

**State machine analog:** `Sources/TransomEngine/PermissionReducer.swift` (pure state + events → effects, consumed by `PermissionController.send`). `UpdateStatus` with busy guard and "failure restores previous" follows the same reducer/effect split.

---

### `UpdateController.swift` (controller, event-driven + timer)

**Analog:** `Sources/TransomMac/Permission/PermissionController.swift` lines 9-14 and 54-62:
```swift
@MainActor public final class PermissionController: ObservableObject {
    @Published public private(set) var state = PermissionState()
    private var pollTask: Task<Void, Never>?
...
        case .startPolling:
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                while true {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    self.send(.pollTick(trusted: AXIsProcessTrusted(), at: self.elapsed))
                }
            }
```
Adapt: injectable `sleep: (Duration) async throws -> Void` (first ~10 s, then 24 h), only while `updates.automatic`; disabled when `Bundle.main.bundleIdentifier != "com.eightabyte.transom"`. Logger category `"update"` (subsystem `com.eightabyte.transom`, `.public` values only).

### `GitHubReleaseClient.swift`, `DMGDownloader.swift`, `DMGVerifier.swift` — no in-repo analog
Use RESEARCH.md Code Examples verbatim (DMGVerifier `SecStaticCodeCheckValidity`, CryptoKit chunked hash, `setxattr` quarantine), ephemeral `URLSession` with `urlCache = nil`. Port semantics from `~/dev/gifsmith/internal/update/install.go`.

### `AppMover.swift` (service, file-I/O + process)
**Analog:** `Sources/TransomMac/Permission/TCCReset.swift` lines 13-30 (Process with argv, never shell-interpolated, logged failure):
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
process.arguments = arguments(bundleID: bundleID)
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
...
do { try process.run() } catch {
    logger.error("tccutil could not launch: \(error.localizedDescription, privacy: .public)")
```
→ `/bin/sh -c '<wait-for-pid loop>; /usr/bin/open "$2"' sh <pid> /Applications/Transom.app` (paths as argv), then `NSApp.terminate(nil)`. Keep the pure `arguments(...)` static (TCCReset line 7) so it is unit-testable.

### `LoginItem.swift` (service)
No direct analog. Protocol `LoginItemService { var status; register(); unregister(); openSystemSettingsLoginItems() }` + `SMAppService.mainApp` impl; inject like `GapPreference(defaults:)` so tests use a fake.

### Onboarding (grown from Permission/)
**Analog:** `Sources/TransomMac/Permission/SetupWindowController.swift` (entire, 93 lines): Combine subscription on `permission.$state` (line 18), `decideAtLaunch` gate (23-26), `windowShouldClose` blocking during reset (67-69), centring on `NSScreen.screens.first` (58-61). Keep these; add `onboarding.completed` / `onboarding.step` UserDefaults keys and step array from `OnboardingFlow.steps`.

Screen Recording seam (Pitfall 5): `Sources/TransomMac/Zoom/SnapshotCapture.swift` 32-40 increments `touches` on every call:
```swift
public static func isGranted() -> Bool { touches += 1; return CGPreflightScreenCaptureAccess() }
public static func request() -> Bool { touches += 1; return CGRequestScreenCaptureAccess() }
```
Onboarding and Settings take `screenRecordingGranted: () -> Bool` / `requestScreenRecording: () -> Bool` closures; production passes `SnapshotCapture.isGranted` / `.request`. `ZoomOffTests` asserts `touches == 0`.

Conflict rows: reuse `ConflictController.turnOff` / `restore` and `ConflictCopy.tooltip(_:)` (pattern at StatusItemController.swift 297-318).

---

### `StatusItemController.swift` (modify) and `ViewControlItems.swift` (new)

**Analog:** StatusItemController.swift.

Status item creation (line 26):
```swift
private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
```
Refresh hook (lines 66-67):
```swift
arrange.onPauseChanged = { [weak self] in self?.updateGlyph() }
arrange.onViewChanged = { [weak self] in self?.updateGlyph() }
```
`onViewChanged` is a single closure — ViewControlItems must chain, not overwrite (e.g. StatusItemController calls `viewControls.refresh()` inside its own handler).

Glyph (lines 261-277) — template image, default symbol size (no forced point size; 1x clipping note in the doc comment), `appearsDisabled` for paused, tooltip/accessibility description:
```swift
let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
image?.isTemplate = true
button.image = image
button.appearsDisabled = paused
button.toolTip = ready && !paused && !zoomed ? Self.bundleName(logger: logger) : description
```
Update dot: wrap the chosen image with RESEARCH `withUpdateDot(_:)` except on the not-ready triangle; append ", update available" to description.

Menu item pattern (lines 215-232, `gapsMenuItem` + `@objc chooseGap` writing through `gaps.set`) — Settings… (⌘,), Report a Problem…, Update items follow `NSMenuItem(title:action:keyEquivalent:)` + `item.target = self`.

Debug lines ("Updates: …", "Login item: …"): add to `debugMenuItem()` (line 378) using `Self.info(_:)` (line 545).

### `ReportProblem.swift` (pure body builder)
**Analog:** `Sources/TransomMac/Shell/MenuCopy.swift` 1-12:
```swift
import TransomEngine
import TransomModel

/// Status-menu copy from the UI-SPEC Copywriting Contract. Pure strings, no AppKit types.
nonisolated public enum MenuCopy {
    public static func header(windows: Int, apps: Int) -> String { ... }
```
Build body from value inputs (counts, versions, capability lines) so the privacy test can pass fixture titles/app names and assert absence. Opening the URL / writing the pasteboard lives in StatusItemController.

### Copy types (`SettingsCopy`, `OnboardingCopy`, `UpdateCopy`)
Same `nonisolated public enum XCopy` shape as MenuCopy; tested like `Tests/TransomMacTests/MenuCopyTests.swift` / `ConflictCopyTests.swift`.

### `CollapsedPanels.swift` (modify, D-16)
Analog: itself — `CollapsedBlockView` (line 15), `static func label(appName:title:)` (line 40, nonisolated pure, reused for line 1), `updateLayer()` (line 63) which already re-resolves colours each draw. Put the fit decision (full / line 1 / icon only) in a `nonisolated static func` so `CollapsedLabelTests` can test it headless, like `label(appName:title:)`. Capsule radius per `TileLayer` (see `Tests/TransomMacTests/TileLayerTests.swift`).

### `FreezeTest.swift` / `FreezeTestTests.swift` (D-17)
`FreezeTest.swift:18` is `private var resumeTask: Task<Void, Never>?` → make it `private(set) var` (internal). Replace the test's deadline loop (FreezeTestTests.swift ~52-56):
```swift
let deadline = ContinuousClock.now + .seconds(1)
while freeze.frozenPID != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
```
with `await freeze.resumeTask?.value`.

---

### Tests (Mac target)
**Analog:** `Tests/TransomMacTests/GapPreferenceTests.swift` 1-30:
```swift
import Foundation
@testable import TransomMac
import Testing

@Suite @MainActor struct GapPreferenceTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.gap.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func anAllowedValuePersistsAndNotifies() throws {
        try withDefaults { defaults in
            let gaps = GapPreference(defaults: defaults)
            var changes: [Double] = []
            gaps.onChange = { changes.append($0) }
            #expect(gaps.set(16))
```
Use for HighlightColor, Settings model (onChange fires from Settings write), menu-bar order prefs, onboarding step persistence. Engine tests follow `Tests/TransomEngineTests/TransomURLTests.swift` / `ConflictPolicyTests.swift` / `CLICommandLineTests.swift` (extend these three for SHIP-08). `UpdateRealDMGTests`: env-gated on `UPDATE_REAL_DMG` (skip when unset), same gating idea as the live suites' `TRANSOM_LIVE`.

---

### `scripts/release.sh` (modify)
Analog: itself. Keep header doc, `set -euo pipefail`, `fail()` helper, arg `case`. Change lines 25-31:
```bash
version=0.3.0
...
profile=pane-notary
dmg="build/Transom-$version.dmg"
```
→ version read from `xcode/project.yml` `MARKETING_VERSION`; `profile="${TRANSOM_NOTARY_PROFILE:-pane-notary}"`; `dmg="build/Transom-$version-universal.dmg"`; write `$dmg.sha256` after staple. Replace the substring DR check:
```bash
case "$requirement" in *"identifier \"$identifier\""*"$team"*) ;; *) fail "designated requirement changed: $requirement" ;; esac
```
with an exact compare against `xcode/designated-requirement.txt`. Add 5×/20 s staple retry (port `~/dev/gifsmith/scripts/stapler-retry.sh`).

### `.github/workflows/release.yml`, `tap.yml` (new)
In-repo analog `.github/workflows/ci.yml` (style: `runs-on: macos-26`, `permissions: contents: read`, `actions/checkout@v5`, `scripts/check-no-appkit.sh`, `swift test --no-parallel`). Structure ported from `~/dev/gifsmith/.github/workflows/release.yml` (gate job, `environment: release`, temp keychain, `notarytool store-credentials`, `if: always()` cleanup) per RESEARCH "release.yml shape". Add to ci.yml a grep guard for `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom`, `DEVELOPMENT_TEAM: S2K7P43927` in `xcode/project.yml` (Pitfall 13).

## Shared Patterns

### Logging
**Source:** `GapPreference.swift:14`, `StatusItemController.swift:27`
```swift
private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")
```
New categories: `update`, `settings`, `onboarding`, `login`. `.public` privacy only for non-identifying values; never titles/app names.

### Validated UserDefaults preference
**Source:** `GapPreference.swift` 16-36. Apply to: HighlightColor, `updates.automatic`, `menuBar.items`, `menuBar.iconOnly`, `gestures.option`, `gestures.wallpaper`, `onboarding.*`, `settings.lastPane`. Inject `defaults: UserDefaults = .standard`.

### Window ownership
**Source:** `SetupWindowController.swift` 28-65 + `KeyClosableWindow` 79-93. Apply to Settings and Onboarding: lazy single window, `isReleasedWhenClosed = false`, `NSApp.activate()` + `makeKeyAndOrderFront`, SwiftUI only inside `NSHostingController`.

### Pure copy enums
**Source:** `MenuCopy.swift` (`nonisolated public enum`, no AppKit). Apply to every new *Copy type and ReportProblem body.

### Shell-handled Command
**Source:** `toggleExcludeFrontmost` at `Arranger.swift:391/890/926`, `ArrangeController.swift:651`, `MenuCopy.swift:55`. Apply to `.settings(SettingsPane?)`.

### Engine purity
`scripts/check-no-appkit.sh` must pass: Engine files import Foundation only.

### Swift 6.3 compatibility (Pitfall 10)
Explicit types in closures/tuples; recent fixes (commit e0f3b30 "CGFloat tuple ... for Swift 6.3") are the reference.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `Updates/GitHubReleaseClient.swift` | service | HTTP request-response | No networking anywhere in the app yet; use RESEARCH Pattern 3 + gifsmith `update.go` |
| `Updates/DMGDownloader.swift` | service | streaming file-I/O | No downloads yet; RESEARCH Code Examples (CryptoKit chunked hash) |
| `Updates/DMGVerifier.swift` | service | file-I/O | No Security framework use yet; RESEARCH Code Examples (probed) |
| `LoginItem.swift` | service | request-response | No SMAppService use yet; RESEARCH Pattern 7 |
| `packaging/homebrew/transom.rb.template` | config | — | No cask in repo; RESEARCH cask block (Rectangle-modelled) |
| `docs/releasing.md`, `docs/macos-beta-checklist.md` | docs | — | No docs dir precedent; content in RESEARCH |

## Metadata

**Analog search scope:** `Sources/TransomEngine`, `Sources/TransomMac/{Permission,Shell,Zoom,Overlay}`, `Tests/TransomMacTests`, `Tests/TransomEngineTests`, `scripts/`, `.github/workflows/`; external reference `~/dev/gifsmith/{internal/update,scripts,.github/workflows}`
**Files scanned:** ~20 read or grepped
**Pattern extraction date:** 2026-11-06
