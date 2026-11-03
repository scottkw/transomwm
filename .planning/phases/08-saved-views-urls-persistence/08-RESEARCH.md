# Phase 8: Saved Views, URLs & Persistence - Research

**Researched:** 2026-11-03
**Domain:** Swift/AppKit macOS window manager: persisted camera views, URL/CLI command routing over local IPC, window re-identification after relaunch/reboot, layout.json schema migration
**Confidence:** HIGH for the in-repo integration points (read this session); MEDIUM for the CFMessagePort and XcodeGen mechanics (official docs + SDK header, not exercised); LOW for ⌘Q event ordering, Tart guest reboot and SSH bootstrap visibility (flagged for VM probes)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Saved views (slots 1–9)
- **D-01:** The default chords are ⌥1–9 to go to a view and ⇧⌥1–9 to save one. When macOS refuses Option-only or
  Option+Shift chords (15.0–15.1), registration falls back to ⌃⌥1–9 and ⇧⌃⌥1–9. All chords are rebindable through
  KeyboardShortcuts, like the other Transom hotkeys. Digits are bound by key position, so they work on any keyboard
  layout ("layout-aware default chords" in the ROADMAP).
- **D-02:** A view stores its display, its Space and the window identities inside the zoomed area (or "home" for a
  whole-desk view). Going back zooms to the smallest node that holds the remaining saved windows, so the view survives
  splits, moves and reflows. It does not store the NodeID, which changes on split, or a screen rect.
- **D-03:** Going to a view that is on another Space or display switches there first, using the Phase 6 overview's
  Space-switch path, then zooms.
- **D-04:** Saving shows a short toast, "Saved view 3", or "Replaced view 3" when the slot was used. Going to a view
  shows "View 3". Both are announced to VoiceOver. An empty slot beeps and shows "No view in slot 3".
- **D-05:** If every window in a saved view has gone, going to it shows that desk's home view, with a notice. The slot
  stays saved.

#### URLs and the `transom` CLI
- **D-06:** The view URLs are `transom://view/<1-9>` and `transom://save-view/<1-9>`. The parser stays a strict
  allow-list. A path is accepted only for these two commands and only for a single digit 1–9; anything else is
  rejected without side effects. The rate limit stays once per second per command, and each slot counts as its own
  command.
- **D-07:** The CLI talks to the running app over a local request/reply channel (a CFMessagePort or similar), so it can
  report "unknown command", "Transom is not running" or "refused (rate limit)" and exit non-zero. Before sending, it
  checks the command with the same `TransomURL` parser from TransomEngine. The app treats CLI requests exactly like
  URL opens: same allow-list, same rate limit.
- **D-08:** If Transom is not running, the CLI prints "Transom is not running" and exits with code 2. It never launches
  the app.
- **D-09:** The `transom` binary ships inside the app bundle. The README gives a one-line `ln -s` install. `transom help`
  lists every command, and so does running it with no arguments. There is no install UI in this phase.

#### Re-matching after a relaunch or reboot
- **D-10:** Each window's match hints are persisted in layout.json: bundle ID, title, frame and its order within the
  app. They reuse WindowRef's existing `titleHint` / `axIdentifier` / `creationOrder` from Phase 1. Candidates are
  scored and a window is matched only above a threshold. On a tie, neither window is matched: the tile becomes a
  placeholder and the window floats.
  - **This supersedes T-03-17** (titles stripped from layout.json by `World.withoutTitleHints()`), because VIEW-04
    needs titles to tell an app's windows apart. layout.json must be written user-only (0600), and titles never go to
    logs at public level.
- **D-11:** Re-matching runs when Transom launches and whenever an app relaunches while Transom keeps running (new pid).
  Both paths use the same matcher. It extends `LayoutRestore.reattach`, which today removes saved windows whose app
  relaunched.
- **D-12:** A placeholder expires 10 s after its app has launched without a match, or 5 min after Transom launches if
  the app never opens. When it expires, the tile is removed through the normal close path, as if the window had closed.
- **D-12a (user, 2026-11-03):** When an app quits while Transom runs, its docked windows become placeholders (so D-11
  relaunch matching has something to fill). They expire 30 s after the quit if the app has not relaunched. ⌘W on a
  window whose app keeps running still closes the tile at once.
- **D-13:** A placeholder is drawn as a dim tile in the app's colour, with the app icon and "Waiting for <App>…". Clicks
  pass through it. It reuses the Phase 4 app-colour / icon tile (AppColor, CollapsedBlockView).

#### Storage and edge cases for saved views
- **D-14:** Views are stored in layout.json under a new `views` key, with a schema version bump and an automatic
  migration, through the Persistence.swift migration steps (the same way `groups` was added in Phase 7).
- **D-15:** Saving into a used slot replaces it, with the "Replaced view N" toast. There is no confirmation.
- **D-16:** There is no clear-slot command. Saving over a slot is the only way to change it.
- **D-17:** When zoom is turned off, the view chords are unregistered and reach apps, like the other zoom chords
  (Phase 4 D-D). Saved views are kept.

### Claude's Discretion
- The scoring weights and threshold for D-10, which must be tested against cases in a table.
- Which IPC mechanism D-07 uses, as long as it is local-only and gives a reply.
- How the toast is built: reuse an existing overlay or notice surface if one fits.
- CLI argument shape beyond `transom <command>` and `transom view 3` / `transom view/3`.

### Deferred Ideas (OUT OF SCOPE)
- An "Install Command-Line Tool…" button: Phase 9 Settings.
- A keyboard, URL or CLI command to form a tab group ("group with"): a gap carried from Phase 7, not in VIEW-01..05.
  This needs a backlog entry.
- A `transom://clear-view/N` command: not needed now (D-16).

**Also binding:** the approved `08-UI-SPEC.md` (surfaces 1–5, exact copy, exit codes 0/1/2/64, `Contents/Helpers/transom`,
brief toast class, placeholder panel properties, OS-version fallback rule, Name raw values `view1…view9` /
`saveView1…saveView9`, log categories `views` / `match` / `cli`). This research does not re-open any of it.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VIEW-01 | User can save the current view to slots 1–9 and return to it with a hotkey | §Pattern 1 (SavedView model + `Navigator.lowestCommonAncestor` resolution), §Pattern 5 (18 KeyboardShortcuts names, OS-version initial), Pitfall 6/7 (KeyboardShortcuts persists `initial`; Space-switch then re-resolve) |
| VIEW-02 | Saved views survive layout changes and app restarts | §Pattern 1 (identities not NodeIDs; remap on every rekey/fill), §Pattern 4 (schema 3 `views`, DeskKey rekeyed with the Space table), Pitfall 3 (identity remap on placeholder fill) |
| VIEW-03 | Transom commands run from `transom://` URLs | §Pattern 2 (extend `TransomURL.parse` path rule for two hosts; `CameraCommand.view/.saveView(ViewSlot)` makes the existing per-`Command` rate limiter per-slot for free) |
| VIEW-04 | Layouts persist across reboots and app relaunches (new window IDs), with windows re-matched to their tiles | §Pattern 3 (HintMatcher, scoring table, tie rule), §Pattern 6 (placeholders = untracked refs kept in the tree with deadlines), Pitfalls 1, 2, 4, 5, 8, 9 |
| VIEW-05 | A bundled `transom` CLI runs the same commands as URLs and reports errors with a non-zero exit code | §Pattern 7 (CFMessagePort request/reply, sync reply from the main queue), §Pattern 8 (XcodeGen `tool` target embedded at `Contents/Helpers`), Pitfalls 10, 11, 12 |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Swift 6 language mode, `swift-tools-version: 6.2`; do not use Swift 6.4-only syntax in shipped code. [CITED: .claude/CLAUDE.md]
- `TransomModel` and `TransomEngine` must not import AppKit (headless tests). New pure logic (HintMatcher, SavedViews, CLI argument parser, CLI help/messages `CLICopy`, IPC wire format) goes in TransomEngine; CFMessagePort, panels and KeyboardShortcuts go in TransomMac / the CLI target. `scripts/check-no-appkit.sh` exists to enforce this. [VERIFIED: ls scripts]
- Private APIs isolated in TransomPrivate with fallbacks; Phase 8 adds **no** private API (Space switching reuses Phase 6's `SpaceSwitcher`, CFMessagePort is public). [VERIFIED: Sources/TransomMac/SpaceSwitcher.swift]
- Clean room: no TrellisWM binary; Loop (GPL-3) read-only reference only.
- KeyboardShortcuts 3.1.0 is the only runtime dependency, pinned `exact: "3.1.0"`; do not add packages. [VERIFIED: Package.swift]
- Logging via `os.Logger`, subsystem `com.eightabyte.transom`; window titles `.private` only (D-10).
- Live/AX tests run only in the Tart VM via `scripts/vm-live-test.sh` (never on the host); a `swift test --filter` gate passes only if at least one test actually ran. [CITED: .planning/phases/03-tiling-mvp/03-CONTEXT.md line 91]
- GSD workflow: changes go through GSD commands; never stage `.planning/config.json`, `.planning/state.json`, `milestone.lock`.
- Global CLAUDE.md: "Silent fallbacks (`or {}`) convert hard failures into silent corruption. Let it crash"; Chesterton's Fence before removing code (relevant to removing `withoutTitleHints` and changing `LayoutRestore.reattach`); evidence standards.
- Ponytail runs at write-time in executors: prefer the smallest change that fully solves each requirement.

## Summary

Phase 8 is mostly integration work on top of machinery that already exists. The `transom://` allow-list (`TransomURL`) and its per-`Command` rate limiter, the camera's `zoomTo(target, displayUUID, focus)` entry point with history, `Navigator.lowestCommonAncestor`, the Phase 6 `SpaceSwitcher`, the layout.json schema-versioned load path (`LayoutStore.decode` with a `LayoutFileV1` migration), the Space-UUID rekey (`SpaceRekey`), and the "dormant window" concept (a saved ref held in the tree with no tracked window, whose tile is reserved but never written) are all in place. The new pieces are: a `SavedView` record and its two engine operations (save, resolve destination); a pure `HintMatcher`; a placeholder lifecycle (deadlines on the Arranger's existing `tick` / `nextWake` clock); a CFMessagePort listener plus a small CLI target; and 18 new KeyboardShortcuts names.

