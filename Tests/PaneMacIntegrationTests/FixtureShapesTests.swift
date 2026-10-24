import Foundation
import Testing

@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct FixtureShapesTests {
    @Test(.timeLimit(.minutes(1)))
    func theFixtureOpensEveryWindowShapeAndObeysCommands() async throws {
        let specs = ["standard", "nofullscreen", "borderless-floating", "utility-panel", "sheet", "minsize:250x150", "tabs:3"]
        let fixture = try await FixtureProcess.launch(specs)
        defer { fixture.terminate() }
        #expect(fixture.allLines().contains { $0.hasPrefix("ready pid=") })

        // sheet prints its host and its sheet-child; tabs:3 prints one line per tab.
        let expected: Int = 1 + 1 + 1 + 1 + 2 + 1 + 3
        #expect(fixture.windows.count == expected)
        #expect(Set(fixture.windows.map(\.id)).count == fixture.windows.count)
        #expect(fixture.windows.filter { $0.kind == "sheet-child" }.count == 1)
        #expect(fixture.windows.allSatisfy { $0.id > 0 })

        _ = try await fixture.send("move 0 200 200")
        _ = try await fixture.send("list")
        let moved = try #require(fixture.windows.first { $0.index == 0 })
        #expect(abs(moved.frame.x - 200) <= 1)
        #expect(abs(moved.frame.y - 200) <= 1)

        _ = try await fixture.send("quit")
        let exited = await waitUntil(timeout: .seconds(5)) { !fixture.process.isRunning }
        #expect(exited)
        #expect(fixture.process.terminationStatus == 0)
    }
}
