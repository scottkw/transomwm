/// The `transom` tool's copy (08 UI-SPEC Surface 5): every stderr line starts with "transom: " and stays ASCII.
public enum CLICopy {
    public static let help = "Usage: transom <command>"
    public static let notRunning = "transom: Transom is not running"
    public static let didNotAnswer = "transom: Transom didn't answer"
    public static let rateLimited = "transom: refused (rate limit). Each command runs at most once per second."
    /// The refusal reason when zoom is off: the app has no announcement for it, its hotkeys being disabled then.
    public static let zoomOff = "Zoom is off"

    public static func refused(_ reason: String) -> String { "transom: refused: \(reason)" }
    public static func unknownCommand(_ command: String) -> String {
        "transom: unknown command \"\(command)\". Run \"transom help\" to see every command."
    }
}