Three findings change how the plan should be written. **First, D-14's mechanism is described incorrectly in CONTEXT:** Phase 7's `groups` was added with `decodeIfPresent` and *no* schema bump, and `Persistence.swift`'s `MigrationChain.standard` has no steps and governs only the nested `World` (schema 1). The real layout.json version is `LayoutFile.schemaVersion = 2`, migrated in `LayoutStore.decode`. The plan should bump `LayoutFile.schemaVersion` to 3, leave `World.currentSchemaVersion` at 1, and add a `case 2` decode path. The bump is what protects the new `views` and titles from being overwritten by an older Transom, because an older build refuses to save a newer file. **Second, a placeholder is almost free in the model:** an untracked ref left in the tree already reserves its tile and gets no frame write (`Arranger.swift:2026-2027`). But three existing paths would delete it at once (`closeDormant` on `.appTerminated`, `closeDormant` on every inventory where the CG list lacks it, and `LayoutRestore.reattach`), and several shell surfaces (stage tiles, overview, collapsed blocks) assume every ref on a *shown* desk is tracked. **Third, titles in the World are stale:** `World` refs keep the title captured when the window entered the World, and `WindowRef` equality is identity-only. So the snapshot must refresh titles from `Arranger.windows` before saving, or the matcher will compare against stale titles.

For the CLI, use CFMessagePort. Its public API resolves "Transom is not running" for free (`CFMessagePortCreateRemote` returns NULL), carries send/receive timeouts, and needs no filesystem state. Its one limitation is that the reply is synchronous, which fits the UI-SPEC's "exit 0 = accepted" contract. Service the port with `CFMessagePortSetDispatchQueue(port, .main)` rather than a run-loop source, so it also works inside `swift test`. Embed the CLI with an XcodeGen `tool` target copied to `wrapper` + `Contents/Helpers`.

**Primary recommendation:** Model saved views as `(slot, DeskKey, home, [WindowIdentity])`. Model placeholders as untracked refs kept in the World plus a session-only `placeholders: [WindowIdentity: Placeholder]` deadline table in the Arranger. Use one integer-weighted `HintMatcher` for both the launch path and the app-relaunch path. Bump `LayoutFile` to schema 3. Ship the CLI as a CFMessagePort client whose argument parsing, help text and wire format live in TransomEngine.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Saved view record, save/resolve logic | TransomEngine (Arranger extension) | TransomModel (`SavedView` Codable if kept beside `LayoutFile`) | Pure decision over `world` + camera state; headless-testable |
| Going to a view across Spaces/displays | TransomMac (`ArrangeController`) | TransomEngine (destination + `zoomTo`) | Space switching posts keys and awaits SkyLight (shell); target choice is pure |
| URL allow-list + slot path rule | TransomEngine (`TransomURL`) | — | Shared verbatim by app and CLI (D-07) |
| Rate limiting (URL + CLI shared) | TransomMac (one gate object owned beside `AppDelegate`) | TransomEngine (`TransomURLRateLimiter`) | One limiter instance must serve both routes |
| Hint matching (scores, threshold, ties) | TransomEngine (`HintMatcher`) | — | Pure table-tested function (D-10 discretion) |
| Placeholder lifecycle (create, fill, expire) | TransomEngine (Arranger state + `tick`/`nextWake`) | TransomModel (`World.adopt` OS-fact op) | Deadlines and fills are layout facts; the Arranger is the only clock owner |
| Placeholder drawing (click-through panel) | TransomMac (`Overlay`/`Zoom`, sibling of `CollapsedPanels`) | — | AppKit `NSPanel` |
| Title/hint persistence | TransomMac (`LayoutStore` stops redacting) | TransomEngine (`Arranger.snapshot` refreshes titles) | File I/O in the shell, data shaping in the engine |
| Schema 3 load/migrate | TransomMac (`LayoutStore.decode`) | TransomEngine (`LayoutFile` fields + validate) | Existing split |
| CLI argument parsing, help, exit-code mapping, wire format | TransomEngine (`CLICommandLine`, `CLICopy`, `CLIProtocol`) | — | Headless tests; the CLI target imports TransomEngine, never AppKit |
| CLI IPC client | `transom-cli` executable (CoreFoundation) | — | Thin main.swift |
| CLI IPC listener | TransomMac (`CLIListener`) | — | Needs the MainActor `ArrangeController` |
| Hotkeys (18 names, OS-version initial) | TransomMac (`Hotkeys.swift`) | TransomEngine (pure version rule, optional) | KeyboardShortcuts is a TransomMac dependency |

## Standard Stack

### Core (all already in the project; no additions)

| Library / API | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| KeyboardShortcuts | 3.1.0 (pinned, revision `772133d9`) | 18 new rebindable names + `Recorder` rows | Already the project's hotkey layer; registers by Carbon virtual key code (`Key.one = Self(kVK_ANSI_1)`), so digits are bound by position (D-01) [VERIFIED: .build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Key.swift:42-51] |
| CoreFoundation `CFMessagePort` | macOS SDK (public, not deprecated) | CLI ↔ app request/reply | Public, local-only Mach IPC with built-in timeouts and a NULL remote when no server exists [VERIFIED: SDK CFMessagePort.h:24-29, 46-47, 57, 63] |
| Foundation `JSONEncoder`/`Codable` | system | `views` in layout.json | Existing persistence pattern |
| Swift Testing | toolchain (Swift 6.4 local) | All new unit tests | Existing suites use `@Suite`/`@Test`/`#expect` [VERIFIED: Tests/TransomEngineTests/TransomURLTests.swift] |
| XcodeGen | 2.46.0 | Adds the `transom` tool target and the copy into `Contents/Helpers` | Existing release-bundle generator [VERIFIED: xcode/project.yml] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CFMessagePort | Unix-domain socket in `~/Library/Application Support/Transom/` (0600) with `getpeereid` | Allows an async reply (could report a failed Space switch) and a same-uid check, and it works from SSH sessions. But it means hand-rolled socket framing, stale-socket cleanup, and a `sun_path` length limit. Use it only if the VM probe (Open Question 2) shows CFMessagePort unusable from the contexts that matter (Raycast, Alfred, Shortcuts, Terminal). |
| CFMessagePort | NSXPCConnection Mach service | Needs launchd registration (LaunchAgent / SMAppService agent): too heavy, and Phase 9 owns login items. |
| CFMessagePort | Apple Events / `NSAppleScript` | Triggers an Automation TCC prompt for every calling terminal app: rejected. |
| CFMessagePort | Distributed notifications | No reply, so the CLI can't report refusals: violates D-07. |
| Greedy max-score assignment with tie detection | Hungarian (optimal) assignment | n per bundle is tiny (usually < 20). Greedy plus an explicit tie rule matches D-10's "on a tie, neither" semantics, which an optimal solver would hide. |

**Installation:** none. No new packages.

**Version verification:** KeyboardShortcuts is resolved at 3.1.0 [VERIFIED: Package.resolved]; `swift build` succeeds on this host today [VERIFIED: `swift build` → "Build complete!"].

## Package Legitimacy Audit

No external packages are installed or added in this phase. KeyboardShortcuts 3.1.0 is already a pinned dependency, carried from Phase 3/4.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none new) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
  ⌥n / ⇧⌥n (Carbon hotkey)     open transom://view/3 (LaunchServices)     transom view 3 (Terminal/Raycast/Shortcuts)
          │                               │                                         │
          │                               ▼                                         ▼
          │                    AppDelegate.application(_:open:)        transom-cli main.swift
          │                               │                              ├─ CLICommandLine.parse(argv) ──► exit 64 + CLICopy msg
          │                               │                              ├─ TransomURL.parse(url) (same allow-list)
          │                               │                              ├─ resolve own bundle → bundle ID → port name
          │                               │                              └─ CFMessagePortCreateRemote ── nil ──► exit 2
          │                               │                                         │ SendRequest(url bytes, 2 s)
          │                               │                                         ▼
          │                               │                         CLIListener (CFMessagePort, main queue)
          │                               ▼                                         │
          │                  ┌──── CommandGate: TransomURL.parse + shared TransomURLRateLimiter ────┐
          │                  │                rejected → log "rejected a URL"/CLI "rejected"        │
          │                  └──────────────────────────────┬────────────────────────────────────────┘
          ▼                                                 ▼
   ArrangeController.dispatch(command, from: .hotkey | .url | .cli)  ──(.cli: sync outcome → reply bytes)
          │
          ├─ .camera(.saveView(n)) ─► Arranger.saveView(n, pointerDisplay) ─► SavedViews[n] = (DeskKey, home|[ids])
          │                                                                    └► toast N13/N14, .save(.debounced)
          │
          └─ .camera(.view(n)) ─► Arranger.viewDestination(n) ──► empty slot / display gone → refusal
                                        │ (desk with most remaining windows; LCA of their leaves; home if all gone)
                                        ▼
                         destination desk's Space shown? ── no ─► SpaceSwitcher.switchTo(space, display) (≤1 s)
                                        │                              │ fail → "Couldn't switch to Desktop n"
                                        │                              ▼ wait until Arranger.displays reflects Space
                                        │                         re-resolve viewDestination(n)
                                        ▼
                         Arranger.zoomTo(target, displayUUID, focus: most-recent window in view) → .cameraMove → stage → settle

  Window lifecycle (AXWindowSystem → WindowEvent stream → Arranger.handle)
     .appTerminated(pid)  ─► mark pid quitting (bundle) ─┐
     .windowDestroyed(w)  ─► w docked && pid quitting? ──┴─ yes ─► keep ref in tree as PLACEHOLDER (deadline now+30 s)
                                                          └ no ──► normal close path (⌘W, D-12a)
     .appLaunched(pid,b)  ─► placeholders of bundle b: deadline = launch + 10 s (sliding per new window, see Pattern 6)
     .windowCreated(info) ─► admit (floats) ─► HintMatcher(placeholders of bundle, fresh candidates) ─► World.adopt → tile
     .tick                ─► expired placeholders ─► LifecycleSync close path (neighbours reflow)

  Launch: LayoutStore.load (schema 1/2/3) ─► SpaceRekey (desks + view desks) ─► .restore(world, …, views)
          ─► first complete inventory ─► LayoutRestore.reattach (identity) ─► HintMatcher (unplaced vs unattached saved)
          ─► unmatched docked → placeholders (deadline restore + 5 min; app running → sliding 10 s)
  Save:   Arranger.snapshot (titles refreshed from `windows`, views) ─► LayoutFile v3 ─► LayoutStore.save (0600, titles kept)
