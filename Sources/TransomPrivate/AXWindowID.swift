import ApplicationServices
import Darwin

/// `_AXUIElementGetWindow`: the CGWindowID behind an AX window element (private, HIServices).
///
/// Reached only through `dlopen` + `dlsym`, never linked, so a removed symbol leaves `function`
/// nil and windows fall back to CG frame matching instead of the app failing to launch.
/// It is AX IPC: call it on the app's AX thread, never on main (it blocks on a frozen app).
public enum AXWindowID {
    public typealias Fn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    public static let function: Fn? = {
        guard !Capabilities.isForcedOff(.axWindowID) else { return nil }
        // RTLD_DEFAULT is not importable, and a default-handle lookup misses when HIServices is not loaded yet.
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow")
        else { return nil }
        return unsafeBitCast(symbol, to: Fn.self)
    }()
}
