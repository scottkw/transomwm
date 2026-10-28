import AppKit
import CoreGraphics
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// D-B / ZOOM-05 live: one-shot captures of fixture windows with the guest's Screen Recording grant. VM only.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct SnapshotCaptureIntegrationTests {
    /// Connects to the window server first. This suite runs beside others in a process with no NSApplication, and a
    /// CoreGraphics call racing the lazy connection on another thread trips `CGS_REQUIRE_INIT` (seen once in the VM).
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(1)))
    func aFixtureWindowCapturesAtTheRequestedPixelSize() async throws {
        try #require(SnapshotCapture.isGranted(), "the VM's SSH session needs the Screen Recording grant")
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let capture = SnapshotCapture()
        try await capture.refreshShareable()
        let id = try #require(fixture.windows.first).id
        let image = try #require(await capture.capture(id, pixelSize: CGSize(width: 400, height: 300)), "no image for window \(id)")
        #expect(abs(image.width - 400) <= 1 && abs(image.height - 300) <= 1, "got \(image.width)x\(image.height)")
        #expect(capture.cached(id) != nil, "a capture is kept in the cache")
    }

    @Test(.timeLimit(.minutes(1)))
    func aParkedWindowCapturesOrFailsWithinTheTimeout() async throws {
        try #require(SnapshotCapture.isGranted(), "the VM's SSH session needs the Screen Recording grant")
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let window = try #require(fixture.windows.first)
        let display = try #require(Displays.current().first)
        let parked = display.parkedFrame(size: window.frame.size, among: [display])
        _ = try await fixture.send("move 0 \(Int(parked.x)) \(Int(parked.y))")
        let capture = SnapshotCapture()
        try await capture.refreshShareable()
        let start = ContinuousClock.now
        let image = await capture.capture(window.id, pixelSize: CGSize(width: 200, height: 150))
        let elapsed = ContinuousClock.now - start
        print("parked capture: \(image.map { "\($0.width)x\($0.height)" } ?? "nil") in \(elapsed)")
        #expect(elapsed < .milliseconds(1100), "a parked capture took \(elapsed)")
    }

    @Test(.timeLimit(.minutes(1)))
    func captureAllReturnsWithinTheMoveBudget() async throws {
        try #require(SnapshotCapture.isGranted(), "the VM's SSH session needs the Screen Recording grant")
        let fixture = try await FixtureProcess.launch(Array(repeating: "standard", count: 6))
        defer { fixture.terminate() }
        let capture = SnapshotCapture()
        try await capture.refreshShareable()
        let requests = fixture.windows.map { (CGWindowID($0.id), CGSize(width: 400, height: 300)) }
        try #require(requests.count == 6)
        let start = ContinuousClock.now
        let images = await capture.captureAll(requests)
        let elapsed = ContinuousClock.now - start
        print("captureAll: \(images.count) of 6 in \(elapsed)")
        #expect(elapsed < SnapshotCapture.moveBudget + .milliseconds(50), "captureAll took \(elapsed)")
    }
}