```

### Recommended Project Structure (new files only)

```
Sources/
├── TransomModel/
│   └── World.swift                 # + adopt(_:by:) OS-fact op; + refreshingTitles(_:) (replaces withoutTitleHints use)
├── TransomEngine/
│   ├── TransomURL.swift            # + "view"/"save-view" path rule, help-table source
│   ├── Command.swift               # + ViewSlot, CameraCommand.view(ViewSlot), .saveView(ViewSlot)
│   ├── SavedViews.swift            # SavedView, SavedViews (slots), validation
│   ├── Arranger+Views.swift        # saveView(_:displayUUID:), viewDestination(_:), remap on rekey/fill
│   ├── HintMatcher.swift           # scoring + greedy assignment + tie rule
│   ├── Arranger+Placeholders.swift # placeholder table, deadlines, fill, expiry, `.placeholders` effect
│   ├── LayoutFile.swift            # schema 3: + views; validate()
│   ├── LayoutRestore.swift         # keep unmatched docked saved windows as placeholders; call HintMatcher
│   ├── CLICommandLine.swift        # argv → URL string | help | usage error (pure)
│   ├── CLICopy.swift               # help text, stderr messages, ASCII conversion (UI-SPEC Surface 5)
│   └── CLIProtocol.swift           # msgid, request/reply encoding, port-name derivation, exit-code mapping
├── TransomMac/
│   ├── CLIListener.swift           # CFMessagePortCreateLocal + SetDispatchQueue(.main)
│   ├── Overlay/PlaceholderPanels.swift  # click-through panel pool (CollapsedPanels pattern)
│   ├── Input/Hotkeys.swift         # + 18 names, OS-version initial
│   └── Shell/ViewCopy.swift        # Shortcuts titles/footer, joined announcement, Debug lines
└── transom-cli/
    └── main.swift                  # parse → resolve bundle → CFMessagePort → exit code
xcode/project.yml                   # + `transom` tool target, embedded via copy wrapper/Contents/Helpers
```

### Pattern 1: Saved view = desk + identities, resolved through the lowest common ancestor

**What:** Store `SavedView { slot, desk: DeskKey, home: Bool, windows: [WindowIdentity] }`. To go to a view, take the saved identities that some desk still holds. The target desk is the one holding most of them (ties go to the saved desk, per UI-SPEC). The target is `Navigator.target(lowestCommonAncestor(leaves), in: tree)`, which already maps the root to `.home`. With no surviving windows, or for a home view, the target is the saved desk's home (D-05).

**When:** every go/save, from every route.

**Facts this relies on (read this session):**
- `public static func lowestCommonAncestor(_ ids: [NodeID], in tree: LayoutTree) -> NodeID?` "The deepest node every one of `ids` descends from (or is); nil when `ids` is empty or one is not in `tree`." [VERIFIED: Sources/TransomEngine/Navigator.swift:50-56]
- `public static func target(_ id: NodeID, in tree: LayoutTree) -> ViewTarget { id == tree.root ? .home : .node(id) }` [VERIFIED: Navigator.swift:39-42]
- `public func leafNode(of window: WindowRef) -> NodeID?`: "The docked window's leaf, or the Desktop tile for a present floater on a shown Desktop." [VERIFIED: Sources/TransomEngine/Navigator.swift:215-220]. Floaters therefore resolve to `.desktop`, and the LCA covers the Desktop tile automatically.
- `func currentView(_ uuid: String, _ key: DeskKey) -> ViewTarget`: "the pending target, else the committed view" [VERIFIED: Arranger+Camera.swift:99-103]. Saving reads this, which satisfies the UI-SPEC rule "if a camera move is in progress, the move's target view is saved".
- `mutating func zoomTo(_ target: ViewTarget, displayUUID uuid: String, kind: PendingMove.Kind = .navigate, focus: WindowRef? = nil)` refuses when `target == current` ("already showing"), and `.navigate` pushes Back history at settle [VERIFIED: Arranger+Camera.swift:232-257]. The UI-SPEC's "camera already at the target → nothing moves (not a refusal)" means the shell must treat that `.info("refused zoomTo: already showing")` as success (toast N15, no beep).

**Which windows are "inside the view" when saving:** for `.node(id)`, every window in `desk.tree.subtree(at: id)` (all members of a tab group), plus `desk.desktop.windows` when the subtree contains `.desktop`. This mirrors `ViewPlanner`'s `showsDesktop` rule [VERIFIED: ViewPlanner.swift:56-58]. For `.home`, store `home: true` with `windows: []`. Refuse N19 when a node view holds no windows.

**Identity remapping (critical for VIEW-02):** identities change on `.windowRekeyed` and on every placeholder fill (relaunch/reboot re-match). Route both through one Arranger helper that also rewrites `views`. Prune identities that no desk holds and no placeholder holds at save time; D-05 still works, because a view with no identities goes home on its saved desk.

**Example (engine skeleton, names are recommendations):**
```swift
// Source: pattern composed from Navigator.swift:50-56, Arranger+Camera.swift:103-107 (this repo)
public struct ViewSlot: Hashable, Sendable, Codable, Comparable {
    public let number: Int                      // 1...9, validated
    public init?(_ number: Int) { guard (1...9).contains(number) else { return nil }; self.number = number }
    public static func < (a: Self, b: Self) -> Bool { a.number < b.number }
}

public struct SavedView: Codable, Equatable, Sendable {
    public var slot: ViewSlot
    public var desk: DeskKey                    // rekeyed with the Space table like desks (Pattern 4)
    public var home: Bool
    public var windows: [WindowIdentity]        // sorted
}

extension Arranger {
    func viewDestination(_ view: SavedView) -> (key: DeskKey, target: ViewTarget, allGone: Bool) {
        let alive = view.windows.compactMap { id in world.desks.first { $0.value.contains(WindowRef(identity: id)) }.map { (id, $0.key) } }
        guard !view.home, !alive.isEmpty else { return (view.desk, .home, !view.home) }
        let counts = Dictionary(grouping: alive, by: \.1).mapValues(\.count)
        let best = counts.max { a, b in a.value != b.value ? a.value < b.value : (b.key == view.desk) }!.key
        let tree = world[best]!.tree
        let leaves = alive.filter { $0.1 == best }.compactMap { leafNode(of: WindowRef(identity: $0.0)) }
        let lca = Navigator.lowestCommonAncestor(leaves, in: tree) ?? tree.root
        return (best, Navigator.target(lca, in: tree), false)
    }
}
```

### Pattern 2: URL allow-list extension (two hosts, one digit) and per-slot rate limit for free

**Current parser (verbatim):**
```swift
// Source: Sources/TransomEngine/TransomURL.swift:23-30
public static func parse(_ url: URL, scheme: String) -> Command? {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
        parts.percentEncodedUser == nil, parts.percentEncodedPassword == nil, parts.port == nil,
        parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil,
        parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/", let host = parts.percentEncodedHost
    else { return nil }
    return commands[host]
}
```
The rate limiter is keyed by `Command`: `private var lastAdmitted: [Command: ContinuousClock.Instant] = [:]` [VERIFIED: TransomURL.swift:36]. Making the slot part of the command (`.camera(.view(ViewSlot))`) therefore gives D-06's "each slot counts as its own command" with no limiter change.

**Change:** keep the existing branch for an empty path or `/`. Add one branch: when `host` is `"view"` or `"save-view"` and `percentEncodedPath` is exactly two bytes, `/` followed by one byte in `"1"..."9"`, return the slot command. Compare `percentEncodedPath` (not `path`), so `/%33` is rejected as the UI-SPEC requires. Note that `transom://view` and `transom://view/` must be rejected, which means the generic empty-path rule must **not** map `view` / `save-view` (keep them out of `commands`).

**Help table:** the UI-SPEC wants a unit test that every allow-listed command has exactly one help line. `commands` is `static let` (internal), so put the help table in TransomEngine beside it and test `Set(commands.keys) ∪ {"view","save-view"} == Set(helpLines.keys)`.

### Pattern 3: HintMatcher — integer scores, threshold, explicit tie rule (D-10 discretion)

**Inputs (all already persisted or tracked):**
- `WindowRef` fields: `identity` (bundleID, pid, windowID), `titleHint: String`, `axIdentifier: String?`, `creationOrder: UInt64` [VERIFIED: Sources/TransomModel/IDs.swift:84-95]
- `creationOrder` is **session-global, not per app**: `private var nextCreationOrder: UInt64 = 1` in `WindowTracker`, assigned `old?.window.creationOrder ?? nextCreationOrder` [VERIFIED: WindowTracker.swift:14, 144-147]. "Order within the app" (D-10) is therefore the rank of `creationOrder` among one bundle's refs, computed separately for saved refs and for candidates.
- Saved frame: for a docked ref, its **home-view tile rect** from `Planner`/`ViewPlanner` on the current display. That is where a clean quit's D-D restore put it, and so where the app reopens it. For a floater, `desk.desktop.frame(of:)`, which is persisted. Recommendation: compute rather than add a field. It meets D-10's intent ("frame" is derivable from the persisted tree and floating frames), and a parked window's last real frame is meaningless anyway (Pitfall 9).

**Recommended scoring (integers so ties are exact; the planner must lock these in a test table):**

| Signal | Condition | Points |
|---|---|---|
| Bundle | different bundle | not a candidate (hard filter) |
| Title | both non-empty, exactly equal | +50 |
| Title | both non-empty, equal after normalisation (trim, case-fold, drop a trailing " — Edited" / " - Edited") | +30 (instead of +50) |
| AX identifier | both non-nil and equal | +15 |
| AX identifier | both non-nil and different | −30 |
| Frame | IoU ≥ 0.9 | +25 |
| Frame | 0.5 ≤ IoU < 0.9 | +10 |
| Order within app | same rank | +10 |
| Sole pair | exactly one unmatched saved ref and exactly one unclaimed candidate for this bundle | +40 |
| **Threshold** | match only if score ≥ 40 | — |

**Assignment:** list all pairs at or above the threshold. Repeatedly take the highest-scoring pair. If another remaining pair with the **same score** shares its saved ref or its candidate, that is a tie: remove every pair involved, so those saved refs stay placeholders and those candidates float (log `match … tie at {s}`). Otherwise commit the pair and remove its row and column. Break iteration order deterministically by identity.

**Required table cases (minimum):** two windows with distinct titles; two with identical titles separated by frame; two identical in every signal (tie → both placeholders, both float); a single-window app whose title changed (sole pair matches); a single window with an empty title and a parked frame (sole pair, 40, matches); two windows with empty titles and parked frames (no match); conflicting AX identifiers (no match); a candidate from a different bundle (never); three saved and two candidates (one placeholder left); title normalisation ("Doc.txt — Edited" vs "Doc.txt").

### Pattern 4: layout.json schema 3 — bump `LayoutFile`, not `World`

