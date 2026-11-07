import SwiftUI
import TransomEngine

/// Settings ▸ Zoom & Gestures (09 UI-SPEC Tab 3). "Use zoom" shows the stored `zoomEnabled` but writes only through
/// `setZoomEnabled`, the menu's Turn On/Off Zoom path, so the announcement and the Turn Off flow run (D-02, T-09-08).
struct ZoomGesturesTab: View {
    let setZoomEnabled: (Bool) -> Void
    @AppStorage(ZoomController.enabledKey) private var zoomEnabled = true
    /// Read lazily by ZoomInput on each double-click, with no onChange, so `@AppStorage` is safe.
    @AppStorage(ShortcutsModel.doubleClickKey) private var doubleClick = true

    static func zoomBinding(isOn: Bool, setZoomEnabled: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { isOn }, set: { (on: Bool) -> Void in setZoomEnabled(on) })
    }

    static func mouseFooter(zoomOn: Bool) -> String {
        zoomOn ? ZoomCopy.doubleClickFooterOn : ZoomCopy.doubleClickFooterZoomOff
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsCopy.useZoom, isOn: Self.zoomBinding(isOn: zoomEnabled, setZoomEnabled: setZoomEnabled))
            } header: {
                Text(SettingsCopy.zoomSection)
            } footer: {
                Self.rowFooter(SettingsCopy.useZoomFooter)
            }
            Section {
                Toggle(ZoomCopy.doubleClickToggle, isOn: $doubleClick).disabled(!zoomEnabled)
            } header: {
                Text(ZoomCopy.mouseSection)
            } footer: {
                Self.rowFooter(Self.mouseFooter(zoomOn: zoomEnabled))
            }
        }
        .formStyle(.grouped)
    }

    private static func rowFooter(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
