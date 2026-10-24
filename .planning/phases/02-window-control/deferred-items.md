## Deferred Items

- Release build warns in `Sources/PaneEngine/PermissionReducer.swift:110`: "'where' only applies to the second pattern match in this 'case'"
  status: open
  **Found by:** 02-09, while running `swift test -c release -Xswiftc -enable-testing`. The file predates 02-09 and the plan does not touch it. Check that the `where` guards both patterns as intended.
