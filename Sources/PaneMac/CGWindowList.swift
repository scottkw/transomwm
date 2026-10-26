import CoreGraphics
import Foundation
import PaneEngine
import PaneModel
import os

/// The second window source: the public CG window list. Window names are read only by `names(pid:)`, never logged (T-02-09).
public nonisolated enum CGWindowList {
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "ax")

    /// Every CG window (`optionAll`: on- and offscreen), bounds already in global top-left points. nil (logged) when
    /// the list could not be read: that is not "no windows", so callers must decide nothing from it.
    public static func snapshot() -> [CGWindowEntry]? { read([.optionAll]) }

    /// The on-screen windows only, front to back (the order `optionAll` does not promise): for "topmost under a point".
    public static func onScreenFrontToBack() -> [CGWindowEntry]? { read([.optionOnScreenOnly, .excludeDesktopElements]) }

    private static func read(_ options: CGWindowListOption) -> [CGWindowEntry]? {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            logger.error("CG window list unavailable; skipping decisions that need it")
            return nil
        }
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

    /// `kCGWindowName` of `pid`'s windows, non-empty only with Screen Recording. Only for an ambiguous frame-fallback
    /// match: compared in memory and dropped, never logged or stored (T-02-31).
    static func names(pid: Int32) -> [UInt32: String] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var names: [UInt32: String] = [:]
        for info in list where (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let name = info[kCGWindowName as String] as? String, !name.isEmpty
            else { continue }
            names[number] = name
        }
        return names
    }
}
