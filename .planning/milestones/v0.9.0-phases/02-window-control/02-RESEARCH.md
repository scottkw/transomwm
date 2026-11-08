# Phase 2: Window Control - Research

**Researched:** 2026-10-24
**Domain:** macOS Accessibility (AX) window tracking and control, private-API isolation, signed agent-app packaging (XcodeGen), Swift 6 concurrency across C callback threads
**Confidence:** HIGH for AX behaviour, Swift 6 compile shapes and test mechanics. Most of these were checked this session with probes run against a throwaway fixture app on macOS 27.0.1 / Xcode 27.1 / Swift 6.4. MEDIUM for lock/sleep signals and the per-app heuristics, which can't be probed without locking the Mac or installing apps. MEDIUM for XcodeGen, which isn't installed locally (spec docs were read, but no project was generated).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### App shell, permission & signing
- Phase 2 ships a minimal menu-bar `Pane.app` (LSUIElement) with a debug menu: live tracked-window list, "Nudge focused window" (move/resize test), "Freeze test" helper, and "Don't arrange <frontmost app>". No tiling.
- Permission flow: one onboarding window explains Accessibility; a button opens System Settings ▸ Privacy & Security ▸ Accessibility; Pane polls `AXIsProcessTrusted()` every 1 s and advances by itself. Stale grant (trusted but AX calls fail) is detected by a real AX probe and explained, with a "Reset permission" button that runs `tccutil reset Accessibility <bundle id>` and tells the user to re-grant.
- All builds (debug included) are signed with the developer's **Developer ID Application** identity (team `S2K7P43927`, hardened runtime) so TCC grants survive rebuilds. Never ad-hoc sign.
- Bundle IDs: release `com.eightabyte.pane`; debug `com.eightabyte.pane.debug` (separate TCC entries).
- App bundle produced by XcodeGen `project.yml` around the SwiftPM targets (per STACK.md); the `.xcodeproj` is generated, never committed.

#### Window tracking & classification
- Track every window of every regular-activation-policy app. Each window is classified **dockable** (AXStandardWindow) or **never-dock** (dialog, sheet, popover, PiP, utility/floating panel, splash). Never-dock windows are tracked but never arranged. Minimised windows are tracked with lifecycle state `absent`.
- Classifier is tested against a committed corpus of recorded AX dumps: a `pane-dump` tool records AX attribute trees from real apps on this Mac into JSON fixtures with titles and other personal strings redacted. Initial corpus: Finder, Safari, Terminal, one Electron app, one Java app, System Settings, an Office app if installed.
- Native tabs: windows of the same app sharing a tab group (`AXTabGroup`, or same frame with tab siblings) count as one tracked window, represented by the visible tab.
- Close confirmation needs two sources: AX element invalid (`kAXErrorInvalidUIElement`) **and** the window id absent from the CG/SkyLight window list. A timeout never counts as closure. Reconciliation pauses during screen lock and sleep; a full refresh runs after unlock/wake. AX notifications are hints that trigger a cancellable refresh.
- OS lifecycle changes reach the model only through `World.apply` (never `World.edit`), per the Phase 1 contract; `.closed` needs no valid desk key.
- After `World.undo` returns restored windows, the engine re-queries the OS for each and reports its real state via `World.apply` (Phase 1 obligation, commit c403f45).

#### Exclusions, minimums & testing
- Exclusion list: bundle IDs in UserDefaults; edited in Phase 2 via the menu item "Don't arrange <frontmost app>" (toggle). Full Settings UI is Phase 9. No hard-coded default exclusions.
- Learned minimums: per window in memory, plus per-bundle-ID hints persisted as JSON in `~/Library/Application Support/Pane/`.
- Testing: unit tests against `FakeWindowSystem` simulate hung apps, slow apps, window-id churn, refusing sizes and lock-screen blanking. A small integration-test target exercises real AX only when the process is trusted (skips otherwise). Real `kill -STOP`, lock-screen, sleep and multi-display checks are a manual UAT checklist the developer runs.
- Private APIs: `PanePrivate` target, one file per API, every symbol loaded via `dlopen`/`dlsym` into optional function pointers; a capability registry logged at launch. Debug launch flag `--disable-private=<name>` (e.g. `AXWindowID`) forces a capability off; without `_AXUIElementGetWindow` windows are matched by pid + frame + title.

#### Architecture (from research, locked)
- Per-app AX thread with its own CFRunLoop and observers; `AXUIElementSetMessagingTimeout` ~1 s per app; an unresponsiveness tracker marks degraded apps; a newer setFrame replaces any queued one for the same window.
- Frame writes are size → position → size with `AXEnhancedUserInterface` temporarily off; every write is read back.
- One tested coordinate-conversion boundary (Pane model is top-left global points; AppKit is bottom-left) and displays matched by UUID.

### Claude's Discretion
- Exact file layout inside the new targets (`PanePrivate`, `PaneMac`, `PaneApp`, test support)
- Refresh debounce intervals, degraded-app thresholds, polling intervals other than the 1 s permission poll
- Debug menu wording and layout

### Deferred Ideas (OUT OF SCOPE)
- Settings window for the exclusion list (Phase 9)
- Multi-display layout persistence and Spaces keying (Phase 6); Phase 2 only matches displays by UUID and converts coordinates
- Fullscreen tile return (WIN-07, Phase 3)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WIN-01 | User is guided through granting Accessibility permission, and a stale grant is detected and explained | Pattern 7 (permission state machine with two stale forms), Pitfall 9 (responsible process), Pitfall 10 (Swift 6 `kAXTrustedCheckOptionPrompt`), verified `tccutil` behaviour, TN3127 DR facts |
| WIN-02 | Pane tracks every standard window of every running app, including windows opened or closed later | Pattern 1 (per-app threads), Pattern 4 (refresh strategy), verified `AXWindows` contents (Finder desktop pseudo-window), NSWorkspace lifecycle |
| WIN-03 | A hung or slow app never freezes Pane or delays arranging other apps' windows | Verified: a frozen app returns -25204 after the timeout and `_AXUIElementGetWindow` blocks too; timeouts don't propagate between elements; Pattern 1 + unresponsiveness tracker; reactive `inventory()` |
| WIN-04 | Pane moves and resizes windows and learns an app's real minimum size when it refuses a size | Verified: undersized `AXSize` write returns success and reads back clamped; `AXMinimumSize` unsupported. Pattern 5 (write pipeline), Pattern 6 (coordinates) |
| WIN-05 | Dialogs, sheets, popovers and PiP windows are never docked (classifier tested against recorded AX dumps) | Verified AX shapes of sheet/borderless/no-fullscreen windows; Chrome PiP is `AXStandardWindow` (AeroSpace dump); minimised and hidden windows report `AXDialog`. Pattern 2 (snapshot + pure classifier + corpus) |
| WIN-06 | Native tabs (Finder, Terminal, Safari, etc.) count as one window | Verified: AX lists only the selected tab, which has an `AXTabGroup` child; hidden tabs are CG-only, offscreen, same bounds; switching tabs swaps the listed ID. Pattern 3 (TabGroupTracker) |
| WIN-08 | User can list apps whose windows Pane never arranges | Exclusion store in UserDefaults; `perform` drops commands for excluded bundle IDs (defence in depth) |
| WIN-09 | A window is only treated as closed when two sources confirm it; lock screen, sleep and timeouts never close windows | Verified signals: closed window gives -25202 plus CG absence; a terminated app gives -25204 (so app death comes from NSWorkspace). Close decision table; lock/sleep signal set |
| SAFE-05 | A missing or broken private API disables only its own feature; Pane still launches | Verified: `RTLD_DEFAULT` isn't importable and default-handle `dlsym` can miss, while explicit `dlopen` of the ApplicationServices path works. `--disable-private` flag prototype ran. Fallback matcher (pid + frame (+ title)) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

From `./.claude/CLAUDE.md` (project) and `/Users/ken/dev/CLAUDE.md` (workspace):

- `PaneModel` and `PaneEngine` must not import AppKit (or Cocoa/SwiftUI/WebKit/Quartz/Carbon). This is enforced by `scripts/check-no-appkit.sh` and `NoAppKitTests`, which must keep passing. AppKit is allowed only in the new Mac/App targets.
- Each private API (`_AXUIElementGetWindow` here) lives in one file with a fallback and is loaded via `dlopen`/`dlsym`. Never use link-time private symbols (`@_silgen_name`, C headers, `-framework SkyLight`).
- Clean room: never open the `.dmg` in the repo root or any TrellisWM material. AeroSpace, yabai and Amethyst are MIT prior art (ideas only; write fresh code). Loop is GPL (read patterns, never copy).
- Swift 6 language mode, `swift-tools-version: 6.2`, macOS 14 floor. Avoid Swift 6.4-only syntax in shipped code. Swift Testing for tests. TDD with RED/GREEN commits; validate after every edit in all builds (CI runs debug **and** `swift test -c release -Xswiftc -enable-testing`; `NoAppKitTests.ciBuildsAndTestsInReleaseToo` asserts those workflow lines exist).
- App shell: AppKit `NSApplication` + `NSStatusItem` + `NSHostingController` windows. Don't use the SwiftUI `App`/`Settings`/`MenuBarExtra` lifecycle. No App Sandbox. Hardened runtime. Never ad-hoc sign.
- Logging: `os.Logger` per subsystem category. Redact window titles in logs (`WindowRef.description` already omits `titleHint`).
- Silent fallbacks (`or {}`) are forbidden: let it crash rather than corrupt. Chesterton's Fence before removing code. Three real examples before abstracting.
- Workflow: GSD. Phase work lives on a branch (main is protected; Phase 1 used `gsd/phase-01-layout-model`).
- Workspace CLAUDE.md: Python work uses a venv (not relevant here); prefer LSP for navigation; never `kill node.exe`.
- UAT that involves the browser uses dev-browser. Not applicable here: Phase 2 UAT is native macOS and manual per CONTEXT.

## Summary

Phase 2 has three parts. The first is a pure, headless core in `PaneEngine`: a classifier over a Codable window-attribute snapshot, the close-confirmation rules, tab-group tracking, minimum-size learning, coordinate conversion and the revised `WindowSystem` protocol. The second is an AppKit/AX layer in a new `PaneMac` library: per-app AX threads, `AXWindowSystem`, permission, displays, lock/sleep signals and the menu-bar shell. The third is a tiny `PanePrivate` target that `dlopen`s `_AXUIElementGetWindow`. XcodeGen wraps `PaneApp` (the main.swift entry point) plus the `PaneMac` product into a Developer-ID-signed `Pane.app`, so `swift test` stays headless. This is the AeroSpace layout: the `project.yml` compiles `Sources/<App>` and depends on a package library product.