**What exists (verbatim):**
- `public static let schemaVersion = 2` (LayoutFile) [VERIFIED: Sources/TransomEngine/LayoutFile.swift:42]
- `public static let currentSchemaVersion = 1` (World; its `init(from:)` rejects any other value) [VERIFIED: Sources/TransomModel/World.swift:87, 279-283]
- `public static let standard = MigrationChain(steps: [:])` [VERIFIED: Sources/TransomModel/Persistence.swift:87]. It applies only to standalone `World.decode`, not to layout.json.
- The load switch: `case 1: contents = try decoder.decode(LayoutFileV1.self, from: data).migrated()` / `case LayoutFile.schemaVersion: contents = try decoder.decode(LayoutFile.self, from: data)` [VERIFIED: Sources/TransomMac/LayoutStore.swift:116-122]
- Phase 7 `groups`: `groups = try container.decodeIfPresent([FloatingTabGroup].self, forKey: .groups) ?? []` with the comment "that absence is the one sanctioned default". It was not a schema bump. [VERIFIED: Sources/TransomModel/DesktopLayer.swift:220-229]
- Save redaction: `redacted.world = contents.world.withoutTitleHints()` and the same for every layout set; then `.posixPermissions: 0o600` [VERIFIED: LayoutStore.swift:59-61, 67]

**Recommendation:**
1. `LayoutFile.schemaVersion = 3`; add `views: [SavedView]` (sorted by slot) and decode it with `decodeIfPresent … ?? []`, so schema-2 bytes decode into the same struct. In `LayoutStore.decode`, accept `case 2, 3`. Keep `case 1` (V1 → migrated). `World` stays at schema 1.
2. Why bump at all, when `decodeIfPresent` alone would read old files: an older Transom (schema-2 build) reading a schema-3 file hits `.newerVersion`, sets `savingDisabled`, and never overwrites the file [VERIFIED: LayoutStore.swift:44-48]. Without the bump, a downgrade would silently drop `views` and re-strip titles on its next save. This is the T-03-18 protection.
3. `LayoutFile.validate()`: slots unique and sorted, at most 9 views, each view's window list at most `LayoutTree.maxNodes`, valid DeskKey.
4. Stop calling `withoutTitleHints()` in `LayoutStore.save`. Apply Chesterton's Fence: it exists for T-03-17, which D-10 supersedes, so delete the call and either repurpose or delete the function. Invert `LayoutStoreTests.titlesAreNeverWritten` into a "titles are written, file is 0600" test.
5. `SpaceRekey`: view desks must follow their Space across reboots. Either include the views' Space IDs in `SpaceRekey.table(for:)` and rekey views with the same computed targets, or store the Space UUID in the view. Recommend the former, so there is one mechanism. A view whose Space is unmatched keeps its key (D-05 / N17 path: "saved Space no longer exists → that display's current Space, home").
6. `Arranger.snapshot` and `ArrangerInput.restore` both gain `views` [VERIFIED: Arranger.swift:378-382 `.restore(world, homeFrames, wantedFrames, arrangement, sets)`].
7. Fix the stale comment `/// All camera state, session-only (never saved, so layout.json stays schema 1)` [VERIFIED: Arranger+Camera.swift:3]. Saved views are persisted; the camera state is still session-only.

**Correction to CONTEXT D-14 (flag to the user, low risk):** "through the Persistence.swift migration steps (the same way `groups` was added in Phase 7)" doesn't match the code. `groups` used no bump, and Persistence.swift's chain doesn't touch layout.json. The recommendation above delivers what D-14 asks for (bump plus automatic migration) through the mechanism the code actually uses.

### Pattern 5: Hotkeys — 18 names, OS-version `initial`, zoom-name gating for free

- `zoomNames` is derived: `entries.compactMap { if case .camera = $0.command { $0.name } else { nil } }` [VERIFIED: Sources/TransomMac/Input/Hotkeys.swift:115]. Making the commands `.camera(.view(n))` and `.camera(.saveView(n))` automatically puts the 18 names under `setZoomHotkeys(enabled:)` (D-17) and under `logSystemConflicts()`.
- `Name.init(_:initial:)` immediately calls `KeyboardShortcuts.setInitialShortcutIfNeeded(initialShortcut, forRawValue: name)` [VERIFIED: .build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Name.swift:33-47], which writes to UserDefaults only when the key is absent [VERIFIED: KeyboardShortcuts.swift:599-613]. **The initial is therefore frozen into UserDefaults the first time the name is constructed** (Pitfall 6).
- Registration failure is not public: `var onRegistrationFailed: (() -> Void)?` is internal on `HotKey` [VERIFIED: HotKey.swift:17], and the library's own handler just drops the hotkey [VERIFIED: KeyboardShortcuts.swift:207-215]. `Shortcut.isDisallowed` returns true only for 15.0/15.1 **and** `Constants.isSandboxed` [VERIFIED: Shortcut.swift:125-140]. The UI-SPEC's version rule is the only deterministic option, and it is what the plan should use.
- Version rule: on macOS 15.0 or 15.1, `initial` uses `[.control, .option]` / `[.shift, .control, .option]`; otherwise `[.option]` / `[.shift, .option]`. Keep it a pure function of `OperatingSystemVersion` so it can be unit-tested with a faked version.

```swift
// Source: pattern on Hotkeys.swift:7-59 + KeyboardShortcuts Key.swift:43-51 (this repo / pinned checkout)
enum ViewChords {
    static func modifiers(save: Bool, os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> NSEvent.ModifierFlags {
        let restricted = os.majorVersion == 15 && os.minorVersion <= 1
        var flags: NSEvent.ModifierFlags = restricted ? [.control, .option] : [.option]
        if save { flags.insert(.shift) }
        return flags
    }
    static let digits: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
}
extension KeyboardShortcuts.Name {
    static let view3 = Self("view3", initial: .init(ViewChords.digits[2], modifiers: ViewChords.modifiers(save: false)))
    static let saveView3 = Self("saveView3", initial: .init(ViewChords.digits[2], modifiers: ViewChords.modifiers(save: true)))
}
```
(The raw values `view1…view9` / `saveView1…saveView9` are fixed by the UI-SPEC and must never be renamed.)

### Pattern 6: Placeholders — untracked refs kept in the World, plus a deadline table

**What already gives this almost for free:**
- Dormant refs reserve their tile and get no write: "An untracked (dormant, G-03-8) window gets nothing either: the window system would drop the command, and its windowCreated replans it." [VERIFIED: Arranger.swift:2026-2027]
- `private var dormantWindows: [WindowRef] { world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }.filter { windows[$0.identity] == nil }… }` [VERIFIED: Arranger.swift:957-960]
- The engine has a single wake clock: `var nextWake: ContinuousClock.Instant?` is the min of all deadlines, and `.tick` processes them [VERIFIED: Arranger.swift:1099-1105, 1073-1087]. Placeholder deadlines join this list.

**What would delete a placeholder today (each must exclude placeholders):**
1. `case .appTerminated(let pid): … faults += closeDormant { $0.pid == pid }` [VERIFIED: Arranger.swift:890-892]. Under D-12a this becomes "turn into placeholders".
2. Every non-restore inventory: `closeDormant { !LayoutRestore.isAlive($0.identity, in: live) }` [VERIFIED: Arranger.swift:285-286]. A placeholder is by definition not alive, so it would close on the next inventory. Exclude placeholders from `dormantWindows`, or skip them in the predicate.
3. `LayoutRestore.reattach` removes every saved window not tracked and not alive: "A window whose app relaunched has a new pid and is removed: re-matching it is VIEW-04's." [VERIFIED: Sources/TransomEngine/LayoutRestore.swift:9-10, 20-26]. It must become: identity re-attach, then HintMatcher over `unplaced` vs the unattached saved refs; matched pairs → `World.rekey(from: saved, to: candidate)` (the candidate is held by no desk yet at restore, so plain rekey works [VERIFIED: World.swift:216-229]); unmatched docked refs → kept as placeholders; unmatched floaters → kept until expiry, then dropped (UI-SPEC).
4. `ArrangeController` feeds every inventory on `.liveWindowsChanged` while `hasDormantWindows` [VERIFIED: ArrangeController.swift:267-268]. Harmless once (2) is fixed, but placeholders shouldn't keep that feed alive needlessly.

**App-quit ordering (D-12a):** the shell yields `.appTerminated(pid:)` before it emits the tracker's terminated decisions (`continuation.yield(.appTerminated(pid: pid))` then `emit(tracker.appTerminated(pid:…))`) [VERIFIED: AXWindowSystem.swift:640-645]. The tracker then closes each window once it leaves the CG list, rechecking every 250 ms for up to 5 s (`for _ in 0..<20` … `Task.sleep(for: .milliseconds(250))`) [VERIFIED: AXWindowSystem.swift:565-578], per CloseRule `case (.terminated, _, false): return .closed` [VERIFIED: CloseRule.swift:54]. So the Arranger can record `quitting[pid] = (bundleID, now)` on `.appTerminated` and, on each `.windowDestroyed(w)` whose pid is quitting and which is **docked**, keep the ref as a placeholder (`forget` the tracking state, don't call `LifecycleSync.handle`) with deadline `quitTime + 30 s`. `.appTerminated` carries no bundle ID (`case appTerminated(pid: Int32)` [VERIFIED: WindowSystem.swift:145]), so look the bundle up from `windows` before they're forgotten. See Pitfall 1 for apps that close their windows before NSWorkspace reports termination.

