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
