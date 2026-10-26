import PaneEngine
import PaneModel

/// The drop preview's look per state (UI-SPEC Color, overlay recipe), as plain values.
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

    static func layers(for state: PreviewState, increaseContrast: Bool) -> [LayerStyle] { [] }

    static func showsLabel(in rect: Size, labelSize: Size) -> Bool { false }
}
