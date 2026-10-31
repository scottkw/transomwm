# Phase 6: Overview, Spaces & Displays - Research

**Researched:** 2026-10-31
**Domain:** macOS Spaces (SkyLight, read-mostly), symbolic hotkeys, display reconfiguration, layout persistence, Core Animation overview on the Phase 4 stage
**Confidence:** MEDIUM overall. Facts probed locally on macOS 27.2 are HIGH. Behaviour that only a state-changing test can settle is LOW until the VM spikes listed under Validation Architecture have run: takeover persistence after a crash, Space switching, G-03-9 ghost AX answers, and ID stability across a reboot.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Overview look and interaction
- D-01: The overview is a new command, **Show Overview**, on its own ⌃⌥⌘ hotkey (a free key, rebindable in the Shortcuts window). ⌃⌥⌘O keeps its Phase 4 meaning: per-display zoom out to all windows (pick mode).
- D-02: Each display shows its own windows in place on its own StagePanel, with a strip of that display's Spaces along its top. No combined cross-display panel.
- D-03: Windows on other Spaces show the last snapshot taken this session; otherwise the existing app-colour + icon + title tile (AppColor). Never try to capture non-composited windows.
- D-04: Clicking a window switches to its Space if needed, focuses it and closes the overview. Arrow keys move the selection, Return opens it, Esc closes the overview. Clicking a Space in the strip switches to that Space.

#### Mission Control takeover
- D-05: v1 takeover triggers are the Mission Control keys (F3 / ⌃↑): disable the system symbolic hotkey and handle the keys ourselves. The 4-finger swipe up (CGEvent type 30, Dock control) is spike-gated: only take it if a VM spike plus a user host check prove it can be consumed safely; otherwise leave the swipe to macOS and say so.
- D-06: Opt-in is a menu toggle (e.g. "Replace Mission Control") that shows a one-time explanation alert, matching the Phase 3 conflict-alert style, plus a Debug submenu status line. Off by default.
- D-07: Crash safety: before disabling, store the original symbolic-hotkey state in UserDefaults; restore it on quit, on turning the toggle off and at the next launch. Also use the MultitouchCanary pattern: a crash while the takeover is on turns it off for that build/version until the user turns it back on.
- D-08: ⌃←/→ Space switching stays with macOS; not taken over.

#### Display arrangements
- D-09: A display arrangement is identified by the sorted set of display UUIDs, ignoring positions and resolution.
- D-10: On unplug, the vanished display's desks become dormant (kept in the World, not planned). Its windows float on a remaining display and return to their tiles on re-plug, matched by display UUID.
- D-11: Debounce display reconfiguration ~1.5 s after the last screen-parameters change, and never act while the session is asleep or locked (SessionGate).
- D-12: "Displays have separate Spaces" off is detected (from SkyLight) and handled silently: one shared Space spanning displays, desks still keyed per display UUID. No prompt.

#### Spaces handling
- D-13: Persist Space desks by the macOS Space UUID (from `SLSCopyManagedDisplaySpaces`); use the numeric ManagedSpaceID at runtime. Existing layout.json files with numeric IDs need a migration (research to confirm ID stability across reboots).
- D-14: A desk that changes while its Space is hidden is marked dirty and planned when its Space is next shown; no AX writes to hidden-Space windows.
- D-15: Without the Spaces lookup, build a window→Space co-visibility map from `activeSpaceDidChange` (Spaces visited since launch only) and hide the Spaces strip.
- D-16: The Spaces strip is read-only in v1: click to switch only. No create, delete or drag-window-to-Space.

### Claude's Discretion
- Which free ⌃⌥⌘ key Show Overview uses; exact strip styling (follow 04-UI-SPEC tokens); selection highlight; how Space switching is performed (public API or SkyLight); arrangement-set schema shape and migration mechanics.

(The approved 06-UI-SPEC already settled the key as ⌃⌥⌘A, plus the strip styling and the selection highlight. This research settles the Space-switching method and the arrangement schema below.)

### Deferred Ideas (OUT OF SCOPE)
- 4-finger swipe takeover, if the spike fails.
- Dragging windows between Spaces; creating/deleting Spaces from the strip.
- Taking over ⌃←/→ Space switching.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OVER-01 | Overview shows every window on every display, with Spaces along the top; clicking a window goes to it | `SLSCopyManagedDisplaySpaces` shape, verified locally (§Verified Facts F1). Overview built on the Phase 4 `StagePanel` (Pattern 6). Space switching by posting the user's own Mission Control chord, then the existing AX focus (Pattern 3). Other-Space mini tiles come from the World's desks plus the session's snapshot cache (D-03) |
| OVER-02 | User can opt in to having Mission Control's swipe and shortcut open Transom's overview instead | Symbolic hotkey IDs **32** (⌃↑) and **108** (the Mission Control key, keycode 160), from local enumeration (F3). Setter and getter resolve on 27.2 (F2). Keys are caught with `KeyboardShortcuts.events(for: Shortcut)` (Pattern 4). Swipe stays spike-gated (Pitfall 9) |
| OVER-03 | If Transom crashes while replacing Mission Control, the system shortcuts are restored on next launch | WindowServer keeps the disabled state after the process exits [CITED: alt-tab-macos source comment]. So: store originals → disable → read back. At launch, stored originals mean an unclean exit, so restore them first. Plus a takeover canary (Pattern 4) |
| OVER-04 | Each display (and each Space) keeps its own layout | Already true at runtime: `DeskKey(displayUUID, spaceID)` and only shown desks are planned (D-25, 03). Phase 6 adds persistence by Space UUID (Pattern 5) and confirms D-14 with tests |
| OVER-05 | Unplugging and re-plugging a display, or sleep/wake, restores that display's layout | Settling gate: early start from `CGDisplayRegisterReconfigurationCallback`, then 1.5 s quiet after `didChangeScreenParameters`, held while SessionGate is paused. Display-based re-homing is suspended while settling. On re-plug the arrangement layout set is restored (Pattern 7) |
| OVER-06 | Remembers layouts per display arrangement and applies the matching one automatically | `ArrangementID` = sorted display UUIDs (D-09). LayoutFile v2 stores the other arrangements' Worlds. A switch runs the existing `LayoutRestore.reattach` against the live inventory (Pattern 7) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Taken from `/Users/ken/dev/CLAUDE.md` and `/Users/ken/dev/transomwm/.claude/CLAUDE.md`. They carry the same authority as locked decisions:

- **Swift 6, SPM**, `swift-tools-version: 6.2`. No Swift 6.4-only syntax in shipped code. Every new target or file follows the per-target settings in Package.swift.
- **`TransomModel` and `TransomEngine` must not import AppKit** (enforced by `scripts/check-no-appkit.sh` and `NoAppKitTests`). All new pure logic goes there so it can be tested headless: arrangement IDs, schema migration, Space re-keying, the co-visibility map, overview geometry and selection, the takeover state machine, and the G-03-9 rule.
- **Private APIs:** each one sits in a single file in `TransomPrivate`, reached by `dlopen`/`dlsym` into optionals, capability-gated (`--disable-private=<Name>`), with a fallback. Never link-time (`@_silgen_name` is forbidden by STACK.md "What NOT to Use").
- **Clean room:** never consult the TrellisWM binary. Loop and AltTab are GPL-3: read them for facts and patterns, never copy their code. yabai, AeroSpace and Amethyst are MIT.
- **Never run live tests, event taps, symbolic-hotkey setters, CoreDock calls, multitouch or window-opening code on the host.** State-changing probes go to the Tart VM (`pane-test`, macOS 15.7.7) through `scripts/vm-spike.sh` / `scripts/vm-live-test.sh`, one at a time, under `.build/transom-vm.lock`.
- **Testing:** 80%+ coverage on critical components. Swift Testing (`@Test`, `#expect`).
- **Silent fallbacks forbidden** ("`or {}` converts hard failures into silent corruption"). A failed takeover read-back must restore and report (N11), never assume.
- **Chesterton's Fence:** the rules for `rehome`, `isAlive` and `CloseRule` exist for documented reasons (02-14, 03, G-03-8). Phase 6 narrows them; it does not remove them.
- **Premature abstraction:** three examples before abstracting. The takeover canary copies `MultitouchCanary` (D-07 says "copy"). Don't generalise it into a framework.
- **Logging:** `os.Logger` subsystem `com.eightabyte.transom`. Window titles are `.private` and never logged.
- **GSD workflow:** edits only through GSD commands. Ponytail applies to executors.

## Summary

Phase 6 is mostly plumbing around four OS seams: Spaces (SkyLight reads), symbolic hotkeys (one SkyLight write), display reconfiguration (public CoreGraphics/AppKit) and Space switching (synthetic key events). Read-only probes on the host settled several key facts.

- `SLSCopyManagedDisplaySpaces` returns an array of display dictionaries. Each has `"Display Identifier"`, `"Current Space"` and `"Spaces"`, and every Space dictionary has `ManagedSpaceID`, `id64`, `type` and `uuid`. On 27.2, `id64 == ManagedSpaceID` for every Space.
- The symbolic-hotkey getter shows Mission Control at ID **32** (⌃↑, keycode 126) and the dedicated Mission Control key at ID **108** (keycode 160, no modifiers).
- Every needed private symbol resolves on 27.2: `SLS/CGSSetSymbolicHotKeyEnabled`, `SLSIsSymbolicHotKeyEnabled`, `SLSGetSymbolicHotKeyValue`, `SLSGetSpaceManagementMode`, and `CoreDockSendNotification` in HIServices.
- The user's machine has `AppleSpacesSwitchOnActivate = 0`. So "activate the app and macOS swooshes to its Space" will not work here, which is a strong argument for switching Spaces explicitly.

Most of the per-display, per-Space behaviour already exists. Desks are keyed by `(displayUUID, spaceID)`, only shown desks are planned, hidden-Space windows stay dormant (G-03-8), and windows that change display are re-homed. Phase 6 makes three structural changes:

1. **Persistence:** LayoutFile schema 2 adds a Space-UUID table, so desks re-key by UUID on load, plus one stored World per display arrangement (OVER-06). LayoutStore must accept and migrate schema 1. Today it sets any non-current version aside as `.corrupt`.
2. **A display "settling" state:** while displays reconfigure, the Arranger must not re-home windows away from a vanishing display's tiles. That would destroy the layout the re-plug needs. It snapshots, waits 1.5 s with the session unlocked, then applies or derives the arrangement's layout set.
3. **The overview**, a shell feature on the existing per-display `StagePanel`. Its geometry, selection navigation and strip layout live in a pure Engine type so they can be tested headless.

