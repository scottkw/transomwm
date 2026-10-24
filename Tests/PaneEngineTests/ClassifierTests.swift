import Testing
import PaneEngine

/// A standard AppKit window: AXWindow/AXStandardWindow, every button present and enabled, CG layer 0.
private func standard(
    role: String? = "AXWindow", subrole: String? = "AXStandardWindow", modal: Bool = false, minimized: Bool = false,
    identifier: String? = nil, close: ButtonFact = .enabled, fullScreenButton: ButtonFact = .enabled,
    sheetAttached: Bool = false, layer: Int? = 0
) -> WindowSnapshot {
    WindowSnapshot(
        role: role, subrole: subrole, modal: modal, main: true, minimized: minimized, fullScreen: false, identifier: identifier,
        close: close, minimize: .enabled, zoom: .enabled, fullScreenButton: fullScreenButton, sheetAttached: sheetAttached,
        cg: layer.map { CGWindowFact(layer: $0, onScreen: true, alpha: 1) }
    )
}

private let app = "com.example.app"
private let disabled = ButtonFact(present: true, enabled: false)

struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let snapshot: WindowSnapshot
    var bundleID = app
    var appHidden = false
    let expected: Classification
    var testDescription: String { name }
}

private let dockable = Classification.window(.dockable, reliable: true)
private func never(_ reason: NeverDockReason) -> Classification { .window(.neverDock(reason), reliable: true) }

private let rows: [Row] = [
    Row(name: "Finder desktop scroll area", snapshot: standard(role: "AXScrollArea", subrole: nil), expected: .notAWindow),
    Row(name: "missing role", snapshot: standard(role: nil), expected: .notAWindow),
    Row(name: "standard window", snapshot: standard(), expected: dockable),
    Row(name: "layer 3 beats subrole", snapshot: standard(subrole: "AXUnknown", layer: 3), expected: never(.floatingLevel)),
    Row(name: "AXDialog", snapshot: standard(subrole: "AXDialog"), expected: never(.subrole)),
    Row(name: "AXSystemDialog", snapshot: standard(subrole: "AXSystemDialog"), expected: never(.subrole)),
    Row(name: "AXFloatingWindow", snapshot: standard(subrole: "AXFloatingWindow"), expected: never(.subrole)),
    Row(name: "AXUnknown", snapshot: standard(subrole: "AXUnknown"), expected: never(.subrole)),
    Row(name: "modal", snapshot: standard(modal: true), expected: never(.modal)),
    Row(name: "no close button", snapshot: standard(close: .absent), expected: never(.noCloseButton)),
    Row(name: "disabled close button", snapshot: standard(close: disabled), expected: dockable),
    Row(name: "no fullscreen button", snapshot: standard(fullScreenButton: .absent), expected: never(.noFullscreenButton)),
    Row(name: "disabled fullscreen button", snapshot: standard(fullScreenButton: disabled), expected: never(.noFullscreenButton)),
    Row(name: "fullscreen button optional for iTerm2", snapshot: standard(fullScreenButton: .absent),
        bundleID: "com.googlecode.iterm2", expected: dockable),
    Row(name: "Ghostty quick terminal identifier", snapshot: standard(identifier: "com.mitchellh.ghostty.quickTerminal"),
        expected: never(.subrole)),
    Row(name: "Xcode Open Quickly identifier", snapshot: standard(identifier: "open_quickly"), expected: never(.subrole)),
    Row(name: "minimised AXDialog is not judged", snapshot: standard(subrole: "AXDialog", minimized: true),
        expected: .window(.dockable, reliable: false)),
    Row(name: "hidden app is not judged", snapshot: standard(subrole: "AXDialog"), appHidden: true,
        expected: .window(.dockable, reliable: false)),
    Row(name: "sheet attached is not judged", snapshot: standard(fullScreenButton: disabled, sheetAttached: true),
        expected: .window(.dockable, reliable: false)),
    Row(name: "floating layer still wins while minimised", snapshot: standard(minimized: true, layer: 3),
        expected: .window(.neverDock(.floatingLevel), reliable: false)),
    Row(name: "no CG entry skips the layer rule", snapshot: standard(layer: nil), expected: dockable),
    Row(name: "no CG entry, dialog", snapshot: standard(subrole: "AXDialog", layer: nil), expected: never(.subrole)),
]

@Suite struct ClassifierTests {
    @Test(arguments: rows)
    func classifiesBySnapshot(row: Row) {
        #expect(Classifier.classify(row.snapshot, bundleID: row.bundleID, appHidden: row.appHidden) == row.expected)
    }

    @Test func overridesAreTakenFromTheArgument() {
        let none = ClassifierOverrides(fullscreenButtonOptional: [], neverDockIdentifiers: [])
        let ghostty = standard(identifier: "com.mitchellh.ghostty.quickTerminal")
        #expect(Classifier.classify(ghostty, bundleID: app, appHidden: false, overrides: none) == dockable)
        let iterm = standard(fullScreenButton: .absent)
        #expect(Classifier.classify(iterm, bundleID: "com.googlecode.iterm2", appHidden: false, overrides: none) == never(.noFullscreenButton))
    }
}
