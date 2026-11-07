import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// The update dot and the update menu items (09 UI-SPEC Surface 3 and 5, SHIP-07, D-10).
@MainActor struct UpdateMenuTests {
    static let release = UpdateRelease(
        version: "0.9.1", url: URL(string: "https://github.com/scottkw/transomwm/releases/download/v0.9.1/Transom-0.9.1-universal.dmg")!,
        size: 1, sha256: String(repeating: "ab", count: 32))

    @Test func theDotShowsOnlyWhileANewerReleaseIsKnownAndAccessIsReady() {
        let known: [UpdateStatus] = [
            .available(Self.release), .downloading(Self.release, fraction: nil), .verifying(Self.release), .opened(Self.release),
        ]
        for status in known {
            #expect(StatusItemController.showsDot(status, ready: true))
            #expect(!StatusItemController.showsDot(status, ready: false))
        }
        for status: UpdateStatus in [.idle, .checking, .current("0.9.0")] {
            #expect(!StatusItemController.showsDot(status, ready: true))
        }
    }

    @Test func theDotCompositeIsAnEighteenPointTemplate() throws {
        let glyph = try #require(NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Transom"))
        let image = StatusItemController.withUpdateDot(glyph)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "Transom")
    }

    @Test func aDMGInstallOffersUpdateTo() {
        let items = StatusItemController.updateItems(.available(Self.release), homebrew: false)
        #expect(items.map(\.title) == ["Update to Transom 0.9.1\u{2026}"])
        #expect(items.map(\.enabled) == [true])
        #expect(items.map(\.action) == [.downloadAndOpen])
    }

    @Test func aHomebrewInstallOffersTheBrewCommand() {
        let items = StatusItemController.updateItems(.opened(Self.release), homebrew: true)
        #expect(items.map(\.title) == ["Transom 0.9.1 is available", "Copy \u{201C}brew upgrade --cask transom\u{201D}"])
        #expect(items.map(\.enabled) == [false, true])
        #expect(items.map(\.action) == [.info, .copyBrewCommand])
        #expect(UpdateCopy.copyBrewTooltip == "Paste it in Terminal to update.")
        #expect(UpdateCopy.updateAvailableSuffix == ", update available")
    }

    @Test func noUpdateItemsWhenCurrent() {
        for status: UpdateStatus in [.idle, .checking, .current("0.9.0")] {
            #expect(StatusItemController.updateItems(status, homebrew: false).isEmpty)
            #expect(StatusItemController.updateItems(status, homebrew: true).isEmpty)
        }
    }
}
