import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Exclusions (09 UI-SPEC Tab 5). Reads and writes the store the menu's Never Arrange list uses (D-02), so
/// its `onChange` hands every edit to the window system.
struct ExclusionsTab: View {
    @ObservedObject var exclusions: ExclusionStore
    /// The installed app's display name, or nil when no app has this bundle ID.
    let displayName: (String) -> String?
    @State private var selection = Set<String>()
    /// The last + click's refusals, one line per refused app.
    @State private var refusal: String?

    enum Decision: Equatable {
        case add(String)
        case refuseSelf
        case refuseNoBundleID
    }

    /// `own` is `Bundle.main.bundleIdentifier`, so the debug build refuses its own `.debug` ID.
    static func decide(bundleID: String?, own: String?) -> Decision {
        guard let bundleID, ExclusionStore.isValid(bundleID) else { return .refuseNoBundleID }
        if let own, bundleID.caseInsensitiveCompare(own) == .orderedSame { return .refuseSelf }
        return .add(bundleID)
    }

    /// Adds every qualifying chosen app; returns the refusal lines for the rest, or nil when none was refused.
    static func exclude(_ apps: [(bundleID: String?, name: String)], own: String?, in exclusions: ExclusionStore) -> String? {
        var refusals: [String] = []
        for app in apps {
            switch decide(bundleID: app.bundleID, own: own) {
            case .add(let id): try? exclusions.add(id)  // only throws for an invalid ID, which decide ruled out
            case .refuseSelf: refusals.append(SettingsCopy.cantExcludeSelf)
            case .refuseNoBundleID: refusals.append(SettingsCopy.noBundleID(MenuCopy.truncatedAppName(app.name)))
            }
        }
        return refusals.isEmpty ? nil : refusals.joined(separator: "\n")
    }

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
                Button { addApps() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(SettingsCopy.addApp)
                Button { removeSelection() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(SettingsCopy.removeApp)
                    .disabled(selection.isEmpty)
                Spacer()
            }
            .padding(.top, 4)
            if let refusal {
                Text(refusal).font(.subheadline).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            Text(SettingsCopy.exclusionsFooter)
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(20)
    }

    private func addApps() {
        refusal = nil
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = SettingsCopy.addAppMessage
        panel.prompt = SettingsCopy.addAppPrompt
        guard panel.runModal() == .OK else { return }
        let apps: [(bundleID: String?, name: String)] = panel.urls.map { url in
            let name = FileManager.default.displayName(atPath: url.path)
            return (bundleID: Bundle(url: url)?.bundleIdentifier, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
        }
        refusal = Self.exclude(apps, own: Bundle.main.bundleIdentifier, in: exclusions)
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
