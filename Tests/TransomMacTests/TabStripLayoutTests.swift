@testable import TransomMac
import TransomModel
import Testing

/// UI-SPEC Surface 2 geometry: group buttons, equal tabs, titled / icon-only / overflow, the narrow rule.
@Suite struct TabStripLayoutTests {
    private let three: [TabStripButton] = [.closeGroup, .minimizeGroup, .floatGroup]

    @Test func twoTabsInAWideStripAreTitledAfterTheButtons() {
        let layout = TabStripLayout(width: 400, tabCount: 2, selected: 0, buttons: three)
        #expect(layout.buttonRects.map(\.x) == [4, 28, 52])
        #expect(layout.buttonRects.allSatisfy { $0.y == 4 && $0.width == 20 && $0.height == 20 })
        #expect(layout.mode == .titled)
        #expect(layout.overflow == nil)
        let width = (316.0 - 4) / 2
        #expect(layout.tabRects == [0: Rect(x: 80, y: 4, width: width, height: 20), 1: Rect(x: 80 + width + 4, y: 4, width: width, height: 20)])
        #expect(layout.tabRects[1].map { $0.x + $0.width } == 396)
    }

    @Test func tabsUnder96ptAreIconOnly() {
        let layout = TabStripLayout(width: 300, tabCount: 4, selected: 0, buttons: three)
        #expect(layout.mode == .iconOnly)
        #expect(layout.tabRects.count == 4 && layout.overflow == nil)
        #expect(layout.tabRects.values.allSatisfy { $0.width >= 32 && $0.width < 96 })
    }

    @Test func tabsUnder32ptOverflowIntoAMenu() throws {
        let layout = TabStripLayout(width: 200, tabCount: 8, selected: 0, buttons: three)
        let overflow = try #require(layout.overflow)
        #expect(overflow.button == Rect(x: 176, y: 4, width: 20, height: 20))
        #expect(layout.mode == .iconOnly)
        #expect(layout.tabRects == [0: Rect(x: 80, y: 4, width: 32, height: 20), 1: Rect(x: 116, y: 4, width: 32, height: 20)])
        #expect(overflow.hidden == [2, 3, 4, 5, 6, 7])
    }

    @Test func theSelectedTabTakesTheLastVisibleSlot() throws {
        let layout = TabStripLayout(width: 200, tabCount: 8, selected: 5, buttons: three)
        #expect(layout.tabRects == [0: Rect(x: 80, y: 4, width: 32, height: 20), 5: Rect(x: 116, y: 4, width: 32, height: 20)])
        #expect(try #require(layout.overflow).hidden == [1, 2, 3, 4, 6, 7])
    }

    @Test func aStripUnder116ptHidesTheButtons() {
        let layout = TabStripLayout(width: 110, tabCount: 2, selected: 0, buttons: three)
        #expect(layout.buttonRects.isEmpty)
        #expect(layout.tabRects[0]?.x == 4)
        #expect(layout.tabRects[1].map { $0.x + $0.width } == 106)
    }
}
