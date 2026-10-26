import PaneEngine
import PaneModel
import PaneTestSupport
import Testing
import os

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)
private let refusal: [ArrangerEffect] = [.beep, .announce("Not enough room to dock here")]

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let w1 = ref(1), w2 = ref(2)
/// w1 on the left; w2 small and well inside the right half, so docking w1 does not touch it.
private let frame1 = Rect(x: 40, y: 80, width: 320, height: 232)
private let frame2 = Rect(x: 730, y: 400, width: 150, height: 120)

/// The fake's event stream, collected in the background. `take()` returns what arrived since the last call.
final class EventInbox: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: [WindowEvent]())

    init(_ stream: AsyncStream<WindowEvent>) {
        Task { [buffer] in
            for await event in stream { buffer.withLock { $0.append(event) } }
        }
    }

    /// The fake yields synchronously; a short wait lets the reader task drain the stream.
    func take() async -> [WindowEvent] {
        try? await Task.sleep(for: .milliseconds(30))
        return buffer.withLock { events in
            defer { events = [] }
            return events
        }
    }
}

/// An Arranger wired to a FakeWindowSystem the way ArrangeController wires it to the live one.
struct Harness {
    let fake = FakeWindowSystem()
    let inbox: EventInbox
    var arranger = Arranger()
    /// The instant every input is fed at; tests of the once-per-second correction move it.
    var now = ContinuousClock.now

    init() {
        inbox = EventInbox(fake.events)
    }

    /// One app, windows 1 and 2 (or `frames`), the main display, the initial sweep, then the inventory.
    static func started(frames: [UInt32: Rect] = [1: frame1, 2: frame2]) async -> Harness {
        var harness = Harness()
        await harness.fake.setDisplays([display])
        await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        for (id, frame) in frames.sorted(by: { $0.key < $1.key }) { await harness.fake.open(.standard(id: id, pid: pid, frame: frame)) }
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.inventory(await harness.fake.inventory()))
        return harness
    }

    /// Feeds one input, runs its `.perform` effects on the fake, then feeds the events those writes caused.
    @discardableResult
    mutating func send(_ input: ArrangerInput) async -> [ArrangerEffect] {
        let effects = arranger.handle(input, now: now)
        await run(effects)
        await settle()
        return effects
    }

    /// Feeds every pending fake event (a few rounds, so echoes of echoes settle too).
    mutating func settle() async {
        for _ in 0..<5 {
            let events = await inbox.take()
            if events.isEmpty { return }
            for event in events { await run(arranger.handle(.event(event), now: now)) }
        }
    }

    /// Refreshes the app after a simulated change and feeds the resulting events; returns all their effects.
    mutating func refresh() async -> [ArrangerEffect] {
        await fake.refresh(pid: pid)
        var effects: [ArrangerEffect] = []
        for event in await inbox.take() {
            let next = arranger.handle(.event(event), now: now)
            effects += next
            await run(next)
        }
        await settle()
        return effects
    }

    private func run(_ effects: [ArrangerEffect]) async {
        for case .perform(let commands) in effects { await fake.perform(commands) }
    }

    func frame(_ window: WindowRef) async -> Rect? {
        await fake.windows[window.windowID]?.frame
    }
}

/// The setFrames in `effects`, by window.
func setFrames(_ effects: [ArrangerEffect]) -> [WindowRef: Rect] {
    var frames: [WindowRef: Rect] = [:]
    for case .perform(let commands) in effects {
        for case .setFrame(let window, let rect) in commands { frames[window] = rect }
    }
    return frames
}

func inside(_ rect: Rect, _ outer: Rect) -> Bool {
    rect.minX >= outer.minX && rect.minY >= outer.minY && rect.maxX <= outer.maxX && rect.maxY <= outer.maxY
}

func info(_ id: UInt32, frame: Rect, kind: WindowKind = .dockable, excluded: Bool = false, minimum: Size? = nil) -> WindowInfo {
    WindowInfo(window: ref(id), frame: frame, state: .present, displayUUID: "main", kind: kind, isExcluded: excluded, learnedMinimum: minimum)
}

