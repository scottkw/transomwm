import ApplicationServices
import PaneEngine
import PaneModel
import PanePrivate

/// A window element on its app thread's cache, with the ID it was given and where that ID came from. Thread-confined.
nonisolated struct CachedWindow {
    let element: AXUIElement
    let source: WindowIDSource
}

/// Builds `AppObservation`s and `WindowSnapshot`s from live AX elements. Every function here is AX IPC:
/// call it only on the app's `AXAppThread`. AX errors map to `AXFailure`, never to nil (WIN-09).
public nonisolated enum AXSnapshotReader {
    /// The batched attributes, in the order `read(_:)` indexes them.
    private static let attributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXModalAttribute, kAXMainAttribute, kAXMinimizedAttribute,
        "AXFullScreen", kAXIdentifierAttribute, kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute,
        kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute, kAXFullScreenButtonAttribute,
        kAXChildrenAttribute,
    ]

    /// One app's windows, read on the calling thread (for `pane-dump`; the live system reads on the app's thread).
    public static func observeApp(pid: Int32, bundleID: String) -> AppObservation {
        let app = AXUIElementCreateApplication(pid)
        // Never cancelled, so never nil.
        return observeApp(app, pid: pid, bundleID: bundleID, hidden: isHidden(app))!.observation
    }

    /// Also returns the listed window elements by window ID (nil when `AXWindows` failed), for the app thread's cache.
    /// `cache` is that cache: an element already in it keeps its ID, and a new one gets the private lookup's ID or,
    /// without it (or with `forceFallback`), is matched by frame against one CG snapshot. `isCancelled` is checked between AX calls; once
    /// it returns true the read stops and returns nil.
    static func observeApp(
        _ app: AXUIElement, pid: Int32, bundleID: String, hidden: Bool, cache: [UInt32: CachedWindow] = [:],
        forceFallback: Bool = false, isCancelled: () -> Bool = { false }
    ) -> (observation: AppObservation, elements: [UInt32: CachedWindow]?)? {
        let start = ContinuousClock.now
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard error == .success else {
            return (AppObservation(pid: pid, bundleID: bundleID, appHidden: hidden, windows: [],
                                   listFailure: AXFailure(code: error.rawValue), duration: start.duration(to: .now)), nil)
        }
        guard let elements = value as? [AXUIElement] else {
            return (AppObservation(pid: pid, bundleID: bundleID, appHidden: hidden, windows: [],
                                   listFailure: .attributeUnsupported, duration: start.duration(to: .now)), nil)
        }
        var byID: [UInt32: CachedWindow] = [:]
        var windows: [WindowObservation] = []
        var fallback = Fallback(pid: pid, cache: cache)
        for element in elements {
            if isCancelled() { return nil }
            let (snapshot, title) = read(element)
            let id = windowID(of: element, snapshot: snapshot, title: title, forceFallback: forceFallback, fallback: &fallback)
            if let id { byID[id.id] = CachedWindow(element: element, source: id.source) }
            windows.append(WindowObservation(
                windowID: id?.id, idSource: id?.source ?? .axPrivate, read: snapshot, title: title, replacesWindowID: id?.replaces))
        }
        return (AppObservation(pid: pid, bundleID: bundleID, appHidden: hidden, windows: windows, duration: start.duration(to: .now)), byID)
    }

    static func snapshot(of window: AXUIElement) -> Result<WindowSnapshot, AXFailure> {
        read(window).snapshot
    }

    /// The app's `AXHidden`. A failed read counts as not hidden; the `AXWindows` read reports the failure.
    static func isHidden(_ app: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXHiddenAttribute as CFString, &value) == .success else { return false }
        return value as? Bool == true
    }

    /// The cached ID of an element already seen; else `_AXUIElementGetWindow` while it is available; otherwise (or
    /// forced, or when it fails for this element) the frame fallback. nil for an element with no window (Finder's
    /// desktop). Each lookup that fails for a real window counts towards switching it off (D-15).
    private static func windowID(
        of element: AXUIElement, snapshot: Result<WindowSnapshot, AXFailure>, title: String, forceFallback: Bool, fallback: inout Fallback
    ) -> (id: UInt32, source: WindowIDSource, replaces: UInt32?)? {
        let function = !forceFallback && Capabilities.isAvailable(.axWindowID) ? AXWindowID.function : nil
        if let cached = fallback.cache.first(where: { CFEqual($0.value.element, element) }) {
            // A fallback ID is checked again while the lookup works, and replaced (the tracker re-keys) when it differs.
            var id: CGWindowID = 0
            guard cached.value.source != .axPrivate, let function, function(element, &id) == .success else {
                return (cached.key, cached.value.source, nil)
            }
            Capabilities.recordSuccess(.axWindowID)
            fallback.bound.insert(id)
            return (id, .axPrivate, id == cached.key ? nil : cached.key)
        }
        if let function {
            var id: CGWindowID = 0
            if function(element, &id) == .success {
                Capabilities.recordSuccess(.axWindowID)
                // shortcut: only IDs bound before a failed element are kept from its frame match; two passes if twins collide.
                fallback.bound.insert(id)
                return (id, .axPrivate, nil)
            }
            // -25201 on a non-window (Finder's desktop) is expected; only a readable AXWindow counts.
            if case .success(let read) = snapshot, read.role == kAXWindowRole { Capabilities.recordFailure(.axWindowID) }
        }
        return fallback.identify(element, snapshot: snapshot, title: title).map { ($0.id, $0.source, nil) }
    }

    /// One observation's frame-fallback state: the app thread's cache, one CG snapshot taken on first need, and the
    /// IDs bound so far, so two identical windows never share one CG window.
    private struct Fallback {
        let pid: Int32
        let cache: [UInt32: CachedWindow]
        var bound: Set<UInt32>
        var cgWindows: [CGWindowEntry]?

        init(pid: Int32, cache: [UInt32: CachedWindow]) {
            self.pid = pid
            self.cache = cache
            bound = Set(cache.keys)
        }

        mutating func identify(_ element: AXUIElement, snapshot: Result<WindowSnapshot, AXFailure>, title: String) -> (id: UInt32, source: WindowIDSource)? {
            guard case .success(let read) = snapshot, read.role == kAXWindowRole, let frame = read.frame else { return nil }
            // No CG list: leave the window unidentified this time rather than give it a synthetic ID.
            guard let cg = cgWindows ?? CGWindowList.snapshot() else { return nil }
            cgWindows = cg
            var match = FallbackMatcher.match(pid: pid, frame: frame, title: title, cgWindows: cg, cgNames: [:], excluding: bound)
            if match == .ambiguous {
                // Names need Screen Recording; they decide this match only and are dropped with it (T-02-31).
                match = FallbackMatcher.match(pid: pid, frame: frame, title: title, cgWindows: cg, cgNames: CGWindowList.names(pid: pid), excluding: bound)
            }
            let id: (id: UInt32, source: WindowIDSource) =
                if case .cg(let windowID) = match { (windowID, .cgFrameMatch) } else {
                    (SyntheticWindowIDs.next(avoiding: Set(cg.map(\.windowID))), .synthetic)
                }
            bound.insert(id.id)
            return id
        }
    }

    private static func read(_ window: AXUIElement) -> (snapshot: Result<WindowSnapshot, AXFailure>, title: String) {
        var array: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(window, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &array)
        guard error == .success, let values = array as? [CFTypeRef], values.count == attributes.count else {
            return (.failure(AXFailure(code: error == .success ? AXError.failure.rawValue : error.rawValue)), "")
        }
        // A dead or hung window can come back as per-attribute errors; keep those, they decide closes.
        if case .failure(let failure) = attributeError(values[0]), failure == .invalidElement || failure == .cannotComplete {
            return (.failure(failure), "")
        }
        func string(_ i: Int) -> String? { values[i] as? String }
        func bool(_ i: Int) -> Bool? { isError(values[i]) ? nil : values[i] as? Bool }

        var snapshot = WindowSnapshot(
            role: string(0), subrole: string(1), modal: bool(2), main: bool(3), minimized: bool(4),
            fullScreen: bool(5), identifier: string(6),
            close: button(values[10]), minimize: button(values[11]), zoom: button(values[12]),
            fullScreenButton: button(values[13])
        )
        if let origin = point(values[8]), let size = size(values[9]) {
            snapshot.frame = Rect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        }
        if let children = values[14] as? [AXUIElement] {
            var sheetAttached = false
            for child in children {
                switch copyString(child, kAXRoleAttribute) {
                case kAXTabGroupRole?:
                    var count: CFIndex = 0
                    if AXUIElementGetAttributeValueCount(child, kAXTabsAttribute as CFString, &count) == .success {
                        snapshot.tabGroup = TabGroupFact(tabCount: count)
                    }
                case kAXSheetRole?:
                    sheetAttached = true
                default:
                    break
                }
            }
            snapshot.sheetAttached = sheetAttached
        }
        return (.success(snapshot), string(7) ?? "")
    }

    private static func isError(_ value: CFTypeRef) -> Bool {
        if case .failure = attributeError(value) { return true }
        return false
    }

    /// A missing attribute in a batched read comes back as an AXValue of type `.axError`.
    private static func attributeError(_ value: CFTypeRef) -> Result<Void, AXFailure> {
        guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError else { return .success(()) }
        var code = AXError.success
        AXValueGetValue(value as! AXValue, .axError, &code)
        return .failure(AXFailure(code: code.rawValue))
    }

    private static func button(_ value: CFTypeRef) -> ButtonFact {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return .absent }
        var enabled: CFTypeRef?
        let ok = AXUIElementCopyAttributeValue(value as! AXUIElement, kAXEnabledAttribute as CFString, &enabled) == .success
        return ButtonFact(present: true, enabled: ok && enabled as? Bool == true)
    }

    static func point(_ value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
