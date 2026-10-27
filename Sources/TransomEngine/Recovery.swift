import TransomModel

/// How this launch treats the layout the last session left (D-17, D-18).
public enum LaunchMode: Equatable, Sendable {
    case normal, recovery
    /// A second unclean exit within about a minute of a recovery launch: start paused (D-18).
    case crashLoop
    /// layout.json was rejected or is from a newer Transom, so the last session's record is unknown: stranded windows are
    /// rescued as after a crash, with no layout to restore and no notice (WR-05). Counts as a recovery launch.
    case unreadable
}

/// The crash-recovery rules (SAFE-02, SAFE-03, D-17, D-18, RESEARCH Pattern 10, thresholds A6). Pure, in CloseRule's
/// style.
///
/// | Previous session record                          | Launch    |
/// |--------------------------------------------------|-----------|
/// | none, or cleanExit                               | normal    |
/// | unclean, a recovery launch that survived 60 s    | recovery  |
/// | unclean, a recovery launch that did not          | crashLoop |
/// | unclean, a normal launch                         | recovery  |
/// | unreadable (layout.json rejected or newer)       | unreadable|
public enum Recovery {
    public static let minVisibleFraction = 0.5
    public static let minVisibleSize = Size(width: 40, height: 40)
    public static let crashLoopWindow: Duration = .seconds(60)

    /// Less than half of `frame`'s area inside the union of the displays' visible frames, or a visible part narrower or
    /// shorter than 40 pt (capped at the window's own size). The visible part is the bounding box of the pieces on each
    /// display. A frame with no area is never stranded.
    public static func isStranded(_ frame: Rect, displays: [DisplayInfo]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        // Visible frames of different displays never overlap, so the pieces' areas add up.
        let pieces = displays.compactMap { display -> Rect? in
            let d = display.visibleFrame
            let minX = max(frame.minX, d.minX), maxX = min(frame.maxX, d.maxX)
            let minY = max(frame.minY, d.minY), maxY = min(frame.maxY, d.maxY)
            return minX < maxX && minY < maxY ? Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) : nil
        }
        let area = pieces.reduce(0) { $0 + $1.width * $1.height }
        guard area >= minVisibleFraction * frame.width * frame.height else { return true }
        let width = (pieces.map(\.maxX).max() ?? 0) - (pieces.map(\.minX).min() ?? 0)
        let height = (pieces.map(\.maxY).max() ?? 0) - (pieces.map(\.minY).min() ?? 0)
        return width < min(minVisibleSize.width, frame.width) || height < min(minVisibleSize.height, frame.height)
    }

    /// The home frame clamped fully inside the display's visible frame; without one, the same size centred on it, shrunk
    /// to fit.
    public static func destination(for frame: Rect, home: Rect?, display: DisplayInfo) -> Rect {
        let area = display.visibleFrame
        if let home { return Planner.clamp(home, into: area) }
        let width = min(frame.width, area.width), height = min(frame.height, area.height)
        return Rect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    /// When a recovery or crash-loop launch records that it survived its first minute; a normal launch never does.
    public static func survivedMinuteDue(launchedAt: ContinuousClock.Instant, mode: LaunchMode) -> ContinuousClock.Instant? {
        mode == .normal ? nil : launchedAt + crashLoopWindow
    }

    /// Where each window Transom may move goes when Transom quits (SAFE-01, D-15): a parked floating window (one with a home
    /// frame) to that frame clamped onto the display it is on, and any other stranded window to its `destination` on its
    /// own display. Docked windows on screen, excluded and never-dock windows, and windows not present are left out.
    public static func terminationPlan(
        windows: [WindowInfo], homeFrames: [WindowIdentity: Rect], displays: [DisplayInfo], docked: Set<WindowIdentity>
    ) -> [WindowRef: Rect] {
        var plan: [WindowRef: Rect] = [:]
        for info in windows where info.kind == .dockable && !info.isExcluded && info.state == .present {
            let id = info.window.identity
            let home = docked.contains(id) ? nil : homeFrames[id]
            // A park corner can show on a neighbouring display, so a home frame alone marks a parked window.
            guard home != nil || isStranded(info.frame, displays: displays) else { continue }
            let homeDisplay = home.flatMap { home in displays.first { $0.visibleFrame.contains(Point(x: home.midX, y: home.midY)) } }
            guard let display = homeDisplay ?? displays.first(where: { $0.uuid == info.displayUUID }) ?? displays.first else { continue }
            plan[info.window] = destination(for: info.frame, home: home, display: display)
        }
        return plan
    }

    public static func launchMode(previous: SessionRecord?, unreadable: Bool = false) -> LaunchMode {
        if unreadable { return .unreadable }
        guard let previous, !previous.cleanExit else { return .normal }
        return previous.recoveryLaunch && !previous.survivedMinute ? .crashLoop : .recovery
    }
}
