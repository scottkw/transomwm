import CoreGraphics

/// The undocumented CGEvent gesture constants (Phase 5). These are event type and field numbers, not dlsym symbols, so
/// they need no Capabilities entry: a field macOS stops populating reads 0, nothing latches and every event passes,
/// which is the fallback (RESEARCH Pattern 6). Every undocumented field number lives in this one file.
///
/// Type 30 is Dock control (Spaces and Mission Control swipes), NOT magnify, and must never appear in a tap mask.
/// The trap: `NSEvent.EventTypeMask.magnify` is `1 << 30`, because AppKit numbers its magnify event 30 and builds it
/// from CG type 29 with field 110 = 8 (RESEARCH Pitfall 1).
public enum GestureEventFields {
    /// `kCGSEventGesture`: pinch, rotate and two-finger touch envelopes. WebKit CoreGraphicsTestSPI.h
    /// (`kCGSEventGesture = 29`), ScrollToZoom CGEventSPI.h, joshuarli/iss iss.c, and a local AppKit-bridge probe on
    /// macOS 27.0.1 that decoded a type-29 event as NSEventTypeMagnify.
    public static let gestureType: UInt32 = 29
    /// `kCGSEventDockControl`: Spaces and Mission Control swipes. Never tapped by Transom; only the spike's listen-only
    /// `tap-listen` observes it. WebKit CoreGraphicsTestSPI.h (`kCGSEventDockControl = 30`), ScrollToZoom, iss.
    public static let dockControlType: UInt32 = 30

    /// Gesture HID sub-type: 8 zoom, 5 rotate, 61/62 gesture started/ended envelopes. WebKit
    /// (`kCGEventGestureHIDType = 110`), ScrollToZoom, and the local AppKit-bridge probe.
    public static let hidType = CGEventField(rawValue: 110)!
    /// The zoom (magnification) delta. WebKit (`kCGEventGestureZoomValue = 113`), ScrollToZoom, local probe.
    public static let zoomValue = CGEventField(rawValue: 113)!
    /// Gesture phase in CG phase values (1 began, 2 changed, 4 ended, 8 cancelled, 128 may begin), not NSEvent.Phase.
    /// WebKit (`kCGEventGesturePhase = 132`), iss, local probe.
    public static let phase = CGEventField(rawValue: 132)!
    /// The real event type, which iss reads instead of the callback's type. WebKit (`kCGSEventTypeField = 55`), iss.
    public static let realType = CGEventField(rawValue: 55)!
    /// Registry entry ID of the HID service that sent the event: tells the built-in trackpad from a Magic Trackpad
    /// and should match the multitouch device's registry ID. ScrollToZoom (`kCGEventRegistryID = 87`), mirroir-mcp.
    public static let senderID = CGEventField(rawValue: 87)!

    /// Field 110 values (WebKit, ScrollToZoom `kIOHIDEventTypeZoom = 8` / `kIOHIDEventTypeRotation = 5`).
    public static let hidZoom: Int64 = 8
    public static let hidRotate: Int64 = 5
    public static let hidGestureStarted: Int64 = 61
    public static let hidGestureEnded: Int64 = 62
}
