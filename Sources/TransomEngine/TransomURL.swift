import Foundation

/// The `transom://` URL scheme of Phase 3 (SAFE-03, TILE-17, Pitfall 21, T-03-40): two parameterless commands, plus the 11 camera commands of Phase 4,
/// Show Overview (Phase 6), the three tab commands (Phase 7), `view/{n}` and `save-view/{n}` (Phase 8, D-06), the ten fourths (Phase 8.1, D-17)
/// the ten halves and thirds (Phase 8.1.1, D-10) and the four corner quarters (Phase 8.1.1, D-17): 40 parameterless commands in all.
/// Anything from any app or web page can open one, so the parser is a strict whitelist and nothing from the URL but the
/// chosen command goes anywhere.
public enum TransomURL {
    static let commands: [String: Command] = [
        "restore": .restoreAll, "split-finder": .finderSplit,
        // Phase 4: every camera command (04 UI-SPEC Hotkeys and URLs).
        "zoom-out": .camera(.zoomOutAll), "step-out": .camera(.stepOut), "step-in": .camera(.stepIn), "back": .camera(.back),
        "forward": .camera(.forward), "pan-left": .camera(.pan(.left)), "pan-right": .camera(.pan(.right)),
        "pan-up": .camera(.pan(.top)), "pan-down": .camera(.pan(.bottom)), "frame-window": .camera(.frameWindow),
        // Phase 6: toggles the overview, like its hotkey (06 UI-SPEC Surface 4).
        "overview": .camera(.overview),
        // Phase 7: the tab commands (07 UI-SPEC Surface 7).
        "next-tab": .tabs(.next), "previous-tab": .tabs(.previous), "move-out-of-group": .tabs(.moveOut),
        // Phase 8.1: the ten fourths (08.1 UI-SPEC Surface 5).
        "dock-column-1": .dockFourth(.first, .horizontal), "dock-column-2": .dockFourth(.second, .horizontal),
        "dock-column-3": .dockFourth(.third, .horizontal), "dock-column-4": .dockFourth(.fourth, .horizontal),
        "dock-column-middle": .dockFourth(.middle, .horizontal),
        "dock-row-1": .dockFourth(.first, .vertical), "dock-row-2": .dockFourth(.second, .vertical),
        "dock-row-3": .dockFourth(.third, .vertical), "dock-row-4": .dockFourth(.fourth, .vertical),
        "dock-row-middle": .dockFourth(.middle, .vertical),
        // Phase 8.1.1: halves and thirds (08.1.1 UI-SPEC Surface 4).
        "dock-left-half": .dockFourth(.firstHalf, .horizontal), "dock-right-half": .dockFourth(.secondHalf, .horizontal),
        "dock-top-half": .dockFourth(.firstHalf, .vertical), "dock-bottom-half": .dockFourth(.secondHalf, .vertical),
        "dock-left-third": .dockFourth(.firstThird, .horizontal), "dock-center-third": .dockFourth(.middleThird, .horizontal),
        "dock-right-third": .dockFourth(.lastThird, .horizontal),
        "dock-top-third": .dockFourth(.firstThird, .vertical), "dock-middle-third": .dockFourth(.middleThird, .vertical),
        "dock-bottom-third": .dockFourth(.lastThird, .vertical),
        // Phase 8.1.1: corner quarters (D-17).
        "dock-top-left": .dockCorner(.topLeft), "dock-top-right": .dockCorner(.topRight),
        "dock-bottom-left": .dockCorner(.bottomLeft), "dock-bottom-right": .dockCorner(.bottomRight),
    ]

