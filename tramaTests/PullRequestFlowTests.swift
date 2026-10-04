import Foundation
import XCTest
@testable import trama

final class PullRequestFlowTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testPullRequestsAreOpenedInOrderAndLinked() throws {
        let w = try lab.workspace()
        let log = lab.root + "/gh.log"
        let fake = lab.root + "/gh"
        try lab.write(fake, """
        #!/bin/sh
        echo "$PWD|$*" >> "\(log)"
        case "$1 $2" in
          "pr view")
            case "$*" in
              *--jq*) exit 1 ;;
              *) echo '{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"IN_PROGRESS","conclusion":""}]}' ;;
            esac ;;
          "pr create") echo "https://github.com/x/$(basename "$PWD")/pull/7" ;;
          "pr edit") ;;
        esac
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake)
        setenv("TRAMA_GH", fake, 1)
        defer { unsetenv("TRAMA_GH") }
        try w.setMergeRank("admin", 2)
        try w.setMergeRank("api", 1)
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Com PRs", repos: ["admin", "api", "android"], goal: "Entregar tudo", noFetch: true))
        try w.addDecision(t.slug, author: "você", "contrato novo")
        try lab.commit(w.worktreePath(t.slug, "rebocs_api"), "api.txt", "x\n", "api")
        try lab.commit(w.worktreePath(t.slug, "rebocs-admin"), "admin.txt", "x\n", "admin")
        let result = try w.openPullRequests(t.slug, draft: true)
        XCTAssertEqual(result.prs.map(\.repo), ["rebocs_api", "rebocs-admin"], "só os repositórios com commits, na ordem de merge")
        XCTAssertTrue(result.warnings.contains { $0.repo == "rebocs-android" && $0.message.contains("sem commits") })
        XCTAssertEqual(result.prs[0].number, 7)
        XCTAssertEqual(result.prs[0].ci, CIState.pending)
        XCTAssertEqual(Set(try w.trama(t.slug).prs.keys), ["rebocs_api", "rebocs-admin"])
        let calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("--draft"))
        XCTAssertTrue(calls.contains("--base main --head trama/com-prs --title Com PRs"))
        XCTAssertTrue(calls.contains("Entregar tudo"))
        XCTAssertTrue(calls.contains("1. https://github.com/x/rebocs_api/pull/7\n2. https://github.com/x/rebocs-admin/pull/7 ← este PR"))
        let remote = lab.root + "/remotos/rebocs_api.git"
        XCTAssertTrue(Git.branchExists(remote, "trama/com-prs"))
        XCTAssertEqual(ciState([["status": "COMPLETED", "conclusion": "FAILURE"], ["status": "IN_PROGRESS"]]), CIState.failure)
        XCTAssertEqual(ciState([["status": "COMPLETED", "conclusion": "SUCCESS"]]), CIState.success)
        XCTAssertEqual(ciState([]), CIState.none)
    }

    func testForgettingPullRequestsKeepsTheOthers() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Descarte", repos: ["api", "admin"], noFetch: true))
        try w.updateTrama(t.slug) {
            $0.prs = ["rebocs_api": "https://github.com/x/rebocs_api/pull/1", "rebocs-admin": "https://github.com/x/rebocs-admin/pull/2"]
        }
        let updated = try w.forgetPullRequests(t.slug, repos: ["rebocs_api"])
        XCTAssertEqual(updated.prs, ["rebocs-admin": "https://github.com/x/rebocs-admin/pull/2"])
        XCTAssertEqual(try w.trama(t.slug).prs.keys.sorted(), ["rebocs-admin"])
        XCTAssertTrue(try w.readCapsule(t.slug).journal.contains { $0.text.contains("PRs descartados") })
        XCTAssertTrue(try w.forgetPullRequests(t.slug, repos: ["rebocs-admin"]).prs.isEmpty)
    }

    func testRemoteBranchesCanBeCreatedRenamedAndDeleted() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Branches", repos: ["api", "admin"], noFetch: true))
        let repos = ["rebocs_api", "rebocs-admin"]
        func names() throws -> [String] { try w.remoteBranchCatalog(t.slug, fetch: true).options.map(\.name) }

        try w.createRemoteBranch(t.slug, name: "release", from: "main", repos: repos)
        XCTAssertEqual(Set(try names()), ["main", "release"])
        XCTAssertThrowsError(try w.createRemoteBranch(t.slug, name: "release", from: "main", repos: repos))
        XCTAssertThrowsError(try w.createRemoteBranch(t.slug, name: "bad name", from: "main", repos: repos))

        try w.renameRemoteBranch(t.slug, from: "release", to: "staging", repos: repos)
        XCTAssertEqual(Set(try names()), ["main", "staging"])
        XCTAssertThrowsError(try w.renameRemoteBranch(t.slug, from: "main", to: "other", repos: repos))

        try w.deleteRemoteBranch(t.slug, name: "staging", repos: ["rebocs_api"])
        let catalog = try w.remoteBranchCatalog(t.slug, fetch: true)
        XCTAssertEqual(catalog.options.first { $0.name == "staging" }?.repos, ["rebocs-admin"])
        XCTAssertThrowsError(try w.deleteRemoteBranch(t.slug, name: "main", repos: repos))
    }

    func testPullRequestsCanTargetAnotherBranchPerRepo() throws {
        let w = try lab.workspace()
        let log = lab.root + "/gh.log"
        let fake = lab.root + "/gh"
        let states = lab.root + "/gh-estados"
        try FileManager.default.createDirectory(atPath: states, withIntermediateDirectories: true)
        try lab.write(fake, """
        #!/bin/sh
        echo "$PWD|$*" >> "\(log)"
        case "$1 $2" in
          "pr view")
            case "$*" in
              *--jq*) exit 1 ;;
              *baseRefName*) cat "\(states)/$(basename "$PWD").json" 2>/dev/null || exit 1 ;;
              *) echo '{"number":7,"state":"OPEN","isDraft":false,"statusCheckRollup":[]}' ;;
            esac ;;
          "pr create") echo "https://github.com/x/$(basename "$PWD")/pull/7" ;;
          "pr edit") ;;
        esac
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake)
        setenv("TRAMA_GH", fake, 1)
        defer { unsetenv("TRAMA_GH") }
        func pullRequestState(_ repo: String, state: String, base: String) throws {
            try lab.write("\(states)/\(repo).json", #"{"url":"https://github.com/x/\#(repo)/pull/7","number":7,"state":"\#(state)","baseRefName":"\#(base)","isDraft":false}"#)
        }
        for name in ["rebocs_api", "rebocs-admin"] {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
        }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Destinos", repos: ["api", "admin", "android"], noFetch: true))
        for name in ["rebocs_api", "rebocs-admin", "rebocs-android"] {
            try lab.commit(w.worktreePath(t.slug, name), "feature.txt", "x\n", "feature")
        }

        let catalog = try w.remoteBranchCatalog(t.slug, fetch: true)
        XCTAssertEqual(catalog.options.map(\.name), ["main", "develop"])
        XCTAssertEqual(catalog.options[1].repos, ["rebocs-admin", "rebocs_api"])
        XCTAssertFalse(catalog.options.contains { $0.isTrama })

        let all = ["rebocs_api": "develop", "rebocs-admin": "develop", "rebocs-android": "develop"]
        let plan = try w.pullRequestPlan(t.slug, targets: all)
        XCTAssertEqual(plan.map(\.repo), ["rebocs-admin", "rebocs-android", "rebocs_api"])
        XCTAssertEqual(plan.map(\.action), [.create, .blocked, .create])
        XCTAssertEqual(plan[1].blocker, .missingTarget)
        XCTAssertEqual(plan.map(\.ahead), [1, 0, 1])
        XCTAssertEqual(plan[0].conflictFiles, [])

        let first = try w.openPullRequests(t.slug, targets: all, only: ["rebocs-admin", "rebocs_api"])
        XCTAssertEqual(first.prs.map(\.repo), ["rebocs-admin", "rebocs_api"])
        XCTAssertEqual(try w.trama(t.slug).prBases, ["rebocs-admin": "develop", "rebocs_api": "develop"])
        var calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("--base develop --head \(t.branch)"))
        XCTAssertFalse(calls.contains("rebocs-android|"), "o repositório fora da rodada não é tocado")
        XCTAssertTrue(Git.branchExists(lab.root + "/remotos/rebocs_api.git", t.branch))
        XCTAssertFalse(Git.branchExists(lab.root + "/remotos/rebocs-android.git", t.branch))

        try pullRequestState("rebocs-admin", state: "OPEN", base: "main")
        try pullRequestState("rebocs_api", state: "OPEN", base: "develop")
        let existing = try w.existingPullRequests(t.slug)
        XCTAssertEqual(existing["rebocs-admin"]?.base, "main")
        XCTAssertNil(existing["rebocs-android"])
        let again = try w.pullRequestPlan(t.slug, existing: existing)
        XCTAssertEqual(again.map(\.action), [.retarget, .create, .update])
        XCTAssertEqual(again[0].summary, "redirecionar o PR #7: main → develop")

        _ = try w.openPullRequests(t.slug, only: ["rebocs-admin", "rebocs_api"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("api --hostname github.com -X PATCH repos/x/rebocs-admin/pulls/7 -f base=develop"))
        XCTAssertFalse(calls.contains("repos/x/rebocs_api/pulls/7 -f base="), "quem já aponta para o destino não é redirecionado")
        XCTAssertTrue(try w.readCapsule(t.slug).journal.contains { $0.text.contains("(antes main)") })

        try pullRequestState("rebocs-admin", state: "OPEN", base: "develop")
        _ = try w.openPullRequests(t.slug, targets: ["rebocs-admin": "main"], only: ["rebocs-admin"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("api --hostname github.com -X PATCH repos/x/rebocs-admin/pulls/7 -f base=main"))
        XCTAssertEqual(try w.trama(t.slug).prBases, ["rebocs_api": "develop"], "voltar para a base padrão apaga a escolha")

        try pullRequestState("rebocs_api", state: "MERGED", base: "develop")
        let merged = try w.pullRequestPlan(t.slug, existing: try w.existingPullRequests(t.slug))
        XCTAssertEqual(merged.first { $0.repo == "rebocs_api" }?.blocker, .merged)
        XCTAssertThrowsError(try w.openPullRequests(t.slug, only: ["rebocs_api"])) {
            XCTAssertTrue(errorMessage($0).contains("já foi mesclado"))
        }
    }

    func testPullRequestPlanListsConflictedFiles() throws {
        let w = try lab.workspace()
        setenv("TRAMA_GH", "/usr/bin/true", 1)
        defer { unsetenv("TRAMA_GH") }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Conflito", repos: ["api"], noFetch: true))
        try lab.commit(w.worktreePath(t.slug, "rebocs_api"), "src/app.txt", "linha A\nlinha 2\nlinha 3\n", "mexe A")
        try lab.pushToMain("rebocs_api", "src/app.txt", "linha B\nlinha 2\nlinha 3\n", "mexe B")
        _ = try w.remoteBranchCatalog(t.slug, fetch: true)
        let row = try XCTUnwrap(try w.pullRequestPlan(t.slug).first)
        XCTAssertEqual(row.conflictFiles, ["src/app.txt"])
        XCTAssertTrue(row.hasConflict)
        XCTAssertEqual(row.ahead, 1)
        XCTAssertEqual(row.action, .create)
    }

    func testParsePullRequestTargets() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Alvos", repos: ["api", "admin"], noFetch: true))
        XCTAssertEqual(try w.parsePullRequestTargets("develop", for: t), ["rebocs_api": "develop", "rebocs-admin": "develop"])
        XCTAssertEqual(try w.parsePullRequestTargets("develop, api=staging", for: t), ["rebocs_api": "staging", "rebocs-admin": "develop"])
        XCTAssertEqual(try w.parsePullRequestTargets("admin=release/1", for: t), ["rebocs-admin": "release/1"])
        XCTAssertThrowsError(try w.parsePullRequestTargets("android=main", for: t)) {
            XCTAssertTrue(errorMessage($0).contains("não faz parte"))
        }
        XCTAssertThrowsError(try w.parsePullRequestTargets("api=", for: t))
    }
}
