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
