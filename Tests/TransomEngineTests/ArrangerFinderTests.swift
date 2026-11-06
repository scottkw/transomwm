import TransomEngine
import TransomModel
import Testing

private let finder = "com.apple.finder"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = 900, bundleID: String = "com.example.finder-split") -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private func finderRef(_ id: UInt32) -> WindowRef { ref(id, pid: 300, bundleID: finder) }

private func info(_ window: WindowRef, _ frame: Rect, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", learnedMinimum: minimum)
}

private let a = ref(1), f = ref(2), e = finderRef(10), n = finderRef(11)

/// One display whose visible area is `width` x `height`, with a docked on the left of the Desktop and f, plus any
/// `others`, floating clear of it on the right.
private struct Scene {
    var arranger = Arranger()
    let start = ContinuousClock.now
    let area: Rect

    init(width: Double, height: Double, others: [WindowRef] = [], minimums: [WindowRef: Size] = [:]) {
        area = Rect(x: 0, y: 25, width: width, height: height)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: width, height: height + 25), visibleFrame: area, currentSpaceID: nil)
        // a's centre is near the left edge halfway down, so its dock lands on the Desktop's left edge.
        let frameA = Rect(x: 40, y: area.midY - 116, width: 320, height: 232)
        let floating = ([f] + others).enumerated().map { i, window in
            info(window, Rect(x: area.maxX - 200, y: 60 + 130 * Double(i), width: 150, height: 120), minimum: minimums[window])
        }
        let inventory = WindowInventory(displays: [display], windows: [info(a, frameA, minimum: minimums[a])] + floating, initialRefreshComplete: true)
        _ = arranger.handle(.inventory(inventory), now: start)
        _ = arranger.handle(.command(.dock, focused: a), now: start)
    }

    var desk: Desk? { arranger.world[key] }

    func plan() throws -> FramePlan {
        try Planner.plan(desk: #require(desk), area: area, gap: 8, mins: [:])
    }

    /// The resolved tile of the leaf holding `window`.
    func tile(of window: WindowRef) throws -> Rect {
        let leaf = try #require(desk?.tree.leaf(containing: window), "\(window) is not docked")
        return try #require(try plan().resolution.nodeRects[leaf])
    }

    @discardableResult
    mutating func arrive(_ window: WindowRef, after delay: Duration = .milliseconds(400), minimum: Size? = nil) -> [ArrangerEffect] {
        arranger.handle(.event(.windowCreated(info(window, Rect(x: 600, y: 200, width: 400, height: 300), minimum: minimum))), now: start + delay)
    }

    func isDocked(_ window: WindowRef) -> Bool { desk?.tree.leaf(containing: window) != nil }
    func isFloating(_ window: WindowRef) -> Bool { desk?.desktop.contains(window) == true }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1 }

/// D-14, TILE-17: ⌃⌥⌘N splits the current tile along its longer side with the first new Finder window.
@Suite struct ArrangerFinderTests {
    @Test func aWideTileSplitsToTheRightWithTheFirstNewFinderWindow() throws {
        var scene = Scene(width: 1600, height: 600)
        let before = try scene.tile(of: a)
        #expect(before.width >= before.height, "precondition: a's tile is not wide: \(before)")

        let effects = scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)

