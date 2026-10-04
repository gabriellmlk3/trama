import Foundation
import XCTest
@testable import trama

final class GitOverviewTests: XCTestCase {
    func testDiffParserNumbersLines() {
        let raw = "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -2,3 +2,3 @@ ctx\n a\n-b\n+c\n d\n"
        let lines = DiffParser.parse(raw)
        XCTAssertEqual(lines.map(\.kind), [.hunk, .context, .removed, .added, .context])
        XCTAssertEqual(lines[1].oldNumber, 2)
        XCTAssertEqual(lines[2].oldNumber, 3)
        XCTAssertEqual(lines[3].newNumber, 3)
        XCTAssertEqual(lines[4].newNumber, 4)
    }

    func testCommitChangesStagesOnlyChosenFiles() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Commit pela UI", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        try lab.write(wt + "/src/app.txt", "linha 1\nmudou\nlinha 3\n")
        try lab.write(wt + "/solto.txt", "a\n")

        XCTAssertThrowsError(try w.commitChanges(t.slug, repo: "api", paths: ["solto.txt"], message: "  "))
        let made = try w.commitChanges(t.slug, repo: "api", paths: ["solto.txt"], message: "só o solto")
        XCTAssertEqual(made.subject, "só o solto")
        XCTAssertEqual(try w.gitOverview(t.slug, repo: "api").changes.map(\.path), ["src/app.txt"])

