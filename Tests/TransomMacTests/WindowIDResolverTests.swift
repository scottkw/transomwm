import ApplicationServices
import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

private let pid: Int32 = 900
private let frameA = Rect(x: 0, y: 0, width: 400, height: 300)
private let frameB = Rect(x: 500, y: 0, width: 400, height: 300)

/// Distinct elements with no AX trust needed: application elements of fake pids, told apart by CFEqual.
private func element(_ n: Int32) -> AXUIElement { AXUIElementCreateApplication(20_000 + n) }

private func item(_ element: AXUIElement, frame: Rect? = frameA, window: Bool = true) -> WindowIDResolver.Item {
    WindowIDResolver.Item(element: element, isReadableWindow: window, frame: frame, title: "")
}

private func cg(_ id: UInt32, _ bounds: Rect = frameA, onScreen: Bool = true) -> CGWindowEntry {
    CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: 0, onScreen: onScreen, alpha: 1)
}

private func freshSession() -> CapabilitySession { CapabilitySession(loaded: { _ in true }) }

/// A lookup stub: a fixed answer per element (nil = the lookup fails), counting its calls per element.
private final class Lookup {
    private var answers: [(element: AXUIElement, id: UInt32?)] = []
    private var counts: [(element: AXUIElement, calls: Int)] = []

    func answer(_ element: AXUIElement, _ id: UInt32?) {
        answers.removeAll { CFEqual($0.element, element) }
        answers.append((element, id))
    }

    func calls(_ element: AXUIElement) -> Int { counts.first { CFEqual($0.element, element) }?.calls ?? 0 }

    func callAsFunction(_ element: AXUIElement) -> UInt32? {
        if let i = counts.firstIndex(where: { CFEqual($0.element, element) }) { counts[i].calls += 1 } else { counts.append((element, 1)) }
        return answers.first { CFEqual($0.element, element) }?.id ?? nil
    }
}

/// How many failures `session` has counted so far. Destructive: it switches the capability off to find out.
private func countedFailures(_ session: CapabilitySession) -> Int {
    guard session.isAvailable(.axWindowID) else { return CapabilitySession.failureLimit }
    var calls = 0
    repeat { calls += 1 } while !session.recordFailure(.axWindowID)
    return CapabilitySession.failureLimit - calls
}

/// The resolver's invariant: byID never holds one element twice, and every resolved ID is that element's key.
private func expectInvariant(_ items: [WindowIDResolver.Item], _ resolution: WindowIDResolver.Resolution, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(resolution.ids.count == items.count, sourceLocation: sourceLocation)
    let elements = Array(resolution.byID.values.map(\.element))
    for i in elements.indices {
        for j in elements.indices where j > i {
            #expect(!CFEqual(elements[i], elements[j]), "one element under two IDs", sourceLocation: sourceLocation)
        }
    }
    for (item, resolved) in zip(items, resolution.ids) {
        guard let resolved else { continue }
        let cached = resolution.byID[resolved.id]
        #expect(cached.map { CFEqual($0.element, item.element) } == true, "\(resolved.id) is not this element's key", sourceLocation: sourceLocation)
        #expect(cached?.source == resolved.source, sourceLocation: sourceLocation)
    }
}

private struct Harness {
    var resolver = WindowIDResolver(pid: pid)
    var cache: [UInt32: CachedWindow] = [:]
    let session = freshSession()
    let lookup = Lookup()
    var cgList: [CGWindowEntry]? = []
    var useLookup = true

    mutating func resolve(_ items: [WindowIDResolver.Item], sourceLocation: SourceLocation = #_sourceLocation) -> WindowIDResolver.Resolution {
        let resolution = resolver.resolve(
            items, cache: cache, lookup: useLookup ? { [lookup] in lookup($0) } : nil, session: session,
            cgWindows: { cgList }, cgNames: { [:] })
        expectInvariant(items, resolution, sourceLocation: sourceLocation)
        cache = resolution.byID
        return resolution
    }
}

/// D-15, SAFE-05, lead decision 2026-10-25 (VERIFICATION gaps 4 and 5, REVIEW WR-03 and WR-04).
@Suite struct WindowIDResolverTests {
    // MARK: Gap 4: failure counting

    @Test func oneElementThatKeepsFailingNeverSwitchesTheLookupOff() {
        var h = Harness()
        let (a1, a2, b) = (element(1), element(2), element(3))
        h.cache = [1: CachedWindow(element: a1, source: .axPrivate), 2: CachedWindow(element: a2, source: .axPrivate)]
        // No frame: the fallback cannot place it either, so it is new on every refresh.
        for _ in 0..<6 {
            let resolution = h.resolve([item(a1), item(a2), item(b, frame: nil)])
            #expect(resolution.ids.map { $0?.id } == [1, 2, nil])
            #expect(h.session.isAvailable(.axWindowID))
        }
        #expect(h.lookup.calls(a1) == 0)
        #expect(h.lookup.calls(a2) == 0)
        #expect(h.lookup.calls(b) == 6)
        #expect(countedFailures(h.session) == 1)
    }

