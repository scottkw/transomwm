# Stack Research

**Domain:** macOS zoomable nested-tiling window manager (menu-bar agent app, non-sandboxed, uses private APIs, distributed outside the Mac App Store)
**Researched:** 2026-10-23
**Confidence:** HIGH for toolchain, layout, packaging and distribution. MEDIUM for private-API behaviour and gesture input.

> **How confidence was assigned.** HIGH means checked against a primary source today: the GitHub API for releases and repo contents, Apple's developer-documentation JSON for API availability, or a run on the dev machine (Xcode 27.1 / Swift 6.4 / macOS 27.0.1). MEDIUM means a primary source plus inference, or several independent secondary sources. LOW means a single web source; LOW items are marked and should not be treated as settled.
> No Context7/MCP doc providers were available in this session. All library versions come from `gh api repos/<owner>/<repo>/releases/latest`, not from memory.

---

## TL;DR (prescriptive)

1. **One `Package.swift`** holds all code as library targets: `PaneModel` → `PaneEngine` → `PaneMac` (AppKit), plus `PanePrivate` (dlsym shims). A thin **XcodeGen `project.yml`** produces `Pane.app` for signing, embedding Sparkle and notarisation. This is AeroSpace's exact pattern.
2. **Swift 6 language mode**, `swift-tools-version: 6.2`, `.macOS(.v14)`. Write new tests with **Swift Testing**. `swift test` runs them headless with no Xcode project.
3. **Call system frameworks directly** for AX, CGEventTap, ScreenCaptureKit, Core Animation and SMAppService, with small wrappers we write ourselves. Take exactly two runtime dependencies: **Sparkle 2.10.0** and **KeyboardShortcuts 3.1.0**.
4. **Load every private symbol with `dlopen`/`dlsym`**, including `_AXUIElementGetWindow`, into optional function pointers in one file per framework. Never link a private symbol at build time.
5. **A Developer ID certificate and notarisation are mandatory**, not optional. Homebrew now rejects casks that fail Gatekeeper, and `--no-quarantine` is deprecated.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Conf. |
|---|---|---|---|---|
| Swift | **6.4** toolchain (Xcode 27.1 locally); package declares `swift-tools-version: 6.2`, Swift 6 language mode | Everything | AeroSpace does the same: tools-version 6.2 with `.swift-version` set to 6.4.0. Tools-version 6.2 is the floor for `.defaultIsolation(MainActor.self)` and `NonisolatedNonsendingByDefault`. It also lets the package build on GitHub's `macos-26` runners, which currently top out at Xcode 26.6. Don't declare 6.4 until CI has Xcode 27. | HIGH (local toolchain + runner-images README) |
| Swift Package Manager | bundled with toolchain | Module graph, dependency resolution, headless build and test of Model and Engine | It enforces the Model / Engine / App split at module level, and `swift test` needs no Xcode project. Every new Swift WM (AeroSpace) keeps its real code in SPM targets. | HIGH |
| XcodeGen | **2.46.0** (2026-07-16) | Generates `Pane.xcodeproj` from `project.yml` for release `.app` builds | AeroSpace's choice. The `.pbxproj` is never committed, so there are no merge conflicts and no hand-edited signing settings. Xcode builds the bundle, embeds Sparkle.framework, applies the entitlements and Info.plist keys, and handles signing. All code stays in SPM, so the project file has only one or two targets. 2.46 supports synced folders and package traits. | HIGH (release API) |
| AppKit | macOS 14 SDK floor, built with the latest SDK | Overlays (`NSPanel`), status item, event plumbing, window-level control | Click-through, full-screen, borderless, non-activating panels at custom window levels are only practical in AppKit. Every WM studied (AeroSpace, Amethyst, Rectangle, Loop) is AppKit-first. | HIGH |
| ApplicationServices / HIServices (Accessibility API) | system | Enumerate, observe, move and resize other apps' windows | No other public API can move another process's windows. Use `AXUIElement`, `AXObserver` and `AXUIElementSetMessagingTimeout` directly. | HIGH |
| ScreenCaptureKit | system, `SCScreenshotManager` (macOS **14.0**) | Window snapshots for the zoom stage | `SCScreenshotManager.captureImage(contentFilter:configuration:)` plus `SCContentFilter(desktopIndependentWindow:)` is available exactly at our floor (14.0). It captures one window even when occluded. `SCStreamConfiguration.ignoreShadowsSingleWindow` is also 14.0. The old `CGWindowListCreateImage` is **unavailable** when the deployment target is ≥15 (verified: compile error with `-target macos15`) and deprecated at 14. | HIGH (Apple doc JSON + local compile) |
| Core Animation (QuartzCore) | system | Render the zoom "stage": one `CALayer` per window snapshot, camera as `sublayerTransform` / bounds | Hardware-composited, cheap to animate hundreds of textured layers, and setting `layer.contents = CGImage` (or an IOSurface) needs no copy. Drive the camera with `NSView.displayLink(target:selector:)` / `CADisplayLink`, both **macOS 14.0**, which match ProMotion. | HIGH (API availability) / MEDIUM (performance, needs a phase-4 spike) |
| CoreGraphics event taps | system (`CGEvent.tapCreate`) | Watch title-bar drags, modifier state, ⌘⇧-drag rectangle zoom, Mission Control key interception | This is the only way to observe and *consume* global input. An active (`.defaultTap`) session tap needs the Accessibility permission we already request. | HIGH |
| ServiceManagement `SMAppService.mainApp` | macOS **13.0** | Launch at login | `register()` / `unregister()` / `status` in three lines. It replaces helper-app login items and the `LaunchAtLogin` packages. | HIGH (Apple doc JSON) |
| Sparkle | **2.10.0** (2026-09-13) | Auto-update | It is the de-facto updater for non-MAS Mac apps (Amethyst, Rectangle, and the reference app ships 2.10). 2.10 requires macOS 12+, fixes delta updates on macOS 27 and drops CocoaPods. It ships through SPM as a binary target. | HIGH (release notes + Package.swift) |

