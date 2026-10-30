import TransomEngine
import TransomModel

/// Gesture Debug lines from the UI-SPEC (Surface 5, G1-G4). Pure strings, no AppKit types.
nonisolated public enum GestureCopy {
    // MARK: G1 Gestures

    public enum Source: Sendable { case on, onWithMultitouch, offZoom, offTapNotRunning, unavailable }

    public static func gesturesLine(_ source: Source) -> String {
        switch source {
        case .on: "Gestures: on, trackpad events"
        case .onWithMultitouch: "Gestures: on, trackpad events and multitouch"
        case .offZoom: "Gestures: off (zoom off)"
        case .offTapNotRunning: "Gestures: off (gesture tap not running)"
        case .unavailable: "Gestures: unavailable (no gesture source)"
        }
    }

    // MARK: G4 Multitouch

    /// The multitouch capability: available with this many trackpads, off (forced off or symbols missing), or off
    /// because the crash canary tripped.
    public enum Multitouch: Equatable, Sendable { case available(Int), off, offAfterCrash }

    public static func multitouchLine(_ state: Multitouch) -> String {
        switch state {
        case .available(0): "Multitouch: available, no trackpad found"
        case .available(1): "Multitouch: available, 1 trackpad"
        case .available(let n): "Multitouch: available, \(n) trackpads"
        case .off: "Multitouch: off, trackpad events only"
        case .offAfterCrash: "Multitouch: off after a crash last launch, trackpad events only"
        }
    }

    // MARK: G2 Gestures taken

    public static func takenLine(taken: Int, timeouts: Int) -> String {
        if taken == 0, timeouts == 0 { return "Gestures taken: none yet" }
        return timeouts > 0 ? "Gestures taken: \(taken), \(timeouts) ended by timeout" : "Gestures taken: \(taken)"
    }

    // MARK: G3 Last gesture

    /// How a gesture ended; a copy of GestureController's outcome so this type stays off the main actor.
    public enum Outcome: Equatable, Sendable { case moved, sprangBack, refused(Navigator.Refusal), tooSmall }

    public static let lastGestureNone = "Last gesture: none yet"

    /// `direction` is nil when the gesture never left the dead zone or locked an axis; its kind names it then.
    public static func lastGestureLine(kind: GestureRecognizer.Kind, direction: GestureRecognizer.Direction?, outcome: Outcome) -> String {
        let how =
            switch outcome {
            case .moved: "moved"
            case .sprangBack: "sprang back"
            case .refused(let refusal): refusalText(refusal)
            case .tooSmall: "too small"
            }
        return "Last gesture: \(direction.map(kindLabel) ?? kind.rawValue), \(how)"
    }

    /// The direction the view moved, matching Move View ▸ Left/Right/Up/Down.
    public static func kindLabel(_ direction: GestureRecognizer.Direction) -> String {
        switch direction {
        case .pinchIn: "pinch in"
        case .pinchOut: "pinch out"
        case .pan(.left): "pan left"
        case .pan(.right): "pan right"
        case .pan(.top): "pan up"
        case .pan(.bottom): "pan down"
        }
    }

    /// The Phase 4 refusal announcement, first letter lower-cased.
    public static func refusalText(_ refusal: Navigator.Refusal) -> String {
        let text = refusal.announcement
        return text.prefix(1).lowercased() + text.dropFirst()
    }
}
