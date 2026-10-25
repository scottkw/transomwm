import PaneEngine
import PaneModel
import os

/// Process-wide allocator of synthetic window IDs (`0xF000_0000 | counter`), given only when the frame fallback
/// is ambiguous (D-15). Real CGWindowIDs stay far below the range; `avoiding` (every CG ID in the refresh) rules
/// out a collision anyway.
nonisolated enum SyntheticWindowIDs {
    private static let counter = OSAllocatedUnfairLock(initialState: UInt32(0))

    static func next(avoiding: Set<UInt32>) -> UInt32 {
        counter.withLock { counter in
            var id: UInt32
            repeat {
                counter += 1
                precondition(counter < 0x1000_0000, "synthetic window IDs exhausted")  // 268 million in one session
                id = 0xF000_0000 | counter
            } while avoiding.contains(id)
            return id
        }
    }
}
