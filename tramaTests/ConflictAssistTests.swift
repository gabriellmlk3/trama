import Foundation
import XCTest
@testable import trama

final class ConflictAssistTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testHintsFromBaseAndSpacing() {
        func hint(_ ours: [String], _ theirs: [String], base: [String]?) -> ConflictHint.Kind? {
            ConflictHunk(id: 0, ours: ours, theirs: theirs, base: base).hint?.kind
        }
        XCTAssertEqual(hint(["a"], ["a"], base: nil), .identical)
        XCTAssertEqual(hint(["    a"], ["a"], base: nil), .spacing)
        XCTAssertEqual(hint(["x"], ["y"], base: ["x"]), .theirsOnly)
        XCTAssertEqual(hint(["x"], ["y"], base: ["y"]), .oursOnly)
        XCTAssertEqual(hint(["x"], ["y"], base: []), .bothAdded)
        XCTAssertNil(hint(["x"], ["y"], base: ["z"]))
        XCTAssertNil(hint(["x"], ["y"], base: nil))
    }

    func testInlineDiffMarksOnlyTheChangedPart() {
        let changes = InlineDiff.changes(ours: ["keep", "let a = 1"], theirs: ["keep", "let a = 22"])
        XCTAssertEqual(changes.ours[1], 8..<9)
        XCTAssertEqual(changes.theirs[1], 8..<10)
        XCTAssertNil(changes.ours[0])
        let spacing = InlineDiff.changes(ours: ["  x"], theirs: ["x"])
        XCTAssertEqual(spacing.spacingOurs, [0])
        XCTAssertEqual(spacing.spacingTheirs, [0])
    }

    func testReversedBothAndSummary() throws {
        let text = "a\n<<<<<<< HEAD\nmeu\n=======\nseu\n>>>>>>> x\nb\n"
        let doc = try ConflictParser.parse(path: "f.txt", text: text)
        let id = doc.hunks[0].id
        XCTAssertEqual(try doc.render([id: .bothReversed]), "a\nseu\nmeu\nb\n")
        XCTAssertEqual(doc.summary([id: .bothReversed]), "1 com as duas")
        XCTAssertEqual(doc.summary([:]), "")
    }

    func testWarningsFlagLeftoverMarkersAndUnbalancedBrackets() throws {
        let text = "func a() {\n<<<<<<< HEAD\n    x()\n=======\n    y()\n>>>>>>> x\n}\n"
        let doc = try ConflictParser.parse(path: "a.swift", text: text)
        let id = doc.hunks[0].id
        XCTAssertEqual(doc.warnings([id: .ours]), [])
        XCTAssertEqual(doc.warnings([id: .custom(["    }", "    {"])]), [])
        XCTAssertFalse(doc.warnings([id: .custom(["    {"])]).isEmpty)
        XCTAssertFalse(doc.warnings([id: .custom(["<<<<<<< HEAD"])]).isEmpty)
    }

    func testDraftRoundTripAndFingerprintGuard() throws {
        let w = try lab.workspace()
        let text = "a\n<<<<<<< HEAD\nmeu\n=======\nseu\n>>>>>>> x\nb\n"
        let doc = try ConflictParser.parse(path: "f.txt", text: text)
        let id = doc.hunks[0].id
        let wt = lab.root
        w.saveConflictDraft(worktree: wt, document: doc, resolutions: [id: .custom(["z"])])
        XCTAssertEqual(w.loadConflictDraft(worktree: wt, document: doc), [id: .custom(["z"])])
        let other = try ConflictParser.parse(path: "f.txt", text: "<<<<<<< HEAD\nq\n=======\nr\n>>>>>>> x\n")
        XCTAssertEqual(w.loadConflictDraft(worktree: wt, document: other), [:])
        w.saveConflictDraft(worktree: wt, document: doc, resolutions: [:])
        XCTAssertEqual(w.loadConflictDraft(worktree: wt, document: doc), [:])
    }

    func testDocumentCarriesBaseAndOrigins() throws {
        let w = try lab.workspace()
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Origem", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Destino", repos: ["api"], noFetch: true))
        let apiA = w.worktreePath(a.slug, "rebocs_api")
        let apiB = w.worktreePath(b.slug, "rebocs_api")
        try lab.commit(apiA, "src/app.txt", "linha A\nlinha 2\nlinha 3\n", "mexe A")
        try lab.commit(apiB, "src/app.txt", "linha B\nlinha 2\nlinha 3\n", "mexe B")
        _ = try w.mergeTrama(from: a.slug, into: b.slug, allowConflicts: true)
        let doc = try w.conflictDocument(repo: "api", worktree: apiB, file: "src/app.txt")
        XCTAssertEqual(doc.hunks[0].base, ["linha 1"])
        let origins = try w.conflictOrigins(repo: "api", worktree: apiB, file: "src/app.txt", document: doc)
        XCTAssertEqual(origins[doc.hunks[0].id]?.theirs?.subject, "mexe A")
        XCTAssertEqual(origins[doc.hunks[0].id]?.ours?.subject, "mexe B")
    }

    func testFencedLinesKeepIndentation() {
        XCTAssertEqual(Workspace.fencedLines("Claro:\n```swift\n    a\n  b\n```\nfim"), ["    a", "  b"])
        XCTAssertEqual(Workspace.fencedLines("  x\n"), ["  x"])
    }

    func testGeneratedFileHint() {
        XCTAssertNotNil(ConflictFile(path: "web/package-lock.json", code: "UU").generatedHint)
        XCTAssertNil(ConflictFile(path: "src/app.swift", code: "UU").generatedHint)
    }
}