This session's probes against a self-built fixture app changed several assumptions in the project research:
- `AXUIElementSetMessagingTimeout` on an element does **not** carry over to equal or child elements.
- `_AXUIElementGetWindow` is itself an IPC call that blocks on a frozen app.
- Native AppKit tabs appear in `AXWindows` as **only the selected tab**. The other tabs exist only in the CG window list, offscreen with identical bounds, and switching tabs changes which window ID AX lists.
- Minimised windows and hidden apps report subrole `AXDialog`.
- Finder's `AXWindows` includes the desktop as an `AXScrollArea`.
- A terminated app answers `kAXErrorCannotComplete`, not `kAXErrorInvalidUIElement`.
- A closed window answers `-25202` and leaves the CG list.

These facts drive the classifier, the close table and tab tracking below.

Two Swift 6 traps were also verified. Under `.defaultIsolation(MainActor.self)`, the per-app thread class silently becomes MainActor-isolated and fails to compile until it is declared `nonisolated`. A class conforming to the `Sendable` `WindowSystem` protocol is *not* implicitly MainActor and must be marked `@MainActor` explicitly. The verified skeletons below compile warning-free under the planned settings.

**Primary recommendation:** Put every decision in pure `PaneEngine` types that take value snapshots. Use the AX layer only to capture snapshots and execute commands on per-app threads. Then 80%+ of WIN-02..09 and SAFE-05 are unit-tested against `FakeWindowSystem`. A fixture app drives the trusted integration suite and automates the `kill -STOP`, minimum-size, tab and close checks.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Window classification (dockable / never-dock / not-a-window) | PaneEngine (pure) | PaneMac (snapshot capture) | Pure function over a Codable snapshot, so the dump corpus tests it headless |
| Close confirmation, lifecycle mapping to `WindowState` | PaneEngine (pure) | PaneMac (gathers AX + CG + NSWorkspace facts) | A decision table over facts; must be exhaustively unit-tested |
| Native tab grouping | PaneEngine (`TabGroupTracker`) | PaneMac (AXTabGroup count + CG offscreen siblings) | Identity rebinding is logic, not I/O |
| Minimum-size learning | PaneEngine (`MinimumSizeLearner`) | PaneMac (persist per-bundle hints JSON) | Pure rule (actual > requested + tolerance); file I/O at the edge |
| Coordinate conversion AppKit ↔ global top-left | PaneEngine (pure math on `Rect`) | PaneMac (feeds `NSScreen` values) | One tested boundary; no AppKit import needed for the math |
| AX reads/writes/observers per app | PaneMac (`AXAppThread`) | — | Thread-confined CF objects; never on main |
| `_AXUIElementGetWindow` + capability registry | PanePrivate | PaneMac (fallback matcher caller) | One file per private API, `dlopen`/`dlsym` |
| Second-source window list | PaneMac (`CGWindowListCopyWindowInfo`) | — | Public API, about 4 ms per full call; SkyLight is not needed in Phase 2 |
| Permission state + stale detection | PaneEngine (state reducer) | PaneMac (probe, `tccutil`, System Settings link, onboarding UI) | Reducer testable; side effects at the edge |
| Lock/sleep/wake pause + refresh | PaneMac (signal collection) | PaneEngine (pause/resume policy) | OS notifications are AppKit/Foundation; policy is pure |
| Exclusion list | PaneMac (UserDefaults store, menu) | PaneEngine/AXWindowSystem (command filter) | Store at the edge; enforcement where commands execute |
| World lifecycle sync (`World.apply`, undo re-query) | PaneEngine (`LifecycleSync`) | — | Phase 1 contract owner |
| Menu bar, onboarding, debug window list | PaneMac/PaneApp (AppKit + `NSHostingController`) | — | UI only |
| Signed `.app` bundle | XcodeGen `xcode/project.yml` + xcodebuild | — | Info.plist, entitlements and signing need a real bundle |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ApplicationServices / HIServices (AX) | macOS 27 SDK, deploy 14 | Enumerate, observe, move and resize windows | The only public API for other processes' windows. Constants verified in SDK headers this session [VERIFIED: SDK AXRoleConstants.h / AXAttributeConstants.h / AXError.h] |
| CoreGraphics `CGWindowListCopyWindowInfo` | system | Second close source; window layer/bounds/onscreen; fallback ID matching | Public, about 3.6–4.0 ms per full `.optionAll` call measured locally [VERIFIED: local probe] |
| `CGDisplayCreateUUIDFromDisplayID`, `CGDisplayBounds` | system | Display UUID keys; top-left display frames | Returned UUID `37D8832A-…` and bounds `(0,0,1710,1112)` locally [VERIFIED: local probe] |
| AppKit (`NSStatusItem`, `NSWorkspace`, `NSScreen`, `NSRunningApplication`) | system | Menu bar shell, app lifecycle notifications, screens | Project-mandated shell [CITED: .planning/research/STACK.md] |
| SwiftUI via `NSHostingController` | system | Onboarding window and debug window list only | Allowed by STACK.md; avoid the SwiftUI App lifecycle |
| `os` (`Logger`, `OSAllocatedUnfairLock`) | macOS 13+ | Logging; locks shared between main and AX threads | `Mutex` (Synchronization) is macOS 15+ only and fails at the 14 floor [VERIFIED: swiftc -target macos14 typecheck] |
| Swift Testing | toolchain (Testing Library 2084 locally) | All tests; `.enabled(if:)` trait for trusted-only suites | Already used by Phase 1 [VERIFIED: local swift test run] |
| XcodeGen | 2.46.0 (2026-07-16) | Generate `xcode/Pane.xcodeproj` from `project.yml` | AeroSpace's exact pattern [VERIFIED: gh api yonaskolb/XcodeGen releases/latest; brew info shows 2.46.0, not installed] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `/usr/bin/tccutil` | system | "Reset permission" button | Run via `Process` with fixed argv `["reset", "Accessibility", bundleID]`. Exits 64 with OSStatus -10814 if the bundle ID isn't known to LaunchServices [VERIFIED: local run] |
| xcbeautify | 3.2.1 | Readable xcodebuild logs | Optional. Not installed locally; pipe through it only if present |

No new SwiftPM dependencies in Phase 2. Sparkle and KeyboardShortcuts aren't needed until later phases.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CG window list as second source | SkyLight `SLSWindowQueryWindows` | Private and adds a second private-API surface. CG with `.optionAll` already lists offscreen, hidden-tab and frozen-app windows [VERIFIED]. Defer SkyLight to Phase 6 |
| Thread + CFRunLoop per app | Custom actor executor (SE-0392) | Unproven with AXObserver run-loop sources. Keep Thread + `CFRunLoopPerformBlock`, wrapped in an async API [CITED: ARCHITECTURE.md Pattern 4] |
| `CFRunLoopPerformBlock` + `CFRunLoopWakeUp` | `NSObject.perform(_:on:with:waitUntilDone:)` (AeroSpace) | Both work. The block form compiled clean under Swift 6 and needs no `@objc` box [VERIFIED: scratch package build] |
| Fixture-locating via `--test-bundle-path` argument | `Bundle.allBundles` / `Bundle(for:)` | `Bundle.allBundles` had no `.xctest` under `swiftpm-testing-helper` [VERIFIED: local probe] |

**Installation (dev tool only):**
```bash
brew install xcodegen   # 2.46.0; writes to /opt/homebrew, needs developer OK (checkpoint)
```

**Version verification:** `brew info --json=v2 xcodegen` → `2.46.0`, installed `[]` [VERIFIED]. GitHub latest release `2.46.0 2026-07-16T06:43:31Z` [VERIFIED: gh api].

## Package Legitimacy Audit

This phase adds no SwiftPM, npm, PyPI or crates packages. The only external tool is a Homebrew formula. The `package-legitimacy` seam covers npm/pypi/crates only, so it doesn't apply here.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| xcodegen | Homebrew (formula) | Project since 2017; 2.46.0 released 2026-07-16 | n/a (brew) | github.com/yonaskolb/XcodeGen | n/a (seam doesn't cover brew); repo and release confirmed via `gh api` | Approved. Install behind a `checkpoint:human-verify`, since it modifies /opt/homebrew |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 NSWorkspace (launch/terminate/activate/hide)   Distributed/NSWorkspace lock+sleep+wake   Screen params change
            │                                             │                                    │
            ▼                                             ▼                                    ▼
 ┌──────────────────────── PaneMac (AppKit, @MainActor) ────────────────────────────────────────────────┐
 │  AppRegistry ──spawns/stops──▶ AXAppThread[pid] ×N  (Thread + CFRunLoop, AX objects confined)        │
 │       ▲                           │  AXObserver callbacks ──▶ hint(pid, notif) ──┐                   │
 │       │                           │  jobs: snapshot / setFrame(latest-wins) / probe                 │
 │       │                           ▼                                              ▼                   │
 │  SessionGate (locked/asleep?) ◀── WindowSnapshot[] + AXErr facts      RefreshScheduler (debounce,   │
 │       │ pauses                     │                                   cancel-latest per pid)        │
 │       ▼                            ▼                                                                 │
 │  CGWindowList (4 ms, all IDs/bounds/layer/onscreen)  ─────▶  AXWindowSystem (implements WindowSystem)│
 │  Displays (CGDisplayBounds + UUID; NSScreen visibleFrame ─▶ Coordinates)    │  ▲ perform(commands)   │
 │  PanePrivate.AXWindowID (dlopen) or FallbackMatcher (pid+frame(+title))     │  │ (excluded → drop)   │
 └─────────────────────────────────────────────────────────────────────────────┼──┼─────────────────────┘
                                                                               │  │
         ┌──────────────────────── PaneEngine (pure, no AppKit) ───────────────▼──┴────────────────────┐
         │ Classifier(snapshot) → dockable | neverDock(reason) | notAWindow                            │
         │ TabGroupTracker(visible windows + CG offscreen siblings) → stable group refs                │
         │ CloseRule(axFact, cgFact, appFact, sessionGate) → keep | absent | closed                     │
         │ MinimumSizeLearner(requested, actual) → learned min    PermissionReducer(probe facts) → UI  │
         │ LifecycleSync: WindowEvent → World.apply(state)  ;  World.undo revived → re-query → apply   │
         └──────────────────────────────────────────────────────────────────────────────────────────────┘
                                                        │
                                       Debug menu UI (window list, nudge, freeze test, exclude toggle)
