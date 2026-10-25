import PanePrivate
import Testing

@Suite struct CapabilitiesTests {
    @Test(arguments: [
        (["PaneApp"], Set<Capability>(), [String]()),
        (["PaneApp", "--disable-private=AXWindowID"], [.axWindowID], []),
        (["PaneApp", "--disable-private=AXWindowID,Bogus"], [.axWindowID], ["Bogus"]),
        (["PaneApp", "--disable-private=Bogus"], [], ["Bogus"]),
        (["PaneApp", "--disable-private"], [], []),
    ] as [([String], Set<Capability>, [String])])
    func disablePrivateTakesOnlyKnownNames(arguments: [String], disabled: Set<Capability>, unknown: [String]) {
        let parsed = Capabilities.parseDisabled(arguments)
        #expect(parsed.disabled == disabled)
        #expect(parsed.unknown == unknown)
    }

    @Test func everyCapabilityIsReported() {
        #expect(Set(Capabilities.report().keys) == Set(Capability.allCases))
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