**Fill (relaunch path):** the relaunched app's window arrives as `.windowCreated`, is admitted as a floater (`admit`), then matched. `World.rekey` can't be used here: when a desk already holds `to`, it closes `from` instead [VERIFIED: World.swift:216-221]. Add a model op `World.adopt(_ placeholder: WindowRef, by window: WindowRef)`: one `reflow`-style OS fact that removes `window` from its Desktop layer (any desk), rekeys the placeholder ref to `window` in its tree leaf, and keeps the undo snapshots valid (forget `window`'s floating entries, rekey `placeholder` → `window`). Then remap `views`, clear `lastRequested[window]` so `planShown` writes the tile, and keep `wantedFrames[window]` (its open frame becomes its pre-dock frame).

**Candidates for relaunch matching:** windows of the bundle created after the placeholder existed and not yet touched by the user (not dragged, docked or grouped). Re-run the matcher on `.windowCreated` **and** on `.windowChanged` for those candidates, because titles arrive late (Pitfall 4).

**Deadlines (D-12/D-12a, recommended reading):**

| Placeholder origin | Deadline |
|---|---|
| Launch, app not running | restore time + 5 min |
| Launch, app running at restore | restore time + 10 s, extended to `lastWindowCreated(bundle) + 10 s` while new windows of that bundle keep arriving |
| App quit while Transom runs | quit time + 30 s; on `.appLaunched` for that bundle, switch to launch time + 10 s (sliding as above) |
| Tie | the deadline of whichever path created it |
| Paused | expiry still runs (UI-SPEC) |

**Effect for the shell:** follow the `collapsedBlocks` / `tabStrips` pattern. `planShown` emits `.placeholders([PlaceholderTile], displayUUID:)` with the plan rect of each untracked placeholder ref on shown desks; that rect is already in `plan.frames`, but `desired` filters it out [VERIFIED: Arranger.swift:2028 `var desired = plan.frames.filter { windows[$0.key.identity]?.isExcluded == false }`]. The stage needs placeholders too: `planTiles` drops untracked refs (`for window in all where windows[window.identity]?.isExcluded == false`) [VERIFIED: Arranger+Camera.swift:315], so add placeholder rects to `CameraMove` separately.

### Pattern 7: CLI IPC over CFMessagePort (sync reply, main dispatch queue)

**API facts (SDK header, read this session):**
- `CFMessagePortCreateLocal(CFAllocatorRef, CFStringRef name, CFMessagePortCallBack, CFMessagePortContext *, Boolean *shouldFreeInfo)` / `CFMessagePortCreateRemote(CFAllocatorRef, CFStringRef name)` [VERIFIED: CFMessagePort.h:46-47]
- `typedef CFDataRef (*CFMessagePortCallBack)(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info);` "If callout wants to keep a hold of the data past the return of the callout, it must COPY the data" [VERIFIED: CFMessagePort.h:40-41]
- `CFMessagePortSendRequest(remote, msgid, data, sendTimeout, rcvTimeout, replyMode, &returnData)`; "NULL replyMode argument means no return value expected" [VERIFIED: CFMessagePort.h:56-57]
- Error codes: `kCFMessagePortSuccess = 0, kCFMessagePortSendTimeout = -1, kCFMessagePortReceiveTimeout = -2, kCFMessagePortIsInvalid = -3, kCFMessagePortTransportError = -4, kCFMessagePortBecameInvalidError = -5` [VERIFIED: CFMessagePort.h:24-29]
- `CFMessagePortSetDispatchQueue(CFMessagePortRef, dispatch_queue_t) API_AVAILABLE(macos(10.6)…)` [VERIFIED: CFMessagePort.h:63]
- Apple doc: "If a local port is already named `name`, the function returns that port instead of creating a new object" (same process); replyMode "the function runs the run loop waiting for a reply, in that mode … use the kCFRunLoopDefaultMode constant" [CITED: developer.apple.com CFMessagePortCreateLocal / CFMessagePortSendRequest doc JSON]

**Design:**
- **Port name** derives from the bundle the CLI ships in: `"\(bundleID).cli"`, so `com.eightabyte.transom.cli` for Release and `com.eightabyte.transom.debug.cli` for Debug. The bundle IDs come from `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom` / `com.eightabyte.transom.debug` [VERIFIED: xcode/project.yml configs], which satisfies the UI-SPEC rule "a Debug build's CLI talks to the Debug app". The app computes the name from `Bundle.main.bundleIdentifier`; the CLI computes it from its resolved bundle (Pitfall 11).
- **Wire format (pure, in `CLIProtocol`):** `msgid = 1` (protocol v1); request = UTF-8 bytes of the full URL built with the scheme from the bundle's `CFBundleURLTypes` (the app's `AppDelegate.registeredScheme()` reads the same key [VERIFIED: AppDelegate.swift:67-71]); reject requests over 256 bytes. Reply = UTF-8 `ok` | `refused\t<reason>` | `rate` | `rejected`. The CLI maps these to exit 0 / 1 / 1 / 64 and returns 2 when `CreateRemote` gives NULL. A `SendRequest` result of `-1`/`-2` maps to "Transom didn't answer" (exit 1); `-3`/`-5` happen when the app quit mid-call, and also map to exit 1.
- **Listener:** `CFMessagePortCreateLocal` with `info = Unmanaged.passUnretained(self).toOpaque()`, a non-capturing `@convention(c)` callback, `CFMessagePortSetDispatchQueue(port, .main)`, and inside the callback `MainActor.assumeIsolated { … }`. Use the dispatch queue rather than a run-loop source: it services the port both in the app and inside `swift test`, whose main thread may not run a CFRunLoop (Pitfall 12). A NULL return from `CreateLocal` (name taken by another running instance) sets Debug "Command-line tool: off (couldn't listen)" and logs `cli listener failed`.
- **Synchronous outcome:** `Arranger.handle` is synchronous; only `run(effects)` is async. Split `ArrangeController.dispatch` [VERIFIED: ArrangeController.swift:560-590] into a sync `decide(command, from:) -> (outcome, effects)` followed by `Task { await run(effects) }`. For `.cli`, the outcome is `refused(reason)` when the hotkey-flavoured decision would beep or announce, with the reason taken from the `.announce(text)` / tab refusal text (UI-SPEC: "the exact text VoiceOver would hear"). Effects are then filtered like `.url`'s (no beep, no announcement). A view go that needs a Space switch replies `ok` when the switch starts; a later switch failure only shows on screen. This is consistent with "0 = accepted (a camera move may still be animating)".
- **Shared gate:** move `TransomURLRateLimiter` out of `AppDelegate` (`private var limiter = TransomURLRateLimiter()` [VERIFIED: AppDelegate.swift:14]) into one object used by both `AppDelegate.application(_:open:)` and `CLIListener`, so a URL `view/3` and a CLI `view/3` share a bucket (UI-SPEC Surface 4). Add `CommandSource.cli` (today `public enum CommandSource { case hotkey, menu, url }` [VERIFIED: ArrangeController.swift:1162]).