/// TILE-03, TILE-07, D-12, D-24, D-26 through the pure Arranger (Pattern 1), driven like the live shell.
@Suite struct ArrangerLifecycleTests {
    @Test func newWindowsFloatOnTheDesktopAndAreNotMoved() async throws {
        let harness = await Harness.started()
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.contains(w1) && desk.desktop.contains(w2))
        #expect(desk.tree.windows.isEmpty)
        #expect(await harness.fake.performed.isEmpty)
        #expect(harness.arranger.deskKey(of: w1) == key)
    }

    @Test func dockingTwoWindowsTilesThemWithoutOverlap() async throws {
        var harness = await Harness.started()
        let first = await harness.send(.command(.dock, focused: w1))
        let firstFrames = setFrames(first)
        #expect(firstFrames.count == 1)
        let tile1 = try #require(firstFrames[w1])
        #expect(inside(tile1, visible))
        #expect(harness.arranger.history.depth(for: key) == 1)

        let second = setFrames(await harness.send(.command(.dock, focused: w2)))
        let a = try #require(second[w1]), b = try #require(second[w2])
        #expect(!a.overlaps(b))
        #expect(inside(a, visible) && inside(b, visible))
        #expect(harness.arranger.history.depth(for: key) == 2)
        #expect(await harness.frame(w1) == a)
        #expect(await harness.frame(w2) == b)
    }

    @Test func closingADockedWindowGivesItsSpaceToItsNeighbour() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        await harness.send(.command(.dock, focused: w2))
        let old = try #require(await harness.frame(w1))
        let grown = try #require(setFrames(await harness.send(.event(.windowDestroyed(w1))))[w2])
        // The split is horizontal: w2 now spans w1's old x range.
        #expect(grown.minX <= old.minX && grown.maxX >= old.maxX)
    }

    @Test func neverDockAndExcludedWindowsAreRecordedButNeverOnADesk() async throws {
        var arranger = Arranger()
        let panel = info(3, frame: Rect(x: 40, y: 80, width: 300, height: 200), kind: .neverDock(.subrole))
        let excluded = info(4, frame: Rect(x: 40, y: 80, width: 300, height: 200), excluded: true)
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [info(1, frame: frame1), panel, excluded])), now: .now)
        #expect(arranger.windows[ref(3).identity] != nil && arranger.windows[ref(4).identity] != nil)
        #expect(arranger.deskKey(of: ref(3)) == nil && arranger.deskKey(of: ref(4)) == nil)
        // Docking w1 at the left puts a tile under both; neither is moved (T-03-07).
        let frames = setFrames(arranger.handle(.command(.dock, focused: w1), now: .now))
        #expect(frames[w1] != nil)
        #expect(frames[ref(3)] == nil && frames[ref(4)] == nil)
        #expect(arranger.handle(.command(.dock, focused: ref(4)), now: .now) == [.beep])
    }

    @Test func aDockWithoutRoomIsRefusedAndChangesNothing() {
        var arranger = Arranger()
        let big = Size(width: 1000, height: 100)
        let inventory = WindowInventory(displays: [display], windows: [info(1, frame: frame1, minimum: big), info(2, frame: frame2, minimum: big)])
        _ = arranger.handle(.inventory(inventory), now: .now)
        let world = arranger.world, history = arranger.history
        // The refusal also flashes the blocked preview (03-11, UI-SPEC keyboard parity; ArrangerDragTests checks its frame).
        let effects = arranger.handle(.command(.dock, focused: w1), now: .now)
        #expect(Array(effects.prefix(2)) == refusal)
        #expect(effects.dropFirst(2).allSatisfy { if case .flashBlocked = $0 { true } else { false } })
        #expect(arranger.world == world)
        #expect(arranger.history == history)
    }

    @Test func framesAlreadyRequestedAreNotWrittenAgain() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        var changed = try #require(harness.arranger.windows[w1.identity])
        changed.window.titleHint = "renamed"
        let effects = await harness.send(.event(.windowChanged(changed)))
        #expect(setFrames(effects).isEmpty)
    }
}