```

### Recommended Project Structure

```
Package.swift                       # add products PaneMac (library, for XcodeGen); targets below
Sources/
├── PaneModel/                      # unchanged
├── PaneEngine/                     # stays Foundation-only (no defaultIsolation change)
│   ├── WindowSystem.swift          # revised protocol + value types
│   ├── WindowSnapshot.swift        # Codable attribute snapshot (live + corpus share it)
│   ├── Classifier.swift            # pure rules + per-bundle override table
│   ├── TabGroupTracker.swift
│   ├── CloseRule.swift             # decision table
│   ├── MinimumSizeLearner.swift
│   ├── Coordinates.swift           # AppKit bottom-left <-> global top-left
│   ├── PermissionReducer.swift
│   └── LifecycleSync.swift         # World.apply wiring + undo re-query obligation
├── PanePrivate/                    # nonisolated; one file per private API
│   ├── AXWindowID.swift            # _AXUIElementGetWindow via dlopen/dlsym
│   └── Capabilities.swift          # registry + --disable-private parsing
├── PaneMac/                        # AppKit; .defaultIsolation(MainActor.self)
│   ├── AX/AXAppThread.swift        # `nonisolated final class`
│   ├── AX/AXSnapshotReader.swift   # AXUIElement -> WindowSnapshot (shared with pane-dump)
│   ├── AX/AppRegistry.swift
│   ├── AXWindowSystem.swift        # `@MainActor final class`
│   ├── CGWindowList.swift
│   ├── Displays.swift
│   ├── FallbackMatcher.swift
│   ├── SessionGate.swift           # lock/sleep/wake signals
│   ├── Permission/                 # probe, tccutil runner, onboarding view
│   ├── Exclusions.swift            # UserDefaults
│   ├── MinimumHintsStore.swift     # ~/Library/Application Support/Pane/min-size-hints.json
│   └── Shell/                      # status item, debug menu, window list
├── PaneApp/main.swift              # executableTarget; compiled by XcodeGen too (AeroSpace pattern)
├── pane-dump/main.swift            # executableTarget; records corpus fixtures
└── PaneFixtureApp/main.swift       # executableTarget; test fixture windows (tabs, sheet, panel, minSize)
Tests/
├── PaneModelTests/                 # unchanged
├── PaneEngineTests/                # classifier corpus, close table, tabs, learner, coords, Fake scenarios
│   └── Fixtures/AXDumps/*.json     # committed, redacted corpus (located via #filePath like NoAppKitTests)
├── PaneTestSupport/  (Sources/…)   # FakeWindowSystem (library target, `actor`)
└── PaneMacIntegrationTests/        # .enabled(if: AXIsProcessTrusted()); launches PaneFixtureApp
xcode/project.yml                   # generated xcode/Pane.xcodeproj is gitignored
scripts/generate.sh, scripts/run-debug.sh
```

Put `PaneTestSupport` under `Sources/` as a plain `.target`, so both `PaneEngineTests` and later phases' tests can depend on it. A test target can't be a dependency.

### Pattern 1: Per-app AX thread (verified skeleton)

**What:** One `Thread` per pid with its own `CFRunLoop`. AX elements and observers are created, used and destroyed only on it. Main sends work with `CFRunLoopPerformBlock` + `CFRunLoopWakeUp` and awaits a continuation.
**When to use:** All AX traffic, *including* `_AXUIElementGetWindow`. It is IPC and blocked for the full timeout on a frozen app [VERIFIED: probe, `frozen gw: 0.51s err -25204`].
**Rules:**
- Mark the class `nonisolated`. Under `.defaultIsolation(MainActor.self)` it otherwise becomes MainActor and fails with "main actor-isolated property … can not be referenced from a nonisolated context" [VERIFIED: scratch build error, then clean build after `nonisolated final class`].
- `AXUIElement`, `AXObserver` and `CFRunLoop` are **not Sendable** in the macOS 27 SDK [VERIFIED: `needsSendable` typecheck errors]. Keep them as thread-confined stored properties of an `@unchecked Sendable` class, and only cross threads with Sendable values (IDs, snapshots, rects).
- Set the **global** timeout once: `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)`. A per-element timeout applies to that element object only, not to equal or child elements [CITED: SDK AXUIElement.h "sets it only for that object, not for other accessibility objects that are equal to it"] [VERIFIED: element with 0.3 s → 0.33 s; fresh equal element → 1.50 s; after global 0.5 → 0.51 s]. Per-app tuning is optional on top.
- Never send AX to Pane's own pid. AeroSpace notes these requests crash [CITED: AeroSpace MacApp.swift "AX requests crash if you send them to yourself"]. Skip `com.apple.loginwindow` [CITED: AeroSpace `lockScreenAppBundleId = "com.apple.loginwindow"`].
- Tear down on the thread in reverse creation order: observers → window elements → app element. Use the refcon as an `Unmanaged` pointer to the thread object, which outlives its observers (Pitfall 17 in PITFALLS.md).

```swift
// Source: scratch prototype compiled warning-free with tools 6.2, Swift 6, defaultIsolation(MainActor),
// NonisolatedNonsendingByDefault, InferIsolatedConformances (this session).
nonisolated struct AXEventHint: Sendable { let pid: pid_t; let windowID: CGWindowID?; let notification: String }

nonisolated final class AXAppThread: @unchecked Sendable {
    let pid: pid_t
    private let hints: AsyncStream<AXEventHint>.Continuation
    private var runLoop: CFRunLoop?          // set on the thread before `ready` signals
    private let ready = DispatchSemaphore(value: 0)
    private var app: AXUIElement?            // thread-confined
    private var observer: AXObserver?        // thread-confined

    init(pid: pid_t, hints: AsyncStream<AXEventHint>.Continuation) {
        self.pid = pid; self.hints = hints
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            app = AXUIElementCreateApplication(pid)
            installObserver()
            ready.signal()
            var ctx = CFRunLoopSourceContext()                       // keeps the loop alive
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFRunLoopSourceCreate(nil, 0, &ctx), .defaultMode)
            CFRunLoopRun()
            if let observer { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode) }
            observer = nil; app = nil                                // reverse order
        }
        thread.name = "AXAppThread \(pid)"
        thread.start()
        ready.wait()
    }

    private func installObserver() {
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<AXAppThread>.fromOpaque(refcon).takeUnretainedValue()
            me.hints.yield(AXEventHint(pid: me.pid, windowID: nil, notification: notification as String))
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs, let app else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            _ = AXObserverAddNotification(obs, app, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }

    func perform<T: Sendable>(_ body: @escaping @Sendable (AXUIElement) -> T) async -> T? {
        await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            guard let runLoop else { cont.resume(returning: nil); return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in cont.resume(returning: app.map(body)) }
            CFRunLoopWakeUp(runLoop)
        }
    }

    func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
        CFRunLoopWakeUp(runLoop)
    }
}
```

The executor must add cancellation (a job token checked between AX calls, as AeroSpace's `RunLoopJob` does [CITED: AeroSpace runLoop.swift]) and per-window latest-wins frame slots (Pattern 5). Register per-window notifications (`kAXUIElementDestroyedNotification`, `kAXWindowMovedNotification`, `kAXWindowResizedNotification`, `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification`, `kAXTitleChangedNotification`) when a window is registered [VERIFIED: constants in AXNotificationConstants.h]. Treat every notification as a hint only.

**Unresponsiveness tracker (discretion, recommended values):**
- Mark an app *degraded* after 2 consecutive `kAXErrorCannotComplete` (-25204) results, or after one job that exceeds 1.5 s.
- While degraded, skip its refreshes, keep only the latest frame per window, and probe its app element's `AXRole` every 2 s.
- The first success marks it recovered and flushes the latest frames.
- Emit a `.appResponsiveness(pid:degraded:)` event so the UI and later the Planner can see it.

### Pattern 2: Snapshot + pure classifier + recorded corpus

**What:** `AXSnapshotReader` (PaneMac) builds a Codable `WindowSnapshot` from one `AXUIElementCopyMultipleAttributeValues` call plus the CG entry for the window. `Classifier.classify(_:overrides:)` (PaneEngine) is a pure function over that struct. `pane-dump` writes the *same* struct (redacted) as JSON fixtures, so corpus tests exercise exactly the live input. This mirrors AeroSpace's design, where a mock protocol is implemented by both live elements and JSON dicts and checked against `axDumps/*.json5` [CITED: AeroSpace AxUiElementWindowTypeTest.swift]. Pane uses one concrete Codable struct instead of a mock protocol, which is simpler.

**Verified AX facts the classifier must encode:**

| Observation | Evidence |
|---|---|
| Finder's `AXWindows` includes the desktop: role `AXScrollArea`, no subrole, no buttons, `_AXUIElementGetWindow` → -25201 | [VERIFIED: local dump of com.apple.finder] |
| Standard AppKit window: `AXWindow`/`AXStandardWindow`, close/min/zoom/fullscreen buttons present and enabled, CG layer 0 | [VERIFIED: fixture] |
| Borderless window at `.floating` level: `AXWindow`/`AXUnknown`, no buttons, CG layer 3 | [VERIFIED: fixture] |
| `collectionBehavior = .fullScreenNone`: `AXStandardWindow`, zoom present, **no** `AXFullScreenButton` | [VERIFIED: fixture] |
| Sheet: **not** in `AXWindows`. It is an `AXSheet` child of its host, but **is** a separate layer-0 onscreen CG window. The host's close button is disabled while the sheet is up | [VERIFIED: fixture] |
| Floating utility `NSPanel` of an inactive app: absent from `AXWindows`, CG layer 3, offscreen | [VERIFIED: fixture] |
| Minimised window stays in `AXWindows` with `AXMinimized=1` and subrole flips to **`AXDialog`** | [VERIFIED: fixture] |
| Hidden app: every window reports subrole **`AXDialog`**, app `AXHidden=1`, all CG entries offscreen | [VERIFIED: fixture] |
| Chrome PiP: subrole **`AXStandardWindow`**, no close/min/zoom/fullscreen buttons, window level always-on-top | [CITED: AeroSpace axDumps/chrome_pip.json5] |
| Firefox PiP lacks a minimise button; Ghostty quick terminal has `AXIdentifier` `com.mitchellh.ghostty.quickTerminal`; Xcode Open Quickly has `AXIdentifier` `open_quickly` | [CITED: AeroSpace AxUiElementWindowType.swift] |
| Terminals and editors that hide decorations (iTerm2, Alacritty, kitty, WezTerm, Emacs, VS Code with `nativeFullScreen:false`), Activity Monitor, GIMP, Steam and Chrome (tab drag-out race) lack an enabled fullscreen button and need overrides | [CITED: AeroSpace AxUiElementWindowType.swift] |
| Batched read of 14 attributes: 0.08 ms vs 0.29 ms for single reads. A missing attribute comes back as an `AXValue` of type `kAXValueAXErrorType` (`error:-25205`) | [VERIFIED: local perf probe] |

**Recommended rule order (Pane's own; tune with the corpus):**
1. `role != "AXWindow"` → `.notAWindow` (never tracked; e.g. the Finder desktop).
2. Snapshot captured while `minimized` or app `hidden` → **don't classify**; keep the previous classification (subrole lies in those states).
3. CG layer ≠ 0 → `.neverDock(.floatingLevel)` (PiP, floating panels, HUDs).
4. `subrole != "AXStandardWindow"` → `.neverDock(.subrole)` (`AXDialog`, `AXSystemDialog`, `AXFloatingWindow`, `AXSystemFloatingWindow`, `AXUnknown`).
5. `modal == true` → `.neverDock(.modal)`.
6. No close button → `.neverDock(.noCloseButton)` (Chrome PiP, popups).
7. Fullscreen button absent or disabled, and bundle not in the override set → `.neverDock(.noFullscreenButton)` (AeroSpace's "not designed to be big" heuristic: System Settings, Calculator, About This Mac).
8. Otherwise `.dockable`.

Classify after a settle delay (recommended 250 ms after creation), because titles and buttons arrive late [CITED: PITFALLS.md Pitfall 7]. Re-classify only on `kAXTitleChanged` or subrole change while visible. Never re-classify because a sheet temporarily disabled the close button. The classification is sticky.

**Corpus fixture format (recommended):**
```json
{
  "schemaVersion": 1,
  "case": "finder_main_window",
  "capturedOn": { "macOS": "27.0.1", "appVersion": "…", "date": "2026-10-24" },
  "app": { "bundleID": "com.apple.finder", "activationPolicy": "regular", "hidden": false },
  "window": {
    "role": "AXWindow", "subrole": "AXStandardWindow", "modal": false, "main": true,
    "minimized": false, "fullScreen": false, "identifier": null,
    "title": { "redacted": true, "length": 9 },
    "buttons": { "close": {"present": true, "enabled": true}, "minimize": {"present": true, "enabled": true},
                 "zoom": {"present": true, "enabled": true}, "fullScreen": {"present": true, "enabled": true} },
    "tabGroup": { "present": true, "tabCount": 2 },
    "frame": { "x": 40, "y": 580, "width": 320, "height": 232 },
    "cg": { "layer": 0, "onScreen": true, "alpha": 1.0 }
  },
  "expected": { "kind": "dockable", "reason": null, "confirmedBy": "developer" }
}
```
Redaction: replace `AXTitle`, `AXDocument`, URLs, file paths and `AXDescription` with `{redacted, length}`. Keep `AXIdentifier` only if it matches an allow-list of developer identifiers (for example `open_quickly`), otherwise redact. Never record tab button titles. `expected` is set by the developer at capture time (`pane-dump --app com.apple.finder --label dockable`), never auto-filled from the current classifier.

### Pattern 3: Native tab groups (verified AppKit behaviour)

**Verified facts** for an AppKit fixture using `NSWindow.addTabbedWindow`:
- `AXWindows` lists **only the selected tab's window**. It has a child `AXTabGroup` whose `AXTabs` count is the number of tabs (children `AXRadioButton`/`AXTabButton`).
- The unselected tab's window is absent from AX but present in CG: `onscreen=0`, layer 0, bounds identical to the visible tab.
- Pressing tab 2 changed the listed ID (6711 → 6712). The old tab's cached element stayed **valid** (size read `0`, window ID still 6711).

[VERIFIED: fixture probes]

**Consequence:** with a naive tracker, every tab switch looks like "window 6711 vanished, window 6712 appeared". That is exactly the AeroSpace #68 / yabai #68 symptom [CITED: AeroSpace issue #68 maintainer: "macOS accessibility API reports tabs as windows"]. Amethyst handles it by swapping in a same-app window that recently left the screen [CITED: Amethyst WindowManager.swift `swapInTab`].

**Recommended design:** a pure `TabGroupTracker` (PaneEngine).
- **Group membership:** a visible window with `tabGroup.tabCount = N ≥ 2`, plus same-pid CG windows that are layer 0, offscreen and within ±1 pt of its bounds. Members are known once seen; hidden members that were never visible are CG-only (no AX element, no title).
- **Stable identity:** a group keeps the `WindowRef` of its first-seen visible member (the "leader"). `WindowInfo` gains `visibleMemberID`. Commands addressed to the group ref go to the visible member's AX element. The World never sees a tab switch, so no `World.edit` or `World.apply` churn.
- **Tab switch:** new visible ID X with an `AXTabGroup`, and the previous visible Y is now a CG-offscreen same-bounds sibling with a valid element → rebind `visibleMemberID = X`. Emit `.windowFocused(groupRef)`, not created or destroyed.
- **Close:** a member closes by the two-source rule (Pattern 4). The group closes only when its last member closes. If the leader member closes first, the group keeps the leader ref as its identity; document this for Phase 3/4, which map refs to CG IDs for snapshots.
- **Safari:** browser tabs (Safari, Chrome, Firefox) are drawn inside one window, so they're one AX window naturally [ASSUMED; confirm with the Safari corpus case]. Finder, Terminal, TextEdit, Ghostty and Xcode use AppKit window tabbing, so they should show the verified fixture behaviour [ASSUMED per app; the corpus confirms Finder and Terminal on this Mac. Ghostty and Xcode aren't installed for runtime UI capture, see Environment].

### Pattern 4: Two-source close rule + refresh strategy

**Verified signals:**

| Situation | AX on cached window element | `_AXUIElementGetWindow` | CG list (`.optionAll`) |
|---|---|---|---|
| Window closed, app alive | **-25202** `kAXErrorInvalidUIElement` | -25201 | **absent** |
| App frozen (`SIGSTOP`) | -25204 after timeout | -25204 after timeout | present |
| App killed | **-25204** (not -25202) | — | absent (after exit) |
| Hidden tab (tab switch) | success | success | present, offscreen |
| Minimised | success, `AXMinimized=1` | success | present |

[VERIFIED: close/freeze/term/tabs probes this session]

**Decision table (pure `CloseRule`):**

| Session gate | App state | AX fact | CG fact | Outcome |
|---|---|---|---|---|
| locked/asleep/waking | any | any | any | **no change** (queue for post-resume refresh) |
| active | terminated (NSWorkspace `didTerminateApplication` or `isTerminated`) | any | absent | `.closed` via `World.apply` |
| active | terminated | any | present | keep; recheck next refresh (WindowServer lag) |
| active | alive | -25202 invalid | absent | `.closed` |
| active | alive | -25202 invalid | present | keep (`.absent` if it's a known tab member); recheck |
| active | alive | -25204 timeout | any | **no change**; feed unresponsiveness tracker |
| active | alive | valid, `AXMinimized` or app hidden | any | `.absent` |
| active | alive | valid, `AXFullScreen=1` | any | `.fullscreen` |
| active | alive | valid, not in `AXWindows` | present | keep (hidden tab / other Space); never close |
| active | alive | valid | absent | keep; recheck (transient) |

Two more rules. Keep a short-lived closed-ID cache (for example 60 s), so an ID reused after unlock isn't mistaken for the old window [CITED: PITFALLS.md Pitfall 2; AeroSpace closedWindowsCache.swift exists]. And never close on `kAXUIElementDestroyedNotification` alone: it only schedules a refresh [CITED: ARCHITECTURE.md Anti-Pattern 3].

**Session gate signals (belt and braces; locked if any says locked):**
- `DistributedNotificationCenter` `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` [CITED: Chromium idle_mac.mm uses them; undocumented, MEDIUM]
- `NSWorkspace.shared.notificationCenter`: `willSleepNotification` / `didWakeNotification`, `screensDidSleepNotification` / `screensDidWakeNotification`, `sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` (fast user switching)
- Frontmost app `com.apple.loginwindow` [CITED: AeroSpace GlobalObserver/MacApp lock-screen guard]
- `CGSessionCopyCurrentDictionary()` key `CGSSessionScreenIsLocked`, polled at refresh time. While unlocked the dictionary lacks it [VERIFIED: keys listed while unlocked; the presence-when-locked part is ASSUMED]

After unlock or wake: wait 1.5 s of quiet (discretion), then run one full refresh of all apps.

**Refresh strategy (discretion, recommended):**
- AX notification or NSWorkspace event for a pid → that pid's refresh, debounced 75 ms and cancel-latest.
- Display change → 500 ms debounce, then re-read displays and refresh all.
- Periodic safety sweep every 5 s per app. It's cheap: one CG call is about 4 ms, plus a batched AX read per window.
- `inventory()` returns the **cached** model immediately and never awaits all apps. Freshness arrives as events. This avoids the AeroSpace #1615 "wait on all app threads" stall [CITED: PITFALLS.md Pitfall 1].

### Pattern 5: Frame write pipeline (latest-wins, read-back, learned minimums)

- **Coalescing:** keep a per-window pending-frame slot under an `OSAllocatedUnfairLock` (macOS 13+; `Mutex` is 15+ only [VERIFIED]). Enqueue overwrites the slot and schedules one drain block on the app thread if none is pending. The drain takes the latest value, which gives latest-wins with no cancellation bookkeeping.
- **Write order on the app thread:**
  1. Read app `AXEnhancedUserInterface`; if true, set it false.
  2. Write `AXSize`, then `AXPosition`, then `AXSize`, checking cancellation between steps.
  3. Read back `AXPosition` + `AXSize`.
  4. Restore `AXEnhancedUserInterface` if it was on.

  [CITED: AeroSpace MacApp.swift setFrame "Set size and then the position. The order is important" + enhancedUserInterface toggle]. Rectangle stopped re-enabling it for Chrome because of cost [CITED: PITFALLS.md Pitfall 6]. Make re-enable a per-bundle setting, default on.
- **Report:** emit `.frameApplied(ref, requested:, actual:)`.
- **Learning rule (pure `MinimumSizeLearner`):** on each axis, if `actual > requested + 2 pt`, then `learnedMin = max(old, actual)` on that axis. Verified example: request 100×80 → read back 250×150 on a window with `minSize` 250×150. The write itself returned `kAXErrorSuccess`, and `AXMinimumSize` is unsupported (-25205) [VERIFIED: freeze probe]. Ignore axes where `actual < requested` (cell-snapping terminals round down). Per-window minimums live in memory. Per-bundle hints use the max seen per bundle, persisted to JSON and validated on load (finite, ≥ 0, ≤ `Geometry.maxCoordinate`).
- **Fight budget:** at most 1 corrective re-plan per window per second [CITED: ARCHITECTURE.md Pattern 3].
- **Exclusions:** `perform` drops every command whose `bundleID` is excluded and logs it once. The window is still tracked (read-only) and `WindowInfo.isExcluded = true`.

### Pattern 6: Coordinates and displays

- Global space (AX, CG, `CGDisplayBounds`) has its origin at the top-left of the primary display, y down. AppKit has its origin at the bottom-left of the primary display, y up. The primary is `NSScreen.screens[0]` / `CGMainDisplayID()`.
- `DisplayInfo.frame`: use `CGDisplayBounds(id)`, which is already top-left. `visibleFrame`: convert `NSScreen.visibleFrame` with `y_top = H_primary − (y_ns + h)`.
- Locally: primary `CGDisplayBounds (0,0,1710,1112)` == `NSScreen.frame`, and `visibleFrame (0,0,1710,1074)` → top-left `(0, 38, 1710, 1074)`, i.e. a 38 pt menu bar [VERIFIED: probe values; conversion math ASSUMED-standard, unit-tested in plan].
- `DisplayInfo.uuid = CFUUIDCreateString(CGDisplayCreateUUIDFromDisplayID(id))`, where `id` comes from `NSScreen.deviceDescription["NSScreenNumber"]` [VERIFIED: probe]. `CGDirectDisplayID` isn't durable [CITED: PITFALLS.md Pitfall 14].
- A window's display is the one with the largest intersection; ties and none go to the nearest display centre.
- `currentSpaceID` stays `nil` in Phase 2 (SkyLight is Phase 6).

Test vectors for `Coordinates` (pure, headless):
- primary 1710×1112 at the origin
- external 1920×1080 **above** (NS y = 1112 → top-left y = −1080)
- **left** (NS x = −1920 → x = −1920, y unchanged)
- **below** with a negative NS y
- round-trip `toAppKit(fromAppKit(r)) == r`

### Pattern 7: Permission state machine + stale detection

States: `notTrusted → waitingForGrant → trusted → probing → ready | staleTrustedButFailing | staleNotTrustedButEnabled`.

- On first run, call `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])`. Use the string literal: referencing the global `kAXTrustedCheckOptionPrompt` is a Swift 6 **error** ("reference to var … is not concurrency-safe"), and its value is `AXTrustedCheckOptionPrompt` [VERIFIED: typecheck + printed value]. This registers Pane in the list.
- The "Open System Settings" button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` [CITED: Rectangle AccessibilityView.swift uses this URL].
- Poll with a `@MainActor` `Task` loop (`try await Task.sleep(for: .seconds(1))`) calling `AXIsProcessTrusted()`. This avoids `Timer`'s `@Sendable` closure friction.
- **Probe** once trusted:
  - On a background thread, read `kAXRoleAttribute` of a known app element (Finder via `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")`), never Pane's own pid.
  - `kAXErrorAPIDisabled` (-25211) → **stale (trusted but failing)**.
  - `-25204` → inconclusive; retry 3× then try the frontmost regular app.
  - Don't use the system-wide `kAXFocusedApplicationAttribute`. It returned -25204 here even though trusted [VERIFIED: probe; cause unknown, see Open Questions].
- **Stale form B:** the toggle shows on, but `AXIsProcessTrusted()` stays false. This is Loop #418 and Amethyst #1856: re-signing or an update changed the designated requirement [CITED: gh issue views]. Pane can't read TCC.db without Full Disk Access. After the user has visited Settings and 15 s pass without trust, show "Already enabled? The entry is stale" with **Reset permission**.
- **Reset permission:** run `/usr/bin/tccutil reset Accessibility <Bundle.main.bundleIdentifier>` through `Process`. Check the exit status (64 = unknown bundle ID [VERIFIED]). Then re-prompt with `AXIsProcessTrustedWithOptions` and go back to `waitingForGrant`.
- **Why Developer ID survives rebuilds:** TCC records the app's designated requirement. Ad-hoc code "has a DR but it's tied to that specific version", while a certificate DR checks the signer (Team ID) plus the identifier [CITED: Apple TN3127]. Verify with `codesign -d -r- "Pane Debug.app"`. It must contain `identifier "com.eightabyte.pane.debug"` and `S2K7P43927`.

### Pattern 8: PanePrivate (verified loading)

```swift
// Source: verified this session (resolves on macOS 27.0.1; nil with --disable-private=AXWindowID).
import ApplicationServices
import Darwin

public enum AXWindowID {
    public typealias Fn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    public static let function: Fn? = {
        guard !Capabilities.isForcedOff(.axWindowID) else { return nil }
        // RTLD_DEFAULT isn't importable in Swift, and default-handle lookup misses when HIServices isn't loaded yet.
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let sym = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: Fn.self)
    }()
}
```
- `RTLD_DEFAULT` → "cannot find 'RTLD_DEFAULT' in scope". `dlsym(UnsafeMutableRawPointer(bitPattern: -2), …)` returned **nil** in a binary that doesn't link AX. Explicit `dlopen` of the umbrella path returned a handle and the symbol, and a bogus symbol returned nil [VERIFIED: rtld/dl probes].
- `static let` of an optional `@convention(c)` function pointer compiles in Swift 6 with no isolation annotations [VERIFIED].
- `Capabilities`:
  - `enum Capability: String, CaseIterable { case axWindowID = "AXWindowID" }`.
  - `isForcedOff` parses `CommandLine.arguments` for `--disable-private=<name>`; accept a comma list.
  - `report() -> [Capability: Bool]` is logged at launch with `Logger(subsystem: "com.eightabyte.pane", category: "private")`.
  - **Call-time degradation:** if the function exists but fails for windows whose AX reads succeed (beyond the expected -25201 for non-windows), count failures and switch that capability to fallback for the session.
- **FallbackMatcher** (used when `AXWindowID.function == nil`):
  1. Match the AX window to the same-pid CG entry with equal bounds (±1 pt). AX and CG frames matched exactly in the fixture: AX `(40,580) 320×232` ↔ CG `X=40,Y=580,W=320,H=232` [VERIFIED].
  2. Prefer `onscreen` and layer 0.
  3. Use the title only when `kCGWindowName` is non-empty, which needs Screen Recording [CITED: PITFALLS.md Pitfall 10].
  4. If still ambiguous (identical frames, e.g. hidden tabs are offscreen), pick the onscreen one. If that's ambiguous too, assign a synthetic session ID from a reserved high range (recommended `0xF000_0000 | counter`) and confirm closes by AX-invalid plus "no same-pid CG window with those bounds".

### Anti-Patterns to Avoid
- **Calling `_AXUIElementGetWindow` on main or in an observer hop:** it blocks on frozen apps. Resolve it once on the app thread at registration and cache it.
- **Classifying minimised or hidden windows:** they report `AXDialog` and would be demoted to never-dock.
- **Tracking CG-only windows:** sheets and hidden tabs exist only in CG. Track only windows that appear in `AXWindows` with role `AXWindow`.
- **Treating -25204 from a dead app as "alive and slow" forever:** app death comes from NSWorkspace termination plus CG absence.
- **Changing `PaneEngine` to `.defaultIsolation(MainActor.self)` now:** it would make Phase 1's public value types MainActor-isolated. Keep PaneEngine nonisolated and mark the few engine classes `@MainActor` explicitly.
- **Launching the app binary directly from a terminal for permission UAT:** TCC attributes it to the terminal (Pitfall 9).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Xcode project for signing/Info.plist/entitlements | Hand-written `.pbxproj` or a bundle-assembly script | XcodeGen `project.yml` + `xcodebuild` | Signing settings, hardened runtime and generated Info.plist keys (`INFOPLIST_KEY_LSUIElement`) are standard Xcode settings [VERIFIED: names present in Xcode 27.1 CoreBuildSystem.xcspec] |
| Locks shared with AX threads | Spin flags, `OSAtomicCompareAndSwap` (AeroSpace uses deprecated atomics) | `OSAllocatedUnfairLock` | macOS 13+, Swift-safe `withLock` [VERIFIED: typecheck at macOS 14] |
| Second window source | SkyLight queries | `CGWindowListCopyWindowInfo(.optionAll)` | Public, about 4 ms, includes offscreen/hidden-tab/frozen windows [VERIFIED] |
| Display identity | Index or `CGDirectDisplayID` keys | `CGDisplayCreateUUIDFromDisplayID` | Durable [CITED: PITFALLS.md Pitfall 14] |
| TCC reset | Editing TCC.db | `/usr/bin/tccutil reset Accessibility <id>` | TCC.db is SIP/FDA-protected; tccutil is the supported tool [VERIFIED: man page + run] |
| Many single attribute reads | Loop of `AXUIElementCopyAttributeValue` | `AXUIElementCopyMultipleAttributeValues` | 3.6× faster per snapshot (0.08 vs 0.29 ms) [VERIFIED] |
| AX wrapper library | AXSwift / Silica | Own thin wrapper | No Swift 6 concurrency; unmaintained [CITED: STACK.md] |

**Key insight:** every AX result is a fact with a time and an error code. Wrappers that collapse errors into `nil` (AeroSpace-style `get(attr)`) lose the -25202 vs -25204 distinction that WIN-09 depends on. Pane's reader must return `Result<Value, AXError>` per attribute.

## Common Pitfalls

### Pitfall 1: Per-element timeouts that don't apply where you think
**What goes wrong:** `AXUIElementSetMessagingTimeout(appElement, 1.0)` is set, but window elements copied from `AXWindows` still use the global default, so a frozen app blocks the app thread longer than expected.
**Why:** the timeout is per element object, not per equal element [CITED: SDK header; VERIFIED: 0.33 s vs 1.50 s].
**How to avoid:** set the system-wide timeout once at launch (1.0 s); optionally set it again on each window element at registration.
**Warning signs:** `-25204` arriving after more than 1.2 s in logs.

### Pitfall 2: Tab switches look like close + open
**What goes wrong:** ghost tiles, or new tiles on every Finder/Terminal tab click.
**Why:** AX swaps which window ID it lists; the hidden tab's element stays valid [VERIFIED].
**How to avoid:** `TabGroupTracker` (Pattern 3) plus the two-source close rule.
**Warning signs:** a `windowCreated` within 100 ms of a same-pid same-frame window going CG-offscreen.

### Pitfall 3: Subrole lies for minimised/hidden windows
**What goes wrong:** a dockable window becomes never-dock after the user minimises it or hides its app.
**Why:** macOS reports `AXDialog` in those states [VERIFIED; CITED: AeroSpace "Minimized windows or windows of a hidden app have subrole AXDialog"].
**How to avoid:** skip classification while `minimized` or app `hidden`; classification is sticky.

### Pitfall 4: Swift 6 isolation traps in AX code
**What goes wrong:** compile errors, or worse, code silently hopping to main.
**Why:** `.defaultIsolation(MainActor.self)` makes thread classes MainActor. `Sendable`-protocol conformers are excluded from default isolation (error "stored property … of 'Sendable'-conforming class is mutable"). `kAXTrustedCheckOptionPrompt` is a global `var`. `AXUIElement`/`AXObserver`/`CFRunLoop` aren't Sendable [VERIFIED: all four this session].
**How to avoid:**
- `nonisolated final class AXAppThread: @unchecked Sendable`
- `@MainActor public final class AXWindowSystem: WindowSystem` with `public nonisolated let events`
- `public actor FakeWindowSystem: WindowSystem` with `nonisolated let events`
- literal `"AXTrustedCheckOptionPrompt"`

[VERIFIED: compiled + test passed]

### Pitfall 5: `dlsym` default handle misses
**What goes wrong:** the capability reports "unavailable" on a Mac where the symbol exists, so fallback runs needlessly.
**Why:** `RTLD_DEFAULT` isn't importable, and `(void*)-2` only searches loaded images [VERIFIED].
**How to avoid:** explicit `dlopen` of the ApplicationServices umbrella path (Pattern 8).

### Pitfall 6: Corpus that tests the classifier against itself
**What goes wrong:** fixtures record the classifier's current output as "expected", so regressions are baked in.
**How to avoid:** `pane-dump` requires an explicit `--label` and a `confirmedBy`. Corpus tests compare against the label. A new case with a wrong label is a review item, not an auto-update.

### Pitfall 7: Lock/sleep blanking treated as closure
**What goes wrong:** the layout is wiped on unlock.
**Why:** AX and `_AXUIElementGetWindow` fail while locked, and IDs can be reused after unlock [CITED: PITFALLS.md Pitfall 2; AeroSpace #445/#771].
**How to avoid:** the session gate pauses `CloseRule`; full refresh after 1.5 s of quiet; closed-ID cache.

### Pitfall 8: "Freeze test" leaving an app stopped
**What goes wrong:** the debug menu `SIGSTOP`s an app and Pane crashes before `SIGCONT`, so the user's app looks hung forever.
**How to avoid:**
- Write the pid to UserDefaults before stopping, and `SIGCONT` any recorded pid at launch.
- Auto-resume after a fixed time (for example 10 s).
- Refuse Pane's own pid, `loginwindow`, `Finder`, `Dock` and `SystemUIServer`.
- Prefer freezing a `PaneFixtureApp` instance in tests.

### Pitfall 9: Responsible-process TCC attribution
**What goes wrong:** the permission flow "works" in testing because the terminal is trusted. Locally, scratch binaries run from this shell reported `AXIsProcessTrusted() == true` with no grant of their own [VERIFIED].
**How to avoid:** permission UAT always launches through LaunchServices: `open -n "…/Pane Debug.app"`. Integration tests may rely on the terminal's trust; that's intended.

### Pitfall 10: Tracking Finder's desktop and other non-windows
**What goes wrong:** a giant phantom "window" appears in the list.
**Why:** Finder's `AXWindows` contains the desktop `AXScrollArea` [VERIFIED].
**How to avoid:** classifier rule 1 (`role == "AXWindow"`).

### Pitfall 11: Running AX before an app finishes launching / policy changes later
**What goes wrong:** missed windows, or slow first calls.
**How to avoid:** register an app thread when `NSRunningApplication.isFinishedLaunching` and `activationPolicy == .regular`; re-check policy on every activation and on each periodic sweep [ASSUMED: standard practice; AeroSpace re-registers on refresh].

## Code Examples

### WindowSystem conformances (verified compile + test)
```swift
// Source: scratch package pkg2 (copied PaneModel + current WindowSystem.swift); swift test passed this session.
@MainActor public final class AXWindowSystem: WindowSystem {          // explicit @MainActor is required
    public nonisolated let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation
    private var cache: [WindowIdentity: WindowInfo] = [:]
    public init() { (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1024)) }
    public func inventory() async -> WindowInventory { WindowInventory(displays: [], windows: Array(cache.values)) }
    public func perform(_ commands: [WindowCommand]) async { /* route to AXAppThreads */ }
}