        #expect(effects.contains(.openFinderWindow))
        #expect(effects.contains(.wake(at: scene.start + .seconds(2))))
        scene.arrive(n)
        #expect(scene.isDocked(n), "the new Finder window did not dock")
        let left = try scene.tile(of: a), right = try scene.tile(of: n)
        #expect(right.minX > left.maxX - 1 && near(right.minY, left.minY) && near(right.height, left.height), "\(left) | \(right)")
        // A right-edge drop into a horizontal split joins it (D-20), so a and n share the row with the Desktop.
        #expect(near(left.minX, before.minX) && right.maxX < scene.area.maxX - 100, "\(left) | \(right) in \(scene.area)")
    }

    @Test func aTallTileSplitsBelow() throws {
        var scene = Scene(width: 1000, height: 900)
        let before = try scene.tile(of: a)
        #expect(before.height > before.width, "precondition: a's tile is not tall: \(before)")

        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        scene.arrive(n)

        let top = try scene.tile(of: a), bottom = try scene.tile(of: n)
        #expect(bottom.minY > top.maxY - 1 && near(bottom.minX, top.minX) && near(bottom.width, top.width), "\(top) over \(bottom)")
        #expect(near(top.minY, before.minY) && near(bottom.maxY, before.maxY), "the split left a's old tile: \(top) / \(bottom) in \(before)")
    }

    @Test func anExistingFinderWindowThatChangesAndANonFinderWindowAreNotTaken() throws {
        var scene = Scene(width: 1600, height: 600, others: [e])
        #expect(scene.isFloating(e), "precondition: e floats")
        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)

        _ = scene.arranger.handle(.event(.windowChanged(info(e, Rect(x: 1300, y: 300, width: 160, height: 120)))), now: scene.start)
        let other = ref(5)
        scene.arrive(other, after: .milliseconds(200))

        #expect(scene.isFloating(e) && !scene.isDocked(e), "an existing Finder window was taken")
        #expect(scene.isFloating(other) && !scene.isDocked(other), "a non-Finder window was taken")
        scene.arrive(n)
        #expect(scene.isDocked(n), "the new Finder window did not dock after the others")
    }

    // MARK: No window, a second press, no room, and the Desktop target

    @Test func withNoNewFinderWindowByTheDeadlineN9ShowsAndTheLayoutIsUnchanged() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        let world = scene.arranger.world

        let effects = scene.arranger.handle(.tick, now: scene.start + .seconds(2))

        #expect(effects.contains(.notice(.finderNoWindow)))
        #expect(scene.arranger.world == world)
        scene.arrive(n, after: .milliseconds(2500))
        #expect(scene.isFloating(n) && !scene.isDocked(n), "a Finder window after the deadline was docked")
        #expect(scene.arranger.handle(.tick, now: scene.start + .seconds(3)).contains(.notice(.finderNoWindow)) == false, "N9 shown twice")
    }

    @Test func aFinderWindowAfterTheDeadlineFloatsEvenBeforeTheTick() {
        var scene = Scene(width: 1600, height: 600)
        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        scene.arrive(n, after: .milliseconds(2100))
        #expect(scene.isFloating(n) && !scene.isDocked(n))
    }

    @Test func aSecondPressReplacesTheFirstAndOnlyOneWindowIsTaken() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        scene.arranger.handle(.command(.finderSplit, focused: nil), now: scene.start + .milliseconds(100))

        scene.arrive(n)
        let m = finderRef(12)
        scene.arrive(m, after: .milliseconds(500))

        // The second press targets the largest tile (the Desktop here), so n docks to its right.
        let desktop = try #require(try scene.plan().desktopRect)
        let tile = try scene.tile(of: n)
        #expect(tile.minX > desktop.maxX - 1 && near(tile.maxX, scene.area.maxX - 8), "\(tile) beside Desktop \(desktop)")
        #expect(scene.isFloating(m) && !scene.isDocked(m), "a second Finder window was taken")
    }

    @Test func aFinderWindowThatWouldLeaveAWindowWithoutRoomFloatsWithABeep() {
        // Docked beside a, n needs 200 + 1450 + a 1x1 Desktop + gaps > 1600, with or without f's 700 pt minimum.
        // Floating, n's minimum is too big to size the Desktop beside a, so a keeps its tile (G-03-6).
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        #expect(scene.isDocked(a), "precondition: a did not dock")
        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        let depth = scene.arranger.history.depth(for: key)

        let effects = scene.arrive(n, minimum: Size(width: 1450, height: 100))

        #expect(effects.contains(.beep) && effects.contains(.announce("Not enough room to dock here")))
        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.isDocked(a))
        #expect(scene.arranger.history.depth(for: key) == depth)
    }

    /// UI-SPEC discretion 6: with no focused docked window the largest tile splits; a is made the largest.
    @Test(arguments: [f, nil] as [WindowRef?])
    func withNoFocusedDockedWindowTheLargestTileSplits(focused: WindowRef?) throws {
        let mins = [a: Size(width: 1000, height: 100)]
        var scene = Scene(width: 1600, height: 600, minimums: mins)
        let desk = try #require(scene.desk), leafA = try #require(desk.tree.leaf(containing: a))
        let rects = try Planner.plan(desk: desk, area: scene.area, gap: 8, mins: mins).resolution.nodeRects
        let before = try #require(rects[leafA])
        let others = rects.filter { id, _ in
            if id == leafA { return false }
            if case .split? = desk.tree.node(id) { return false }
            return true
        }
        try #require(others.values.allSatisfy { $0.width * $0.height < before.width * before.height }, "precondition: a's tile is not the largest")

        scene.arranger.handle(.command(.finderSplit, focused: focused), now: scene.start)
        let effects = scene.arrive(n)

        let left = try scene.tile(of: a), tile = try scene.tile(of: n)
        #expect(tile.minX > left.maxX - 1 && near(tile.minY, left.minY) && near(tile.height, left.height), "\(left) | \(tile)")
        #expect(!effects.contains(.beep))
    }

    /// UI-SPEC discretion 6: on an empty desk the new Finder window becomes the first tile, filling the visible frame.
    @Test func onAnEmptyDeskTheFinderWindowFillsTheVisibleFrame() throws {
        var arranger = Arranger()
        let start = ContinuousClock.now
        let area = Rect(x: 0, y: 25, width: 1600, height: 600)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1600, height: 625), visibleFrame: area, currentSpaceID: nil)
        _ = arranger.handle(.restore(try World(ids: IDSource(), desks: [key: Desk(tree: LayoutTree())]), homeFrames: [:]), now: start)
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [info(f, Rect(x: 1400, y: 60, width: 150, height: 120))], initialRefreshComplete: true)), now: start)

        let pressed = arranger.handle(.command(.finderSplit, focused: f), now: start)
        let effects = arranger.handle(.event(.windowCreated(info(n, Rect(x: 600, y: 200, width: 400, height: 300)))), now: start + .milliseconds(400))

        #expect(pressed.contains(.openFinderWindow) && !pressed.contains(.beep))
        let desk = try #require(arranger.world[key])
        let root = try #require(desk.tree.root)
        #expect(desk.tree.leaf(containing: n) == root)
        #expect(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).resolution.nodeRects[root] == Rect(x: 8, y: 33, width: 1584, height: 584))
        #expect(!effects.contains(.beep))
    }

    /// A display with no desk yet: the desk is made when the Finder window arrives, and the window docks there.
    @Test func onADisplayWithNoDeskYetTheFinderWindowDocks() throws {
        var arranger = Arranger()
        let start = ContinuousClock.now
        let area = Rect(x: 0, y: 25, width: 1600, height: 600)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1600, height: 625), visibleFrame: area, currentSpaceID: nil)
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [], initialRefreshComplete: true)), now: start)
        try #require(arranger.world[key] == nil, "precondition: the desk exists")

        let pressed = arranger.handle(.command(.finderSplit, focused: nil), now: start)
        let effects = arranger.handle(.event(.windowCreated(info(n, Rect(x: 600, y: 200, width: 400, height: 300)))), now: start + .milliseconds(400))

        #expect(pressed.contains(.openFinderWindow) && !pressed.contains(.beep))
        #expect(arranger.world[key]?.tree.leaf(containing: n) != nil)
        #expect(!effects.contains(.beep))
    }
}
