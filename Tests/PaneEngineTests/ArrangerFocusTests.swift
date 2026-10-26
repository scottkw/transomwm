import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = pid, bundleID: String = bundleID) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1)
private let b = ref(2)
private let c = ref(3)
private let d = ref(4)
private let e = ref(5)
/// d overlaps b's rows only; e overlaps c's only.
private let frameD = Rect(x: 1000, y: 100, width: 300, height: 200)
private let frameE = Rect(x: 1000, y: 600, width: 300, height: 200)

/// [a | V[b, c] | Desktop], with d and e floating on the Desktop when `floating`, re-attached from a saved World so
/// the shape does not depend on where Dock would put each window. Then focused, in order: `focusOrder`.
private func columns(floating: Bool = true, focusOrder: [WindowRef]) async throws -> Harness {
    var frames: [UInt32: Rect] = [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: frameD, 3: frameE]
    if floating {
        frames[4] = frameD
        frames[5] = frameE
    }
    var harness = await Harness.started(frames: frames)
    var world = World()
    var history = UndoHistory()
    try world.addDesk(key)
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        guard let left = desk.tree.leaf(containing: a) else { throw .windowNotFound(a) }
        try desk.tree.insert(b, at: .right, of: left, ids: &ids)
        guard let middle = desk.tree.leaf(containing: b) else { throw .windowNotFound(b) }
        try desk.tree.insert(c, at: .bottom, of: middle, ids: &ids)
        if floating {
            try desk.desktop.add(d, frame: frameD)
            try desk.desktop.add(e, frame: frameE)
        }
    }
    harness.arranger = Arranger()
    await harness.send(.restore(world, homeFrames: [:]))
    await harness.send(.inventory(await harness.fake.inventory()))
    for window in focusOrder { await harness.send(.event(.windowFocused(window))) }
    return harness
}

/// D-11, TILE-09: ⌃⌥⌘ arrows focus the nearest tile across that edge, ties to the most recently focused window.
@Suite struct ArrangerFocusTests {
    @Test func focusMovesToTheNearestTileAndTiesGoToTheMostRecentlyFocused() async throws {
        var harness = try await columns(focusOrder: [c, b, a])
        #expect(harness.arranger.world[key]?.tree.windows == [a, b, c])

        #expect(await harness.send(.command(.focus(.right), focused: a)) == [.perform([.focus(b)])])
        #expect(harness.arranger.focusOrder.first == b.identity, "the fake's windowFocused did not reach the Arranger")
        #expect(await harness.send(.command(.focus(.left), focused: c)) == [.perform([.focus(a)])])
        #expect(await harness.send(.command(.focus(.left), focused: a)) == [.beep])
    }

    @Test func aTieGoesTheOtherWayWhenTheOtherWindowWasFocusedLast() async throws {
        var harness = try await columns(focusOrder: [b, c, a])
        #expect(await harness.send(.command(.focus(.right), focused: a)) == [.perform([.focus(c)])])
    }

    @Test func aDesktopNeighbourFocusesItsMostRecentlyFocusedFloatingWindow() async throws {
        var harness = try await columns(focusOrder: [e, d, b])
        #expect(await harness.send(.command(.focus(.right), focused: b)) == [.perform([.focus(d)])])

        var empty = try await columns(floating: false, focusOrder: [b])
        #expect(await empty.send(.command(.focus(.right), focused: b)) == [.beep])
    }

    @Test func aFloatingWindowUsesItsFrame() async throws {
        var harness = try await columns(focusOrder: [b, c, e])
        #expect(await harness.send(.command(.focus(.left), focused: e)) == [.perform([.focus(c)])])
        #expect(await harness.send(.command(.focus(.left), focused: d)) == [.perform([.focus(b)])])
    }

    @Test func focusOrderFollowsFocusEventsAndForgetsClosedWindows() async throws {
        var harness = try await columns(focusOrder: [a, b, c])
        #expect(harness.arranger.focusOrder.prefix(3) == [c.identity, b.identity, a.identity])
        await harness.send(.event(.windowFocused(a)))
        #expect(harness.arranger.focusOrder.prefix(3) == [a.identity, c.identity, b.identity])
        await harness.send(.event(.windowDestroyed(c)))
        #expect(!harness.arranger.focusOrder.contains(c.identity))
    }

    @Test func theFakeFocusesAndRaisesAndDropsBothForAnExcludedApp() async throws {
        let fake = FakeWindowSystem()
        let inbox = EventInbox(fake.events)
        let x = ref(9, pid: 901, bundleID: "com.example.excluded")
        await fake.setDisplays([display])
        await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await fake.addApp(FakeApp(pid: 901, bundleID: "com.example.excluded"))
        await fake.open(.standard(id: 1, pid: pid, frame: frameD))
        await fake.open(.standard(id: 9, pid: 901, frame: frameE))
        await fake.refreshAll()
        await fake.setExcluded(["com.example.excluded"])
        _ = await inbox.take()

        await fake.perform([.focus(a), .raise(a), .focus(x), .raise(x)])

        #expect(await inbox.take() == [.windowFocused(a)])
        #expect(await fake.raised == [a])
        #expect(await fake.dropped == [.focus(x), .raise(x)])
    }
}
