import TransomEngine
import TransomMac
import TransomModel
import Testing

/// UI-SPEC Surface 2, Accessibility and Copywriting Contract: the explainer, reveal announcements and capture states.
@Suite struct ZoomCopyTests {
    @Test func theExplainerCopyMatchesTheContract() {
        #expect(ZoomCopy.explainerMessage == "Show window previews while zooming?")
        #expect(
            ZoomCopy.explainerInformative
                == "Transom takes still pictures of your windows using Screen Recording. Without it, zoom shows app icons instead.")
        #expect(ZoomCopy.allowPreviews == "Allow Previews")
        #expect(ZoomCopy.notNow == "Not Now")
    }

    @Test(arguments: [
        (ViewTarget.home, nil as String?, 5, 0, "Showing all windows"),
        (.node(NodeID(raw: 7)), "Safari", 1, 0, "Showing \u{201C}Safari\u{201D}"),
        (.node(NodeID(raw: 7)), nil, 3, 0, "Showing 3 windows"),
        (.node(NodeID(raw: 7)), nil, 3, 1, "Showing 3 windows, 1 collapsed"),
        (.node(NodeID(raw: 7)), nil, 3, 2, "Showing 3 windows, 2 collapsed"),
        (.node(.desktop), nil, 2, 0, "Showing the Desktop"),
    ])
    func revealAnnouncementsUseExplicitBranches(view: ViewTarget, app: String?, windows: Int, collapsed: Int, expected: String) {
        #expect(ZoomCopy.revealAnnouncement(view: view, appName: app, windowCount: windows, collapsed: collapsed) == expected)
    }

    @Test func aLongAppNameIsTruncatedInTheAnnouncement() {
        let name = String(repeating: "a", count: 40)
        #expect(
            ZoomCopy.revealAnnouncement(view: .node(NodeID(raw: 7)), appName: name, windowCount: 1, collapsed: 0)
                == "Showing \u{201C}\(MenuCopy.truncatedAppName(name))\u{201D}")
    }

    @Test func captureDebugStates() {
        #expect(ZoomCopy.capturePreviews == "window previews")
        #expect(ZoomCopy.captureNoPermission == "app-icon tiles (no Screen Recording)")
        #expect(ZoomCopy.captureFailing == "app-icon tiles (capture failing)")
    }

    @Test func captureLogLines() {
        #expect(ZoomCopy.logGranted == "screen recording: granted")
        #expect(ZoomCopy.logNotGranted == "screen recording: not granted, using app-icon tiles")
        #expect(ZoomCopy.logRevoked == "screen recording: revoked mid-session, using app-icon tiles")
        #expect(ZoomCopy.logFailing == "capture failing while granted; macOS may need Transom reopened")
        #expect(ZoomCopy.logExplainerShown == "explainer shown")
        #expect(ZoomCopy.logExplainerAllow == "explainer: allow")
        #expect(ZoomCopy.logExplainerNotNow == "explainer: not now")
    }
}
