import Foundation
@testable import TransomMac
import Testing

/// SHIP-06, D-13, D-14, UI-SPEC Surface 4 and Tab 6: the menu-bar view controls are a pure layout of the Menu Bar
/// choices and the camera. No test creates a real status item.
@Suite @MainActor struct ViewControlItemsTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.menubar.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func layout(
        _ items: [MenuBarItem], iconOnly: Bool = false, zoomOn: Bool = true, paused: Bool = false, slots: [Int] = [], current: Int? = nil,
        back: Bool = true, forward: Bool = true
    ) -> [ViewControlSpec] {
        ViewControlItems.layout(
            items: items, iconOnly: iconOnly, zoomOn: zoomOn, paused: paused, slots: slots, current: current, backAvailable: back,
            forwardAvailable: forward)
    }

    @Test func nothingShowsByDefault() throws {
        try withDefaults { defaults in
            let preference = MenuBarPreference(defaults: defaults)
            #expect(preference.items.map(\.control) == [.back, .forward, .views])
            #expect(preference.items.allSatisfy { !$0.enabled })
            #expect(!preference.iconOnly)
            #expect(layout(preference.items, slots: [1, 2]).isEmpty)
        }
    }

    @Test func backEnabledGivesOneBackControlWhileZoomIsOn() throws {
        try withDefaults { defaults in
            let preference = MenuBarPreference(defaults: defaults)
            var changes = 0
            preference.onChange = { changes += 1 }
            preference.setEnabled(.back, true)
            #expect(changes == 1)
            #expect(MenuBarPreference(defaults: defaults).items == preference.items)
            let specs = layout(preference.items)
            #expect(specs == [ViewControlSpec(kind: .back, symbol: "chevron.backward", description: "Back", appearsDisabled: false)])
            #expect(specs.first?.command == .camera(.back))
        }
    }

    @Test func zoomOffHidesEveryControl() {
        let all = MenuBarControl.allCases.map { MenuBarItem(control: $0, enabled: true) }
        #expect(layout(all, zoomOn: false, slots: [1, 3], current: 3).isEmpty)
    }

    @Test func aCorruptStoredListIsReplacedByTheDefault() throws {
        let duplicate = Data(#"[{"control":"back","enabled":true},{"control":"back","enabled":true},{"control":"views","enabled":true}]"#.utf8)
        for stored in [duplicate, Data("nonsense".utf8)] as [Any] + ["back"] {
            try withDefaults { defaults in
                defaults.set(stored, forKey: MenuBarPreference.itemsKey)
                #expect(MenuBarPreference(defaults: defaults).items == MenuBarPreference.defaultItems)
                #expect(defaults.object(forKey: MenuBarPreference.itemsKey) == nil)
            }
        }
    }
}
