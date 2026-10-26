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
- **(03-18) Space 2's docked windows are dropped on every Pane relaunch.** Clean repro, twice in the VM: layout.json
  had a second desk (spaceID 41) with Notes#150 and reminders#693 docked, both apps running; after quit and relaunch
  on Space 1 the desk key stays but its docked list is empty. Matches the 03-UAT.md note on test 17.
