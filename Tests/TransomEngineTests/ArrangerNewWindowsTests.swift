import TransomEngine
import TransomModel
import Testing

private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = 900, bundleID: String = "com.example.new-windows") -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), f = ref(2), n = ref(20)
private let opening = Rect(x: 600, y: 200, width: 400, height: 300)

private func opened(_ window: WindowRef, frame: Rect = opening, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", learnedMinimum: minimum, openedWhileRunning: true)
}

private func found(_ window: WindowRef, _ frame: Rect, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", learnedMinimum: minimum)
}

/// One display whose visible area is `width` x `height`, with New Windows: Tile, a docked on the left of the Desktop and
/// f floating clear of it on the right.
private struct Scene {
    var arranger: Arranger
    let start = ContinuousClock.now
    let area: Rect
    let minimums: [WindowRef: Size]

    init(width: Double, height: Double, mode: NewWindowsMode = .tile, docked: Bool = true, minimums: [WindowRef: Size] = [:]) {
        arranger = Arranger(newWindows: mode)
        self.minimums = minimums
        area = Rect(x: 0, y: 25, width: width, height: height)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: width, height: height + 25), visibleFrame: area, currentSpaceID: nil)
        // a's centre is near the left edge halfway down, so its dock lands on the Desktop's left edge.
        let frameA = Rect(x: 40, y: area.midY - 116, width: 320, height: 232)
        let frameF = Rect(x: area.maxX - 200, y: 60, width: 150, height: 120)
        let inventory = WindowInventory(
            displays: [display], windows: [found(a, frameA, minimum: minimums[a]), found(f, frameF, minimum: minimums[f])], initialRefreshComplete: true)
        _ = arranger.handle(.inventory(inventory), now: start)
        if docked { _ = arranger.handle(.command(.dock, focused: a), now: start) }
    }

    var desk: Desk? { arranger.world[key] }
    var undoSteps: Int { arranger.history.depth(for: key) }

    func plan() throws -> FramePlan {
        try Planner.plan(desk: #require(desk), area: area, gap: 8, mins: minimums)
    }

    func tile(of window: WindowRef) throws -> Rect {
        let leaf = try #require(desk?.tree.leaf(containing: window), "\(window) is not docked")
        return try #require(try plan().resolution.nodeRects[leaf])
    }

    mutating func focus(_ window: WindowRef) {
        _ = arranger.handle(.event(.windowFocused(window)), now: start)
    }

    @discardableResult
    mutating func arrive(_ info: WindowInfo = opened(n)) -> [ArrangerEffect] {
        arranger.handle(.event(.windowCreated(info)), now: start + .milliseconds(400))
    }

    func isDocked(_ window: WindowRef) -> Bool { desk?.tree.leaf(containing: window) != nil }
    func isFloating(_ window: WindowRef) -> Bool { desk?.desktop.contains(window) == true }
    func floatingFrame(_ window: WindowRef) -> Rect? { desk?.desktop.windows.first { $0.window == window }?.frame }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1 }

/// TILE-21, D-01..D-06: New Windows: Tile, in the engine.
@Suite struct ArrangerNewWindowsTests {
    // MARK: Where it lands (D-02, D-03)

    @Test func aWideFocusedTileGetsTheNewWindowToItsRight() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        #expect(try scene.tile(of: a).width >= scene.tile(of: a).height, "precondition: a's tile is not wide")

        scene.arrive()