```swift
// Source: composed from CFMessagePort.h (SDK) — listener skeleton
@MainActor final class CLIListener {
    private var port: CFMessagePort?
    let handle: (String) -> String          // URL text in, reply text out (CommandGate + ArrangeController.decide)

    init?(name: String, handle: @escaping (String) -> String) {
        self.handle = handle
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()   // listener lives as long as the app
        let callback: CFMessagePortCallBack = { _, msgid, data, info in
            guard msgid == CLIProtocol.version, let info, let data, CFDataGetLength(data) <= CLIProtocol.maxRequestBytes,
                  let text = String(data: data as Data, encoding: .utf8)
            else { return Unmanaged.passRetained(Data(CLIProtocol.rejected.utf8) as CFData) }
            let reply = MainActor.assumeIsolated { Unmanaged<CLIListener>.fromOpaque(info).takeUnretainedValue().handle(text) }
            return Unmanaged.passRetained(Data(reply.utf8) as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, nil) else { return nil }
        CFMessagePortSetDispatchQueue(port, .main)
        self.port = port
    }
}
```
(The reply's ownership follows CF's rule for this callback, "System will release returned CFData" [VERIFIED: CFMessagePort.h:41], hence `passRetained`. The executor must confirm the Swift import's return type of `CFMessagePortCallBack`, `Unmanaged<CFData>?`, against the toolchain.)

### Pattern 8: Embedding the CLI at `Contents/Helpers` with XcodeGen

- XcodeGen dependency properties: `embed` ("Whether to embed the dependency. Defaults to true for application target"), `codeSign` ("Whether the codeSignOnCopy setting is applied when embedding … Defaults to true"), `copy` ("Copy Files Phase for this dependency. This only applies when embed is true") with `destination` one of `absolutePath, productsDirectory, wrapper, executables, resources, javaResources, frameworks, sharedFrameworks, sharedSupport, plugins` and `subpath` ("The path inside of the destination to copy the files"); product type `tool` exists [CITED: github.com/yonaskolb/XcodeGen Docs/ProjectSpec.md].
- Recommended spec addition:

```yaml
# Source: XcodeGen ProjectSpec (dependency copy) + existing xcode/project.yml
targets:
  transom:                       # product "transom" (lowercase), never inside Contents/MacOS (UI-SPEC note 1)
    type: tool
    platform: macOS
    deploymentTarget: "14.0"
    sources: [../Sources/transom-cli]
    dependencies:
      - package: Transom
        product: TransomEngine
    settings:
      base:
        PRODUCT_NAME: transom
        OTHER_CODE_SIGN_FLAGS: "--timestamp"   # notarisation: every executable needs a secure timestamp + hardened runtime
  Transom:
    dependencies:
      - package: Transom
        product: TransomMac
      - target: transom
        embed: true
        codeSign: true
        copy: { destination: wrapper, subpath: Contents/Helpers }
```
- SwiftPM: add `.executableTarget(name: "transom-cli", dependencies: ["TransomEngine"])` so `swift build` compiles and tests can spawn it. The binary would be `transom-cli` under SwiftPM; Xcode's `PRODUCT_NAME: transom` names the shipped one. The repo already uses hyphenated executable targets (`transom-dump`) [VERIFIED: Package.swift].
- `scripts/release.sh` already runs `codesign --verify --strict --deep` on the app [VERIFIED: scripts/release.sh:42], which covers the helper. Add an explicit check that `Contents/Helpers/transom` exists and carries the team's signature with the hardened runtime flag.

### Anti-Patterns to Avoid

- **Storing a NodeID or a rect in a saved view:** D-02 forbids it; NodeIDs change on split.
- **Bumping `World.currentSchemaVersion`:** the nested World decode rejects any value but the current one (World.swift:279-283), and `MigrationChain.standard` has no steps. Bump `LayoutFile` only.
- **Using `World.rekey` to fill a placeholder with an already-admitted floater:** it closes the placeholder instead (World.swift:218-221).
- **Treating placeholders as "dormant":** dormant means "alive on a hidden Space"; placeholders are not alive and would be closed by `closeDormant`.
- **Persisting titles from `World` refs as they stand:** they are stale (Pitfall 2).
- **Doing the CLI's command work off the main thread:** the Arranger and ArrangeController are MainActor; use `assumeIsolated` on the main queue.
- **Adding `view`/`save-view` to the parameterless `commands` table:** that would accept `transom://view` and `transom://view/`, which the UI-SPEC rejects.
- **Calling `KeyboardShortcuts.setShortcut` at launch to "apply" the fallback:** that overwrites user rebinds. Only `initial` may encode the version rule.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Smallest node holding a set of windows | custom tree walk | `Navigator.lowestCommonAncestor` + `Navigator.target` | Exists, tested, maps root → `.home` |
| Space switch for a view | new key posting | `SpaceSwitcher.switchTo(space:on:)` (1 s timeout, waits for modifiers up) | Phase 6 path with known VM behaviour [VERIFIED: SpaceSwitcher.swift:11, 19-46, 69-75] |
| Camera move + history + focus after settle | new animation path | `ArrangerInput.zoomTo(target, displayUUID:, focus:)` | Single camera protocol, history at settle |
| Space ID drift across reboots for view desks | new UUID mapping | `SpaceRekey.table` / `rekey` | Same table desks use |
| Hotkey registration / recorder / conflict detection | Carbon wrapper | KeyboardShortcuts 3.1.0 | Already wired, persistent names |
| IPC framing / timeouts / "not running" detection | Unix socket protocol | CFMessagePort | Built-in timeouts; NULL remote = not running |
| Close of an expired placeholder | bespoke tree removal | `LifecycleSync.handle(.windowDestroyed(ref))` → `World.apply(.closed)` | Same OS-fact path as a real close (D-12): purges undo, reflows neighbours |
| App icon/colour for placeholders | new colour extraction | `AppColor` + Phase 4 fallback-tile layout constants | D-13 / UI-SPEC |
| Toasts | new panel | `ToastPresenter` / `NoticeQueue` with a per-item duration | UI-SPEC note 5; `NoticeQueue.duration` is a static 6 s today [VERIFIED: Sources/TransomMac/Overlay/NoticeQueue.swift:20] |

**Key insight:** in this phase every "new" behaviour has an existing engine primitive to compose. Most of the risk is in the interactions: dormant vs placeholder, stale titles, identity remaps, and synchronous replies. New algorithms carry little of it.

## Runtime State Inventory

(This phase migrates a persisted schema and changes what is written. The inventory answers "after the code changes, what stored state still reflects the old behaviour?")

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `~/Library/Application Support/Transom/layout.json` at schema 2, with titles stripped, on every existing install; also `layout.json.pre-rekey-*` backups and `layout.json.corrupt` | Code: decode `case 2` → schema 3 in memory, write schema 3 at the next save (no data migration step; titles fill in as windows are seen). Existing files have empty titles, so the **first** relaunch after upgrading matches on frame, order and the sole-pair rule only: expected, and worth a README/release note |
| Live service config | None. Transom has no external service config | None, verified by reading project.yml and ArrangeController's store wiring |
| OS-registered state | KeyboardShortcuts writes each name's `initial` into UserDefaults (`KeyboardShortcuts_<name>`) on first construction (Name.swift:42-47); LaunchServices URL scheme registration (`transom`, `transom-debug`) unchanged; new Mach bootstrap name `com.eightabyte.transom[.debug].cli` registered at runtime only (vanishes when the app quits) | None for existing names. New names freeze their initial on first run (Pitfall 6) |
| Secrets/env vars | None. No secret or env var keyed to anything renamed. A test-only env override for the CLI port name, if added, must be documented | None |
| Build artifacts | Stale `xcode/.xcode-build` after the project.yml change (adds a target); the user-installed symlink `/usr/local/bin/transom` (new, README) | Regenerate via `scripts/generate.sh`; a clean build is advisable. The symlink is user-created; nothing to migrate |

## Common Pitfalls

### Pitfall 1: Apps that close their windows before NSWorkspace reports termination
**What goes wrong:** for D-12a to apply, the Arranger must see `.appTerminated(pid)` before the windows' `.windowDestroyed`. If an app tears its windows down during ⌘Q while the process is still alive, CloseRule's `case (.alive, .invalidElement, false): return .closed` [VERIFIED: CloseRule.swift:56] closes the tiles as ⌘W closes, and no placeholder appears.
**Why:** NSWorkspace's terminate notification comes after process exit. AX hints for destroyed windows may arrive earlier.
**How to avoid:** measure first, with a VM probe that logs event order for ⌘Q of TextEdit, Safari, Terminal and the fixture app. If the race is real, add a small "late terminate" rollback: keep the pre-close desk for docked closes of an app's **last** windows for ≈1.5 s, and if `.appTerminated` for that pid arrives in that window and the desk hasn't changed since, restore those refs as placeholders. ⌘W of one window while others stay open is unaffected (D-12a).
**Warning signs:** after ⌘Q the tiles collapse instead of showing "Waiting for…".

### Pitfall 2: Stale titles in the World
**What goes wrong:** `World` refs keep the title from when the window entered the World. `WindowRef` equality is identity-only ("a title change never makes the same window look like a different one" [VERIFIED: IDs.swift:82-83]), and LifecycleSync never rewrites refs on `.windowChanged` [VERIFIED: LifecycleSync.swift:40-42]. Titles also arrive late ("Titles and buttons arrive late, so a new window waits out the settle delay first" [VERIFIED: WindowTracker.swift:122]).
**How to avoid:** add a pure `World.refreshingTitles(_ titles: [WindowIdentity: String]) -> World` (applied to the world and every layout set) and call it in `Arranger.snapshot` with titles from `windows`. Untracked placeholder refs keep their loaded title.
**Warning signs:** the matcher works in unit tests but ties in the VM for documents renamed after docking.

### Pitfall 3: Saved views lose their windows after a relaunch
**What goes wrong:** a view stores identities, but the filled placeholder's identity is new (new pid and window ID), so ⌥3 lands at home.
**How to avoid:** use one remap helper, called from `.windowRekeyed` handling, from restore-time matches and from `adopt`, and rewrite `views` there. Test: save view → simulate relaunch match → go view resolves to the same LCA.

### Pitfall 4: Matching before titles exist
**What goes wrong:** the relaunched window is created with an empty or default title ("Untitled", "Electron") and matched wrongly, or not at all.
**How to avoid:** re-run the matcher on `.windowChanged` for fresh candidates until the placeholder fills or expires; never undo a committed match. Keep the threshold high enough that empty-title windows match only through the sole-pair rule.

### Pitfall 5: Identity collision after a reboot
**What goes wrong:** after a reboot, pids and window IDs restart from low numbers. A new window can carry the same `(windowID, pid, bundleID)` as a saved one, and `LayoutRestore.reattach` keeps it by identity [VERIFIED: LayoutRestore.swift:16-22], attaching the wrong window to a tile.
**How to avoid:** persist the boot session in `SessionRecord` (`sysctl kern.bootsessionuuid` exists on this host [VERIFIED: local `sysctl -n kern.bootsessionuuid` → a UUID]). When it differs from the saved one, skip identity re-attach and go straight to hint matching. Older files lack the field, so treat it as unknown and keep identity re-attach: the same-login assumption.
**Warning signs:** after a VM cold boot, two windows of one app have swapped tiles.

### Pitfall 6: KeyboardShortcuts freezes `initial` into UserDefaults
**What goes wrong:** on first construction the version-rule default is stored as if the user had set it. A user who first runs on 15.1 keeps ⌃⌥ after upgrading to 15.2. Restore Defaults re-evaluates (`reset` → `setShortcut(name.initialShortcut, …)` [VERIFIED: KeyboardShortcuts.swift:399-403]).
**How to avoid:** accept this (it is harmless, because the chord works) and document it. Never call `setShortcut` automatically.

### Pitfall 7: Zooming before the Arranger knows the new Space
**What goes wrong:** `SpaceSwitcher.switchTo` returns when SkyLight reports the Space, but `Arranger.displays[i].currentSpaceID` updates only on the later `.spaceChanged` event [VERIFIED: Arranger.swift:876-878]. `zoomTo` then plans the old desk's tree (`world[Self.key(display)]` [VERIFIED: Arranger+Camera.swift:238]) and refuses "node not found", or zooms the wrong desk.
**How to avoid:** after a successful switch, wait (bounded, about 500 ms) until `arranger.displays` shows the target Space, then **re-resolve** `viewDestination(n)`, since nodes may have changed, and call `zoomTo`.

### Pitfall 8: Placeholders on a shown desk reach code that assumes "tracked"
**What goes wrong:** until now, untracked refs existed only on hidden Spaces. Stage tiles, the overview, collapsed blocks, tab strips, focus and Navigator step-in may skip, crash on, or mis-draw untracked refs.
**How to avoid:** add a public `Arranger.isPlaceholder(_:)`, add explicit placeholder rects to `CameraMove` and to the effect stream, keep placeholders out of overview selection and counts (UI-SPEC), and audit every `windows[$0.identity]` force or optional path that runs on shown desks. A tab group whose members are all waiting shows one placeholder (UI-SPEC).

### Pitfall 9: Frame hints for parked windows are meaningless
**What goes wrong:** a window parked by the camera is off-screen; if the app relaunches it there, its frame matches nothing.
**How to avoid:** use the home-view tile rect as the saved frame, and give frame a modest weight (Pattern 3).

### Pitfall 10: The CLI from an SSH session may not see the GUI session's port
**What goes wrong:** CFMessagePort names live in the Mach bootstrap namespace. A process started over SSH may sit in a different bootstrap context from the Aqua session where Transom registered, and `CreateRemote` returns NULL, so the CLI wrongly reports "not running" (exit 2). The VM notes already need `launchctl asuser 501 …` to reach the pasteboard over SSH [CITED: auto-memory tart-vm-desktop-testing].
**How to avoid:** in VM tests run the CLI as `launchctl asuser $(id -u admin) ./transom …`, or from Terminal inside the GUI session. Note it in the README if confirmed. Raycast, Alfred, Shortcuts and Terminal run in the GUI session. [ASSUMED until the VM probe]

### Pitfall 11: The CLI can't find its own bundle
**What goes wrong:** run through `/usr/local/bin/transom`, `argv[0]` is "transom" or the symlink path. `Bundle.main` for an executable in `Contents/Helpers` isn't reliably the app bundle.
**How to avoid:** take `Bundle.main.executableURL` (or `_NSGetExecutablePath`), apply `resolvingSymlinksInPath()`, expect `…/X.app/Contents/Helpers/transom`, go up two levels to the `.app`, and read its bundle ID and URL scheme with `Bundle(url:)`. Put the path logic in a pure, unit-tested function. Outside a bundle (SwiftPM dev builds), fall back to the Release ID or a documented env override. [ASSUMED: `Bundle.main` behaviour for Helpers; test in the VM]

### Pitfall 12: CFMessagePort callbacks never fire in tests
**What goes wrong:** a run-loop source on the main CFRunLoop isn't serviced while `swift test`'s main thread isn't running a CFRunLoop.
**How to avoid:** `CFMessagePortSetDispatchQueue(port, .main)`. In a host-safe test, spawn the built `transom-cli` binary as a `Process` against a uniquely named test port. This is IPC only: no windows, no events.

### Pitfall 13: ⌥-digit chords type characters on many layouts (carried Pitfall 16)
**What goes wrong:** ⌥5–9 type `[ ] | { }` on German. Transom swallows them while zoom is on.
**How to avoid:** this is accepted by D-01 and mitigated through the Shortcuts footer, the README note and rebinding (UI-SPEC note 4). There's no auto-switch. Hotkeys are registered by key code [VERIFIED: Key.swift:43-51].

### Pitfall 14: Unmatched placeholder closes happen while paused or locked
**What goes wrong:** expiry runs while paused (UI-SPEC), but `World` changes during a locked session or display settling could fight the restore paths.
**How to avoid:** expiry goes through `LifecycleSync` (an OS fact; allowed while paused); the existing `planShown` guards (`!sessionPaused, pauseReasons.isEmpty, !settling` [VERIFIED: Arranger.swift:1979]) defer the reflow writes, as the UI-SPEC wants.

## Code Examples

### URL path rule (one extra branch)
```swift
// Source: extension of Sources/TransomEngine/TransomURL.swift:23-30 (this repo)
public static func parse(_ url: URL, scheme: String) -> Command? {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
        parts.percentEncodedUser == nil, parts.percentEncodedPassword == nil, parts.port == nil,
        parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil, let host = parts.percentEncodedHost
    else { return nil }
    let path = parts.percentEncodedPath
    if host == "view" || host == "save-view" {
        let bytes = Array(path.utf8)
        guard bytes.count == 2, bytes[0] == UInt8(ascii: "/"), (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(bytes[1]),
              let slot = ViewSlot(Int(bytes[1] - UInt8(ascii: "0")))
        else { return nil }
        return .camera(host == "view" ? .view(slot) : .saveView(slot))
    }
    guard path.isEmpty || path == "/" else { return nil }
    return commands[host]
}
```

### CLI client core
```swift
// Source: composed from CFMessagePort.h (SDK, read this session)
func send(_ url: String, port name: String) -> Int32 {
    guard let remote = CFMessagePortCreateRemote(nil, name as CFString) else {
        FileHandle.standardError.write(Data((CLICopy.notRunning + "\n").utf8)); return 2
    }
    var reply: Unmanaged<CFData>?
    let status = CFMessagePortSendRequest(remote, CLIProtocol.version, Data(url.utf8) as CFData, 2, 2,
                                          CFRunLoopMode.defaultMode.rawValue, &reply)
    guard status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() as Data? else {
        FileHandle.standardError.write(Data((CLICopy.noAnswer + "\n").utf8)); return 1
    }
    return CLIProtocol.exitCode(forReply: String(decoding: data, as: UTF8.self), command: url)   // prints stderr as needed
}
```

### Expiry through the normal close path
```swift
// Source: pattern on Arranger.closeDormant (Arranger.swift:964-975) and LifecycleSync.handle (LifecycleSync.swift:26-29)
mutating func expirePlaceholders(now: ContinuousClock.Instant) -> [ArrangerEffect] {
    var faults: [ArrangerEffect] = []
    for (id, p) in placeholders.sorted(by: { $0.key < $1.key }) where now >= p.deadline {
        placeholders[id] = nil
        do throws(LayoutError) { _ = try LifecycleSync.handle(.windowDestroyed(p.ref), world: &world, history: &history) }
        catch { faults.append(.fault("could not expire placeholder \(p.ref): \(error)")) }
    }
    return faults
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Titles stripped from layout.json (T-03-17, `withoutTitleHints`) | Titles written, file 0600, logs `.private` | Phase 8 (D-10) | Invert `titlesAreNeverWritten` test; update the README layout.json row (UI-SPEC copy) |
| Saved windows of a relaunched app removed at restore | Hint-matched, else placeholder with expiry | Phase 8 (D-11, D-12) | `LayoutRestore.reattach` changes contract; its doc comment must be rewritten |
| App quit → tiles close after the CG list agrees | App quit → placeholders for 30 s | Phase 8 (D-12a) | `.appTerminated` handling changes |
| `CGWindowListCreateImage`, deprecated Carbon helpers | (unchanged) KeyboardShortcuts Carbon `RegisterEventHotKey` still the supported global-hotkey path | — | No change |

**Deprecated/outdated:** nothing used by this phase is deprecated. `CFMessagePort` is not marked deprecated on macOS; Apple's doc says only that it is unavailable on iOS 7+ [CITED: Apple CFMessagePortCreateLocal doc JSON].

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Most AppKit apps' windows reach Transom as `.windowDestroyed` *after* `.appTerminated` on ⌘Q (the window teardown is the process exit) | Pattern 6, Pitfall 1 | App-quit placeholders don't appear for some apps; needs the rollback in Pitfall 1 |
| A2 | A CFMessagePort registered by the GUI app isn't visible from an SSH session without `launchctl asuser` | Pitfall 10 | VM CLI tests report exit 2 falsely; the README may need a note |
| A3 | `Bundle.main.executableURL` for a tool in `Contents/Helpers` points at the tool (possibly via the symlink), and two `deletingLastPathComponent` calls after `resolvingSymlinksInPath()` reach the `.app` | Pitfall 11 | The CLI talks to the wrong or no port |
| A4 | The scoring weights and threshold in Pattern 3 give good real-world results | Pattern 3 | Wrong matches or too many placeholders; tune via the table |
| A5 | Tart macOS guests support an in-guest `sudo reboot` (or need `tart stop` + `tart run`), with auto-login back to the admin GUI session | Validation | The reboot UAT needs a manual VNC login step |
| A6 | `CFMessagePortCallBack` imports into Swift as returning `Unmanaged<CFData>?` and `CFMessagePortSendRequest`'s `returnData` as `UnsafeMutablePointer<Unmanaged<CFData>?>` | Pattern 7 code | Compile fixes only (no design impact) |
| A7 | Reading of D-12 for apps already running at restore: a sliding 10 s from the last window created (not a flat 10 s from restore) | Pattern 6 deadlines | Placeholders for slow-restoring apps expire too early or too late; confirm with the user |
| A8 | Synchronous "accepted" replies (exit 0 before a Space switch finishes) are acceptable under the UI-SPEC's exit-0 wording | Pattern 7 | If the user wants switch failures reported, CFMessagePort is insufficient and the socket alternative is needed |

## Open Questions (RESOLVED)

1. **⌘Q event ordering (A1).**
   - What we know: the shell yields `.appTerminated` before tracker decisions; CloseRule closes terminated apps' windows once they leave the CG list.
   - What's unclear: whether some apps' windows are destroyed while the process is still "alive" for NSWorkspace.
   - Recommendation: a Wave-0 VM probe (log event order for 4 apps); include the Pitfall 1 rollback only if needed.
   - RESOLVED: VM probe in 08-04; the rollback is conditional on its result.
2. **CLI reachability from SSH (A2).**
   - What we know: GUI-session clients (Terminal, Raycast, Alfred, Shortcuts) share the Aqua bootstrap.
   - What's unclear: SSH behaviour on macOS 14/15/27.
   - Recommendation: the VM CLI test uses `launchctl asuser`. If SSH turns out to matter to the user, revisit the socket alternative.
   - RESOLVED: VM CLI checks use `launchctl asuser`; 08-07 records plain-SSH behaviour (A2) for information only.
3. **D-12 deadline for apps running at restore (A7).** The recommendation (sliding 10 s) needs user confirmation; it's a one-line constant either way. RESOLVED (orchestrator, 2026-11-03): sliding 10 s, restarted by each new window of that app.
4. **First relaunch after upgrade has no titles.** Existing schema-2 files have empty titles, so the first post-upgrade re-match relies on frame, order and sole-pair. Accept this and put a line in the release notes. RESOLVED: accepted; README note in 08-07.
5. **Boot-session guard (Pitfall 5).** It adds a `SessionRecord` field (`bootSession: String?`). It's cheap, but the planner should confirm it fits the schema-3 bump. RESOLVED: included in the schema-3 bump (08-02/08-03).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift toolchain / `swift build` | everything | ✓ | Swift 6.4 (Xcode 27.1); `swift build` succeeds | — |
| KeyboardShortcuts checkout | hotkeys | ✓ | 3.1.0 @ `772133d9` | — |
| `xcodegen` | CLI embedding (project.yml) | not probed this session (per CLAUDE.md, installed as 2.46.0) | — | `scripts/generate.sh` exits 2 with an install hint |
| `tart` + VM `pane-test` | live/re-match/CLI end-to-end tests | per auto-memory (`~/.local/bin/tart`, VM `pane-test`) | — | none: live tests are VM-only |
| `kern.bootsessionuuid` sysctl | Pitfall 5 guard | ✓ (host) | — | treat as unknown (identity re-attach kept) |
| Developer ID signing identity | release build with embedded helper | per project.yml (`DEVELOPMENT_TEAM: S2K7P43927`) | — | Debug build for VM tests |

**Missing dependencies with no fallback:** none identified.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) on the Swift 6.4 toolchain |
| Config file | none (SwiftPM test targets in Package.swift: `TransomModelTests`, `TransomEngineTests`, `TransomMacTests`, `TransomMacIntegrationTests`) |
| Quick run command | `swift test --filter "TransomEngineTests.(TransomURLTests|HintMatcherTests|SavedViewsTests|CLICommandLineTests|CLIProtocolTests)"` |
| Full suite command | `swift test` (host-safe suites; live suites gate on `TRANSOM_LIVE=1` and skip on the host) |
| Live (VM only) | `scripts/vm-live-test.sh <SuiteName>` |

Every `--filter` gate must show a non-zero executed test count (03-CONTEXT verification rule).

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VIEW-01 | Save stores desk + identities/home; refuses empty (N19); replaced flag | unit | `swift test --filter TransomEngineTests.ArrangerViewsTests` | ❌ Wave 0 |
| VIEW-01 | Go resolves LCA; desk with most windows; ties → saved desk; all gone → home + allGone; display gone refusal; already-there treated as success | unit | `swift test --filter TransomEngineTests.ArrangerViewsTests` | ❌ Wave 0 |
| VIEW-01 | Version rule: 15.0/15.1 → ⌃⌥ / ⇧⌃⌥; else ⌥ / ⇧⌥; 18 names, raw values, all in `zoomNames` | unit | `swift test --filter TransomMacTests.HotkeysTests` | ❌ Wave 0 (check for an existing hotkeys test file) |
| VIEW-02 | View survives split/move (identities, not NodeIDs); remap on `windowRekeyed` and on placeholder fill | unit | `swift test --filter TransomEngineTests.ArrangerViewsTests` | ❌ Wave 0 |
| VIEW-02 | layout.json schema 3 round trip; schema 2 loads with `views == []`; schema 1 still migrates; a newer (4) file is left untouched; validate rejects dup slots, slot 0/10, > 9 views; titles written, 0600 | unit (temp dir) | `swift test --filter "TransomMacTests.LayoutStoreTests|TransomEngineTests.SpaceRekeyTests"` | ✅ (extend; invert `titlesAreNeverWritten`) |
| VIEW-02 | View desks rekeyed with the Space table | unit | `swift test --filter TransomEngineTests.SpaceRekeyTests` | ✅ extend |
| VIEW-03 | `view/1…9`, `save-view/1…9` parse; every UI-SPEC-rejected form returns nil; per-slot rate limit independence | unit | `swift test --filter TransomEngineTests.TransomURLTests` | ✅ extend |
| VIEW-03 | Help table covers every allow-listed command exactly once | unit | `swift test --filter TransomEngineTests.CLICopyTests` | ❌ Wave 0 |
| VIEW-04 | HintMatcher scoring table (Pattern 3 cases incl. ties, sole pair, AX conflict, bundle filter) | unit (parameterised) | `swift test --filter TransomEngineTests.HintMatcherTests` | ❌ Wave 0 |
| VIEW-04 | Restore: identity re-attach, then hint match; unmatched docked → placeholder; floaters kept to expiry; boot-session mismatch skips identity | unit | `swift test --filter TransomEngineTests.ArrangerRestoreTests` | ✅ extend |
| VIEW-04 | App quit → placeholders (30 s); relaunch → fill via `adopt`; ⌘W closes at once; expiry via close path at 10 s / 5 min / 30 s; inventories don't close placeholders; `nextWake` includes deadlines | unit | `swift test --filter TransomEngineTests.ArrangerPlaceholderTests` | ❌ Wave 0 |
| VIEW-04 | `World.adopt` and `World.refreshingTitles` keep the World valid and undo snapshots consistent | unit | `swift test --filter TransomModelTests.WorldAdoptTests` | ❌ Wave 0 |
| VIEW-04 | Fixture app quit/relaunch with distinct titles re-matches both windows to their tiles; a fixture never reopened leaves a placeholder that expires | live (VM) | `scripts/vm-live-test.sh RematchIntegrationTests` | ❌ Wave 0 |
| VIEW-04 | Transom relaunch (new ArrangeController on the same store dir, the pattern at ArrangeIntegrationTests.swift:219-231) plus fixture relaunch = simulated reboot | live (VM) | `scripts/vm-live-test.sh RematchIntegrationTests` | ❌ Wave 0 |
| VIEW-05 | Argument parsing → URL/help/usage error; exact stderr text; exit codes 0/1/2/64; ASCII conversion of refusal reasons | unit | `swift test --filter "TransomEngineTests.CLICommandLineTests|TransomEngineTests.CLIProtocolTests"` | ❌ Wave 0 |
| VIEW-05 | Port-name and bundle derivation from a resolved Helpers path (pure) | unit | `swift test --filter TransomEngineTests.CLIProtocolTests` | ❌ Wave 0 |
| VIEW-05 | IPC round trip: `CLIListener` on a unique test port + spawned `transom-cli` → ok / refused / rate / not running (no listener → 2) | integration (host-safe: IPC only, no windows/events) | `swift test --filter TransomMacTests.CLIListenerTests` | ❌ Wave 0 |
| VIEW-05 | Installed app: `transom view 3; echo $?` for success, unknown, bad slot, rate limit, Transom quit (2) | live (VM, `launchctl asuser`) | manual script in VM UAT | manual |
| UI | Real reboot, placeholder click-through, VoiceOver joined line, German layout chords | UAT | UI-SPEC "backstop" rows + user host checklist | manual |

### Sampling Rate
- **Per task commit:** the quick run command for the suites the task touches (non-zero test count).
- **Per wave merge:** `swift test` (full host suite) plus `scripts/check-no-appkit.sh`.
- **Phase gate:** full host suite green, then the VM `RematchIntegrationTests` and the CLI VM script, then `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `Tests/TransomEngineTests/HintMatcherTests.swift`: VIEW-04 scoring table
- [ ] `Tests/TransomEngineTests/ArrangerViewsTests.swift`: VIEW-01/02
- [ ] `Tests/TransomEngineTests/ArrangerPlaceholderTests.swift`: VIEW-04 lifecycle
- [ ] `Tests/TransomEngineTests/CLICommandLineTests.swift`, `CLIProtocolTests.swift`, `CLICopyTests.swift`: VIEW-05 and the help table
- [ ] `Tests/TransomModelTests/WorldAdoptTests.swift`: model ops
- [ ] `Tests/TransomMacTests/CLIListenerTests.swift`: IPC round trip (needs the `transom-cli` SwiftPM target built first)
- [ ] `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift`: VM only, fixture quit/relaunch, Transom relaunch
- [ ] VM probe script/notes for Open Questions 1 and 2 (event order on ⌘Q; CLI over SSH vs `launchctl asuser`)
- [ ] Extend `TransomURLTests`, `LayoutStoreTests` (invert the titles test, add schema 2/3), `SpaceRekeyTests`, `ArrangerRestoreTests`

## Security Domain

`security_enforcement: true`, ASVS level 1 [VERIFIED: .planning/config.json].

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No accounts; local single-user app |
| V3 Session Management | no | — |
| V4 Access Control | yes (local IPC) | CFMessagePort is reachable only within the user's Mach bootstrap namespace (same login session); sandboxed apps can't look up arbitrary global names without a mach-lookup exception [ASSUMED]. Parity with the URL scheme, which any web page can trigger, is D-07's chosen bar. The allow-list holds no destructive command (no close/quit) [VERIFIED: TransomURL.swift:8-19] |
| V5 Input Validation | yes | `TransomURL.parse` strict allow-list (exact scheme, lowercase host, `percentEncodedPath` exactly `/` + one digit for the two view hosts); CLI request size cap (256 B) and msgid check; LayoutFile.validate for `views` (slot range, uniqueness, counts) before use |
| V6 Cryptography | no | — |
| V7 Error Handling & Logging | yes | Rejected URLs/CLI requests logged without contents; titles `.private`; `cli`/`match`/`views` log categories with public non-sensitive values (UI-SPEC) |
| V8 Data Protection | yes | layout.json now holds titles: write 0600 (existing `setAttributes`), keep `~/Library` defaults; backups/`.corrupt` copies preserve permissions (`copyItem`/`moveItem`) |
| V11 Business Logic (abuse) | yes | Rate limit 1/s per command per slot, shared by URL and CLI; refusals have no side effects |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious web page / app spams `transom://save-view/N` to overwrite a user's views | Tampering | Per-slot rate limit (once a second each); saving never moves windows; accept residual risk (a view is easy to re-save; no data loss beyond the slot). Note it in the threat model as "accept" with this reasoning |
| Local process floods the CLI port | Denial of service | Same rate limit; replies are constant-time decisions; 256 B cap |
| Crafted URL with percent-encoding or extra path segments | Tampering | `percentEncodedPath` byte compare; any query, fragment, user or port is rejected (existing) |
| Window titles (document names) leaked via layout.json or logs | Information disclosure | 0600 file; `.private` log interpolation; `WindowRef.description` excludes titles [VERIFIED: IDs.swift:107-110] |
| Brief world-readable window during the atomic write (`.atomic` then `setAttributes`) | Information disclosure | Low: `~/Library` is user-only by default [ASSUMED]. Optional hardening: create the temp file with 0600 before the rename |
| Hostile layout.json `views` (out-of-range slot, huge lists) | Tampering | `LayoutFile.validate` + the existing 16 MB cap (`World.maxEncodedBytes`) [VERIFIED: Persistence.swift:25] |
| Name squatting: another process registers `com.eightabyte.transom.cli` first so the CLI talks to it | Spoofing | Low (requires local code execution as the user). The app logs `cli listener failed` when `CreateLocal` returns NULL; accept |

## Sources

### Primary (HIGH confidence)
- Repo files read this session: `Sources/TransomEngine/{TransomURL,LayoutFile,LayoutRestore,Arranger,Arranger+Camera,Navigator,ViewPlanner,Command,CloseRule,WindowTracker,LifecycleSync,SpaceRekey,SpaceSwitchPlan,FallbackMatcher}.swift`, `Sources/TransomModel/{World,Persistence,IDs,DesktopLayer}.swift`, `Sources/TransomMac/{LayoutStore,AppDelegate,ArrangeController,AXWindowSystem,SpaceSwitcher}.swift`, `Sources/TransomMac/Input/Hotkeys.swift`, `Sources/TransomMac/Overlay/NoticeQueue.swift`, `Package.swift`, `Package.resolved`, `xcode/project.yml`, `scripts/{vm-live-test,vm-spike,release,build-debug,generate}.sh`, `Tests/TransomEngineTests/TransomURLTests.swift`, `Tests/TransomMacTests/LayoutStoreTests.swift` (test list), `Tests/TransomMacIntegrationTests/{IntegrationSupport,ArrangeIntegrationTests}.swift`
- Pinned KeyboardShortcuts 3.1.0 checkout: `Name.swift`, `Key.swift`, `KeyboardShortcuts.swift`, `HotKey.swift`, `Shortcut.swift`, `RecorderCocoa.swift`
- macOS SDK header `CoreFoundation.framework/Headers/CFMessagePort.h` (local Xcode 27.1 SDK)
- Local probes: `swift build` (success), `sysctl -n kern.bootsessionuuid kern.boottime`

### Secondary (MEDIUM confidence)
- XcodeGen ProjectSpec: https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/Docs/ProjectSpec.md (dependency `embed`/`codeSign`/`copy`, destinations, product type `tool`)
- Apple docs (JSON): CFMessagePortCreateLocal, CFMessagePortSendRequest via developer.apple.com/tutorials/data/documentation/corefoundation/…

### Tertiary (LOW confidence)
- Web search on Tart guest reboot behaviour: no conclusive source (https://github.com/cirruslabs/tart/wiki); treated as A5
- Auto-memory notes on VM SSH/`launchctl asuser` usage (pasteboard), basis for Pitfall 10

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. No new dependencies; every API was checked in the SDK header or the pinned checkout.
- Architecture: HIGH for the engine integration points (code read with line numbers); MEDIUM for the placeholder audit breadth (Pitfall 8 lists surfaces, but not every call site was traced).
- Pitfalls: HIGH for 2, 3, 5, 6, 7, 9, 12 (code or SDK evidence); LOW for 1, 10, 11 (need VM probes).
- Matching weights: MEDIUM (reasoned, needs the table plus VM evidence).

**Research date:** 2026-11-03
**Valid until:** 2026-12-03 (stable stack; re-check if KeyboardShortcuts or the macOS SDK changes)
