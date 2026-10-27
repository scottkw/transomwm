import Foundation
import Testing
@testable import TransomModel

private let desktop = Rect(x: 100, y: 50, width: 1200, height: 900)
private let window = Rect(x: 0, y: 0, width: 400, height: 300)

private func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Rect { Rect(x: x, y: y, width: w, height: h) }

/// Expected frames for `desktop` with gap 8: inset (108, 58, 1184, 884).
private let expected: [SnapTarget: Rect] = [
    .leftHalf: r(108, 58, 588, 884), .rightHalf: r(704, 58, 588, 884),
    .topHalf: r(108, 58, 1184, 438), .bottomHalf: r(108, 504, 1184, 438),
    .leftThird: r(108, 58, 389, 884), .centerThird: r(505, 58, 389, 884), .rightThird: r(902, 58, 390, 884),
    .topLeft: r(108, 58, 588, 438), .topRight: r(704, 58, 588, 438),
    .bottomLeft: r(108, 504, 588, 438), .bottomRight: r(704, 504, 588, 438),
    .maximize: r(108, 58, 1184, 884), .center: r(500, 350, 400, 300),
]

private func inside(_ inner: Rect, _ outer: Rect) -> Bool {
    inner.minX >= outer.minX && inner.minY >= outer.minY && inner.maxX <= outer.maxX && inner.maxY <= outer.maxY
}

@Suite struct SnapTests {
    @Test(arguments: SnapTarget.allCases) func everyTargetWithGap8(_ target: SnapTarget) throws {
        let frame = Snap.frame(target, window: window, desktop: desktop, gap: 8)
        #expect(frame == expected[target], "\(target)")
        #expect(frame.isValidGeometry)
        #expect(inside(frame, desktop))
    }

    @Test(arguments: SnapTarget.allCases) func everyTargetFitsWithAnyGap(_ target: SnapTarget) {
        for gap in [0.0, 3.5, 20] {
            let frame = Snap.frame(target, window: Rect(x: 0, y: 0, width: 5000, height: 5000), desktop: desktop, gap: gap)
            #expect(frame.isValidGeometry && inside(frame, desktop), "\(target) gap \(gap): \(frame)")
        }
    }

    @Test func gapZeroHalvesMeetExactly() {
        let left = Snap.frame(.leftHalf, window: window, desktop: desktop, gap: 0)
        let right = Snap.frame(.rightHalf, window: window, desktop: desktop, gap: 0)
        #expect(left == r(100, 50, 600, 900))
        #expect(left.maxX == right.minX && right.maxX == desktop.maxX)
    }

    @Test func centerClampsAnOversizedWindow() {
        let wide = Snap.frame(.center, window: r(0, 0, 2000, 300), desktop: desktop, gap: 8)
        #expect(wide == r(108, 350, 1184, 300))
    }
}
