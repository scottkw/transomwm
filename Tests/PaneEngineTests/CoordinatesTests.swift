import Testing
import PaneEngine
import PaneModel

private let primaryHeight: Double = 1112

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Rect {
    Rect(x: x, y: y, width: w, height: h)
}

private func display(_ uuid: String, _ frame: Rect) -> DisplayInfo {
    DisplayInfo(uuid: uuid, frame: frame, visibleFrame: frame, currentSpaceID: nil)
}

@Suite struct CoordinatesTests {
    /// (AppKit rect, expected top-left rect) with a 1710×1112 primary display at the origin.
    static let vectors: [(appKit: Rect, topLeft: Rect)] = [
        (rect(0, 0, 1710, 1112), rect(0, 0, 1710, 1112)),          // primary
        (rect(0, 1112, 1920, 1080), rect(0, -1080, 1920, 1080)),   // external above
        (rect(-1920, 0, 1920, 1080), rect(-1920, 32, 1920, 1080)), // external left
        (rect(0, -1080, 1920, 1080), rect(0, 1112, 1920, 1080)),   // external below
        (rect(0, 0, 1710, 1074), rect(0, 38, 1710, 1074)),         // visibleFrame under a 38 pt menu bar
    ]

    @Test(arguments: vectors.indices)
    func appKitRectsConvertToTopLeft(_ i: Int) {
        let (appKit, topLeft) = Self.vectors[i]
        #expect(Coordinates.topLeft(fromAppKit: appKit, primaryHeight: primaryHeight) == topLeft)
    }

    @Test(arguments: vectors.map(\.appKit) + [rect(0.5, 10.5, 100.5, 50.5)])
    func conversionRoundTripsExactly(_ r: Rect) {
        let there = Coordinates.topLeft(fromAppKit: r, primaryHeight: primaryHeight)
        #expect(Coordinates.appKit(fromTopLeft: there, primaryHeight: primaryHeight) == r)
    }

    private let a = display("A", rect(0, 0, 1000, 1000))
    private let b = display("B", rect(1000, 0, 2000, 1000))

    @Test func aFrameMostlyOnBIsOnB() {
        #expect(Coordinates.displayUUID(for: rect(900, 100, 400, 300), among: [a, b]) == "B")
    }

    @Test func aFrameStraddlingEquallyGoesToTheNearerCentre() {
        // 100×100 on each side; A's centre (500, 500) is nearer than B's (2000, 500).
        #expect(Coordinates.displayUUID(for: rect(900, 0, 200, 100), among: [b, a]) == "A")
    }

    @Test func aFrameOnNoDisplayGoesToTheNearestCentre() {
        #expect(Coordinates.displayUUID(for: rect(3500, 400, 100, 100), among: [a, b]) == "B")
        #expect(Coordinates.displayUUID(for: rect(-800, 2000, 100, 100), among: [b, a]) == "A")
    }

    @Test func equalDistancesResolveToTheSmallerUUID() {
        let left = display("ZZZ", rect(0, 0, 1000, 1000))
        let right = display("AAA", rect(1000, 0, 1000, 1000))
        // Below both, centred on the shared edge.
        #expect(Coordinates.displayUUID(for: rect(950, 2000, 100, 100), among: [left, right]) == "AAA")
        #expect(Coordinates.displayUUID(for: rect(950, 2000, 100, 100), among: [right, left]) == "AAA")
    }

    @Test func noDisplaysGivesNil() {
        #expect(Coordinates.displayUUID(for: rect(0, 0, 100, 100), among: []) == nil)
    }
}
