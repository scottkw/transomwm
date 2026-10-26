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
