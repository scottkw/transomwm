@testable import PaneMac
import PaneEngine
import PaneModel
import Testing

private let own: Int32 = 999
private let point = Point(x: 66, y: 389)

private func entry(_ id: UInt32, pid: Int32, layer: Int, _ bounds: Rect, alpha: Double = 1) -> CGWindowEntry {
    CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: layer, onScreen: true, alpha: alpha)
}

private let dock = entry(7, pid: 362, layer: 20, Rect(x: 0, y: 0, width: 1024, height: 768))
private let textEdit = entry(202, pid: 500, layer: 0, Rect(x: 12, y: 375, width: 574, height: 326))

/// The tap's window-0 fallback (G-03-4): the topmost layer-0 window of another process under the point, as pressWindow.
@Suite struct TopmostWindowTests {
    private func topmost(_ list: [CGWindowEntry]) -> UInt32? { CGWindowList.topmost(at: point, in: list, excludingPID: own) }

    @Test func theDocksFullScreenOverlayIsSkipped() {
        #expect(topmost([dock, textEdit]) == 202)
    }

    @Test func menuBarLayersAndOwnHandlesListedFirstAreSkipped() {
        let item = entry(30, pid: 400, layer: 25, Rect(x: 0, y: 0, width: 1024, height: 768))
        let menubar = entry(31, pid: 401, layer: 24, Rect(x: 0, y: 0, width: 1024, height: 768))
        let handle = entry(40, pid: own, layer: 3, Rect(x: 0, y: 380, width: 200, height: 20))
        #expect(topmost([item, menubar, dock, handle, textEdit]) == 202)
    }

    @Test func aLayer0WindowOfAnotherAppInFrontWins() {
        let front = entry(303, pid: 600, layer: 0, Rect(x: 0, y: 300, width: 400, height: 200))
        #expect(topmost([dock, front, textEdit]) == 303)
    }

    @Test func transparentOwnAndMissingEntriesAreSkipped() {
        let clear = entry(50, pid: 700, layer: 0, Rect(x: 0, y: 300, width: 400, height: 200), alpha: 0)
        let mine = entry(51, pid: own, layer: 0, Rect(x: 0, y: 300, width: 400, height: 200))
        let elsewhere = entry(52, pid: 701, layer: 0, Rect(x: 600, y: 0, width: 100, height: 100))
        #expect(topmost([clear, mine, elsewhere, textEdit]) == 202)
    }

    @Test func noLayer0HitOrAnEmptyListIsNil() {
        #expect(topmost([dock]) == nil)
        #expect(topmost([]) == nil)
    }
}
