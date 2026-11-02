import AppKit

/// Close Group's confirmation (UI-SPEC Surface 4, 2026-11-02): "Close Group" first and default (Return), "Cancel" with
/// Esc, and "Do not show this again". Checked on a confirmed alert, it is kept in UserDefaults as `tabs.confirmCloseGroup`
/// = false; checked on a canceled one, it is not, so a canceled alert never makes the next Close Group silent.
@MainActor final class CloseGroupConfirmation {
    static let key = "tabs.confirmCloseGroup"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// True unless the user chose not to be asked; a missing or non-Bool value asks.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.key) }
    }

    /// Whether to close the group's `count` windows: true at once when suppressed, else the alert's answer. The app
    /// frontmost before the alert is activated again, so a save prompt shows in front.
    func confirm(count: Int) -> Bool {
        guard isEnabled else { return true }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = TabCopy.closeGroupAlertMessage(count)
        alert.informativeText = TabCopy.closeGroupAlertInformative
        alert.addButton(withTitle: TabCopy.closeGroup)  // first: default, Return
        alert.addButton(withTitle: TabCopy.closeGroupAlertCancel)  // titled Cancel: NSAlert gives it Esc
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = TabCopy.doNotShowAgain
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on { isEnabled = false }
        if let previous, previous.processIdentifier != getpid() { previous.activate() }
        return confirmed
    }
}
