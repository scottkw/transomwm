@testable import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainKey = DeskKey(displayUUID: "main", spaceID: nil)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)

private func window(_ id: UInt32) -> WindowRef { WindowRef(identity: WindowIdentity(windowID: id, pid: 900, bundleID: "com.example.overview")) }

private func info(_ id: UInt32, frame: Rect) -> WindowInfo {
    WindowInfo(window: window(id), frame: frame, state: .present, displayUUID: "main", kind: .dockable, isExcluded: false)
}

/// 07-04 / 07-11 (UI-SPEC Surface 6): the overview counts a group once, by its selected member.
@Suite @MainActor struct OverviewTabInputsTests {
    @Test func aDockedGroupsHiddenMemberIsNotAnOverviewWindow() throws {
        let a = window(1), b = window(3), f = window(2)
        var arranger = Arranger()
        let infos = [info(1, frame: Rect(x: 40, y: 80, width: 320, height: 232)), info(2, frame: Rect(x: 1250, y: 700, width: 150, height: 100)),
                     info(3, frame: Rect(x: 730, y: 400, width: 150, height: 120))]
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        _ = arranger.handle(.command(.dock, focused: b), now: .now)
        let leaf = try #require(arranger.world[mainKey]?.tree.leaf(containing: b))
        try arranger.world.edit(mainKey, history: &arranger.history) { desk, _ throws(LayoutError) in
            try desk.desktop.remove(f)
            try desk.tree.group(f, into: leaf)  // [b, f], f selected
        }
        _ = arranger.handle(.gap(8), now: .now)

        let shown = try #require(OverviewController.inputs(arranger, spaces: nil, frontToBack: nil).first).windows.map(\.window)
        #expect(Set(shown) == [a, f], "the overview's windows: \(shown)")
        #expect(arranger.tabGroupMembers(holding: f)?.selected == 1)
    }
}
