import TransomEngine
import TransomMac
import TransomModel
import Testing

/// Notice kinds beyond the one Phase 3 has so far, so the replace, merge and crash rules are all exercised.
private enum TestNotice: QueueableNotice {
    case floated(Int)
    case restored
    case crash(Int)

    var isCrashNotice: Bool {
        if case .crash = self { true } else { false }
    }

    func merged(with other: TestNotice) -> TestNotice? {
        if case .floated(let n) = self, case .floated(let m) = other { .floated(n + m) } else { nil }
    }
}

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 42, bundleID: "com.example.notice"))
}

/// UI-SPEC Surface 4: one toast at a time, replaced by a newer one except crash notices, same-kind notices merged,
/// up to 3 queued behind a crash notice with the oldest dropped, 6 s on screen (10 s for crash notices).
@Suite struct NoticeQueueTests {
    let t0 = ContinuousClock.now

    @Test func aNewNoticeOfAnotherKindReplacesTheVisibleOne() {
        var queue = NoticeQueue<TestNotice>()
        #expect(queue.post(.floated(1), at: t0) == .show(.floated(1)))
        #expect(queue.post(.restored, at: t0 + .seconds(1)) == .show(.restored))
        #expect(queue.visible == .restored)
        // The replaced one does not come back.
        #expect(queue.expire(at: t0 + .seconds(7)) == .hide)
        #expect(queue.visible == nil)
    }

    @Test func sameKindNoticesMergeIntoOneCount() {
        var queue = NoticeQueue<Notice>()
        _ = queue.post(.lostRoom([ref(1)]), at: t0)
        #expect(queue.post(.lostRoom([ref(2), ref(3)]), at: t0 + .seconds(2)) == .show(.lostRoom([ref(1), ref(2), ref(3)])))
        #expect(queue.visible == .lostRoom([ref(1), ref(2), ref(3)]))
    }

    @Test func aVisibleNoticeExpiresAfterSixSeconds() {
        var queue = NoticeQueue<TestNotice>()
        _ = queue.post(.restored, at: t0)
        #expect(queue.expiresAt == t0 + .seconds(6))
        #expect(queue.expire(at: t0 + .milliseconds(5_999)) == .unchanged)
        #expect(queue.visible == .restored)
        #expect(queue.expire(at: t0 + .seconds(6)) == .hide)
        #expect(queue.visible == nil)
    }

    @Test func aCrashNoticeIsNeverReplacedAndTheOldestQueuedNoticeIsDropped() {
        var queue = NoticeQueue<TestNotice>()
        #expect(queue.post(.crash(1), at: t0) == .show(.crash(1)))
        #expect(queue.expiresAt == t0 + .seconds(10))
        for (i, notice) in [TestNotice.restored, .floated(1), .crash(2), .floated(2), .restored].enumerated() {
            #expect(queue.post(notice, at: t0 + .seconds(Double(i + 1) / 10)) == .unchanged)
        }
        #expect(queue.visible == .crash(1))
        // Queued: restored, floated(1+2), crash(2), restored → the first restored is dropped.
        #expect(queue.expire(at: t0 + .milliseconds(9_999)) == .unchanged)
        #expect(queue.expire(at: t0 + .seconds(10)) == .show(.floated(3)))
        #expect(queue.expiresAt == t0 + .seconds(16))
        #expect(queue.expire(at: t0 + .seconds(16)) == .show(.crash(2)))
        #expect(queue.expire(at: t0 + .seconds(26)) == .show(.restored))
        #expect(queue.expire(at: t0 + .seconds(32)) == .hide)
    }

    /// Two N12s within the toast's lifetime merge into the several-displays form.
    @Test func twoDisplaysDisconnectedNoticesMergeNamesAndWindows() {
        let first = Notice.displaysDisconnected(names: ["A"], windows: 2)
        #expect(first.merged(with: .displaysDisconnected(names: ["B"], windows: 1)) == .displaysDisconnected(names: ["A", "B"], windows: 3))
        var queue = NoticeQueue<Notice>()
        _ = queue.post(first, at: t0)
        #expect(queue.post(.displaysDisconnected(names: ["B"], windows: 1), at: t0 + .seconds(1)) == .show(.displaysDisconnected(names: ["A", "B"], windows: 3)))
    }

    /// N2 (plan 14) is a real crash notice: 10 s on screen, and a later N1 waits behind it.
    @Test func crashRecoveredStaysTenSecondsAndALaterNoticeQueuesBehindIt() {
        var queue = NoticeQueue<Notice>()
        #expect(queue.post(.crashRecovered(unplaced: 0), at: t0) == .show(.crashRecovered(unplaced: 0)))
        #expect(queue.expiresAt == t0 + .seconds(10))
        #expect(queue.post(.lostRoom([ref(1)]), at: t0 + .seconds(1)) == .unchanged)
        #expect(queue.visible == .crashRecovered(unplaced: 0))
        #expect(queue.expire(at: t0 + .seconds(10)) == .show(.lostRoom([ref(1)])))
    }

    // 08 UI-SPEC View toasts: the brief class.
    private static let three = ViewSlot(3)!
    private static let saved = Notice.viewSaved(three, replaced: false, displayUUID: "main")
    private static let shown = Notice.viewShown(three, displayUUID: "main")

    @Test func briefNoticesShowForOneAndAHalfSecondsNormalSixCrashTen() {
        var queue = NoticeQueue<Notice>()
        _ = queue.post(Self.shown, at: t0)
        #expect(queue.expiresAt == t0 + .milliseconds(1500))
        #expect(NoticeQueue<Notice>.briefDuration == .milliseconds(1500))
        _ = queue.post(.viewWindowsClosed(Self.three, displayUUID: "main"), at: t0)
        #expect(queue.expiresAt == t0 + .seconds(6), "N17 is a normal toast")
        _ = queue.post(.crashLoop, at: t0)
        #expect(queue.expiresAt == t0 + .seconds(10))
    }

    @Test func aBriefNoticeReplacesAnyNonCrashNoticeAndRestartsItsTime() {
        var queue = NoticeQueue<Notice>()
        _ = queue.post(.lostRoom([ref(1)]), at: t0)
        #expect(queue.post(Self.saved, at: t0 + .seconds(1)) == .show(Self.saved))
        #expect(queue.post(Self.shown, at: t0 + .seconds(2)) == .show(Self.shown))
        #expect(queue.post(Self.shown, at: t0 + .seconds(3)) == .show(Self.shown), "brief notices never merge; the newer wins")
        #expect(queue.expiresAt == t0 + .seconds(3) + .milliseconds(1500))
        #expect(queue.expire(at: t0 + .seconds(5)) == .hide, "the replaced notices do not come back")
    }

    @Test func aBriefNoticeBehindACrashNoticeIsDroppedNotQueued() {
        var queue = NoticeQueue<Notice>()
        _ = queue.post(.crashLoop, at: t0)
        #expect(queue.post(Self.shown, at: t0 + .seconds(1)) == .unchanged)
        #expect(queue.visible == .crashLoop)
        #expect(queue.expire(at: t0 + .seconds(10)) == .hide, "nothing was queued")
    }

    @Test func n17BehindACrashNoticeIsQueuedLikeANormalNotice() {
        var queue = NoticeQueue<Notice>()
        let closed = Notice.viewWindowsClosed(Self.three, displayUUID: "main")
        _ = queue.post(.crashLoop, at: t0)
        #expect(queue.post(closed, at: t0 + .seconds(1)) == .unchanged)
        #expect(queue.expire(at: t0 + .seconds(10)) == .show(closed))
    }
}
