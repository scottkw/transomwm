# Deferred items, phase 08.1.1

- (08.1.1-12) `Tests/TransomMacIntegrationTests/OptionsBundleIntegrationTests.swift` L56-57 and L153-154 still explain their steps with the Desktop tile ("the largest tile, the Desktop", "inside the Desktop tile"). The suite is in neither 08.1.1-12's nor 08.1.1-18's file list and was not run. Its expectations may be stale on the empty desk.
- (08.1.1-12) `Tests/TransomMacIntegrationTests/HoldOptionIntegrationTests.swift` L30 and L185 still name the Desktop tile. That suite belongs to 08.1.1-18 Task 2. Its `dockedPair` setup now gives [0 | 1] across the whole screen (LiveDrag.swift, 08.1.1-12).
- (08.1.1-18) Resolved: HoldOptionIntegrationTests no longer names the Desktop tile (its drop point and drag distance were stale; fixed in 08.1.1-18 Task 2).
- (08.1.1-18) Pre-existing macOS 27.2 live failures, outside this phase: each one fails the same way at 475030e, the commit before 08.1.1 (log `.build/0811-18-baseline-vm27.log`), and each passes on macOS 15.7.
  - `OverviewIntegrationTests`: swiftpm-testing-helper exits with status 0 during `overviewOpensPerDisplayAndCloses`, before any result line. The suite never reports.
  - `OverviewSpaceSwitchIntegrationTests`: `pickingAMiniTileOnAnotherSpaceSwitchesThereAndFocusesItsWindow` (L114 cached), `theFirstVisitToASpaceNotYetReadCapturesItsWindows` (L155 cached), `aPanelStrandedOnAnotherSpaceDoesNotHideTheNextOpen` (L195, the Arranger never sees the second Space). Same class as the known `aViewOnAnotherSpaceSwitchesFirst`.
  - `TabStripSpaceIntegrationTests.theStripShowsOnlyOnItsGroupsSpace` (L61): a strip stays ordered in on the second desktop.
  - `TabGroupIntegrationTests.closeAndMinimizeCommandsActOnFixtureWindows` (L200-201): the close is not confirmed within `Arranger.closeConfirmation` (about 3 s).
