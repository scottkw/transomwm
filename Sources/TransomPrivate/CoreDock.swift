import Darwin
import Foundation

/// Asks the Dock to show Mission Control (private, OVER-03): Transom's fallback when its overview can't open while it
/// has taken the Mission Control keys. Reached only through `dlopen` + `dlsym` of HIServices, never linked.
///
/// Provenance: symbol present in HIServices on macOS 27.2 and 15.7.7 (06-RESEARCH F2, 06-SPIKE spaces-dump); signature
/// (CFStringRef notification, int) from the public gist by unixzii.
public enum CoreDock {
    typealias SendNotification = @convention(c) (CFString, Int32) -> Void

    /// Toggles Mission Control.
    public static let missionControl = "com.apple.expose.awake"

    private static let function: SendNotification? = {
        guard !Capabilities.isForcedOff(.coreDock),
              let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDockSendNotification")
        else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()

    public static var isLoaded: Bool { function != nil }

    /// False when the capability is unavailable; the call itself reports nothing back.
    @discardableResult
    public static func send(_ notification: String, session: CapabilitySession = Capabilities.session) -> Bool {
        guard session.isAvailable(.coreDock), let function else { return false }
        function(notification as CFString, 0)
        return true
    }
}