    @Test func fiveDistinctFailingElementsSwitchTheLookupOffOnce() {
        var h = Harness()
        let failing = (1...5).map { element($0) }
        var listed: [WindowIDResolver.Item] = []
        for (n, e) in failing.enumerated() {
            listed.append(item(e, frame: nil))
            _ = h.resolve(listed)
            #expect(h.session.isAvailable(.axWindowID) == (n < 4), "after \(n + 1) failing elements")
        }
        // Off now: no element is looked up again.
        let calls = failing.map { h.lookup.calls($0) }
        _ = h.resolve(listed)
        #expect(failing.map { h.lookup.calls($0) } == calls)
    }

    @Test func aSuccessBetweenFailuresKeepsTheLookupOn() {
        var h = Harness()
        let failing = (1...5).map { element($0) }
        let good = element(9)
        h.lookup.answer(good, 99)
        var listed = failing.prefix(4).map { item($0, frame: nil) }
        _ = h.resolve(listed)
        listed.append(item(good))
        #expect(h.resolve(listed).ids.last??.id == 99)
        listed.append(item(failing[4], frame: nil))
        _ = h.resolve(listed)
        #expect(h.session.isAvailable(.axWindowID))
        #expect(countedFailures(h.session) == 1)
    }

    /// Review WR-02 (iteration 4): a hidden tab or a window on another Space leaves AXWindows and comes back as the
    /// same element, so its failure counts once, not once per listing.
    @Test func aFailingElementCountsOnceEvenAfterItLeftAXWindows() {
        var h = Harness()
        let b = element(3)
        _ = h.resolve([item(b, frame: nil)])
        _ = h.resolve([item(b, frame: nil)])
        _ = h.resolve([])
        _ = h.resolve([item(b, frame: nil)])
        #expect(countedFailures(h.session) == 1)
    }

    /// Five tab switches or Space round trips back to one failing element never switch the lookup off, whether the
    /// element stayed cached (a window on another Space) or left the cache too (a hidden tab).
    @Test(arguments: [true, false])
    func roundTripsOfOneFailingElementNeverSwitchTheLookupOff(staysCached: Bool) {
        var h = Harness()
        let b = element(3)
        for _ in 0..<5 {
            _ = h.resolve([item(b)])
            let cached = h.cache
            _ = h.resolve([])
            if staysCached { h.cache = cached }
        }
        _ = h.resolve([item(b)])
        #expect(h.session.isAvailable(.axWindowID))
        #expect(countedFailures(h.session) == 1)
    }

    @Test func aNonWindowElementsFailureIsNeverCounted() {
        var h = Harness()
        _ = h.resolve([item(element(1), frame: nil, window: false)])
        #expect(countedFailures(h.session) == 0)
    }

    // MARK: Gap 5: re-check

    @Test(arguments: [
        (WindowIDSource.synthetic, WindowIdentity.syntheticIDBase | 7, UInt32(42), UInt32?(WindowIdentity.syntheticIDBase | 7)),
        (.cgFrameMatch, 30, 42, 30),
        (.cgFrameMatch, 30, 30, nil),
    ])
    func aCachedFallbackIDIsLookedUpAgainAndReplacedWhenItDiffers(source: WindowIDSource, cached: UInt32, real: UInt32, replaces: UInt32?) {
        var h = Harness()
        let e = element(1)
        h.cache = [cached: CachedWindow(element: e, source: source)]
        h.lookup.answer(e, real)
        let resolution = h.resolve([item(e)])
        #expect(resolution.ids == [WindowIDResolver.Resolved(id: real, source: .axPrivate, replaces: replaces)])
        #expect(Array(resolution.byID.keys) == [real])
        #expect(countedFailures(h.session) == 0)
    }

    @Test func aCachedFallbackIDWhoseLookupStillFailsIsKept() {
        var h = Harness()
        let e = element(1)
        h.cache = [30: CachedWindow(element: e, source: .cgFrameMatch)]
        let resolution = h.resolve([item(e)])
        #expect(resolution.ids == [WindowIDResolver.Resolved(id: 30, source: .cgFrameMatch, replaces: nil)])
        #expect(h.lookup.calls(e) == 1)
    }

    // MARK: Gap 5: collisions

