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
        for name in ["view", "save-view"] where first == name || first.hasPrefix(name + "/") {
            let slots = (first == name ? [] : [String(first.dropFirst(name.count + 1))]) + arguments.dropFirst()
            guard slots.count <= 1 else { return .usage(CLICopy.tooManyArguments) }
            guard let slot = slots.first, TransomURL.slot(digit: slot) != nil else { return .usage(CLICopy.needsSlot(name)) }
            return .send("\(name)/\(slot)")
        }
        if first == "settings" {
            switch arguments.count {
            case 1: return .send("settings")
            // Only a known raw value reaches the URL, never the argument text; an unknown pane opens General (D-04).
            case 2: return .send("settings?pane=\((SettingsPane(rawValue: arguments[1]) ?? .general).rawValue)")
            default: return .usage(CLICopy.settingsTooManyArguments)
            }
        }
        let isHelp = ["help", "-h", "--help"].contains(first)
        guard isHelp || TransomURL.commands[first] != nil else { return .usage(CLICopy.unknownCommand(first)) }
        switch arguments.count {
        case 1: return isHelp ? .help : .send(first)
        case 2: return .usage(CLICopy.takesNoArgument(first))
        default: return .usage(CLICopy.tooManyArguments)
        }
    }
}
