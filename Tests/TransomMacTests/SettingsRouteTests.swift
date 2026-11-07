import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// SHIP-08, D-04: a settings URL passes the gate and reaches the Settings window's one entry point, with no window built.
/// The controller is never started.
@Suite @MainActor struct SettingsRouteTests {
    private func route(_ string: String) throws -> (reply: String, effects: [ArrangerEffect], calls: [(SettingsPane?, CommandSource)]) {
        let gate = CommandGate(scheme: "transom")
        let url = try #require(URL(string: string))
        guard case .command(let command) = gate.admitOpened(url, at: .now) else {
            Issue.record("\(string) was not admitted")
            return ("", [], [])
        }
        let controller = ArrangeController(system: AXWindowSystem())
        var calls: [(SettingsPane?, CommandSource)] = []
        controller.openSettings = { calls.append(($0, $1)) }
        let decision = controller.decide(command, from: .url)
        return (decision.reply, decision.effects, calls)
    }

    @Test func aSettingsURLOpensSettingsOnItsPane() throws {
        let routed = try route("transom://settings?pane=updates")
        #expect(routed.effects.isEmpty)
        #expect(routed.reply == CLIProtocol.ok)
        #expect(routed.calls.count == 1)
        #expect(routed.calls.first?.0 == .updates)
        #expect(routed.calls.first?.1 == .url)
    }

    @Test func aBareSettingsURLOpensTheLastTab() throws {
        let routed = try route("transom://settings")
        #expect(routed.effects.isEmpty)
        #expect(routed.reply == CLIProtocol.ok)
        #expect(routed.calls.count == 1)
        #expect(routed.calls.first?.0 == nil)
        #expect(routed.calls.first?.1 == .url)
    }
}
