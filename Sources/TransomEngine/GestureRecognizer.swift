import Foundation
import TransomModel

/// Every gesture threshold (D-01, D-03, E-02, UI-SPEC Surfaces 1-2). Feel only: tuned at UAT, never written elsewhere.
public enum GestureTuning {
    /// Pinch: nothing is reported while |ln s| is below this.
    public static let pinchDeadZone = 0.03
    /// Pinch commits at |p| ≥ this, or on a flick of |dp/dt| ≥ `pinchFlickRate` per second with |p| ≥ `pinchFlickMinimum`.
    public static let pinchCommit = 0.5
    public static let pinchFlickRate = 2.0
    public static let pinchFlickMinimum = 0.15
    /// Flick velocities are measured over this many seconds of samples.
    public static let flickWindow = 0.08
    /// Pan: the axis locks once |Σ| reaches this many points with the dominant axis this many times the other.
    public static let panAxisLock = 12.0
    public static let panAxisDominance = 1.5
    /// Pan commits at |d|/W ≥ this, or on a flick of ≥ `panFlickVelocity` pt/s toward the drag with |d| ≥ `panFlickMinimum`.
    public static let panCommit = 1.0 / 3
    public static let panFlickVelocity = 800.0
    public static let panFlickMinimum = 24.0
    /// Overscroll R(x, L) = L·(1 − 1/(x·c/L + 1)), the iOS scroll-view curve; L is a quarter level for a pinch, W for a pan.
    public static let overscrollCoefficient = 0.55
    public static let pinchOverscrollLimit = 0.25
    /// Fingers up short of the threshold: how long a pan waits for its first momentum sample, a velocity estimate.
    public static let momentumWait = 0.06
    /// A gesture ends with no event for this long after fingers-up, or while fingers are down.
    public static let fingersUpTimeout = 0.3
    public static let fingersDownTimeout = 2.0
    /// T-05-06: each sample's magnification is clamped to ±this, and s is floored before ln.
    public static let magnificationClamp = 1.0
    public static let scaleFloor = 0.05
}

/// One gesture's judgement (D-08): source-neutral samples (the event tap's, or multitouch's in 05-07) in, progress and a
/// snap decision out. It only names a direction; Phase 4's `cameraStep` picks the target (D-02), one level per gesture.
public struct GestureRecognizer: Sendable {
    public enum Kind: String, Codable, Sendable { case pinch, pan }

    /// One event in the spike's tap-listen keys. `phase` and `momentum` keep the raw CG encodings: phase 1 began,
    /// 2 changed, 4 ended, 8 cancelled, 128 mayBegin; momentum 0 none, 1 begin, 2 continue, 3 end. Deltas are as macOS
    /// delivers them (natural scrolling).
    public struct Sample: Codable, Equatable, Sendable {
        public var t: Double
        public var kind: Kind
        public var phase: Int
        public var momentum: Int
        public var magnification: Double
        public var dx: Double
        public var dy: Double

        enum CodingKeys: String, CodingKey {
            case t, kind, phase, momentum, magnification = "m", dx, dy
        }

        public init(t: Double, kind: Kind, phase: Int, momentum: Int = 0, magnification: Double = 0, dx: Double = 0, dy: Double = 0) {
            self.t = t
            self.kind = kind
            self.phase = phase
            self.momentum = momentum
            self.magnification = magnification
            self.dx = dx
            self.dy = dy
        }
    }

    /// Pinch in is fingers apart. A pan names the edge whose area it shows: fingers left show `.right`.
    public enum Direction: Equatable, Sendable { case pinchIn, pinchOut, pan(Edge) }

    public enum Update: Equatable, Sendable {
        case started(Direction), progress(Direction, Double), reversed(Direction), ended(Release)
    }

    public struct Release: Equatable, Sendable {
        /// Nil when the gesture never left the dead zone (pinch) or locked an axis (pan).
        public var direction: Direction?
        /// |p| at the end.
        public var progress: Double
        public var passedThreshold: Bool
        /// Passed by a flick, short of the distance threshold.
        public var byFlick: Bool
        public var endedByTimeout: Bool
        public var tooSmall: Bool
    }