        try w.commitChanges(t.slug, repo: "api", paths: ["src/app.txt"], message: "o resto")
        XCTAssertTrue(try w.gitOverview(t.slug, repo: "api").changes.isEmpty)
    }

    func testSuggestedMessageOnlySeesChosenFiles() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Mensagem sugerida", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        try lab.write(wt + "/src/app.txt", "linha 1\nmudou\nlinha 3\n")
        try lab.write(wt + "/solto.txt", "a\n")
        let fake = lab.root + "/claude"
        try lab.write(fake, "#!/bin/sh\nprintf '%s' \"$2\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake)
        setenv("TRAMA_CLAUDE", fake, 1)
        defer { unsetenv("TRAMA_CLAUDE") }

        let prompt = try w.suggestCommitMessage(t.slug, repo: "api", paths: ["solto.txt"])
        XCTAssertTrue(prompt.contains("solto.txt"))
        XCTAssertFalse(prompt.contains("src/app.txt"))
        XCTAssertTrue(try w.suggestCommitMessage(t.slug, repo: "api").contains("src/app.txt"))
    }

    func testSyncWorktreeFetchesAndFastForwardsThePrimaryCopy() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        XCTAssertEqual(Git.behindUpstream(primary), 0)

        try lab.pushToMain("rebocs_api", "novo.txt", "x\n", "chegou do remoto")
        XCTAssertEqual(Git.behindUpstream(primary), 0)

        let found = try w.syncWorktree(repo: "api", worktree: primary, pull: false)
        XCTAssertTrue(found.contains("1 commit novo"))
        XCTAssertEqual(Git.behindUpstream(primary), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary + "/novo.txt"))

        let pulled = try w.syncWorktree(repo: "api", worktree: primary, pull: true)
        XCTAssertTrue(pulled.contains("atualizada"))
        XCTAssertEqual(Git.behindUpstream(primary), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary + "/novo.txt"))
    }

    func testLocalBaseBehindRemoteIsDetectedAndUpdated() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Base velha", repos: ["api"], noFetch: true))
        let primary = try w.repo("api").path
        XCTAssertEqual(try w.gitOverview(t.slug, repo: "api").localBaseBehind, 0)

        try lab.pushToMain("rebocs_api", "novo.txt", "x\n", "chegou do remoto")
        try lab.git(primary, "checkout", "-q", "--detach")
        try lab.git(primary, "fetch", "-q")
        XCTAssertEqual(try w.gitOverview(t.slug, repo: "api").localBaseBehind, 1)

        XCTAssertTrue(try w.updateLocalBase(repo: "api", branch: "main").contains("atualizada"))
        XCTAssertEqual(try w.gitOverview(t.slug, repo: "api").localBaseBehind, 0)
    }

    func testFetchAllAlsoUpdatesTheUpstreamOfThePrimaryBranch() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        try lab.pushToMain("rebocs_api", "base.txt", "b\n", "base")
        try lab.git(primary, "checkout", "-q", "-b", "feat")
        try lab.git(primary, "push", "-q", "-u", "origin", "feat")
        let peer = lab.root + "/colega/rebocs_api"
        try lab.git(peer, "fetch", "-q")
        try lab.git(peer, "checkout", "-q", "-B", "feat", "origin/feat")
        try lab.commit(peer, "f.txt", "1\n", "feat nova")
        try lab.git(peer, "push", "-q", "origin", "feat")

        XCTAssertEqual(Git.behindUpstream(primary), 0)
        w.fetchAll()
        XCTAssertEqual(Git.behindUpstream(primary), 1)
    }

    func testSyncPrimariesReportsEachRepoSeparately() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Todas", repos: ["api", "admin"], noFetch: true))
        let api = try w.repo("api").path
        try lab.pushToMain("rebocs_api", "novo.txt", "x\n", "chegou do remoto")
        try lab.git(try w.repo("admin").path, "checkout", "-q", "--detach")

        let outcomes = try w.syncPrimaries(t.slug)
        XCTAssertEqual(outcomes.map(\.repo), ["rebocs_api", "rebocs-admin"])
        XCTAssertEqual(outcomes.map(\.failed), [false, true])
        XCTAssertTrue(outcomes[1].message.contains("HEAD solto"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: api + "/novo.txt"))
    }

    func testPullRequestTextIsBuiltFromTheCommitsAheadOfTheTarget() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Texto do PR", repos: ["api", "admin"], noFetch: true))
        try lab.commit(w.worktreePath(t.slug, "rebocs_api"), "src/novo.txt", "x\n", "adiciona o endpoint novo")
        let fake = lab.root + "/claude"
        try lab.write(fake, "#!/bin/sh\nprintf '%s' \"$2\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake)
        setenv("TRAMA_CLAUDE", fake, 1)
        defer { unsetenv("TRAMA_CLAUDE") }

        let text = try w.suggestPullRequestText(t.slug)
        XCTAssertTrue(text.summary.contains("adiciona o endpoint novo"))
        XCTAssertTrue(text.summary.contains("rebocs_api"))
        XCTAssertFalse(text.summary.contains("rebocs-admin"), "repositório sem commits à frente fica de fora")
    }

    func testParsePullRequestTextSplitsTitleAndSummary() {
        let text = Workspace.parsePullRequestText("```\n# Novo endpoint\n\nPorque sim.\n- item\n```")
        XCTAssertEqual(text?.title, "Novo endpoint")
        XCTAssertEqual(text?.summary, "Porque sim.\n- item")
        XCTAssertNil(Workspace.parsePullRequestText("  \n"))
    }

    func testDiscardFilesAndLines() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Descartar", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        try lab.commit(wt, "src/lista.txt", "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n", "lista")

        try lab.write(wt + "/src/lista.txt", "A\nb\nc\nd\ne\nf\ng\nh\ni\nJ\nextra\n")
        let change = try XCTUnwrap(try w.gitOverview(t.slug, repo: "api").changes.first)
        let diff = try w.fileDiff(t.slug, repo: "api", change: change)
        let first = try XCTUnwrap(diff.first(where: { $0.kind == .removed && $0.text == "a" }))
        let firstAdded = try XCTUnwrap(diff.first(where: { $0.kind == .added && $0.text == "A" }))
        try w.discardLines(t.slug, repo: "api", change: change, lines: [first.id, firstAdded.id])
        XCTAssertEqual(try File.read(wt + "/src/lista.txt"), "a\nb\nc\nd\ne\nf\ng\nh\ni\nJ\nextra\n")

        let rest = try XCTUnwrap(try w.gitOverview(t.slug, repo: "api").changes.first)
        let restDiff = try w.fileDiff(t.slug, repo: "api", change: rest)
        let extra = try XCTUnwrap(restDiff.first(where: { $0.text == "extra" }))
        try w.discardLines(t.slug, repo: "api", change: rest, lines: [extra.id])
        XCTAssertEqual(try File.read(wt + "/src/lista.txt"), "a\nb\nc\nd\ne\nf\ng\nh\ni\nJ\n")
        XCTAssertThrowsError(try w.discardLines(t.slug, repo: "api", change: rest, lines: [9999]))

        try lab.write(wt + "/solto.txt", "novo\n")
        try w.discardChanges(t.slug, repo: "api", paths: ["solto.txt", "src/lista.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: wt + "/solto.txt"))
        XCTAssertEqual(try File.read(wt + "/src/lista.txt"), "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
        XCTAssertTrue(try w.gitOverview(t.slug, repo: "api").changes.isEmpty)
        XCTAssertThrowsError(try w.discardChanges(t.slug, repo: "api", paths: ["nao-existe.txt"]))
    }

    func testOverviewOfWorktree() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Visao git", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        try lab.commit(wt, "src/novo.txt", "um\ndois\n", "novo arquivo")
        try lab.write(wt + "/src/app.txt", "linha 1\nmudou\nlinha 3\n")
        try lab.write(wt + "/solto.txt", "a\nb\nc\n")
        try lab.pushToMain("rebocs_api", "outro.txt", "x\n", "a base andou")
        try Git.fetchBase(wt, "main")

        let o = try w.gitOverview(t.slug, repo: "api")
        XCTAssertEqual(o.branch, t.branch)
        XCTAssertEqual(o.aheadCount, 1)
        XCTAssertEqual(o.behindCount, 1)
        XCTAssertEqual(o.ahead.first?.subject, "novo arquivo")
        XCTAssertEqual(o.behind.first?.subject, "a base andou")
        XCTAssertFalse(o.pushed)
        XCTAssertEqual(o.changes.map(\.path), ["solto.txt", "src/app.txt"])
        XCTAssertEqual(o.changes.first(where: { $0.path == "solto.txt" })?.added, 3)
        XCTAssertEqual(o.changes.first(where: { $0.path == "src/app.txt" })?.removed, 1)
        XCTAssertEqual(o.worktrees.count, 2)
        XCTAssertEqual(o.worktrees.filter(\.isPrimary).count, 1)

        let tracked = try XCTUnwrap(o.changes.first(where: { $0.path == "src/app.txt" }))
        XCTAssertTrue(try w.fileDiff(t.slug, repo: "api", change: tracked).contains { $0.kind == .added && $0.text == "mudou" })
        let loose = try XCTUnwrap(o.changes.first(where: { $0.path == "solto.txt" }))
        XCTAssertEqual(try w.fileDiff(t.slug, repo: "api", change: loose).filter { $0.kind == .added }.count, 3)
    }

    func testFindingChangesForLocalBranch() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let dir = lab.repos["rebocs_api"]!
        try lab.git(dir, "checkout", "-q", "-b", "solta")
        try lab.commit(dir, "src/extra.txt", "a\nb\n", "extra")
        var f = Finding(type: FindingType.noRemote, repo: "rebocs_api", title: "x", detail: "y")
        f.branch = "solta"
        f.path = dir
        let c = try w.findingChanges(f)
        XCTAssertEqual(c.changes.map(\.path), ["src/extra.txt"])
        XCTAssertEqual(c.changes.first?.code, "N")
        XCTAssertEqual(c.commitCount, 1)
        XCTAssertEqual(try w.findingFileDiff(f, change: c.changes[0]).filter { $0.kind == .added }.count, 2)

        try lab.write(dir + "/src/app.txt", "mudou\n")
        var g = Finding(type: FindingType.forgottenChange, repo: "rebocs_api", title: "x", detail: "y")
        g.path = dir
        XCTAssertEqual(try w.findingChanges(g).changes.map(\.path), ["src/app.txt"])
    }
}
