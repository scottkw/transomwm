import TransomMac
import Testing

/// UI-SPEC Surface 7: the S1 Spaces Debug line.
@Suite struct OverviewCopyTests {
    @Test(arguments: [
        (OverviewCopy.SpacesLine.counts(spaces: 3, displays: 1, shared: false), "Spaces: 3 on 1 display"),
        (.counts(spaces: 5, displays: 2, shared: false), "Spaces: 5 across 2 displays"),
        (.counts(spaces: 4, displays: 2, shared: true), "Spaces: 4, shared by 2 displays"),
        (.visited(2), "Spaces: 2 visited since launch"),
    ])
    func theSpacesLineMatchesTheContract(line: OverviewCopy.SpacesLine, expected: String) {
        #expect(OverviewCopy.spacesLine(line) == expected)
    }
}
