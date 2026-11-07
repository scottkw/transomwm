import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Success criterion 5, D-D, T-04-30: with zoom off every camera command is dispatched, yet no zoom piece is made and
/// ScreenCaptureKit is never touched (SnapshotCapture's touch counter stays at 0).
@Suite(.serialized) @MainActor struct ZoomOffTests {
    static let commands: [CameraCommand] =
        [.zoomOutAll, .stepOut, .stepIn, .back, .forward, .frameWindow] + [Edge.left, .right, .top, .bottom].map(CameraCommand.pan)

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

    /// D-07: with zoom off no gesture tap exists, whatever is dispatched. With zoom on but no `startTap` (as in every
    /// unit test) there is none either, so unit tests never open a tap on the host.
    @Test func zoomOffNeverCreatesAGestureTap() async {
        let off = ArrangeController(system: AXWindowSystem(), zoomEnabled: false)
        off.beep = {}
        for source in [CommandSource.hotkey, .menu, .url] {
            for command in Self.commands { await off.dispatch(.camera(command), from: source) }
        }
        #expect(off.isGestureTapRunning == false)
        #expect(off.gestures.isActive == false)

        let on = ArrangeController(system: AXWindowSystem(), zoomEnabled: true)
        on.gestures.publish()
        #expect(on.isGestureTapRunning == false)
        #expect(on.gestures.isActive == false)
    }

    /// D-07 (05-07): with zoom off no multitouch device is opened, whatever is dispatched; with zoom on but no running
    /// gesture tap (every unit test) none is either.
    @Test func zoomOffOpensNoMultitouchDevice() async {
        let off = ArrangeController(system: AXWindowSystem(), zoomEnabled: false)
        off.beep = {}
        for source in [CommandSource.hotkey, .menu, .url] {
            for command in Self.commands {
                await off.dispatch(.camera(command), from: source)
                #expect(off.isMultitouchRunning == false, "after \(command) from \(source)")
            }
        }
        await off.zoom(to: .home, displayUUID: "main")
        #expect(off.isMultitouchRunning == false)

        let on = ArrangeController(system: AXWindowSystem(), zoomEnabled: true)
        on.gestures.publish()
        #expect(on.isMultitouchRunning == false)
    }
}
