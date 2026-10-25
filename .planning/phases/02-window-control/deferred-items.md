## Deferred Items

- Release build warns in `Sources/PaneEngine/PermissionReducer.swift:110`: "'where' only applies to the second pattern match in this 'case'"
  status: open
  **Found by:** 02-09, while running `swift test -c release -Xswiftc -enable-testing`. The file predates 02-09 and the plan does not touch it. Check that the `where` guards both patterns as intended.

- Intermittent `CloseIntegrationTests.closeFreezeHideAndQuitAreDecidedByTwoSources` failure at line 58 ("unhidden window not .present within 2 s"), seen 1 time in about 37 unlocked runs
  status: open
  **Found by:** the debug session for the live move-test flake (`.planning/debug/live-move-test-flaky.md`). No session pause was logged and the Mac was unlocked. After the unhide, no refresh ran for 2 s. Either the "app shown" notification was lost after the freeze and resume, or it arrived before a coinciding refresh read the hidden flag. Next step: log the hidden flag on every refresh.
