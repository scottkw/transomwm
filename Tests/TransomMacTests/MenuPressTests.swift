@testable import TransomMac
import Testing

private func item(_ character: String?, _ modifiers: Int?, depth: Int, enabled: Bool = true) -> MenuPress.ItemFact {
    MenuPress.ItemFact(commandCharacter: character, modifiers: modifiers, depth: depth, enabled: enabled)
}

/// RESEARCH Pattern 14: the ⌘-only N item (kAXMenuItemModifierNone) is found by its key equivalent, never its title.
@Suite struct MenuPressTests {
    @Test func theFirstEnabledCommandOnlyNIsPicked() {
        let facts = [item("N", 2, depth: 1), item("O", 0, depth: 2), item("N", 0, depth: 2), item("N", 0, depth: 2)]
        #expect(MenuPress.firstCommandN(facts) == 2)
    }

    @Test func disabledShiftedAndTooDeepItemsAreSkipped() {
        let facts = [item("N", 0, depth: 2, enabled: false), item("N", 1, depth: 2), item("N", 0, depth: 4), item("N", 0, depth: 3)]
        #expect(MenuPress.firstCommandN(facts) == 3)
    }

    @Test func noMatchIsNil() {
        #expect(MenuPress.firstCommandN([item("O", 0, depth: 2), item("N", 2, depth: 2), item(nil, nil, depth: 2)]) == nil)
        #expect(MenuPress.firstCommandN([]) == nil)
    }
}
