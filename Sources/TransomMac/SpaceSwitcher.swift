import CoreGraphics
import TransomEngine
import TransomPrivate
import os

/// Switches a display to another Space by posting the user's own Mission Control chords (06-RESEARCH Pattern 3), then
/// waits up to 1 s for SkyLight to report the change. Never writes SkyLight Space state; hotkeys are only read.
@MainActor final class SpaceSwitcher {
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "spaces")
    private let spaces: () -> SpacesSnapshot?
    static let timeout = Duration.seconds(1)

    init(spaces: @escaping () -> SpacesSnapshot?) {
        self.spaces = spaces
    }

    /// True once `display` shows `space` (at once when it already does); false when there is no route or the Space has
    /// not changed within 1 s.
    func switchTo(space: UInt64, on display: String) async -> Bool {
        guard let list = spaces()?.displays.first(where: { $0.displayUUID == display }),
            let current = SkyLightSpaces.currentSpace(displayUUID: display) ?? list.current,
            let from = list.spaces.firstIndex(where: { $0.id == current }), let to = list.spaces.firstIndex(where: { $0.id == space })
        else {
            logger.notice("switch to space \(space, privacy: .public) failed: not listed on display \(display, privacy: .public)")
            return false
        }
        let chords = SpaceSwitchPlan.plan(from: from, to: to, target: list.spaces[to], hotkeys: Self.hotkey)
        guard !chords.isEmpty else { return true }
        let method = chords.map { "\($0.keyCode)" }.joined(separator: ",")
        logger.info("switch to space \(space, privacy: .public) via keys \(method, privacy: .public)")
        await Self.waitForInputUp()
        for chord in chords { Self.post(chord) }
        let deadline = ContinuousClock.now + Self.timeout
        while ContinuousClock.now < deadline {
            if SkyLightSpaces.currentSpace(displayUUID: display) == space { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        logger.notice("switch to space \(space, privacy: .public) failed after 1 s")
        return false
    }

    /// keyDown with the chord's explicit flags, so held modifiers never change it (Pitfall 7), then keyUp with none: a
    /// keyUp still carrying ⌃ leaves ⌃ marked down in the HID state after the post (seen in the VM, 06-07).
    static func post(_ chord: Chord) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: down) else { return }
            event.flags = down ? CGEventFlags(rawValue: chord.flags) : []
            event.post(tap: .cghidEventTap)
        }
    }

    /// ⌘ ⌘ ⇧ ⌥ ⌃ ⇧ ⌥ ⌃ (right and left) and fn.
    static let modifierKeys: [CGKeyCode] = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    /// The symbolic hotkey's chord and enabled state, read-only; nil when the getter is unavailable.
    private static func hotkey(_ id: Int32) -> SpaceSwitchPlan.HotKey? {
        guard let value = SymbolicHotKeys.value(id), let enabled = SymbolicHotKeys.isEnabled(id) else { return nil }
        return (enabled, value.keyCode, value.modifiers)
    }

    /// Posts only after the triggering click or chord's modifiers are released (T-06-19), waiting at most 500 ms.
    private static func waitForInputUp() async {
        for _ in 0..<25 {
            let mouse = [CGMouseButton.left, .right, .center].contains { CGEventSource.buttonState(.hidSystemState, button: $0) }
            if !mouse, !Self.modifierKeys.contains(where: { CGEventSource.keyState(.hidSystemState, key: $0) }) { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
