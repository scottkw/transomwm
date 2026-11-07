import SwiftUI
import TransomEngine

/// Settings ▸ Zoom & Gestures (09 UI-SPEC Tab 3). "Use zoom" shows the stored `zoomEnabled` but writes only through
/// `setZoomEnabled`, the menu's Turn On/Off Zoom path, so the announcement and the Turn Off flow run (D-02, T-09-08).
struct ZoomGesturesTab: View {
    let setZoomEnabled: (Bool) -> Void
    let gestures: GesturePreference
    /// Observable, so the Mission Control toggle follows `state`; nil when the app has no takeover.
    let takeover: MissionControlTakeover?
    /// StatusItemController's explanation-alert flow (`choose(explain:)` with TakeoverAlert).
    let chooseTakeover: () -> Void
    @AppStorage(ZoomController.enabledKey) private var zoomEnabled = true
    /// Read lazily by ZoomInput on each double-click, with no onChange, so `@AppStorage` is safe.
    @AppStorage(ShortcutsModel.doubleClickKey) private var doubleClick = true

    static func zoomBinding(isOn: Bool, setZoomEnabled: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { isOn }, set: { (on: Bool) -> Void in setZoomEnabled(on) })
    }

    static func optionBinding(_ gestures: GesturePreference) -> Binding<Bool> {
        Binding(get: { gestures.takesOption }, set: { (on: Bool) -> Void in gestures.setOption(on) })
    }

    static func wallpaperBinding(_ gestures: GesturePreference) -> Binding<Bool> {
        Binding(get: { gestures.takesWallpaper }, set: { (on: Bool) -> Void in gestures.setWallpaper(on) })
    }

    /// Every write runs the takeover's own flow, whatever was asked: it shows on only once `state` is `.on` (T-09-11).
    static func takeoverBinding(isOn: Bool, choose: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { isOn }, set: { (_: Bool) -> Void in choose() })
    }

    static func takeoverUsable(_ takeover: MissionControlTakeover?, zoomOn: Bool) -> Bool {
        takeover?.isAvailable == true && zoomOn
    }

    static func takeoverFooter(_ takeover: MissionControlTakeover?, zoomOn: Bool) -> String {
        guard let takeover, takeover.isAvailable else { return SettingsCopy.takeoverUnavailable }
        guard zoomOn else { return ZoomCopy.doubleClickFooterZoomOff }
        return SettingsCopy.takeoverFooter(OverviewCopy.takeoverAlertKeys(takeover.currentChord))
    }

    static func trackpadFooter(zoomOn: Bool) -> String {
        zoomOn ? SettingsCopy.gestureOptionFooter : ZoomCopy.doubleClickFooterZoomOff
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
                Toggle(SettingsCopy.gestureOption, isOn: Self.optionBinding(gestures)).disabled(!zoomEnabled)
                Toggle(SettingsCopy.gestureWallpaper, isOn: Self.wallpaperBinding(gestures)).disabled(!zoomEnabled)
            } header: {
                Text(SettingsCopy.trackpadSection)
            } footer: {
                Self.rowFooter(Self.trackpadFooter(zoomOn: zoomEnabled))
            }
            Section {
                Toggle(ZoomCopy.doubleClickToggle, isOn: $doubleClick).disabled(!zoomEnabled)
            } header: {
                Text(ZoomCopy.mouseSection)
            } footer: {
                Self.rowFooter(Self.mouseFooter(zoomOn: zoomEnabled))
            }
            Section {
                Toggle(
                    SettingsCopy.useMissionControlKeys,
                    isOn: Self.takeoverBinding(isOn: takeover?.isOn == true, choose: chooseTakeover)
                ).disabled(!Self.takeoverUsable(takeover, zoomOn: zoomEnabled))
            } header: {
                Text(SettingsCopy.missionControlSection)
            } footer: {
                Self.rowFooter(Self.takeoverFooter(takeover, zoomOn: zoomEnabled))
            }
        }
        .formStyle(.grouped)
    }

    private static func rowFooter(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
