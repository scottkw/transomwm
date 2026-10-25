import PaneEngine
import Testing

/// The consume rule of `SpaceSwitchMarks` (02-17): a mark flags every full update of its pid until one whose reads
/// began at or after the notification that set it.
@Suite struct SpaceSwitchMarksTests {
    /// Successive updates of `pid`, each with its reads begun at the given generation (nil: the current one).
    private func takes(_ marks: inout SpaceSwitchMarks, pid: Int32 = 1, reads: [UInt64?]) -> [Bool] {
        reads.map { marks.take(pid: pid, readGeneration: $0 ?? marks.generation) }
    }

    @Test func noMarkIsNotFlagged() {
        var marks = SpaceSwitchMarks()
        #expect(takes(&marks, reads: [nil]) == [false])
    }

    @Test func aMarkIsConsumedByAnUpdateWhoseReadsBeganAfterIt() {
        var marks = SpaceSwitchMarks()
        marks.spaceDidChange(pids: [1])
        #expect(takes(&marks, reads: [nil, nil]) == [true, false])
    }

    /// The notification lands between the start of the reads and ingest: that update is flagged and the mark stays
    /// for the next update, the first that fully sees the new Space.
    @Test func aNotificationInjectedBetweenTheReadsAndIngestFlagsThatUpdateAndTheNext() {
        var marks = SpaceSwitchMarks()
        let read = marks.generation
        marks.spaceDidChange(pids: [1])
        #expect(takes(&marks, reads: [read, nil, nil]) == [true, true, false])
    }

    @Test func aReadBetweenTwoNotificationsDoesNotConsumeTheNewerMark() {
        var marks = SpaceSwitchMarks()
        marks.spaceDidChange(pids: [1])
        let read = marks.generation
        marks.spaceDidChange(pids: [1])
        #expect(takes(&marks, reads: [read, nil, nil]) == [true, true, false])
    }

    @Test func onlyThePidsPassedAreMarkedAndForgetDropsAMark() {
        var marks = SpaceSwitchMarks()
        marks.spaceDidChange(pids: [1, 2])
        #expect(takes(&marks, pid: 3, reads: [nil]) == [false])
        marks.forget(pid: 2)
        #expect(takes(&marks, pid: 2, reads: [nil]) == [false])
        #expect(takes(&marks, pid: 1, reads: [nil]) == [true])
    }
}
