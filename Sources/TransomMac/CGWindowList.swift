import CoreGraphics
import Foundation
import TransomEngine
import TransomModel
import os

/// The second window source: the public CG window list. Window names are read only by `names(pid:)`, never logged (T-02-09).
public nonisolated enum CGWindowList {
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "ax")

    /// Every CG window (`optionAll`: on- and offscreen), bounds already in global top-left points. nil (logged) when
    /// the list could not be read: that is not "no windows", so callers must decide nothing from it.
    public static func snapshot() -> [CGWindowEntry]? { read([.optionAll]) }

    /// The on-screen windows only, front to back (the order `optionAll` does not promise): for "topmost under a point".
    public static func onScreenFrontToBack() -> [CGWindowEntry]? { read([.optionOnScreenOnly, .excludeDesktopElements]) }

    /// The topmost visible layer-0 window of another process under `point`: the tap's fallback when an event carries no
    /// window (0 at the session tap, 03-11), so a green button under another window is never taken.
    static func topmostWindow(at point: Point) -> UInt32? {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let display = CGGetDisplaysWithPoint(CGPoint(x: point.x, y: point.y), 1, &id, &count) == .success && count > 0
            ? CGDisplayBounds(id) : nil
        let bounds = display.map { Rect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
        return onScreenFrontToBack().flatMap { topmost(at: point, in: $0, excludingPID: getpid(), display: bounds) }
    }

    /// The first entry of the front-to-back `list` of a pid other than `own`, visible and containing `point`, if it is
    /// at layer 0; nil when a window above layer 0 owns the point first (a menu, Dock tile, popover or banner, CR-01).
    /// Only an overlay covering the whole `display` under the point is looked through: the Dock's full-screen layer-20
    /// window on macOS 15 (G-03-4).
    static func topmost(at point: Point, in list: [CGWindowEntry], excludingPID own: Int32, display: Rect?) -> UInt32? {
        for entry in list where entry.pid != own && entry.alpha > 0 && entry.bounds.contains(point) {
            if entry.layer == 0 { return entry.windowID }
            if let display, entry.bounds.minX <= display.minX, entry.bounds.minY <= display.minY,
               entry.bounds.maxX >= display.maxX, entry.bounds.maxY >= display.maxY { continue }
            return nil
        }
        return nil
    }

    /// The tracked windows of the front-to-back `list`, layer 0 only, in list order, each once (8.1.1 D-18).
    static func frontToBack(_ list: [CGWindowEntry], tracked: (UInt32) -> WindowIdentity?) -> [WindowIdentity] {
        var seen = Set<WindowIdentity>()
        return list.compactMap { $0.layer == 0 ? tracked($0.windowID) : nil }.filter { seen.insert($0).inserted }
    }

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
