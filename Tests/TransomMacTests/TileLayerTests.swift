import AppKit
@testable import TransomMac
import Testing

/// The brightest opaque pixel of `image` drawn into a bitmap while `drawing` is the current drawing appearance.
@MainActor private func brightest(_ image: NSImage, drawing: NSAppearance) throws -> Double {
    let rep = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawing.performAsCurrentDrawingAppearance { image.draw(in: NSRect(x: 0, y: 0, width: 80, height: 24)) }
    NSGraphicsContext.restoreGraphicsState()
    var best = 0.0
    for x in 0..<80 {
        for y in 0..<24 {
            guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
            best = max(best, (color.redComponent + color.greenComponent + color.blueComponent) / 3)
        }
    }
    return best
}

/// UAT 04 item 7: a fallback tile's title keeps the appearance it was made in, however late its image is drawn.
@Suite @MainActor struct TileLayerTests {
    @Test func aDarkTitleStaysLightTextWhenDrawnLater() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))
        var image: NSImage?
        dark.performAsCurrentDrawingAppearance { image = TileLayer.text("WWWWWW", size: CGSize(width: 80, height: 24)) }

        #expect(try brightest(try #require(image), drawing: light) > 0.8, "labelColor in dark mode is light text")
    }
}

/// 07 UI-SPEC Surface 6: the stage strip's layout at each scale.
@Suite struct StripLayerStyleTests {
    @Test func atFullScaleThreeChipsShareTheWidthWithIcons() {
        let style = StripLayerStyle.layout(frame: CGRect(x: 0, y: 0, width: 400, height: 28), scale: 1, count: 3)
        #expect(style.radius == 8)
        #expect(style.chips.count == 3)
        #expect(Set(style.chips.map(\.width)).count == 1, "the chips are not equal: \(style.chips)")
        #expect(style.chips.first?.minX == 4 && style.chips.last?.maxX == 396, "the chips do not sit inside 4 pt padding")
        #expect(style.showsIcons && !style.fillOnly)
    }

    @Test func atAQuarterTheRadiusFloorsAt2AndIconsHide() {
        let style = StripLayerStyle.layout(frame: CGRect(x: 0, y: 0, width: 100, height: 7), scale: 0.25, count: 3)
        #expect(style.radius == 2)
        #expect(!style.showsIcons, "a 4 pt icon showed")
        #expect(!style.fillOnly, "a 7 pt strip drew only its fill")
    }

    @Test func belowFourPointsTallOnlyTheFillIsDrawn() {
        let style = StripLayerStyle.layout(frame: CGRect(x: 0, y: 0, width: 40, height: 2.8), scale: 0.1, count: 3)
        #expect(style.fillOnly)
    }
}
