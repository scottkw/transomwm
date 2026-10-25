import PaneModel

/// RED stub (02-12): learns nothing yet.
public struct MinimumSizeLearner: Equatable, Sendable {
    public static let tolerance: Double = 2

    public init() {}

    public mutating func learn(window: WindowIdentity, requested: Rect, actual: Rect) -> Size? { nil }

    public func minimum(for window: WindowIdentity) -> Size? { nil }

    public mutating func forget(_ window: WindowIdentity) {}
}
