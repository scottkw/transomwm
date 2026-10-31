import AppKit
import Foundation
import KeyboardShortcuts
import TransomEngine
@testable import TransomMac
import TransomPrivate
import Testing

/// Stands in for SkyLight and Carbon: records every call, so no test changes the host's Mission Control shortcuts or
/// registers a hotkey. Starts with 32 = ⌃↑ and 108 = F3, both enabled; IDs in `stuck` ignore writes (a refused apply).
@MainActor final class FakeHotKeys: HotKeyBackend {
    var isAvailable = true
    var enabled: [Int32: Bool] = [32: true, 108: true]
    var values: [Int32: SymbolicHotKeys.Value] = [:]
    var stuck: Set<Int32> = []
    private(set) var writes: [Int32: [Bool]] = [:]
    private(set) var registered: [KeyboardShortcuts.Shortcut] = []

    func isEnabled(_ id: Int32) -> Bool? { enabled[id] }
    func setEnabled(_ id: Int32, _ on: Bool) {
        writes[id, default: []].append(on)
        guard !stuck.contains(id) else { return }
        enabled[id] = on
    }
    func value(_ id: Int32) -> SymbolicHotKeys.Value? { values[id] }
    func events(for shortcut: KeyboardShortcuts.Shortcut) -> AsyncStream<KeyboardShortcuts.EventType> {
        registered.append(shortcut)
        return AsyncStream { $0.finish() }
    }
}

/// OVER-02, D-06 (Surface 5): the O2 menu choice → explanation alert → takeover → Debug S5, on an injected backend.
@Suite(.serialized) @MainActor struct TakeoverMenuTests {
    /// A throwaway defaults suite, never Transom's real one.
    static func defaults() -> (UserDefaults, () -> Void) {
        let suite = "com.eightabyte.transom.tests.takeover.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    static func takeover(_ defaults: UserDefaults, _ backend: FakeHotKeys, zoomOn: Bool = true) -> MissionControlTakeover {
        MissionControlTakeover(defaults: defaults, backend: backend, zoomOn: zoomOn)
    }

    static func s5(_ takeover: MissionControlTakeover) -> String { OverviewCopy.takeoverLine(takeover.debugLine) }

    @Test func firstChoiceExplainsThenTurnsOnAndLaterChoicesSkipTheAlert() {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let backend = FakeHotKeys()
        backend.values = [32: .init(keyCode: 126, modifiers: 0x840000)]
        let takeover = Self.takeover(defaults, backend)
        var announced: [String] = []
        takeover.announce = { announced.append($0) }
        #expect(Self.s5(takeover) == "Mission Control takeover: off")

        var alerts = 0
        takeover.choose { answered in
            alerts += 1
            #expect(OverviewCopy.takeoverAlertInformative(takeover.currentChord).hasPrefix("The Mission Control key (F3) and Control-Up Arrow will"))
            answered(true)
        }
        #expect(alerts == 1)
        #expect(backend.writes[32] == [false] && backend.writes[108] == [false])
        #expect(takeover.isOn)
        #expect(Self.s5(takeover) == "Mission Control takeover: on, F3 and \u{2303}\u{2191}")
        #expect(backend.registered.count == 2, "⌃↑ and F3 caught as Carbon hotkeys")
        #expect(announced == ["Mission Control keys show the overview"])

        takeover.choose { _ in Issue.record("turning off never explains") }
        #expect(backend.enabled == [32: true, 108: true], "originals restored")
        #expect(takeover.storedOriginals == nil)
        #expect(Self.s5(takeover) == "Mission Control takeover: off")
        #expect(announced.last == "Mission Control keys restored")

        takeover.choose { _ in Issue.record("the explanation was confirmed before") }
        #expect(takeover.isOn)
    }

    @Test func notNowLeavesItOffAndAsksAgain() {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let backend = FakeHotKeys()
        let takeover = Self.takeover(defaults, backend)
        takeover.choose { $0(false) }
        #expect(!takeover.isOn && takeover.preferenceOn == false)
        #expect(backend.writes.isEmpty)
        var asked = false
        takeover.choose { asked = true; $0(true) }
        #expect(asked && takeover.isOn)
    }

    @Test func keysFollowHotkey32() {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let backend = FakeHotKeys()
        let takeover = Self.takeover(defaults, backend)
        backend.values = [32: .init(keyCode: 126, modifiers: 0x840000 | 0x100000)]  // ⌃⌘↑
        guard case .custom(let glyphs) = takeover.currentChord else {
            Issue.record("not custom: \(takeover.currentChord)")
            return
        }
        #expect(glyphs.contains("\u{2318}") && glyphs.contains("\u{2303}"))
        backend.enabled[32] = false
        #expect(takeover.currentChord == .off)
        takeover.setPreference(true)
        #expect(Self.s5(takeover) == "Mission Control takeover: on, F3", "32 turned off by the user: only F3 is taken")
        #expect(backend.writes[32] == nil)
    }

    @Test func unavailableBackendReadsUnavailable() {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let backend = FakeHotKeys()
        backend.isAvailable = false
        let takeover = Self.takeover(defaults, backend)
        takeover.launchRestore()
        #expect(!takeover.isAvailable)
        #expect(Self.s5(takeover) == "Mission Control takeover: unavailable (private API off)")
        takeover.setPreference(true)
        #expect(backend.writes.isEmpty)
    }

    @Test func o2SitsAfterFrameDesktopBeforeAllowWindowPreviews() {
        let menu = CommandMenu { _ in }
        let item = { (title: String) in NSMenuItem(title: title, action: nil, keyEquivalent: "") }
        let titles = menu.zoomSection(
            enabled: true, framingWindow: false, framingDesktop: false, takeover: item("Replace Mission Control"),
            previews: item("Allow Window Previews\u{2026}"), toggle: item("Turn Off Zoom")
        ).map(\.title)
        #expect(Array(titles.suffix(4)) == ["Frame Desktop", "Replace Mission Control", "Allow Window Previews\u{2026}", "Turn Off Zoom"])
        let off = menu.zoomSection(
            enabled: false, framingWindow: false, framingDesktop: false, takeover: item("Replace Mission Control"), previews: nil,
            toggle: item("Turn On Zoom"))
        #expect(!off.map(\.title).contains("Replace Mission Control"), "rendered only with zoom on")
    }
}