    /// One line of `transom help` per command, in help order; `help` itself has no URL.
    static let helpLines: [(section: String, command: String, argument: String, description: String)] = [
        ("Views", "view", "<1-9>", "Go to a saved view"),
        ("Views", "save-view", "<1-9>", "Save the current view to a slot"),
        ("Zoom", "zoom-out", "", "Zoom out to all windows"),
        ("Zoom", "step-out", "", "Zoom out one level"),
        ("Zoom", "step-in", "", "Zoom in one level"),
        ("Zoom", "back", "", "Go to the previous view"),
        ("Zoom", "forward", "", "Go to the next view"),
        ("Zoom", "pan-left", "", "Move the view left"),
        ("Zoom", "pan-right", "", "Move the view right"),
        ("Zoom", "pan-up", "", "Move the view up"),
        ("Zoom", "pan-down", "", "Move the view down"),
        ("Zoom", "frame-window", "", "Frame the focused window, or go back"),
        ("Zoom", "overview", "", "Open or close the overview"),
        ("Arrange", "split-finder", "", "Split with a new Finder window"),
        ("Arrange", "restore", "", "Restore all windows"),
        ("Dock", "dock-left-half", "", "Dock the focused window to the left half"),
        ("Dock", "dock-right-half", "", "Dock the focused window to the right half"),
        ("Dock", "dock-top-half", "", "Dock the focused window to the top half"),
        ("Dock", "dock-bottom-half", "", "Dock the focused window to the bottom half"),
        ("Dock", "dock-left-third", "", "Dock the focused window to the left third"),
        ("Dock", "dock-center-third", "", "Dock the focused window to the center third"),
        ("Dock", "dock-right-third", "", "Dock the focused window to the right third"),
        ("Dock", "dock-top-third", "", "Dock the focused window to the top third"),
        ("Dock", "dock-middle-third", "", "Dock the focused window to the middle third"),
        ("Dock", "dock-bottom-third", "", "Dock the focused window to the bottom third"),
        ("Dock", "dock-column-1", "", "Dock the focused window as the 1st of 4 columns"),
        ("Dock", "dock-column-2", "", "Dock the focused window as the 2nd of 4 columns"),
        ("Dock", "dock-column-3", "", "Dock the focused window as the 3rd of 4 columns"),
        ("Dock", "dock-column-4", "", "Dock the focused window as the 4th of 4 columns"),
        ("Dock", "dock-column-middle", "", "Dock the focused window as the middle half column"),
        ("Dock", "dock-row-1", "", "Dock the focused window as the 1st of 4 rows"),
        ("Dock", "dock-row-2", "", "Dock the focused window as the 2nd of 4 rows"),
        ("Dock", "dock-row-3", "", "Dock the focused window as the 3rd of 4 rows"),
        ("Dock", "dock-row-4", "", "Dock the focused window as the 4th of 4 rows"),
        ("Dock", "dock-row-middle", "", "Dock the focused window as the middle half row"),
        ("Tabs", "next-tab", "", "Select the next tab in the focused tab group"),
        ("Tabs", "previous-tab", "", "Select the previous tab"),
        ("Tabs", "move-out-of-group", "", "Move the focused tab out of its group"),
        ("Other", "help", "", "Show this list"),
    ]

    /// The command for `url`: exactly `scheme`, a lowercase command host, no user, password, port, query or fragment, and
    /// a path that is empty or "/", or for `view` and `save-view` only, "/" and one digit 1-9. Nil for anything else.
    public static func parse(_ url: URL, scheme: String) -> Command? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
            parts.percentEncodedUser == nil, parts.percentEncodedPassword == nil, parts.port == nil,
            parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil, let host = parts.percentEncodedHost
        else { return nil }
        let path = parts.percentEncodedPath
        if path.isEmpty || path == "/" { return commands[host] }
        guard path.hasPrefix("/"), let slot = slot(digit: String(path.dropFirst())) else { return nil }
        return switch host {
        case "view": .camera(.view(slot))
        case "save-view": .camera(.saveView(slot))
        default: nil
        }
    }

    /// The slot for exactly one byte "1"..."9". Bytes, so that a percent-encoded digit or a non-ASCII one fails.
    static func slot(digit: String) -> ViewSlot? {
        let bytes = Array(digit.utf8)
        guard bytes.count == 1, let byte = bytes.first, (0x31...0x39).contains(byte) else { return nil }
        return ViewSlot(Int(byte) - 0x30)
    }

    /// The first `CFBundleURLSchemes` entry of `bundle`'s Info.plist: `transom`, or `transom-debug` in Debug (A8); nil outside the app bundle.
    public static func registeredScheme(in bundle: Bundle) -> String? {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first
    }
}

/// Each URL command runs at most once per second; a refused attempt does not restart the second.
public struct TransomURLRateLimiter: Sendable {
    public static let interval: Duration = .seconds(1)
    private var lastAdmitted: [Command: ContinuousClock.Instant] = [:]
    private var lastDockURL: ContinuousClock.Instant?

    public init() {}

    public mutating func admit(_ command: Command, at now: ContinuousClock.Instant) -> Bool {
        if let last = lastAdmitted[command], now - last < Self.interval { return false }
        lastAdmitted[command] = now
        return true
    }

    /// `admit` for an opened URL. Any app or web page can open one, and with one second each the twenty dock commands would allow
    /// twenty layout edits a second, emptying the undo history in under three, so they share one second here. The CLI stays on `admit`,
    /// so a script can dock several windows quickly.
    public mutating func admitOpenedURL(_ command: Command, at now: ContinuousClock.Instant) -> Bool {
        guard case .dockFourth = command else { return admit(command, at: now) }
        if let lastDockURL, now - lastDockURL < Self.interval { return false }
        guard admit(command, at: now) else { return false }
        lastDockURL = now
        return true
    }
}
