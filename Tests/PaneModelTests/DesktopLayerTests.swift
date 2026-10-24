import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let frameA = Rect(x: 10, y: 20, width: 300, height: 200)
private let frameB = Rect(x: 400, y: 20, width: 300, height: 200)

private let invalidFrames: [Rect] = [
    Rect(x: .nan, y: 0, width: 100, height: 100),
    Rect(x: 0, y: 0, width: -1, height: 100),
    Rect(x: 0, y: 0, width: 100, height: -1),
    Rect(x: 1_000_001, y: 0, width: 100, height: 100),
    Rect(x: 0, y: 0, width: .infinity, height: 100),
]

/// A desk whose tree holds `docked`.
private func dockedDesk(_ docked: WindowRef, ids: inout IDSource) throws -> Desk {
    var tree = LayoutTree()
    try tree.insertRoot(docked, ids: &ids)
    return Desk(tree: tree)
}

@Suite struct DesktopLayerTests {
    @Test func newDeskHasEmptyDesktopLayerThatRoundTripsEmpty() throws {
        let desk = Desk()
        #expect(desk.desktop.windows.isEmpty)
        #expect(desk.desktop == DesktopLayer())

        let world = try World(ids: IDSource(), desks: [DeskKey(displayUUID: "D1", spaceID: nil): desk])
        let data = try world.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"desktop\":{\"windows\":[]}"))
        let decoded = try World.decode(from: data)
        #expect(decoded[DeskKey(displayUUID: "D1", spaceID: nil)]?.desktop.windows.isEmpty == true)
        #expect(decoded == world)
    }

    @Test func insertionOrderSurvivesAddSetFrameAndRemove() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: frameA)
        try layer.add(b, frame: frameB)
        #expect(layer.windows.map(\.window) == [a, b])

        let moved = Rect(x: 50, y: 60, width: 320, height: 240)
        try layer.setFrame(moved, for: a)
        #expect(layer.windows.map(\.window) == [a, b])
        #expect(layer.frame(of: a) == moved)
        #expect(layer.frame(of: b) == frameB)

        try layer.remove(a)
        #expect(layer.windows.map(\.window) == [b])
        #expect(!layer.contains(a))
        #expect(layer.contains(b))
        #expect(layer.frame(of: a) == nil)
    }

    @Test func insertionOrderSurvivesJSONRoundTrip() throws {
        var layer = DesktopLayer()
        try layer.add(c, frame: frameA)
        try layer.add(a, frame: frameB)
        try layer.add(b, frame: frameA)
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(DesktopLayer.self, from: data)
        #expect(decoded.windows.map(\.window) == [c, a, b])
        #expect(decoded == layer)
    }

    @Test func duplicateAddThrowsAndChangesNothing() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: frameA)
        let before = layer
        #expect(throws: LayoutError.duplicateWindow(a)) { try layer.add(a, frame: frameB) }
        #expect(layer == before)
        #expect(layer.frame(of: a) == frameA)
    }

    @Test func removeOrSetFrameOfUnknownWindowThrowsWindowNotFound() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: frameA)
        let before = layer
        #expect(throws: LayoutError.windowNotFound(b)) { try layer.remove(b) }
        #expect(throws: LayoutError.windowNotFound(b)) { try layer.setFrame(frameB, for: b) }
        #expect(layer == before)
    }

    @Test(arguments: invalidFrames)
    func invalidFrameThrowsInvalidGeometryAndChangesNothing(frame: Rect) throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: frameA)
        let before = layer
        #expect(throws: LayoutError.self) { try layer.add(b, frame: frame) }
        #expect(throws: LayoutError.self) { try layer.setFrame(frame, for: a) }
        do {
            try layer.add(b, frame: frame)
        } catch {
            guard case .invalidGeometry = error else {
                Issue.record("expected invalidGeometry, got \(error)")
                return
            }
        }
        #expect(layer == before)
        #expect(layer.frame(of: a) == frameA)
    }

    @Test func negativeOriginFramesAreAccepted() throws {
        var layer = DesktopLayer()
        let left = Rect(x: -1440, y: -200, width: 800, height: 600)
        try layer.add(a, frame: left)
        #expect(layer.frame(of: a) == left)
        try layer.validate()
    }

    @Test func addedWindowIsPresentAndStoredClosedStateIsRejected() throws {
        var layer = DesktopLayer()
        try layer.add(a, frame: frameA)
        #expect(layer.windows.first?.state == .present)
        try layer.validate()

        let json = String(decoding: try JSONEncoder().encode(layer), as: UTF8.self)
            .replacingOccurrences(of: "\"present\"", with: "\"closed\"")
        let closed = try JSONDecoder().decode(DesktopLayer.self, from: Data(json.utf8))
        #expect(throws: LayoutError.self) { try closed.validate() }
    }

    @Test func deskRejectsWindowThatIsDockedAndFloating() throws {
        var ids = IDSource()
        var desk = try dockedDesk(a, ids: &ids)
        try desk.validate()
        #expect(desk.contains(a))
        #expect(!desk.contains(b))

        try desk.desktop.add(b, frame: frameB)
        #expect(desk.contains(b))
        try desk.validate()

        try desk.desktop.add(a, frame: frameA)
        #expect(throws: LayoutError.duplicateWindow(a)) { try desk.validate() }
    }

    @Test func worldRejectsWindowFloatingOnTwoDesks() throws {
        var one = Desk()
        var two = Desk()
        try one.desktop.add(a, frame: frameA)
        try two.desktop.add(a, frame: frameB)
        #expect(throws: LayoutError.duplicateWindow(a)) {
            try World(ids: IDSource(), desks: [
                DeskKey(displayUUID: "D1", spaceID: nil): one,
                DeskKey(displayUUID: "D2", spaceID: nil): two,
            ])
        }
    }

    @Test func worldRejectsWindowFloatingOnOneDeskAndDockedOnAnother() throws {
        var ids = IDSource()
        let docked = try dockedDesk(a, ids: &ids)
        var floating = Desk()
        try floating.desktop.add(a, frame: frameA)
        #expect(throws: LayoutError.duplicateWindow(a)) {
            try World(ids: ids, desks: [
                DeskKey(displayUUID: "D1", spaceID: nil): docked,
                DeskKey(displayUUID: "D2", spaceID: nil): floating,
            ])
        }
    }
}
