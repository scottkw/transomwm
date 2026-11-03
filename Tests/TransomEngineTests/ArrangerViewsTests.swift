@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3), d = ref(4)
private let three = ViewSlot(3)!

/// a, b and c docked one after another (Phase 3 tiles: a | b | (Desktop tile / c)), d floating on the Desktop, zoom on.
private func threeDocked() async throws -> Harness {
    var harness = await Harness.started(frames: [
        1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
        3: Rect(x: 1100, y: 600, width: 150, height: 120), 4: Rect(x: 1000, y: 100, width: 200, height: 150),
    ])
    for window in [a, b, c] { await harness.send(.command(.dock, focused: window)) }
    try #require(harness.arranger.world[key].map { Set($0.tree.windows) } == [a, b, c])
    await harness.send(.zoomEnabled(true))
    return harness
}

private func tree(_ harness: Harness) throws -> LayoutTree {
    try #require(harness.arranger.world[key]?.tree)
}

/// The smallest node holding `windows`' leaves (a floater's is the Desktop tile).
private func lca(_ windows: [WindowRef], _ harness: Harness) throws -> NodeID {
    try #require(Navigator.lowestCommonAncestor(windows.compactMap { harness.arranger.leafNode(of: $0) }, in: tree(harness)))
}

private func moves(_ effects: [ArrangerEffect]) -> [CameraMove] {
    effects.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }
}

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

@discardableResult
private func camera(_ command: CameraCommand, _ harness: inout Harness, focused: WindowRef? = nil) async -> [ArrangerEffect] {
    await harness.send(.camera(command, displayUUID: "main", focused: focused, pointer: nil))
}

/// Moves the camera to `target` and settles.
private func zoom(_ harness: inout Harness, to target: ViewTarget) async throws {
    let move = try #require(moves(await harness.send(.zoomTo(target, displayUUID: "main"))).first)
    await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
}

/// VIEW-01, 08 UI-SPEC Surface 1: ⇧⌥{n} stores the view's desk and window identities, ⌥{n} zooms back to the smallest
/// node holding the windows still there.
@Suite struct ArrangerViewsTests {
    @Test func savingThenGoingBackZoomsToTheSavedWindows() async throws {
        var harness = try await threeDocked()
        let node = try lca([c, d], harness)
        let root = try tree(harness).root
        try #require(node != root, "c and the Desktop tile share a split without a and b")
        try await zoom(&harness, to: .node(node))

        let saved = await camera(.saveView(three), &harness)

        #expect(notices(saved) == [.viewSaved(three, replaced: false, displayUUID: "main")])
        #expect(moves(saved).isEmpty)
        #expect(harness.arranger.camera.savedViews[three] == SavedView(slot: three, desk: key, home: false, windows: [c.identity, d.identity]))
        try await zoom(&harness, to: .home)

        let shown = await camera(.view(three), &harness)

        #expect(moves(shown).map(\.to) == [.node(node)])
        #expect(notices(shown) == [.viewShown(three, displayUUID: "main")])
    }
}