/// TILE-09: Float and Undo, each one undo step, and the availability rule shared by menu items and hotkeys.
extension ArrangerLifecycleTests {
    @Test func floatPutsADockedWindowOnTheDesktopAtItsClampedTileRect() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        await harness.send(.command(.dock, focused: w2))
        let tile = try #require(await harness.frame(w1))
        let effects = await harness.send(.command(.float, focused: w1))
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.tree.state(of: w1) == nil)
        let desktop = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).desktopRect)
        #expect(desk.desktop.frame(of: w1) == Planner.clamp(tile, into: desktop))
        #expect(setFrames(effects)[w2] != nil, "the neighbour was not re-planned")
        #expect(harness.arranger.history.depth(for: key) == 3)
        #expect(await harness.frame(w1) == desk.desktop.frame(of: w1))
    }

    @Test func floatOfAFloatingWindowOrWithNoFocusBeepsAndChangesNothing() async {
        var harness = await Harness.started()
        let world = harness.arranger.world
        #expect(await harness.send(.command(.float, focused: w1)) == [.beep])
        #expect(await harness.send(.command(.float, focused: nil)) == [.beep])
        #expect(harness.arranger.world == world)
    }

    @Test func undoOfADockReplansDirectlyAndPutsTheWindowBack() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        let effects = await harness.send(.command(.undo, focused: w1))
        #expect(!effects.contains { if case .requery = $0 { true } else { false } })
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.tree.windows.isEmpty)
        #expect(desk.desktop.frame(of: w1) == frame1)
        #expect(setFrames(effects)[w1] == frame1)
        #expect(await harness.frame(w1) == frame1)
        #expect(harness.arranger.history.depth(for: key) == 0)
    }

    /// CR-01: a window admitted after the undone edit (no undo step) is still floating on the desk after the undo.
    @Test func undoKeepsAWindowAdmittedSinceTheUndoneEdit() throws {
        var arranger = Arranger()
        let inventory = WindowInventory(displays: [display], windows: [info(1, frame: frame1)], initialRefreshComplete: true)
        _ = arranger.handle(.inventory(inventory), now: .now)
        _ = arranger.handle(.command(.dock, focused: w1), now: .now)
        _ = arranger.handle(.event(.windowCreated(info(2, frame: frame2))), now: .now)
        #expect(arranger.world[key]?.desktop.contains(w2) == true)

        _ = arranger.handle(.command(.undo, focused: w1), now: .now)

        let desk = try #require(arranger.world[key])
        #expect(desk.desktop.frame(of: w1) == frame1)
        #expect(desk.desktop.frame(of: w2) == frame2, "the window admitted after the dock was dropped from every desk")
    }

    @Test func undoWithNoFocusUsesTheMainDisplaysDesk() async {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        #expect(harness.arranger.isAvailable(.undo, focused: nil))
        await harness.send(.command(.undo, focused: nil))
        #expect(harness.arranger.history.depth(for: key) == 0)
    }

    @Test func undoWithEmptyHistoryBeeps() async {
        var harness = await Harness.started()
        #expect(await harness.send(.command(.undo, focused: w1)) == [.beep])
        #expect(await harness.send(.command(.undo, focused: nil)) == [.beep])
    }

    @Test func aRequeriedCloseRemovesTheRevivedWindow() async throws {
        var harness = await Harness.started()
        await harness.send(.requeried(RevivedWindows(key: key, windows: [w2]), [(w2, .closed)]))
        let desk = try #require(harness.arranger.world[key])
        #expect(!desk.contains(w2) && desk.contains(w1))
    }

    @Test func availabilityFollowsTheFocusedWindow() async {
        var harness = await Harness.started()
        #expect(harness.arranger.isAvailable(.dock, focused: w1))
        #expect(!harness.arranger.isAvailable(.dock, focused: nil))
        #expect(!harness.arranger.isAvailable(.float, focused: w1))
        #expect(!harness.arranger.isAvailable(.undo, focused: w1))
        await harness.send(.command(.dock, focused: w1))
        #expect(!harness.arranger.isAvailable(.dock, focused: w1))
        #expect(harness.arranger.isAvailable(.float, focused: w1))
        #expect(harness.arranger.isAvailable(.undo, focused: w1))
        // A window no desk holds (never-dock, excluded or unknown) cannot be docked.
        #expect(!harness.arranger.isAvailable(.dock, focused: ref(99)))
    }
}