    @Test(arguments: [false, true])
    func theElementTheLookupNamesOwnsTheIDAndAFrameMatchedHolderIsReidentified(newFirst: Bool) throws {
        var h = Harness()
        let (holder, owner) = (element(1), element(2))
        h.cache = [30: CachedWindow(element: holder, source: .cgFrameMatch)]
        h.lookup.answer(owner, 30)
        h.cgList = [cg(30)]
        let items = newFirst ? [item(owner), item(holder)] : [item(holder), item(owner)]
        let resolution = h.resolve(items)
        let ownerResolved = try #require(resolution.ids[newFirst ? 0 : 1])
        let holderResolved = try #require(resolution.ids[newFirst ? 1 : 0])
        #expect(ownerResolved == WindowIDResolver.Resolved(id: 30, source: .axPrivate, replaces: nil))
        #expect(holderResolved.source == .synthetic)
        #expect(holderResolved.id >= WindowIdentity.syntheticIDBase)
        #expect(holderResolved.replaces == 30)
        #expect(resolution.byID.count == 2)
    }

    @Test func aReidentifiedHolderTakesItsOwnFrameMatchWhenThereIsOne() {
        var h = Harness()
        let (holder, owner) = (element(1), element(2))
        h.cache = [30: CachedWindow(element: holder, source: .cgFrameMatch)]
        h.lookup.answer(owner, 30)
        h.cgList = [cg(30), cg(31, frameB)]
        let resolution = h.resolve([item(holder, frame: frameB), item(owner)])
        #expect(resolution.ids == [
            WindowIDResolver.Resolved(id: 31, source: .cgFrameMatch, replaces: 30),
            WindowIDResolver.Resolved(id: 30, source: .axPrivate, replaces: nil),
        ])
    }

    @Test func aCrossSpaceTwinsIDMovesToTheTwinAndTheHolderGetsItsOwn() {
        var h = Harness()
        let (holder, twin) = (element(1), element(2))
        h.cache = [30: CachedWindow(element: holder, source: .cgFrameMatch)]
        h.lookup.answer(holder, 40)
        h.lookup.answer(twin, 30)
        let resolution = h.resolve([item(holder), item(twin)])
        #expect(resolution.ids == [
            WindowIDResolver.Resolved(id: 40, source: .axPrivate, replaces: 30),
            WindowIDResolver.Resolved(id: 30, source: .axPrivate, replaces: nil),
        ])
    }

    @Test func twoNewIdenticalWindowsNeverShareAnID() {
        var h = Harness()
        h.useLookup = false
        h.cgList = [cg(30), cg(31)]
        let resolution = h.resolve([item(element(1)), item(element(2))])
        let ids = resolution.ids.compactMap { $0?.id }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    // MARK: First failure

    @Test func aFirstFailureNeverTakesAnOffscreenOnlyMatchAndWaitsOneRefresh() {
        var h = Harness()
        let e = element(1)
        h.cgList = [cg(55, onScreen: false)]
        let first = h.resolve([item(e)])
        #expect(first.ids == [nil])
        #expect(first.identityPending)
        h.cgList = [cg(55, onScreen: false), cg(56)]
        let second = h.resolve([item(e)])
        #expect(second.ids == [WindowIDResolver.Resolved(id: 56, source: .cgFrameMatch, replaces: nil)])
        #expect(!second.identityPending)
    }

    @Test func aFirstFailureTakesAnOnscreenMatchAtOnce() {
        var h = Harness()
        h.cgList = [cg(56)]
        let resolution = h.resolve([item(element(1))])
        #expect(resolution.ids == [WindowIDResolver.Resolved(id: 56, source: .cgFrameMatch, replaces: nil)])
        #expect(!resolution.identityPending)
    }

    // MARK: Lookup unavailable

    @Test func withoutTheLookupCachedElementsKeepTheirIDsAndNewOnesUseTheFallback() {
        var h = Harness()
        h.useLookup = false
        let (cached, matched, ambiguous) = (element(1), element(2), element(3))
        let synthetic = WindowIdentity.syntheticIDBase | 0x0FFF_0000
        h.cache = [synthetic: CachedWindow(element: cached, source: .synthetic)]
        h.cgList = [cg(30, frameB), cg(31, onScreen: false), cg(32, onScreen: false)]
        let resolution = h.resolve([item(cached), item(matched, frame: frameB), item(ambiguous)])
        #expect(resolution.ids[0] == WindowIDResolver.Resolved(id: synthetic, source: .synthetic, replaces: nil))
        #expect(resolution.ids[1] == WindowIDResolver.Resolved(id: 30, source: .cgFrameMatch, replaces: nil))
        #expect(resolution.ids[2]?.source == .synthetic)
        #expect(!resolution.identityPending)
        #expect(countedFailures(h.session) == 0)
    }

    @Test func withoutACGListANewElementStaysUnidentified() {
        var h = Harness()
        h.useLookup = false
        h.cgList = nil
        #expect(h.resolve([item(element(1))]).ids == [nil])
    }
}
