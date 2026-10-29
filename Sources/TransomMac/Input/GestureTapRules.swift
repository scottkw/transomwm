import CoreGraphics
import Foundation
import TransomEngine
import TransomModel
import TransomPrivate

/// What the gesture tap needs to decide, published whole from main (like `ZoomTapState`). Rects are global top-left points.
public nonisolated struct GestureTapState: Equatable, Sendable {
    /// Why the tap is not armed, for the debug log only (UI-SPEC Logging).
    public enum DisarmReason: Equatable, Sendable { case zoomPaused, notReady, rectZoomOrDrag }

    /// Zoom on, Transom ready, not paused, no rubber band or drag in progress.
    public var armed: Bool
    public var disarmReason: DisarmReason?
    /// Frames of displays whose shown Space has a desk: only there is a gesture taken.
    public var deskDisplays: [CGRect]
    /// Frames of displays whose shown Space has no desk (a full-screen app).
    public var fullScreenDisplays: [CGRect]
    /// Finder's pid, whose target pid means "maybe the desktop" (0 = unknown).
    public var finderPID: Int32
    /// Registry IDs of the trackpads (field 87). Empty means not known, and the sender filter is off (E-04).
    public var trackpadSenders: Set<UInt64>

    public init(
        armed: Bool = false, disarmReason: DisarmReason? = nil, deskDisplays: [CGRect] = [], fullScreenDisplays: [CGRect] = [],
        finderPID: Int32 = 0, trackpadSenders: Set<UInt64> = []
    ) {
        self.armed = armed
        self.disarmReason = disarmReason
        self.deskDisplays = deskDisplays
        self.fullScreenDisplays = fullScreenDisplays
        self.finderPID = finderPID
        self.trackpadSenders = trackpadSenders
    }
}

/// One consumed event, handed to main. Phases are CG encodings only (Pitfall 3).
public nonisolated struct GestureSample: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case pinch, pan }
    /// Why the sequence was taken; set on its first sample only.
    public enum Reason: Equatable, Sendable { case optionHeld, wallpaper }

    public var kind: Kind
    /// Scroll phase for a pan, gesture phase for a pinch (1, 2, 4, 8, 128).
    public var phase: Int
    /// Momentum phase for a pan (0-3); 0 for a pinch.
    public var momentum: Int
    /// Clamped to ±1, NaN and infinity read as 0.
    public var magnification: Double
    public var dx: Double
    public var dy: Double
    public var location: CGPoint
    /// Seconds on the uptime clock.
    public var timestamp: Double
    public var flags: CGEventFlags
    public var senderID: UInt64
    public var reason: Reason?
}

/// What the pointer is over, for the no-⌥ wallpaper test (D-05).
public nonisolated enum PointerSurface: Equatable, Sendable { case window, wallpaper, overlay }

