import Foundation
import XCTest
@testable import trama

final class Lab {
    let root: String
    var repos: [String: String] = [:]

    init() throws {
        root = Paths.real(NSTemporaryDirectory()) + "/trama-teste-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        setenv("GIT_AUTHOR_NAME", "Teste", 1)
        setenv("GIT_AUTHOR_EMAIL", "teste@example.com", 1)
        setenv("GIT_COMMITTER_NAME", "Teste", 1)
        setenv("GIT_COMMITTER_EMAIL", "teste@example.com", 1)
        setenv("GIT_CONFIG_GLOBAL", root + "/gitconfig", 1)
        setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
        try write(root + "/gitconfig", "[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n[commit]\n\tgpgsign = false\n")
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    func git(_ dir: String, _ args: String...) throws -> String {
        try Git.run(dir, args)
    }

    func write(_ path: String, _ content: String) throws {
        try File.write(content, to: path)
    }

    func commit(_ dir: String, _ file: String, _ content: String, _ msg: String) throws {
        try write(dir + "/" + file, content)
        try git(dir, "add", "-A")
        try git(dir, "commit", "-q", "-m", msg)
    }

    @discardableResult
    func newRepo(_ name: String) throws -> String {
        let remote = "\(root)/remotos/\(name).git"
        let dir = "\(root)/github/\(name)"
        try FileManager.default.createDirectory(atPath: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try git(remote, "init", "-q", "--bare", "-b", "main")
        try git(dir, "init", "-q", "-b", "main")
        try commit(dir, "README.md", "# \(name)\n", "inicial")
        try commit(dir, "src/app.txt", "linha 1\nlinha 2\nlinha 3\n", "app")
        try git(dir, "remote", "add", "origin", remote)
        try git(dir, "push", "-q", "-u", "origin", "main")
        repos[name] = dir
        return dir
    }

    func pushToMain(_ name: String, _ file: String, _ content: String, _ msg: String) throws {
        let peer = "\(root)/colega/\(name)"
        if Paths.exists(peer) {
            try git(peer, "pull", "-q")
        } else {
            try FileManager.default.createDirectory(atPath: "\(root)/colega", withIntermediateDirectories: true)
            try git(root, "clone", "-q", "\(root)/remotos/\(name).git", peer)
        }
        try commit(peer, file, content, msg)
        try git(peer, "push", "-q", "origin", "main")
    }

    func workspace(withContext: Bool = true) throws -> Workspace {
        for n in ["rebocs_api", "rebocs-admin", "rebocs-android", "rebocs-context"] {
            try newRepo(n)
        }
        let w = try Workspace.configure(root: root + "/Tramas", context: withContext ? repos["rebocs-context"] : nil)
        w.executable = "/Applications/Trama.app/Contents/MacOS/trama"
        for n in ["rebocs_api", "rebocs-admin", "rebocs-android"] {
            try w.addRepo(repos[n]!)
        }
        return w
    }
}

final class TextTests: XCTestCase {
    func testSlugify() {
        XCTAssertEqual(slugify("Surcharge noturno"), "surcharge-noturno")
        XCTAssertEqual(slugify("Onboarding do prestador!"), "onboarding-do-prestador")
        XCTAssertEqual(slugify("  Ação: Pix / Repasse D+1 "), "acao-pix-repasse-d-1")
        XCTAssertEqual(slugify("ÇÃO"), "cao")
        XCTAssertEqual(slugify("!!!"), "")
    }

    func testRelativeTime() {
        let now = Date()
        let t = Int64(now.timeIntervalSince1970)
        XCTAssertEqual(relativeTime(t - 10, now: now), "agora")
        XCTAssertEqual(relativeTime(t - 8 * 60, now: now), "há 8 min")
        XCTAssertEqual(relativeTime(t - 3 * 3600, now: now), "há 3 h")
        XCTAssertEqual(relativeTime(t - 30 * 3600, now: now), "ontem")
        XCTAssertEqual(relativeTime(t - 6 * 86400, now: now), "há 6 dias")
        XCTAssertEqual(relativeTime(nil), "")
    }

    func testTable() {
        XCTAssertEqual(table([["a", "bb", "c"], ["ddd", "e", "f"]]), "a    bb  c\nddd  e   f\n")
    }

    func testArguments() throws {
        let a = try Arguments.parse(["Surcharge", "noturno", "--repos", "api,admin", "--sem-fetch", "--base=develop"], valueFlags: ["repos", "base"])
        XCTAssertEqual(a.text(from: 0), "Surcharge noturno")
        XCTAssertEqual(a.value("repos"), "api,admin")
        XCTAssertEqual(a.value("base"), "develop")
        XCTAssertTrue(a.has("sem-fetch"))
        XCTAssertThrowsError(try Arguments.parse(["--repos"], valueFlags: ["repos"]))
    }
}

final class CapsuleTests: XCTestCase {
    func testSections() {
        let t = Trama(slug: "x", title: "X", branch: "trama/x", base: nil, repos: ["a", "b"], state: TramaState.active, task: nil, createdAt: 0)
        var doc = CapsuleDoc.new(t, goal: "")
        XCTAssertTrue(doc.contains("_("))
        doc = CapsuleDoc.set(doc, section: CapsuleSection.goal, content: "Fazer Y")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.decisions, line: "- 2026-09-30 10:00 · você: usar Z")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.decisions, line: "- 2026-09-30 10:05 · agente · api: janela usa fuso da cidade")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.pending, line: "- [ ] testar 5h59")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.pending, line: "- [ ] texto do selo")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.handoffs, line: "- [ ] 2026-09-30 10:06 · rebocs_api → rebocs-android · agente · api: exibir selo")
        let c = CapsuleDoc.parse(slug: "x", path: "/tmp/x.md", doc: doc)
        XCTAssertEqual(c.title, "X")
        XCTAssertEqual(c.goal, "Fazer Y")
        XCTAssertEqual(c.decisions.count, 2)
        XCTAssertEqual(c.decisions[1].author, "agente · api")
        XCTAssertEqual(c.decisions[1].text, "janela usa fuso da cidade")
        XCTAssertNotNil(c.decisions[1].timestamp)
        XCTAssertEqual(c.handoffs.count, 1)
        XCTAssertEqual(c.handoffs[0].from, "rebocs_api")
        XCTAssertEqual(c.handoffs[0].to, "rebocs-android")
        XCTAssertEqual(c.handoffs[0].author, "agente · api")
        XCTAssertEqual(c.handoffs[0].text, "exibir selo")
        XCTAssertFalse(c.handoffs[0].done)
        XCTAssertEqual(c.pending.map(\.text), ["testar 5h59", "texto do selo"])

        let (doc2, n) = CapsuleDoc.mark(doc, section: CapsuleSection.pending) { $0.index == 2 }
        let c2 = CapsuleDoc.parse(slug: "x", path: "", doc: doc2)
        XCTAssertEqual(n, 1)
        XCTAssertFalse(c2.pending[0].done)
        XCTAssertTrue(c2.pending[1].done)
        XCTAssertEqual(doc2.components(separatedBy: "## \(CapsuleSection.journal)").count, 2)
        XCTAssertEqual(doc2.components(separatedBy: "## \(CapsuleSection.handoffs)").count, 2)
    }

    func testMissingSectionIsCreated() {
        let doc = CapsuleDoc.insert("# Só título\n", section: CapsuleSection.decisions, line: "- 2026-09-30 10:00 · você: ok")
        XCTAssertEqual(CapsuleDoc.parse(slug: "x", path: "", doc: doc).decisions.count, 1)
    }
}

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

    func testNotInitialized() {
        XCTAssertThrowsError(try Workspace.open(root: lab.root + "/nada")) { error in
            XCTAssertEqual(error as? TramaError, .notInitialized)
        }
    }

    func testDecodesConfigWrittenByOlderVersion() throws {
        let legacy = """
        {
          "basePadrao" : "main",
          "contexto" : "/Users/x/rebocs-context",
          "pastaCapsulas" : "tramas",
          "prefixoBranch" : "trama/",
          "repos" : [
            { "apelido" : "admin", "base" : "main", "caminho" : "/Users/x/rebocs-admin", "nome" : "rebocs-admin" },
            { "apelido" : "api", "base" : "main", "caminho" : "/Users/x/rebocs_api", "nome" : "rebocs_api" }
          ],
          "versao" : 1
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(legacy.utf8))
        XCTAssertEqual(config.defaultBranch, "main")
        XCTAssertEqual(config.context, "/Users/x/rebocs-context")
        XCTAssertEqual(config.branchPrefix, "trama/")
        XCTAssertEqual(config.repos.count, 2)
        XCTAssertEqual(config.repos[0].name, "rebocs-admin")
        XCTAssertEqual(config.repos[0].alias, "admin")
        XCTAssertEqual(config.repos[0].path, "/Users/x/rebocs-admin")
    }

    func testDecodesTramasWrittenByOlderVersion() throws {
        let legacy = """
        {
          "tramas" : [
            {
              "atualizadaEm" : 1790782145,
              "branch" : "trama/rebocs-dev",
              "criadaEm" : 1790782145,
              "estado" : "ativa",
              "repos" : ["rebocs-admin", "rebocs_api"],
              "slug" : "rebocs-dev",
              "titulo" : "Rebocs dev"
            }
          ]
        }
        """
        struct TramasFileShape: Decodable { var tramas: [Trama] }
        let decoded = try JSONDecoder().decode(TramasFileShape.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.tramas.count, 1)
        XCTAssertEqual(decoded.tramas[0].title, "Rebocs dev")
        XCTAssertEqual(decoded.tramas[0].state, TramaState.active)
        XCTAssertTrue(decoded.tramas[0].isActive)
        XCTAssertEqual(decoded.tramas[0].createdAt, 1790782145)
    }

    func testDecodesAgentWrittenByOlderVersion() throws {
        let legacy = """
        {
          "atualizadoEm" : 1790782157,
          "cwd" : "/Users/x/Tramas/rebocs-dev/rebocs_api",
          "estado" : "aberto",
          "iniciadoEm" : 1790782157,
          "repo" : "rebocs_api",
          "sessao" : "a0ff0c95-7f7c-4cae-9b5a-1cb414b3e99d",
          "trama" : "rebocs-dev"
        }
        """
        let agent = try JSONDecoder().decode(Agent.self, from: Data(legacy.utf8))
        XCTAssertEqual(agent.session, "a0ff0c95-7f7c-4cae-9b5a-1cb414b3e99d")
        XCTAssertEqual(agent.state, AgentState.open)
        XCTAssertEqual(agent.repo, "rebocs_api")
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

    func testRecipeSuggestionOnRegistration() throws {
        let dir = try lab.newRepo("suggest-web")
        try lab.write(dir + "/.env", "A=1\n")
        try lab.write(dir + "/.env.example", "A=\n")
        try lab.write(dir + "/package-lock.json", "{}\n")
        let w = try lab.workspace()
        let r = try w.addRepo(dir)
        XCTAssertEqual(r.recipe, Recipe(copy: [".env*"], run: ["npm ci"]))
        XCTAssertEqual(try Workspace.open(root: w.root).repo("suggest-web").recipe, r.recipe)
    }

    func testRecipeCopiesFilesAndRunsCommands() throws {
        let w = try lab.workspace()
        let api = lab.repos["rebocs_api"]!
        try lab.write(api + "/.env", "SECRET=1\n")
        try lab.write(api + "/config/.env.local", "LOCAL=1\n")
        try w.setRecipe("api", copy: [".env*", "config/.env*"], run: ["echo ok > prepared.txt"])
        XCTAssertThrowsError(try w.setRecipe("api", copy: ["../fora"], run: []))
        let (t, warnings) = try w.newTrama(NewTramaOptions(title: "Preparada", repos: ["api", "admin"], noFetch: true))
        XCTAssertTrue(warnings.isEmpty)
        let wt = w.worktreePath(t.slug, "rebocs_api")
        XCTAssertEqual(try File.read(wt + "/.env"), "SECRET=1\n")
        XCTAssertEqual(try File.read(wt + "/config/.env.local"), "LOCAL=1\n")
        let deadline = Date().addingTimeInterval(20)
        while w.prepState(t.slug, "rebocs_api") == PrepState.running, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(w.prepState(t.slug, "rebocs_api"), PrepState.ready)
        XCTAssertEqual(try File.read(wt + "/prepared.txt"), "ok\n")
        XCTAssertNil(w.prepState(t.slug, "rebocs-admin"))
        let status = w.repoStatus(t, try w.repo("api"), predictConflict: false)
        XCTAssertEqual(status.prep, PrepState.ready)
        XCTAssertTrue(try File.read(w.prepLogPath(t.slug, "rebocs_api"))?.contains("copiado: .env") == true)
    }

    func testRecipeFailureIsReported() throws {
        let w = try lab.workspace()
        try w.setRecipe("api", copy: [], run: ["echo antes", "exit 3", "echo depois"])
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Falha", repos: ["api"], noFetch: true))
        let deadline = Date().addingTimeInterval(20)
        while w.prepState(t.slug, "rebocs_api") == PrepState.running, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(w.prepState(t.slug, "rebocs_api"), PrepState.failed)
        let log = try File.read(w.prepLogPath(t.slug, "rebocs_api")) ?? ""
        XCTAssertTrue(log.contains("antes"))
        XCTAssertFalse(log.contains("depois"))
        _ = try w.archive(t.slug)
        XCTAssertNil(w.prepState(t.slug, "rebocs_api"))
    }

    func testPortsPerTramaAndServiceLifecycle() throws {
        let w = try lab.workspace()
        try w.setServices("api", [ServiceConfig(name: "dev", command: "echo $PORT $TRAMA_PORTA_BASE > ports.txt; exec sleep 60", port: 3100)])
        XCTAssertThrowsError(try w.setServices("api", [ServiceConfig(name: "x y", command: "a", port: 3000)]))
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Porta A", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Porta B", repos: ["api"], noFetch: true))
        XCTAssertEqual([a.portIndex, b.portIndex], [0, 1])
        let r = try w.repo("api")
        let service = r.services[0]
        XCTAssertEqual(w.servicePort(a, service), 3100)
        XCTAssertEqual(w.servicePort(b, service), 3110)
        defer {
            w.stopServices(a.slug)
            w.stopServices(b.slug)
        }
        XCTAssertEqual(try w.startServices(a.slug).map(\.port), [3100])
        XCTAssertEqual(try w.startServices(b.slug).map(\.port), [3110])
        XCTAssertTrue(try w.startServices(a.slug).isEmpty, "já no ar")
        XCTAssertTrue(w.serviceStatuses(a, r)[0].running)
        let wt = w.worktreePath(b.slug, "rebocs_api")
        let deadline = Date().addingTimeInterval(20)
        while !Paths.exists(wt + "/ports.txt"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(try File.read(wt + "/ports.txt"), "3110 3010\n")
        XCTAssertEqual(w.stopServices(a.slug), 1)
        XCTAssertFalse(w.serviceStatuses(a, r)[0].running)
        XCTAssertTrue(w.serviceStatuses(b, r)[0].running)
        _ = try w.park(b.slug)
        XCTAssertFalse(w.serviceStatuses(b, r)[0].running)
        XCTAssertThrowsError(try w.startServices(b.slug), "estacionada")
        _ = try w.archive(a.slug, force: true)
        let (c, _) = try w.newTrama(NewTramaOptions(title: "Porta C", repos: ["api"], noFetch: true))
        XCTAssertEqual(c.portIndex, 0, "o índice de uma trama arquivada é reaproveitado")
    }

    func testPortInUseIsRefused() throws {
        let w = try lab.workspace()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = in_addr_t(0)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 1)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        let busy = Int(UInt16(bigEndian: addr.sin_port))
        XCTAssertTrue(Workspace.portInUse(busy))
        try w.setServices("api", [ServiceConfig(name: "dev", command: "sleep 60", port: busy)])
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Ocupada", repos: ["api"], noFetch: true))
        XCTAssertThrowsError(try w.startServices(t.slug)) { XCTAssertTrue(errorMessage($0).contains("em uso")) }
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

    func testFailureMidwayUndoesEverything() throws {
        let w = try lab.workspace()
        try FileManager.default.createDirectory(atPath: w.worktreePath("quebrada", "rebocs-admin"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try w.newTrama(NewTramaOptions(title: "Quebrada", repos: ["api", "admin"], noFetch: true)))
        XCTAssertFalse(Git.branchExists(lab.repos["rebocs_api"]!, "trama/quebrada"))
        XCTAssertEqual(try w.tramas().count, 0)
    }
}

final class HooksTests: XCTestCase {
    func testInstallRemove() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let path = lab.root + "/settings.json"
        try lab.write(path, #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say pronto"}]}]}}"#)
        let exe = "/Applications/Trama.app/Contents/MacOS/trama"
        try Hooks.install(settings: path, executable: exe)
        try Hooks.install(settings: path, executable: exe)
        XCTAssertTrue(try Hooks.status(settings: path).values.allSatisfy { $0 })
        XCTAssertEqual(Hooks.installedCommand(settings: path), exe + " hook")

        let m = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        XCTAssertEqual(m["model"] as? String, "opus", "não perde outras configurações")
        let hooks = try XCTUnwrap(m["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["Stop"] as? [Any])?.count, 2, "o hook do usuário + o do Trama, sem duplicar")
        let start = ((hooks["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(start?["command"] as? String, exe + " hook")
        XCTAssertNil(start?["async"], "SessionStart é síncrono")
        XCTAssertTrue(Paths.exists(path + ".antes-da-trama"))
        XCTAssertFalse(try String(contentsOfFile: path).contains("\\/"), "caminhos sem barras escapadas")

        XCTAssertFalse(Hooks.repointIfNeeded(settings: path, executable: exe))
        XCTAssertTrue(Hooks.repointIfNeeded(settings: path, executable: "/Users/x/Applications/Trama.app/Contents/MacOS/trama"))
        XCTAssertEqual(Hooks.installedCommand(settings: path), "/Users/x/Applications/Trama.app/Contents/MacOS/trama hook")

        XCTAssertEqual(try Hooks.remove(settings: path), Hooks.events.count)
        let after = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let left = try XCTUnwrap(after["hooks"] as? [String: Any])
        XCTAssertEqual(Array(left.keys), ["Stop"])

        try lab.write(path, "{ quebrado")
        XCTAssertThrowsError(try Hooks.install(settings: path, executable: exe), "não sobrescreve settings.json inválido")
    }

    func testCommandWithSpace() {
        XCTAssertEqual(Hooks.command("/Users/x/My Apps/Trama.app/Contents/MacOS/trama"), "\"/Users/x/My Apps/Trama.app/Contents/MacOS/trama\" hook")
    }
}

final class CLITests: XCTestCase {
    struct RunResult {
        var code: Int32
        var output: String
        var error: String
    }

    func run(_ args: [String], in folder: String, root: String, input: String = "", agent: Bool = false) -> RunResult {
        var output = ""
        var error = ""
        var environment = ["TRAMA_HOME": root]
        if agent { environment["CLAUDECODE"] = "1" }
        let cli = CLI(
            output: { output += $0 },
            error: { error += $0 },
            input: { Data(input.utf8) },
            currentDirectory: { folder },
            environment: environment
        )
        setenv("TRAMA_HOME", root, 1)
        let code = cli.run(args)
        return RunResult(code: code, output: output, error: error)
    }

    func testAgentFlow() throws {
        let lab = try Lab()
        defer {
            lab.cleanup()
            unsetenv("TRAMA_HOME")
        }
        let w = try lab.workspace()
        let root = w.root

        var r = run(["nova", "Surcharge", "noturno", "--repos", "api,admin", "--sem-fetch", "--objetivo", "Cobrar à noite"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(r.output.contains("✓ Trama “Surcharge noturno” tecida"))

        let wtAPI = w.worktreePath("surcharge-noturno", "rebocs_api")
        r = run(["onde"], in: wtAPI, root: root)
        XCTAssertEqual(r.output, "Surcharge noturno (surcharge-noturno) · rebocs_api\n")

        r = run(["decisao", "janela", "usa", "o", "fuso", "da", "cidade"], in: wtAPI, root: root, agent: true)
        XCTAssertEqual(r.code, 0, r.error)
        r = run(["handoff", "admin", "campo night_multiplier pronto"], in: wtAPI, root: root, agent: true)
        XCTAssertEqual(r.code, 0, r.error)
        r = run(["handoff", "android", "exibir selo"], in: wtAPI, root: root, agent: true)
        XCTAssertTrue(r.error.contains("não faz parte desta trama"))

        r = run(["capsula", "--json"], in: wtAPI, root: root)
        let capsule = try JSONDecoder().decode(TramaCapsule.self, from: Data(r.output.utf8))
        XCTAssertEqual(capsule.decisions.first?.author, "agente · api")
        XCTAssertEqual(capsule.decisions.first?.text, "janela usa o fuso da cidade")
        XCTAssertEqual(capsule.handoffs.first?.to, "rebocs-admin")
        XCTAssertEqual(capsule.goal, "Cobrar à noite")

        let event = #"{"session_id":"abc-1","hook_event_name":"SessionStart","cwd":"\#(wtAPI)","source":"startup"}"#
        r = run(["hook"], in: lab.root, root: root, input: event)
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.output.hasPrefix(#"{"hookSpecificOutput""#))
        r = run(["hook"], in: lab.root, root: root, input: "isto não é json")
        XCTAssertEqual(r.code, 0, "o hook nunca falha")
        XCTAssertEqual(r.output, "")

        r = run(["recebido"], in: w.worktreePath("surcharge-noturno", "rebocs-admin"), root: root)
        XCTAssertTrue(r.output.contains("1 handoff marcado como recebido"))

        r = run(["status"], in: wtAPI, root: root)
        XCTAssertTrue(r.output.contains("rebocs_api"))
        XCTAssertTrue(r.output.contains("↑0 ↓0"))

        r = run(["ls"], in: lab.root, root: root)
        XCTAssertTrue(r.output.contains("● Surcharge noturno"))

        r = run(["decisao", "sem trama"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 1)
        XCTAssertTrue(r.error.contains("não sei de qual trama"))

        r = run(["nova", "x", "--repos", "inexistente"], in: lab.root, root: root)
        XCTAssertTrue(r.error.contains("não está cadastrado"))

        r = run(["estado"], in: lab.root, root: root)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(r.output.utf8)))

        r = run(["comando-que-nao-existe"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 2)

        r = run(["ajuda"], in: lab.root, root: root)
        XCTAssertTrue(r.output.contains("handoff"))
    }

    func testWhenAppBecomesCommand() {
        XCTAssertTrue(CLI.shouldRunAsCLI(["/Users/g/.local/bin/trama"]))
        XCTAssertTrue(CLI.shouldRunAsCLI(["trama", "status"]))
        XCTAssertTrue(CLI.shouldRunAsCLI(["/Applications/Trama.app/Contents/MacOS/Trama", "hook"]))
        XCTAssertTrue(CLI.shouldRunAsCLI(["/Applications/trama.app/Contents/MacOS/trama", "decisao", "x"]))
        XCTAssertFalse(CLI.shouldRunAsCLI(["/Applications/Trama.app/Contents/MacOS/Trama"]), "aberto pelo Finder")
        XCTAssertFalse(CLI.shouldRunAsCLI(["/Applications/trama.app/Contents/MacOS/trama"]), "executável em minúsculas também abre a interface")
        XCTAssertFalse(CLI.shouldRunAsCLI(["/Applications/Trama.app/Contents/MacOS/Trama", "-NSDocumentRevisionsDebugMode", "YES"]), "aberto pelo Xcode")
    }
}

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

final class TransitionTests: XCTestCase {
    private func agent(_ session: String, _ state: String) -> Agent {
        Agent(session: session, trama: "t", repo: "r", cwd: "/x", state: state, message: nil, startedAt: 1, updatedAt: 1)
    }

    func testTransitionsOnlyOnChange() {
        let before = [agent("a", AgentState.working), agent("b", AgentState.waiting), agent("c", AgentState.working)]
        let after = [agent("a", AgentState.waiting), agent("b", AgentState.waiting), agent("c", AgentState.done), agent("d", AgentState.waiting), agent("e", AgentState.done)]
        let result = agentTransitions(from: before, to: after)
        XCTAssertEqual(result.map(\.agent.session), ["a", "c", "d"])
        XCTAssertEqual(result.map(\.alert), [.waiting, .done, .waiting])
    }
}