    /// What the stage shows: every tile at lerp(start, end, t), then scaled about the pinch point by `overscrollScale`
    /// or moved along the pan's axis by `overscrollOffset` points.
    public struct FollowState: Equatable, Sendable {
        public var t: Double
        public var overscrollScale: Double
        public var overscrollOffset: Double
    }

    public let kind: Kind
    /// The display's visibleFrame size: a pan's W.
    public let viewSize: Size
    /// Ended: every later sample is ignored.
    public private(set) var isFinished = false
    private var sumM = 0.0, sumX = 0.0, sumY = 0.0
    private var axis: Axis?
    private var direction: Direction?
    /// Saw phase 1 or 2 (spike C2: a 128 → 8 sequence with no motion is noise, not a gesture).
    private var moved = false
    /// The signed value after each sample (p for a pinch, Σdx and Σdy for a pan), for flicks.
    private var history: [(t: Double, x: Double, y: Double)] = []
    private var lastT: Double?
    /// A pan's fingers lifted short of the threshold: the release waits for the first momentum sample.
    private var fingersUp = false

    public init(kind: Kind, viewSize: Size) {
        self.kind = kind
        self.viewSize = viewSize
    }

    public mutating func feed(_ raw: Sample) -> Update? {
        guard !isFinished, raw.kind == kind else { return nil }
        let sample = sanitized(raw)
        lastT = sample.t
        if sample.momentum != 0 { return fingersUp ? momentum(sample) : nil }
        switch sample.phase {
        case 1, 2: moved = true
        case 4: break
        case 8: return end(cancelled: true)
        default: return nil  // 128 mayBegin, or a momentum-only sample: no finger motion
        }
        sumM += sample.magnification
        sumX += sample.dx
        sumY += sample.dy
        if kind == .pan, axis == nil { lockAxis() }
        history.append(kind == .pinch ? (sample.t, signed, 0) : (sample.t, sumX, sumY))
        return sample.phase == 4 ? fingersLifted() : report()
    }

    /// Call while a gesture is open. A pan waiting for momentum decides after `momentumWait`. Polled that late, past
    /// `fingersUpTimeout`, its stream went quiet, so the release is flagged endedByTimeout. With fingers down,
    /// `fingersDownTimeout` of silence ends it as a cancel.
    public mutating func timeout(now: Double) -> Update? {
        guard !isFinished, let lastT else { return nil }
        let quiet = now - lastT
        if fingersUp { return quiet >= GestureTuning.momentumWait ? end(byTimeout: quiet >= GestureTuning.fingersUpTimeout) : nil }
        return quiet >= GestureTuning.fingersDownTimeout ? end(cancelled: true, byTimeout: true) : nil
    }

    /// UI-SPEC Surface 1: with a target t = min(|p|, 1) and overscroll past one level; with none t = 0 and overscroll
    /// from 0.
    public func follow(hasTarget: Bool) -> FollowState {
        let value = signed, sign: Double = value < 0 ? -1 : 1
        let level = kind == .pinch ? 1 : extent, limit = kind == .pinch ? GestureTuning.pinchOverscrollLimit : extent
        let over = sign * Self.overscroll(hasTarget ? max(abs(value) - level, 0) : abs(value), limit: limit)
        return FollowState(
            t: hasTarget ? min(progress, 1) : 0, overscrollScale: kind == .pinch ? pow(2, over) : 1, overscrollOffset: kind == .pan ? over : 0)
    }

    /// R(x, L): approaches L, never reaches it.
    public static func overscroll(_ x: Double, limit: Double) -> Double {
        limit * (1 - 1 / (x * GestureTuning.overscrollCoefficient / limit + 1))
    }

    /// p for a pinch (one level per doubling or halving of s = 1 + Σm); the locked-axis Σ in points for a pan.
    private var signed: Double {
        switch kind {
        case .pinch: log(max(1 + sumM, GestureTuning.scaleFloor)) / log(2)
        case .pan: axis.map { $0 == .horizontal ? sumX : sumY } ?? 0
        }
    }

    private var extent: Double { axis == .vertical ? viewSize.height : viewSize.width }

    /// |p|: levels for a pinch, the share of the view crossed for a pan.
    private var progress: Double { kind == .pinch ? abs(signed) : abs(signed) / extent }

    private func value(_ point: (t: Double, x: Double, y: Double)) -> Double { axis == .vertical ? point.y : point.x }

