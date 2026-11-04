@testable import TransomEngine
import Testing

/// 08 UI-SPEC Surface 5: the exact help block, ASCII, at most 72 columns, with one line for every command.
@Suite struct CLICopyTests {
    @Test func theHelpIsTheContractBlock() {
        #expect(CLICopy.help == """
            Usage: transom <command>

            Runs a command in the running Transom app. Each command does the same
            as its transom:// URL, for example "transom view 3" is
            transom://view/3.

            Views
              view <1-9>           Go to a saved view
              save-view <1-9>      Save the current view to a slot

            Zoom
              zoom-out             Zoom out to all windows
              step-out             Zoom out one level
              step-in              Zoom in one level
              back                 Go to the previous view
              forward              Go to the next view
              pan-left             Move the view left
              pan-right            Move the view right
              pan-up               Move the view up
              pan-down             Move the view down
              frame-window         Frame the focused window, or go back
              frame-desktop        Frame the Desktop tile, or go back
              overview             Open or close the overview

            Arrange
              toggle-desktop       Hide or show the Desktop tile
              split-finder         Split with a new Finder window
              restore              Restore all windows

            Tabs
              next-tab             Select the next tab in the focused tab group
              previous-tab         Select the previous tab
              move-out-of-group    Move the focused tab out of its group

            Other
              help                 Show this list

            Exit status: 0 done, 1 refused, 2 Transom is not running,
            64 unknown command or bad argument.
            """)
    }

    @Test func theHelpFitsAnyTerminal() {
        #expect(CLICopy.help.utf8.allSatisfy { $0 < 0x80 })
        #expect(CLICopy.help.split(separator: "\n").allSatisfy { $0.count <= 72 })
    }

    /// D-09: every allow-listed command has exactly one help line.
    @Test func everyCommandHasExactlyOneHelpLine() {
        let allowed = Set(TransomURL.commands.keys).union(["view", "save-view", "help"])
        let listed = TransomURL.helpLines.map(\.command)
        #expect(listed.count == allowed.count)
        #expect(Set(listed) == allowed)
    }

    @Test func asciiStraightensTheAppsTypography() {
        #expect(CLICopy.ascii("Couldn\u{2019}t show \u{201C}Mail\u{201D}\u{2026}") == "Couldn't show \"Mail\"...")
        #expect(CLICopy.ascii("Arranging is paused") == "Arranging is paused")
    }

    /// Anything else non-ASCII, or a control character from whoever answered on the port, can't reach the terminal.
    @Test func asciiReplacesEverythingElse() {
        #expect(CLICopy.ascii("Caf\u{00E9}\u{1B}[2J\n") == "Caf??[2J?")
    }
}
