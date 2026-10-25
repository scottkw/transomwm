import ApplicationServices
import PaneEngine
import PaneModel
import PanePrivate

/// Window-ID resolution for one app (D-15, SAFE-05), owned by its `AXAppThread` and confined to that thread.
nonisolated struct WindowIDResolver {
    struct Item {
        let element: AXUIElement
        /// The batched read succeeded with role AXWindow: only such an element's lookup failure is unexpected.
        let isReadableWindow: Bool
        let frame: Rect?
        let title: String
    }

    struct Resolved: Equatable {
        let id: UInt32
        let source: WindowIDSource
        /// The ID the element was cached under, when this resolve changed it.
        let replaces: UInt32?
    }

    struct Resolution {
        /// Parallel to the items; nil means unidentified this pass.
        var ids: [Resolved?]
        var byID: [UInt32: CachedWindow]
        /// A new element waits one more refresh before the frame fallback may identify it.
        var identityPending: Bool
    }

    let pid: Int32

    init(pid: Int32) {
        self.pid = pid
    }

    /// `lookup` nil means unavailable (forced fallback or capability off).
    mutating func resolve(
        _ items: [Item], cache: [UInt32: CachedWindow], lookup: ((AXUIElement) -> UInt32?)?, session: CapabilitySession,
        cgWindows: () -> [CGWindowEntry]?, cgNames: () -> [UInt32: String]
    ) -> Resolution {
        Resolution(ids: items.map { _ in nil }, byID: [:], identityPending: false)  // RED stub (02-16 Task 2)
    }
}
