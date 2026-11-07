import Foundation
import TransomEngine
import TransomModel
@testable import TransomMac
import Testing

/// Report a Problem (09 UI-SPEC Surface 5, D-15): versions, counts and capability lines only (T-09-36).
struct ReportProblemTests {
    /// 2 displays, 3 open windows in 2 apps (plus a closed one), with titles and bundle IDs the report must not carry.
    static let inventory: WindowInventory = {
        let frame = Rect(x: 0, y: 0, width: 100, height: 100)
        let ref = { (id: UInt32, pid: Int32, title: String) in
            WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: "com.secret.app\(pid)"), titleHint: title)
        }
        let display = { (uuid: String) in DisplayInfo(uuid: uuid, frame: frame, visibleFrame: frame, currentSpaceID: nil) }
        return WindowInventory(
            displays: [display("Studio Display"), display("DELL U2723QE")],
            windows: [
                WindowInfo(window: ref(1, 1, "Secret Plan.docx"), frame: frame, state: .present, displayUUID: "Studio Display"),
                WindowInfo(window: ref(2, 1, "Secret Plan v2.docx"), frame: frame, state: .absent, displayUUID: nil),
                WindowInfo(window: ref(3, 2, "Payroll — Numbers"), frame: frame, state: .present, displayUUID: "DELL U2723QE"),
                WindowInfo(window: ref(4, 3, "Closed Diary"), frame: frame, state: .closed, displayUUID: nil),
            ], initialRefreshComplete: true)
    }()

    static func details() -> ReportProblem.ReportDetails {
        ReportProblem.details(
            inventory: inventory, version: "0.9.0", build: "12", homebrew: false, macOSVersion: "27.2.0", macOSBuild: "26C55",
            appleSilicon: true, accessibility: .on, screenRecording: false, zoom: true,
            gestures: GestureCopy.gesturesLine(.on),
            lines: [
                MenuCopy.capabilityItem(windowIDLookupAvailable: true), MenuCopy.spacesItem(available: true),
                MenuCopy.tapItem(running: true), OverviewCopy.takeoverLine(.off), ViewCopy.cliLine(listening: true),
            ])
    }

    @Test func theReportNeverContainsTitlesAppNamesOrBundleIDs() {
        let body = ReportProblem.body(Self.details())
        #expect(body.contains("Displays: 2. Tracking 3 windows in 2 apps."))
        for secret in ["Secret Plan", "Payroll", "Closed Diary", "com.secret.app", "Studio Display", "DELL"] {
            #expect(!body.contains(secret), "leaked \(secret)")
        }
    }

    @Test func theIssueURLEncodesPlusAmpersandEqualsAndHash() {
        let url = ReportProblem.issueURL(body: "a+b&c=d#e f")
        #expect(url.absoluteString == "https://github.com/scottkw/transomwm/issues/new?body=a%2Bb%26c%3Dd%23e%20f")
    }

    @Test func theClipboardTextIsTheDetailsBlock() {
        let details = Self.details()
        let block = ReportProblem.detailsBlock(details)
        #expect(ReportProblem.body(details).hasSuffix("### Details\n" + block))
        #expect(block.hasPrefix("Transom 0.9.0 (12), installed from the disk image\n"))
    }

    @Test func theBodyIsTheUISpecTemplate() {
        let want = """
            ### What happened?


            ### What did you expect?


            ### Details
            Transom 0.9.0 (12), installed from the disk image
            macOS 27.2.0 (26C55), Apple Silicon
            Displays: 2. Tracking 3 windows in 2 apps.
            Accessibility: on. Screen Recording: off.
            Zoom: on. Gestures: on, trackpad events
            Window ID lookup: available
            Spaces lookup: available
            Event tap: running
            Mission Control takeover: off
            Command-line tool: listening
            """
        #expect(ReportProblem.body(Self.details()) == want)
    }

    @Test func theMenuItemAndTooltipAreTheUISpecCopy() {
        #expect(MenuCopy.reportProblem == "Report a Problem\u{2026}")
        #expect(
            MenuCopy.reportProblemTooltip
                == "Opens a new GitHub issue with your Transom and macOS versions. Window titles and app names are never included. The same details are copied to the clipboard."
        )
    }
}
