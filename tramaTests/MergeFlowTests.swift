import Foundation
import XCTest
@testable import trama

final class MergeFlowTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testMergeOneTramaIntoAnother() throws {
        let w = try lab.workspace()
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Origem", repos: ["api", "admin"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Destino", repos: ["api", "android"], noFetch: true))
        let apiA = w.worktreePath(a.slug, "rebocs_api")
        let apiB = w.worktreePath(b.slug, "rebocs_api")
        XCTAssertEqual(w.sharedRepos(a, b), ["rebocs_api"])
        XCTAssertThrowsError(try w.mergeTrama(from: a.slug, into: a.slug))
        try lab.commit(apiA, "feature.txt", "nova\n", "feature")
        try lab.write(apiB + "/solto.txt", "x\n")
        XCTAssertThrowsError(try w.mergeTrama(from: a.slug, into: b.slug), "destino sujo") { XCTAssertTrue(errorMessage($0).contains("nada foi mesclado")) }
        XCTAssertFalse(Paths.exists(apiB + "/feature.txt"))
        try FileManager.default.removeItem(atPath: apiB + "/solto.txt")
        let ok = try w.mergeTrama(from: a.slug, into: b.slug)
        XCTAssertEqual(ok.map(\.situation), ["mesclado"])
        XCTAssertEqual(try File.read(apiB + "/feature.txt"), "nova\n")
        XCTAssertEqual(try w.mergeTrama(from: a.slug, into: b.slug).map(\.situation), ["atualizado"])
        XCTAssertTrue(try w.readCapsule(b.slug).journal.contains { $0.text.contains("merge de “Origem”") })
        try lab.commit(apiA, "src/app.txt", "linha A\nlinha 2\nlinha 3\n", "mexe A")
        try lab.commit(apiB, "src/app.txt", "linha B\nlinha 2\nlinha 3\n", "mexe B")
        XCTAssertThrowsError(try w.mergeTrama(from: a.slug, into: b.slug)) { XCTAssertTrue(errorMessage($0).contains("conflito")) }
        XCTAssertEqual(try Git.statusLines(apiB), [], "nada foi tocado")
        let conflict = try w.mergeTrama(from: a.slug, into: b.slug, allowConflicts: true)
        XCTAssertEqual(conflict.map(\.situation), ["conflito"])
        XCTAssertFalse(try Git.statusLines(apiB).isEmpty)
    }

    func testResolveMergeConflicts() throws {
        let w = try lab.workspace()
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Origem", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Destino", repos: ["api"], noFetch: true))
        let apiA = w.worktreePath(a.slug, "rebocs_api")
        let apiB = w.worktreePath(b.slug, "rebocs_api")
        try lab.commit(apiA, "src/app.txt", "linha A\nlinha 2\nlinha 3\n", "mexe A")
        try lab.commit(apiA, "outro.txt", "A\n", "outro A")
        try lab.commit(apiB, "src/app.txt", "linha B\nlinha 2\nlinha 3\n", "mexe B")
        try lab.commit(apiB, "outro.txt", "B\n", "outro B")
        XCTAssertEqual(try w.mergeTrama(from: a.slug, into: b.slug, allowConflicts: true).map(\.situation), ["conflito"])
        let state = try w.conflictState(repo: "api", worktree: apiB)
        XCTAssertTrue(state.merging)
        XCTAssertEqual(state.files.map(\.path), ["outro.txt", "src/app.txt"])
        XCTAssertThrowsError(try w.concludeMerge(repo: "api", worktree: apiB), "ainda há conflitos")
        let doc = try w.conflictDocument(repo: "api", worktree: apiB, file: "src/app.txt")
        XCTAssertEqual(doc.hunks.count, 1)
        XCTAssertEqual(doc.hunks[0].ours, ["linha B"])
        XCTAssertEqual(doc.hunks[0].theirs, ["linha A"])
        XCTAssertThrowsError(try doc.render([:]))
        let merged = try doc.render([doc.hunks[0].id: .both])
        XCTAssertEqual(merged, "linha B\nlinha A\nlinha 2\nlinha 3\n")
        try w.saveResolution(repo: "api", worktree: apiB, file: "src/app.txt", content: merged)
        try w.acceptSide(repo: "api", worktree: apiB, file: "outro.txt", side: .theirs)
        XCTAssertEqual(try File.read(apiB + "/outro.txt"), "A\n")
        XCTAssertTrue(try w.conflictState(repo: "api", worktree: apiB).files.isEmpty)
        XCTAssertThrowsError(try w.acceptSide(repo: "api", worktree: apiB, file: "../fora.txt", side: .ours))
        try w.concludeMerge(repo: "api", worktree: apiB)
        XCTAssertFalse(try w.conflictState(repo: "api", worktree: apiB).merging)
        XCTAssertEqual(try Git.statusLines(apiB), [])
        XCTAssertEqual(try File.read(apiB + "/src/app.txt"), merged)
    }

    func testAbortMergeAndDeletedByOneSide() throws {
        let w = try lab.workspace()
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Origem", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Destino", repos: ["api"], noFetch: true))
        let apiA = w.worktreePath(a.slug, "rebocs_api")
        let apiB = w.worktreePath(b.slug, "rebocs_api")
        try lab.git(apiA, "rm", "-q", "src/app.txt")
        try lab.git(apiA, "commit", "-q", "-m", "remove")
        try lab.commit(apiB, "src/app.txt", "linha 1 mudada\nlinha 2\nlinha 3\n", "muda")
        XCTAssertEqual(try w.mergeTrama(from: a.slug, into: b.slug, allowConflicts: true).map(\.situation), ["conflito"])
        let files = try w.conflictState(repo: "api", worktree: apiB).files
        XCTAssertEqual(files.map(\.code), ["UD"])
        XCTAssertFalse(files[0].canMerge)
        XCTAssertThrowsError(try w.conflictDocument(repo: "api", worktree: apiB, file: "src/app.txt"))
        try w.abortMerge(repo: "api", worktree: apiB)
        XCTAssertFalse(try w.conflictState(repo: "api", worktree: apiB).merging)
        XCTAssertTrue(Paths.exists(apiB + "/src/app.txt"))
        XCTAssertEqual(try w.mergeTrama(from: a.slug, into: b.slug, allowConflicts: true).map(\.situation), ["conflito"])
        try w.acceptSide(repo: "api", worktree: apiB, file: "src/app.txt", side: .theirs)
        XCTAssertFalse(Paths.exists(apiB + "/src/app.txt"))
        try w.concludeMerge(repo: "api", worktree: apiB)
    }

    func testConflictPicksComposeLinesWithoutDuplicates() {
        let hunk = ConflictHunk(id: 0, ours: ["a", "b", "c"], theirs: ["b", "d"], base: nil)
        XCTAssertEqual(hunk.commonLines, ["b"])
        XCTAssertEqual(hunk.composed(ours: [0, 1], theirs: [0, 1]), ["a", "b", "d"])
        XCTAssertEqual(hunk.composed(ours: [], theirs: [1]), ["d"])
        XCTAssertNil(ConflictPicks().resolution(for: hunk))
        XCTAssertEqual(ConflictPicks.all(hunk, ours: true, theirs: false).resolution(for: hunk), .ours)
        XCTAssertEqual(ConflictPicks(ours: [2], theirs: [1]).resolution(for: hunk), .custom(["c", "d"]))
    }

    func testConflictParserKeepsContextAndLabels() throws {
        let text = "a\n<<<<<<< HEAD\nmeu\n=======\nseu\n>>>>>>> trama/x\nb\n<<<<<<< HEAD\n=======\nnovo\n>>>>>>> trama/x\n"
        let doc = try ConflictParser.parse(path: "f", text: text)
        XCTAssertEqual(doc.hunks.count, 2)
        XCTAssertEqual(doc.oursLabel, "HEAD")
        XCTAssertEqual(doc.theirsLabel, "trama/x")
        XCTAssertEqual(try doc.render(Dictionary(uniqueKeysWithValues: doc.hunks.map { ($0.id, ConflictResolution.theirs) })), "a\nseu\nb\nnovo\n")
        XCTAssertEqual(try doc.render(Dictionary(uniqueKeysWithValues: doc.hunks.map { ($0.id, ConflictResolution.custom(["x"])) })), "a\nx\nb\nx\n")
        XCTAssertThrowsError(try ConflictParser.parse(path: "f", text: "<<<<<<< HEAD\nx\n"))
    }

    func testMergeBetweenWorktrees() throws {
        let w = try lab.workspace()
        let main = lab.repos["rebocs_api"]!
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Para a main", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        try lab.commit(wt, "novo.txt", "x\n", "novo")
        try lab.write(main + "/solto.txt", "sujo\n")
        let r = try w.mergeWorktrees(repo: "api", from: wt, into: main)
        XCTAssertEqual(r.situation, "mesclado")
        XCTAssertEqual(try File.read(main + "/novo.txt"), "x\n")
        XCTAssertTrue(Paths.exists(main + "/solto.txt"), "mudança solta do destino preservada")
        XCTAssertEqual(try w.mergeWorktrees(repo: "api", from: wt, into: main).situation, "atualizado")
        XCTAssertThrowsError(try w.mergeWorktrees(repo: "api", from: wt, into: wt))
        XCTAssertThrowsError(try w.mergeWorktrees(repo: "api", from: wt, into: lab.root))
    }

    func testMergeAnyBranchIntoWorktree() throws {
        let w = try lab.workspace()
        let main = lab.repos["rebocs_api"]!
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Qualquer branch", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        _ = try Git.run(main, "branch", "outra")
        _ = try Git.run(main, "worktree", "add", "-q", lab.root + "/outra-wt", "outra")
        try lab.commit(lab.root + "/outra-wt", "outra.txt", "o\n", "outra")
        let branches = try w.mergeableBranches(repo: "api", worktree: wt, fetch: false)
        XCTAssertTrue(branches.contains("outra"))
        XCTAssertFalse(branches.contains(t.branch))
        XCTAssertEqual(try w.mergeBranch(repo: "api", ref: "outra", into: wt).situation, "mesclado")
        XCTAssertEqual(try File.read(wt + "/outra.txt"), "o\n")
        XCTAssertEqual(try w.mergeBranch(repo: "api", ref: "outra", into: wt).situation, "atualizado")
        XCTAssertThrowsError(try w.mergeBranch(repo: "api", ref: "nao-existe", into: wt))
    }

    func testDirectMergeIntoSelectedBranches() throws {
        let w = try lab.workspace()
        for name in ["rebocs_api", "rebocs-admin"] {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
        }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Direta", repos: ["api", "admin"], noFetch: true))
        for name in ["rebocs_api", "rebocs-admin"] {
            try lab.commit(w.worktreePath(t.slug, name), "feature.txt", "x\n", "feature")
        }
        let remote = "\(lab.root)/remotos"
        // develop avança sozinho em um repo: exige commit de merge; o outro avança direto
        try lab.pushToMain("rebocs_api", "outro.txt", "y\n", "outro")
        try lab.git(lab.root + "/colega/rebocs_api", "push", "-q", "origin", "main:develop")

        let result = try w.mergeIntoBranches(t.slug, targets: ["rebocs_api": "develop", "rebocs-admin": "develop"])
        XCTAssertEqual(result.results.map(\.situation), ["mesclado", "mesclado"])
        XCTAssertTrue(Git.refExists("\(remote)/rebocs-admin.git", "refs/heads/develop"))
        let apiLog = try Git.run("\(remote)/rebocs_api.git", "log", "--format=%s", "develop")
        XCTAssertTrue(apiLog.contains("feature") && apiLog.contains("outro") && apiLog.contains("Merge branch"))
        let adminLog = try Git.run("\(remote)/rebocs-admin.git", "log", "--format=%s", "develop")
        XCTAssertFalse(adminLog.contains("Merge branch"))
        XCTAssertTrue(adminLog.contains("feature"))
        XCTAssertThrowsError(try w.mergeIntoBranches(t.slug, targets: ["rebocs_api": "inexistente"], only: ["rebocs_api"]))
    }
}