public actor FakeWindowSystem: WindowSystem {                          // Sources/PaneTestSupport
    public nonisolated let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation
    public private(set) var performed: [WindowCommand] = []
    private var windows: [WindowIdentity: WindowInfo] = [:]
    public init() { (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded) }
    public func inventory() async -> WindowInventory { WindowInventory(displays: [], windows: windows.values.sorted { $0.window.identity < $1.window.identity }) }
    public func perform(_ commands: [WindowCommand]) async { performed += commands }
    public func open(_ info: WindowInfo) { windows[info.window.identity] = info; continuation.yield(.windowCreated(info)) }
}
```

### Current protocol and values Phase 2 builds on (verbatim)
[VERIFIED: Sources/PaneEngine/WindowSystem.swift:46-55, 60-64, 72-75]
```swift
    case windowCreated(WindowInfo)
    case windowDestroyed(WindowRef)
    case windowMoved(WindowRef, Rect)
    case windowResized(WindowRef, Rect)
    case windowFocused(WindowRef)
    case windowStateChanged(WindowRef, WindowState)
    case appLaunched(pid: Int32, bundleID: String)
    case appTerminated(pid: Int32)
    case displaysChanged
    case spaceChanged(displayUUID: String, spaceID: UInt64?)
...
    case setFrame(WindowRef, Rect)
    case park(WindowRef, displayUUID: String)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
