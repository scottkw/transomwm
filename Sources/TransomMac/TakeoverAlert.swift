import AppKit

/// The Replace Mission Control explanation (UI-SPEC Surface 5): a modeless informational alert, "Replace Mission
/// Control" first and default (Return), "Not Now" with Esc; closing it counts as Not Now. It waits while `isBusy` (a
/// drag, a held mouse button, the overview open) and reads {Keys} when it appears. Tracking, hotkeys and zoom keep
/// working while it is up.
@MainActor final class TakeoverAlert: NSObject, NSWindowDelegate {
    private let alert = NSAlert()
    private let chord: () -> OverviewCopy.Chord
    private let isBusy: () -> Bool
    private let answered: (_ confirmed: Bool) -> Void
    private let retry = WakeTimer()
    private var done = false

    init(chord: @escaping () -> OverviewCopy.Chord, isBusy: @escaping () -> Bool, answered: @escaping (_ confirmed: Bool) -> Void) {
        self.chord = chord
        self.isBusy = isBusy
        self.answered = answered
        super.init()
        alert.alertStyle = .informational
        alert.messageText = OverviewCopy.takeoverAlertMessage
        let replace = alert.addButton(withTitle: OverviewCopy.replaceMissionControl)  // first: default, Return
        let notNow = alert.addButton(withTitle: OverviewCopy.takeoverNotNow)
        notNow.keyEquivalent = "\u{1b}"  // NSAlert gives Esc only to a button titled Cancel
        replace.target = self
        replace.action = #selector(replacePressed)
        notNow.target = self
        notNow.action = #selector(notNowPressed)
    }

    func show() {
        guard !isBusy() else {
            retry.set(.now + .milliseconds(500)) { [weak self] in self?.show() }
            return
        }
        alert.informativeText = OverviewCopy.takeoverAlertInformative(chord())  // hotkey 32 as it is now, before apply
        alert.layout()
        alert.window.delegate = self
        alert.window.hidesOnDeactivate = false
        NSApp.activate()
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
    }

    @objc private func replacePressed() { finish(true) }
    @objc private func notNowPressed() { finish(false) }
    func windowWillClose(_ notification: Notification) { finish(false) }

    private func finish(_ confirmed: Bool) {
        guard !done else { return }
        done = true
        alert.window.orderOut(nil)
        answered(confirmed)
    }
}
