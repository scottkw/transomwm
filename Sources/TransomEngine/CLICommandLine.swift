/// What the `transom` tool's arguments ask for (08 UI-SPEC Surface 5), checked against the URL allow-list's tables.
public enum CLICommandLine {
    public enum Parsed: Equatable {
        case help
        /// The URL path after the scheme: `zoom-out`, `view/3`.
        case send(String)
        /// The stderr line for a bad command line (exit 64).
        case usage(String)
    }

    public static func parse(_ arguments: [String]) -> Parsed {
        guard let first = arguments.first else { return .help }
        if arguments.count == 2, first == "view" || first == "save-view" { return .send("\(first)/\(arguments[1])") }
        if arguments.count == 1, first.hasPrefix("view/") || first.hasPrefix("save-view/") || TransomURL.commands[first] != nil { return .send(first) }
        return .usage(CLICopy.unknownCommand(first))
    }
}