/// The gesture tap's consume rules (D-04, D-05, D-06, E-04, E-05; RESEARCH Pattern 2). Pure, like `ZoomTapRules`: a
/// sequence is decided once, at its first event, and that decision holds through momentum end. Every new start decides
/// afresh and a quiet latch expires, so a lost end can never swallow later scrolling (Pitfall 4).
public nonisolated enum GestureTapRules {
    /// Scroll (22) and kCGSEventGesture (29). Never 1 << 30: that is Dock control (Pitfall 1).
    public static let mask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue) | (1 << GestureEventFields.gestureType)

    /// After fingers-up (scroll Ended, momentum maybe to come), a sequence ends after this much quiet.
    public static let quietTimeout = 0.3
    /// With fingers down, a sequence ends after this long with no event (resting fingers mid-pan keep the latch).
    public static let fingersDownTimeout = 2.0

    /// Why a sequence passes. These match the UI-SPEC Logging reasons.
    public enum PassReason: Equatable, Sendable {
        case disarmed(GestureTapState.DisarmReason?)
        case fullScreen, notDeskDisplay
        /// ⌃ or ⌘ also held (E-05).
        case chord
        case notTrackpad
        /// The sequence's first event seen was not its start: the app already has the start.
        case midSequence
        case windowUnderPointer, overlayUnderPointer
        /// A target pid that is not Finder: passed with no CG read.
        case shortCircuit
    }

    public struct Sequence: Equatable, Sendable {
        public var kind: GestureSample.Kind
        public var consuming: Bool
        public var fingersUp = false
        /// Time of the sequence's first event (also its identity in logs).
        public var started: Double
        public var lastEvent: Double
        public var optionHeld: Bool
        public var passReason: PassReason?
        public var reason: GestureSample.Reason?
    }

    /// One slot per kind, so a scroll cancelled by a starting pinch never disturbs the pinch's latch.
    public struct Latch: Equatable, Sendable {
        public var pan: Sequence?
        public var pinch: Sequence?
        public static let none = Latch()
    }

    public enum Decision: Equatable, Sendable {
        case pass
        /// Take the event; nil for consumed events that carry no sample (rotate, container).
        case consume(GestureSample?)
    }

    /// The fields copied from one event in the tap callback.
    public struct Input: Equatable, Sendable {
        public var type: UInt32
        public var scrollPhase: Int64 = 0
        public var momentumPhase: Int64 = 0
        public var isContinuous = true
        public var dx: Double = 0
        public var dy: Double = 0
        public var hidType: Int64 = 0
        public var gesturePhase: Int64 = 0
        public var zoom: Double = 0
        public var targetPID: Int32 = 0
        public var senderID: UInt64 = 0
        public var flags: CGEventFlags = []
        public var location: CGPoint = .zero
        /// Seconds on the uptime clock, read when the callback ran.
        public var timestamp: Double = 0

        public init(
            type: UInt32, scrollPhase: Int64 = 0, momentumPhase: Int64 = 0, isContinuous: Bool = true, dx: Double = 0, dy: Double = 0,
            hidType: Int64 = 0, gesturePhase: Int64 = 0, zoom: Double = 0, targetPID: Int32 = 0, senderID: UInt64 = 0,
            flags: CGEventFlags = [], location: CGPoint = .zero, timestamp: Double = 0
        ) {
            self.type = type
            self.scrollPhase = scrollPhase
            self.momentumPhase = momentumPhase
            self.isContinuous = isContinuous
            self.dx = dx
            self.dy = dy
            self.hidType = hidType
            self.gesturePhase = gesturePhase
            self.zoom = zoom
            self.targetPID = targetPID
            self.senderID = senderID
            self.flags = flags
            self.location = location
            self.timestamp = timestamp
        }

        /// Field reads only: no allocation, no AX, no logging.
        public init(event: CGEvent, type: CGEventType) {
            self.type = type.rawValue
            if type == .scrollWheel {
                scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
                dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            } else if type.rawValue == GestureEventFields.gestureType {
                hidType = event.getIntegerValueField(GestureEventFields.hidType)
                gesturePhase = event.getIntegerValueField(GestureEventFields.phase)
                zoom = event.getDoubleValueField(GestureEventFields.zoomValue)
            }
            targetPID = Int32(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
            senderID = UInt64(bitPattern: event.getIntegerValueField(GestureEventFields.senderID))
            flags = event.flags
            location = event.location
            timestamp = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
        }
    }

    /// Whether the tap takes this event. `surface` is called at most once per sequence, only when neither ⌥ nor the
    /// target pid decides.
    public static func decide(
        _ input: Input, state: GestureTapState, latch: inout Latch, surface: (CGPoint) -> PointerSurface
    ) -> Decision {
        let now = input.timestamp
        if let pan = latch.pan, expired(pan, now: now) { latch.pan = nil }
        if let pinch = latch.pinch, expired(pinch, now: now) { latch.pinch = nil }

        if input.type == CGEventType.scrollWheel.rawValue {
            // Discrete wheels and unphased scrolls are never a trackpad gesture (E-04).
            guard input.isContinuous, input.scrollPhase != 0 || input.momentumPhase != 0 else { return .pass }
            let first = input.scrollPhase == 128 || input.scrollPhase == 1
            if first {
                latch.pan = start(.pan, input, state: state, surface: surface)
            } else if latch.pan == nil {
                latch.pan = Sequence(kind: .pan, consuming: false, started: now, lastEvent: now, optionHeld: false, passReason: .midSequence)
            }
            guard var sequence = latch.pan else { return .pass }
            sequence.lastEvent = now
            if input.scrollPhase == 4 { sequence.fingersUp = true }
            let ends = input.momentumPhase == 3 || input.scrollPhase == 8
            latch.pan = ends ? nil : sequence
            guard sequence.consuming else { return .pass }
            return .consume(sample(input, kind: .pan, reason: first ? sequence.reason : nil))
        }

        guard input.type == GestureEventFields.gestureType else { return .pass }
        let zoom = input.hidType == GestureEventFields.hidZoom
        let first = zoom && input.gesturePhase == 1
        if first {
            latch.pinch = start(.pinch, input, state: state, surface: surface)
        } else if latch.pinch == nil {
            // Rotate-only, smart zoom, envelopes and other sub-types outside a latch pass untouched.
            guard zoom else { return .pass }
            latch.pinch = Sequence(kind: .pinch, consuming: false, started: now, lastEvent: now, optionHeld: false, passReason: .midSequence)
        }
        guard var sequence = latch.pinch else { return .pass }
        sequence.lastEvent = now
        let ends = zoom && (input.gesturePhase == 4 || input.gesturePhase == 8)
        latch.pinch = ends ? nil : sequence
        // Envelopes 61/62 pass even inside a taken pinch (A4; spike gate T2 decides whether to flip this).
        let taken = zoom || input.hidType == GestureEventFields.hidRotate || input.hidType == 0
        guard sequence.consuming, taken else { return .pass }
        return .consume(zoom ? sample(input, kind: .pinch, reason: first ? sequence.reason : nil) : nil)
    }

    private static func expired(_ sequence: Sequence, now: Double) -> Bool {
        now - sequence.lastEvent > (sequence.fingersUp ? quietTimeout : fingersDownTimeout)
    }

    /// The decision at a sequence's first event (RESEARCH Pattern 2, steps 1-3).
    private static func start(
        _ kind: GestureSample.Kind, _ input: Input, state: GestureTapState, surface: (CGPoint) -> PointerSurface
    ) -> Sequence {
        let option = input.flags.contains(.maskAlternate)
        var sequence = Sequence(kind: kind, consuming: false, started: input.timestamp, lastEvent: input.timestamp, optionHeld: option)
        func passing(_ reason: PassReason) -> Sequence {
            sequence.passReason = reason
            return sequence
        }
        func taking(_ reason: GestureSample.Reason) -> Sequence {
            sequence.consuming = true
            sequence.reason = reason
            return sequence
        }
        let location = input.location
        guard state.armed else { return passing(.disarmed(state.disarmReason)) }
        if state.fullScreenDisplays.contains(where: { $0.contains(location) }) { return passing(.fullScreen) }
        guard state.deskDisplays.contains(where: { $0.contains(location) }) else { return passing(.notDeskDisplay) }
        if input.senderID != 0, !state.trackpadSenders.isEmpty, !state.trackpadSenders.contains(input.senderID) {
            return passing(.notTrackpad)
        }
        if !input.flags.intersection([.maskControl, .maskCommand]).isEmpty { return passing(.chord) }
        if option { return taking(.optionHeld) }
        if input.targetPID != 0 && input.targetPID != state.finderPID { return passing(.shortCircuit) }
        switch surface(location) {
        case .wallpaper: return taking(.wallpaper)
        case .window: return passing(.windowUnderPointer)
        case .overlay: return passing(.overlayUnderPointer)
        }
    }

    private static func sample(_ input: Input, kind: GestureSample.Kind, reason: GestureSample.Reason?) -> GestureSample {
        let magnification = input.zoom.isFinite ? min(max(input.zoom, -1), 1) : 0
        let pinch = kind == .pinch
        return GestureSample(
            kind: kind, phase: Int(pinch ? input.gesturePhase : input.scrollPhase), momentum: pinch ? 0 : Int(input.momentumPhase),
            magnification: magnification, dx: input.dx, dy: input.dy, location: input.location, timestamp: input.timestamp,
            flags: input.flags, senderID: input.senderID, reason: reason)
    }

    /// The front-to-back walk of `CGWindowList.topmost`, as a tri-state: our own pid and invisible entries are skipped,
    /// an overlay covering the whole `display` is looked through (the Dock's layer-20 window), a layer-0 hit is a
    /// window, anything else above it is an overlay (menu, popover), and no hit is wallpaper.
    public static func surface(at point: CGPoint, in list: [CGWindowEntry], excludingPID own: Int32, display: CGRect?) -> PointerSurface {
        let p = Point(x: point.x, y: point.y)
        for entry in list where entry.pid != own && entry.alpha > 0 && entry.bounds.contains(p) {
            if entry.layer == 0 { return .window }
            if let display, entry.bounds.minX <= display.minX, entry.bounds.minY <= display.minY,
                entry.bounds.maxX >= display.maxX, entry.bounds.maxY >= display.maxY
            {
                continue
            }
            return .overlay
        }
        return .wallpaper
    }

    /// One CG window list read. When the list can't be read the answer is `.overlay`, so the event passes.
    public static func liveSurface(at point: CGPoint) -> PointerSurface {
        guard let list = CGWindowList.onScreenFrontToBack() else { return .overlay }
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let display = CGGetDisplaysWithPoint(point, 1, &id, &count) == .success && count > 0 ? CGDisplayBounds(id) : nil
        return surface(at: point, in: list, excludingPID: getpid(), display: display)
    }
}
