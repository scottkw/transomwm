import CoreGraphics
@testable import TransomMac
import Testing

/// The follow math (UI-SPEC Surfaces 1 and 4), pure functions only: no panel is created.
struct StageFollowTests {
    private let start = CGRect(x: 0, y: 0, width: 100, height: 50)
    private let end = CGRect(x: 200, y: 100, width: 300, height: 150)

    private func rect(t: Double, scale: Double = 1, anchor: CGPoint = .zero, offset: CGVector = .zero, start: CGRect? = nil) -> CGRect {
        let from = start ?? self.start
        return StagePanel.followRect(start: from, end: start == nil ? end : from, t: t, scale: scale, anchor: anchor, offset: offset)
    }

    @Test func lerpsFromStartToEnd() {
        #expect(rect(t: 0) == start)
        #expect(rect(t: 1) == end)
        #expect(rect(t: 0.5) == CGRect(x: 100, y: 50, width: 200, height: 100))
    }

    @Test func scalesAboutTheAnchor() {
        let anchor = CGPoint(x: 100, y: 100)
        #expect(rect(t: 0, scale: 2, anchor: anchor, start: CGRect(x: 100, y: 100, width: 10, height: 10)) == CGRect(x: 100, y: 100, width: 20, height: 20))
        #expect(rect(t: 0, scale: 2, anchor: anchor, start: CGRect(x: 110, y: 100, width: 10, height: 10)) == CGRect(x: 120, y: 100, width: 20, height: 20))
    }

    @Test func translatesByTheOffset() {
        #expect(rect(t: 0.5, offset: CGVector(dx: 30, dy: 0)) == CGRect(x: 130, y: 50, width: 200, height: 100))
    }

    @Test func reduceMotionCrossfadesTheSnapAndFadesTheSpringBack() {
        #expect(ZoomController.followStyle(reduceMotion: true) == (snapCrossfade: true, springBackFade: true))
        #expect(ZoomController.followStyle(reduceMotion: false) == (snapCrossfade: false, springBackFade: false))
    }
}
