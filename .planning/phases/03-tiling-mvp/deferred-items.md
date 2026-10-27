# Phase 3 deferred items

Out-of-scope issues found while executing plans. Not fixed by the plan that found them.

## Found in 03-08

- **Live `ArrangeIntegrationTests/aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` fails on this Mac.** It fails the
  same way at a216975, before any 03-08 change ("window 0 did not float clear of window 1 within 5 s (fixture frames
  [])", the guard in the final `waitUntil`). It passed in 03-06 and 03-07. The Mac now has a second display (DELL
  S3425DW beside the built-in one). That is the most likely cause, since the test sizes its minimums from the main
  display only. Not re-run after 3 failures (live-test rule); diagnose with a two-display fake first.
- **`aMinimisedDockedWindowLendsItsTileAndComesBack` (live) failed once and passed on the rerun.** The deminimised
  window did not return within 3 s.
- **`FreezeTestTests/itResumesByItself` is timing-sensitive.** It failed once under the full `swift test` load (the
  50 ms auto-resume with a 1 s deadline) and passed three times alone.

## Found in 03-12

- **A floating window whose minimum is larger than the display blocks every dock on its desk.** The Planner sizes the
  Desktop tile to the largest present floating window's minimum, and the Desktop is never an unfit victim, so with such
  a window floating, any docked tile comes out unfit. Arrange All then refuses every window (beep plus blocked flash),
  and Dock does the same. Pre-existing Planner semantics, seen while writing the 03-12 leftover test. A window that
  big can't sit on the Desktop either, so the fix probably belongs in how the Planner caps that minimum.
- **`swift format lint --strict` is not clean on the existing code** (about 1,250 findings in Arranger.swift at
  8038b4b under the default rules; there is no `.swift-format` file and no lint step in CI). New 03-12 code follows
  the file's existing style (`var candidate = world, candidateHistory = history`).

## Found in 03-16