### Supporting Libraries

| Library | Version | Purpose | When to Use | Conf. |
|---|---|---|---|---|
| **KeyboardShortcuts** (sindresorhus, MIT) | **3.1.0** (2026-09-11) | User-configurable global hotkeys (zoom out, step in/out, back/forward, saved views ⌥1–9) plus a SwiftUI `Recorder` for Settings | Use from phase 4 onward, for any hotkey the user can rebind. It is Swift 6, uses MainActor default isolation, is maintained (3.1.0 targets macOS 27 compatibility), is used by Amethyst, and includes conflict detection (`isTakenBySystem`). It wraps Carbon `RegisterEventHotKey`, which is still the supported global-hotkey mechanism. | HIGH (release API, Package.swift) |
| swift-collections (Apple) | **1.7.4** | `OrderedDictionary` / `Deque` for window registries, MRU and history stacks | Optional. Add only once a real need appears, such as the back/forward history ring or an ordered window registry. AeroSpace uses it. | HIGH (version) |
| OSLog (`os.Logger`) | system | Structured logging with per-subsystem categories (`ax`, `tap`, `camera`, `skylight`) | Always. No dependency, near-zero cost when disabled, readable in Console.app. Users can send `log collect` output for bug reports. | HIGH |
| SwiftUI | system | Settings window, onboarding and permission-flow screens only | Host it in an AppKit-owned `NSWindow` through `NSHostingController`. Do not use the SwiftUI `App`/`Settings` scene lifecycle (see What NOT to Use). | HIGH |
| Foundation `Codable` + `JSONEncoder` | system | Persist the layout tree, saved views and per-display state to `~/Library/Application Support/Pane/` | Always. `PaneModel` may import Foundation but not AppKit. Value types plus Codable give free round-trip tests. | HIGH |
| `UserDefaults` / `@AppStorage` | system | Preferences: gaps, exclusions, toggles | Always. Skip `Defaults` (sindresorhus) unless the settings surface grows past ~30 keys. | MEDIUM (judgement) |
| *(reference only)* OpenMultitouchSupport (Kyome22, MIT) | 4.0.0 (2026-05-28) | Raw trackpad contacts | **Do not depend on it.** 4.0.0 raised its floor to **macOS 15** (our floor is 14) and ships a **prebuilt binary XCFramework**, an unauditable private-API blob. Read its headers and port the ~10 `MT*` signatures into our own `PanePrivate/MultitouchSupport.swift` dlsym shim. | HIGH (Package.swift + release notes) |

### Development Tools

