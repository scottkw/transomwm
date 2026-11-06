@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"  // Harness's app
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = pid, bundleID: String = bundleID) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), f = ref(2)
/// Over the left half, where a's tile lands once a docks.
private let overA = Rect(x: 500, y: 100, width: 300, height: 200)

/// a docked on the left, f floating partly over a's tile.
private func docked() async -> Harness {
    var harness = await Harness.started(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: overA])
    await harness.send(.command(.dock, focused: a))
    return harness
}

/// Every command the window system ran that moves, parks or raises `window`.
private func touches(_ window: WindowRef, _ harness: Harness) async -> [WindowCommand] {
    await harness.fake.performed.filter { command in
        switch command {
        case .setFrame(let w, _), .park(let w, _, _), .raise(let w): w == window
        default: false
        }
    }
}

/// D-05, D-06, D-14: floating windows are plain macOS windows; Transom never frames, clamps, parks or raises them.
@Suite struct ArrangerFloatingTests {
    @Test func aFloatingWindowOverADockedTileIsNeverMoved() async throws {
        var harness = await docked()
        let tile = try #require(await harness.frame(a))
        try #require(overA.overlaps(tile), "f is clear of a's tile")
        await harness.send(.inventory(await harness.fake.inventory()))
        await harness.send(.tick)
        let further = Rect(x: 200, y: 150, width: 300, height: 200)
        await harness.fake.userMove(2, to: further)
        _ = await harness.refresh()
        await harness.send(.tick)

        #expect(await touches(f, harness).isEmpty)
        #expect(await harness.frame(f) == further)
        #expect(harness.arranger.world[key]?.desktop.frame(of: f) == further)
        #expect(await harness.frame(a) == tile)
    }

    /// D-06: a new floating window stays where its app opened it, even over a docked tile.
    @Test func aNewFloatingWindowStaysWhereItsAppPutIt() async throws {
        var harness = await docked()
        let n = ref(3), frame = Rect(x: 100, y: 300, width: 400, height: 250)
        await harness.fake.open(.standard(id: 3, pid: pid, frame: frame))
        await harness.fake.refreshAll()
        await harness.fake.advance(by: .milliseconds(300))  // a new window settles before it is reported
        await harness.fake.refreshAll()
        await harness.settle()

        #expect(harness.arranger.world[key]?.desktop.frame(of: n) == frame)
        #expect(await touches(n, harness).isEmpty)
        #expect(await harness.frame(n) == frame)
    }

    /// D-29: an excluded floating window is never moved or parked (from ArrangerDesktopTests).
    @Test func anExcludedFloatingWindowIsNeverMoved() async throws {
        var harness = await docked()
        let excludedBundle = "com.example.excluded"
        let x = ref(5, pid: 901, bundleID: excludedBundle), frame = Rect(x: 300, y: 300, width: 200, height: 150)
        await harness.fake.addApp(FakeApp(pid: 901, bundleID: excludedBundle))
        await harness.fake.open(.standard(id: 5, pid: 901, frame: frame))
        await harness.fake.refreshAll()
        await harness.fake.advance(by: .milliseconds(300))
        await harness.fake.refreshAll()
        await harness.settle()
        #expect(harness.arranger.world[key]?.desktop.contains(x) == true)
        await harness.fake.setExcluded([excludedBundle])
        await harness.settle()

        #expect(await harness.fake.parked.isEmpty)
        // D-29: the Arranger sends nothing for x for the window system's filter to drop.
        #expect(await harness.fake.dropped.isEmpty)
        #expect(await touches(x, harness).isEmpty)
        #expect(await harness.fake.windows[5]?.frame == frame)
    }

    /// G-03-6 retired: a floater takes no room, so one wider than the screen never floats a docked window.
    @Test func aFloaterBiggerThanTheScreenLeavesTheDockedWindowsAlone() async throws {
        var harness = await docked()
        let tile = try #require(await harness.frame(a))
        var info = try #require(harness.arranger.windows[f.identity])
        info.learnedMinimum = Size(width: 2000, height: 1000)

        let effects = await harness.send(.event(.windowChanged(info)))

        #expect(!effects.contains { if case .notice = $0 { true } else { false } })
        #expect(harness.arranger.world[key]?.tree.state(of: a) == .present)
        #expect(await harness.frame(a) == tile)
        #expect(await touches(f, harness).isEmpty)
    }
}