...
public protocol WindowSystem: AnyObject, Sendable {
    var events: AsyncStream<WindowEvent> { get }
    func inventory() async -> WindowInventory
    func perform(_ commands: [WindowCommand]) async
}
```
[VERIFIED: Sources/PaneModel/IDs.swift:57-60 and :109] `public struct WindowIdentity` with `public var windowID: UInt32`, `public var pid: Int32`, `public var bundleID: String`; `case present, absent, fullscreen, closed`.
[VERIFIED: Sources/PaneModel/World.swift:121, :147] `public mutating func apply(_ state: WindowState, for window: WindowRef, on key: DeskKey, history: inout UndoHistory) throws(LayoutError)`; `public mutating func undo(_ key: DeskKey, history: inout UndoHistory) throws(LayoutError) -> [WindowRef]?`.
[VERIFIED: Sources/PaneModel/Resolve.swift:31] `public func resolve(_ tree: LayoutTree, in area: Rect, mins: [WindowRef: Size], gap: Double) throws(LayoutError) -> Resolution`. Learned minimums feed `mins`.

**Recommended protocol revisions** (additive, so Phase 1 tests keep compiling; names are proposals [ASSUMED]):
- `WindowInfo`: add `kind` (dockable / neverDock(reason)), `isExcluded`, `visibleMemberID: UInt32?` (tab group), `tabCount`.
- `WindowEvent`: add `.frameApplied(WindowRef, requested: Rect, actual: Rect)`, `.appResponsiveness(pid: Int32, degraded: Bool)`, `.sessionPaused(Bool)`.
- `WindowSystem`: add `func windowInfo(_ ref: WindowRef) async -> WindowInfo?`. This is the re-query hook for the `World.undo` obligation. `LifecycleSync` calls it for each revived ref and reports via `World.apply` (`nil` → `.closed` only after the two-source rule, else the reported state).

### Trusted-only integration suite that launches the fixture (verified)
```swift
// Source: scratch package; passed under `swift test` this session (products dir: .build/out/Products/Debug).
enum Env {
    static let trusted = AXIsProcessTrusted()
    static var productsDir: URL? {   // swiftpm-testing-helper gets "--test-bundle-path <…>/X.xctest/Contents/MacOS/X"
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--test-bundle-path"), i + 1 < args.count,
              let r = args[i + 1].range(of: ".xctest") else { return nil }
        return URL(fileURLWithPath: String(args[i + 1][..<r.upperBound])).deletingLastPathComponent()
    }
}