The takeover is small but crash-sensitive. Disabling a symbolic hotkey is WindowServer session state that outlives the process [CITED: alt-tab-macos commit 848ae5f, "the effect of enabling/disabling persists after the app is quit"]. So the order is fixed: store originals (never overwrite existing ones) → disable → read back → register Carbon hotkeys for the freed chords. Restore on toggle-off, zoom-off, "Restore macOS Window Settings" and quit. At launch, the presence of stored originals alone means an unclean exit: restore before anything else.

**Primary recommendation:** Settle every LOW item with one Wave 0 VM spike product (`transom-spaces-spike`). It covers dumping the Spaces and hotkey tables, the disable / kill -9 / relaunch / restore cycle, the Space-switch methods, the G-03-9 ghost answers and the before/after-reboot ID diff. Then build in this order: pure Engine types → TransomPrivate symbol files → shell controllers → overview UI. Multi-display behaviour is verified only by the UI-SPEC hardware checklist.

## Architectural Responsibility Map

The generic web tiers don't apply. These are Transom's tiers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Space list, current Space, Space UUIDs, management mode | TransomPrivate (`SkyLightSpaces` + new reads) | TransomMac `SpacesProvider` (snapshot value type) | Private API isolation rule. The shell turns raw dictionaries into a `SpacesSnapshot` value that Engine can consume |
| Space UUID ↔ runtime ID re-keying, v1→v2 migration | TransomEngine (`LayoutFile`, new `SpaceRekey`) | TransomMac `LayoutStore` (version gate) | Pure and headless-testable. LayoutStore only decodes and dispatches by version |
| Arrangement identity, layout sets, switch/merge rules | TransomEngine (`Arranger` + new `Arrangements`) | TransomModel (`World` unchanged) | The Arranger already owns the World. A switch is an in-session restore |
| Display reconfiguration debounce and settling | TransomMac (`AXWindowSystem` / new `DisplaySettler`) | TransomEngine (Arranger `.displaysSettling`/`.displaysSettled` inputs) | OS notifications and timers are shell. Suspending re-homing while settling is Engine policy |
| Mission Control takeover state machine | TransomEngine (pure `TakeoverPolicy`: what to store, restore, apply) | TransomMac `MissionControlTakeover` (UserDefaults, Carbon keys) + TransomPrivate `SymbolicHotKeys` | The crash-safety rules must be unit-testable without touching WindowServer |
| Opening system Mission Control as a fallback | TransomPrivate `CoreDock` | TransomMac takeover controller | Private, own capability (UI-SPEC Surface 5) |
| Space switching (strip click, pick on another Space) | TransomMac `SpaceSwitcher` (CGEvent post) | TransomPrivate (read-only hotkey getter for the user's chord) | Public posting plus a private read. No SkyLight write |
| Overview geometry, strip layout, selection navigation | TransomEngine (pure `OverviewLayout` / `OverviewSelection`) | TransomMac `OverviewController` (StagePanel, layers, Carbon keys) | The geometry and keyboard rules in UI-SPEC Surfaces 1–3 are pure functions and are tested headless |
| Co-visibility Space map (lookup off) | TransomEngine (pure `CoVisibilitySpaces`) | TransomMac (feeds on-screen CG lists at Space changes) | Pure clustering. The shell supplies observations |
| G-03-9 close rule | TransomEngine (`CloseRule`, `WindowTracker.decide`) | — | Existing two-source rule, one new input |

## Standard Stack

### Core (all system; no new package)

| Technology | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SkyLight private reads (`SLSCopyManagedDisplaySpaces`, `SLSManagedDisplayGetCurrentSpace`, `SLSGetSpaceManagementMode`, `SLSCopySpacesForWindows`) | macOS 14–27 (resolve verified on 27.2) | Space list, current Space, UUIDs, separate-Spaces mode | The only way to list Spaces and their UUIDs. yabai and Amethyst do the same [VERIFIED: local dlsym probe 2026-10-31] |
| SkyLight symbolic hotkeys (`SLSSetSymbolicHotKeyEnabled`, `SLSIsSymbolicHotKeyEnabled`, `SLSGetSymbolicHotKeyValue`; `CGS*` aliases also export) | resolve verified on 27.2 | Mission Control takeover and reading the user's chords | The only way to stop the Dock from taking ⌃↑ / F3 without editing the persistent plist [VERIFIED: local dlsym probe] |
| `CoreDockSendNotification(CFString, Int32)` in HIServices | resolve verified on 27.2 | Open macOS Mission Control when the overview can't | Signature from a public gist [CITED: gist.github.com/unixzii/7091dda6aea958c6da669e436365df65]. The symbol resolves in `HIServices.framework` [VERIFIED: local dlsym probe] |
| `NSScreen.screensHaveSeparateSpaces` | public, macOS 10.9+ | Detect "Displays have separate Spaces" (D-12) | Public, so prefer it over SkyLight. `SLSGetSpaceManagementMode` (1 = separate on this host) is the cross-check [VERIFIED: local probe: true with NSApplication up, mode 1] |
| `CGDisplayRegisterReconfigurationCallback` | public, macOS 10.3+ | Early "displays are changing" signal (before and after each display change) | [CITED: developer.apple.com CGDisplayRegisterReconfigurationCallback, "invoked twice for each display … once before the reconfiguration, and once after"] |
| `NSApplication.didChangeScreenParametersNotification` | public | Settled screen list (already observed at `AXWindowSystem.swift:112-116`) | Already in use. Debounce it to 1.5 s (D-11) |
| `CGDisplayCreateUUIDFromDisplayID` | public | Display identity (already in `Displays.swift:56-59`) | Display IDs are not durable (Pitfall 14, existing) |
| `CGEvent` keyboard posting (`.cghidEventTap`) | public; needs the Accessibility grant Transom has | Space switching by the user's own chords | Amethyst's documented approach (MIT) [CITED: Amethyst README via search: Mission Control ⌃n shortcuts must be enabled to move windows between Spaces] |
| KeyboardShortcuts 3.1.0 (existing dep) | 3.1.0, pinned exact | `Name.showOverview` recorder row; temporary `events(for: Shortcut)` streams for overview keys and the freed Mission Control chords | Already used for pick-mode Esc (`ZoomInput.swift:179-181`). `Shortcut(carbonKeyCode:carbonModifiers:)` exists [VERIFIED: .build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Shortcut.swift:86 `public init(carbonKeyCode: Int, carbonModifiers: Int = 0)`; KeyboardShortcuts.swift:786 `public static func events(for shortcut: Shortcut) -> AsyncStream<KeyboardShortcuts.EventType>`] |
| ScreenCaptureKit via existing `SnapshotCapture` | macOS 14 | Overview snapshots (current Space only) and background capture after a Space visit | Phase 4 path. D-03 forbids capturing hidden-Space windows |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `GetProcessForPID` + `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` | private, all resolve on 27.2 | Focus a window by ID on another Space (yabai MIT approach) | **Fallback only**, behind the spike verdict. Use it if posted chords prove display-ambiguous in multi-display keyboard picks (Pattern 3) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Posting the user's "Move left/right a space" chord (IDs 79/81) | `SLSManagedDisplaySetCurrentSpace` + `SLSShowSpaces`/`SLSHideSpaces` | Rejected. It changes WindowServer's current Space behind the Dock's back, and yabai routes Space focus through its scripting addition (SIP off) instead [ASSUMED: from yabai design knowledge; risk is Dock/menu-bar desync] |
| Posting chords | Activate the window's app and rely on macOS's swoosh | Rejected for this user: `AppleSpacesSwitchOnActivate = 0` on the host [VERIFIED: `defaults read NSGlobalDomain AppleSpacesSwitchOnActivate` → 0] |
| Posting chords | Open Mission Control and click the Space via AX (Hammerspoon approach) | Rejected: it shows Mission Control's own animation, which is slow and fragile [ASSUMED] |
| Session-scoped symbolic hotkey disable | Write `com.apple.symbolichotkeys` plist + `activateSettings -u` | Rejected. A persistent change makes a crash permanent; the session-scoped one dies at logout at worst [CITED: theregister.com 2009 hotkeys article: persistent changes need the plist] |
| Carbon hotkeys for the freed chords | Add keyDown to the CGEventTap mask | Rejected: the tap mask stays mouse + flagsChanged (T-03-28, UI-SPEC Surface 3). Carbon hotkeys consume the key without a keyboard tap |

**Installation:** none. No new package; KeyboardShortcuts 3.1.0 is already pinned.

## Package Legitimacy Audit

This phase installs **no external packages**. Every capability uses system frameworks or the existing pinned KeyboardShortcuts 3.1.0, which was audited in earlier phases.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none new) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Verified Facts (local read-only probes, macOS 27.2 build 26B123, 2026-10-31)

All probes called getters only (scratchpad binaries `probe`, `enumhk`, `disp`, `sep`). No setter was called.

