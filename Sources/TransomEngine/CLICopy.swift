import Foundation

/// The `transom` tool's copy (08 UI-SPEC Surface 5): every stderr line starts with "transom: " and stays ASCII.
public enum CLICopy {
    public static let notRunning = "transom: Transom is not running"
    public static let didNotAnswer = "transom: Transom didn't answer"
    public static let rateLimited = "transom: refused (rate limit). Each command runs at most once per second."
    public static let tooManyArguments = "transom: too many arguments. Run \"transom help\" to see every command."
    /// The refusal reason when zoom is off: the app has no announcement for it, its hotkeys being disabled then.
    public static let zoomOff = "Zoom is off"

    public static func refused(_ reason: String) -> String { "transom: refused: \(ascii(reason))" }
    public static func refusedWithoutReason(_ command: String) -> String { refused("\(command) can't act right now") }
    public static func unknownCommand(_ command: String) -> String {
        "transom: unknown command \"\(ascii(command))\". Run \"transom help\" to see every command."
    }
    public static func needsSlot(_ command: String) -> String { "transom: \(command) needs a slot from 1 to 9, as in \"transom \(command) 3\"." }
    public static func takesNoArgument(_ command: String) -> String { "transom: \(command) takes no argument." }

    /// Output is safe in any terminal, log or script: the app's curly quotes and "…" go straight, and anything else that
    /// isn't printable ASCII, such as a control character from whoever answered on the port, becomes "?".
    public static func ascii(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{2018}", "\u{2019}": result += "'"
            case "\u{201C}", "\u{201D}": result += "\""
            case "\u{2026}": result += "..."
            case " "..."~": result.unicodeScalars.append(scalar)
            default: result += "?"
            }
        }
        return result
    }

    /// The whole help text (D-09). The command lines come from `TransomURL.helpLines`.
    public static let help: String = {
        var sections: [String] = []
        var lines: [String] = []
        var current: String?
        for line in TransomURL.helpLines {
            if line.section != current {
                if !lines.isEmpty { sections.append(lines.joined(separator: "\n")) }
                lines = [line.section]
                current = line.section
            }
            let usage = line.argument.isEmpty ? line.command : "\(line.command) \(line.argument)"
            lines.append("  " + usage.padding(toLength: 21, withPad: " ", startingAt: 0) + line.description)
        }
        sections.append(lines.joined(separator: "\n"))
        return (["""
            Usage: transom <command>

            Runs a command in the running Transom app. Each command does the same
            as its transom:// URL, for example "transom view 3" is
            transom://view/3.
            """] + sections + ["""
            Exit status: 0 done, 1 refused, 2 Transom is not running,
            64 unknown command or bad argument.
            """]).joined(separator: "\n\n")
    }()
}
