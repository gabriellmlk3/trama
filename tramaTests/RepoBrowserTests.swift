import Foundation
import XCTest
@testable import trama

final class RepoBrowserTests: XCTestCase {
    func node(_ hash: String, _ parents: String...) -> GraphCommit {
        GraphCommit(hash: hash, short: hash, parents: parents, author: "", timestamp: 0, subject: hash)
    }

    func testGraphKeepsLinearHistoryInOneLane() {
        let rows = CommitGraph.layout([node("c", "b"), node("b", "a"), node("a")])
        XCTAssertEqual(rows.map(\.lane), [0, 0, 0])
        XCTAssertEqual(rows.map(\.width), [1, 1, 1])
        XCTAssertTrue(rows[0].top.isEmpty)
        XCTAssertEqual(rows[1].top, [GraphSegment(from: 0, to: 0, color: 0)])
        XCTAssertTrue(rows[2].bottom.isEmpty)
    }

    func testGraphOpensLaneForMergeAndConvergesAtForkPoint() {
        let rows = CommitGraph.layout([node("m", "b", "c"), node("c", "a"), node("b", "a"), node("a")])
        XCTAssertEqual(rows.map(\.lane), [0, 1, 0, 0])
        XCTAssertEqual(rows[0].bottom.map { [$0.from, $0.to] }, [[0, 0], [0, 1]])
        XCTAssertEqual(rows[1].top.map { [$0.from, $0.to] }, [[0, 0], [1, 1]])
        XCTAssertEqual(rows[3].top.map { [$0.from, $0.to] }, [[0, 0], [1, 0]])
        XCTAssertTrue(rows[3].bottom.isEmpty)
        XCTAssertEqual(rows.map(\.width), [2, 2, 2, 2])
        XCTAssertNotEqual(rows[0].color, rows[1].color)
    }

    func testGraphGivesSeparateTipsTheirOwnLanes() {
        let rows = CommitGraph.layout([node("x", "a"), node("y", "a"), node("a")])
        XCTAssertEqual(rows.map(\.lane), [0, 1, 0])
        XCTAssertEqual(rows[2].top.map { [$0.from, $0.to] }, [[0, 0], [1, 0]])
    }

    func testDecorationsSeparateHeadBranchesRemotesAndTags() {
        let refs = Git.parseDecorations("HEAD -> refs/heads/feat, tag: refs/tags/v1, refs/remotes/origin/main, refs/remotes/origin/HEAD, refs/heads/main, refs/stash")
        XCTAssertEqual(refs, [
            RefLabel(name: "feat", kind: .head),
            RefLabel(name: "v1", kind: .tag),
            RefLabel(name: "origin/main", kind: .remote),
            RefLabel(name: "main", kind: .local),
        ])
        XCTAssertEqual(Git.parseDecorations("HEAD"), [RefLabel(name: "HEAD", kind: .head)])
        XCTAssertEqual(Git.parseDecorations(""), [])
    }

