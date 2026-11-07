import AppKit
import SwiftUI

/// Settings ▸ Exclusions (09 UI-SPEC Tab 5). Reads and writes the store the menu's Never Arrange list uses (D-02), so
/// its `onChange` hands every edit to the window system.
struct ExclusionsTab: View {
    @ObservedObject var exclusions: ExclusionStore
    /// The installed app's display name, or nil when no app has this bundle ID.
    let displayName: (String) -> String?
    @State private var selection = Set<String>()

    struct Row: Equatable {
        let bundleID: String
        let title: String
        let installed: Bool
    }

    /// `ExclusionStore.sortedEntries` order; an app no longer installed is titled by its bundle ID.
    static func rows(_ exclusions: ExclusionStore, displayName: (String) -> String?) -> [Row] {
        var names: [String: String] = [:]
        for id in exclusions.bundleIDs { names[id] = displayName(id) }
        return exclusions.sortedEntries(displayNames: names).map { entry in
            let installed = names[entry.bundleID] != nil
            return Row(bundleID: entry.bundleID, title: installed ? MenuCopy.truncatedAppName(entry.title) : entry.bundleID, installed: installed)
        }
    }

    var body: some View {
        let rows = Self.rows(exclusions, displayName: displayName)
        VStack(alignment: .leading, spacing: 0) {
            List(rows, id: \.bundleID, selection: $selection) { row in
                HStack {
                    Self.icon(row)
                    Text(row.title).foregroundStyle(row.installed ? .primary : .secondary)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if rows.isEmpty { Text(MenuCopy.noExclusions).foregroundStyle(.secondary) }
            }
            HStack(spacing: 0) {
                Button { removeSelection() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(SettingsCopy.removeApp)
                    .disabled(selection.isEmpty)
                Spacer()
            }
            .padding(.top, 4)
            Text(SettingsCopy.exclusionsFooter)
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(20)
    }

    /// At once and unconfirmed: + or the menu adds an app back.
    private func removeSelection() {
        for id in selection { exclusions.remove(id) }
        selection = []
    }

    private static func icon(_ row: Row) -> some View {
        Group {
            if row.installed, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
