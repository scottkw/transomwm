import PaneEngine
import PaneModel
import Testing

private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)

/// a belongs to app X, b to app Y.
private let a = WindowRef(identity: WindowIdentity(windowID: 1, pid: 900, bundleID: "com.example.x"))
private let b = WindowRef(identity: WindowIdentity(windowID: 2, pid: 901, bundleID: "com.example.y"))

private func info(_ window: WindowRef, frame: Rect, excluded: Bool = false) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main", kind: .dockable, isExcluded: excluded)
}

private func commands(_ effects: [ArrangerEffect]) -> [WindowCommand] {
    effects.flatMap { effect -> [WindowCommand] in if case .perform(let commands) = effect { commands } else { [] } }
}

/// a and b floating, a on the left and b small in the right half.
private func started() -> Arranger {
    var arranger = Arranger()
    let windows = [info(a, frame: Rect(x: 40, y: 80, width: 320, height: 232)), info(b, frame: Rect(x: 730, y: 400, width: 150, height: 120))]
    _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: windows, initialRefreshComplete: true)), now: .now)
    return arranger
}

/// TILE-18, D-29: excluding an app floats its docked windows to the Desktop tile, and Pane never moves its windows.
@Suite struct ArrangerExclusionTests {
    @Test func aDockedWindowThatBecomesExcludedFloatsAtItsFrameAndItsNeighbourReflows() throws {
        var arranger = started()
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        let docked = setFrames(arranger.handle(.command(.dock, focused: b), now: .now))
        let tileA = try #require(docked[a]), tileB = try #require(docked[b])
        let depth = arranger.history.depth(for: key)

        let effects = arranger.handle(.event(.windowChanged(info(a, frame: tileA, excluded: true))), now: .now)
        let desk = try #require(arranger.world[key])
        #expect(desk.tree.state(of: a) == nil)
        #expect(desk.desktop.frame(of: a) == tileA, "the excluded window did not stay at its frame")
        #expect(arranger.history.depth(for: key) == depth, "excluding added an undo step")
        #expect(!commands(effects).contains { $0.window == a }, "a command was sent for the excluded window")
        let grown = try #require(setFrames(effects)[b])
        #expect(grown != tileB, "the neighbour did not reflow")
    }

    /// CR-01: an undo to a snapshot from before the exclusion must not dock the excluded window again.
    @Test func undoNeverDocksAWindowExcludedSinceTheSnapshot() throws {
        var arranger = started()
        let tileA = try #require(setFrames(arranger.handle(.command(.dock, focused: a), now: .now))[a])
        _ = arranger.handle(.command(.dock, focused: b), now: .now)
        _ = arranger.handle(.event(.windowChanged(info(a, frame: tileA, excluded: true))), now: .now)

        _ = arranger.handle(.command(.undo, focused: b), now: .now)

        let desk = try #require(arranger.world[key])
        #expect(desk.tree.state(of: a) == nil, "the undo docked the excluded window again")
        #expect(desk.desktop.contains(a))
    }

    @Test func anExcludedFloatingWindowIsNeverClampedOrParkedAndStaysFloatingWhenIncludedAgain() throws {
        var arranger = started()
        // a covers the left of the screen, where b's tile will go.
        let wide = Rect(x: 40, y: 80, width: 900, height: 600)
        _ = arranger.handle(.event(.windowChanged(info(a, frame: wide, excluded: true))), now: .now)
        let dock = arranger.handle(.command(.dock, focused: b), now: .now)
        #expect(setFrames(dock)[b] != nil)
        #expect(!commands(dock).contains { $0.window == a }, "the excluded window was clamped")
        let hide = arranger.handle(.command(.toggleDesktop, focused: b), now: .now)
        #expect(!commands(hide).contains { $0.window == a }, "the excluded window was parked")
        _ = arranger.handle(.command(.toggleDesktop, focused: b), now: .now)

        _ = arranger.handle(.event(.windowChanged(info(a, frame: wide))), now: .now)
        let desk = try #require(arranger.world[key])
        #expect(desk.desktop.contains(a) && desk.tree.state(of: a) == nil, "including the app again docked its window")
    }

    @Test func aNewWindowOfAnExcludedAppIsRecordedButOnNoDesk() {
        var arranger = started()
        let c = WindowRef(identity: WindowIdentity(windowID: 3, pid: 900, bundleID: "com.example.x"))
        let effects = arranger.handle(.event(.windowCreated(info(c, frame: Rect(x: 100, y: 100, width: 300, height: 200), excluded: true))), now: .now)
        #expect(arranger.windows[c.identity] != nil)
        #expect(arranger.deskKey(of: c) == nil)
        #expect(!commands(effects).contains { $0.window == c })
    }
}
