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