        let left = try scene.tile(of: a), right = try scene.tile(of: n)
        #expect(right.minX > left.maxX - 1 && near(right.minY, left.minY) && near(right.height, left.height), "\(left) | \(right)")
        #expect(!scene.isFloating(n))
    }

    @Test func aTallFocusedTileGetsTheNewWindowBelow() throws {
        var scene = Scene(width: 1000, height: 900)
        scene.focus(a)
        let before = try scene.tile(of: a)
        #expect(before.height > before.width, "precondition: a's tile is not tall: \(before)")

        scene.arrive()

        let top = try scene.tile(of: a), bottom = try scene.tile(of: n)
        #expect(bottom.minY > top.maxY - 1 && near(bottom.minX, top.minX) && near(bottom.width, top.width), "\(top) over \(bottom)")
    }

    /// Pitfall 5: the settle delay holds back `.windowCreated`, so the new window's own focus can arrive first.
    @Test func theNewWindowsOwnFocusDoesNotChangeTheTarget() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        scene.focus(n)
        let before = try scene.tile(of: a)

        scene.arrive()

        let left = try scene.tile(of: a), right = try scene.tile(of: n)
        #expect(left.width < before.width && right.minX > left.maxX - 1, "n did not land beside a: \(left) | \(right)")
    }

    @Test func aFloatingFocusSplitsTheLargestTile() throws {
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 1000, height: 100)])
        scene.focus(f)
        let desktop = try #require(try scene.plan().desktopRect)
        #expect(try scene.tile(of: a).width > desktop.width, "precondition: a's tile is not the largest")

        scene.arrive()

        let after = try #require(try scene.plan().desktopRect)
        let left = try scene.tile(of: a), tile = try scene.tile(of: n)
        #expect(tile.minX > left.maxX - 1 && tile.maxX < after.minX + 1, "n is not beside a: \(left) | \(tile) | \(after)")
    }

    @Test func noFocusAtAllSplitsTheLargestTile() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.arrive()
        let after = try #require(try scene.plan().desktopRect)
        let tile = try scene.tile(of: n)
        #expect(tile.minX > after.maxX - 1 && near(tile.height, after.height), "\(after) | \(tile)")
    }

    @Test func withNothingDockedItIsTheFirstTileBesideTheDesktop() throws {
        var scene = Scene(width: 1600, height: 600, docked: false)
        scene.focus(a)  // floating, so not a docked tile

        scene.arrive()

        let desktop = try #require(try scene.plan().desktopRect)
        let tile = try scene.tile(of: n)
        #expect(scene.desk?.tree.windows == [n])
        #expect(tile.minX > desktop.maxX - 1 && near(tile.height, desktop.height), "\(desktop) | \(tile)")
    }

    @Test func aDeskThatDoesNotExistYetIsCreated() throws {
        var arranger = Arranger(newWindows: .tile)
        let area = Rect(x: 0, y: 25, width: 1600, height: 600)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1600, height: 625), visibleFrame: area, currentSpaceID: nil)
        let start = ContinuousClock.now
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [], initialRefreshComplete: true)), now: start)

        _ = arranger.handle(.event(.windowCreated(opened(n))), now: start)

        #expect(arranger.world[key]?.tree.windows == [n])
    }

    // MARK: One undo step (D-06)

    @Test func itIsOneUndoStepAndUndoFloatsItWhereItOpened() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let steps = scene.undoSteps

        scene.arrive()
        #expect(scene.undoSteps == steps + 1)
        #expect(scene.arranger.wantedFrames[n.identity] == opening)

        _ = scene.arranger.handle(.command(.undo, focused: a), now: scene.start + .seconds(1))

        #expect(scene.undoSteps == steps)
        #expect(!scene.isDocked(n))
        #expect(scene.floatingFrame(n) == opening)
    }

    // MARK: Float, the default (D-01)

    @Test func withFloatTheSameEventFloatsItWithNoUndoStep() throws {
        var scene = Scene(width: 1600, height: 600, mode: .float, docked: false)
        scene.focus(a)
        let steps = scene.undoSteps

        scene.arrive()

        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.undoSteps == steps)
        #expect(scene.desk?.tree.windows.isEmpty == true)
        #expect(scene.floatingFrame(n) == opening)
    }

    @Test func floatIsTheEnginesDefault() {
        #expect(Arranger().newWindows == .float)
    }
}
