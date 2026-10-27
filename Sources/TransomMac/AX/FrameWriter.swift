import ApplicationServices
import TransomEngine
import TransomModel

/// One frame write to another app's window (D-17). Every call is AX IPC: run it only on the app's `AXAppThread`.
nonisolated enum FrameWriter {
    /// Turns the app's `AXEnhancedUserInterface` off if it is on (it animates and fights writes), writes size, then
    /// position, then size again (the first size makes room for the move, the second applies once moved), reads
    /// position and size back, and turns enhanced UI back on if it was on and `reenableEnhancedUI` is set.
    /// Frames are top-left global points, as AX uses them. The first AX error stops the sequence and is returned;
    /// `actual` is the read-back, nil when it failed or the write was cancelled (both nil).
    static func write(
        _ rect: Rect, window: AXUIElement, app: AXUIElement, reenableEnhancedUI: Bool, isCancelled: () -> Bool
    ) -> (actual: Rect?, failure: AXFailure?) {
        let enhancedUI = "AXEnhancedUserInterface" as CFString
        var current: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhancedUI, &current) == .success && current as? Bool == true
        if wasEnhanced { _ = AXUIElementSetAttributeValue(app, enhancedUI, kCFBooleanFalse) }
        defer {
            if wasEnhanced && reenableEnhancedUI { _ = AXUIElementSetAttributeValue(app, enhancedUI, kCFBooleanTrue) }
        }

        var size = CGSize(width: rect.width, height: rect.height)
        var origin = CGPoint(x: rect.x, y: rect.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return (nil, .other(AXError.failure.rawValue))
        }
        for (attribute, value) in [(kAXSizeAttribute, sizeValue), (kAXPositionAttribute, originValue), (kAXSizeAttribute, sizeValue)] {
            if isCancelled() { return (nil, nil) }
            let error = AXUIElementSetAttributeValue(window, attribute as CFString, value)
            guard error == .success else { return (nil, AXFailure(code: error.rawValue)) }
        }
        if isCancelled() { return (nil, nil) }

        var position: CFTypeRef?
        var readSize: CFTypeRef?
        let positionError = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
        guard positionError == .success else { return (nil, AXFailure(code: positionError.rawValue)) }
        let sizeError = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &readSize)
        guard sizeError == .success else { return (nil, AXFailure(code: sizeError.rawValue)) }
        guard let position, let readSize, let point = AXSnapshotReader.point(position), let extent = AXSnapshotReader.size(readSize) else {
            return (nil, .other(AXError.failure.rawValue))
        }
        return (Rect(x: point.x, y: point.y, width: extent.width, height: extent.height), nil)
    }
}
