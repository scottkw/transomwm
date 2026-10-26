import PaneEngine
import PaneModel
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

        // The second press targets the Desktop tile, so n docks to its right, at the area's right edge.
        let desktop = try #require(try scene.plan().desktopRect)
        let tile = try scene.tile(of: n)
        #expect(tile.minX > desktop.maxX - 1 && near(tile.maxX, scene.area.maxX - 8), "\(tile) beside Desktop \(desktop)")
        #expect(scene.isFloating(m) && !scene.isDocked(m), "a second Finder window was taken")
    }

    @Test func aFinderWindowThatWouldLeaveAWindowWithoutRoomFloatsWithABeep() {
        // Floating, n only widens the Desktop (a 200 + 800); docked beside a it needs 200 + 800 + 700 for f's Desktop.
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        #expect(scene.isDocked(a), "precondition: a did not dock")
        scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        let depth = scene.arranger.history.depth(for: key)

        let effects = scene.arrive(n, minimum: Size(width: 800, height: 100))

        #expect(effects.contains(.beep) && effects.contains(.announce("Not enough room to dock here")))
        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.isDocked(a))
        #expect(scene.arranger.history.depth(for: key) == depth)
    }

    @Test func aFloatingFocusedWindowSplitsTheDesktopTile() throws {
        var scene = Scene(width: 1600, height: 600)
        let desktop = try #require(try scene.plan().desktopRect)
        #expect(desktop.width >= desktop.height, "precondition: the Desktop tile is not wide: \(desktop)")
        scene.arranger.handle(.command(.finderSplit, focused: f), now: scene.start)
        scene.arrive(n)
        let tile = try scene.tile(of: n)
        let after = try #require(try scene.plan().desktopRect)
        #expect(tile.minX > after.maxX - 1 && near(tile.minY, after.minY) && near(tile.height, after.height), "\(after) | \(tile)")
    }

    @Test func withNoFocusedWindowTheMainDisplaysDesktopTileIsSplit() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.arranger.handle(.command(.finderSplit, focused: nil), now: scene.start)
        scene.arrive(n)
        let tile = try scene.tile(of: n)
        let after = try #require(try scene.plan().desktopRect)
        #expect(tile.minX > after.maxX - 1 && near(tile.height, after.height), "\(after) | \(tile)")
    }
}
