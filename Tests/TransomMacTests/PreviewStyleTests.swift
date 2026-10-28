@testable import TransomMac
import TransomEngine
import TransomModel
import Testing

private let r = Rect(x: 100, y: 100, width: 400, height: 300)
private let o = Rect(x: 600, y: 100, width: 400, height: 300)

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

/// UI-SPEC Color: the overlay recipe per state, Increase Contrast and the label clearance rule.
@Suite struct PreviewStyleTests {
    @Test func dockIsAnAccentTintWithASolidBorder() throws {
        let layers = PreviewStyle.layers(for: .dock(r), increaseContrast: false)
        let layer = try #require(layers.first)
        #expect(layers.count == 1)
        #expect(layer.rect == r && layer.fill == .accent && near(layer.fillAlpha, 0.20))
        #expect(layer.border == .accent && near(layer.borderAlpha, 0.85) && layer.borderWidth == 2 && layer.dash == nil)
        #expect(layer.cornerRadius == 12 && layer.label == nil)
    }

    @Test func swapShowsTheLabelledTargetOverTheDashedOrigin() throws {
        let layers = PreviewStyle.layers(for: .swap(target: r, origin: o), increaseContrast: false)
        #expect(layers.count == 2)
        let target = try #require(layers.first { $0.rect == r }), origin = try #require(layers.first { $0.rect == o })
        #expect(target.fill == .accent && near(target.fillAlpha, 0.20) && near(target.borderAlpha, 0.85) && target.dash == nil)
        #expect(target.label == PreviewStyle.Label(text: "Swap", glyph: "arrow.left.arrow.right", glyphRole: .label))
        #expect(origin.fill == .accent && near(origin.fillAlpha, 0.10) && near(origin.borderAlpha, 0.85) && origin.dash == [8, 4])
        #expect(origin.label == nil)
        #expect(layers.last?.rect == r, "the target is drawn under the origin")
    }

    @Test func blockedIsRedWithTheNoRoomLabel() throws {
        let layer = try #require(PreviewStyle.layers(for: .blocked(r), increaseContrast: false).first)
        #expect(layer.fill == .red && near(layer.fillAlpha, 0.12) && layer.border == .red && near(layer.borderAlpha, 0.85))
        #expect(layer.dash == nil)
        #expect(layer.label == PreviewStyle.Label(text: "Not enough room", glyph: "nosign", glyphRole: .red))
    }

    @Test(arguments: [PreviewState.snapBack(r, label: nil), .clamp(r)])
    func ghostsAreANeutralDashedTint(state: PreviewState) throws {
        let layer = try #require(PreviewStyle.layers(for: state, increaseContrast: false).first)
        #expect(layer.fill == .label && near(layer.fillAlpha, 0.08) && layer.border == .label && near(layer.borderAlpha, 0.50))
        #expect(layer.dash == [8, 4] && layer.label == nil)
    }

    @Test func theHiddenDesktopGhostCarriesItsLabel() throws {
        let layer = try #require(PreviewStyle.layers(for: .snapBack(r, label: "Show the Desktop Tile to float windows"), increaseContrast: false).first)
        #expect(layer.label?.text == "Show the Desktop Tile to float windows")
        #expect(layer.fill == .label && layer.dash == [8, 4])
    }

    @Test func increaseContrastRaisesFillsByHalfAndMakesBordersOpaque() throws {
        let dock = try #require(PreviewStyle.layers(for: .dock(r), increaseContrast: true).first)
        #expect(near(dock.fillAlpha, 0.30) && near(dock.borderAlpha, 1))
        let blocked = try #require(PreviewStyle.layers(for: .blocked(r), increaseContrast: true).first)
        #expect(near(blocked.fillAlpha, 0.18) && near(blocked.borderAlpha, 1))
        let ghost = try #require(PreviewStyle.layers(for: .clamp(r), increaseContrast: true).first)
        #expect(near(ghost.fillAlpha, 0.12) && near(ghost.borderAlpha, 1))
        let origin = try #require(PreviewStyle.layers(for: .swap(target: r, origin: o), increaseContrast: true).first { $0.rect == o })
        #expect(near(origin.fillAlpha, 0.15) && near(origin.borderAlpha, 1))
    }

    @Test func theLabelHidesWithoutSixteenPointsOfClearanceOnEachSide() {
        let label = Size(width: 60, height: 20)
        #expect(PreviewStyle.showsLabel(in: Size(width: 92, height: 52), labelSize: label))
        #expect(!PreviewStyle.showsLabel(in: Size(width: 91, height: 52), labelSize: label))
        #expect(!PreviewStyle.showsLabel(in: Size(width: 92, height: 51), labelSize: label))
    }

    @Test func theRubberBandTargetAndPickRingFollowTheZoomRecipe() {
        let band = PreviewStyle.band(r, increaseContrast: false)
        #expect(band.fill == .label && near(band.fillAlpha, 0.08) && band.border == .label && near(band.borderAlpha, 0.50))
        #expect(band.borderWidth == 1 && band.cornerRadius == 0 && band.dash == nil)
        let target = PreviewStyle.rectTarget(r, increaseContrast: false)
        #expect(target.fill == .accent && near(target.fillAlpha, 0.20) && near(target.borderAlpha, 0.85))
        #expect(target.borderWidth == 2 && target.cornerRadius == 12)
        let ring = PreviewStyle.pickRing(r, radius: 10, increaseContrast: false)
        #expect(near(ring.fillAlpha, 0) && ring.border == .accent && near(ring.borderAlpha, 0.85) && ring.borderWidth == 2)
        #expect(ring.cornerRadius == 10)
        // Increase Contrast: 8 -> 12, 20 -> 30, every border opaque.
        #expect(near(PreviewStyle.band(r, increaseContrast: true).fillAlpha, 0.12))
        #expect(near(PreviewStyle.band(r, increaseContrast: true).borderAlpha, 1))
        #expect(near(PreviewStyle.rectTarget(r, increaseContrast: true).fillAlpha, 0.30))
        #expect(near(PreviewStyle.pickRing(r, radius: 10, increaseContrast: true).borderAlpha, 1))
    }
}
