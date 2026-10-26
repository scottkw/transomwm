import AppKit
import CoreGraphics
import PaneModel

/// Reads one window's CG bounds at 60 Hz while it is being dragged (RESEARCH Pattern 4): fresher than AX move
/// notifications, and no AX IPC. Bounds are global top-left points. It stops itself once the left button is up, so a
/// mouse-up the tap missed cannot leave it running.
@MainActor final class DragFramePoller {
    private var task: Task<Void, Never>?

    func start(windowID: UInt32, onFrame: @escaping (Rect) -> Void) {
        stop()
        task = Task {
            var last: Rect?
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                if let frame = Self.bounds(of: windowID), frame != last {
                    last = frame
                    onFrame(frame)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// `CGWindowListCreateDescriptionFromArray` takes raw CGWindowID values, not CFNumbers.
    nonisolated static func bounds(of windowID: UInt32) -> Rect? {
        guard let id = UnsafeRawPointer(bitPattern: UInt(windowID)) else { return nil }
        var values: [UnsafeRawPointer?] = [id]
        guard let array = CFArrayCreate(nil, &values, 1, nil),
            let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]],
            let dictionary = list.first?[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        else { return nil }
        return Rect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
    }
}
