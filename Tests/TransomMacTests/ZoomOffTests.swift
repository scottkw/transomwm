import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Success criterion 5, D-D, T-04-30: with zoom off every camera command is dispatched, yet no zoom piece is made and
/// ScreenCaptureKit is never touched (SnapshotCapture's touch counter stays at 0).
@Suite(.serialized) @MainActor struct ZoomOffTests {
    static let commands: [CameraCommand] =
        [.zoomOutAll, .stepOut, .stepIn, .back, .forward, .frameWindow, .frameDesktop] + [Edge.left, .right, .top, .bottom].map(CameraCommand.pan)

    @Test func zoomOffNeverTouchesScreenCaptureKit() async {
        let before = SnapshotCapture.touches
        let arrange = ArrangeController(system: AXWindowSystem(), zoomEnabled: false)
        arrange.beep = {}
        for source in [CommandSource.hotkey, .menu, .url] {
            for command in Self.commands { await arrange.dispatch(.camera(command), from: source) }
        }
        await arrange.zoom(to: .home, displayUUID: "main")

        #expect(SnapshotCapture.touches == before)
        #expect(SnapshotCapture.touches == 0, "something in this process touched ScreenCaptureKit")
        #expect(arrange.hasZoomController == false)
        #expect(arrange.isZoomEnabled == false)
    }
}
