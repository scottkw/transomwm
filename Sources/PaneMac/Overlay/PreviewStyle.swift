import PaneEngine
import PaneModel

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
    static let dash: [Double] = [8, 4]

    /// The layers for `state`, back to front. Increase Contrast multiplies every fill alpha by 1.5 and makes every
    /// border opaque.
    static func layers(for state: PreviewState, increaseContrast: Bool) -> [LayerStyle] {
        let layers: [LayerStyle] =
            switch state {
            case .dock(let rect):
                [LayerStyle(rect: rect, fill: .accent, fillAlpha: 0.20, border: .accent, borderAlpha: 0.85)]
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
            }
        guard increaseContrast else { return layers }
        return layers.map { layer in
            var layer = layer
            layer.fillAlpha *= 1.5
            layer.borderAlpha = 1
            return layer
        }
    }

    /// The label shows only with 16 pt of clearance on every side (UI-SPEC overlay label).
    static func showsLabel(in rect: Size, labelSize: Size) -> Bool {
        rect.width >= labelSize.width + 2 * labelClearance && rect.height >= labelSize.height + 2 * labelClearance
    }

    private static func ghost(_ rect: Rect, label: Label?) -> LayerStyle {
        LayerStyle(rect: rect, fill: .label, fillAlpha: 0.08, border: .label, borderAlpha: 0.50, dash: dash, label: label)
    }
}
