/// Which apps' next full update must be flagged `ObservationContext.spaceChanged`.
///
/// Each Space-switch notification bumps `generation` and marks the pids running then (a newer notification replaces an
/// older mark). An update is flagged while its pid has a mark. It consumes the mark only if its reads began at or after
/// the notification that set it (`readGeneration`, recorded when the reads begin). A notification that lands between
/// an update's reads and its ingest therefore flags that update and the next one, never zero.
public struct SpaceSwitchMarks: Equatable, Sendable {
    public private(set) var generation: UInt64 = 0
    private var marks: [Int32: UInt64] = [:]

    public init() {}

    public mutating func spaceDidChange(pids: some Sequence<Int32>) {
        generation += 1
        for pid in pids { marks[pid] = generation }
    }

    /// Whether the update of `pid` whose reads began at `readGeneration` is flagged.
    public mutating func take(pid: Int32, readGeneration: UInt64) -> Bool {
        false  // RED stub
    }

    public mutating func forget(pid: Int32) {
        marks[pid] = nil
    }
}