| Tool | Version | Purpose | Notes |
|---|---|---|---|
| Xcode | 27.1 locally; CI on `macos-26` runners (Xcode 26.6 default) | Release builds, Instruments (Core Animation / Time Profiler for the zoom stage) | Debug loop is `swift build` / `swift test`. Xcode is only needed to build the signed `.app` and to profile. |
| XcodeGen | 2.46.0 | `xcodegen generate --spec xcode/project.yml` | Run it from a `generate.sh`. Add `*.xcodeproj` to `.gitignore`. |
| `swift format` (swift-format, bundled in the toolchain) | ships with Swift 6.4 (standalone 604.0.0) | Formatting and lint | No install needed (verified: `swift format --version` works locally). Add `.swift-format` and run `swift format lint --strict -r Sources Tests` in CI. Add SwiftLint 0.65.1 only if custom rules become necessary. |
| xcbeautify | 3.2.1 | Readable `xcodebuild` logs in CI | `brew install xcbeautify`. |
| `xcrun notarytool` + `xcrun stapler` | Xcode 27 | Notarise and staple the `.app` / `.dmg` | `notarytool store-credentials pane-notary` once, then `submit --keychain-profile pane-notary --wait`. |
| Sparkle CLI tools (`generate_keys`, `generate_appcast`, `sign_update`) | 2.10.0 | EdDSA keys, appcast generation | Found under the SPM artifacts dir (`.../artifacts/sparkle/Sparkle/bin/`). Keep the private EdDSA key in the login keychain and back it up (`generate_keys -x`). |
| create-dmg (optional) | 1.3.0 | Pretty DMG | A notarised **zip** is enough for Sparkle and Homebrew. Amethyst, Loop and AeroSpace ship zips. Add a DMG only for website downloads. |
| GitHub Actions | `macos-26` (arm64) | `swift test` on every PR, tag-triggered release job (build, sign, notarise, appcast, cask bump) | Import the Developer ID `.p12` into a temporary keychain in the job and use an App Store Connect API key for notarytool. |
| Homebrew | 7.0.10 current | Cask distribution | Start with our own tap, `<org>/homebrew-tap`, and submit to `homebrew/cask` once notable (see Distribution). |

---

## Package Layout (prescriptive)

```
Package.swift                 // swift-tools-version: 6.2, platforms: [.macOS(.v14)]
.swift-version                // 6.4
Sources/
  PaneModel/                  // import Foundation only. Value-type tree, geometry, Codable. No concurrency annotations needed (Sendable structs).
  PaneEngine/                 // depends: PaneModel. Camera, navigator, drag/drop/resize sessions, saved views, tweens.
                              //   Defines `protocol WindowSystem` (+ Snapshotter, Clock); never imports AppKit.
  PanePrivate/                // Swift target. One file per private framework: SkyLight.swift, MultitouchSupport.swift,
                              //   HIServicesPrivate.swift (_AXUIElementGetWindow, CoreDockSendNotification), SymbolicHotKeys.swift.
                              //   Every symbol is `static let fn: FnType? = load("name")`.
  PaneMac/                    // depends: PaneEngine, PanePrivate, Sparkle, KeyboardShortcuts. AppKit + AX + SCK + taps + overlays.
                              //   `AXWindowSystem: WindowSystem`. This is AeroSpace's "AppBundle" library target.
  PaneApp/                    // executableTarget: 5-line main.swift -> PaneMac.run(). Lets `swift run PaneApp` work for quick dev.
Tests/
  PaneModelTests/             // Swift Testing
  PaneEngineTests/            // Swift Testing, with FakeWindowSystem
xcode/
  project.yml                 // XcodeGen: one `application` target "Pane" depending on local package product PaneMac
  Pane.entitlements           // hardened runtime; NO app-sandbox
  Info.plist keys via INFOPLIST_KEY_* (LSUIElement=YES, CFBundleURLTypes for pane://, SUFeedURL, SUPublicEDKey)
scripts/ generate.sh, build-release.sh, notarize.sh, bump-cask.sh
```

**Swift settings per target** (MEDIUM, a judgement call grounded in AeroSpace and KeyboardShortcuts settings):

| Target | Settings | Why |
|---|---|---|
| PaneModel | Swift 6 mode, `.enableUpcomingFeature("NonisolatedNonsendingByDefault")`, `.enableUpcomingFeature("ExistentialAny")` | Pure value types are `Sendable` for free. Leave them nonisolated so tests and the engine can use them from anywhere. |
| PaneEngine | the above plus `.defaultIsolation(MainActor.self)` | The engine is driven by UI events and display-link ticks on main. MainActor by default removes most Sendable noise. Mark pure helpers `nonisolated`. |
| PaneMac / PaneApp | `.defaultIsolation(MainActor.self)`, `NonisolatedNonsendingByDefault`, `InferIsolatedConformances` | AppKit is MainActor. C callbacks (AXObserver, CGEventTap, MT contact frames) are `@convention(c)` and arrive on their own run-loop threads, so bridge them explicitly with `Unmanaged` refcon plus `MainActor.assumeIsolated` or a hop. |
| PanePrivate | Swift 6 mode, nonisolated | Function-pointer tables are immutable `static let`s. |

