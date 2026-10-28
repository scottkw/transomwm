import AppKit
import TransomEngine
import TransomModel
import SwiftUI

/// The latest inventory for the Tracked Windows window. `AXWindowSystem.events` has one reader
/// (StatusItemController), which forwards each re-read inventory here.
@MainActor final class TrackedWindowsFeed: ObservableObject {
    @Published var inventory = WindowInventory(displays: [], windows: [])
}

/// 02-UI-SPEC Surface 3: the live table, its footer and the no-permission, loading and empty states.
/// Titles are rendered only, never logged (T-02-23).
struct TrackedWindowsView: View {
    @ObservedObject var feed: TrackedWindowsFeed
    @ObservedObject var permission: PermissionController
    @ObservedObject var exclusions: ExclusionStore
    /// Read on every render: the lookup can be switched off mid-session (D-15).
    let windowIDLookupAvailable: () -> Bool
    let showSetup: () -> Void
    @State private var selection: WindowIdentity?

    var body: some View {
        let inventory = feed.inventory
        let phase = permission.state.phase
        let stale = phase == .staleTrustedButFailing || phase == .resetting || permission.state.showStaleFormB
        let state = TrackedWindowsModel.state(permissionReady: phase == .ready, stale: stale, inventory: inventory)
        let rows = TrackedWindowsModel.rows(
            inventory, exclusions: Set(exclusions.bundleIDs), appNames: Self.appNames(inventory),
            displayNames: Displays.localizedNames()
        )
        VStack(spacing: 0) {
            Group {
                switch state {
                case .noPermission(let stale):
                    ContentUnavailableView {
                        Label("Transom can't see windows yet", systemImage: "lock.shield")
                    } description: {
                        Text("Give Transom Accessibility access to list and arrange windows.")
                    } actions: {
                        Button(MenuCopy.permissionItem(stale: stale), action: showSetup)
                    }
                case .loading:
                    ContentUnavailableView {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for windows\u{2026}")
                        }
                    }
                case .empty:
                    ContentUnavailableView(
                        "No windows to track", systemImage: "macwindow",
                        description: Text("Open a window in any app and it appears here.")
                    )
                case .populated:
                    table(rows)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if state == .populated { Text(TrackedWindowsModel.footer(inventory, rows: rows)) }
                Spacer()
                Text(MenuCopy.capabilityItem(windowIDLookupAvailable: windowIDLookupAvailable()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
    }

    private func table(_ rows: [TrackedWindowRow]) -> some View {
        Table(rows, selection: $selection) {
            TableColumn("App") { row in
                HStack(spacing: 4) {
                    if let icon = NSRunningApplication(processIdentifier: row.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(row.appName).truncationMode(.tail)
                }
            }
            .width(min: 160)
            TableColumn("Title") { row in
                Text(row.title).truncationMode(.middle)
                    .foregroundStyle(row.isPlaceholderTitle ? .secondary : .primary)
                    .help(row.isPlaceholderTitle ? "" : row.title)
            }
            .width(min: 180)
            TableColumn("ID") { row in
                Text(row.idText).monospacedDigit()
                    .foregroundStyle(row.isSyntheticID ? .secondary : .primary)
                    .help(row.isSyntheticID ? "Matched by frame because window ID lookup is unavailable" : "")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72)
            TableColumn("Kind", value: \.kindText).width(min: 160)
            TableColumn("State", value: \.stateText).width(min: 88)
            TableColumn("Tabs") { row in trailing(row.tabsText) }.width(min: 56)
            TableColumn("Frame") { row in trailing(row.frameText).monospacedDigit() }.width(min: 168)
            TableColumn("Display", value: \.displayText).width(min: 140)
            TableColumn("Min Size") { row in trailing(row.minSizeText).monospacedDigit() }.width(min: 96)
            TableColumn("Status") { row in
                HStack(spacing: 4) {
                    if row.isExcluded {
                        badge("Excluded", fill: Color(nsColor: .quaternaryLabelColor), text: Color(nsColor: .secondaryLabelColor))
                    }
                    if row.isNotResponding {
                        badge("Not responding", fill: Color(nsColor: .systemOrange).opacity(0.15), text: Color(nsColor: .systemOrange))
                    }
                }
            }
            .width(min: 120)
        }
        .lineLimit(1)
        .transaction { $0.animation = nil }
    }

    private func trailing(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func badge(_ title: String, fill: Color, text: Color) -> some View {
        Text(title).font(.caption).foregroundStyle(text)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(fill, in: RoundedRectangle(cornerRadius: 4))
    }

    private static func appNames(_ inventory: WindowInventory) -> [Int32: String] {
        var names: [Int32: String] = [:]
        for pid in Set(inventory.windows.map(\.window.pid)) {
            if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { names[pid] = name }
        }
        return names
    }
}
