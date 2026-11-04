import TransomEngine
import TransomModel

/// The drop preview's look per state (UI-SPEC Color, overlay recipe), as plain values so the recipe is unit-tested
/// without drawing. Colour roles become semantic NSColors only in PreviewPanel.
nonisolated enum PreviewStyle {
    enum ColorRole: Equatable, Sendable { case accent, red, label }

    struct Label: Equatable, Sendable {
        var text: String
        var glyph: String?
        var glyphRole: ColorRole
    }

    struct LayerStyle: Equatable, Sendable {
        var rect: Rect
        var fill: ColorRole
        var fillAlpha: Double
        var border: ColorRole
        var borderAlpha: Double
        var borderWidth: Double = 2
        var dash: [Double]?
        var cornerRadius: Double = 12
        var label: Label?
    }

    static let labelClearance = 16.0

    static let swapLabel = "Swap"
    static let blockedLabel = "Not enough room"
    /// The Collapsed state's glyph (UI-SPEC Surface 7), drawn by PreviewPanel's label like every preview glyph.
    static let collapsedGlyph = "arrow.down.right.and.arrow.up.left"
    /// The Group preview's glyph (UI-SPEC Surface 1).
    static let groupGlyph = "rectangle.topthird.inset.filled"
    static let dash: [Double] = [8, 4]

    /// The layers for `state`, back to front. Increase Contrast multiplies every fill alpha by 1.5 and makes every
    /// border opaque.
    static func layers(for state: PreviewState, increaseContrast: Bool) -> [LayerStyle] {
        let layers: [LayerStyle] =
            switch state {
            case .dock(let rect):
                [LayerStyle(rect: rect, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85)]
            case .fourth(let rect, let text):
                [
                    LayerStyle(
                        rect: rect, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85,
                        label: Label(text: text, glyph: nil, glyphRole: .label))
                ]
            case .swap(let target, let origin):
                [
                    LayerStyle(rect: origin, fill: .accent, fillAlpha: 0.10, border: .accent, borderAlpha: 0.85, dash: dash),
                    LayerStyle(
                        rect: target, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85,
                        label: Label(text: swapLabel, glyph: "arrow.left.arrow.right", glyphRole: .label)),
                ]
            case .blocked(let rect):
                [
                    LayerStyle(
                        rect: rect, fill: .red, fillAlpha: 0.12, border: .red, borderAlpha: 0.85,
                        label: Label(text: blockedLabel, glyph: "nosign", glyphRole: .red))
                ]
            case .snapBack(let rect, let text):
                [ghost(rect, label: text.map { Label(text: $0, glyph: nil, glyphRole: .label) })]
            case .clamp(let rect):
                [ghost(rect, label: nil)]
            case .collapsed(let rect, let text):
                [
                    LayerStyle(
                        rect: rect, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85,
                        label: Label(text: text, glyph: collapsedGlyph, glyphRole: .label))
                ]
            case .group(let frame, let strip, let text):
                // The frame, the strip band inset 2 pt inside its border, and the label centred in the content rect.
                [
                    LayerStyle(rect: frame, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85),
                    LayerStyle(
                        rect: Rect(x: strip.x + 2, y: strip.y + 2, width: max(0, strip.width - 4), height: max(0, strip.height - 2)),
                        fill: .accent, fillAlpha: 0.50, border: .accent, borderAlpha: 0, borderWidth: 0, cornerRadius: 8),
                ]
                    + (text.map {
                        [
                            LayerStyle(
                                rect: TabBand.content(of: frame), fill: .accent, fillAlpha: 0, border: .accent, borderAlpha: 0, borderWidth: 0,
                                label: Label(text: $0, glyph: groupGlyph, glyphRole: .label))
                        ]
                    } ?? [])
            }
        return increaseContrast ? layers.map(contrasted) : layers
    }

    /// The ⌘⇧-drag marquee (UI-SPEC Surface 4): a neutral tint, thin solid border, square corners.
    static func band(_ rect: Rect, increaseContrast: Bool) -> LayerStyle {
        let style = LayerStyle(rect: rect, fill: .label, fillAlpha: 0.08, border: .label, borderAlpha: 0.50, borderWidth: 1, cornerRadius: 0)
        return increaseContrast ? contrasted(style) : style
    }

    /// The area a ⌘⇧-drag would frame: the dock preview's look.
    static func rectTarget(_ rect: Rect, increaseContrast: Bool) -> LayerStyle {
        let style = LayerStyle(rect: rect, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85)
        return increaseContrast ? contrasted(style) : style
    }

    /// Pick mode's hover ring (Surface 5): border only, drawn inside the tile with the tile's radius.
    static func pickRing(_ rect: Rect, radius: Double, increaseContrast: Bool) -> LayerStyle {
        // Inset by half the 2 pt border, so the stroke lies inside the tile.
        let inside = Rect(x: rect.x + 1, y: rect.y + 1, width: max(rect.width - 2, 0), height: max(rect.height - 2, 0))
        let style = LayerStyle(rect: inside, fill: .accent, fillAlpha: 0, border: .accent, borderAlpha: 0.85, cornerRadius: radius)
        return increaseContrast ? contrasted(style) : style
    }

    /// Increase Contrast: every fill alpha × 1.5, every border opaque.
    private static func contrasted(_ layer: LayerStyle) -> LayerStyle {
        var layer = layer
        layer.fillAlpha *= 1.5
        layer.borderAlpha = 1
        return layer
    }

    /// The label shows only with 16 pt of clearance on every side (UI-SPEC overlay label).
    static func showsLabel(in rect: Size, labelSize: Size) -> Bool {
        rect.width >= labelSize.width + 2 * labelClearance && rect.height >= labelSize.height + 2 * labelClearance
    }

    private static func ghost(_ rect: Rect, label: Label?) -> LayerStyle {
        LayerStyle(rect: rect, fill: .label, fillAlpha: 0.08, border: .label, borderAlpha: 0.50, dash: dash, label: label)
    }
}