@Suite(.serialized, .enabled(if: Env.trusted, "needs a process with the Accessibility grant"))
struct FixtureTests {
    @Test(.timeLimit(.minutes(1))) func fixtureLaunchesAndHasWindows() async throws {
        let exe = try #require(Env.productsDir).appendingPathComponent("PaneFixtureApp")
        let p = Process(); p.executableURL = exe; try p.run()
        defer { p.terminate() }
        try await Task.sleep(for: .seconds(2))
        // … AXWindowSystem against p.processIdentifier
    }
}
```
The test target must list `PaneFixtureApp` (an `executableTarget`) in its dependencies so SwiftPM builds it [VERIFIED]. Add an env override `PANE_FIXTURE_APP` for toolchains that use a different runner layout. CI on Xcode 26.6 is unverified: the products path there may be `.build/debug` [ASSUMED].

### XcodeGen `xcode/project.yml` (recommended shape)
```yaml
# Source pattern: AeroSpace xcode/project.yml (MIT, read this session) + XcodeGen 2.46.0 ProjectSpec "Local Package".
name: Pane
packages:
  Pane:
    path: ..                      # repo root Package.swift (AeroSpace uses a symlink for git-worktree friendliness)
configs:
  Debug: debug
  Release: release
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    GENERATE_INFOPLIST_FILE: YES
    INFOPLIST_KEY_LSUIElement: YES
    MARKETING_VERSION: "0.2.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "Developer ID Application"
    DEVELOPMENT_TEAM: S2K7P43927
    ENABLE_HARDENED_RUNTIME: YES
