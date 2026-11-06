import TransomEngine
import Testing

/// 08 UI-SPEC Surface 5: what every command line means, with the exact usage messages.
@Suite struct CLICommandLineTests {
    @Test(arguments: [[], ["help"], ["-h"], ["--help"]] as [[String]])
    func helpForms(_ arguments: [String]) {
        #expect(CLICommandLine.parse(arguments) == .help)
    }

    @Test(arguments: [
        (["view", "3"], "view/3"), (["view/3"], "view/3"), (["save-view", "9"], "save-view/9"), (["save-view/1"], "save-view/1"),
        (["zoom-out"], "zoom-out"), (["move-out-of-group"], "move-out-of-group"), (["dock-column-1"], "dock-column-1"), (["dock-row-middle"], "dock-row-middle"),
        (["dock-left-half"], "dock-left-half"), (["dock-right-half"], "dock-right-half"), (["dock-top-half"], "dock-top-half"),
        (["dock-bottom-half"], "dock-bottom-half"), (["dock-left-third"], "dock-left-third"), (["dock-center-third"], "dock-center-third"),
        (["dock-right-third"], "dock-right-third"), (["dock-top-third"], "dock-top-third"), (["dock-middle-third"], "dock-middle-third"),
        (["dock-bottom-third"], "dock-bottom-third"),
    ] as [([String], String)])
    func commandsToSend(arguments: [String], path: String) {
        #expect(CLICommandLine.parse(arguments) == .send(path))
    }

    @Test(arguments: ["foo", "VIEW", "zoom-out/3", "transom://view/3", "", "dock-column-5", "toggle-desktop", "frame-desktop", "dock-half", "dock-left-quarter"])
    func unknownCommands(_ command: String) {
        #expect(CLICommandLine.parse([command]) == .usage("transom: unknown command \"\(command)\". Run \"transom help\" to see every command."))
    }

    @Test func anUnknownCommandIsPrintedAsASCII() {
        #expect(CLICommandLine.parse(["\u{201C}x\u{201D}"]) == .usage("transom: unknown command \"\"x\"\". Run \"transom help\" to see every command."))
    }

    @Test(arguments: [["view"], ["view", "0"], ["view", "10"], ["view", "x"], ["view", "03"], ["view", "%33"], ["view/"], ["view/0"], ["view/10"], ["view/x"]] as [[String]])
    func badViewSlots(_ arguments: [String]) {
        #expect(CLICommandLine.parse(arguments) == .usage("transom: view needs a slot from 1 to 9, as in \"transom view 3\"."))
    }

    @Test(arguments: [["save-view"], ["save-view", "0"], ["save-view", "10"], ["save-view", "x"], ["save-view/x"]] as [[String]])
    func badSaveViewSlots(_ arguments: [String]) {
        #expect(CLICommandLine.parse(arguments) == .usage("transom: save-view needs a slot from 1 to 9, as in \"transom save-view 3\"."))
    }

    @Test func aParameterlessCommandTakesNoArgument() {
        #expect(CLICommandLine.parse(["zoom-out", "3"]) == .usage("transom: zoom-out takes no argument."))
        #expect(CLICommandLine.parse(["help", "3"]) == .usage("transom: help takes no argument."))
        #expect(CLICommandLine.parse(["dock-column-1", "3"]) == .usage("transom: dock-column-1 takes no argument."))
        #expect(CLICommandLine.parse(["dock-left-half", "3"]) == .usage("transom: dock-left-half takes no argument."))
    }

    @Test(arguments: [["view", "3", "4"], ["view/3", "4"], ["zoom-out", "3", "4"]] as [[String]])
    func tooManyArguments(_ arguments: [String]) {
        #expect(CLICommandLine.parse(arguments) == .usage("transom: too many arguments. Run \"transom help\" to see every command."))
    }
}
