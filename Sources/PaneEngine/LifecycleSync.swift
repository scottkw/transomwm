import PaneModel

/// Maps OS lifecycle facts onto the layout model (D-10).
public enum LifecycleSync {
    public static func handle(_ event: WindowEvent, world: inout World, history: inout UndoHistory) throws(LayoutError) -> Bool {
        false
    }
}
