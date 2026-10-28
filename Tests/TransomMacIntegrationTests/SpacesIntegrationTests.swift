import TransomMac
import TransomPrivate
import Testing

/// D-15 live: the read-only SkyLight lookup puts the fixture's shown tab and its standard window on one Space. A
/// hidden native tab reports either no Space or the group's, never another one.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct SpacesIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aShownTabAndAStandardWindowShareOneSpaceAndTheHiddenTabNeverReportsAnother() async throws {
        let fixture = try await FixtureProcess.launch(["tabs:2", "standard"])
        defer { fixture.terminate() }
        let tabs = fixture.windows.filter { $0.kind == "tabs:2" }
        let standard = try #require(fixture.windows.first { $0.kind == "standard" })
        #expect(tabs.count == 2)
        func shownTab() -> FixtureWindow? {
            let onScreen = Set((CGWindowList.snapshot() ?? []).filter { $0.pid == fixture.pid && $0.onScreen }.map(\.windowID))
            return tabs.first { onScreen.contains($0.id) }
        }
        #expect(await waitUntil(timeout: .seconds(2)) { shownTab() != nil }, "no tab of the fixture is onscreen")
        let shown = try #require(shownTab())
        let hidden = try #require(tabs.first { $0.id != shown.id })

        let spaces = try #require(SkyLightSpaces.spaces(of: [shown.id, hidden.id, standard.id]), "Spaces lookup unavailable")
        let shownSpaces = spaces[shown.id] ?? []
        #expect(!shownSpaces.isEmpty, "the shown tab reported no Space")
        #expect(spaces[standard.id] == shownSpaces, "the standard window is not on the shown tab's Space")
        let hiddenSpaces = spaces[hidden.id] ?? []
        let branch = hiddenSpaces.isEmpty ? "no Space (empty set)" : "the group's Space"
        print("SpacesIntegrationTests: the hidden tab reported \(branch)")
        #expect(hiddenSpaces.isEmpty || hiddenSpaces == shownSpaces, "the hidden tab reported \(hiddenSpaces), not \(branch)")
    }

    /// D-25: the main display's current Space is the one Space a visible fixture window is on, and `Displays`
    /// reports it as `currentSpaceID`. Reads only; no Space switch.
    @Test(.timeLimit(.minutes(1)))
    func theMainDisplaysCurrentSpaceIsTheSpaceOfAVisibleWindow() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let window = try #require(fixture.windows.first)
        let main = try #require(Displays.current().first)
        let current = try #require(SkyLightSpaces.currentSpace(displayUUID: main.uuid), "no current Space for the main display")
        #expect(SkyLightSpaces.spaces(of: [window.id])?[window.id] == [current])
        #expect(main.currentSpaceID == current)
    }
}