- **Test UserDefaults suites leave empty plists behind.** `removePersistentDomain(forName:)` clears the domain but
  cfprefsd leaves `~/Library/Preferences/com.eightabyte.pane.tests.<suite>.<UUID>.plist` files (102 from
  `GapPreferenceTests` at 03-16; 03-16's own `conflicts` ones were removed by hand). Test-only domains, never the
  user's data. A shared helper that also deletes the file, or one fixed suite name per test file, would stop the pile-up.
- **The plan's `killall` grep baseline is out of date.** `grep -rn killall Sources` finds one hit at 16d0692: the
  03-15 doc comment in `AppDelegate.swift` describing `killall Pane` sending SIGTERM. 03-16 adds none.

## Found in 03-17

Seen during the release run and the clean-Mac install check (Tart VM, macOS 15.7.7, 2026-10-26). Not fixed by 03-17.

- **`release.sh`'s hdiutil fallback lost the DMG.** create-dmg is not installed, so the script took the hdiutil path.
  `hdiutil create` printed "created: …/build/Pane-0.3.0.dmg", but the file was not there afterwards and the next
  `codesign` of the DMG failed (exit 1). Running the same hdiutil command by hand produced the file. Root cause is
  unknown. It may be timing, or a sandbox effect of running under the Claude Code Bash tool. Options: check the file
  exists after `hdiutil create` and retry once, or install create-dmg. The app was already notarised and stapled when
  this happened; the DMG steps were finished by hand.
- **An Accessibility grant made while Pane is running is not picked up until relaunch.** On first launch the log shows
  no permission transition and no tracking. After a relaunch it shows notTrusted -> probing -> ready. The likely cause
  is that polling only starts inside the Set Up Pane flow (`PermissionController` `.startPolling`). It is not known
  whether the Set Up Pane window appeared on first launch.
- **Safari windows do not dock when dragged by their title area (unified toolbar).** TextEdit docks fine. Safari stays
  floating on the desktop area.
- **The app icon is a blank placeholder in Pane's alerts.** iconservices logs STORE_LOOKUP not-found. The Release build
  may have no AppIcon asset.
- **A floating Safari window was placed at the bottom of the desktop region, with empty space above it.** Cosmetic.
  Check whether this placement is intended.
- **(03-18) A plain green click on a floating window that exactly fills the Desktop tile does nothing (beep).**
  `Arranger.dock` targets the window's centre; that is the Desktop tile's centre, so `dockTarget` returns
  `.tile(_, .center)` and dock beeps (tab groups are Phase 7, Arranger.swift:671). It happens after an Option-click
  zoom on a floating window, because D-33 clamps it to the whole Desktop tile. Seen in the VM: a press preset to the
  real window ID behaves the same, so it is not the tap's window lookup. TILE-06 expects "floating docks". Options:
  fall back to a non-centre edge target when the centre hits the Desktop tile, or accept and announce.
  **Resolved by quick 261027-gqo (2026-10-27):** Dock never returns the centre zone for a tile. `Planner.dockTarget`
  has fallen back to the nearest edge band since 03-04. At the exact centre that fallback used to pick the right edge;
  per the user decision it now picks the left edge. The new regression test is
  `ArrangerGreenButtonTests.aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt`. Drag-drop onto a centre is
  unchanged. The VM beep with 460 pt minimums is the D-26 no-room refusal, which the 03-19 item tracks.
- **(03-18) Space 2's docked windows are dropped on every Pane relaunch.** Clean repro, twice in the VM: layout.json
  had a second desk (spaceID 41) with Notes#150 and reminders#693 docked, both apps running; after quit and relaunch
  on Space 1 the desk key stays but its docked list is empty. Matches the 03-UAT.md note on test 17.
  **Resolved by 03-23 (G-03-8):** saved windows still in the layer-0 CG list stay dormant in their desk and re-attach
  when their Space is shown; VM clean and kill -9 relaunches on 0.3.7 (1005) kept Space 41 intact.
- **(03-19) Dock Window is enabled in the menu when the dock will be refused for lack of room.** `Arranger.availability`
  checks only that the focused window floats and is present. In the VM desk (floating Finder windows, 460 pt minimum,
  and Safari in the Desktop tile) no split of the 574x326 Desktop tile fits, so ⌃⌥⌘D on a new TextEdit window beeped
  with Dock Window enabled and no log line. pane://split-finder was refused the same way while Safari's window sat in
  the full-width Desktop tile. Both are D-26 behaving as designed; the silent refusal is what can be mistaken for a
  focus bug. Options: log the refusal at info level, or disable Dock Window when the plan has no room.
  **Resolved (user, 2026-10-27):** ArrangeController logs every `.announce` at info level, so each no-room
  refusal (keyboard, command, drag, Finder) now writes "Not enough room to dock here" to the `com.eightabyte.pane` `arrange` log.
- **(03-22) Notices are never logged.** `.notice(.lostRoom(...))` goes only to the toast, and the toast is not visible
  over VNC, so a VM run cannot show that the lost-room notice fired; it can only infer it from a docked window turning
  floating with no command. Options: log each notice at info level in ArrangeController when it is queued.
  **Resolved (user, 2026-10-27):** `ArrangeController.post` logs each notice (`notice lostRoom(...)`) to the
  `com.eightabyte.pane` `arrange` log before queuing it; the effect runner posts through it.
- **(G-03-9, deferred to Phase 6 by the user, 2026-10-26) A closed Safari window stays tracked and in layout.json.**
  Safari keeps the closed window's CGWindowList (optionAll) entry for minutes: layer 0, offscreen, empty Space list.
  `CloseRule` only closes once the CG entry is gone, and 03-23's `LayoutRestore.isAlive` / `AXWindowSystem.liveWindows`
  count any layer-0 entry as alive, so the window stays present (count, layout.json) and survives relaunch as dormant.
  Bookkeeping only: no overlap; the running-session ghost can only add its learned minimum to the Desktop tile minimum.
  Fix direction: when Space data is known, a layer-0 entry with an empty Space list counts as absent (CloseRule AX-invalid
  row; isAlive). First measure in the VM what minimised windows, Cmd-H-hidden apps and hidden tabs report for Spaces.
  Failing headless tests drafted in .planning/debug/g-03-9-closed-safari-lingers.md.

## Found in 03-24

- **(G-03-10 live risk, a non-goal of 03-24) An app whose AX reads fail at the first unpaused sweep loses its saved
  shown-Space windows at restore.** The restore waits for an unpaused sweep, not for each app's first successful read.
  So an app that answers -25204 or times out just after unlock (or at an ordinary launch) is untracked when `reattach`
  runs. Its windows on the shown Space are removed, because the `live` filter keeps only hidden-Space entries dormant.
  They come back as new floaters on its next refresh. This is unchanged by 03-24 and is the same at any launch. Also
  accepted (plan-check W2): a hint refresh already in flight for a pid when the first unpaused sweep reaches it folds
  that pid's initial refresh into a non-initial follow-up (AXWindowSystem `refresh`, the `inFlight` guard), so that
  app's new windows can still be settling at `.sessionPaused(false)`. Options: keep a shown-Space saved window dormant
  while its app's first read failed, or hold the restore until every app's first read succeeded or it was degraded.

## Found in 03-25 and 03-26

- **(G-03-11, a non-goal of 03-25) A floater the user leaves past the screen edge, clear of tiles, is still left
  alone.** The orchestrator's default was to clamp any floater sticking out of the Desktop back in. In a planning
  experiment that broke the 03-04 fence `aFloatingWindowOffTheScreenEdgeButClearOfTilesIsLeftAlone` (D-24) and six drag
  and reflow tests. Only frames Pane's own clamp left outside are corrected. Option: ask the user whether D-24 should
  change.
- **(03-25) Floater floors can stop a boundary drag early for an app that applies writes late (T-03-71).** The
  read-back still shows the old size, so the floor holds until that app's next smaller frame event drops it. Floors are
  session-only and counted by boundary drags only.
- **(03-25) Float All keeps its tile-rect placement (TILE-16).** The 2026-10-27 decision names Float and the green
  button only. Option: Float All could use each window's pre-dock frame too.

## Polish (user, 2026-10-27)

- Green button: after Pane takes a plain click, macOS 15's Move & Resize hover popup (ThemeWidgetControlViewService, layer 101) stays open until the pointer leaves, because the swallowed press never reaches it. Close or dismiss it after a taken press. User asked to log it as polish (G-03-4 hand check on 0.3.10).