**F1 — `SLSCopyManagedDisplaySpaces(cid) -> CFArray` shape** [VERIFIED: local probe]:
```
display: 37D8832A-2D66-02CA-B9F7-8F30A301B230 keys: ["Current Space", "Display Identifier", "Spaces"]
  current: ["ManagedSpaceID", "id64", "type", "uuid"] 3 3 0 7A041E06-6227-4718-86AD-2EF8A8D6E7DA
  space keys: ["ManagedSpaceID", "id64", "type", "uuid"] id64 3 msid 3 type 0 uuid 7A041E06-...
  space keys: ["Display Identifier", "ManagedSpaceID", "id64", "type", "uuid"] id64 4 msid 4 type 0 uuid EF244C48-...
  space keys: [...] id64 149 msid 149 type 0 uuid 6C5CB59E-...
```
- The display's `"Display Identifier"` equals `CGDisplayCreateUUIDFromDisplayID` of the built-in display (`37D8832A-2D66-02CA-B9F7-8F30A301B230`, `CGDisplayIsMain` 1) [VERIFIED: local probe].
- Some Space dictionaries carry their own `"Display Identifier"`. In `com.apple.spaces`, the persisted `ManagedSpaceOrdering` lists all six UUIDs under that one display, and `"Collapsed Space"` records exist for 8 other display UUIDs (displays seen before) [VERIFIED: `defaults read com.apple.spaces`]. **Use the grouping (which display's `"Spaces"` array lists a Space) as the Space→display truth. Never use the per-Space `"Display Identifier"` subkey for that.**
- `id64 == ManagedSpaceID` for every Space here. `SLSCopySpacesForWindows` and `SLSManagedDisplayGetCurrentSpace` already return these numbers (03-RESEARCH probe: current Space id64 6 matched).
- The persisted plist names the main monitor `"Display Identifier" = Main`, while the live API returned the UUID. The live API in spans mode is **not observed**: on a single-display host it may return `"Main"` [ASSUMED].

**F2 — symbols resolve** [VERIFIED: local dlsym, SkyLight path `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`]: `SLSMainConnectionID, SLSCopyManagedDisplaySpaces, SLSGetSpaceManagementMode, SLSManagedDisplayGetCurrentSpace, SLSCopySpacesForWindows, SLSSpaceGetType, SLSSpaceCopyName, SLSGetActiveSpace, SLSManagedDisplaySetCurrentSpace, SLSShowSpaces, SLSHideSpaces, SLSCopyManagedDisplayForSpace, SLSCopyWindowsWithOptionsAndTags, SLSMoveWindowsToManagedSpace, CGSSetSymbolicHotKeyEnabled, CGSIsSymbolicHotKeyEnabled, CGSGetSymbolicHotKeyValue, CGSSetSymbolicHotKeyValue, SLSSetSymbolicHotKeyEnabled, SLSIsSymbolicHotKeyEnabled, SLSGetSymbolicHotKeyValue, _SLPSSetFrontProcessWithOptions, SLPSPostEventRecordTo` all `true`. In HIServices: `CoreDockSendNotification`, `_AXUIElementGetWindow` `true`. **The VM (15.7.7) is not yet probed**: Wave 0 spike.

**F3 — symbolic hotkey table** (getter `SLSGetSymbolicHotKeyValue(id, &char, &vk, &mods) -> Int32`, rc 0 means valid) [VERIFIED: local enumeration 0..<400]:
```
32 en=true char=65535 vk=126 mods=0x840000      ⌃↑ (+fn flag)      Mission Control
33 en=true char=65535 vk=125 mods=0x840000      ⌃↓                 Application windows (D-08: never touch)
34 en=true char=65535 vk=126 mods=0x860000      ⌃⇧↑                (shift variant of 32)
79/80 vk=123 0x940000/0x960000, 81/82 vk=124    ⌃← / ⌃→ (+⇧)        Move left/right a space
108 en=true char=65535 vk=160 mods=0x800000     Mission Control key (keycode 160), no modifier
109..117 vk=160 with ⌥/⌘/⌥⌘/⇧⌘/⇧/⌃/⌃⌥/⌃⇧         other Mission Control key combinations
118..133 en=false vk=18..29 mods 0x40000/0xc0000  Switch to Desktop 1..16 (⌃1…) — disabled on this host
173/174 vk=131                                  Launchpad key
```
- The meanings of 32, 33, 79–82 and 118–133 match the macOS Keyboard Shortcuts pane [CITED: gist.github.com/mkhl/455002 (32 = ExposeAllWindows)]. **108 = the Mission Control key** is inferred from vk 160 with no modifier [ASSUMED meaning; value VERIFIED]. F3 sending keycode 160 rests on community keycode lists [CITED: gist.github.com/eegrok/949034 comment; macscripter.net "key code 160 -- Show Mission Control"].
- IDs 32–37 are **absent** from `com.apple.symbolichotkeys` (macOS defaults in force), yet the getter returns their effective values. **Read through the getter, never the plist.** [VERIFIED]
- Modifier encoding is NX/CG device-independent flags: `0x20000` ⇧, `0x40000` ⌃, `0x80000` ⌥, `0x100000` ⌘, `0x800000` fn/secondary (set for arrows and F-keys).

**F4 — Spaces mode and settings** [VERIFIED: local]:
- `SLSGetSpaceManagementMode(cid)` = 1. `NSScreen.screensHaveSeparateSpaces` = **false in a bare CLI process, true after `_ = NSApplication.shared`**. `com.apple.spaces spans-displays` is absent (default: separate Spaces on).
- `defaults read NSGlobalDomain AppleSpacesSwitchOnActivate` = **0**. `com.apple.dock mru-spaces` = 0 (no auto-rearrange).
- Trackpad: `TrackpadFourFingerVertSwipeGesture = 2` (the four-finger swipe up opens Mission Control).

**F5 — in-repo values the plan touches** (opened with Read this session):
- `Sources/TransomPrivate/Capabilities.swift:5-8`: `public enum Capability: String, CaseIterable, Sendable {` / `case axWindowID = "AXWindowID"` / `case spaces = "Spaces"` / `case multitouch = "Multitouch"`
- `Sources/TransomPrivate/Capabilities.swift:137`: `public static let key = "privateCanary.Multitouch"`
- `Sources/TransomPrivate/SkyLightSpaces.swift:9-11`: `typealias MainConnectionID = @convention(c) () -> Int32` / `typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?`; `:21` `typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64`
- `Sources/TransomEngine/LayoutFile.swift:34`: `public static let schemaVersion = 1`
- `Sources/TransomModel/World.swift:87`: `public static let currentSchemaVersion = 1`
- `Sources/TransomMac/LayoutStore.swift:96-97`: `guard version <= LayoutFile.schemaVersion else { throw .newerVersion(version) }` / `guard version == LayoutFile.schemaVersion else { throw .corrupt("unknown schemaVersion \(version)") }`
- `Sources/TransomModel/IDs.swift:119-121`: `public struct DeskKey: Hashable, Comparable, Codable, Sendable {` / `public let displayUUID: String` / `public let spaceID: UInt64?`
- `Sources/TransomModel/Persistence.swift:25`: `public static let maxEncodedBytes = 16 * 1024 * 1024`
- `Sources/TransomEngine/Arranger.swift:619-620`: `case .appResponsiveness, .appLaunched, .displaysChanged:` / `break`
- `Sources/TransomEngine/Arranger.swift:40-41`: `public enum PauseReason: Int, Comparable, Hashable, Sendable {` / `case stageManager = 0, crashLoop = 1, user = 2`
- `Sources/TransomEngine/LayoutRestore.swift:37-40`: `!identity.isSyntheticWindowID && live.contains {` / `$0.layer == 0 && $0.windowID == identity.windowID && $0.pid == identity.pid && $0.spaces?.isEmpty != true`
- `Sources/TransomEngine/CloseRule.swift:48-49,53`: `case (.alive, .invalidElement, false): return .closed` / `case (.alive, .invalidElement, true): return isKnownTabMember ? .state(.absent) : .recheck` / `case (.alive, .valid(false, _, _, _), true): return .noChange`
- `Sources/TransomMac/AXWindowSystem.swift:590-595`: `private func displaysDidChange() {` … `displays = Displays.current()` / `continuation.yield(.displaysChanged)` / `scheduler?.scheduleAll(after: .milliseconds(500))`

## Architecture Patterns

### System Architecture Diagram

```
 OS signals                         Shell (TransomMac, MainActor)                    Engine (pure)             Effects
 ─────────                          ─────────────────────────────                    ─────────────             ───────
 activeSpaceDidChange ───────────▶ AXWindowSystem.spaceDidChange ──▶ .spaceChanged ─▶ Arranger: plan shown desk ─▶ AX setFrame (shown Space only)
        │                               │                                              (dirty hidden desks wait, D-14)
        │                               └─▶ SpacesProvider.refresh() ── SpacesSnapshot ─▶ OverviewLayout / Debug S1
        │                                       ▲ (SkyLightSpaces: CopyManagedDisplaySpaces,       ▲
        │                                       │  GetCurrentSpace, ManagementMode)                │
        └─(lookup off)─▶ CoVisibilitySpaces ◀── on-screen CG list after 1 s settle ───────────────┘

 CG reconfig callback (begin) ───▶ DisplaySettler.begin ──▶ .displaysSettling ─▶ Arranger: snapshot World, suspend
 didChangeScreenParameters ──────▶ DisplaySettler.touch (restart 1.5 s)            display re-homing, no plans
 SessionGate pause/resume ───────▶ DisplaySettler.hold / release
                                   1.5 s quiet & unlocked ─▶ .displaysSettled(arrangementID) ─▶ Arrangements.switch:
                                                                                     known → reattach stored World
                                                                                     new   → carry over + float vanished
                                                                                   ─▶ save(LayoutFile v2) ─▶ N12 if floated

 Hotkey ⌃⌥⌘A / menu / URL / F3·⌃↑ (takeover) ─▶ OverviewController.toggle
        │  SnapshotCapture (current Space, ≤120 ms) + cache (other Spaces)
        │  OverviewLayout(displays, spaces, desks plans) ─▶ StagePanel per display (strip + main area)
        │  temporary Carbon keys (arrows/Tab/Return/Esc) ─▶ OverviewSelection
        └─ pick ─▶ same Space: focus (existing AX path)
                   other Space: SpaceSwitcher.post(chord ×|Δ|) ─▶ wait spaceChanged ≤1 s ─▶ focus ─ or beep "Couldn't switch"

 Menu "Replace Mission Control" ─▶ MissionControlTakeover (TakeoverPolicy)
        store originals (UserDefaults, never overwrite) ─▶ SymbolicHotKeys.setEnabled(32,108,…,false) ─▶ read back
        ─ ok ─▶ register Carbon keys for user's chord + keycode 160 ─▶ arm canary
        ─ fail ─▶ restore originals, N11
 Launch: originals present? ─▶ restore first (unclean exit) ─▶ canary for this build? ─▶ stay off + N10 : re-apply if pref on
 Quit / toggle off / zoom off / Restore macOS Window Settings ─▶ unregister keys ─▶ restore originals ─▶ clear store + canary
```

### Recommended Project Structure (new files only)

```
Sources/TransomPrivate/
├── SkyLightSpaces.swift        # + managedDisplaySpaces() and managementMode(): raw reads (extend; same file, same capability)
├── SymbolicHotKeys.swift       # NEW: is/set/get symbolic hotkey; capability .symbolicHotKeys
└── CoreDock.swift              # NEW: CoreDockSendNotification; capability .coreDock
Sources/TransomEngine/
├── SpacesSnapshot.swift        # NEW: value types (SpaceInfo{id, uuid, type, displayUUID, index}); parse from [[String: Any]]-like input
├── SpaceRekey.swift            # NEW: World re-key by UUID table; v1 migration
├── Arrangements.swift          # NEW: ArrangementID, LayoutSet, switch/merge rule
├── CoVisibilitySpaces.swift    # NEW: lookup-off fallback clustering
├── OverviewLayout.swift        # NEW: strip/main-area geometry, mini-tile rects, labels (pure)
├── OverviewSelection.swift     # NEW: initial selection, arrows/Tab rules (pure)
└── TakeoverPolicy.swift        # NEW: launch/apply/lift/restore decisions over an injected store (pure)
Sources/TransomMac/
├── SpacesProvider.swift        # NEW: wraps SkyLightSpaces + NSScreen.screensHaveSeparateSpaces → SpacesSnapshot
├── DisplaySettler.swift        # NEW: CG reconfig callback + 1.5 s debounce + SessionGate hold
├── SpaceSwitcher.swift         # NEW: posts the user's chords; 1 s verification
├── MissionControlTakeover.swift# NEW: UserDefaults store, canary, Carbon key streams, CoreDock fallback
├── Overview/OverviewController.swift  # NEW: per-display StagePanel overview mode, captures, keys, picks
└── Shell/OverviewCopy.swift    # NEW: all strings (UI-SPEC), AppKit-free, unit-tested
Sources/transom-spaces-spike/main.swift  # NEW: Wave 0 VM spike harness (never run on host)
```

### Pattern 1: SpacesProvider on the existing SkyLightSpaces

**What:** Extend `SkyLightSpaces` in the same file, behind the same `Capability.spaces`. Add `managedDisplaySpaces() -> [[String: Any]]?` (`SLSCopyManagedDisplaySpaces`, `@convention(c) (Int32) -> Unmanaged<CFArray>?`, +1 retained) and `managementMode() -> Int32?`. The symbols are optional, like `currentSpace`, so a missing one never turns off the per-window lookup. Parse into Engine value types in a **pure** function that takes `[[String: Any]]`, so it is tested with fixture dictionaries copied from F1.

**Rules:**
- Space→display = the display dictionary whose `"Spaces"` array contains it. `"Display Identifier"` of a display dictionary may be a UUID or `"Main"` (spans mode, ASSUMED). Map `"Main"` to the main display's UUID: the menu-bar screen, `NSScreen.screens.first`.
- `type`: 0 = desktop, 4 = full screen, 2 = system (yabai `space.c` compares `SLSSpaceGetType` with 0/4/2 [CITED: github.com/koekeishiya/yabai src/space.c]). Skip type 2. Label type 4 by the app owning the full-screen window (UI-SPEC).
- `uuid` may be **empty** for a display's original Desktop on some systems [CITED: ianyh.com/blog/identifying-spaces-in-mac-os-x shows `uuid = ""`; Keyboard Maestro forum via search]. Persist an empty UUID as the synthetic key `"default:<displayUUID>"`, never as `""`.
- Separate Spaces: `NSScreen.screensHaveSeparateSpaces`, read in the app process after `NSApplication.shared` exists (F4). Cross-check `managementMode() == 1`. In spans mode, use the single Space list for every display (UI-SPEC: strip on the main display only); desks stay keyed per display UUID (D-12).
- Refresh on `activeSpaceDidChange`, on settled display change, and when the overview opens. It is WindowServer IPC, so it's cheap and fine on main (existing comment, `SkyLightSpaces.swift:7`).

```swift
// Source: pattern of SkyLightSpaces.swift:24-32 (existing), signature verified by local probe F1
typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
typealias GetSpaceManagementMode = @convention(c) (Int32) -> Int32
// in the same `functions` closure:
let copyMDS = dlsym(handle, "SLSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyManagedDisplaySpaces.self) }
public static func managedDisplaySpaces(session: CapabilitySession = Capabilities.session) -> [[String: Any]]? {
    guard session.isAvailable(.spaces), let functions, let copy = functions.copyMDS,
          let array = copy(functions.connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
    return array
}
```

### Pattern 2: Persist desks by Space UUID (D-13) with a side table, not a new DeskKey

**What:** Keep `DeskKey(displayUUID, spaceID: UInt64?)` exactly as it is. World's Codable, validation and every Arranger lookup depend on it. Add a **Space table** to `LayoutFile`: `spaces: [SavedSpace]` with `SavedSpace { id: UInt64, uuid: String }`, covering every numeric `spaceID` used by any desk in the file at save time. At load, a pure `SpaceRekey.rekey(world, saved: [UInt64: String], current: [String: UInt64]) -> (World, unmatched: [DeskKey])` re-keys each desk to the current runtime ID of its UUID.

- A desk whose UUID is unknown in this login (Space deleted) keeps its numeric key and is dormant. Its windows go through the normal `LayoutRestore` close path (they are not alive), and the log reads "layout.json migrated: {n} desks re-keyed by Space UUID, {u} unmatched kept dormant" (UI-SPEC).
- **Collision guard:** if an unmatched desk's numeric key equals a live Space's current ID, a new Space reused the number. Drop that desk's key to a quarantine (log it), so a new Space never inherits a stale layout.
- **v1 migration:** a schema-1 file has no table. Build the table from the current Spaces list (numeric → UUID) before re-keying. This is correct when the file was written in the same login session, which is the only case where its windows can re-attach at all: restore is by `WindowIdentity` (window ID + pid), and IDs do not survive an app relaunch or reboot. So the migration can at worst misfile empty desks after a reboot.
- **Reboot stability of numeric IDs is unverified** (no source found; host evidence is inconclusive: IDs 3,4,5,7,8 coexist with 149). The UUID side table makes the answer irrelevant for correctness. The VM reboot spike only confirms that UUIDs persist (UI-SPEC backstop).

### Pattern 3: Space switching (Claude's discretion: decided)

**Decision:** post the user's own Mission Control chords as synthetic key events. Read them with the read-only getter, so a customised chord works. Never write SkyLight Space state.

1. **Strip click (Space S on display D):** compute Δ = index(S) − index(current) within D's ordered `"Spaces"` list. Then:
   - If "Switch to Desktop n" (IDs 118+n−1) is **enabled** by the user and S is a desktop Space with n ≤ 16, post that chord once.
   - Else post "Move right a space" (81) or "Move left a space" (79) |Δ| times, 0 ms apart: macOS chains the transitions.
   - If the needed hotkey is disabled or the getter is missing, fall back to the default chords (⌃→ / ⌃←, keycodes 124/123 with ⌃). If no Space change is seen within 1 s: beep + "Couldn't switch to Desktop {n}" (UI-SPEC Surface 2).
2. **Pick a window on another Space:** switch as above, wait for `.spaceChanged` on D (≤ 1 s), then run the existing focus path (`AXWindowSystem.focus`: AXMain + AXRaise + activate + AXFrontmost fallback). After the switch, AX lists the window, so its element is cached. Before the switch it usually is not, because AX lists only current-Space windows.
3. **Posting details:** use `CGEventSource(stateID: .hidSystemState)` and post to `.cghidEventTap`. **Set `event.flags` explicitly** (keyDown + keyUp, ⌃ plus the chord's flags, without the 0x800000 fn bit). CGEvent creation otherwise starts from the current modifier state [CITED: ianyh.com blog "accessibility-windows-and-spaces-in-os-x" via search]. Synthetic HID events trigger symbolic hotkeys: `osascript … key code 160` opening Mission Control is community-documented [CITED: macscripter.net] and the VM used ⌃→ during G-03-8. Transom's event tap mask is mouse + flagsChanged, so there is no self-loop.
4. **Display ambiguity:** which display a posted ⌃→ acts on in multi-display separate-Spaces mode is **unverified** (likely the display under the pointer) [ASSUMED]. A pointer click on a strip is on that display, so it's safe. For a keyboard pick after Tab on another display, the window case may use the yabai focus route (`_SLPSSetFrontProcessWithOptions(&psn, wid, 0x200 /*kCPSUserGenerated*/)` + two `SLPSPostEventRecordTo` key-window records) [CITED: yabai `window_manager_focus_window_without_raise`, MIT]. AltTab reports this route switches to the window's Space [CITED: alt-tab-macos commit c927920 comment]. **Ship this only if the spike shows the posted chord switches the wrong display**, and put it in its own `TransomPrivate/FrontProcess.swift` with a capability. Otherwise, for a cross-display thumbnail pick by keyboard, accept "Couldn't switch" when no change is seen.

### Pattern 4: Mission Control takeover with crash-safe restore (OVER-02, OVER-03)

**IDs taken:** `[32, 108]` always (⌃↑ and the Mission Control key). `34` (⌃⇧↑) and `113` (⇧ + Mission Control key) only if the VM spike shows they open Mission Control as "slow" variants. `33/35/115/117` (application windows) and `79–82` are **never** touched (D-08, UI-SPEC). Store exactly the IDs disabled.

**Signatures** (no connection argument):
```swift
// Getter verified by local probe F3 (rc 0, sane values). Setter shape from alt-tab-macos commit 848ae5f
// (hotkey Int, Bool) -> CGError [CITED]; the SLS* names resolve too (F2) — prefer SLS*, fall back to CGS*.
typealias IsEnabled  = @convention(c) (Int32) -> Bool
typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32      // CGError
typealias GetValue   = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>,
                                       UnsafeMutablePointer<UInt32>) -> Int32
```

**State machine (pure `TakeoverPolicy` over an injected store; shell executes):**

| Event | Action |
|---|---|
| Launch | (1) If `takeover.originals` exists, the previous run did not lift cleanly: **restore each stored ID to its stored enabled value, read back, then delete originals**. This runs first, before the Arranger starts (UI-SPEC: "restored before anything else"). (2) If the takeover canary for this OS build + app version is set: stay off, queue N10 once, Debug "off after a crash last launch". (3) Else if the preference is on and zoom is on and the capability is available: apply |
| Apply | (1) Read current enabled state of each ID. (2) **Write originals only if none are stored** (never overwrite: a second apply after a failed restore must not record "disabled" as original). (3) `setEnabled(id, false)` for each. (4) Read back: all false → register Carbon keys and arm the canary. Any true → restore originals, keep the toggle off, N11 |
| Lift (toggle off, zoom off, "Restore macOS Window Settings", quit) | Unregister Carbon keys → restore originals → read back → delete originals → clear canary. On quit this runs inside `AppDelegate.applicationShouldTerminate`'s restore (`AppDelegate.swift:31-40`), so SIGTERM and logout also lift (`handleSIGTERM`) |
| Trigger (Carbon key) | Overview open → dismiss. Overview can open → open. Otherwise → `CoreDock.send("com.apple.expose.awake")`, else beep + refusal |

- **Carbon keys for the freed chords:** `KeyboardShortcuts.events(for: Shortcut(carbonKeyCode: Int(vk), carbonModifiers: carbon(mods)))` for hotkey 32's *current* value, plus `Shortcut(carbonKeyCode: 160)` for 108. Map NX flags to Carbon (`0x20000`→`shiftKey 0x200`, `0x40000`→`controlKey 0x1000`, `0x80000`→`optionKey 0x800`, `0x100000`→`cmdKey 0x100`; drop `0x800000`). Register only **after** read-back confirms the disable, and unregister **before** restoring.
- **`{Keys}` copy** (UI-SPEC): from hotkey 32's enabled state and value *before* apply. Disabled by the user → "The Mission Control key (F3)" only, and 32 is not stored (nothing to restore).
- **Canary:** a copy of `MultitouchCanary` with its own key, e.g. `privateCanary.MissionControl` [ASSUMED name]. Armed on successful apply, cleared on lift. A leftover from a different OS build or app version is cleared, per MultitouchCanary semantics. D-07 says copy, so copy rather than abstract.
- **Drift:** System Settings ▸ Keyboard Shortcuts may re-enable a hotkey while the takeover is on [ASSUMED]. Re-read the enabled state when the status menu opens and on each takeover trigger. If one is enabled again, re-apply silently, keeping the stored originals.
- **New capabilities:** `case symbolicHotKeys = "SymbolicHotKeys"` (fallback "Mission Control keys unchanged") and `case coreDock = "CoreDock"` (fallback "beep instead of Mission Control") [ASSUMED raw names; they become a `--disable-private=` contract, so pick once].

### Pattern 5: LayoutFile schema 2 and migration

```swift
// TransomEngine/LayoutFile.swift (shape; field names are a recommendation)
public struct LayoutFile: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public var schemaVersion: Int
    public var world: World                    // the CURRENT arrangement's World (Arranger unchanged)
    public var arrangement: [String]           // sorted display UUIDs of `world` (D-09); [] = unknown (v1 migration)
    public var layoutSets: [LayoutSet]         // other arrangements, sorted by ID, capped (e.g. 16, LRU by lastUsed)
    public var spaces: [SavedSpace]            // numeric id → UUID for every spaceID used in world + layoutSets
    public var homeFrames: [HomeFrame]
    public var wantedFrames: [HomeFrame]
    public var session: SessionRecord
}
public struct LayoutSet: Codable, Equatable, Sendable { public var arrangement: [String]; public var world: World; public var lastUsed: Date }
public struct SavedSpace: Codable, Equatable, Sendable { public var id: UInt64; public var uuid: String }
```
- **Bump to 2** (not additive-optional like `wantedFrames`). A v1 Transom then sees schema 2 as newer: it leaves the file untouched and saves nothing (existing T-03-18 rule). That way a downgrade can't silently drop the layout sets.
- **LayoutStore must accept version 1:** change `LayoutStore.swift:96-97` so that `1` decodes through a `LayoutFileV1` shape (the current struct, renamed) and converts with `arrangement = []`, `layoutSets = []` and `spaces` built at restore time from the live Spaces list. Leaving the `version == LayoutFile.schemaVersion` guard in place **sets every user's layout.json aside as `.corrupt`** on first launch. This is the #1 regression to test.
- `World.currentSchemaVersion` stays 1. The World shape is unchanged; each LayoutSet carries a World and reuses World's validated decode.
- Validation on load: every `LayoutSet.arrangement` is sorted and unique, no duplicate arrangement IDs, `spaces` IDs unique. Each set's World validates on its own (a window may appear in several sets, never twice in one). Keep the 16 MiB cap (`Persistence.swift:25`) on the whole file.
- A schema-1 `arrangement = []` is adopted as "the current arrangement" at the first settled inventory.

### Pattern 6: Overview on the Phase 4 StagePanel

- **One `OverviewController`** in the shell owns overview mode across all displays. It reuses `StagePanel` (one per screen, lazy) and `TileLayer` (snapshot / fallback / collapsed block), adding strip layers (thumbnails, mini tiles, label capsules) and the selection ring.
- **The command is handled in the shell, not by the Arranger:** `Arranger.process(.command(.camera…))` rejects camera commands without a display (`Arranger.swift`, "camera command without a display"). Add `CameraCommand.overview` (UI-SPEC: `.camera(.overview)`) and route it in `ArrangeController.dispatch` like `toggleExcludeFrontmost`. It joins `Hotkeys.zoomNames` automatically through the `.camera` case (`Hotkeys.swift:105`).
- **Pure geometry (`OverviewLayout`)**, with inputs = displays (`visibleFrame`), `SpacesSnapshot`, planned frames per desk, the home-view tile rects for zoomed displays and the window order. Outputs = strip band rect, thumbnail rects (clamp `visibleFrame.height × 0.12` to 64…112, shrink-to-fit down to 32), main-area transform, mini-tile rects, labels. Desk plans for hidden Spaces come from `Planner.plan(desk:area:gap:mins:)` on the stored World: no AX reads, D-14 safe.
- **Pure selection (`OverviewSelection`):** the UI-SPEC Surface 3 rules (45° cone, strip transitions, Tab order by display frame, the initial-selection cascade), unit-tested.
- **Keys:** temporary `KeyboardShortcuts.events(for: Shortcut(...))` streams for ← → ↑ ↓, Tab, ⇧Tab, Return, keypad Enter and Esc while open. Cancel the tasks on close: the same mechanism as pick-mode Esc (`ZoomInput.swift:179-184`).
- **Interruptions** (UI-SPEC): `.spaceChanged`, `.displaysChanged`/settling, sessionPaused, `.windowFocused` from ⌘Tab, any command, menu open → fade 120 ms. Wire them where `zoomInput.endPick` is already called in `ArrangeController.start()` (`.spaceChanged`, `.windowFocused`, `.displaysChanged` branches).
- **Snapshots:** current Space via `SnapshotCapture.captureAll` (concurrency 4, 120 ms budget). Background capture once per Space visit after 1 s settle, only with zoom on and Screen Recording granted. Cache keyed by window ID, evicted on `windowDestroyed`. Never capture a window whose Space is hidden (D-03).

### Pattern 7: Display settling and arrangement layout sets (OVER-05, OVER-06, D-09..D-11)

**Problem in today's code:** `displaysDidChange` yields `.displaysChanged` at once, and `ArrangeController` feeds an inventory immediately. `Arranger.place` then calls `rehome`, which **removes** a window from its tile and floats it as soon as macOS moves it to another display. On re-plug nothing remembers the tile. D-10 needs "return to their tiles on re-plug". The fix is a settling window plus layout sets:

1. **Begin:** on the first CG reconfiguration callback (`kCGDisplayBeginConfigurationFlag`) or the first `didChangeScreenParameters`, whichever comes first, send `.displaysSettling`. The Arranger copies `preChangeWorld = world` and sets `settling = true`. While settling, `rehome` skips display-based moves (Space-based moves stay), and `planShown` sends no frames. Gap handles hide.
2. **Debounce:** restart a 1.5 s timer on each `didChangeScreenParameters`. Hold it while `SessionGate.isPaused`; on resume, restart the full 1.5 s (D-11). Debug S2 shows "Displays: settling…" / "Displays: waiting for wake".
3. **Settled:** read `Displays.current()` and the SpacesSnapshot, compute `ArrangementID(sorted UUIDs)` and send `.displaysSettled(id)` with the inventory.
   - **Same ID:** re-plan on new frames (resolution or rearrangement only).
   - **Known ID (a stored LayoutSet):** stash `preChangeWorld` as the set for the old ID. Load the stored World. Run `LayoutRestore.reattach(stored, tracked: inventory.windows, live:)`, the same code path as launch restore, so the dormant, synthetic-ID and closed rules all apply. Then re-plan. **Merge rule:** a window the user docked or moved by hand while in the old arrangement (an undoable edit after the last switch) keeps its current placement, and is removed from the stored World before reattach (UI-SPEC: "user action wins").
   - **New ID:** stash `preChangeWorld` under the old ID. Continue with the current World, whose vanished-display desks are naturally dormant (only `displays.map(Self.key)` desks are planned). Clear `settling` and feed the inventory: the existing `rehome` floats the moved windows on their new display's desk at their frames. The UI-SPEC wants a cascade from the Desktop tile's top-left; add that as a frame transform for windows whose desk display vanished. Emit N12 with the count.
4. **Re-plug into the original arrangement** is the "known ID" case: the stashed pre-unplug World comes back, so its windows return to their tiles (D-10).
5. Arrangement IDs and layout sets save with the normal debounced save.

**Space movement on unplug:** macOS moves a vanished display's Spaces onto a remaining display and keeps their UUIDs. That is what `"Collapsed Space"` and the per-Space `"Display Identifier"` records in `com.apple.spaces` suggest (F1). So after unplug, a Space's numeric ID can appear under the built-in display's UUID as `DeskKey(builtin, 3)`. Treat this as a new desk (floating). The old `DeskKey(DELL, 3)` stays dormant in the stashed set [ASSUMED interpretation; hardware checklist items 1–4 verify].

### Pattern 8: Co-visibility fallback (D-15)

Pure `CoVisibilitySpaces`. At each settled Space change (1 s after `activeSpaceDidChange`), it takes the on-screen layer-0 window IDs per display (public `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`). It joins the visit to the earlier cluster with the largest Jaccard overlap ≥ 0.5, else starts a new synthetic Space ID from a reserved high range (e.g. `0x8000_0000_0000_0000 | n`). IDs are session-only and **never persisted or used as DeskKeys**.

**Scope recommendation:** feed only the Debug line "Spaces: {v} visited since launch" and nothing that persists. Desks stay one per display with the lookup off (existing A7 behaviour, "Spaces lookup off: one layout per display"). The strip is hidden (D-15), so the overview needs no other-Space data. Wiring synthetic IDs into `WindowInfo.spaces` or `DeskKey` would risk mis-clustered windows being planned into the wrong desk and stale synthetic keys reaching layout.json. See Open Question 2.

### Pattern 9: G-03-9 fix (narrow)

Add one fact to `CloseRule.decide`: `cgSpacesKnownEmpty: Bool`. It is true when the window's CG entry is present **and** the Spaces lookup is available **and** it reported an empty set. Change only the rows where the ghost lands:

| Session | App | AX | CG | spacesKnownEmpty | tab member | Decision |
|---|---|---|---|---|---|---|
| active | alive | invalidElement | present | **true** | **false** | **closed** (was recheck) |
| active | terminated | any | present | **true** | any | **closed** (was recheck; the app is gone) |
| active | alive | valid, **unlisted**, not minimised/hidden/fullscreen | present | **true** | **false** | **recheck, then closed after N consecutive sweeps** (only if the VM probe shows the ghost answers *valid*; else leave noChange) |

- Rows for **minimised** and **⌘H-hidden** windows are decided earlier by AX (`valid(minimized/appHidden)` → `.state(.absent)`, `CloseRule.swift:51`). An empty Space set for them can't close them while AX answers valid. The VM probe confirms what SkyLight reports for minimised, hidden and hidden-tab windows.
- **Hidden native tabs report an empty Space set** (02-14, verified live on 27) [VERIFIED: STATE.md decision 02-14]. So the tab-member guard is mandatory. Tab-group `remaining` membership (`WindowTracker.swift`, `tabGroups.members(of:).intersection(inCG)`) keeps using the **raw** CG presence.
- `LayoutRestore.isAlive` already treats a no-Space entry as closed (`LayoutRestore.swift:37-40`). The relaunch half of G-03-9 is done; only the running-session half remains.

### Anti-Patterns to Avoid

- **Keying anything by the per-Space `"Display Identifier"` subkey.** It names a display the Space wants to go back to, not where it is (F1).
- **Calling `NSScreen.screensHaveSeparateSpaces` before `NSApplication.shared` exists**, for example in `transom-dump` or a test: it returns false (F4).
- **Reading Mission Control chords from `com.apple.symbolichotkeys`:** defaults are absent there (F3). Use the getter.
- **Overwriting stored originals on a second apply.** A failed restore would then record "disabled" as the original, and the user loses Mission Control for good.
- **Re-homing during display settling.** It destroys the tile memory the re-plug needs (Pattern 7).
- **Writing `DeskKey(spaceID: syntheticCoVisibilityID)` into the World**: it gets persisted.
- **Any AX write to a hidden-Space window** (D-14): planning only covers shown desks; keep it that way.
- **Capturing hidden-Space windows** (D-03).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Restoring a saved World against live windows after an arrangement switch | A new matching algorithm | `LayoutRestore.reattach` + `Arranger.reattach` path | Already handles dormant hidden-Space windows (G-03-8), synthetic IDs, closed windows and stranded frames |
| Global key capture for overview and takeover keys | keyDown in the CGEventTap, or a new Carbon wrapper | `KeyboardShortcuts.events(for: Shortcut)` | Already used for pick-mode Esc. It consumes the key; the tap mask stays mouse-only (T-03-28) |
| Separate-Spaces detection | Parsing `com.apple.spaces` | `NSScreen.screensHaveSeparateSpaces` (+ `SLSGetSpaceManagementMode` cross-check) | Public, and the plist may lag |
| Crash canary | A new persistence scheme | Copy of `MultitouchCanary` (D-07) | Already handles per-build/version semantics and the Debug wording |
| Session lock/sleep gating | New observers | `SessionGate` | Belt-and-braces signals, already verified on 27 |
| Snapshots | New SCK code | `SnapshotCapture.captureAll` / `cached` | Concurrency limit, cache and permission handling exist |
| Stage panels and tile drawing | New NSPanel/CALayer stack | `StagePanel`, `TileLayer`, `AppColor` | UI-SPEC requires Phase 4 surfaces unchanged |
| Opening macOS Mission Control | Posting ⌃↑ (it's disabled while the takeover is on) | `CoreDockSendNotification("com.apple.expose.awake", 0)` | Posting a disabled chord does nothing |

**Key insight:** every risky OS interaction here (hotkey state, Space state, display state) has either a session-scoped private write with a known restore, or a public read. The plan should never introduce a *persistent* system change. The only state change is the symbolic-hotkey disable, which dies at logout at worst.

## Runtime State Inventory

Phase 6 is not a rename. It does migrate persisted data and touches OS session state, so the inventory applies.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `~/Library/Application Support/Transom/layout.json` at schema 1 (World with numeric `spaceID`s) | **Code + data migration:** LayoutStore accepts schema 1, converts it to schema 2 in memory, and saves as 2 on the next debounced save. Test that v1 is never set aside as `.corrupt` |
| Stored data | UserDefaults (new keys): `takeover.enabled`, `takeover.explained`, `takeover.originals`, `privateCanary.MissionControl`, `KeyboardShortcuts_showOverview` (written by the library) [ASSUMED key names except the library's] | Code only. "Restore Defaults" in the Shortcuts window resets `showOverview` (UI-SPEC) |
| Live service config | None. No external services | None, verified by scope |
| OS-registered state | **WindowServer symbolic-hotkey enabled flags** for IDs 32, 108 (and optionally 34, 113). Session-scoped and persists after process exit [CITED: alt-tab-macos 848ae5f] | Restore at lift and quit, and at launch when originals are stored. VM crash test confirms |
| OS-registered state | Carbon hotkey registrations (process-scoped, die with the process) | None beyond unregistering on lift |
| Secrets/env vars | None | None |
| Build artifacts | New executable target `transom-spaces-spike` (build-only on host; runs in the VM) | Add it to Package.swift. vm-spike.sh already takes `SPIKE_PRODUCT` |

## Common Pitfalls

### Pitfall 1: LayoutStore sets every existing layout.json aside on upgrade
**What goes wrong:** bumping `LayoutFile.schemaVersion` to 2 while `LayoutStore.swift:97` still requires `version == LayoutFile.schemaVersion` turns every user's file into `layout.json.corrupt`.
**How to avoid:** add a version-1 decode branch and migration; test with a real schema-1 fixture taken from the current encoder.
**Warning signs:** log "rejected layout.json: corrupt(\"unknown schemaVersion 1\")".

### Pitfall 2: Takeover leaves the user without Mission Control
**What goes wrong:** a crash, kill -9 or a failed restore leaves IDs 32/108 disabled for the rest of the login session.
**Why:** the WindowServer flag outlives the process [CITED: alt-tab-macos 848ae5f].
**How to avoid:** originals are written before the first disable and never overwritten. The launch-time restore runs before anything else. Read back after every set. Restore on quit inside `applicationShouldTerminate`. A canary keeps a crashing build from re-applying.
**Warning signs:** F3 does nothing with Transom not running; Debug S5 says on while `SLSIsSymbolicHotKeyEnabled(32)` is true.

### Pitfall 3: The Mission Control key is a different hotkey from ⌃↑
**What goes wrong:** disabling only 32 leaves F3 (keycode 160, ID 108) opening Mission Control.
**How to avoid:** take `[32, 108]`. Let the VM spike decide 34/113 (F3).

### Pitfall 4: Re-homing during display reconfiguration loses the layout
**What goes wrong:** windows moved by macOS off a vanishing display are re-homed (removed from tiles) before the arrangement is recognised, so re-plug brings nothing back.
**How to avoid:** the settling state (Pattern 7) starts at the earliest signal (CG callback begin flag) and suspends display-based `rehome` and planning until settled.
**Warning signs:** on hardware checklist item 2, windows stay floating after re-plug.

### Pitfall 5: `screensHaveSeparateSpaces` lies outside an app
**What goes wrong:** a CLI or test reads false on a separate-Spaces machine (F4).
**How to avoid:** read it in the app process after `NSApplication.shared`. In tests, inject the flag.

### Pitfall 6: Empty or "Main" identifiers
**What goes wrong:** Desktop 1 may have `uuid = ""` (older/fresh systems) and spans mode may report `"Display Identifier" = "Main"`, giving duplicate or unmatched keys.
**How to avoid:** synthesise `"default:<displayUUID>"` for an empty UUID; map `"Main"` to the main display's UUID. Unit-test both with fixtures.

### Pitfall 7: Posted chord modifiers inherit the user's held keys
**What goes wrong:** a Return pressed with ⇧ held, or a lingering ⌃⌥⌘ from the Show Overview chord, changes the posted ⌃→ into ⌃⇧→ (a different hotkey).
**How to avoid:** set `flags` explicitly on both keyDown and keyUp, and post only after the hotkey's key-up.

### Pitfall 8: Symbolic hotkeys changed by the user while taken over
**What goes wrong:** System Settings re-enables 32, so F3 opens both Mission Control and the overview, or Mission Control wins [ASSUMED].
**How to avoid:** re-check when the menu opens and on each trigger; re-apply silently without touching the stored originals.

### Pitfall 9: Four-finger swipe consumption
**What goes wrong:** a filter that consumes type-30 events too broadly blocks ⌃←/→-equivalent Space swipes while Transom runs.
**Known:** a session tap *sees* type-30 events on 27.2 (05-SPIKE T4: "80 Dock-control events observed and never consumed"). Whether *consuming* them stops the Dock is unknown. The Tart VM has no multi-finger trackpad, so the real test can only be a bounded user-run host check.
**How to avoid:** ship [swipe kept] unless that check passes (D-05). A tap dies with its process, so this risk has no crash persistence, unlike the hotkeys.

### Pitfall 10: G-03-9 fix closes live windows
**What goes wrong:** hidden native tabs (empty Space set, 02-14) or minimised windows are treated as closed.
**How to avoid:** change only the rows in Pattern 9; keep the tab-member guard and raw-CG tab membership. VM-probe what minimised, hidden and hidden-tab windows report first.

### Pitfall 11: Space switch on the wrong display (multi-display keyboard picks)
**What goes wrong:** posted ⌃→ acts on the pointer's display [ASSUMED], not the selected one.
**How to avoid:** pointer picks are safe. For keyboard picks across displays, use the SLPS focus route for windows if the spike shows the problem; otherwise "Couldn't switch".

### Pitfall 12: Overview opened while a display is settling
**What goes wrong:** geometry from stale `visibleFrame`s, or panels on a vanished screen.
**How to avoid:** the overview refuses or interrupts while settling (UI-SPEC: display change interrupts the overview). `StagePanel` lookup goes through `Displays.screen(uuid:)` at open time.

### Pitfall 13: Identical external displays
**What goes wrong:** two monitors of the same model without serials can report swapped or equal UUIDs, so the arrangement ID is ambiguous [ASSUMED].
**How to avoid:** `Displays.current()` already skips a display without a UUID. Log duplicate UUIDs and treat the arrangement as "new" (carry over) rather than applying a stored set.

## Code Examples

### Reading the user's Mission Control chord and taking over (shape)
```swift
// TransomPrivate/SymbolicHotKeys.swift — getter signature verified by local probe (F3); setter shape [CITED: alt-tab-macos 848ae5f]
public enum SymbolicHotKeys {
    public static let missionControl: Int32 = 32       // ⌃↑ by default (F3 enumeration)
    public static let missionControlKey: Int32 = 108   // keycode 160, no modifier (F3 enumeration; meaning ASSUMED)
    public struct Value: Equatable, Sendable { public let keyCode: UInt16; public let modifiers: UInt32 }
    private static let fns: (isOn: IsEnabled, set: SetEnabled, get: GetValue)? = {
        guard !Capabilities.isForcedOff(.symbolicHotKeys),
              let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let i = dlsym(h, "SLSIsSymbolicHotKeyEnabled") ?? dlsym(h, "CGSIsSymbolicHotKeyEnabled"),
              let s = dlsym(h, "SLSSetSymbolicHotKeyEnabled") ?? dlsym(h, "CGSSetSymbolicHotKeyEnabled"),
              let g = dlsym(h, "SLSGetSymbolicHotKeyValue") ?? dlsym(h, "CGSGetSymbolicHotKeyValue")
        else { return nil }
        return (unsafeBitCast(i, to: IsEnabled.self), unsafeBitCast(s, to: SetEnabled.self), unsafeBitCast(g, to: GetValue.self))
    }()
    public static func isEnabled(_ id: Int32) -> Bool? { fns.map { $0.isOn(id) } }
    public static func setEnabled(_ id: Int32, _ on: Bool) -> Bool { fns.map { $0.set(id, on) == 0 } ?? false }
    public static func value(_ id: Int32) -> Value? {
        guard let fns else { return nil }
        var ch: UInt16 = 0, vk: UInt16 = 0, mods: UInt32 = 0
        return fns.get(id, &ch, &vk, &mods) == 0 ? Value(keyCode: vk, modifiers: mods) : nil
    }
}
```

### Opening macOS Mission Control as the fallback
```swift
// TransomPrivate/CoreDock.swift — symbol in HIServices (F2); signature (CFStringRef, int) [CITED: gist unixzii]
typealias SendNotification = @convention(c) (CFString, Int32) -> Void
// dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
// send("com.apple.expose.awake" as CFString, 0)   // toggles Mission Control (VM spike confirms it works with 32/108 disabled)
```

### Posting a Space-switch chord with explicit flags
```swift
// TransomMac/SpaceSwitcher.swift (public CGEvent API)
func post(keyCode: CGKeyCode, flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down) else { return }
        e.flags = flags            // never inherit held modifiers (Pitfall 7)
        e.post(tap: .cghidEventTap)
    }
}
// default "move right a space": keyCode 124, flags .maskControl  (ID 81 value: vk 124, 0x940000 incl. fn bit — drop fn)
```

### Debounced settling (shell)
```swift
// TransomMac/DisplaySettler.swift (shape)
CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
    guard flags.contains(.beginConfigurationFlag), let userInfo else { return }
    let settler = Unmanaged<DisplaySettler>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { MainActor.assumeIsolated { settler.begin() } }   // thread not documented: always hop
}, Unmanaged.passUnretained(self).toOpaque())
// didChangeScreenParameters → touch(): restart 1.5 s WakeTimer unless SessionGate.isPaused (then wait for resume)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Space IDs from `com.apple.spaces` plist reads | Live `SLSCopyManagedDisplaySpaces` | long-standing (yabai, Amethyst) | The plist names the main display "Main" and lags; read live |
| `CGWindowListCreateImage` for previews | `SCScreenshotManager` (existing) | macOS 14/15 | Already in Phase 4 |
| Persisting layouts by numeric Space ID | By Space UUID (Amethyst `layoutsBySpaceUUID`, MIT; .planning/research/ARCHITECTURE.md) | — | D-13 |
| `CVDisplayLink` | `NSView.displayLink` | macOS 14 | Existing stage |

**Deprecated/outdated:** `GetProcessForPID` (deprecated since 10.9, still exported) is only needed for the optional SLPS focus fallback.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Symbolic hotkey 108 (vk 160, no modifier) is what the F3 Mission Control key triggers; 34/113 are "slow" variants | Verified Facts F3, Pattern 4 | F3 keeps opening Mission Control (takeover half-works). VM spike posts key code 160 with 108 disabled |
| A2 | Disabled state persists for the login session after kill -9, and the Dock respects it live without restart | Pattern 4, Pitfall 2 | If it reverts on exit, crash restore is moot (harmless). If the Dock ignores it, the takeover fails read-back-independently. VM crash test |
| A3 | `CoreDockSendNotification("com.apple.expose.awake", 0)` opens Mission Control with 32/108 disabled | Pattern 4 | Fallback does nothing → beep path. VM spike |
| A4 | Posted ⌃→/⌃← (and ⌃n when enabled) switch Spaces; multi-display: acts on the pointer's display | Pattern 3, Pitfall 11 | Strip clicks fail → "Couldn't switch". VM spike (single display) + hardware checklist item 7 |
| A5 | `"Display Identifier" = "Main"` in spans mode; Desktop 1 may have empty uuid | Pattern 1, Pitfall 6 | Unmatched desks in spans mode. Hardware checklist item 6; VM plist read |
| A6 | macOS moves a vanished display's Spaces onto the remaining display, keeping UUIDs | Pattern 7 | Desk keys after unplug differ from expectation. Hardware checklist 1–4 |
| A7 | Safari's ghost answers -25202 (invalidElement) rather than valid-unlisted | Pattern 9 | If valid-unlisted, the narrow fix needs the bounded-recheck row. VM ghost probe |
| A8 | Numeric Space IDs are reassigned at reboot (unknown either way) | Pattern 2 | None for correctness (UUID table). VM reboot diff |
| A9 | `SLSManagedDisplaySetCurrentSpace` desyncs the Dock | Alternatives | Only affects a rejected option |
| A10 | Capability raw names `SymbolicHotKeys` / `CoreDock` and UserDefaults key names | Pattern 4, Runtime State | Naming only; but `--disable-private=` names become a contract |
| A11 | System Settings can re-enable a taken hotkey behind Transom's back | Pitfall 8 | Drift check costs little either way |
| A12 | Identical external displays can share or swap UUIDs | Pitfall 13 | Wrong layout set applied. Logged; treated as a new arrangement |

## Open Questions

1. **Exact takeover ID set beyond `[32, 108]`.**
   - Known: 34 = ⌃⇧↑ and 109–117 = keycode 160 with modifiers (F3).
   - Unclear: which of them open Mission Control versus Show Desktop, application windows or settings.
   - Recommendation: the VM spike posts each chord with only 32/108 disabled and records which still opens Mission Control. Take only the Mission Control ones.
2. **Does D-15's co-visibility map feed desks?**
   - Known: D-15 says build it and hide the strip; desks today are per display with the lookup off.
   - Unclear: whether the user expects per-Space layouts without SkyLight.
   - Recommendation: Debug-only (Pattern 8). Ask in plan review if in doubt; per-Space desks on clustered IDs are the riskier reading.
3. **Merge rule detail for "user action wins" on arrangement switch.**
   - Recommendation: track `userPlacedSinceSwitch: Set<WindowIdentity>`, filled by undoable edits (`World.edit` callers) after the last switch. Remove those windows from the stored World before reattach. Unit-test with FakeWindowSystem `setDisplays`.
4. **Behaviour on macOS 14.** Neither VM nor host runs 14. A `ghcr.io/cirruslabs/macos-sonoma-vanilla` VM could cover it (not present locally). Otherwise, accept 15.7.7 (VM) plus 27.2 (host) as evidence.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift toolchain | build/tests | ✓ | Apple Swift 6.4.2, Xcode 27.2 | — |
| Tart | VM spikes and live suites | ✓ | 2.40.1 | — |
| VM `pane-test` | spikes, live tests | ✓ (stopped; start through the scripts) | macOS 15.7.7, 2 Spaces (IDs 1 and 41, per G-03-8 notes) | — |
| VM SSH key | scripts | ✓ | `~/.ssh/pane_vm_ed25519` | — |
| Second display + hot-plug | OVER-05/06 | VM ✗; host ✓ (MacBook Air + DELL) | — | **User hardware checklist** (UI-SPEC items 1–7) |
| Multi-finger trackpad in VM | swipe spike | ✗ | — | User-run bounded host check, or ship [swipe kept] |
| macOS 14 test system | "14, 15 and 27" UAT note | ✗ | — | Optional sonoma VM image; else note the gap |

**Missing dependencies with no fallback:** none blocking. Multi-display and swipe behaviour are verified by the user on hardware.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`, `@Test`, `#expect`) via SwiftPM, toolchain 6.4.2 |
| Config file | `Package.swift` (test targets `TransomModelTests`, `TransomEngineTests`, `TransomMacTests`, `TransomMacIntegrationTests`) |
| Quick run command | `swift test --filter TransomEngineTests` (or a suite: `swift test --filter ArrangementsTests`) |
| Full suite command | `swift test` (live suites skip without `TRANSOM_LIVE=1`) + `scripts/check-no-appkit.sh` |
| VM live command | `scripts/vm-live-test.sh <Filter>` (TRANSOM_LIVE=1 in the guest) |
| VM spike command | `SPIKE_PRODUCT=transom-spaces-spike scripts/vm-spike.sh <subcommand>` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OVER-01 | SpacesSnapshot parses F1 fixtures (UUID, "Main", empty uuid, type 4, Spaces grouping) | unit | `swift test --filter SpacesSnapshotTests` | ❌ Wave 0 |
| OVER-01 | Overview geometry: strip band, thumbnail clamp/shrink to 16 Spaces, main-area transform, mini-tile rects from desk plans | unit | `swift test --filter OverviewLayoutTests` | ❌ Wave 0 |
| OVER-01 | Selection: initial cascade, 45° arrows, strip ↑/↓, Tab wrap, closed-item reselect | unit | `swift test --filter OverviewSelectionTests` | ❌ Wave 0 |
| OVER-01 | OverviewCopy strings, plurals, `{Keys}` branches | unit | `swift test --filter OverviewCopyTests` | ❌ Wave 0 |
| OVER-01 | Space-switch plan: Δ computation, ⌃n preference, chord from getter value, flag stripping | unit | `swift test --filter SpaceSwitcherTests` | ❌ Wave 0 |
| OVER-01 | Strip click and other-Space pick land on the Space and focus the window | VM live | `scripts/vm-live-test.sh OverviewSpaceSwitchIntegrationTests` (fixture windows on Spaces 1/41) | ❌ |
| OVER-02 | TakeoverPolicy: apply stores originals once, read-back failure restores, lift order, zoom-off lift/re-apply, Restore macOS Window Settings | unit | `swift test --filter TakeoverPolicyTests` | ❌ Wave 0 |
| OVER-02 | Carbon key mapping from NX flags (32's value) and keycode 160 | unit | `swift test --filter TakeoverKeysTests` | ❌ Wave 0 |
| OVER-02 | Disabling 32/108 stops Mission Control; posted key code 160 / ⌃↑ reach Transom; CoreDock opens Mission Control | VM spike | `SPIKE_PRODUCT=transom-spaces-spike scripts/vm-spike.sh hotkeys` | ❌ |
| OVER-03 | Launch with stored originals restores before anything; canary per build/version; N10 once; never overwrite originals | unit | `swift test --filter TakeoverPolicyTests` | ❌ Wave 0 |
| OVER-03 | kill -9 with the takeover on → hotkeys stay disabled → relaunch restores → Mission Control opens | VM spike | `... vm-spike.sh takeover-crash` (two runs: `apply-then-abort`, then `check-restore`) | ❌ |
| OVER-04 | Hidden desk changes are not planned until shown (D-14); no setFrame to hidden-Space windows | unit (FakeWindowSystem) | `swift test --filter ArrangerSpacesTests` (extend) | ✅ extend |
| OVER-04 | SpaceRekey: UUID re-key, unmatched dormant, collision quarantine, v1 migration | unit | `swift test --filter SpaceRekeyTests` | ❌ Wave 0 |
| OVER-04 | LayoutStore loads schema 1 (not `.corrupt`), saves 2, newer (3) still blocks saving | unit | `swift test --filter LayoutStoreTests` (extend) | ✅ extend |
| OVER-04 | Space UUIDs survive a VM reboot; desks on Desktop 2 come back on Desktop 2 | VM spike | `... vm-spike.sh spaces-dump` before and after a guest restart, diff | ❌ |
| OVER-05 | Settling: no re-home or plans while settling; held while paused; 1.5 s restart; re-plug restores tiles | unit (FakeWindowSystem `setDisplays`) | `swift test --filter ArrangerDisplaySettleTests` | ❌ Wave 0 |
| OVER-05 | Unplug floats with cascade + N12 count; re-plug silent return; user-docked window stays | unit | `swift test --filter ArrangerDisplaySettleTests` | ❌ Wave 0 |
| OVER-05 | Real unplug/re-plug, sleep with change | manual | UI-SPEC hardware checklist items 1, 2, 3, 5 | — |
| OVER-06 | ArrangementID sorting/equality; known set reattached; new set carries over; LRU cap; save/load round-trip | unit | `swift test --filter ArrangementsTests` | ❌ Wave 0 |
| OVER-06 | Dock/undock cycles | manual | UI-SPEC hardware checklist item 4; item 6 (separate Spaces off) | — |
| G-03-9 | Ghost (invalidElement + CG present + no Space, not a tab member) closes; hidden tab and minimised do not | unit | `swift test --filter CloseRuleTests` + `CloseScenarioTests` (extend) | ✅ extend |
| G-03-9 | AX answer and Space sets for the Safari ghost, minimised, ⌘H-hidden, hidden tab | VM spike | `... vm-spike.sh ghost` | ❌ |
| D-15 | Co-visibility clustering (Jaccard join, synthetic range, never persisted) | unit | `swift test --filter CoVisibilitySpacesTests` | ❌ Wave 0 |

### VM spike subcommands (`transom-spaces-spike`, Wave 0; one run at a time under the lock)
1. `spaces-dump`: symbol resolution on 15.7.7 (F2 list); `SLSCopyManagedDisplaySpaces` raw JSON; `SLSGetSpaceManagementMode`; `NSScreen.screensHaveSeparateSpaces` (with NSApplication); `defaults read com.apple.spaces`. Also once with a fixture window in native full screen, to capture the type-4 dictionary shape.
2. `hotkeys`: enumerate 0..<400. Disable `[32, 108]`, read back, then post `key code 160` and ⌃↑ and detect whether Mission Control opened (Dock-owned on-screen windows in the CG list + a still capture). Register Carbon streams for the freed chords and confirm they fire. Try `CoreDockSendNotification("com.apple.expose.awake")`. Test 34 and 113 the same way. **Restore originals in a `defer` and in a SIGINT handler.**
3. `takeover-crash`: run A stores originals in a file, disables, then `abort()`. Run B checks the state is still disabled, restores, and checks Mission Control opens again.
4. `switch`: with 2 Spaces, measure each method's latency to `activeSpaceDidChange`: posted ⌃→ ×1, ⌃→ ×2 (if a third Space exists), the SLPS focus of a fixture window on Space 41, and AX focus after the switch. Run with `AppleSpacesSwitchOnActivate` both 0 and 1, restoring the guest's original value.
5. `ghost`: G-03-9: Safari close lingering entry (AX error and Spaces), plus minimised, ⌘H-hidden and hidden-tab Space sets (the axghost probe from the g-03-9 doc).
6. Reboot diff: `spaces-dump` → `tart stop` / `tart run` → `spaces-dump`; compare UUIDs and numeric IDs.

### User hardware checklist
Use UI-SPEC items 1–7 verbatim. Add one takeover item for 27.2: turn on Replace Mission Control, press F3 and ⌃↑ (the overview opens), quit Transom (F3 opens Mission Control again), turn it on again, `kill -9` Transom (F3 still does nothing), relaunch (F3 opens Mission Control at once; toast N10). The swipe check, if attempted: a bounded `tap-consume` run of ≤ 30 s, user-started.

### Sampling Rate
- **Per task commit:** `swift test --filter <touched suite>` + `scripts/check-no-appkit.sh`
- **Per wave merge:** `swift test`
- **Phase gate:** full suite green; VM spikes 1–6 recorded in `06-SPIKE.md`; the relevant VM live suites pass; hardware checklist answered in `06-UAT.md` before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `Sources/transom-spaces-spike/main.swift` + Package.swift target: spikes 1–6
- [ ] `Tests/TransomEngineTests/Fixtures/Spaces/*.json`: F1 dictionaries (separate on, plus synthetic "Main", empty uuid and type-4 cases)
- [ ] Test files: `SpacesSnapshotTests`, `SpaceRekeyTests`, `ArrangementsTests`, `ArrangerDisplaySettleTests`, `TakeoverPolicyTests`, `TakeoverKeysTests`, `SpaceSwitcherTests`, `OverviewLayoutTests`, `OverviewSelectionTests`, `OverviewCopyTests`, `CoVisibilitySpacesTests`
- [ ] `FakeWindowSystem`: a per-display Spaces list (ordered, with UUIDs) and moving a vanished display's Spaces onto a remaining display, to model A6
- [ ] Schema-1 layout.json fixture for `LayoutStoreTests`

## Security Domain

`security_enforcement: true`, ASVS level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (local) | Only Transom's own process changes symbolic hotkeys. The `transom://overview` URL goes through the existing whitelist and once-per-second rate limit (`TransomURL`, `AppDelegate.swift:53-65`); no URL can toggle the takeover |
| V5 Input Validation | yes | layout.json is user-writable (T-03-15). Validate `layoutSets`, `arrangement` and `spaces` (sorted, unique, finite, within the 16 MiB cap); reject the whole file on doubt. SkyLight dictionaries are type-checked with `as?` and unknown types skipped (the T-02-38 style in `SkyLightSpaces.spaceIDs`) |
| V6 Cryptography | no | The arrangement `{id}` in Debug is a display hash, not a security control |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Crafted layout.json with a huge number of layout sets or Spaces | DoS | Size cap, set-count cap (LRU), validation, set-aside on reject |
| Takeover left on after a crash (user loses Mission Control) | DoS (availability) | Originals-first ordering, launch restore, canary, read-back |
| Synthetic key posting misfires into the frontmost app (wrong chord) | Tampering | Explicit flags; post only the user's own Mission Control chords from the getter; never post text keys |
| A malicious URL toggling system settings | Elevation | No URL for the takeover; the overview URL only shows UI |
| Window titles in logs or the overview cache | Information disclosure | Titles `.private` in logs; the snapshot cache is in memory only, evicted on close; panels have `sharingType = .none` (Phase 4) |
| Private API returns garbage after an OS update | Tampering / DoS | `as?` parsing, capability call-time degradation (`recordFailure`), feature-level fallback |

## Sources

### Primary (HIGH confidence)
- Local read-only probes on macOS 27.2 (26B123), 2026-10-31: dlsym resolution (F2), `SLSCopyManagedDisplaySpaces` output (F1), symbolic hotkey enumeration via `SLSGetSymbolicHotKeyValue`/`SLSIsSymbolicHotKeyEnabled` (F3), `SLSGetSpaceManagementMode`, `NSScreen.screensHaveSeparateSpaces`, display UUIDs (F4); `defaults read com.apple.spaces`, `com.apple.symbolichotkeys`, `com.apple.dock`, `NSGlobalDomain AppleSpacesSwitchOnActivate`, trackpad prefs.
- Repo source read this session: `SkyLightSpaces.swift`, `Capabilities.swift`, `Displays.swift`, `AXWindowSystem.swift`, `SessionGate.swift`, `Arranger.swift`, `LayoutRestore.swift`, `LayoutFile.swift`, `LayoutStore.swift`, `World.swift`, `IDs.swift`, `CloseRule.swift`, `WindowSystem.swift`, `AppDelegate.swift`, `ArrangeController.swift`, `GestureEventFields.swift`, `Hotkeys.swift`, KeyboardShortcuts checkout (`Shortcut.swift`, `KeyboardShortcuts.swift`), `scripts/vm-spike.sh`, `scripts/vm-live-test.sh`, `.planning/debug/g-03-9-closed-safari-lingers.md`, `.planning/debug/g-03-8-hidden-space-relaunch.md`, `05-SPIKE.md` (T4).

### Secondary (MEDIUM confidence)
- developer.apple.com `CGDisplayRegisterReconfigurationCallback` documentation JSON (before/after invocation, macOS 10.3+).
- github.com/lwouis/alt-tab-macos commit 848ae5f (`CGSSetSymbolicHotKeyEnabled(hotkey, Bool) -> CGError`; "the effect of enabling/disabling persists after the app is quit"). GPL-3: facts only.
- github.com/koekeishiya/yabai `src/window_manager.c` (`_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` focus), `src/space.c` (types 0/4/2), `src/display.c` (walks `"Spaces"`/`"id64"`/`"Display Identifier"`). MIT.

### Tertiary (LOW confidence, marked for validation)
- gist.github.com/unixzii/7091dda6aea958c6da669e436365df65: `CoreDockSendNotification(CFStringRef, int)`, `com.apple.expose.awake`.
- gist.github.com/mkhl/455002: symbolic hotkey 32 = ExposeAllWindows.
- gist.github.com/eegrok/949034 (comment), macscripter.net/t/-/73180: F3 = keycode 160.
- ianyh.com/blog/identifying-spaces-in-mac-os-x (2013): Space uuid can be empty; ianyh.com/blog/accessibility-windows-and-spaces-in-os-x: posting ⌃→, explicit modifier flags.
- github.com/lwouis/alt-tab-macos commit c927920: focusing a window in another Space switches to that Space.
- theregister.com 2009 "hotkeys framework": persistent changes need the `com.apple.symbolichotkeys` plist.
- Amethyst README (via search): Mission Control ⌃n shortcuts must be enabled for Space moves.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. Every symbol resolution and data shape was probed locally; no new packages.
- Architecture: MEDIUM. The patterns fit existing code paths, but the settling and arrangement merge rules are new design with no direct prior art.
- Pitfalls: MEDIUM. Several rest on [ASSUMED] OS behaviour that the Wave 0 VM spikes and the hardware checklist must confirm.

**Research date:** 2026-10-31
**Valid until:** 2026-11-30 for the repo-derived parts. Private-API facts must be re-probed on each macOS update (host 27.2, VM 15.7.7).
