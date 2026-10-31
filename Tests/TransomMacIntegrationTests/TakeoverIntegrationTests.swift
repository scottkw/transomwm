import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomPrivate
import Testing

/// OVER-02 / OVER-03 live: the takeover disables macOS's Mission Control shortcuts, their chords open and close the
/// overview, and lifting gives macOS its shortcuts back. VM only: it changes symbolic-hotkey state and posts keys. Each
/// test restores the hotkeys it recorded whatever happens (T-06-26), and keeps its defaults in a throwaway suite.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct TakeoverIntegrationTests {
    static let watched: [Int32] = [32, 108, 113]

    init() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    private func suite() -> (UserDefaults, String) {
        let name = "transom.takeover.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func states() -> [Int32: Bool] {
        Dictionary(uniqueKeysWithValues: Self.watched.compactMap { id in SymbolicHotKeys.isEnabled(id).map { (id, $0) } })
    }

    private func restoreDirectly(_ originals: [Int32: Bool]) {
        for (id, enabled) in originals { SymbolicHotKeys.setEnabled(id, enabled) }
    }

    /// Key-down carries the hotkey's flags with fn (06-07); key-up carries none.
    private func press(_ keyCode: CGKeyCode, flags: UInt64) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        down?.flags = CGEventFlags(rawValue: flags)
        down?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    @Test(.timeLimit(.minutes(1)))
    func missionControlKeysOpenTheOverviewAndLiftRestores() async throws {
        let originals = states()
        defer { restoreDirectly(originals) }
        try #require(originals[32] != nil && originals[108] != nil, "SymbolicHotKeys unavailable: \(originals)")
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }

        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()
        _ = await waitUntil(timeout: .seconds(3)) { arrange.arranger.windows.values.contains { $0.window.pid == fixturePID } }

        let takeover = MissionControlTakeover(defaults: defaults)
        arrange.takeover = takeover
        try #require(takeover.apply(), "apply failed: \(takeover.state)")
        let taken: [Int32] = if case .on(let keys) = takeover.state { keys } else { [] }
        print("takeover taken IDs: \(taken), originals \(originals)")
        for id in taken { #expect(SymbolicHotKeys.isEnabled(id) == false, "hotkey \(id) still enabled") }
        #expect(takeover.storedOriginals == originals.filter { taken.contains($0.key) })

        // F3 (108), ⌃↑ (32) and ⇧F3 (113): each opens the overview, then closes it. The overview's key panel is up
        // for each close press, so this also shows Carbon hotkeys fire while it is key.
        let chords: [(id: Int32, key: CGKeyCode, flags: UInt64)] = [(108, 160, 0x800000), (32, 126, 0x840000), (113, 160, 0x820000)]
        for chord in chords where taken.contains(chord.id) {
            press(chord.key, flags: chord.flags)
            let opened = await waitUntil(timeout: .seconds(1)) {
                dispatchAppKitEvents()
                return arrange.overviewController?.isOpen == true
            }
            #expect(opened, "hotkey \(chord.id)'s chord did not open the overview")
            try await Task.sleep(for: .milliseconds(400))  // past the open move
            press(chord.key, flags: chord.flags)
            let closed = await waitUntil(timeout: .seconds(1)) {
                dispatchAppKitEvents()
                return arrange.overviewController?.isOpen == false
            }
            #expect(closed, "hotkey \(chord.id)'s chord did not dismiss the overview while its panel was key")
            print("hotkey \(chord.id): opened \(opened), dismissed while key \(closed)")
        }

        takeover.lift(reason: .toggleOff)
        #expect(states() == originals, "lift did not restore the originals")
        #expect(takeover.storedOriginals == nil, "lift left originals stored")
        #expect(takeover.state == .off)
    }
}
