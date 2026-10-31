import TransomEngine
import TransomModel

/// Status-menu copy from the UI-SPEC Copywriting Contract. Pure strings, no AppKit types.
nonisolated public enum MenuCopy {
    public static let maxAppNameLength = 32

    /// "No windows to track", "Tracking 1 window in 1 app", "Tracking 12 windows in 5 apps".
    public static func header(windows: Int, apps: Int) -> String {
        if windows == 0 { return "No windows to track" }
        return "Tracking \(count(windows, "window")) in \(count(apps, "app"))"
    }

    /// Item 1 while ready (02-UI-REVIEW fix 1): no count before the first sweep, and closed windows never count.
    public static func header(_ inventory: WindowInventory) -> String {
        guard inventory.initialRefreshComplete else { return lookingForWindows }
        let open = inventory.windows.filter { $0.state != .closed }
        return header(windows: open.count, apps: Set(open.map(\.window.pid)).count)
    }

    public static let lookingForWindows = "Looking for windows\u{2026}"

    /// Section headers (UI-SPEC Surface 1, D-28).
    public static let arrangeSection = "Arrange"
    public static let safetySection = "Safety"
    public static let exclusionsSection = "Exclusions"

    /// A command item's title. Toggles have their own functions (`desktopToggle`).
    public static func commandTitle(_ command: Command) -> String {
        switch command {
        case .dock: "Dock Window"
        case .float: "Float Window"
        case .undo: "Undo Layout Change"
        case .toggleDesktop: desktopToggle(hidden: false)
        case .focus(let edge), .moveOrSnap(let edge): direction(edge)
        case .swapPrevious: "Swap with Previous Window"
        case .growTile: "Grow Tile"
        case .shrinkTile: "Shrink Tile"
        case .balanceSplit: "Balance Split"
        case .rotateSplit: "Rotate Layout"
        case .flipSplit: "Flip Split"
        case .snap(let target): snapTitle(target)
        case .arrangeAll: "Arrange All Windows"
        case .floatAll: "Float All Windows"
        case .finderSplit: "Split with New Finder Window"
        case .togglePause: pauseToggle(paused: false)
        case .toggleExcludeFrontmost: dontArrangeFallback
        case .restoreAll: "Restore All Windows"
        case .camera(let command): cameraTitle(command)
        }
    }

    /// A Zoom section item (UI-SPEC menu copy).
    public static func cameraTitle(_ command: CameraCommand) -> String {
        switch command {
        case .zoomOutAll: "Zoom Out to All Windows"
        case .stepOut: "Zoom Out One Level"
        case .stepIn: "Zoom In One Level"
        case .back: "Back"
        case .forward: "Forward"
        case .pan(let edge): direction(edge)  // the Move View submenu's items
        case .frameWindow: "Frame Focused Window"
        case .frameDesktop: "Frame Desktop"
        }
    }

    public static let moveMenu = "Move Window"
    public static let snapMenu = "Snap Floating Window"

    /// A Focus or Move Window item.
    public static func direction(_ edge: Edge) -> String {
        switch edge {
        case .left: "Left"
        case .right: "Right"
        case .top: "Up"
        case .bottom: "Down"
        }
    }

    /// A Snap Floating Window item.
    public static func snapTitle(_ target: SnapTarget) -> String {
        switch target {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }

    public static func pauseToggle(paused: Bool) -> String { paused ? "Resume Arranging" : "Pause Arranging" }

    /// Item 2, only while paused: the highest-priority reason (UI-SPEC Pause states).
    public static func pauseLine(_ reasons: Set<PauseReason>) -> String? {
        switch reasons.min() {
        case nil: nil
        case .stageManager: "Arranging paused: Stage Manager is on"
        case .crashLoop: "Arranging paused after Transom quit unexpectedly"
        case .user: "Arranging paused"
        }
    }

    public static let pausedGlyphDescription = "Transom: arranging paused"

    public static let gapsMenu = "Gaps"
    public static func gapTitle(_ gap: Double) -> String { gap == 0 ? "None" : "\(Int(gap)) pt" }

    public static func desktopToggle(hidden: Bool) -> String { hidden ? "Show Desktop Tile" : "Hide Desktop Tile" }

    /// nil at 0, else "1 app not responding" / "N apps not responding".
    public static func degradedLine(count apps: Int) -> String? {
        apps == 0 ? nil : "\(count(apps, "app")) not responding"
    }

    public static func capabilityItem(windowIDLookupAvailable: Bool) -> String {
        windowIDLookupAvailable ? "Window ID lookup: available" : "Window ID lookup: off, matching by frame"
    }

    /// The Debug submenu's event-tap line (UI-SPEC Copywriting Contract).
    public static let tapRunning = "Event tap: running"
    public static let tapOff = "Event tap: off, drags not detected"
    public static func tapItem(running: Bool) -> String { running ? tapRunning : tapOff }

    public static func spacesItem(available: Bool) -> String {
        available ? "Spaces lookup: available" : "Spaces lookup: off, using Spaces visited since launch"
    }

    /// Names over 32 graphemes become their first 32 plus "…", so menu width stays bounded.
    public static func truncatedAppName(_ name: String) -> String {
        name.count <= maxAppNameLength ? name : name.prefix(maxAppNameLength) + "\u{2026}"
    }

    /// Item 1 of the menu while not ready; nil when ready (the tracking header shows instead).
    public static func permissionHeader(_ phase: PermissionPhase) -> String? {
        switch phase {
        case .ready: nil
        case .notTrusted, .waitingForGrant: "Accessibility access needed"
        case .probing: "Checking Accessibility access\u{2026}"
        // A reset only starts from a stale form.
        case .staleTrustedButFailing, .resetting: "Accessibility access isn't working"
        }
    }

    public static func permissionItem(stale: Bool) -> String {
        stale ? "Fix Accessibility Access\u{2026}" : "Grant Accessibility Access\u{2026}"
    }

    /// Callout E body (UI-SPEC error state).
    public static func resetFailedBody(code: Int32, appName: String) -> String {
        "tccutil stopped with code \(code). In System Settings \u{25B8} Privacy & Security \u{25B8} Accessibility, "
            + "select \u{201C}\(appName)\u{201D}, click the minus button, then turn \(appName) on again."
    }

    /// Pass the name through `truncatedAppName` first.
    public static func dontArrange(appName: String) -> String { "Don't Arrange \u{201C}\(appName)\u{201D}" }
    public static let dontArrangeFallback = "Don't Arrange Frontmost App"
    public static let noExclusions = "No apps excluded"

    /// Nudge copy (Debug submenu, all builds).
    public static let nudgeItem = "Nudge Focused Window"
    public static let nudgeExcluded = "Nudge Focused Window (app excluded)"
    public static let nudgeNoWindow = "Nudge Focused Window (no window)"

    /// Freeze-test copy (Debug submenu, Surface 4). Pass names through `truncatedAppName` first.
    public static func freezeItem(appName: String) -> String { "Freeze \u{201C}\(appName)\u{201D} for 10 Seconds\u{2026}" }
    public static let freezeNotAllowed = "Freeze Frontmost App (not allowed)"
    public static func resumeItem(appName: String) -> String { "Resume \u{201C}\(appName)\u{201D} Now" }
    public static func freezeAlertMessage(appName: String) -> String { "Freeze \u{201C}\(appName)\u{201D} for 10 seconds?" }
    public static func freezeAlertInfo(appName: String) -> String {
        "Transom will pause \(appName) to check that a frozen app can't stall it. \(appName) resumes by itself after "
            + "10 seconds, or choose Debug \u{25B8} Resume \u{201C}\(appName)\u{201D} Now."
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}
