# Deferred items, phase 08.1.1

- (08.1.1-12) `Tests/TransomMacIntegrationTests/OptionsBundleIntegrationTests.swift` L56-57 and L153-154 still explain their steps with the Desktop tile ("the largest tile, the Desktop", "inside the Desktop tile"). The suite is in neither 08.1.1-12's nor 08.1.1-18's file list and was not run. Its expectations may be stale on the empty desk.
- (08.1.1-12) `Tests/TransomMacIntegrationTests/HoldOptionIntegrationTests.swift` L30 and L185 still name the Desktop tile. That suite belongs to 08.1.1-18 Task 2. Its `dockedPair` setup now gives [0 | 1] across the whole screen (LiveDrag.swift, 08.1.1-12).
