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

    /// Surface 6 menu copy and the Accessibility "Zoom off" / "Zoom on" announcements.
    @Test func theMenuCopyMatchesTheContract() {
        #expect(ZoomCopy.zoomSection == "Zoom")
        #expect(ZoomCopy.moveViewMenu == "Move View")
        #expect(ZoomCopy.allowWindowPreviews == "Allow Window Previews\u{2026}")
        #expect(ZoomCopy.turnOffZoom == "Turn Off Zoom")
        #expect(ZoomCopy.turnOnZoom == "Turn On Zoom")
        #expect(ZoomCopy.shortcutsItem == "Shortcuts\u{2026}")
        #expect(ZoomCopy.zoomedInDescription == "Transom: zoomed in")
        #expect(ZoomCopy.zoomOffAnnouncement == "Zoom off")
        #expect(ZoomCopy.zoomOnAnnouncement == "Zoom on")
    }

    @Test func theZoomStateDebugLine() {
        #expect(ZoomCopy.zoomStateLine(enabled: true, capture: ZoomCopy.capturePreviews) == "Zoom: on, window previews")
        #expect(
            ZoomCopy.zoomStateLine(enabled: true, capture: ZoomCopy.captureNoPermission) == "Zoom: on, app-icon tiles (no Screen Recording)")
        #expect(ZoomCopy.zoomStateLine(enabled: true, capture: ZoomCopy.captureFailing) == "Zoom: on, app-icon tiles (capture failing)")
        #expect(ZoomCopy.zoomStateLine(enabled: false, capture: ZoomCopy.capturePreviews) == "Zoom: off")
    }

    /// Zero-one-many: explicit branches, never "(s)".
    @Test func theSettleAndCacheDebugLinesUseExplicitPlurals() {
        #expect(ZoomCopy.lastSettleLine(nil) == "Last settle: none yet")
        #expect(ZoomCopy.lastSettleLine((ms: 42, windows: 1)) == "Last settle: 42 ms, 1 window")
        #expect(ZoomCopy.lastSettleLine((ms: 120, windows: 6)) == "Last settle: 120 ms, 6 windows")
        #expect(ZoomCopy.snapshotCacheLine(windows: 0, bytes: 0) == "Snapshot cache: empty")
        #expect(ZoomCopy.snapshotCacheLine(windows: 1, bytes: 3 * 1_048_576) == "Snapshot cache: 1 window, 3 MB")
        #expect(ZoomCopy.snapshotCacheLine(windows: 5, bytes: 40 * 1_048_576 + 400_000) == "Snapshot cache: 5 windows, 40 MB")
    }

    /// 08 UI-SPEC Surface 3: the Saved Views Recorder titles.
    @Test func theSavedViewShortcutTitles() {
        #expect(ZoomCopy.shortcutTitle(.camera(.view(ViewSlot(3)!))) == "Go to View 3")
        #expect(ZoomCopy.shortcutTitle(.camera(.saveView(ViewSlot(3)!))) == "Save View 3")
        #expect(ZoomCopy.shortcutTitle(.dockFourth(.first, .horizontal)) == "Dock to 1st Column")
        #expect(ZoomCopy.shortcutTitle(.dockFourth(.middle, .vertical)) == "Dock to Middle Half Row")
    }

    @Test func theRubberBandCancelCopyMatchesTheContract() {
        #expect(ZoomCopy.zoomCanceled == "Zoom canceled")
        #expect(ZoomCopy.logRectNoTarget == "rect zoom: no target")
        #expect(ZoomCopy.logRectCanceled == "rect zoom canceled (Esc)")
        #expect(ZoomCopy.logRepost == "\u{2318}\u{21E7}-click re-posted")
        #expect(ZoomCopy.logPickOn == "pick mode on")
    }
}
