import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// Within 2 pt on every side (the fixture reports whole points).
private func near(_ a: Rect, _ b: Rect) -> Bool {
    abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

/// One value as the store's encoder writes it, to interpolate into the hand-written file.
private func json(_ value: some Encodable) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

/// 8.1.1 D-02, D-03 on real windows (UI-SPEC "Migration of a real 08.1 layout.json"): a schema-3 layout.json whose desk
/// holds a hidden Desktop tile comes back without it. VM only: it moves windows. The store is a temporary directory,
/// never the user's real layout.json.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "moves real windows; VM only"))
@MainActor struct MigrationIntegrationTests {
    init() { _ = NSApplication.shared }

    /// H[W0 0.5, Desktop(hidden) 0.5] with W1 floating at the park rect and a home frame, as 08.1 left it after Hide
    /// Desktop Tile. After the launch W0 fills the visible frame, W1 is back at its home frame, nothing is undoable and
    /// the next save is schema 4.
    @Test(.timeLimit(.minutes(1)))
    func aSchema3LayoutWithAHiddenDesktopComesBackWithoutIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let pid = fixture.pid
        let system = AXWindowSystem(appFilter: { candidate, _ in candidate == pid })
        await system.start()
        let ids = fixture.windows.sorted { $0.index < $1.index }.map(\.id)
        func tracked() async -> [WindowInfo] {
            let inventory = await system.inventory()
            guard inventory.initialRefreshComplete else { return [] }
            return ids.compactMap { id in inventory.windows.first { $0.window.windowID == id && $0.state == .present } }
        }
        _ = await waitUntil(timeout: .seconds(3)) { await tracked().count == 2 }
        let infos = await tracked()
        try #require(infos.count == 2, "the fixture windows were never tracked")
        let w0 = infos[0].window, w1 = infos[1].window

        var builder = Arranger()
        _ = builder.handle(.inventory(await system.inventory()), now: .now)
        let key = try #require(builder.deskKey(of: w0))
        let displays = Displays.current()
        let display = try #require(displays.first { $0.uuid == key.displayUUID })
        let visible = display.visibleFrame

        // W1 parked as the hidden Desktop left it, and seen there before Transom starts.
        let park = display.parkedFrame(size: infos[1].frame.size, among: displays)
        _ = try await fixture.send("move 1 \(Int(park.x)) \(Int(park.y))")
        var parkedAt: Rect?
        let seenParked = await waitUntil(timeout: .seconds(3)) {
            parkedAt = await tracked().first { $0.window == w1 }?.frame
            return parkedAt.map { Recovery.isStranded($0, displays: displays) } ?? false
        }
        try #require(seenParked, "window 1 never reached the park rect \(park): \(String(describing: parkedAt))")
        let home = Rect(
            x: visible.minX + 80, y: visible.minY + 60,
            width: min(infos[1].frame.width, visible.width - 160), height: min(infos[1].frame.height, visible.height - 120))

        // What an 08.1 Transom wrote (LayoutFileV3Fixture's shape); the current encoder can no longer write a Desktop node.
        let schema3 = """
            {
              "arrangement" : \(try json(ArrangementID(displays.map(\.uuid)))),
              "homeFrames" : [ { "frame" : \(try json(home)), "window" : \(try json(w1.identity)) } ],
              "layoutSets" : [ ],
              "schemaVersion" : 3,
              "session" : \(try json(SessionRecord(cleanExit: true, launchedAt: Date(), bootSession: BootSession.current()))),
              "spaces" : [ ],
              "views" : [ ],
              "wantedFrames" : [ ],
              "world" : {
                "desks" : [
                  {
                    "desk" : {
                      "desktop" : {
                        "windows" : [ { "frame" : \(try json(try #require(parkedAt))), "state" : "present", "window" : \(try json(w1)) } ]
                      },
                      "tree" : {
                        "nodes" : {
                          "0" : { "desktop" : { "hidden" : true } },
                          "1" : { "panel" : { "_0" : \(try json(w0)) } },
                          "2" : { "split" : { "axis" : "horizontal", "children" : [ 1, 0 ], "weights" : [ 0.5, 0.5 ] } }
                        },
                        "root" : 2,
                        "states" : [ { "state" : "present", "window" : \(try json(w0.identity)) } ]
                      }
                    },
                    "key" : \(try json(key))
                  }
                ],
                "ids" : { "next" : 3 },
                "schemaVersion" : 1
              }
            }
            """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: LayoutStore.fileName)
        try Data(schema3.utf8).write(to: file)

        let store = LayoutStore(directory: directory)
        let arrange = ArrangeController(system: system, store: store)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()
        #expect(store.loadError == nil, "the schema-3 file was rejected: \(String(describing: store.loadError))")

        let migratedKey = try #require(arrange.arranger.deskKey(of: w0), "window 0 is on no desk after the launch")
        let desk = try #require(arrange.arranger.world[migratedKey])
        #expect(desk.tree.windows == [w0], "the migrated tree holds \(desk.tree.windows), not window 0 alone")
        #expect(arrange.arranger.isFloating(w1), "window 1 is no longer floating")
        let tile = try #require(try Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames[w0])
        #expect(tile.width > 0.9 * visible.width && tile.height > 0.9 * visible.height, "window 0's tile \(tile) does not fill \(visible)")
        let wantedHome = Planner.clamp(home, into: visible)

        var frames: [Rect?] = []
        let settled = await waitUntil(timeout: .seconds(5)) {
            _ = try? await fixture.send("list")
            frames = (0..<2).map { index in fixture.windows.first { $0.index == index }?.frame }
            return frames[0].map { near($0, tile) } == true && frames[1].map { near($0, wantedHome) } == true
        }
        #expect(settled, "windows are at \(frames), not window 0 at its tile \(tile) and window 1 at its home frame \(wantedHome)")
        #expect(arrange.arranger.history.depth(for: migratedKey) == 0, "the migration left an undo step")

        // The launch write already went down: schema 4, no Desktop node.
        let saved = try String(contentsOf: file, encoding: .utf8)
        let version = try JSONSerialization.jsonObject(with: Data(saved.utf8)) as? [String: Any]
        #expect(version?["schemaVersion"] as? Int == LayoutFile.schemaVersion && LayoutFile.schemaVersion == 4, "layout.json still says \(String(describing: version?["schemaVersion"]))")
        #expect(!saved.contains("\"hidden\""), "the saved layout.json still names a Desktop node")
    }
}