targets:
  Pane:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - ../Sources/PaneApp          # main.swift -> PaneMac.run()
    dependencies:
      - package: Pane
        product: PaneMac
    entitlements:
      path: Pane.entitlements       # generated by XcodeGen
      properties:
        com.apple.security.app-sandbox: false
    settings:
      configs:
        Debug:
          PRODUCT_NAME: "Pane Debug"
          PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.pane.debug
        Release:
          PRODUCT_NAME: Pane
          PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.pane
          SWIFT_TREAT_WARNINGS_AS_ERRORS: YES
```
The setting names `ENABLE_HARDENED_RUNTIME`, `CODE_SIGN_STYLE`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`, `GENERATE_INFOPLIST_FILE` and `INFOPLIST_KEY_LSUIElement` exist in Xcode 27.1's CoreBuildSystem.xcspec [VERIFIED]. The `packages: path:` and `dependencies: - package: product:` syntax is [CITED: XcodeGen 2.46.0 ProjectSpec.md; AeroSpace project.yml]. Whether manual Developer ID signing of a Debug build succeeds with no provisioning profile, and whether `xcodebuild -scheme Pane` finds an auto-generated scheme, are [ASSUMED: AeroSpace's build-release.sh uses `-scheme AeroSpace` with no `schemes:` block]. Wave 0 verifies both. Add `xcode/*.xcodeproj/` and `xcode/.xcode-build/` to `.gitignore`.

**Build & run for UAT:**
```bash
brew install xcodegen                                  # once (checkpoint)
(cd xcode && xcodegen generate)                        # scripts/generate.sh
xcodebuild -project xcode/Pane.xcodeproj -scheme Pane -configuration Debug \
  -derivedDataPath xcode/.xcode-build build
APP="xcode/.xcode-build/Build/Products/Debug/Pane Debug.app"
codesign --verify --strict --verbose=2 "$APP"
codesign -d -r- "$APP"                                 # expect identifier "com.eightabyte.pane.debug" … S2K7P43927
open -n "$APP" --args --disable-private=AXWindowID     # always via LaunchServices (TCC attribution)
```
`open -n` opens a new instance; `--args` passes argv to `main()` [CITED: `man open`]. The first codesign use of the Developer ID key may show a keychain "allow" prompt [ASSUMED].

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| One AX thread / main-thread AX | One thread + run loop per app | AeroSpace core rewrite (#131) | Required for WIN-03 |
| Link-time private symbols (AeroSpace `private.h`) | `dlopen`/`dlsym` optionals | Project rule | Missing symbol degrades instead of failing at launch |
| `Mutex` from Synchronization | `OSAllocatedUnfairLock` at a macOS 14 floor | `Mutex` needs macOS 15 | Use the os lock |
| `swift test` products under `.build/debug` | Swift 6.4 local layout `.build/out/Products/Debug` | Swift 6.4 / swift-build backend | Locate the fixture via `--test-bundle-path`, not hard-coded paths [VERIFIED locally] |
| `NSApp.activate(ignoringOtherApps:)` | `NSApp.activate()` | macOS 14 deprecation | Bring the onboarding window forward from an agent app [ASSUMED] |

**Deprecated/outdated:**
- `AXIsProcessTrusted` isn't deprecated (header shows `CF_AVAILABLE_MAC(10_4)`), but `AXIsProcessTrustedWithOptions` is needed for the prompt.
- The project research claim "AeroSpace uses a 1 s timeout" is inaccurate. No `MessagingTimeout` call appears in AeroSpace's code search. yabai sets 1.0 s on the system element; AltTab sets 0.25 s per app and globally [VERIFIED: gh search code].

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Safari/Chrome/Firefox tabs are one AX window | Pattern 3 | Corpus case needs a tab heuristic for browsers |
| A2 | Finder, Terminal, Ghostty and Xcode tabs behave like the verified AppKit fixture | Pattern 3 | TabGroupTracker needs per-app rules; corpus will show |
| A3 | `CGSSessionScreenIsLocked` appears in the session dictionary while locked; `com.apple.screenIsLocked` still fires on macOS 27 | Pattern 4 | Lock pause misses. Mitigated by the other signals plus the two-source rule |
| A4 | Manual Developer ID signing of a Debug build works without a profile; `xcodebuild -scheme Pane` finds the scheme; first build may trigger a keychain prompt | XcodeGen | Wave 0 build task fails; add `schemes:` or adjust signing |
| A5 | Re-signing ad-hoc (`codesign -f -s -`) after a grant reproduces "toggle on, `AXIsProcessTrusted` false" for stale-grant UAT | Validation | Need another way to simulate a stale grant (e.g. change the Team-signed DR by signing with a different identity) |
| A6 | Stale form B detection by 15 s timeout after the Settings visit is acceptable UX | Pattern 7 | Copy or threshold change only |
| A7 | GitHub `macos-26` runners are not AX-trusted, so the integration suite skips there; if they are trusted, the fixture still makes it deterministic | Validation | CI flakiness if trusted and windows misbehave headless |
| A8 | Proposed protocol additions (`kind`, `visibleMemberID`, `.frameApplied`, `windowInfo(_:)`) | Code Examples | Naming only; planner may adjust |
| A9 | Synthetic fallback IDs in `0xF000_0000…` never collide with real CG IDs | Pattern 8 | Collision would conflate windows; real IDs observed are below 10,000 |
| A10 | Classifier rule 7 (no enabled fullscreen button → never-dock) is the right default for Pane (System Settings would float) | Pattern 2 | Developer may want System Settings dockable; it's an override table entry either way |
| A11 | Register app threads only after `isFinishedLaunching`; re-check activation policy on refresh | Pitfall 11 | Missed early windows; caught by the periodic sweep |

## Open Questions (RESOLVED)

1. **Why did the system-wide `kAXFocusedApplicationAttribute` return -25204 while trusted?** RESOLVED (design avoids it)
   - What we know: app elements worked fine in the same session, and the shell may be sandboxed.
   - Resolution: Pane never relies on the system-wide focused-application attribute. The permission probe reads `AXRole` of Finder's app element on a background thread (1 s timeout, 3 retries, then the frontmost regular app, never Pane's own pid), and an all-timeout result resolves to ready and is logged. Implemented in 02-05-PLAN.md Task 2 (`PermissionProbe`). Focused windows for Nudge come from AX focus hints and `AXMain`, not the system-wide element (02-06, 02-13).
2. **Is System Settings dockable?** RESOLVED: never-dock by default.
   - Resolution: classifier rule 7 (no enabled fullscreen button) leaves System Settings never-dock (Assumption A10); the corpus case is labelled `neverDock` and the developer confirms it in the 02-03 human-check, so changing it later is a one-line override-table entry. Implemented in 02-03-PLAN.md Tasks 1 and 3.
3. **Java app for the corpus:** RESOLVED: Android Studio.
   - Correction: this Mac has `/Applications/Android Studio.app`, a JetBrains IntelliJ-platform (Swing) app that bundles its own Java runtime, so a Java GUI app is available even though `java_home` finds no system JDK. No install and no checkpoint are needed. LibreOffice covers the office case.
   - Resolution: 02-03-PLAN.md Task 3 captures Android Studio's first window (family `java`) and LibreOffice's Start Center (family `office`); the corpus coverage test requires both families.
4. **Multi-display UAT:** RESOLVED: unit vectors now, physical check in manual UAT.
   - Resolution: coordinate conversion and display assignment are unit-tested with synthetic above/left/below layouts (02-06-PLAN.md Task 1); FrameWriteIntegrationTests exercises a second display when one is attached and records when it was not (02-12-PLAN.md Task 2); the developer runs the multi-display Nudge check with an external display or Sidecar (02-13-PLAN.md Task 3 human-check).
5. **Group identity when the leader tab closes:** RESOLVED: keep the leader ref.
   - Resolution: a tab group keeps its first-seen member's `WindowRef` for its whole life; `WindowInfo.visibleMemberID` carries the CGWindowID to address. Recorded in the 02-01-PLAN.md `<assumption_delta_decision>` (with the conditions that would force a Pane-owned ID later) and implemented in 02-10-PLAN.md; Phases 3-4 are told to address windows through `visibleMemberID`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / xcodebuild | Signed `.app` | ✓ | 27.1 (27A9275) | — |
| Swift toolchain | Everything | ✓ | 6.4 (swiftlang-6.4.0.34.1) | — |
| macOS | Runtime | ✓ | 27.0.1 (26A434) | — |
| Developer ID Application identity | Signing | ✓ | "Developer ID Application: Ken Scott (S2K7P43927)", 1 valid identity | — |
| XcodeGen | `project.yml` → xcodeproj | ✗ | brew has 2.46.0 | `brew install xcodegen` (checkpoint) |
| xcbeautify | Log prettifying | ✗ | — | Plain xcodebuild output |
| Homebrew | Installing XcodeGen | ✓ | 7.0.10 | — |
| `tccutil` | Reset permission | ✓ | /usr/bin/tccutil | — |
| gh CLI | Prior-art reading | ✓ | logged in | — |
| AX trust in dev shell | Integration tests | ✓ | `AXIsProcessTrusted()` true from this shell | Suite skips when false |
| Corpus apps | `pane-dump` corpus | ✓ | Finder, Safari, Terminal, System Settings; Electron: VS Code, Obsidian, Signal, Termius; Java: Android Studio (bundled runtime); Office: LibreOffice (no MS Office); Chrome, Firefox (PiP cases); Warp | — (Open Question 3 resolved) |
| External display | SC3 multi-display UAT | ✗ | built-in only (2560×1664 Retina, 1710×1112 pt) | Unit-tested coordinates; UAT needs a display/Sidecar |

**Missing dependencies with no fallback:**
- An external display for the SC3 multi-display UAT step (or Sidecar; covered by the 02-13 human-check).