**Enforce "Model/Engine never import AppKit"** with a CI grep (`! grep -rE '^import (AppKit|Cocoa|SwiftUI)' Sources/PaneModel Sources/PaneEngine`). SPM cannot forbid an SDK import on its own. (HIGH)

---

## Private API Access (prescriptive)

| API | Framework | How | Fallback | Conf. |
|---|---|---|---|---|
| `_AXUIElementGetWindow(AXUIElement, *CGWindowID) -> AXError` | ApplicationServices (HIServices) | `dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow")` cast to `@convention(c)` | Match the AX window frame and title against `CGWindowListCopyWindowInfo` (public, unchanged since 10.5) | HIGH (symbol resolves on macOS 27.0.1, verified locally) |
| `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace`, `SLSManagedDisplayGetCurrentSpace`, `SLSCopySpacesForWindows`, `SLSWindowQueryWindows` / `SLSWindowQueryResultCopyWindows` / `SLSWindowIterator*` | `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` | `dlopen(path, RTLD_LAZY)` once, then `dlsym` per symbol into optionals. Loop's `SkyLightSymbolLoader` is a clean public example (GPL-3.0, so read it, do not copy it). | Without Spaces: single-Space mode, with the Spaces bar hidden | HIGH (all resolve on macOS 27, verified locally); MEDIUM (signatures, from yabai/Loop) |
| `CGSSetSymbolicHotKeyEnabled` / `SLSSetSymbolicHotKeyEnabled`, `CoreDockSendNotification` | SkyLight / HIServices | dlsym | Mission Control takeover becomes "off" (feature-flagged) | HIGH (resolve); MEDIUM (behaviour) |
| `MTDeviceCreateList`, `MTDeviceCreateDefault`, `MTRegisterContactFrameCallback`, `MTDeviceStart`/`Stop` | `/System/Library/PrivateFrameworks/MultitouchSupport.framework` | dlopen/dlsym. Write our own ~150-line shim modelled on OpenMultitouchSupport's (MIT) header. | Hotkeys plus `NSEvent` magnify inside our own overlay. A global ⌥-pinch would be unavailable. | HIGH (resolve); MEDIUM (callback struct layout) |

