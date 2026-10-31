import Foundation
import TransomPrivate
import Testing

@Suite struct CapabilitiesTests {
    @Test(arguments: [
        (["TransomApp"], Set<Capability>(), [String]()),
        (["TransomApp", "--disable-private=AXWindowID"], [.axWindowID], []),
        (["TransomApp", "--disable-private=AXWindowID,Bogus"], [.axWindowID], ["Bogus"]),
        (["TransomApp", "--disable-private=Bogus"], [], ["Bogus"]),
        (["TransomApp", "--disable-private"], [], []),
        (["TransomApp", "--disable-private=Spaces"], [.spaces], []),
        (["TransomApp", "--disable-private=AXWindowID,Spaces"], [.axWindowID, .spaces], []),
        (["TransomApp", "--disable-private=Multitouch"], [.multitouch], []),
        (["TransomApp", "--disable-private=SymbolicHotKeys,CoreDock"], [.symbolicHotKeys, .coreDock], []),
    ] as [([String], Set<Capability>, [String])])
    func disablePrivateTakesOnlyKnownNames(arguments: [String], disabled: Set<Capability>, unknown: [String]) {
        let parsed = Capabilities.parseDisabled(arguments)
        #expect(parsed.disabled == disabled)
        #expect(parsed.unknown == unknown)
    }

    @Test func everyCapabilityIsReported() {
        #expect(Capability.allCases.map(\.rawValue) == ["AXWindowID", "Spaces", "Multitouch", "SymbolicHotKeys", "CoreDock"])
        #expect(Set(Capabilities.report().keys) == Set(Capability.allCases))
    }

    @Test func eachCapabilityNamesItsOwnFallback() {
        #expect(Capability.axWindowID.fallback == "matching by frame")
        #expect(Capability.spaces.fallback == "single Space")
        #expect(Capability.multitouch.fallback == "trackpad gestures from system events")
        #expect(Capability.symbolicHotKeys.fallback == "Mission Control keys unchanged")
        #expect(Capability.coreDock.fallback == "beep instead of Mission Control")
    }
}

/// The multitouch crash canary, on a private defaults suite: no device is listed or opened here.
@Suite struct MultitouchCanaryTests {
    private func fresh() -> UserDefaults {
        let name = "transom.canary.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func noCanaryIsNotTripped() {
        #expect(!MultitouchCanary(defaults: fresh(), osBuild: "26B123", appVersion: "1.0 (1)").isTripped())
    }

    @Test func aLeftoverCanaryForTheSameBuildAndVersionTripsAndStays() {
        let defaults = fresh()
        MultitouchCanary(defaults: defaults, osBuild: "26B123", appVersion: "1.0 (1)").arm()
        let next = MultitouchCanary(defaults: defaults, osBuild: "26B123", appVersion: "1.0 (1)")
        #expect(next.isTripped())
        #expect(next.isTripped(), "stays off until the build or version changes")
    }

    @Test(arguments: [("26C5", "1.0 (1)"), ("26B123", "1.1 (2)")])
    func aNewBuildOrVersionClearsTheCanaryAndRetries(build: String, version: String) {
        let defaults = fresh()
        MultitouchCanary(defaults: defaults, osBuild: "26B123", appVersion: "1.0 (1)").arm()
        #expect(!MultitouchCanary(defaults: defaults, osBuild: build, appVersion: version).isTripped())
        #expect(defaults.object(forKey: MultitouchCanary.key) == nil)
    }

    /// WR-08: the Debug menu's way back after a trip clears the canary, and multitouch is no longer tripped this launch.
    @Test func turningMultitouchBackOnClearsTheCanary() {
        let defaults = fresh()
        let canary = MultitouchCanary(defaults: defaults, osBuild: "26B123", appVersion: "1.0 (1)")
        canary.arm()
        #expect(canary.isTripped())
        MultitouchCanary.turnBackOn(canary)
        #expect(defaults.object(forKey: MultitouchCanary.key) == nil)
        #expect(!canary.isTripped())
        #expect(!MultitouchCanary.tripped)
    }

    @Test func clearRemovesTheKey() {
        let defaults = fresh()
        let canary = MultitouchCanary(defaults: defaults, osBuild: "26B123", appVersion: "1.0 (1)")
        canary.arm()
        #expect(defaults.dictionary(forKey: MultitouchCanary.key)?["osBuild"] as? String == "26B123")
        canary.clear()
        #expect(defaults.object(forKey: MultitouchCanary.key) == nil)
        #expect(!canary.isTripped())
    }

    @Test func theCurrentOSBuildIsRead() {
        #expect(MultitouchCanary.currentOSBuild != "?")
        #expect(!MultitouchCanary.currentOSBuild.isEmpty)
    }
}

/// Call-time degradation (D-15): a present but misbehaving private API is switched off for the session.
/// Each test owns its session, so the process-wide one the integration tests use is never touched.
@Suite struct CapabilitySessionTests {
    private func loaded() -> CapabilitySession { CapabilitySession(loaded: { _ in true }) }

    @Test func aSuccessResetsTheFailureCount() {
        let session = loaded()
        for _ in 0..<4 { session.recordFailure(.axWindowID) }
        session.recordSuccess(.axWindowID)
        for _ in 0..<4 { session.recordFailure(.axWindowID) }
        #expect(session.isAvailable(.axWindowID))
    }

    @Test func fiveConsecutiveFailuresSwitchTheCapabilityOffOnce() {
        let session = loaded()
        let flips = (1...6).map { _ in session.recordFailure(.axWindowID) }
        #expect(flips == [false, false, false, false, true, false])
        #expect(!session.isAvailable(.axWindowID))
        session.recordSuccess(.axWindowID)
        #expect(!session.isAvailable(.axWindowID), "a session-disabled capability stays off")
    }

    @Test func theCurrentSpaceLookupIsNilWhileSpacesAreOff() {
        let off = CapabilitySession(loaded: { _ in false })
        #expect(SkyLightSpaces.currentSpace(displayUUID: "any", session: off) == nil)
    }

    @Test func aCapabilityThatDidNotLoadIsNeverAvailable() {
        let session = CapabilitySession(loaded: { _ in false })
        session.recordSuccess(.axWindowID)
        #expect(!session.isAvailable(.axWindowID))
        // Already off: failures never "switch it off" again, so nothing is logged.
        #expect((1...5).map { _ in session.recordFailure(.axWindowID) }.allSatisfy { !$0 })
    }

    @Test func concurrentReadsAgree() async {
        let session = loaded()
        let values = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 { group.addTask { session.isAvailable(.axWindowID) } }
            return await group.reduce(into: Set<Bool>()) { $0.insert($1) }
        }
        #expect(values == [true])
    }

    @Test func concurrentFailuresFlipTheCapabilityExactlyOnce() async {
        let session = loaded()
        let flips = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 { group.addTask { session.recordFailure(.axWindowID) } }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(flips == 1)
        #expect(!session.isAvailable(.axWindowID))
    }
}
