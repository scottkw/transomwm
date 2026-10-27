import Foundation
import Testing
import TransomEngine

/// Tests/TransomEngineTests/ClassifierCorpusTests.swift -> Tests/TransomEngineTests/Fixtures/AXDumps.
private let corpusDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Fixtures/AXDumps")

private let corpusFiles: [String] =
    ((try? FileManager.default.contentsOfDirectory(atPath: corpusDirectory.path)) ?? [])
    .filter { $0.hasSuffix(".json") }.sorted()

private func load(_ file: String) throws -> CorpusCase {
    try CorpusCase.decode(Data(contentsOf: corpusDirectory.appendingPathComponent(file)))
}

/// The label vocabulary for a classifier result.
private func label(_ classification: Classification) -> (kind: String, reason: String?) {
    switch classification {
    case .notAWindow: ("notAWindow", nil)
    case .window(.dockable, _): ("dockable", nil)
    case .window(.neverDock(let reason), _): ("neverDock", reason.rawValue)
    }
}

@Suite struct ClassifierCorpusTests {
    @Test(arguments: corpusFiles)
    func everyCaseClassifiesToItsLabel(file: String) throws {
        let corpusCase = try load(file)
        let result = label(Classifier.classify(corpusCase.window, bundleID: corpusCase.app.bundleID, appHidden: corpusCase.app.hidden))
        #expect(result.kind == corpusCase.expected.kind, "\(file)")
        if let reason = corpusCase.expected.reason {
            #expect(result.reason == reason, "\(file)")
        }
        #expect(corpusCase.caseName + ".json" == file)
    }

    @Test func theCorpusCoversTheRequiredAppsFamiliesAndKinds() throws {
        let cases = try corpusFiles.map(load)
        let bundles = Set(cases.map(\.app.bundleID))
        for bundle in ["com.apple.finder", "com.apple.Safari", "com.apple.Terminal", "com.apple.systempreferences"] {
            #expect(bundles.contains(bundle), "missing \(bundle)")
        }
        let families = Set(cases.map(\.app.family))
        for family in ["electron", "java", "office"] {
            #expect(families.contains(family), "missing family \(family)")
        }
        let kinds = Set(cases.map(\.expected.kind))
        #expect(kinds == ["dockable", "neverDock", "notAWindow"])
    }

    @Test(arguments: corpusFiles)
    func noCaseHoldsAHomePathOrATitleString(file: String) throws {
        let text = try String(contentsOf: corpusDirectory.appendingPathComponent(file), encoding: .utf8)
        #expect(!text.contains("/" + "Users" + "/"), "\(file) contains a home-directory path")
        #expect(text.range(of: #""title"\s*:\s*""#, options: .regularExpression) == nil, "\(file) has a title string")
        let corpusCase = try load(file)
        #expect(corpusCase.title.redacted)
        if let identifier = corpusCase.window.identifier {
            #expect(ClassifierOverrides.standard.neverDockIdentifiers.contains(identifier), "\(file) keeps identifier \(identifier)")
        }
    }

    @Test func decodeRejectsNewerSchemasAndOversizedInput() throws {
        let newer = Data(#"{"schemaVersion": 2}"#.utf8)
        #expect(throws: CorpusCase.DecodeError.newerVersion(found: 2)) { try CorpusCase.decode(newer) }
        let huge = Data(repeating: 0x20, count: CorpusCase.maxEncodedBytes + 1)
        #expect(throws: CorpusCase.DecodeError.tooLarge(bytes: huge.count)) { try CorpusCase.decode(huge) }
    }
}