**Why dlsym and not a C header with link-time binding (AeroSpace's `PrivateApi/private.h`):** a link-time reference to a symbol Apple removes makes dyld fail *at launch*, and the app won't open at all. A `dlsym` miss returns nil, so we can log once and degrade one feature. That is the PROJECT.md "isolated in one file with a fallback" constraint, enforced by the type system (`fn?`). (HIGH reasoning)

**Notarisation is not affected by private-API use.** The notary service checks signature, hardened runtime and malware, not API usage. AeroSpace, yabai and Loop ship private-API calls outside the MAS. `dlopen` of Apple-signed system frameworks passes library validation, so **no `disable-library-validation` entitlement is needed**. (MEDIUM: standard practice, not re-verified against Apple docs today)

---

## Input: Hotkeys, Event Taps, Gestures

- **Global hotkeys** come from KeyboardShortcuts 3.1.0 (Carbon `RegisterEventHotKey` underneath). Note: **macOS 15.0–15.1 refused Option-only and Option+Shift-only hotkeys**, as an anti-keylogger measure. Apple reverted this in **15.2**. Pane's default ⌥1–9 therefore works on 14.x and 15.2+, but **not on 15.0/15.1**. Fall back to ⌃⌥1–9 when registration fails. (MEDIUM: Apple Dev Forums thread + Eternal Storms blog)
- **Event tap:** one active `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, ...)` on a dedicated thread with its own `CFRunLoop`. Mask: mouse down/drag/up, flagsChanged, keyDown (for Mission Control keys), scrollWheel. **Always** handle `.tapDisabledByTimeout` / `.tapDisabledByUserInput` by re-enabling. Keep the callback under ~1 ms and do no AX calls inside it. (HIGH)
- **Trackpad pinch/pan:** follow the reference app and use MultitouchSupport through our own shim. Whether a CGEventTap can reliably *see and consume* system magnify/gesture events (CGEvent types 29/30) over other apps on macOS 14–27 is **unverified** (LOW). Phase 5 needs a one-day spike to compare both paths before committing.

---

## Window Snapshots (ScreenCaptureKit) specifics

- Check permission with `CGPreflightScreenCaptureAccess()` and request it with `CGRequestScreenCaptureAccess()`. Screen Recording is **optional**. Without it, render app-colour plus `NSRunningApplication.icon` tiles (PROJECT.md requirement).
- Map AX windows to `SCWindow` through `windowID` (from `_AXUIElementGetWindow`), taken from `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)`.
- Capture with `SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow:), configuration:)`. Set `width`/`height` to the **on-stage pixel size, not native** (for example 25% when zoomed out), `ignoreShadowsSingleWindow = true`, `showsCursor = false`. Batch captures concurrently with a small limit (4–6) and cache them per windowID with a timestamp. (HIGH for API; MEDIUM for batching numbers)
- macOS 15+ re-asks for Screen Recording consent roughly **monthly**, and that cannot be suppressed. Onboarding copy should say so. (MEDIUM: 9to5Mac/TidBITS, 2024 reports)
- Newer APIs to *conditionally* adopt: `captureImage(in:)` (15.2) and `captureScreenshot(contentFilter:configuration:)` (26.0, HDR / SDR+HDR outputs). Put them behind `if #available`. Not needed for v1.

---

## Build, Sign, Notarise, Ship

**Signing identities**

| Build | Identity | Why |
|---|---|---|
| Local dev | A **stable** identity: an Apple Development cert, or a self-signed cert like AeroSpace's `aerospace-codesign-certificate` | TCC (Accessibility, Screen Recording) grants are keyed to the code signature's designated requirement. Ad-hoc signing (`-`) changes it on every rebuild, so permissions silently reset. This is the #1 dev-loop time sink for WMs. Use a separate debug bundle ID (`…pane.debug`) so dev and release grants don't collide. |
| Release | **Developer ID Application** + hardened runtime + notarised + stapled | Required by Homebrew (below) and by Gatekeeper for downloaded apps. Costs USD 99/yr. AeroSpace skips this and strips quarantine in its own tap, a route Homebrew is closing. |

**Entitlements:** hardened runtime on, `com.apple.security.app-sandbox` absent or false (AX does not work sandboxed), no other entitlements expected. (HIGH)

**Release pipeline:** `swift test` → `xcodegen generate` → `xcodebuild -scheme Pane -configuration Release ARCHS="arm64 x86_64"` (universal: PROJECT.md needs Intel) → `codesign --verify --deep --strict` → `ditto -c -k --keepParent Pane.app Pane-x.y.z.zip` → `notarytool submit --wait` → `stapler staple Pane.app` → re-zip → `generate_appcast` → GitHub Release + appcast on GitHub Pages → bump cask.

**Sparkle wiring:** add the `https://github.com/sparkle-project/Sparkle` package to `project.yml` with `from: 2.10.0` and link it to `PaneMac` through Package.swift. Instantiate `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate:, userDriverDelegate:)` in code (no XIB). Set Info.plist `SUFeedURL` (https) and `SUPublicEDKey`, and consider `SURequireSignedFeed`. We are not sandboxed, so the XPC services can be stripped. Ad-hoc-signed debug builds may fail to load Sparkle under library validation, so use the stable dev identity. (HIGH: Sparkle docs + 2.10 release)

**Homebrew:**
- Homebrew 5.0 deprecated `--no-quarantine`. The policy (Acceptable Casks): *"apps … that Gatekeeper can assess must pass Homebrew's Gatekeeper checks"* and *"must not require … Gatekeeper to be disabled or bypassed."* Casks that failed Gatekeeper were scheduled to lose support on 2026-09-01. (HIGH for the policy text, from docs.brew.sh; MEDIUM for the date, from secondary sources)
- `homebrew/cask` also applies notability thresholds that a brand-new repo won't meet. **Ship first via our own tap** (`brew install <org>/tap/pane`), then submit upstream. Model the cask on Rectangle's official one: `auto_updates true` (Sparkle owns updates), `depends_on macos: :sonoma`, `uninstall quit:` / `login_item:`, `zap trash:`, and a `livecheck` with `strategy :sparkle`. (HIGH: read from homebrew-cask today)

---

## How the prior art does it (evidence, read 2026-10-23)

| Project | License | Build | Tests | Hotkeys | Updates | Private API style | Distribution |
|---|---|---|---|---|---|---|---|
| **AeroSpace** 0.21.3-Beta | MIT | Package.swift (tools 6.2, `.swift-version` 6.4.0) + **XcodeGen** for release; debug is SPM-only | XCTest | HotKey 0.2.1 (Carbon) | none (brew) | C target `PrivateApi` declaring `_AXUIElementGetWindow` (link-time) | Own tap, self-signed, **not notarised**, `xattr -d com.apple.quarantine` postflight |
| **Amethyst** 0.24.3 | MIT | Committed `.xcodeproj` + workspace, fastlane | Quick/Nimble (XCTest) | KeyboardShortcuts (+ legacy MASShortcut) | Sparkle 2 | Silica (own AX wrapper) | homebrew/cask, notarised |
| **Rectangle** 2.0.4 | MIT-variant (GitHub: NOASSERTION) | Committed `.xcodeproj`, deployment 10.15 | XCTest | MASShortcut fork | Sparkle 2 | minimal | homebrew/cask, DMG, notarised, `depends_on :sonoma` |
| **Loop** 1.4.2 | **GPL-3.0** (do not copy) | Committed `.xcodeproj`, deployment 13.0 | XCTest | own | **own updater** (ZIPFoundation + helper), not Sparkle | `dlopen`/`dlsym` SkyLight loader with optional typed function pointers | homebrew/cask zip |
| **yabai** 7.1.25 | MIT | C, Makefile | none | skhd (separate) | brew | SkyLight via headers; SIP-off features | Own tap |

Takeaways: AeroSpace's **SPM + XcodeGen** structure fits Pane's layering best. Loop's **dlsym loader** is the best private-API isolation pattern. Rectangle and Amethyst show the **notarised + Sparkle + homebrew/cask** distribution path. Nobody uses Swift Testing yet, simply because their test suites predate it. (HIGH)

---

## Installation

```bash
# One-time dev tooling
brew install xcodegen xcbeautify
xcode-select -p   # must point at Xcode 27.x (or 26.4+ for tools-version 6.2)

# Package.swift dependencies (the only two runtime deps)
#   .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
#   .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
# optional later:
#   .package(url: "https://github.com/apple/swift-collections", from: "1.7.4"),

# Dev loop (no Xcode project needed)
swift build && swift test
swift format lint --strict -r Sources Tests

# Release
./scripts/generate.sh            # xcodegen generate --spec xcode/project.yml
./scripts/build-release.sh       # xcodebuild | xcbeautify, codesign verify, notarize, staple, appcast
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|---|---|---|
| SPM + XcodeGen | **Plain committed `.xcodeproj`** with Xcode 16+ synchronized folders (Loop, Rectangle, Amethyst) | If contributors mostly work in Xcode and nobody minds `.pbxproj` diffs. Synced folders make it far less painful than before. Code should still live in SPM targets. |
| SPM + XcodeGen | **Tuist 4.213** | When a multi-app or multi-extension workspace needs caching and graph tooling. That is overkill for one app target plus a local package, and it adds a `mise`-managed CLI and Swift manifests. |
| SPM + XcodeGen | **Pure SPM with a hand-rolled bundle script** (`swift build` → copy into `Pane.app/Contents/MacOS`, write Info.plist, embed Sparkle.framework, fix rpaths, `codesign`) or swift-bundler | Only if Xcode must be avoided entirely. You'd re-implement framework embedding, asset catalogs (`actool`) and entitlements by hand. AeroSpace explicitly says "don't use this build for release". |
| Swift Testing | XCTest | Only for `measure {}` performance baselines (Swift Testing has no perf-metric API) or for UI tests. Swift 6.4 adds XCTest↔Swift Testing interop, so both can coexist in one target. |
| KeyboardShortcuts 3.1.0 | HotKey 0.2.1 (soffes; AeroSpace) | If hotkeys are only config-file defined with no recorder UI. Last push 2024-12, effectively frozen. |
| KeyboardShortcuts | Hotkeys handled in our CGEventTap | For chords that Carbon can't express (modifier-only, or keys we must *suppress* such as Mission Control F3/⌃↑). Pane needs the tap anyway for those, so keep Carbon for normal rebindable shortcuts. |
| Own AX wrapper | AXSwift 0.3.2 (tmandry) | Never for new code. Last release 2021, no Swift 6 concurrency, no messaging-timeout ergonomics. |
| Own AX wrapper | Silica (ianyh) | Never. It's shaped around Amethyst's needs and its last tag is v0.3.7. |
| Own MT shim | OpenMultitouchSupport 3.0.x | If the shim proves fiddly: 3.0.x supported macOS 13+ (4.0 needs 15+). It's still a binary XCFramework, so pin the checksum. |
| Core Animation stage | Metal (`CAMetalLayer`) | Only if Instruments shows CA can't hold 120 Hz with more than ~100 snapshot layers. Unlikely; defer. |
| Sparkle | Custom updater (Loop) | Never. You would own EdDSA verification, delta updates and relaunch logic. |
| Developer ID + notarisation | Unsigned + own tap with quarantine strip (AeroSpace) | Not viable for a public 2026 release. Homebrew is ending Gatekeeper bypasses, and macOS 15+ makes running unsigned downloads hard (System Settings → Open Anyway). |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| `CGWindowListCreateImage` / `CGWindowListCreateImageFromArray` | Deprecated in 14, **unavailable** at deployment target ≥15 (verified compile error), and it triggers extra "deprecated capture" privacy prompts on 15.1+ | `SCScreenshotManager` |
| Link-time private symbols (`@_silgen_name`, C header declarations, `-framework SkyLight`) | If Apple removes a symbol, dyld fails at launch and the whole app is dead | `dlopen` + `dlsym` into optional function pointers in `PanePrivate` |
| SwiftUI `App` + `Settings {}` scene + `MenuBarExtra` as the app shell | Agent (`LSUIElement`) apps can't reliably bring a Settings scene forward. `openSettings` and activation policy juggling are fragile across 14–27. MenuBarExtra lacks NSMenu control. | AppKit `NSApplication` + `NSStatusItem` + `NSHostingController` windows |
| App Sandbox | The AX API does not work sandboxed, and neither does dlopen of private frameworks | Hardened runtime, non-sandboxed |
| `SMLoginItemSetEnabled`, helper launcher apps, `LaunchAtLogin` (legacy), `LSSharedFileList` (Amethyst's LoginServiceKit) | Deprecated since macOS 13 | `SMAppService.mainApp` |
| Quick / Nimble / RxSwift (Amethyst-era) | Heavy dependencies that Swift Testing and Swift concurrency have replaced | Swift Testing `#expect`, `AsyncStream` |
| OpenMultitouchSupport 4.x as a dependency | Requires macOS 15 (breaks our 14 floor), and it is a closed binary blob wrapping a private API | Own dlsym shim |
| Ad-hoc signing for day-to-day dev | It resets Accessibility/Screen Recording grants on every rebuild | Stable dev cert + separate debug bundle ID |
| Running AX calls inside the event-tap callback or blocking main on slow apps | The tap gets disabled by timeout, and the UI hangs on Electron/Java apps | Per-app AX work off main with `AXUIElementSetMessagingTimeout` (~0.25–1 s), results marshalled to MainActor |
| Copying Loop code | GPL-3.0 is incompatible with Pane's MIT license | Read it for patterns and reimplement |
| CocoaPods / Carthage | Sparkle 2.10 dropped CocoaPods; the ecosystem is SPM-only | SPM |

---

## Stack Patterns by Variant

**If CI must build the signed app before GitHub ships an Xcode 27 runner:**
- Keep `swift-tools-version: 6.2` and avoid Swift 6.4-only syntax (such as `anyAppleOS` availability and async `defer`) in shipped code.
- The `macos-26` image provides Xcode 26.6 (macOS 26.5 SDK), and builds against that SDK run fine on macOS 27.

**If Screen Recording is denied:**
- The stage draws `CALayer`s with an app-colour fill (dominant icon colour) plus a centred app icon and title text, all from public APIs.
- No functional loss for tiling, which keeps the "Core Value" requirement independent of SCK.

**If a private symbol is missing at runtime (new macOS):**
- Log once with `os.Logger(category: "private")`, disable only that feature (Spaces bar, Mission Control takeover, global pinch), and show the status in an About/Diagnostics pane.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|---|---|---|
| Sparkle 2.10.0 | macOS 12+ deployment, Xcode 26/27 | 2.10 dropped < 12 because Xcode 27 can't target older OSes. Fine for our 14 floor. |
| KeyboardShortcuts 3.1.0 | swift-tools 6.2, macOS 10.15+ | Uses `.defaultIsolation(MainActor.self)`, so a 6.2+ toolchain is required. |
| swift-tools-version 6.2 | Xcode 26.x (CI), Xcode 27.1 (local) | 6.4 tools-version would lock out the current GitHub runners. |
| XcodeGen 2.46.0 | Xcode 27 project format via XcodeProj 9.14 | Pin it in CI (`brew install xcodegen` gets the latest; or use mint/mise with a version). |
| `SCScreenshotManager` | macOS 14.0+ | Our exact floor, so no availability branching for the core path. |
| `NSView.displayLink` / `CADisplayLink` (macOS) | macOS 14.0+ | No `CVDisplayLink` needed (deprecated in 15). |
| `SMAppService` | macOS 13.0+ | — |
| Private symbols listed above | Verified resolvable on macOS 27.0.1 (build 26A434), 2026-10-23 | Presence only. Behaviour and signatures must be re-tested each macOS beta. |

---

## Sources

- GitHub API (primary, HIGH): latest releases and repo contents read 2026-10-23 for sparkle-project/Sparkle (2.10.0 notes + Package.swift), nikitabobko/AeroSpace (Package.swift, `xcode/project.yml`, `build-release.sh`, `script/build-brew-cask.sh`, `Sources/PrivateApi/include/private.h`, test imports), ianyh/Amethyst (Package.resolved), rxhanson/Rectangle and mrkai77/Loop (pbxproj package refs, `Loop/Private APIs/SkyLightSymbolLoader.swift`), sindresorhus/KeyboardShortcuts (3.1.0, Package.swift), Kyome22/OpenMultitouchSupport (4.0.0, Package.swift, README), yonaskolb/XcodeGen (2.46.0 notes), tuist/tuist (4.213.0), apple/swift-collections (1.7.4), apple/swift-format (604.0.0), realm/SwiftLint (0.65.1), cpisciotta/xcbeautify (3.2.1), tmandry/AXSwift (0.3.2, 2021), soffes/HotKey (pushed 2024-12).
- Homebrew/homebrew-cask `Casks/r/rectangle.rb`, `Casks/a/amethyst.rb`, `Casks/l/loop.rb` (primary, HIGH).
- actions/runner-images `images/macos/macos-26-arm64-Readme.md` (Xcode 26.6 default) (primary, HIGH).
- Apple developer documentation JSON (`developer.apple.com/tutorials/data/documentation/...`) for availability: SMAppService.mainApp 13.0; SCScreenshotManager / captureImage(contentFilter:) / SCContentFilter(desktopIndependentWindow:) / ignoreShadowsSingleWindow 14.0; captureImage(in:) 15.2; captureScreenshot 26.0; NSView.displayLink & CADisplayLink 14.0 (primary, HIGH).
- Local verification on macOS 27.0.1 / Xcode 27.1 / Swift 6.4: `swift package init` generates Swift Testing tests and `swift test` passes; `CGWindowListCreateImage` is a deprecation warning at a macOS 14 target and an error at 15; all listed private symbols resolve via dlsym; `swift format` is bundled (HIGH).
- https://sparkle-project.org/documentation/ — SPM setup, SUFeedURL/SUPublicEDKey, generate_keys/generate_appcast, library-validation note (MEDIUM via fetch, matches release notes).
- https://docs.brew.sh/Acceptable-Casks — Gatekeeper requirement wording (HIGH, official).
- https://workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet and https://feedbagel.com/post/homebrew-to-remove-no-quarantine-flag-support-for-macos-security-compliance — `--no-quarantine` deprecation, 2026-09-01 date (MEDIUM, secondary).
- https://developer.apple.com/forums/thread/763878?page=2 and https://blog.eternalstorms.at/2024/09/23/keyboard-shortcuts-using-option-and-or-shift-modifiers-only-no-longer-allowed-on-macos-sequoia/ — Option-only hotkey restriction in 15.0–15.1, reverted in 15.2 (MEDIUM).
- https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/ and https://talk.tidbits.com/t/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly/28621 — monthly Screen Recording re-consent (MEDIUM, 2024 reporting).
- https://www.infoq.com/news/2026/09/swift-6-4-released/ and https://developer.apple.com/wwdc26/guides/swift/ — Swift 6.4 features incl. Swift Testing/XCTest interop (MEDIUM).
- CGEventTap visibility of system gesture events: no conclusive source found (LOW). Flagged for a phase-5 spike.

---
*Stack research for: macOS zoomable nested-tiling window manager (Pane)*
*Researched: 2026-10-23*