/// TILE-20, WIN-07: a minimised or fullscreen docked window lends its space and comes back to the same tile;
/// nothing is written while the session is paused.
extension ArrangerLifecycleTests {
    /// [w1 | w2 | Desktop], with both docked windows' frames.
    private func twoDocked() async throws -> (Harness, Rect, Rect) {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: w1))
        await harness.send(.command(.dock, focused: w2))
        return (harness, try #require(await harness.frame(w1)), try #require(await harness.frame(w2)))
    }

    private func planned(_ harness: Harness) throws -> FramePlan {
        try Planner.plan(desk: try #require(harness.arranger.world[key]), area: visible, gap: 8, mins: [:])
    }

    @Test func aMinimisedDockedWindowLendsItsTileAndReturnsToIt() async throws {
        var (harness, a, b) = try await twoDocked()
        await harness.fake.update(1) { $0.snapshot.minimized = true }
        let lent = setFrames(await harness.refresh())
        #expect(harness.arranger.world[key]?.tree.state(of: w1) == .absent)
        let grown = try #require(lent[w2])
        #expect(grown.minX == a.minX && grown.width > b.width)
        #expect(lent[w1] == nil)

        await harness.fake.update(1) { $0.snapshot.minimized = false }
        let back = setFrames(await harness.refresh())
        let plan = try planned(harness)
        let returned = try #require(plan.frames[w1])
        #expect(abs(returned.x - a.x) <= 0.5 && abs(returned.width - a.width) <= 0.5)
        #expect(back[w2] == b)
        #expect(await harness.frame(w1) == a)
        #expect(await harness.frame(w2) == b)
    }

    @Test func aFullscreenDockedWindowKeepsItsLeafAndReturnsToItsTile() async throws {
        var (harness, a, b) = try await twoDocked()
        await harness.fake.setFullscreen(1, true)
        let lent = setFrames(await harness.refresh())
        #expect(harness.arranger.world[key]?.tree.state(of: w1) == .fullscreen)
        #expect(lent[w1] == nil, "Pane wrote a fullscreen window")
        #expect(try #require(lent[w2]).width > b.width)

        await harness.fake.setFullscreen(1, false)
        _ = await harness.refresh()
        #expect(try planned(harness).frames[w1] == a)
        #expect(await harness.frame(w2) == b)
    }

    @Test func nothingIsWrittenWhileThePauseLastsAndTheDeskIsReplannedOnResume() async throws {
        var (harness, _, b) = try await twoDocked()
        #expect(await harness.send(.event(.sessionPaused(true))).isEmpty)
        // The close is still recorded (and saved); no window is written.
        #expect(await harness.send(.event(.windowDestroyed(w1))) == [.save(.debounced)])
        let resumed = await harness.send(.event(.sessionPaused(false)))
        // One write, plus the gap handles the closed window took with it (03-13).
        #expect(resumed.filter { if case .gapHandles = $0 { false } else { true } }.count == 1)
        #expect(try #require(setFrames(resumed)[w2]).width > b.width)
    }

    @Test func aMinimisedFloatingWindowKeepsItsFrameAndStaysFloating() async throws {
        var harness = await Harness.started()
        await harness.fake.update(2) { $0.snapshot.minimized = true }
        _ = await harness.refresh()
        #expect(harness.arranger.world[key]?.state(of: w2) == .absent)
        await harness.fake.update(2) { $0.snapshot.minimized = false }
        let effects = await harness.refresh()
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.state(of: w2) == .present)
        #expect(desk.desktop.frame(of: w2) == frame2)
        #expect(desk.tree.windows.isEmpty)
        #expect(setFrames(effects).isEmpty)
    }
}
