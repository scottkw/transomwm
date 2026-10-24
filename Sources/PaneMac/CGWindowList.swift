import CoreGraphics
import Foundation
import PaneEngine
import PaneModel
import os

/// The second window source: the public CG window list. No window names are read or logged (T-02-09).
public nonisolated enum CGWindowList {
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "ax")

    /// Every CG window (`optionAll`: on- and offscreen), bounds already in global top-left points.
    public static func snapshot() -> [CGWindowEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var skipped = 0
        let entries = list.compactMap { info -> CGWindowEntry? in
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else {
                skipped += 1
                return nil
            }
            return CGWindowEntry(
                windowID: number, pid: pid,
                bounds: Rect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height),
                layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                onScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            )
        }
        if skipped > 0 { logger.debug("CG window list: skipped \(skipped, privacy: .public) entries without number, pid or bounds") }
        return entries
    }
}
