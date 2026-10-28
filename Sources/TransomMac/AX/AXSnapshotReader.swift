import ApplicationServices
import TransomEngine
import TransomModel
import TransomPrivate

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

    /// One app's windows, read on the calling thread (for `transom-dump`; the live system reads on the app's thread).
    public static func observeApp(pid: Int32, bundleID: String) -> AppObservation {
        let app = AXUIElementCreateApplication(pid)
        var resolver = WindowIDResolver(pid: pid)
        // Never cancelled, so never nil.
        return observeApp(app, pid: pid, bundleID: bundleID, hidden: isHidden(app), resolver: &resolver)!.observation
    }

    /// Also returns the listed window elements by window ID (nil when `AXWindows` failed), for the app thread's cache.
    /// `cache` is that cache and `resolver` the app thread's `WindowIDResolver`, which assigns each element its ID
    /// through `_AXUIElementGetWindow` or, without it (or with `forceFallback`), by frame against one CG snapshot.
    /// `isCancelled` is checked between AX calls; once it returns true the read stops and returns nil.
    static func observeApp(
        _ app: AXUIElement, pid: Int32, bundleID: String, hidden: Bool, cache: [UInt32: CachedWindow] = [:],
        resolver: inout WindowIDResolver, forceFallback: Bool = false, isCancelled: () -> Bool = { false }
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
        var reads: [(snapshot: Result<WindowSnapshot, AXFailure>, title: String)] = []
        for element in elements {
            if isCancelled() { return nil }
            reads.append(read(element))
        }
        let items = zip(elements, reads).map { element, read in
            let window = if case .success(let snapshot) = read.snapshot, snapshot.role == kAXWindowRole { snapshot } else { WindowSnapshot?.none }
            return WindowIDResolver.Item(element: element, isReadableWindow: window != nil, frame: window?.frame, title: read.title)
        }
        let resolution = resolver.resolve(
            items, cache: cache, lookup: windowIDLookup(forced: forceFallback), session: Capabilities.session,
            cgWindows: { CGWindowList.snapshot() }, cgNames: { CGWindowList.names(pid: pid) })
        let windows = zip(reads, resolution.ids).map { read, id in
            WindowObservation(windowID: id?.id, idSource: id?.source ?? .axPrivate, read: read.snapshot, title: read.title, replacesWindowID: id?.replaces)
        }
        return (AppObservation(pid: pid, bundleID: bundleID, appHidden: hidden, windows: windows, duration: start.duration(to: .now),
                               identityPending: resolution.identityPending), resolution.byID)
    }

    /// `_AXUIElementGetWindow` as a lookup that returns the CGWindowID on success; nil when the fallback is forced,
    /// the function is missing or the capability is off.
    private static func windowIDLookup(forced: Bool) -> ((AXUIElement) -> UInt32?)? {
        guard !forced, Capabilities.isAvailable(.axWindowID), let function = AXWindowID.function else { return nil }
        return { element in
            var id: CGWindowID = 0
            return function(element, &id) == .success ? id : nil
        }
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
            let frame = Rect(x: origin.x, y: origin.y, width: size.width, height: size.height)
            snapshot.frame = frame
            snapshot.greenButton = greenButton(values[13], else: values[12], in: frame)
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

    /// The green button (the fullscreen button, else the zoom button) as an offset from the window's top-left, read with
    /// one batched call (RESEARCH Pattern 5). An app reports these values itself, so a rect that is not finite or not
    /// inside the window is dropped: a bogus one can only ever cover that window (T-03-36).
    private static func greenButton(_ fullScreen: CFTypeRef, else zoom: CFTypeRef, in frame: Rect) -> Rect? {
        let isElement = { (value: CFTypeRef) in CFGetTypeID(value) == AXUIElementGetTypeID() }
        guard let value = isElement(fullScreen) ? fullScreen : isElement(zoom) ? zoom : nil else { return nil }
        var array: CFArray?
        let names = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(value as! AXUIElement, names, AXCopyMultipleAttributeOptions(rawValue: 0), &array) == .success,
            let values = array as? [CFTypeRef], values.count == 2, let origin = point(values[0]), let size = size(values[1])
        else { return nil }
        let offset = Rect(x: origin.x - frame.x, y: origin.y - frame.y, width: size.width, height: size.height)
        guard offset.isValidGeometry, offset.width > 0, offset.height > 0, offset.minX >= 0, offset.minY >= 0,
            offset.maxX <= frame.width, offset.maxY <= frame.height
        else { return nil }
        return offset
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
