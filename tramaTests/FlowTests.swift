import Foundation
import XCTest
@testable import trama

final class FlowTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testRegistrationAndAliases() throws {
        let w = try lab.workspace()
        for (key, name) in [("api", "rebocs_api"), ("admin", "rebocs-admin"), ("rebocs-android", "rebocs-android"), ("android", "rebocs-android")] {
            let r = try w.repo(key)
            XCTAssertEqual(r.name, name)
            XCTAssertEqual(r.base, "main")
        }
        XCTAssertThrowsError(try w.addRepo(lab.repos["rebocs_api"]!), "repositório repetido")
        XCTAssertThrowsError(try w.addRepo(lab.root), "pasta que não é git")
        let w2 = try Workspace.open(root: w.root)
        XCTAssertEqual(w2.config.repos.count, 3)
        XCTAssertEqual(w2.config.context, lab.repos["rebocs-context"])
    }

    func testOpenRequestIsConsumedOnce() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Pedido de abertura", repos: ["api"]))
        XCTAssertNil(w.takeOpenRequest())
        XCTAssertThrowsError(try w.requestOpen("nao-existe"))
        try w.requestOpen(t.slug)
        XCTAssertEqual(w.takeOpenRequest(), t.slug)
        XCTAssertNil(w.takeOpenRequest())
    }

    func testFullFlow() throws {
        let w = try lab.workspace()
        let repos = lab.repos

        let (t, warnings) = try w.newTrama(NewTramaOptions(
            title: "Surcharge noturno", repos: ["api,admin"], task: "CU-482", goal: "Cobrar multiplicador entre 22h e 6h."
        ))
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(t.slug, "surcharge-noturno")
        XCTAssertEqual(t.branch, "trama/surcharge-noturno")
        XCTAssertEqual(t.repos, ["rebocs_api", "rebocs-admin"])
        let wtAPI = w.worktreePath(t.slug, "rebocs_api")
        let wtAdmin = w.worktreePath(t.slug, "rebocs-admin")
        XCTAssertEqual(try lab.git(wtAPI, "rev-parse", "--abbrev-ref", "HEAD"), t.branch)
        XCTAssertNotEqual(Git.execute(wtAPI, ["rev-parse", "--abbrev-ref", "@{upstream}"]).code, 0, "a branch da trama não deve rastrear origin/main")
        let claudeMD = try XCTUnwrap(try File.read(w.tramaPath(t.slug) + "/CLAUDE.md"))
        XCTAssertTrue(claudeMD.contains("/Applications/Trama.app/Contents/MacOS/trama"))
        XCTAssertTrue(claudeMD.contains(wtAdmin))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: w.tramaPath(t.slug) + "/CAPSULA.md"))

        var capsule = try w.readCapsule(t.slug)
        XCTAssertTrue(capsule.exists)
        XCTAssertEqual(capsule.title, "Surcharge noturno")
        XCTAssertEqual(capsule.goal, "Cobrar multiplicador entre 22h e 6h.")
        XCTAssertEqual(capsule.journal.count, 1)
        XCTAssertTrue(capsule.path.hasPrefix(repos["rebocs-context"]!))
        XCTAssertThrowsError(try w.newTrama(NewTramaOptions(title: "Surcharge noturno", repos: ["api"])), "slug repetido")

        try FileManager.default.createDirectory(atPath: wtAPI + "/src/fundo", withIntermediateDirectories: true)
        let place = try w.locate(wtAPI + "/src/fundo")
        XCTAssertEqual(place.trama.slug, t.slug)
        XCTAssertEqual(place.repo?.name, "rebocs_api")
        XCTAssertThrowsError(try w.locate(repos["rebocs_api"]!))

        try lab.commit(wtAPI, "src/noturno.txt", "multiplicador\n", "feat: janela noturna")
        try lab.write(wtAPI + "/rascunho.txt", "wip")
        try lab.pushToMain("rebocs_api", "docs/outra.txt", "coisa\n", "docs: outra")
        XCTAssertEqual(w.repoStatus(t, try w.repo("api"), predictConflict: false).behind, 0, "sem fetch, a trama ainda não sabe que a main andou")
        XCTAssertEqual(w.fetchAll(), [])
        var st = w.repoStatus(t, try w.repo("api"), predictConflict: true)
        XCTAssertEqual(st.ahead, 1)
        XCTAssertEqual(st.behind, 1)
        XCTAssertEqual(st.changed, 1)
        XCTAssertEqual(st.conflict, "limpo")
        XCTAssertEqual(st.lastCommit?.subject, "feat: janela noturna")

        try lab.commit(wtAdmin, "src/app.txt", "linha 1\nNOSSA\nlinha 3\n", "feat: nossa")
        try lab.pushToMain("rebocs-admin", "src/app.txt", "linha 1\nDELES\nlinha 3\n", "feat: deles")
        w.fetchAll()
        XCTAssertEqual(w.repoStatus(t, try w.repo("admin"), predictConflict: true).conflict, "conflito")

        try w.addDecision(t.slug, author: "você", "multiplicador mora em pricing_modifiers")
        try w.addHandoff(t.slug, from: "rebocs_api", to: "rebocs-admin", author: "agente · api", "campo night_multiplier pronto")
        try w.addPending(t.slug, "testar 5h59")
        try w.addPending(t.slug, "texto do selo")
        try w.completePending(t.slug, 1)
        XCTAssertThrowsError(try w.completePending(t.slug, 1), "não conclui de novo")

        let now = Date()
        let output = try w.handleHook(HookInput(session: "s-admin", event: "SessionStart", cwd: wtAdmin, source: "startup"), now: now)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "SessionStart")
        let context = try XCTUnwrap(specific["additionalContext"] as? String)
        for snippet in ["Surcharge noturno", "rebocs-admin", "campo night_multiplier pronto", "Handoffs esperando por você", "pricing_modifiers"] {
            XCTAssertTrue(context.contains(snippet), "contexto sem “\(snippet)”")
        }
        try w.handleHook(HookInput(session: "s-admin", event: "UserPromptSubmit", cwd: wtAdmin, userPrompt: "implementa a tela de modificadores\ncom detalhes"), now: now)
        var ags = try w.agents()
        XCTAssertEqual(ags.count, 1)
        XCTAssertEqual(ags[0].state, AgentState.working)
        XCTAssertEqual(ags[0].repo, "rebocs-admin")
        XCTAssertEqual(ags[0].message, "implementa a tela de modificadores")
        try w.handleHook(HookInput(session: "s-admin", event: "Notification", cwd: wtAdmin, message: "Claude needs your permission to use Bash", notificationType: "permission_prompt"), now: now)
        XCTAssertEqual(try w.agents()[0].state, AgentState.waiting)
        try w.handleHook(HookInput(session: "s-admin", event: "PostToolUse", cwd: wtAdmin), now: now)
        try w.handleHook(HookInput(session: "s-admin", event: "Stop", cwd: wtAdmin, lastAssistantMessage: "Pronto: tela criada.\nDetalhes..."), now: now)
        ags = try w.agents()
        XCTAssertEqual(ags[0].state, AgentState.done)
        XCTAssertEqual(ags[0].message, "Pronto: tela criada.")
        XCTAssertEqual(try w.handleHook(HookInput(session: "fora", event: "SessionStart", cwd: repos["rebocs_api"]!), now: now), "", "fora de uma trama o hook fica quieto")
        XCTAssertEqual(try w.confirmHandoffs(t.slug, to: "rebocs-admin"), 1)
        capsule = try w.readCapsule(t.slug)
        XCTAssertEqual(capsule.decisions.count, 1)
        XCTAssertTrue(capsule.handoffs[0].done)
        XCTAssertEqual(capsule.pending.map(\.done), [true, false])

        let state = try w.fullState()
        XCTAssertEqual(state.tramas.count, 1)
        XCTAssertEqual(state.tramas[0].status.count, 2)
        XCTAssertEqual(state.tramas[0].status(for: "rebocs-admin")?.agents.count, 1)
        XCTAssertEqual(state.tramas[0].title, "Surcharge noturno", "acesso direto aos campos da trama")
        let stateJSON = try JSONSerialization.jsonObject(with: JSON.encoder().encode(state)) as? [String: Any]
        let first = (stateJSON?["tramas"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["slug"] as? String, "surcharge-noturno", "JSON achatado como no motor antigo")
        try w.handleHook(HookInput(session: "s-admin", event: "SessionEnd", cwd: wtAdmin), now: now)
        XCTAssertEqual(try w.agents().count, 0)

        _ = try w.pullRepos(t.slug, ["android"], noFetch: true)
        XCTAssertTrue(Paths.exists(w.worktreePath(t.slug, "rebocs-android")))
        XCTAssertTrue(try XCTUnwrap(try File.read(w.tramaPath(t.slug) + "/CLAUDE.md")).contains("rebocs-android"))
        _ = try w.dropRepo(t.slug, "android")
        XCTAssertTrue(Git.branchExists(repos["rebocs-android"]!, t.branch), "soltar mantém a branch")

        _ = try w.park(t.slug)
        XCTAssertTrue(try w.trama(t.slug).isParked)
        try FileManager.default.removeItem(atPath: wtAPI + "/rascunho.txt")
        let (resumed, results) = try w.resume(t.slug, rebase: true, noFetch: true)
        XCTAssertTrue(resumed.isActive)
        XCTAssertNil(resumed.parkedAt)
        let situations = Dictionary(uniqueKeysWithValues: results.map { ($0.repo, $0.situation) })
        XCTAssertEqual(situations["rebocs_api"], "rebase")
        XCTAssertEqual(situations["rebocs-admin"], "conflito")
        st = w.repoStatus(t, try w.repo("api"), predictConflict: false)
        XCTAssertEqual(st.behind, 0)
        XCTAssertEqual(st.ahead, 1)
        XCTAssertFalse(Git.execute(wtAdmin, ["status"]).output.contains("rebase in progress"), "rebase com conflito foi abortado")

        try lab.write(repos["rebocs-admin"]! + "/esquecido.txt", "ops")
        let api = repos["rebocs_api"]!
        try lab.git(api, "branch", "feat/velha")
        try lab.git(api, "checkout", "-q", "-b", "feat/solta")
        try lab.commit(api, "solta.txt", "x", "feat: solta")
        try lab.git(api, "checkout", "-q", "-b", "feat/enviada")
        try lab.git(api, "push", "-q", "-u", "origin", "feat/enviada")
        try lab.commit(api, "local.txt", "y", "feat: só local")
        try lab.git(api, "checkout", "-q", "main")
        let findings = try w.findings()
        let byType = Dictionary(findings.map { ($0.type + "/" + ($0.repo ?? ""), $0) }, uniquingKeysWith: { a, _ in a })
        let edit = try XCTUnwrap(byType[FindingType.editOnBase + "/rebocs-admin"])
        XCTAssertEqual(edit.suggestedTrama, t.slug)
        XCTAssertEqual(edit.command, "trama adotar admin --para surcharge-noturno")
        XCTAssertEqual(byType[FindingType.merged + "/rebocs_api"]?.items, ["feat/velha"])
        XCTAssertEqual(byType[FindingType.noRemote + "/rebocs_api"]?.branch, "feat/solta")
        XCTAssertEqual(byType[FindingType.noRemote + "/rebocs_api"]?.count, 1)
        XCTAssertEqual(byType[FindingType.unpushed + "/rebocs_api"]?.branch, "feat/enviada")
        XCTAssertEqual(byType[FindingType.unpushed + "/rebocs_api"]?.count, 1)
        XCTAssertFalse(findings.contains { $0.branch == t.branch }, "a branch da trama não é um achado")
        XCTAssertEqual(findings.first?.type, FindingType.editOnBase)

        try w.adoptChanges("admin", into: t.slug)
        XCTAssertTrue(Paths.exists(wtAdmin + "/esquecido.txt"))
        XCTAssertEqual(try Git.statusLines(repos["rebocs-admin"]!), [])
        XCTAssertEqual(try w.cleanMerged("api"), ["feat/velha"])
        XCTAssertTrue(Git.branchExists(api, "feat/solta"), "limpar não apaga branch com commit exclusivo")

        XCTAssertTrue(try w.syncCapsule(t.slug))
        XCTAssertEqual(try lab.git(repos["rebocs-context"]!, "log", "-1", "--format=%s"), "trama(surcharge-noturno): atualiza cápsula")
        XCTAssertFalse(try w.syncCapsule(t.slug), "nada novo")

        XCTAssertThrowsError(try w.archive(t.slug))
        _ = try w.archive(t.slug, force: true)
        XCTAssertFalse(Paths.exists(w.tramaPath(t.slug)))
        XCTAssertTrue(Git.branchExists(api, t.branch), "arquivar mantém as branches")
        XCTAssertTrue(try w.readCapsule(t.slug).exists, "a cápsula fica no repositório de contexto")
    }

    func testContextPerTrama() throws {
        let w = try lab.workspace()
        try lab.newRepo("outro-contexto")
        let other = lab.repos["outro-contexto"]!
        let global = lab.repos["rebocs-context"]!

        let (a, _) = try w.newTrama(NewTramaOptions(title: "Global", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Outro projeto", repos: ["api"], context: other, noFetch: true))
        XCTAssertNil(a.context)
        XCTAssertEqual(b.context, other)
        XCTAssertTrue(w.capsulePath(a.slug).hasPrefix(global))
        XCTAssertTrue(w.capsulePath(b.slug).hasPrefix(other))
        XCTAssertTrue(try w.readCapsule(b.slug).exists)

        XCTAssertThrowsError(try w.newTrama(NewTramaOptions(title: "Quebrada", repos: ["api"], context: lab.root + "/nao-existe", noFetch: true)))

        try w.addDecision(a.slug, author: "você", "vai junto")
        let moved = try w.setTramaContext(a.slug, other)
        XCTAssertEqual(moved.context, other)
        XCTAssertTrue(w.capsulePath(a.slug).hasPrefix(other))
        XCTAssertEqual(try w.readCapsule(a.slug).decisions.count, 1, "a cápsula acompanha a troca")
        XCTAssertFalse(Paths.exists(global + "/tramas/" + a.slug + ".md"))

        let back = try w.setTramaContext(a.slug, nil)
        XCTAssertNil(back.context)
        XCTAssertTrue(w.capsulePath(a.slug).hasPrefix(global))
        XCTAssertEqual(try w.readCapsule(a.slug).decisions.count, 1)

        XCTAssertTrue(try w.syncCapsule(b.slug))
        XCTAssertFalse(try lab.git(other, "log", "-1", "--format=%s").isEmpty)
    }

    func testSetBaseChangesTramaBase() throws {
        let w = try lab.workspace(withContext: false)
        let api = lab.repos["rebocs_api"]!
        try lab.git(api, "branch", "develop")
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Base", repos: ["api"], noFetch: true))
        XCTAssertTrue(try w.baseCandidates(repos: ["api"], excluding: t.branch).contains("develop"))
        let updated = try w.setBase(t.slug, base: "develop")
        XCTAssertEqual(updated.base, "develop")
        XCTAssertThrowsError(try w.setBase(t.slug, base: "nao-existe"))
    }

    func testWithoutContextRepo() throws {
        let w = try lab.workspace(withContext: false)
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Solo", repos: ["api"], noFetch: true))
        XCTAssertEqual(w.capsulePath(t.slug), w.tramaPath(t.slug) + "/CAPSULA.md")
        try w.addDecision(t.slug, author: "você", "ok")
        _ = try w.archive(t.slug)
        let c = try w.readCapsule(t.slug)
        XCTAssertTrue(c.exists, "sem contexto, a cápsula sobrevive ao arquivamento")
        XCTAssertEqual(c.decisions.count, 1)
    }

    func testRemoveDeletesTramaAndOptionallyBranches() throws {
        let w = try lab.workspace(withContext: true)
        let (keep, _) = try w.newTrama(NewTramaOptions(title: "Fica", repos: ["api"], noFetch: true))
        let (gone, _) = try w.newTrama(NewTramaOptions(title: "Some", repos: ["api"], noFetch: true))
        let api = lab.repos["rebocs_api"]!
        let removed = try w.remove(gone.slug)
        XCTAssertEqual(removed.slug, gone.slug)
        XCTAssertEqual(try w.tramas().map(\.slug), [keep.slug])
        XCTAssertFalse(Paths.exists(w.tramaPath(gone.slug)))
        XCTAssertTrue(Git.branchExists(api, gone.branch), "por padrão a branch fica")

        let (again, _) = try w.newTrama(NewTramaOptions(title: "Some de novo", repos: ["api"], noFetch: true))
        _ = try w.remove(again.slug, deleteBranches: true)
        XCTAssertFalse(Git.branchExists(api, again.branch))
    }

    func testAgentAtTramaRootIsRoot() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Agent raiz", repos: ["api"], noFetch: true))
        try w.handleHook(HookInput(session: "raiz", event: "UserPromptSubmit", cwd: w.tramaPath(t.slug), userPrompt: "coordene"))
        try w.handleHook(HookInput(session: "repo", event: "UserPromptSubmit", cwd: w.worktreePath(t.slug, "rebocs_api"), userPrompt: "edite"))
        let agents = try w.agents()
        XCTAssertTrue(try XCTUnwrap(agents.first { $0.session == "raiz" }).isRoot)
        XCTAssertFalse(try XCTUnwrap(agents.first { $0.session == "repo" }).isRoot)
    }

    func testEditorIsResolvedInsideTheWorktree() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Editor", repos: ["api"], noFetch: true))
        let wt = w.worktreePath(t.slug, "rebocs_api")
        try FileManager.default.createDirectory(atPath: wt + "/App.xcodeproj", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: wt + "/Pods/Pods.xcodeproj", withIntermediateDirectories: true)
        let launch = try w.editorLaunch(t.slug, repo: "api")
        XCTAssertEqual(launch.app, "Xcode")
        XCTAssertEqual(launch.path, wt + "/App.xcodeproj", "abre o projeto do worktree, não o da cópia principal")
        try FileManager.default.createDirectory(atPath: wt + "/App.xcworkspace", withIntermediateDirectories: true)
        XCTAssertEqual(try w.editorLaunch(t.slug, repo: "api").path, wt + "/App.xcworkspace")
        try w.setEditor("api", "Cursor")
        let custom = try w.editorLaunch(t.slug, repo: "api")
        XCTAssertEqual(custom.app, "Cursor")
        XCTAssertEqual(custom.path, wt)
        try w.setEditor("api", nil)
        XCTAssertNil(try w.repo("api").editor)
    }

    func testCodeWorkspaceListsEveryWorktreeAndGoesAwayOnArchive() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Janela única", repos: ["api", "admin"], noFetch: true))
        let path = try w.writeCodeWorkspace(t.slug)
        XCTAssertEqual(path, w.tramaPath(t.slug) + "/" + t.slug + ".code-workspace")
        let json = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(File.read(path)).utf8)) as? [String: Any]
        let folders = try XCTUnwrap(json?["folders"] as? [[String: String]])
        XCTAssertEqual(folders.map { $0["path"] }, t.repos)
        XCTAssertEqual(folders.map { $0["name"] }, try t.repos.map { try w.repo($0).alias })
        for folder in folders { XCTAssertTrue(Paths.isDirectory(w.tramaPath(t.slug) + "/" + (folder["path"] ?? ""))) }
        _ = try w.archive(t.slug)
        XCTAssertFalse(Paths.exists(path))
    }

    func testFailureMidwayUndoesEverything() throws {
        let w = try lab.workspace()
        try FileManager.default.createDirectory(atPath: w.worktreePath("quebrada", "rebocs-admin"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try w.newTrama(NewTramaOptions(title: "Quebrada", repos: ["api", "admin"], noFetch: true)))
        XCTAssertFalse(Git.branchExists(lab.repos["rebocs_api"]!, "trama/quebrada"))
        XCTAssertEqual(try w.tramas().count, 0)
    }
}
