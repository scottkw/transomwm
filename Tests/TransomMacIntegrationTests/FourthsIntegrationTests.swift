import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// TILE-23 on real windows, through the same command every route sends. VM only: it moves windows.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "moves real windows; VM only"))
@MainActor struct FourthsIntegrationTests {
    /// Connects to the window server first, as ZoomSettleIntegrationTests does.
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(1)))
    func theCommandDocksAFloatingWindowAsTheFirstColumn() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await LiveArrange.start(fixture)
        defer { withExtendedLifetime(arrange) {} }
        let ref = try #require(refs.first)

        await arrange.dispatch(.dockFourth(.first, .horizontal), focused: ref)

        let key = try #require(arrange.arranger.deskKey(of: ref))
        let desk = try #require(arrange.arranger.world[key])
        let root = try #require(desk.tree.root)
        guard case let .split(axis, _, weights)? = desk.tree.node(root) else {
            Issue.record("the root is not a split: \(desk.tree)")
            return
        }
        #expect(axis == .horizontal)
        #expect(weights.count == 2)
        #expect(abs(weights[0] - 0.25) <= 1e-9 && abs(weights[1] - 0.75) <= 1e-9, "root weights \(weights)")
        let visible = try LiveArrange.visibleFrame()
        let planned = try #require(try Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames[ref])
        let settled = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, 0) else { return false }
            return LiveArrange.near(now, planned)
        }
        #expect(settled, "the window never reached \(planned)")
    }
}
