import CoreGraphics
import Foundation

/// One pointer or modifier event, copied out of the CGEvent in the tap callback.
nonisolated struct TapEvent: Sendable {
    let type: CGEventType
    let location: CGPoint
    let flags: CGEventFlags
    let windowUnderPointer: Int64
}

/// The session event tap (RESEARCH Pattern 6).
nonisolated final class InputTap: @unchecked Sendable {
    let events: AsyncStream<TapEvent>
    private let continuation: AsyncStream<TapEvent>.Continuation
    private(set) var port: CFMachPort?
    private(set) var thread: Thread?

    init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    var isRunning: Bool { false }

    func start() -> Bool { false }

    func stop() {}
}