(Correction: a Java GUI app is available, Android Studio; see Open Question 3.)

**Missing dependencies with fallback:**
- XcodeGen (install via brew behind a checkpoint).
- xcbeautify (optional).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (toolchain bundled; Testing Library 2084), as in Phase 1 |
| Config file | none (SwiftPM). CI: `.github/workflows/ci.yml` |
| Quick run command | `swift test --filter PaneEngineTests` |
| Full suite command | `swift test && swift test -c release -Xswiftc -enable-testing` |
| Trusted integration | `swift test --filter PaneMacIntegrationTests` (auto-skips without AX trust) |

### Test layers
1. **Headless unit (PaneEngineTests + FakeWindowSystem):** classifier corpus, CloseRule table, TabGroupTracker, MinimumSizeLearner, Coordinates, PermissionReducer, LifecycleSync (incl. undo re-query obligation), capability parsing, exclusion filter, Fake scenarios for hung app / slow app / ID churn / refusing sizes / lock blanking.
2. **Trusted integration (PaneMacIntegrationTests + PaneFixtureApp):** real AX against fixture windows. Covers enumerate, open/close, setFrame plus read-back, `minSize` learning, native tabs (switch via AX press), sheet/borderless/no-fullscreen classification, `SIGSTOP` of one fixture while a second fixture's setFrame completes in < 1 s, and the `--disable-private` fallback path.
3. **Manual UAT checklist** (developer): first-launch grant via `open -n`, stale grant (A5 recipe), real `kill -STOP` on a user app, lock/unlock and sleep/wake with 10 tracked windows, multi-display arrangements (above/left), Finder/Terminal/Safari tabs, exclusion toggle, corpus capture of real apps.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WIN-01 | Permission reducer transitions; stale forms A/B; reset exit-code handling | unit | `swift test --filter PermissionReducerTests` | ❌ Wave 0 |
| WIN-01 | Onboarding, polling advance, Reset button | manual UAT | `open -n "…/Pane Debug.app"` | n/a |
| WIN-02 | Inventory + created/destroyed events; CG-only and non-AXWindow ignored | unit + integration | `swift test --filter "TrackingTests\|FixtureTrackingTests"` | ❌ Wave 0 |
| WIN-03 | Hung app doesn't block other apps' commands; degraded tracker | unit (Fake hung) + integration (SIGSTOP fixture) | `swift test --filter "ResponsivenessTests\|FreezeIntegrationTests"` | ❌ Wave 0 |
| WIN-04 | Learned minimum from read-back; latest-wins coalescing; size→pos→size | unit + integration (fixture minSize 250×150) | `swift test --filter "MinimumSizeLearnerTests\|FrameWriteIntegrationTests"` | ❌ Wave 0 |
| WIN-04 | Secondary displays in any arrangement | unit (Coordinates vectors) + manual UAT | `swift test --filter CoordinatesTests` | ❌ Wave 0 |
| WIN-05 | Corpus classification matches labels | unit (corpus) + integration (fixture shapes) | `swift test --filter ClassifierCorpusTests` | ❌ Wave 0 |
| WIN-06 | Tab group = one window; switch rebinds without create/destroy | unit + integration (fixture tabs) | `swift test --filter "TabGroupTrackerTests\|TabsIntegrationTests"` | ❌ Wave 0 |
| WIN-08 | Excluded bundle IDs: commands dropped, windows still listed | unit | `swift test --filter ExclusionTests` | ❌ Wave 0 |
| WIN-09 | Close table incl. timeout/lock/terminated rows; closed-ID cache | unit + integration (fixture close via AX press) | `swift test --filter "CloseRuleTests\|CloseIntegrationTests"` | ❌ Wave 0 |
| WIN-09 | Real lock/sleep | manual UAT | — | n/a |
| SAFE-05 | Forced-off capability → fallback matcher; launch with flag | unit + integration | `swift test --filter "CapabilitiesTests\|FallbackMatcherTests"` | ❌ Wave 0 |
| (P1 obligation) | Undo-revived windows re-queried, reported via `World.apply` | unit | `swift test --filter LifecycleSyncTests` | ❌ Wave 0 |
| (guardrail) | PaneEngine/PaneModel stay AppKit-free | existing unit | `swift test --filter NoAppKitTests` | ✅ |

### Sampling Rate
- **Per task commit:** `swift test --filter PaneEngineTests` (< 30 s), plus `scripts/check-no-appkit.sh`
- **Per wave merge:** `swift test` and `swift test -c release -Xswiftc -enable-testing`
- **Phase gate:** full suite green (integration suite run from a trusted terminal), signed Debug build verified with `codesign`, manual UAT checklist signed off before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `Package.swift`: targets `PanePrivate`, `PaneMac` (+ library product), `PaneApp`, `pane-dump`, `PaneFixtureApp`, `PaneTestSupport`; test targets `PaneEngineTests`, `PaneMacIntegrationTests`
- [ ] `Sources/PaneTestSupport/FakeWindowSystem.swift`: shared fixture (actor)
- [ ] `Sources/PaneFixtureApp/main.swift`: windows with tabs, sheet, utility panel, borderless floating, `fullScreenNone`, `minSize`; command channel (argv or stdin) to open/close windows
- [ ] `Tests/PaneEngineTests/Fixtures/AXDumps/`: corpus directory + JSON schema doc
- [ ] `xcode/project.yml`, `scripts/generate.sh`, `.gitignore` entries
- [ ] Install XcodeGen (checkpoint) and verify signed Debug build + DR (A4)

## Security Domain

`security_enforcement: true`, ASVS level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Local app, no accounts |
| V3 Session Management | no | — |
| V4 Access Control | yes (OS-level) | Hardened runtime; non-sandboxed only because AX requires it; Accessibility via TCC; no extra entitlements; Release has no `get-task-allow` |
| V5 Input Validation | yes | Validate `min-size-hints.json` (schema version, finite, 0…`Geometry.maxCoordinate`, size cap); exclusion list entries are bundle-ID strings only; `--disable-private` accepts only known `Capability` names; AX strings treated as untrusted data |
| V6 Cryptography | no | Code signing only (Developer ID); no app crypto |
| V7 Error Handling & Logging | yes | `os.Logger`; never log titles (`WindowRef.description` already redacts); log AX error codes |
| V12 Files & Resources | yes | Write only under `~/Library/Application Support/Pane/` with atomic writes; corpus files redacted |
| V14 Configuration | yes | DR check in UAT (`codesign -d -r-`); bundle IDs fixed |

### Known Threat Patterns for a macOS AX agent app

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Command injection via `tccutil` invocation | Tampering / EoP | `Process` with fixed `executableURL=/usr/bin/tccutil` and argv array; bundle ID from `Bundle.main`, never user input; no shell |
| Wrong `dlsym` signature → memory corruption in an AX-privileged process | Tampering | Signature `(AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError` from several prior-art headers; one call site; call-time failure counting |
| Privacy leak of window titles in logs or the committed corpus | Information disclosure | Title redaction in logs and `pane-dump`; review the corpus diff before commit |
| Malicious or huge hints JSON crashing or poisoning layout | Tampering / DoS | Size cap, schema check, bounds check; reject the whole file on error (no silent fallback: log and start empty is an explicit, logged decision) |
| Freeze-test helper abused to stop critical processes | DoS | Refuse system pids/bundles; auto-resume; recorded pid resumed at launch; Debug builds only |
| AX requests to own pid → crash | DoS | Exclude own pid from tracking |

## Sources

### Primary (HIGH confidence)
- macOS 27.0 SDK headers: `AXRoleConstants.h`, `AXAttributeConstants.h`, `AXNotificationConstants.h`, `AXError.h`, `AXUIElement.h` (constants, error codes, timeout semantics)
- Local probes this session (scratchpad, throwaway fixture apps): freeze/timeout, close signals, termination, native tabs/sheet/panel/minimise/hide, Finder desktop, CG/AX frame equality, batched-read perf, display UUID/bounds, `dlopen`/`dlsym`, Sendable/isolation compile checks, Swift Testing trusted suite + fixture launch, `tccutil` exit code, Xcode xcspec setting names, `Mutex` vs `OSAllocatedUnfairLock`
- AeroSpace source (MIT), read via `gh api`: `Sources/AppBundle/model/AxUiElementWindowType.swift`, `Sources/AppBundleTests/AxUiElementWindowTypeTest.swift`, `axDumps/` listing + `chrome_pip.json5`, `Sources/AppBundle/tree/MacApp.swift`, `runLoop.swift`, `xcode/project.yml`, `generate.sh`, `build-release.sh`
- Amethyst source (MIT): `Amethyst/Managers/WindowManager.swift` (`swapInTab`)
- XcodeGen 2.46.0 `Docs/ProjectSpec.md` (Swift Package / Local Package, Plist, entitlements)
- Apple TN3127 "Inside Code Signing: Requirements" (developer.apple.com JSON): DR semantics, ad-hoc DR tied to version

### Secondary (MEDIUM confidence)
- GitHub issues: AeroSpace #68 (native tabs), Loop #418 and Amethyst #1856 (stale grants), yabai #2688 (TCC UI on 26.1)
- `gh search code`: messaging-timeout usage in yabai (1.0 s system-wide), AltTab (0.25 s), Rectangle; deep link in Rectangle `AccessibilityView.swift`
- Project research: `.planning/research/ARCHITECTURE.md`, `PITFALLS.md`, `STACK.md`

### Tertiary (LOW confidence)
- WebSearch: `com.apple.screenIsLocked` usage (Chromium `idle_mac.mm`, Keyboard Maestro forum 2026-04); no macOS 27 confirmation ([Chromium idle_mac.mm](https://chromium.googlesource.com/chromium/src/+/e8a107c96/ui/base/idle/idle_mac.mm), [Keyboard Maestro forum](https://forum.keyboardmaestro.com/t/feature-request-lock-trigger/51487))

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. Toolchain, identity and SDK verified locally; XcodeGen version verified, generation not run.
- Architecture: HIGH for threading/isolation shapes and AX facts (compiled and probed); MEDIUM for tab-group identity and the refresh intervals (design).
- Pitfalls: HIGH for the probed ones (1–6, 9, 10); MEDIUM for lock/sleep (7) and the launch timing (11).

**Research date:** 2026-10-24
**Valid until:** 2026-11-23 (30 days; re-probe AX facts on any macOS point release)
