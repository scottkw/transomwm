import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = pid, bundleID: String = bundleID) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), f = ref(2), g = ref(3)
/// f and g sit well inside the right half, so docking a on the left leaves them clear of its tile.
private let homeF = Rect(x: 900, y: 100, width: 300, height: 200)
private let homeG = Rect(x: 950, y: 500, width: 300, height: 200)

/// [a | Desktop] with f and g floating on the Desktop.
private func docked() async -> Harness {
    var harness = await Harness.started(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: homeF, 3: homeG])
    await harness.send(.command(.dock, focused: a))
    return harness
}

/// D-29: an excluded floating window is never moved; G-03-6: a floater too big for the room leaves the docked window docked.
@Suite struct ArrangerDesktopTests {
    @Test func anExcludedFloatingWindowIsNeverParked() async throws {
        var harness = await docked()
        let excludedBundle = "com.example.excluded"
        let x = ref(5, pid: 901, bundleID: excludedBundle), frame = Rect(x: 1100, y: 300, width: 200, height: 150)
        await harness.fake.addApp(FakeApp(pid: 901, bundleID: excludedBundle))
        await harness.fake.open(.standard(id: 5, pid: 901, frame: frame))
        await harness.fake.refreshAll()
        await harness.fake.advance(by: .milliseconds(300))  // a new window settles before it is reported
        await harness.fake.refreshAll()
        await harness.settle()
        #expect(harness.arranger.world[key]?.desktop.contains(x) == true)
        await harness.fake.setExcluded([excludedBundle])
        await harness.settle()

        #expect(await harness.fake.parked.isEmpty)
        // D-29: the Arranger sends nothing for x for the window system's filter to drop.
        #expect(await harness.fake.dropped.isEmpty)
        #expect(await harness.frame(x) == frame)
        #expect(harness.arranger.homeFrames[x.identity] == nil)
    }
}

extension ArrangerDesktopTests {
    /// G-03-6: f's 768 pt minimum cannot sit beside a's 800 pt one (1424 inner width), so f stops sizing the Desktop
    /// tile instead of a floating off its tile.
    @Test func aFloaterTooBigForTheRoomLeavesTheDockedWindowDocked() async throws {
        var harness = await docked()
        func learned(_ window: WindowRef, width: Double) throws -> WindowInfo {
            var info = try #require(harness.arranger.windows[window.identity])
            info.learnedMinimum = Size(width: width, height: 100)
            return info
        }
        await harness.send(.event(.windowChanged(try learned(a, width: 800))))

        let effects = await harness.send(.event(.windowChanged(try learned(f, width: 768))))

        #expect(!effects.contains { if case .notice(.lostRoom) = $0 { true } else { false } })
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.tree.state(of: a) == .present)
        #expect(desk.desktop.contains(f))
        let again = await harness.send(.event(.windowChanged(try learned(f, width: 768))))
        #expect(setFrames(again).isEmpty)
    }
}
