import TransomEngine
import Testing

/// An in-memory `takeover.originals`.
final class MemoryTakeoverStore: TakeoverStore {
    var originals: [Int32: Bool]?
    init(_ originals: [Int32: Bool]? = nil) { self.originals = originals }
    func setOriginals(_ originals: [Int32: Bool]) { self.originals = originals }
    func clearOriginals() { originals = nil }
}

@Suite struct TakeoverPolicyTests {
    // MARK: apply and read-back

    @Test func aFirstApplyStoresTheCurrentStatesThenDisables() {
        let steps = TakeoverPolicy.apply(ids: [32, 108], current: [32: true, 108: true], store: MemoryTakeoverStore())
        #expect(steps == [.storeOriginals([32: true, 108: true]), .disable(32), .disable(108)])
    }

    /// T-06-27: after a failed restore the live state reads "disabled"; it must never become the original.
    @Test func storedOriginalsAreNeverOverwritten() {
        let store = MemoryTakeoverStore([32: true, 108: true])
        let steps = TakeoverPolicy.apply(ids: [32, 108], current: [32: false, 108: false], store: store)
        #expect(steps == [.disable(32), .disable(108)])
        #expect(store.originals == [32: true, 108: true])
    }

    @Test func aNewlyTakenIDIsAddedWithoutTouchingStoredOnes() {
        let steps = TakeoverPolicy.apply(ids: [32, 108], current: [32: false, 108: true], store: MemoryTakeoverStore([32: true]))
        #expect(steps == [.storeOriginals([32: true, 108: true]), .disable(32), .disable(108)])
    }

    @Test func aReadBackWithEverythingOffApplies() {
        #expect(TakeoverPolicy.afterReadBack([32: false, 108: false], store: MemoryTakeoverStore([32: true, 108: true])) == .applied)
    }

    @Test(arguments: [[32: true, 108: false], [32: false, 108: nil]] as [[Int32: Bool?]])
    func aReadBackStillOnOrUnreadableFailsAndRestores(readBack: [Int32: Bool?]) {
        let store = MemoryTakeoverStore([32: true, 108: true])
        #expect(TakeoverPolicy.afterReadBack(readBack, store: store) == .applyFailed(restore: [32: true, 108: true]))
    }

    // MARK: taken IDs (D-08)

    @Test func hotkey32TurnedOffByTheUserIsNotTaken() {
        #expect(TakeoverPolicy.takenIDs(hotkey32Enabled: false, extra: []) == [108])
    }

    @Test func extrasJoinSorted() {
        #expect(TakeoverPolicy.takenIDs(hotkey32Enabled: true, extra: [34]) == [32, 34, 108])
        #expect(TakeoverPolicy.takenIDs(hotkey32Enabled: true, extra: TakeoverPolicy.spikeExtra) == [32, 108, 113])
    }

    @Test(arguments: [33, 35, 79, 80, 81, 82, 115, 117] as [Int32])
    func neverTouchedIDsAreRejectedFromExtra(id: Int32) {
        #expect(TakeoverPolicy.takenIDs(hotkey32Enabled: true, extra: [id]) == [32, 108])
    }

    @Test func theSpikeSetIs113Only() {
        #expect(TakeoverPolicy.spikeExtra == [113])
    }

    // MARK: launch (OVER-03, D-07)

    @Test(arguments: [false, true])
    func storedOriginalsAreRestoredFirstWhateverThePreference(preferenceOn: Bool) {
        let actions = TakeoverPolicy.launch(
            store: MemoryTakeoverStore([32: true, 108: true]), canaryTripped: false, crashNoticed: false, preferenceOn: preferenceOn, zoomOn: true,
            available: true)
        #expect(actions.first == .restore([32: true, 108: true]))
        #expect(actions.last == (preferenceOn ? .apply : .off))
    }

    @Test func aTrippedCanaryStaysOffAndQueuesTheNoticeEvenWithThePreferenceOn() {
        let actions = TakeoverPolicy.launch(
            store: MemoryTakeoverStore([32: true]), canaryTripped: true, crashNoticed: false, preferenceOn: true, zoomOn: true, available: true)
        #expect(actions == [.restore([32: true]), .stayOff, .queueCrashNotice])
    }

    @Test func theCrashNoticeIsQueuedOnce() {
        let actions = TakeoverPolicy.launch(
            store: MemoryTakeoverStore(), canaryTripped: true, crashNoticed: true, preferenceOn: true, zoomOn: true, available: true)
        #expect(actions == [.stayOff])
    }

    @Test(arguments: [
        (true, true, true, TakeoverPolicy.LaunchAction.apply),
        (true, false, true, .liftedForZoom),
        (true, true, false, .unavailable),
        (true, false, false, .unavailable),
        (false, true, true, .off),
    ])
    func withNothingStoredThePreferenceZoomAndCapabilityDecide(preferenceOn: Bool, zoomOn: Bool, available: Bool, expected: TakeoverPolicy.LaunchAction) {
        let actions = TakeoverPolicy.launch(
            store: MemoryTakeoverStore(), canaryTripped: false, crashNoticed: false, preferenceOn: preferenceOn, zoomOn: zoomOn, available: available)
        #expect(actions == [expected])
    }

    // MARK: lift

    @Test func liftRestoresTheStoredOriginalsAndAMatchingReadBackClearsThem() {
        let store = MemoryTakeoverStore([32: true, 108: true])
        #expect(TakeoverPolicy.lift(store: store) == [32: true, 108: true])
        #expect(TakeoverPolicy.afterRestore([32: true, 108: true], store: store))
        #expect(store.originals == nil)
    }

    @Test func liftWithNothingStoredIsANoOp() {
        let store = MemoryTakeoverStore()
        #expect(TakeoverPolicy.lift(store: store).isEmpty)
    }

    /// A restore that did not take keeps the originals for the next launch's restore.
    @Test func aMismatchedRestoreKeepsTheOriginals() {
        let store = MemoryTakeoverStore([32: true, 108: true])
        #expect(!TakeoverPolicy.afterRestore([32: true, 108: false], store: store))
        #expect(store.originals == [32: true, 108: true])
    }

    // MARK: trigger and drift

    @Test(arguments: [
        (true, true, true, TakeoverPolicy.TriggerAction.dismiss),
        (true, false, false, .dismiss),
        (false, true, false, .open),
        (false, false, true, .missionControl),
        (false, false, false, .refuse),
    ])
    func theMissionControlKeyAlwaysDoesSomething(overviewOpen: Bool, canOpen: Bool, coreDock: Bool, expected: TakeoverPolicy.TriggerAction) {
        #expect(TakeoverPolicy.trigger(overviewOpen: overviewOpen, canOpen: canOpen, coreDockAvailable: coreDock) == expected)
    }

    @Test func driftReDisablesOnlyReEnabledIDs() {
        let store = MemoryTakeoverStore([32: true, 108: true])
        #expect(TakeoverPolicy.drift(taken: [32, 108], enabledNow: [32: true, 108: false]) == [32])
        #expect(TakeoverPolicy.drift(taken: [32, 108], enabledNow: [32: false, 108: false]).isEmpty)
        #expect(store.originals == [32: true, 108: true])
    }
}
