# Phase 8: Saved Views, URLs & Persistence - Context

**Gathered:** 2026-11-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Save the current camera view to slots 1–9 and return to it by hotkey, URL or CLI. The `transom://` scheme grows view
commands. A bundled `transom` command-line tool runs every URL command and exits non-zero with a message on errors.
Layouts come back after Transom relaunches, app relaunches and reboots, with windows re-matched to their tiles by
persisted hints. Windows that never return leave a placeholder that expires.

Requirements: VIEW-01, VIEW-02, VIEW-03, VIEW-04, VIEW-05.

Out of scope: the Settings window and an "Install CLI" button (Phase 9), a keyboard/URL way to form a tab group, and
multi-display work beyond what Phase 6 already does.

</domain>

<decisions>
## Implementation Decisions

### Saved views (slots 1–9)
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

### URLs and the `transom` CLI
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

### Re-matching after a relaunch or reboot
- **D-10:** Each window's match hints are persisted in layout.json: bundle ID, title, frame and its order within the
  app. They reuse WindowRef's existing `titleHint` / `axIdentifier` / `creationOrder` from Phase 1. Candidates are
  scored and a window is matched only above a threshold. On a tie, neither window is matched: the tile becomes a
  placeholder and the window floats.
  - **This supersedes T-03-17** (titles stripped from layout.json by `World.withoutTitleHints()`), because VIEW-04
    needs titles to tell an app's windows apart. layout.json must be written user-only (0600), and titles never go to
    logs at public level.
- **D-10a (user, 2026-11-03):** A lone window whose title changed matches its tile only if it reopens at about its old
  frame (WR-03). Opened elsewhere, it floats and the tile expires. Never taking a wrong window outranks keeping the tile.
- **D-11:** Re-matching runs when Transom launches and whenever an app relaunches while Transom keeps running (new pid).
  Both paths use the same matcher. It extends `LayoutRestore.reattach`, which today removes saved windows whose app
  relaunched.
- **D-12:** A placeholder expires 10 s after its app has launched without a match, or 5 min after Transom launches if
  the app never opens. When it expires, the tile is removed through the normal close path, as if the window had closed.
- **D-12a (user, 2026-11-03):** When an app quits while Transom runs, its docked windows become placeholders (so D-11
  relaunch matching has something to fill). They expire 30 s after the quit if the app has not relaunched. ⌘W on a
  window whose app keeps running still closes the tile at once.
- **D-12b (user, 2026-11-03):** Tiles for windows on Spaces not being shown wait on every path, including when a stored
  display arrangement is re-applied after a reboot. They do not expire while their desk is hidden.
- **D-13:** A placeholder is drawn as a dim tile in the app's colour, with the app icon and "Waiting for <App>…". Clicks
  pass through it. It reuses the Phase 4 app-colour / icon tile (AppColor, CollapsedBlockView).

### Storage and edge cases for saved views
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/ROADMAP.md`: Phase 8 section, with its success criteria and scope notes (allow-list, rate limit, match
  hints with a score threshold, layout-aware chords)
- `.planning/REQUIREMENTS.md`: VIEW-01..05
- `.planning/phases/03-tiling-mvp/03-CONTEXT.md`: URL scheme safety (SAFE-03), crash-safe restore, the ⌃⌥ fallback
  note for ⌥1–9
- `.planning/phases/04-zoom-camera/04-CONTEXT.md`: camera targets (`ViewTarget`), history, zoom-off behaviour (D-D)
- `.planning/phases/06-overview-spaces-displays/06-CONTEXT.md`: Space switching, per-display/per-Space desks
- `.planning/phases/07-tab-groups/07-CONTEXT.md`: the `groups` schema addition, an example of the migration pattern
- `.claude/CLAUDE.md`: stack (KeyboardShortcuts 3.1.0, no AppKit in Model/Engine), hotkey caveat for 15.0–15.1

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/TransomEngine/TransomURL.swift`: the allow-list parser and `TransomURLRateLimiter`. Extend these for view
  paths, and reuse the parser in the CLI.
- `Sources/TransomEngine/LayoutRestore.swift`: `reattach(_:tracked:live:)`, the identity re-attach. VIEW-04 extends it
  with hint-based matching.
- `Sources/TransomEngine/ViewPlanner.swift`: `ViewTarget` (`.home` / `.node(NodeID)`) and the camera planning that
  views resolve to.
- `Sources/TransomModel/Persistence.swift` and `World.swift`: `schemaVersion` and stepwise migrations.
  `withoutTitleHints()` is the T-03-17 stripping that D-10 reverses.
- `Sources/TransomMac/Input/Hotkeys.swift`: KeyboardShortcuts names, the `entries` table and `setZoomHotkeys(enabled:)`.
- `Sources/TransomMac/LayoutStore.swift`: reads and writes layout.json.
- `Sources/TransomMac/Zoom/AppColor.swift` and `CollapsedBlockView`: the app-colour tile for placeholders.
- `Sources/TransomEngine/FallbackMatcher.swift`: an existing scoring-style matcher (AX to CG) to model the hint matcher
  on.

### Established Patterns
- Pure decision logic lives in TransomEngine and is unit-tested headless. TransomMac does the AppKit and AX side.
- Commands flow through the `Command` enum and Arranger dispatch, and URLs map to the same commands as hotkeys.
- Live behaviour is tested only in the Tart VM (`scripts/vm-live-test.sh`), never on the host.
- Package.swift already has extra executable targets (transom-dump, the spikes), so the CLI is a new
  `executableTarget`, copied into the bundle by `xcode/project.yml`.

### Integration Points
- `AppDelegate` handles URL opens. The CLI's IPC listener lives beside it and feeds the same path.
- The Arranger runs the first-inventory restore and handles app launch/terminate, which is where re-matching and
  placeholder expiry hook in.
- The README's URL list and hotkey table, and its layout.json and defaults sections.

</code_context>

<specifics>
## Specific Ideas

- The user consistently accepts the recommended defaults: minimal UI, no extra confirmation dialogs, VoiceOver
  announcements for feedback.
- Toast and notice copy: "Saved view 3", "Replaced view 3", "View 3", "No view in slot 3", "Waiting for Safari…",
  "Transom is not running".

</specifics>

<deferred>
## Deferred Ideas

- An "Install Command-Line Tool…" button: Phase 9 Settings.
- A keyboard, URL or CLI command to form a tab group ("group with"): a gap carried from Phase 7, not in VIEW-01..05.
  This needs a backlog entry.
- A `transom://clear-view/N` command: not needed now (D-16).

</deferred>