    func testStatusReadsBranchUpstreamAndCounts() {
        let raw = "# branch.oid 2660d540ddef8ad26cf0f5d5db37768c1e6796c7\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -3\n1 .M N... 100644 100644 100644 a a f.txt\nu UU N... 1 2 3 4 a b c d g.txt\n? novo.txt\n"
        let s = Git.parseStatus(raw)
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.head, "2660d54")
        XCTAssertEqual(s.upstream, "origin/main")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertEqual(s.behind, 3)
        XCTAssertEqual(s.changed, 3)
        XCTAssertEqual(s.conflicts, 1)
        XCTAssertTrue(Git.parseStatus("# branch.oid (initial)\n# branch.head (detached)\n").detached)
    }

    func testTrackParsing() {
        XCTAssertEqual(Git.parseTrack("ahead 3, behind 2").ahead, 3)
        XCTAssertEqual(Git.parseTrack("ahead 3, behind 2").behind, 2)
        XCTAssertEqual(Git.parseTrack("behind 4").behind, 4)
        XCTAssertTrue(Git.parseTrack("gone").gone)
        XCTAssertEqual(Git.parseTrack("").ahead, 0)
    }

    func testBrowserReadsHistoryBranchesStashAndWorktrees() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Grafo", repos: ["api"], noFetch: true))
        try lab.commit(w.worktreePath(t.slug, "rebocs_api"), "src/novo.txt", "x\n", "na trama")
        try lab.write(primary + "/rascunho.txt", "a\n")
        _ = try w.saveStash("api", checkout: primary, message: "guardado")

        let state = try w.repoBrowser("api")
        XCTAssertEqual(state.checkout, primary)
        XCTAssertEqual(state.status.branch, "main")
        XCTAssertEqual(state.status.upstream, "origin/main")
        XCTAssertEqual(state.commits.first?.subject, "na trama")
        XCTAssertTrue(state.commits.first?.refs.contains(RefLabel(name: t.branch, kind: .local)) == true)
        XCTAssertTrue(state.commits.contains { $0.isHead && $0.subject == "app" })
        XCTAssertEqual(state.graph.count, state.commits.count)
        XCTAssertEqual(state.checkouts.count, 2)
        XCTAssertEqual(state.checkouts.filter(\.isPrimary).map(\.path), [primary])
        XCTAssertEqual(state.stashes.map(\.message), ["On main: guardado"])
        XCTAssertTrue(state.changes.isEmpty)
        let tramaBranch = try XCTUnwrap(state.localBranches.first { $0.name == t.branch })
        XCTAssertNotNil(tramaBranch.openAt)
        XCTAssertEqual(state.localBranches.first?.name, "main")
        XCTAssertTrue(state.localBranches.first?.current == true)
        XCTAssertEqual(state.remoteBranches.map(\.name), ["origin/main"])

        let snapshot = try XCTUnwrap(w.repoSnapshots().first { $0.name == "rebocs_api" })
        XCTAssertEqual(snapshot.stashes, 1)
        XCTAssertEqual(snapshot.worktrees, 2)
        XCTAssertEqual(snapshot.status.changed, 0)

        let worktree = try w.repoBrowser("api", checkout: w.worktreePath(t.slug, "rebocs_api"))
        XCTAssertEqual(worktree.status.branch, t.branch)
        XCTAssertThrowsError(try w.repoBrowser("api", checkout: lab.root))
    }

    func testCommitDetailHandlesRootAndRegularCommits() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        let head = try Git.run(primary, "rev-parse", "HEAD")
        let root = try Git.run(primary, "rev-list", "--max-parents=0", "HEAD")

        let detail = try w.commitDetail("api", hash: head)
        XCTAssertEqual(detail.subject, "app")
        XCTAssertEqual(detail.author, "Teste")
        XCTAssertEqual(detail.changes.map(\.path), ["src/app.txt"])
        XCTAssertEqual(detail.changes.first?.added, 3)
        let diff = try w.commitFileDiff("api", detail: detail, path: "src/app.txt")
        XCTAssertEqual(diff.filter { $0.kind == .added }.count, 3)

        let first = try w.commitDetail("api", hash: root)
        XCTAssertTrue(first.parents.isEmpty)
        XCTAssertEqual(first.changes.map(\.path), ["README.md"])
        XCTAssertEqual(first.changes.first?.code, "N")

        XCTAssertThrowsError(try w.commitDetail("api", hash: "--all"))
        XCTAssertThrowsError(try w.commitDetail("api", hash: "deadbeef"))
    }

    func testSwitchBranchRefusesBranchOpenInAnotherWorktree() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Ocupada", repos: ["api"], noFetch: true))

        XCTAssertThrowsError(try w.switchBranch("api", checkout: primary, branch: t.branch, remote: false)) { error in
            XCTAssertTrue(errorMessage(error).contains("já está aberta"))
        }
        XCTAssertThrowsError(try w.deleteBranch("api", name: t.branch))
        XCTAssertEqual(Git.currentBranchName(primary), "main")
    }

    func testCreateSwitchAndDeleteBranch() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path

        XCTAssertThrowsError(try w.createBranch("api", checkout: primary, name: "nome inválido", from: nil, switchTo: false))
        _ = try w.createBranch("api", checkout: primary, name: "experimento", from: "HEAD~1", switchTo: true)
        XCTAssertEqual(Git.currentBranchName(primary), "experimento")
        XCTAssertEqual(Git.lastCommit(primary)?.subject, "inicial")
        XCTAssertThrowsError(try w.createBranch("api", checkout: primary, name: "experimento", from: nil, switchTo: false))

        XCTAssertThrowsError(try w.deleteBranch("api", name: "experimento"))
        _ = try w.switchBranch("api", checkout: primary, branch: "main", remote: false)
        _ = try w.deleteBranch("api", name: "experimento")
        XCTAssertFalse(Git.branchExists(primary, "experimento"))

        _ = try w.createBranch("api", checkout: primary, name: "solta", from: nil, switchTo: true)
        try lab.commit(primary, "solta.txt", "s\n", "só na solta")
        _ = try w.switchBranch("api", checkout: primary, branch: "main", remote: false)
        XCTAssertThrowsError(try w.deleteBranch("api", name: "solta")) { error in
            XCTAssertTrue(errorMessage(error).contains("não apaga"))
        }
        XCTAssertTrue(Git.branchExists(primary, "solta"))
    }

    func testSwitchToRemoteBranchCreatesTrackingBranch() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        try lab.git(primary, "push", "-q", "origin", "main:refs/heads/novidade")
        _ = try w.fetchRepo("api")

        let state = try w.repoBrowser("api")
        XCTAssertTrue(state.remoteBranches.contains { $0.name == "origin/novidade" && $0.localName == "novidade" })
        _ = try w.switchBranch("api", checkout: primary, branch: "origin/novidade", remote: true)
        XCTAssertEqual(Git.currentBranchName(primary), "novidade")
        XCTAssertEqual(Git.checkoutStatus(primary).upstream, "origin/novidade")
    }

    func testPushPublishesBranchAndPullFastForwards() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path

        _ = try w.createBranch("api", checkout: primary, name: "publicar", from: nil, switchTo: true)
        try lab.commit(primary, "p.txt", "p\n", "para publicar")
        XCTAssertEqual(try w.pushCheckout("api", checkout: primary), "publicar publicada em origin")
        XCTAssertEqual(Git.checkoutStatus(primary).upstream, "origin/publicar")
        try lab.commit(primary, "p.txt", "p2\n", "mais um")
        XCTAssertTrue(try w.pushCheckout("api", checkout: primary).hasPrefix("1 commit enviado"))
        XCTAssertEqual(Git.checkoutStatus(primary).ahead, 0)

        _ = try w.switchBranch("api", checkout: primary, branch: "main", remote: false)
        try lab.pushToMain("rebocs_api", "remoto.txt", "r\n", "veio do colega")
        _ = try w.pullCheckout("api", checkout: primary)
        XCTAssertEqual(Git.lastCommit(primary)?.subject, "veio do colega")
    }

    func testStashApplyPopAndDrop() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path

        XCTAssertThrowsError(try w.saveStash("api", checkout: primary, message: ""))
        try lab.write(primary + "/src/app.txt", "mudou\n")
        try lab.write(primary + "/novo.txt", "n\n")
        _ = try w.saveStash("api", checkout: primary, message: "primeiro")
        XCTAssertTrue(Git.fileChanges(primary).isEmpty)

        let entry = try XCTUnwrap(Git.stashes(primary).first)
        _ = try w.applyStash("api", checkout: primary, hash: entry.hash, drop: false)
        XCTAssertEqual(Set(Git.fileChanges(primary).map(\.path)), ["src/app.txt", "novo.txt"])
        XCTAssertEqual(Git.stashes(primary).count, 1)

        try w.discardInCheckout("api", checkout: primary, paths: ["src/app.txt"])
        try FileManager.default.removeItem(atPath: primary + "/novo.txt")
        _ = try w.applyStash("api", checkout: primary, hash: entry.hash, drop: true)
        XCTAssertTrue(Git.stashes(primary).isEmpty)
        XCTAssertThrowsError(try w.applyStash("api", checkout: primary, hash: entry.hash, drop: false))

        _ = try w.saveStash("api", checkout: primary, message: "segundo")
        _ = try w.dropStash("api", hash: try XCTUnwrap(Git.stashes(primary).first).hash)
        XCTAssertTrue(Git.stashes(primary).isEmpty)
    }

    func testCommitInCheckoutOnlyTakesChosenFiles() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        try lab.write(primary + "/a.txt", "a\n")
        try lab.write(primary + "/b.txt", "b\n")

        let made = try w.commitCheckout("api", checkout: primary, paths: ["a.txt"], message: "só a")
        XCTAssertEqual(made.subject, "só a")
        XCTAssertEqual(Git.fileChanges(primary).map(\.path), ["b.txt"])
    }
    func testBrowserHistoryFollowsNewCommitsBranchesAndTags() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path

        let first = try w.repoBrowser("api")
        let again = try w.repoBrowser("api")
        XCTAssertTrue(again.sameContent(as: first), "sem mudanças, o estado lido de novo é igual")

        try lab.commit(primary, "novo.txt", "x\n", "segundo")
        let afterCommit = try w.repoBrowser("api")
        XCTAssertEqual(afterCommit.commits.first?.subject, "segundo")
        XCTAssertEqual(afterCommit.commits.count, first.commits.count + 1)
        XCTAssertEqual(afterCommit.graph.count, afterCommit.commits.count)

        try lab.git(primary, "tag", "v1")
        let afterTag = try w.repoBrowser("api")
        XCTAssertTrue(afterTag.commits.first?.refs.contains(RefLabel(name: "v1", kind: .tag)) == true)

        try lab.git(primary, "branch", "lateral")
        let afterBranch = try w.repoBrowser("api")
        XCTAssertTrue(afterBranch.commits.first?.refs.contains(RefLabel(name: "lateral", kind: .local)) == true)

        let short = try w.repoBrowser("api", limit: 1)
        XCTAssertEqual(short.commits.count, 1)
        XCTAssertTrue(short.truncated)
        XCTAssertEqual(try w.repoBrowser("api").commits.count, afterBranch.commits.count, "limites diferentes não se misturam no cache")
    }

    func testUntrackedLineCountFollowsFileChangesAndCountsCRLF() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let primary = try w.repo("api").path
        try lab.write(primary + "/lf.txt", "a\nb\nc\n")
        try lab.write(primary + "/crlf.txt", "a\r\nb\r\n")
        func added(_ name: String) -> Int? { Git.fileChanges(primary).first { $0.path == name }?.added }
        XCTAssertEqual(added("lf.txt"), 3)
        XCTAssertEqual(added("crlf.txt"), 2)
        try lab.write(primary + "/lf.txt", "a\nb\nc\nd\ne\n")
        XCTAssertEqual(added("lf.txt"), 5, "o cache não esconde arquivo que mudou")
    }
}
