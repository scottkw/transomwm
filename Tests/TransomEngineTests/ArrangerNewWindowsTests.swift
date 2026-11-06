@testable import TransomEngine
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

    // MARK: An empty desk (8.1.1 D-08)

    /// New Windows: Tile on a desk restored with no tree at all, so this holds before and after new desks lose their
    /// Desktop tile (08.1.1-09); f floats on it.
    private func emptyDesk(zoom: Bool = false) throws -> (arranger: Arranger, area: Rect, start: ContinuousClock.Instant) {
        var arranger = Arranger(newWindows: .tile)
        let start = ContinuousClock.now
        let area = Rect(x: 0, y: 25, width: 1600, height: 600)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1600, height: 625), visibleFrame: area, currentSpaceID: nil)
        _ = arranger.handle(.restore(try World(ids: IDSource(), desks: [key: Desk(tree: LayoutTree())]), homeFrames: [:]), now: start)
        let floater = found(f, Rect(x: 1400, y: 60, width: 150, height: 120))
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [floater], initialRefreshComplete: true)), now: start)
        if zoom { _ = arranger.handle(.zoomEnabled(true), now: start) }
        _ = arranger.handle(.event(.windowFocused(f)), now: start)
        return (arranger, area, start)
    }

    @Test func withNothingDockedATiledNewWindowFillsTheVisibleFrame() throws {
        var (arranger, area, start) = try emptyDesk()
        try #require(arranger.world[key]?.tree.root == nil, "precondition: the desk is not empty")
        let steps = arranger.history.depth(for: key)

        let effects = arranger.handle(.event(.windowCreated(opened(n))), now: start + .milliseconds(400))

        let desk = try #require(arranger.world[key])
        let root = try #require(desk.tree.root)
        #expect(desk.tree.leaf(containing: n) == root)
        #expect(!desk.desktop.contains(n))
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        #expect(plan.resolution.nodeRects[root] == Rect(x: 8, y: 33, width: 1584, height: 584))
        #expect(arranger.history.depth(for: key) == steps + 1)
        #expect(!effects.contains(.beep))

        _ = arranger.handle(.command(.undo, focused: f), now: start + .seconds(1))

        let undone = try #require(arranger.world[key])
        #expect(undone.tree.root == nil)
        #expect(undone.desktop.frame(of: n) == opening)
    }

    @Test func withNothingDockedAndZoomOnAWindowBiggerThanTheScreenDocksCollapsed() throws {
        var (arranger, _, start) = try emptyDesk(zoom: true)

        _ = arranger.handle(.event(.windowCreated(opened(n, minimum: Size(width: 1700, height: 100)))), now: start + .milliseconds(400))

        #expect(arranger.world[key]?.tree.leaf(containing: n) != nil)
        #expect(arranger.camera.collapsible.contains(n.identity))
    }

    @Test func withNothingDockedAndZoomOffAWindowBiggerThanTheScreenFloatsSilently() throws {
        var (arranger, _, start) = try emptyDesk()
        let steps = arranger.history.depth(for: key)

        let effects = arranger.handle(.event(.windowCreated(opened(n, minimum: Size(width: 1700, height: 100)))), now: start + .milliseconds(400))

        let desk = try #require(arranger.world[key])
        #expect(desk.tree.root == nil)
        #expect(desk.desktop.frame(of: n) == opening)
        #expect(arranger.history.depth(for: key) == steps)
        #expect(!effects.contains(.beep))
        #expect(!effects.contains { if case .announce = $0 { true } else { false } }, "\(effects)")
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

    // MARK: What never auto-tiles (D-04, D-05)

    enum NeverCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case neverDock, excluded, minimised, narrow, short, foundLate

        var testDescription: String { rawValue }

        var info: WindowInfo {
            var info = opened(n)
            switch self {
            case .neverDock: info.kind = .neverDock(.subrole)
            case .excluded: info.isExcluded = true
            case .minimised: info.state = .absent
            case .narrow: info.frame = Rect(x: 600, y: 200, width: 199, height: 400)
            case .short: info.frame = Rect(x: 600, y: 200, width: 400, height: 119)
            case .foundLate: info.openedWhileRunning = false
            }
            return info
        }

        /// Dialogs, excluded apps and minimised windows are on no desk at all; the others float.
        var floats: Bool {
            switch self {
            case .neverDock, .excluded, .minimised: false
            case .narrow, .short, .foundLate: true
            }
        }
    }

    @Test(arguments: NeverCase.allCases)
    func neverAutoTiles(_ row: NeverCase) throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let steps = scene.undoSteps, tree = scene.desk?.tree

        let effects = scene.arrive(row.info)

        #expect(!scene.isDocked(n))
        #expect(scene.isFloating(n) == row.floats)
        #expect(scene.undoSteps == steps)
        #expect(scene.desk?.tree == tree)
        #expect(!effects.contains(.beep))
    }

    enum PausedCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case byTheUser, session, settlingDisplays

        var testDescription: String { rawValue }

        var input: ArrangerInput {
            switch self {
            case .byTheUser: .setPaused(.user, true)
            case .session: .event(.sessionPaused(true))
            case .settlingDisplays: .displaysSettling
            }
        }
    }

    @Test(arguments: PausedCase.allCases)
    func whileArrangingCantActItFloats(_ row: PausedCase) throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let steps = scene.undoSteps
        _ = scene.arranger.handle(row.input, now: scene.start)

        scene.arrive()

        #expect(!scene.isDocked(n))
        #expect(scene.isFloating(n))
        #expect(scene.undoSteps == steps)
    }

    @Test func theSmallestWindowThatTilesIs200By120() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.arrive(opened(n, frame: Rect(x: 600, y: 200, width: 200, height: 120)))
        #expect(scene.isDocked(n))
    }

    @Test func pausedThenResumedItStaysFloating() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let steps = scene.undoSteps
        _ = scene.arranger.handle(.setPaused(.user, true), now: scene.start)
        scene.arrive()

        _ = scene.arranger.handle(.setPaused(.user, false), now: scene.start + .seconds(1))
        _ = scene.arranger.handle(.tick, now: scene.start + .seconds(2))

        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.undoSteps == steps)
    }

    /// D-05: only the moment it opens counts. Choosing Tile, or a floating window changing later, moves nothing.
    @Test func choosingTileMovesNothingAlreadyFloating() throws {
        var scene = Scene(width: 1600, height: 600, mode: .float)
        scene.arrive()
        let world = scene.arranger.world

        let effects = scene.arranger.handle(.newWindows(.tile), now: scene.start)
        #expect(effects.isEmpty)
        #expect(scene.arranger.newWindows == .tile)
        _ = scene.arranger.handle(.event(.windowChanged(opened(n))), now: scene.start + .seconds(1))

        #expect(scene.arranger.world == world)
        #expect(scene.isFloating(n))
    }

    @Test func choosingFloatAgainFloatsTheNextWindow() throws {
        var scene = Scene(width: 1600, height: 600)
        _ = scene.arranger.handle(.newWindows(.float), now: scene.start)
        scene.arrive()
        #expect(scene.isFloating(n) && !scene.isDocked(n))
    }

    // MARK: Re-matching runs first (D-05)

    private func titled(_ id: UInt32, _ title: String, pid: Int32 = 900) -> WindowRef {
        WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: "com.example.new-windows"), titleHint: title)
    }

    /// `titles` docked, each of pid 900, plus another app's window, focused and docked; then pid 900 quits.
    private func afterAQuit(_ titles: [String]) -> (Arranger, ContinuousClock.Instant, WindowRef) {
        var arranger = Arranger(newWindows: .tile)
        let start = ContinuousClock.now
        let area = Rect(x: 0, y: 25, width: 1440, height: 875)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)
        let other = ref(9, pid: 950, bundleID: "com.example.other")
        let quitting = titles.enumerated().map { titled(UInt32($0.offset + 1), $0.element) }
        let frames = quitting.indices.map { Rect(x: 40 + 200 * Double($0), y: 300, width: 150, height: 120) }
        let windows = zip(quitting, frames).map { found($0, $1) } + [found(other, Rect(x: 1000, y: 600, width: 150, height: 120))]
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: windows, initialRefreshComplete: true)), now: start)
        for window in quitting + [other] { _ = arranger.handle(.command(.dock, focused: window), now: start) }
        _ = arranger.handle(.event(.windowFocused(other)), now: start)
        _ = arranger.handle(.event(.appTerminated(pid: 900)), now: start)
        for window in quitting { _ = arranger.handle(.event(.windowDestroyed(window)), now: start) }
        return (arranger, start, other)
    }

    @Test func aWindowWithAWaitingTileFillsItInsteadOfDockingBesideTheFocusedOne() throws {
        var (arranger, start, other) = afterAQuit(["Notes"])
        #expect(arranger.placeholderCount == 1, "precondition: no tile is waiting")
        let tree = try #require(arranger.world[key]?.tree)
        let steps = arranger.history.depth(for: key)
        let back = titled(11, "Notes", pid: 901)

        _ = arranger.handle(.event(.windowCreated(opened(back))), now: start + .seconds(1))

        let desk = try #require(arranger.world[key])
        #expect(arranger.placeholderCount == 0)
        #expect(Set(desk.tree.windows) == [back, other], "\(desk.tree.windows)")
        #expect(desk.tree.leaf(containing: back) == tree.leaf(containing: titled(1, "Notes")), "it is not in its own tile")
        #expect(arranger.history.depth(for: key) == steps, "auto-tile added an undo step")
        #expect(!desk.desktop.contains(back))
    }

    /// Pitfall 6: a tie may still fill a tile as its title settles, and once it expires the window stays floating.
    @Test func aTieStaysFloatingAndStaysFloatingAfterItExpires() throws {
        var (arranger, start, _) = afterAQuit(["Notes", "Notes"])
        #expect(arranger.placeholderCount == 2, "precondition: no tiles are waiting")
        let steps = arranger.history.depth(for: key)
        let first = titled(11, "Notes", pid: 901), second = titled(12, "Notes", pid: 901)

        _ = arranger.handle(.event(.windowCreated(opened(first))), now: start + .seconds(1))
        _ = arranger.handle(.event(.windowCreated(opened(second))), now: start + .seconds(1))

        var desk = try #require(arranger.world[key])
        #expect(desk.desktop.contains(first) && desk.desktop.contains(second))
        #expect(desk.tree.leaf(containing: first) == nil && desk.tree.leaf(containing: second) == nil)

        _ = arranger.handle(.tick, now: start + .seconds(120))
        desk = try #require(arranger.world[key])
        #expect(arranger.placeholderCount == 0, "the tiles should have expired")
        #expect(desk.desktop.contains(first) && desk.desktop.contains(second))
        #expect(arranger.history.depth(for: key) == steps)
    }

    @Test func aDormantWindowComingBackWakesInItsSavedPlace() throws {
        var arranger = Arranger(newWindows: .tile)
        let start = ContinuousClock.now
        let area = Rect(x: 0, y: 25, width: 1440, height: 875)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)
        let saved = ref(1), other = ref(9, pid: 950, bundleID: "com.example.other")
        var layout = World()
        try layout.addDesk(key)
        try layout.reflow(key) { desk, ids throws(LayoutError) in
            try desk.tree.insert(saved, at: .left, of: .desktop, ids: &ids)
        }
        let live = [saved, other].map { CGWindowEntry(windowID: $0.windowID, pid: $0.pid, bounds: opening, layer: 0, onScreen: false, alpha: 1) }
        _ = arranger.handle(.restore(layout, homeFrames: [:]), now: start)
        let inventory = WindowInventory(
            displays: [display], windows: [found(other, Rect(x: 1000, y: 600, width: 150, height: 120))], initialRefreshComplete: true, liveWindows: live)
        _ = arranger.handle(.inventory(inventory), now: start)
        _ = arranger.handle(.event(.windowFocused(other)), now: start)
        #expect(arranger.hasDormantWindows, "precondition: the saved window is not dormant")
        let leaf = try #require(arranger.world[key]?.tree.leaf(containing: saved))
        let steps = arranger.history.depth(for: key)

        _ = arranger.handle(.event(.windowCreated(opened(saved))), now: start + .seconds(1))

        let desk = try #require(arranger.world[key])
        #expect(desk.tree.windows == [saved])
        #expect(desk.tree.leaf(containing: saved) == leaf)
        #expect(!desk.desktop.contains(saved))
        #expect(arranger.history.depth(for: key) == steps)
        #expect(!arranger.hasDormantWindows)
    }

    // MARK: No room (D-06)

    @Test func noRoomWithZoomOffFloatsSilently() throws {
        // As in ArrangerFinderTests: docked beside a, n's minimum can't fit, and floating it can't size the Desktop either.
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        scene.focus(a)
        let steps = scene.undoSteps

        let effects = scene.arrive(opened(n, minimum: Size(width: 1450, height: 100)))

        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.isDocked(a))
        #expect(scene.undoSteps == steps)
        #expect(!effects.contains(.beep))
        #expect(!effects.contains { if case .announce = $0 { true } else { false } }, "\(effects)")
        #expect(!effects.contains { if case .notice = $0 { true } else { false } }, "\(effects)")
    }

    @Test func noRoomWithZoomOnDocksAndAnnouncesTheCollapse() throws {
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        _ = scene.arranger.handle(.zoomEnabled(true), now: scene.start)
        scene.focus(a)
        let steps = scene.undoSteps

        let effects = scene.arrive(opened(n, minimum: Size(width: 1450, height: 100)))

        #expect(scene.isDocked(n) && !scene.isFloating(n))
        #expect(scene.undoSteps == steps + 1)
        let collapsed = scene.arranger.camera.collapsible
        #expect(!collapsed.isEmpty)
        let others = collapsed.subtracting([n.identity]).count
        let announcement = CollapseCopy.dockedAnnouncement(dragged: collapsed.contains(n.identity), others: others)
        #expect(effects.contains(.announce(announcement)), "\(effects)")
        #expect(!effects.contains(.beep))
    }

    // MARK: A minimum learned after docking (WR-05)

    /// macOS gives no minimum up front, so the first window of an app docks. Then the app refuses the tile.
    private func learnedAfterDocking(zoom: Bool) -> (scene: Scene, effects: [ArrangerEffect]) {
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        if zoom { _ = scene.arranger.handle(.zoomEnabled(true), now: scene.start) }
        scene.focus(a)
        scene.arrive()
        #expect(scene.isDocked(n), "precondition: with no minimum known n docks")
        var learned = opened(n, minimum: Size(width: 1450, height: 100))
        learned.frame = Rect(x: 800, y: 33, width: 1450, height: 584)
        let effects = scene.arranger.handle(.event(.windowChanged(learned)), now: scene.start + .seconds(2))
        return (scene, effects)
    }

    @Test func aMinimumLearnedAfterDockingFloatsItSilentlyWhereItOpenedWithZoomOff() {
        let (scene, effects) = learnedAfterDocking(zoom: false)

        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.floatingFrame(n) == opening)
        #expect(scene.isDocked(a))
        #expect(!effects.contains(.beep))
        #expect(!effects.contains { if case .announce = $0 { true } else { false } }, "\(effects)")
        #expect(!effects.contains { if case .notice = $0 { true } else { false } }, "\(effects)")
    }

    @Test func aMinimumLearnedAfterDockingCollapsesItWithZoomOn() {
        let (scene, effects) = learnedAfterDocking(zoom: true)

        #expect(scene.isDocked(n) && !scene.isFloating(n))
        #expect(scene.arranger.camera.collapsible.contains(n.identity))
        #expect(!effects.contains { if case .notice = $0 { true } else { false } }, "\(effects)")
        let others = scene.arranger.camera.collapsible.subtracting([n.identity]).count
        #expect(effects.contains(.announce(CollapseCopy.dockedAnnouncement(dragged: true, others: others))), "\(effects)")
    }

    /// Only until it has taken a tile: after that, losing room is the ordinary case and gets the ordinary notice.
    @Test func afterATileThatFitsLostRoomIsTheOrdinaryCase() throws {
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        scene.focus(a)
        scene.arrive()
        let tile = try scene.tile(of: n)
        _ = scene.arranger.handle(.event(.frameApplied(n, requested: tile, actual: tile)), now: scene.start + .seconds(1))

        var learned = opened(n, minimum: Size(width: 1450, height: 100))
        learned.frame = tile
        let effects = scene.arranger.handle(.event(.windowChanged(learned)), now: scene.start + .seconds(2))

        #expect(scene.isFloating(n))
        #expect(effects.contains(.notice(.lostRoom([n]))), "\(effects)")
    }

    /// A refused write is no answer yet; the learned minimum that follows it is.
    @Test func aRefusedWriteKeepsItWaitingForTheMinimum() throws {
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        scene.focus(a)
        scene.arrive()
        let tile = try scene.tile(of: n)
        let refused = Rect(x: tile.x, y: tile.y, width: tile.width + 200, height: tile.height)
        _ = scene.arranger.handle(.event(.frameApplied(n, requested: tile, actual: refused)), now: scene.start + .seconds(1))

        var learned = opened(n, minimum: Size(width: 1450, height: 100))
        learned.frame = refused
        let effects = scene.arranger.handle(.event(.windowChanged(learned)), now: scene.start + .seconds(2))

        #expect(scene.isFloating(n))
        #expect(!effects.contains { if case .notice = $0 { true } else { false } }, "\(effects)")
    }

    // MARK: During a drag (WR-01)

    /// Presses `window` and reports it dragged by `dx`, so the session is classified: a size change is a resize.
    private func press(_ scene: inout Scene, _ window: WindowRef, to frame: Rect) {
        let grab = Point(x: frame.midX, y: frame.minY + 10)
        _ = scene.arranger.handle(.pointer(PointerEvent(kind: .down, location: grab, pressWindow: window)), now: scene.start)
        _ = scene.arranger.handle(.pointer(PointerEvent(kind: .dragged, location: Point(x: grab.x + 100, y: grab.y))), now: scene.start)
        _ = scene.arranger.handle(.dragFrame(window.identity, frame), now: scene.start)
    }

    private func letGo(_ scene: inout Scene) {
        _ = scene.arranger.handle(.pointer(PointerEvent(kind: .up, location: Point(x: 0, y: 0))), now: scene.start)
    }

    /// The weights of the split holding `window`'s leaf.
    private func weights(_ scene: Scene, around window: WindowRef) throws -> [Double] {
        let tree = try #require(scene.desk?.tree)
        let leaf = try #require(tree.leaf(containing: window))
        guard case .split(_, _, let weights)? = tree.parent(of: leaf).flatMap(tree.node) else { return [] }
        return weights
    }

    /// One edge resize of a, with or without a window opening halfway through.
    private func resizingA(openingOne: Bool) throws -> Scene {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let tile = try scene.tile(of: a)
        _ = scene.arranger.handle(.event(.frameApplied(a, requested: tile, actual: tile)), now: scene.start)
        _ = scene.arranger.handle(.event(.windowMoved(a, tile)), now: scene.start)
        press(&scene, a, to: Rect(x: tile.x, y: tile.y, width: tile.width + 100, height: tile.height))
        if openingOne {
            let shape = scene.desk?.tree
            scene.arrive()
            #expect(scene.arranger.deskKey(of: n) == nil, "n joined a desk under the drag")
            #expect(scene.desk?.tree == shape, "the tree changed under the drag")
        }
        letGo(&scene)
        return scene
    }

    @Test func aWindowOpeningDuringAResizeFloatsAfterItAndChangesNothing() throws {
        let plain = try resizingA(openingOne: false)
        var scene = try resizingA(openingOne: true)

        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.floatingFrame(n) == opening)
        #expect(scene.undoSteps == plain.undoSteps, "the new window took an undo step")
        #expect(try weights(scene, around: a) == weights(plain, around: a), "the drag's result changed")

        // Only that gesture: the next window tiles again.
        let next = ref(21)
        scene.arrive(opened(next))
        #expect(scene.isDocked(next))
    }

    /// One gap drag between a and the Desktop, with or without a window opening halfway through.
    private func draggingTheGap(openingOne: Bool) throws -> Scene {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let tree = try #require(scene.desk?.tree)
        let resolution = try scene.plan().resolution
        let handle = try #require(GapHandles.handles(tree: tree, resolution: resolution, gap: 8).first)
        _ = scene.arranger.handle(.gapDrag(handle, delta: 50, ended: false), now: scene.start)
        if openingOne {
            scene.arrive()
            #expect(scene.arranger.deskKey(of: n) == nil, "n joined a desk under the gap drag")
        }
        _ = scene.arranger.handle(.gapDrag(handle, delta: 50, ended: true), now: scene.start)
        return scene
    }

    @Test func aWindowOpeningDuringAGapDragFloatsAfterItAndChangesNothing() throws {
        let plain = try draggingTheGap(openingOne: false)
        let scene = try draggingTheGap(openingOne: true)

        #expect(scene.isFloating(n) && !scene.isDocked(n))
        #expect(scene.undoSteps == plain.undoSteps)
        #expect(try weights(scene, around: a) == weights(plain, around: a), "the gap drag's result changed")
    }

    /// A window closed before the drag ended leaves nothing behind.
    @Test func aWindowThatOpensAndClosesDuringADragNeverJoins() throws {
        var scene = Scene(width: 1600, height: 600)
        scene.focus(a)
        let tile = try scene.tile(of: a)
        press(&scene, a, to: Rect(x: tile.x, y: tile.y, width: tile.width + 100, height: tile.height))
        scene.arrive()
        _ = scene.arranger.handle(.event(.windowDestroyed(n)), now: scene.start)

        letGo(&scene)

        #expect(scene.arranger.deskKey(of: n) == nil)
    }

    // MARK: Finder Split (Pitfall 4)

    private func finder(_ id: UInt32) -> WindowRef { ref(id, pid: 300, bundleID: Arranger.finderBundleID) }

    @Test func finderSplitsWindowGoesWhereThePressAsked() throws {
        var scene = Scene(width: 1600, height: 600)
        _ = scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        scene.focus(f)  // the ordinary rule would split the largest tile, not a's
        let steps = scene.undoSteps

        let effects = scene.arrive(opened(finder(10)))

        let desktop = try #require(try scene.plan().desktopRect)
        let left = try scene.tile(of: a), tile = try scene.tile(of: finder(10))
        #expect(tile.minX > left.maxX - 1 && tile.maxX < desktop.minX + 1, "\(left) | \(tile) | \(desktop)")
        #expect(scene.undoSteps == steps + 1)
        #expect(!effects.contains(.beep))
    }

    @Test func aFinderSplitsWindowThatCantFitStillBeepsAsItAlwaysHas() throws {
        var scene = Scene(width: 1600, height: 600, minimums: [a: Size(width: 200, height: 100), f: Size(width: 700, height: 100)])
        _ = scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)

        let effects = scene.arrive(opened(finder(10), minimum: Size(width: 1450, height: 100)))

        #expect(effects.contains(.beep) && effects.contains(.announce("Not enough room to dock here")))
        #expect(scene.isFloating(finder(10)))
    }

    @Test func aSecondFinderWindowFollowsTheOrdinaryRule() throws {
        var scene = Scene(width: 1600, height: 600)
        _ = scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        scene.arrive(opened(finder(10)))
        scene.focus(finder(10))
        let beside = try scene.tile(of: finder(10))
        let steps = scene.undoSteps

        scene.arrive(opened(finder(11)))

        #expect(scene.isDocked(finder(11)))
        #expect(scene.undoSteps == steps + 1)
        #expect(try scene.tile(of: finder(10)).width < beside.width || scene.tile(of: finder(10)).height < beside.height, "it did not land beside the focused tile")
    }

    @Test func anotherAppsWindowDuringTheWaitDocksAndLeavesTheExpectation() throws {
        var scene = Scene(width: 1600, height: 600)
        _ = scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)

        scene.arrive(opened(ref(5)))
        #expect(scene.isDocked(ref(5)))

        scene.arrive(opened(finder(10)))
        #expect(scene.isDocked(finder(10)))
    }

    @Test func aFinderWindowAfterTheDeadlineFollowsTheOrdinaryRule() throws {
        var scene = Scene(width: 1600, height: 600)
        _ = scene.arranger.handle(.command(.finderSplit, focused: a), now: scene.start)
        _ = scene.arranger.handle(.event(.windowCreated(opened(finder(10)))), now: scene.start + .seconds(3))
        #expect(scene.isDocked(finder(10)))
    }

    // MARK: Another Space

    /// `home(of:)`: a window whose Spaces exclude the shown one belongs on its own Space's desk. No tile there can be planned
    /// from here, so it floats there and the shown desk doesn't change.
    @Test func aWindowOnAnotherSpaceLandsOnThatDesk() throws {
        var arranger = Arranger(newWindows: .tile)
        let start = ContinuousClock.now
        let area = Rect(x: 0, y: 25, width: 1440, height: 875)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: 1)
        let shownKey = DeskKey(displayUUID: "main", spaceID: 1), otherKey = DeskKey(displayUUID: "main", spaceID: 2)
        var docked = found(a, Rect(x: 40, y: 300, width: 320, height: 232))
        docked.spaces = [1]
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [docked], initialRefreshComplete: true)), now: start)
        _ = arranger.handle(.command(.dock, focused: a), now: start)
        _ = arranger.handle(.event(.windowFocused(a)), now: start)
        let shownBefore = try #require(arranger.world[shownKey])
        var new = opened(n)
        new.spaces = [2]

        _ = arranger.handle(.event(.windowCreated(new)), now: start + .seconds(1))

        #expect(arranger.world[otherKey]?.desktop.contains(n) == true)
        #expect(arranger.world[shownKey] == shownBefore)
    }
}
