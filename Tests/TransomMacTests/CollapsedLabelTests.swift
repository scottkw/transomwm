import CoreGraphics
@testable import TransomMac
import Testing

/// UI-SPEC Surface 7: a collapsed block's label card under its icon, and how it falls back on smaller blocks.
@Suite struct CollapsedLabelTests {
    private static let full = CGSize(width: 120, height: 41)
    private static let line = CGSize(width: 120, height: 24)

    private func fit(_ width: CGFloat, _ height: CGFloat, icon: CGFloat = 32) -> CollapsedBlockView.LabelFit {
        CollapsedBlockView.labelFit(block: CGSize(width: width, height: height), icon: icon, fullCard: Self.full, lineCard: Self.line)
    }

    @Test func aWideBlockShowsTheFullCard() {
        #expect(fit(480, 600) == .full)
    }

    @Test func aShortBlockShowsLineOneOnly() {
        // 32 + 8 + 41 + 32 = 113 for the full card; 32 + 8 + 24 + 32 = 96 for line 1.
        #expect(fit(480, 100) == .lineOne)
    }

    @Test func aThinStripShowsIconOnly() {
        #expect(fit(480, 40) == .iconOnly)
        #expect(fit(100, 600) == .iconOnly)  // narrower than the card + 32
        #expect(fit(480, 40, icon: 0) == .iconOnly)
    }

    @Test func theThresholdIsInclusive() {
        #expect(fit(152, 113) == .full)
        #expect(fit(152, 112) == .lineOne)
        #expect(fit(152, 96) == .lineOne)
        #expect(fit(152, 95) == .iconOnly)
        #expect(fit(151, 600) == .iconOnly)
    }

    @Test func theLinesAreTitleAndCollapsed() {
        let lines = CollapsedBlockView.labelLines(title: "Downloads", appName: "Safari", groupSize: 1)
        #expect(lines.0 == "Downloads")
        #expect(lines.1 == "Collapsed")
    }

    @Test func anEmptyTitleUsesTheAppName() {
        #expect(CollapsedBlockView.labelLines(title: "", appName: "Safari", groupSize: 1).0 == "Safari")
        let long = String(repeating: "a", count: 40)
        #expect(CollapsedBlockView.labelLines(title: "", appName: long, groupSize: 1).0 == String(repeating: "a", count: 32) + "\u{2026}")
    }

    @Test func aGroupSaysHowManyWindows() {
        let lines = CollapsedBlockView.labelLines(title: "Downloads", appName: "Safari", groupSize: 3)
        #expect(lines.0 == "Downloads")
        #expect(lines.1 == "3 windows, collapsed")
    }
}
