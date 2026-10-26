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

    init(width: Double, height: Double, others: [WindowRef] = []) {
        area = Rect(x: 0, y: 25, width: width, height: height)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: width, height: height + 25), visibleFrame: area, currentSpaceID: nil)
        // a's centre is near the left edge halfway down, so its dock lands on the Desktop's left edge.
        let frameA = Rect(x: 40, y: area.midY - 116, width: 320, height: 232)
        let floating = ([f] + others).enumerated().map { i, window in
            info(window, Rect(x: area.maxX - 200, y: 60 + 130 * Double(i), width: 150, height: 120))
        }
        let inventory = WindowInventory(displays: [display], windows: [info(a, frameA)] + floating, initialRefreshComplete: true)
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
    mutating func arrive(_ window: WindowRef, after delay: Duration = .milliseconds(400)) -> [ArrangerEffect] {
        arranger.handle(.event(.windowCreated(info(window, Rect(x: 600, y: 200, width: 400, height: 300)))), now: start + delay)
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
        #expect(near(left.minX, before.minX) && near(right.maxX, before.maxX), "the split left a's old tile: \(left) | \(right) in \(before)")
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
}