    private func direction(of value: Double) -> Direction {
        switch (kind, axis) {
        case (.pinch, _): value > 0 ? .pinchIn : .pinchOut
        case (.pan, .vertical?): .pan(value < 0 ? .bottom : .top)
        case (.pan, _): .pan(value < 0 ? .right : .left)
        }
    }

    private mutating func report() -> Update? {
        let value = signed
        guard let current = direction else {
            let begun = kind == .pinch ? abs(value) * log(2) >= GestureTuning.pinchDeadZone : axis != nil
            guard begun else { return nil }
            direction = direction(of: value)
            return direction.map { .started($0) }
        }
        let now = value == 0 ? current : direction(of: value)
        guard now == current else {
            direction = now
            return .reversed(now)
        }
        return .progress(now, progress)
    }

    /// The signed value's rate over the last `flickWindow` seconds of samples.
    private var windowVelocity: Double {
        guard let last = history.last else { return 0 }
        let ref = history.last { $0.t <= last.t - GestureTuning.flickWindow } ?? history[0]
        let dt = last.t - ref.t
        return dt > 0 ? (value(last) - value(ref)) / dt : 0
    }

    /// A flick toward the current direction, fast and far enough.
    private func flicks(_ velocity: Double) -> Bool {
        let value = signed
        guard velocity * value > 0 else { return false }
        return switch kind {
        case .pinch: abs(velocity) >= GestureTuning.pinchFlickRate && abs(value) >= GestureTuning.pinchFlickMinimum
        case .pan: abs(velocity) >= GestureTuning.panFlickVelocity && abs(value) >= GestureTuning.panFlickMinimum
        }
    }

    /// The pan axis locks once |Σ| reaches `panAxisLock` with one axis `panAxisDominance` times the other.
    private mutating func lockAxis() {
        let x = abs(sumX), y = abs(sumY)
        guard (x * x + y * y).squareRoot() >= GestureTuning.panAxisLock else { return }
        if x >= GestureTuning.panAxisDominance * y {
            axis = .horizontal
        } else if y >= GestureTuning.panAxisDominance * x {
            axis = .vertical
        }
    }

    private var byDistance: Bool { progress >= (kind == .pinch ? GestureTuning.pinchCommit : GestureTuning.panCommit) }

    /// Fingers up: a pan short of the threshold waits for its first momentum sample's velocity; anything else ends now.
    private mutating func fingersLifted() -> Update? {
        guard kind == .pan, direction != nil, !byDistance, !flicks(windowVelocity) else { return end() }
        fingersUp = true
        return nil
    }

    /// The first momentum sample decides: its delta on the locked axis over the time since the last finger sample.
    private mutating func momentum(_ sample: Sample) -> Update? {
        let dt = history.last.map { sample.t - $0.t } ?? 0
        let delta = axis == .vertical ? sample.dy : sample.dx
        return end(momentumVelocity: dt > 0 ? delta / dt : 0)
    }

    private mutating func end(cancelled: Bool = false, byTimeout: Bool = false, momentumVelocity: Double = 0) -> Update? {
        isFinished = true
        // C2: never started, no phase 1 or 2 or no motion at all: noise, so no gesture.
        guard direction != nil || (moved && (sumM != 0 || sumX != 0 || sumY != 0)) else { return nil }
        let passed = direction != nil && !cancelled && (byDistance || flicks(windowVelocity) || flicks(momentumVelocity))
        return .ended(
            Release(
                direction: direction, progress: progress, passedThreshold: passed, byFlick: passed && !byDistance, endedByTimeout: byTimeout,
                tooSmall: direction == nil))
    }

    /// T-05-06: NaN and ∞ become 0 (a bad time keeps the last one), magnification is clamped.
    private func sanitized(_ raw: Sample) -> Sample {
        func finite(_ v: Double) -> Double { v.isFinite ? v : 0 }
        var sample = raw
        sample.t = raw.t.isFinite ? raw.t : lastT ?? 0
        sample.magnification = min(max(finite(raw.magnification), -GestureTuning.magnificationClamp), GestureTuning.magnificationClamp)
        sample.dx = finite(raw.dx)
        sample.dy = finite(raw.dy)
        return sample
    }
}
