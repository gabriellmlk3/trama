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
            try w.setProvider(n, .github)
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
        XCTAssertTrue(calls.contains("pr edit https://github.com/x/rebocs-admin/pull/7 --base develop"))
        XCTAssertFalse(calls.contains("pr edit https://github.com/x/rebocs_api/pull/7 --base"), "quem já aponta para o destino não é redirecionado")
        XCTAssertTrue(try w.readCapsule(t.slug).journal.contains { $0.text.contains("(antes main)") })

        try pullRequestState("rebocs-admin", state: "OPEN", base: "develop")
        _ = try w.openPullRequests(t.slug, targets: ["rebocs-admin": "main"], only: ["rebocs-admin"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("pr edit https://github.com/x/rebocs-admin/pull/7 --base main"))
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

final class ProviderTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func fakeTool(_ name: String, _ script: String) throws -> String {
        let path = lab.root + "/" + name
        try lab.write(path, "#!/bin/sh\n" + script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func host(_ w: Workspace, _ repo: String, as url: String) throws {
        let dir = lab.repos[repo]!
        try w.setProvider(repo, nil)
        try lab.git(dir, "remote", "set-url", "origin", url)
        try lab.git(dir, "config", "url.\(lab.root)/remotos/\(repo).git.insteadOf", url)
    }

    func commitAll(_ w: Workspace, _ t: Trama, _ repos: [String]) throws {
        for name in repos {
            try lab.commit(w.worktreePath(t.slug, name), "feature.txt", "x\n", "feature")
        }
    }

    func testRemoteParsingDetectsTheProvider() throws {
        func detect(_ raw: String) -> ProviderKind? { RemoteRepo.parse(raw)?.detectedKind }
        XCTAssertEqual(detect("git@github.com:acme/api.git"), .github)
        XCTAssertEqual(detect("https://github.com/acme/api"), .github)
        XCTAssertEqual(detect("ssh://git@github.example.com:22/acme/api.git"), .github)
        XCTAssertEqual(detect("https://user:token@gitlab.com/group/sub/proj.git"), .gitlab)
        XCTAssertEqual(detect("git@gitlab.mycompany.com:group/proj.git"), .gitlab)
        XCTAssertEqual(detect("https://bitbucket.org/acme/api.git"), .bitbucket)
        XCTAssertEqual(detect("https://git.mycompany.com/team/api.git"), .manual)
        XCTAssertEqual(detect("https://acme@dev.azure.com/acme/Proj/_git/api"), .azure)
        XCTAssertEqual(detect("git@ssh.dev.azure.com:v3/acme/Proj/api"), .azure)
        XCTAssertEqual(detect("https://acme.visualstudio.com/Proj/_git/api"), .azure)
        XCTAssertEqual(detect("https://tfs.mycompany.com/tfs/Col/Proj/_git/api"), .azure)
        XCTAssertNil(RemoteRepo.parse("/tmp/remotos/api.git"))
        XCTAssertNil(RemoteRepo.parse("../remotos/api.git"))
        XCTAssertNil(RemoteRepo.parse("file:///tmp/remotos/api.git"))
        XCTAssertNil(RemoteRepo.parse(""))

        XCTAssertEqual(RemoteRepo.parse("https://acme@dev.azure.com/acme/My%20Project/_git/api")?.azure,
                       AzureCoordinates(organizationURL: "https://dev.azure.com/acme", project: "My Project", repository: "api"))
        XCTAssertEqual(RemoteRepo.parse("git@ssh.dev.azure.com:v3/acme/Proj/api")?.azure,
                       AzureCoordinates(organizationURL: "https://dev.azure.com/acme", project: "Proj", repository: "api"))
        XCTAssertEqual(RemoteRepo.parse("https://acme.visualstudio.com/DefaultCollection/Proj/_git/api")?.azure,
                       AzureCoordinates(organizationURL: "https://acme.visualstudio.com", project: "Proj", repository: "api"))
        XCTAssertEqual(RemoteRepo.parse("https://dev.azure.com/acme/_git/api")?.azure?.project, "api")
        XCTAssertEqual(RemoteRepo.parse("https://tfs.mycompany.com/tfs/Col/Proj/_git/api")?.azure,
                       AzureCoordinates(organizationURL: "https://tfs.mycompany.com/tfs/Col", project: "Proj", repository: "api"))
        XCTAssertNil(RemoteRepo.parse("https://github.com/acme/api")?.azure)
        XCTAssertEqual(RemoteRepo.parse("https://dev.azure.com/acme/My%20Project/_git/api")?.azure?.webURL,
                       "https://dev.azure.com/acme/My%20Project/_git/api")

        func link(_ raw: String, _ kind: ProviderKind) -> String? {
            RemoteRepo.parse(raw)?.newPullRequestURL(kind: kind, branch: "trama/x", target: "main")
        }
        XCTAssertEqual(link("git@github.com:acme/api.git", .github), "https://github.com/acme/api/compare/main...trama/x?expand=1")
        XCTAssertEqual(link("https://dev.azure.com/acme/Proj/_git/api", .azure),
                       "https://dev.azure.com/acme/Proj/_git/api/pullrequestcreate?sourceRef=trama%2Fx&targetRef=main")
        XCTAssertEqual(link("git@gitlab.com:g/p.git", .gitlab),
                       "https://gitlab.com/g/p/-/merge_requests/new?merge_request%5Bsource_branch%5D=trama%2Fx&merge_request%5Btarget_branch%5D=main")
        XCTAssertEqual(link("https://bitbucket.org/acme/api.git", .bitbucket),
                       "https://bitbucket.org/acme/api/pull-requests/new?source=trama%2Fx&dest=main")
        XCTAssertEqual(link("https://git.mycompany.com/team/api.git", .manual), "https://git.mycompany.com/team/api")

        XCTAssertEqual(ProviderKind.named("Azure-DevOps"), .azure)
        XCTAssertEqual(ProviderKind.named("gh"), .github)
        XCTAssertNil(ProviderKind.named("auto"))
        XCTAssertEqual(AzureProvider.pullRequestId("https://dev.azure.com/acme/Proj/_git/api/pullrequest/42"), 42)
        XCTAssertEqual(GitLabProvider.mergeRequestId("https://gitlab.com/g/p/-/merge_requests/5"), 5)
        XCTAssertEqual(AzureProvider.ciState([]), CIState.none)
        XCTAssertEqual(GitLabProvider.ci(["head_pipeline": ["status": "running"]]), CIState.pending)
        XCTAssertEqual(GitLabProvider.ci([:]), CIState.none)
    }

    func testProviderIsDetectedAndStoredPerRepo() throws {
        let w = try lab.workspace()
        XCTAssertEqual(try w.repo("api").provider, .github)
        try w.setProvider("api", nil)
        XCTAssertEqual(w.providerKind(for: try w.repo("api")), .manual, "um remoto local não diz nada")
        try lab.git(lab.repos["rebocs_api"]!, "remote", "set-url", "origin", "git@gitlab.com:acme/api.git")
        XCTAssertEqual(w.providerKind(for: try w.repo("api")), .gitlab)
        try w.setProvider("api", .azure)
        XCTAssertEqual(w.providerKind(for: try w.repo("api")), .azure, "o ajuste manual vence a detecção")
        XCTAssertEqual(try Workspace.open(root: w.root).repo("api").provider, .azure)
        try w.setProvider("api", nil)
        XCTAssertNil(try Workspace.open(root: w.root).repo("api").provider)
    }

    func testAzurePullRequestsAreOpenedRetargetedAndTracked() throws {
        let w = try lab.workspace()
        let log = lab.root + "/az.log"
        let states = lab.root + "/az-estados"
        try FileManager.default.createDirectory(atPath: states, withIntermediateDirectories: true)
        let fake = try fakeTool("az", """
        echo "$PWD|$*" >> "\(log)"
        repo="$(basename "$PWD")"
        prev=""
        for arg in "$@"; do
          if [ "$prev" = "--in-file" ]; then cat "$arg" >> "\(log)"; echo >> "\(log)"; fi
          prev="$arg"
        done
        case "$1 $2 $3" in
          "repos pr list") cat "\(states)/lista-$repo.json" 2>/dev/null || echo '[]' ;;
          "repos pr show") cat "\(states)/pr-$repo.json" 2>/dev/null || exit 1 ;;
          "repos pr create") echo '{"pullRequestId":42,"status":"active","isDraft":false,"targetRefName":"refs/heads/main","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/'"$repo"'"}}' ;;
          "repos pr update") echo '{}' ;;
          "repos pr policy") cat "\(states)/politicas-$repo.json" 2>/dev/null || echo '[]' ;;
          "devops invoke "*) echo '{}' ;;
        esac
        """)
        setenv("TRAMA_AZ", fake, 1)
        defer { unsetenv("TRAMA_AZ") }
        let names = ["rebocs-admin", "rebocs-android", "rebocs_api"]
        for name in names {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
            try host(w, name, as: "https://acme@dev.azure.com/acme/Proj/_git/\(name)")
        }
        func pullRequest(_ repo: String, status: String, target: String) throws {
            try lab.write("\(states)/pr-\(repo).json", #"{"pullRequestId":42,"status":"\#(status)","isDraft":false,"targetRefName":"refs/heads/\#(target)","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/\#(repo)"}}"#)
        }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Azure", repos: ["api", "admin", "android"], goal: "Entregar no Azure", noFetch: true))
        try commitAll(w, t, names)

        let plan = try w.pullRequestPlan(t.slug)
        XCTAssertEqual(plan.map(\.provider), [.azure, .azure, .azure])
        XCTAssertEqual(plan.map(\.action), [.create, .create, .create])

        let first = try w.openPullRequests(t.slug, draft: true)
        XCTAssertEqual(first.prs.map(\.repo), names)
        XCTAssertTrue(first.manual.isEmpty)
        XCTAssertEqual(try w.trama(t.slug).prs["rebocs_api"], "https://dev.azure.com/acme/Proj/_git/rebocs_api/pullrequest/42")
        var calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("repos pr create --source-branch \(t.branch) --target-branch main --title Azure --description=## Azure"))
        XCTAssertTrue(calls.contains("--draft true"))
        XCTAssertTrue(calls.contains("--organization https://dev.azure.com/acme --detect false --output json --project Proj --repository rebocs_api"))
        XCTAssertTrue(calls.contains("Entregar no Azure"))
        XCTAssertTrue(calls.contains("repos pr update --id 42 --description=## Azure"))
        XCTAssertTrue(calls.contains("### PRs desta trama"))
        XCTAssertTrue(Git.branchExists(lab.root + "/remotos/rebocs_api.git", t.branch))

        for name in names { try pullRequest(name, status: "active", target: "main") }
        let existing = try w.existingPullRequests(t.slug)
        XCTAssertEqual(existing["rebocs-admin"]?.number, 42)
        XCTAssertEqual(existing["rebocs-admin"]?.base, "main")
        XCTAssertEqual(existing["rebocs-admin"]?.state, "open")
        XCTAssertEqual(try w.pullRequestPlan(t.slug, targets: ["rebocs-admin": "develop"], existing: existing).map(\.action), [.retarget, .update, .update])

        _ = try w.openPullRequests(t.slug, targets: ["rebocs-admin": "develop"], only: ["rebocs-admin"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("devops invoke --area git --resource pullRequests --route-parameters project=Proj repositoryId=rebocs-admin pullRequestId=42 --http-method PATCH --in-file"))
        XCTAssertTrue(calls.contains(#"{"targetRefName":"refs/heads/develop"}"#))
        XCTAssertEqual(try w.trama(t.slug).prBases, ["rebocs-admin": "develop"])

        try lab.write("\(states)/politicas-rebocs_api.json", #"[{"status":"approved","configuration":{"type":{"displayName":"Build"}}},{"status":"queued","configuration":{"type":{"displayName":"Minimum number of reviewers"}}}]"#)
        var infos = w.pullRequestInfos(try w.trama(t.slug))
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.number, 42)
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.state, "open")
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.ci, CIState.success, "a política de revisores não conta como CI")
        try lab.write("\(states)/politicas-rebocs_api.json", #"[{"status":"rejected","configuration":{"type":{"displayName":"Build"}}}]"#)
        infos = w.pullRequestInfos(try w.trama(t.slug))
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.ci, CIState.failure)

        try pullRequest("rebocs_api", status: "completed", target: "main")
        let merged = try w.pullRequestPlan(t.slug, existing: try w.existingPullRequests(t.slug))
        XCTAssertEqual(merged.first { $0.repo == "rebocs_api" }?.blocker, .merged)
        XCTAssertThrowsError(try w.openPullRequests(t.slug, only: ["rebocs_api"])) {
            XCTAssertTrue(errorMessage($0).contains("já foi mesclado"))
        }

        try lab.write("\(states)/lista-rebocs-android.json", #"[{"pullRequestId":7,"status":"abandoned","sourceRefName":"refs/heads/\#(t.branch)","targetRefName":"refs/heads/main","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/rebocs-android"}},{"pullRequestId":9,"status":"active","sourceRefName":"refs/heads/\#(t.branch)","targetRefName":"refs/heads/develop","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/rebocs-android"}}]"#)
        let provider = try XCTUnwrap(w.host(for: try w.repo("android"), dir: w.worktreePath(t.slug, "rebocs-android")).provider)
        let byBranch = try XCTUnwrap(provider.existing(w.worktreePath(t.slug, "rebocs-android"), t.branch))
        XCTAssertEqual(byBranch.number, 9, "o PR ativo vence o abandonado")
        XCTAssertEqual(byBranch.base, "develop")
    }

    func testGitLabMergeRequestsAreOpenedAndRetargeted() throws {
        let w = try lab.workspace()
        let log = lab.root + "/glab.log"
        let states = lab.root + "/glab-estados"
        try FileManager.default.createDirectory(atPath: states, withIntermediateDirectories: true)
        let fake = try fakeTool("glab", """
        echo "$PWD|$*" >> "\(log)"
        repo="$(basename "$PWD")"
        case "$1 $2" in
          "mr view") cat "\(states)/$repo.json" 2>/dev/null || exit 1 ;;
          "mr create")
            echo "Creating merge request for x into main in acme/$repo"
            echo
            echo "!5 Titulo (https://gitlab.com/acme/$repo/-/merge_requests/5)" ;;
          "mr update") ;;
        esac
        """)
        setenv("TRAMA_GLAB", fake, 1)
        defer { unsetenv("TRAMA_GLAB") }
        let names = ["rebocs-admin", "rebocs_api"]
        for name in names {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
            try host(w, name, as: "git@gitlab.com:acme/\(name).git")
        }
        func mergeRequest(_ repo: String, state: String, target: String, pipeline: String) throws {
            try lab.write("\(states)/\(repo).json", #"{"iid":5,"web_url":"https://gitlab.com/acme/\#(repo)/-/merge_requests/5","state":"\#(state)","target_branch":"\#(target)","draft":false,"head_pipeline":{"status":"\#(pipeline)"}}"#)
        }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "GitLab", repos: ["api", "admin"], noFetch: true))
        try commitAll(w, t, names)
        XCTAssertEqual(try w.pullRequestPlan(t.slug).map(\.provider), [.gitlab, .gitlab])

        let first = try w.openPullRequests(t.slug, draft: true)
        XCTAssertEqual(first.prs.map(\.repo), names)
        XCTAssertEqual(try w.trama(t.slug).prs["rebocs_api"], "https://gitlab.com/acme/rebocs_api/-/merge_requests/5")
        var calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("mr create --source-branch \(t.branch) --target-branch main --title GitLab --description=## GitLab"))
        XCTAssertTrue(calls.contains("--yes --no-editor --draft"))
        XCTAssertTrue(calls.contains("mr update 5 --description=## GitLab"))

        try mergeRequest("rebocs-admin", state: "opened", target: "main", pipeline: "failed")
        try mergeRequest("rebocs_api", state: "opened", target: "main", pipeline: "success")
        let existing = try w.existingPullRequests(t.slug)
        XCTAssertEqual(existing["rebocs-admin"]?.number, 5)
        XCTAssertEqual(try w.pullRequestPlan(t.slug, existing: existing).map(\.action), [.update, .update])
        XCTAssertEqual(try w.pullRequestPlan(t.slug, targets: ["rebocs-admin": "develop"], existing: existing).map(\.action), [.retarget, .update])

        _ = try w.openPullRequests(t.slug, targets: ["rebocs-admin": "develop"], only: ["rebocs-admin"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("mr update 5 --target-branch develop"))

        let infos = w.pullRequestInfos(try w.trama(t.slug))
        XCTAssertEqual(infos.first { $0.repo == "rebocs-admin" }?.ci, CIState.failure)
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.ci, CIState.success)
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.state, "open")

        try mergeRequest("rebocs_api", state: "merged", target: "main", pipeline: "success")
        let merged = try w.pullRequestPlan(t.slug, existing: try w.existingPullRequests(t.slug))
        XCTAssertEqual(merged.first { $0.repo == "rebocs_api" }?.blocker, .merged)
    }

    func testHostsWithoutAutomationGetALinkAndTheBranchPushed() throws {
        let w = try lab.workspace()
        for name in ["rebocs-admin", "rebocs-android", "rebocs_api"] {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
        }
        try host(w, "rebocs_api", as: "https://bitbucket.org/acme/rebocs_api.git")
        try host(w, "rebocs-admin", as: "https://dev.azure.com/acme/Proj/_git/rebocs-admin")
        try host(w, "rebocs-android", as: "https://git.mycompany.com/team/rebocs-android.git")
        setenv("TRAMA_AZ", lab.root + "/nao-existe/az", 1)
        defer { unsetenv("TRAMA_AZ") }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Manual", repos: ["api", "admin", "android"], noFetch: true))
        try commitAll(w, t, ["rebocs-admin", "rebocs-android", "rebocs_api"])

        let plan = try w.pullRequestPlan(t.slug)
        XCTAssertEqual(plan.map(\.provider), [.azure, .manual, .bitbucket])
        XCTAssertEqual(plan.map(\.action), [.manual, .manual, .manual])
        XCTAssertEqual(plan.map(\.automatic), [false, false, false])
        XCTAssertEqual(plan[0].missingTool, "az")
        XCTAssertTrue(plan[0].summary.contains("sem o az"))
        XCTAssertNil(plan[2].missingTool)

        let result = try w.openPullRequests(t.slug, targets: ["rebocs_api": "develop"])
        XCTAssertTrue(result.prs.isEmpty)
        XCTAssertEqual(result.manual.map(\.repo), ["rebocs-admin", "rebocs-android", "rebocs_api"])
        let branch = queryEncoded(t.branch)
        XCTAssertEqual(result.manual[0].url, "https://dev.azure.com/acme/Proj/_git/rebocs-admin/pullrequestcreate?sourceRef=\(branch)&targetRef=main")
        XCTAssertEqual(result.manual[1].url, "https://git.mycompany.com/team/rebocs-android")
        XCTAssertEqual(result.manual[2].url, "https://bitbucket.org/acme/rebocs_api/pull-requests/new?source=\(branch)&dest=develop")
        XCTAssertTrue(result.warnings.contains { $0.repo == "rebocs-admin" && $0.message.contains("não encontrei o `az`") })
        for name in ["rebocs-admin", "rebocs-android", "rebocs_api"] {
            XCTAssertTrue(Git.branchExists(lab.root + "/remotos/\(name).git", t.branch), name)
        }
        let saved = try w.trama(t.slug)
        XCTAssertEqual(saved.prs, [:])
        XCTAssertEqual(saved.prBases, ["rebocs_api": "develop"])
        XCTAssertTrue(try w.readCapsule(t.slug).journal.contains { $0.text.contains("pelo navegador") })
    }

    func testPullRequestBodyKeepsTheLinksWhenTooLong() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Longa", repos: ["api"], goal: "Objetivo", noFetch: true))
        for i in 1...40 {
            try w.addDecision(t.slug, author: "você", String(repeating: "decisão \(i) ", count: 10))
        }
        let capsule = try w.readCapsule(t.slug)
        let links = [(repo: "a", url: "https://x/1"), (repo: "b", url: "https://x/2")]
        let full = w.pullRequestBody(t, capsule: capsule, links: links, current: "b")
        XCTAssertTrue(full.count > 1000)
        let short = w.pullRequestBody(t, capsule: capsule, links: links, current: "b", limit: 1000)
        XCTAssertTrue(short.count <= 1000)
        XCTAssertTrue(short.contains("2. https://x/2 ← este PR"))
        XCTAssertTrue(short.contains("…"))
        XCTAssertTrue(short.hasPrefix("## Longa"))
    }
}

final class AgentSkillTests: XCTestCase {
    func testInstallRefreshRemove() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let exe = "/Applications/Trama.app/Contents/MacOS/trama"
        XCTAssertFalse(AgentSkill.isInstalled(home: lab.root))
        try AgentSkill.install(executable: exe, home: lab.root)
        XCTAssertTrue(AgentSkill.isInstalled(home: lab.root))
        let text = try XCTUnwrap(try File.read(AgentSkill.path(home: lab.root)))
        XCTAssertTrue(text.hasPrefix("---\nname: trama\n"))
        for command in CLI.commands.keys where ["nova", "ls", "estacionar", "retomar", "arquivar", "pr", "puxar", "handoff"].contains(command) {
            XCTAssertTrue(text.contains("trama \(command)"), command)
        }
        XCTAssertFalse(AgentSkill.refreshIfInstalled(executable: exe, home: lab.root))
        XCTAssertTrue(AgentSkill.refreshIfInstalled(executable: "/Users/x/Trama.app/Contents/MacOS/trama", home: lab.root))
        XCTAssertTrue(try AgentSkill.remove(home: lab.root))
        XCTAssertFalse(Paths.exists(Paths.parent(AgentSkill.path(home: lab.root))))
    }

    func testDoesNotRemoveUserSkill() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.write(AgentSkill.path(home: lab.root), "---\nname: trama\n---\nminha")
        XCTAssertFalse(AgentSkill.isInstalled(home: lab.root))
        XCTAssertFalse(try AgentSkill.remove(home: lab.root))
        XCTAssertTrue(Paths.exists(AgentSkill.path(home: lab.root)))
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

    func testProviderCommandsAndManualPullRequests() throws {
        let lab = try Lab()
        defer {
            lab.cleanup()
            unsetenv("TRAMA_HOME")
        }
        let w = try lab.workspace()
        let root = w.root
        var r = run(["repo", "provedor", "api"], in: lab.root, root: root)
        XCTAssertEqual(r.output, "rebocs_api: GitHub (definido por você)\n")
        r = run(["repo", "provedor", "api", "azure"], in: lab.root, root: root)
        XCTAssertEqual(r.output, "rebocs_api: Azure DevOps (definido por você)\n")
        r = run(["repo", "provedor", "api", "talvez"], in: lab.root, root: root)
        XCTAssertNotEqual(r.code, 0)
        XCTAssertTrue(r.error.contains("provedor desconhecido"))
        XCTAssertEqual(try Workspace.open(root: root).repo("api").provider, .azure, "valor inválido não grava nada")

        let dir = lab.repos["rebocs_api"]!
        try lab.git(dir, "remote", "set-url", "origin", "https://bitbucket.org/acme/rebocs_api.git")
        try lab.git(dir, "config", "url.\(lab.root)/remotos/rebocs_api.git.insteadOf", "https://bitbucket.org/acme/rebocs_api.git")
        r = run(["repo", "provedor", "api", "auto"], in: lab.root, root: root)
        XCTAssertEqual(r.output, "rebocs_api: Bitbucket (detectado pelo remoto)\n")
        r = run(["repo", "ls"], in: lab.root, root: root)
        XCTAssertTrue(r.output.contains("PROVEDOR"))
        XCTAssertTrue(r.output.contains("Bitbucket"))

        r = run(["nova", "Cli manual", "--repos", "api", "--sem-fetch"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        let worktree = w.worktreePath("cli-manual", "rebocs_api")
        try lab.commit(worktree, "feature.txt", "x\n", "feature")

        r = run(["pr", "--simular"], in: worktree, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(r.output.contains("PROVEDOR"))
        XCTAssertTrue(r.output.contains("Bitbucket"))
        XCTAssertTrue(r.output.contains("abrir pelo navegador"))

        r = run(["pr"], in: worktree, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(r.output.contains("abra o PR em main pelo link (Bitbucket): https://bitbucket.org/acme/rebocs_api/pull-requests/new?source=trama%2Fcli-manual&dest=main"))
        XCTAssertTrue(Git.branchExists(lab.root + "/remotos/rebocs_api.git", "trama/cli-manual"))

        r = run(["pr", "--json"], in: worktree, root: root)
        XCTAssertTrue(r.output.contains(#""state" : "manual""#))
    }

    func testRepoSuggestionsAndApprovalPolicy() throws {
        let lab = try Lab()
        defer {
            lab.cleanup()
            unsetenv("TRAMA_HOME")
        }
        let w = try lab.workspace()
        let root = w.root

        var r = run(["nova", "Selo", "--repos", "api,admin", "--sem-fetch"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        let here = w.worktreePath("selo", "rebocs_api")

        r = run(["repo", "descobrir", "--json"], in: lab.root, root: root)
        let found = try JSONDecoder().decode([DiscoveredRepo].self, from: Data(r.output.utf8))
        XCTAssertEqual(found.map(\.name), ["rebocs-context"])

        r = run(["sugerir", "android", "exibir selo no app", "--trama", "selo"], in: here, root: root, agent: true)
        XCTAssertEqual(r.code, 0, r.error)
        r = run(["sugerir", "android", "de novo", "--trama", "selo"], in: here, root: root, agent: true)
        XCTAssertEqual(r.code, 1)
        XCTAssertTrue(r.error.contains("já foi sugerido"))
        r = run(["sugerir", "admin", "já está", "--trama", "selo"], in: here, root: root, agent: true)
        XCTAssertTrue(r.error.contains("já faz parte"))
        r = run(["sugerir", "desconhecido", "x", "--trama", "selo"], in: here, root: root, agent: true)
        XCTAssertTrue(r.error.contains("não conheço"))
        r = run(["sugerir", found[0].path, "contexto compartilhado"], in: here, root: root, agent: true)
        XCTAssertEqual(r.code, 0, r.error)

        var capsule = try w.readCapsule("selo")
        XCTAssertEqual(capsule.openSuggestions.map(\.to), ["rebocs-android", found[0].path])
        XCTAssertEqual(capsule.suggestions[0].author, "agente · api")
        XCTAssertEqual(capsule.suggestions[0].text, "exibir selo no app")

        r = run(["sugestao", "aceitar", "1", "--trama", "selo", "--sem-fetch"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(Paths.isDirectory(w.worktreePath("selo", "rebocs-android")))
        XCTAssertTrue(try w.trama("selo").repos.contains("rebocs-android"))

        r = run(["sugestao", "aceitar", "2", "--trama", "selo", "--sem-fetch"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        let reloaded = try Workspace.open(root: root)
        XCTAssertTrue(reloaded.config.repos.contains { $0.name == "rebocs-context" })
        XCTAssertTrue(try reloaded.trama("selo").repos.contains("rebocs-context"))

        capsule = try reloaded.readCapsule("selo")
        XCTAssertTrue(capsule.openSuggestions.isEmpty)
        XCTAssertTrue(capsule.suggestions.allSatisfy { $0.done && !$0.dismissed })
        r = run(["sugestao", "aceitar", "1", "--trama", "selo"], in: lab.root, root: root)
        XCTAssertTrue(r.error.contains("não há sugestão aberta"))
    }

    func testDismissedSuggestionStaysOutOfTheTrama() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let t = try w.newTrama(NewTramaOptions(title: "Selo", repos: ["api"], noFetch: true)).trama
        let item = try w.suggestRepo(t.slug, target: "android", author: "agente", reason: "selo")
        try w.dismissSuggestion(t.slug, number: item.index)
        let capsule = try w.readCapsule(t.slug)
        XCTAssertTrue(capsule.suggestions[0].dismissed)
        XCTAssertTrue(capsule.openSuggestions.isEmpty)
        XCTAssertEqual(try w.trama(t.slug).repos, ["rebocs_api"])
        XCTAssertThrowsError(try w.acceptSuggestion(t.slug, number: item.index))
    }

    func testApprovalPolicyTurnsAgentPullsIntoSuggestions() throws {
        let lab = try Lab()
        defer {
            lab.cleanup()
            unsetenv("TRAMA_HOME")
        }
        let w = try lab.workspace()
        let root = w.root
        var r = run(["nova", "Selo", "--repos", "api", "--sem-fetch"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        let here = w.worktreePath("selo", "rebocs_api")

        r = run(["repo", "puxada"], in: lab.root, root: root)
        XCTAssertTrue(r.output.hasPrefix("livre"))
        r = run(["repo", "puxada", "aprovacao"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertEqual(try Workspace.open(root: root).config.agentPullPolicy, .approval)

        r = run(["puxar", "selo", "admin", "--motivo", "contrato novo"], in: here, root: root, agent: true)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(r.output.contains("espera o aceite"))
        XCTAssertEqual(try w.trama("selo").repos, ["rebocs_api"])
        XCTAssertEqual(try w.readCapsule("selo").openSuggestions.first?.text, "contrato novo")

        r = run(["repo", "add", lab.root + "/github/rebocs-context"], in: here, root: root, agent: true)
        XCTAssertEqual(r.code, 1)
        XCTAssertTrue(r.error.contains("exige aprovação"))

        r = run(["puxar", "selo", "android", "--sem-fetch"], in: lab.root, root: root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(try w.trama("selo").repos.contains("rebocs-android"))

        r = run(["repo", "puxada", "livre"], in: lab.root, root: root)
        r = run(["puxar", "selo", "admin", "--sem-fetch"], in: here, root: root, agent: true)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertTrue(try w.trama("selo").repos.contains("rebocs-admin"))
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

final class GitAuthenticationTests: XCTestCase {
    func testAuthenticationFailuresPointToGitAccounts() {
        let messages = [
            "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
            "remote: Invalid username or token. Password authentication is not supported",
            "remote: HTTP Basic: Access denied",
            "git@gitlab.com: Permission denied (publickey)."
        ]
        for stderr in messages {
            let error = GitError(args: ["push"], code: 128, stderr: stderr)
            XCTAssertTrue(error.isAuthenticationFailure, stderr)
            XCTAssertTrue(error.description.contains("Contas Git"), stderr)
        }
    }

    func testOtherFailuresKeepTheGitMessage() {
        let error = GitError(args: ["push"], code: 1, stderr: "! [rejected] main -> main (non-fast-forward)")
        XCTAssertFalse(error.isAuthenticationFailure)
        XCTAssertTrue(error.description.hasPrefix("git push:"))
    }

    func testCredentialEnvironmentsCoverEveryProvider() {
        for kind in ProviderKind.withCredentials {
            XCTAssertFalse(kind.defaultHost.isEmpty)
            XCTAssertNotNil(kind.tokenPage(host: kind.defaultHost, organization: "acme"))
        }
    }

    func testInstallerCoversEveryProviderCLI() {
        for kind in ProviderKind.withCredentials {
            guard let cli = kind.cliName else { continue }
            let tool = ToolInstaller.named(cli)
            XCTAssertNotNil(tool, cli)
            XCTAssertTrue(tool?.installCommand.contains("brew install") == true, cli)
            XCTAssertTrue(kind.loginCommand(host: kind.defaultHost)?.contains(tool?.ensureCommand ?? "?") == true, cli)
        }
        XCTAssertEqual(ToolInstaller.named("GitHub")?.id, "gh")
        XCTAssertNil(ToolInstaller.named("foo"))
    }

    func testClaudeSessionHistoryIsDetectedPerWorktree() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let worktree = lab.root + "/trama/app"
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        XCTAssertFalse(ClaudeSessions.hasHistory(at: worktree, home: lab.root))
        let dir = ClaudeSessions.projectDirectory(for: worktree, home: lab.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        XCTAssertFalse(ClaudeSessions.hasHistory(at: worktree, home: lab.root))
        try lab.write(dir + "/abc.jsonl", "{}\n")
        XCTAssertTrue(ClaudeSessions.hasHistory(at: worktree, home: lab.root))
        XCTAssertFalse(ClaudeSessions.hasHistory(at: lab.root + "/trama/outro", home: lab.root))
    }

    func testClaudeConversationsAreListedNewestFirstWithTitles() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let worktree = lab.root + "/trama/app"
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        let dir = ClaudeSessions.projectDirectory(for: worktree, home: lab.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try lab.write(dir + "/velha.jsonl", "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"primeira pergunta\\nsegunda linha\"}}\n")
        try lab.write(dir + "/nova.jsonl", "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>x</command-name>\"}}\n{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"ignorada\"}}\n{\"type\":\"custom-title\",\"customTitle\":\"Título dado\"}\n")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: dir + "/velha.jsonl")
        let list = ClaudeSessions.conversations(at: worktree, home: lab.root)
        XCTAssertEqual(list.map(\.id), ["nova", "velha"])
        XCTAssertEqual(list.map(\.title), ["Título dado", "primeira pergunta"])
    }
}

final class PTYTests: XCTestCase {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: [UInt8] = []

        func add(_ chunk: [UInt8]) {
            lock.lock()
            bytes.append(contentsOf: chunk)
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    func testDeliversOutputAndExitCodeInOrder() throws {
        let collector = Collector()
        let exited = expectation(description: "saiu")
        nonisolated(unsafe) var code: Int32?
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh", "-c", "printf trama-ok; exit 3"],
            directory: NSTemporaryDirectory(),
            columns: 80,
            rows: 24,
            onOutput: collector.add,
            onExit: { value in
                code = value
                exited.fulfill()
            }
        )
        wait(for: [exited], timeout: 5)
        XCTAssertEqual(code, 3)
        XCTAssertTrue(collector.text.contains("trama-ok"))
        XCTAssertGreaterThan(pty.pid, 0)
    }

    func testStartsInDirectoryAndEchoesInput() throws {
        let collector = Collector()
        let exited = expectation(description: "saiu")
        let directory = Paths.real(NSTemporaryDirectory())
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh"],
            directory: directory,
            columns: 80,
            rows: 24,
            onOutput: collector.add,
            onExit: { _ in exited.fulfill() }
        )
        pty.write(Array("pwd; stty size; exit\n".utf8))
        wait(for: [exited], timeout: 5)
        XCTAssertTrue(collector.text.contains(directory.hasSuffix("/") ? String(directory.dropLast()) : directory))
        XCTAssertTrue(collector.text.contains("24 80"))
    }

    func testResizeReachesChild() throws {
        let collector = Collector()
        let exited = expectation(description: "saiu")
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh"],
            directory: nil,
            columns: 80,
            rows: 24,
            onOutput: collector.add,
            onExit: { _ in exited.fulfill() }
        )
        pty.resize(columns: 120, rows: 40)
        pty.write(Array("stty size; exit\n".utf8))
        wait(for: [exited], timeout: 5)
        XCTAssertTrue(collector.text.contains("40 120"))
    }

    func testTerminateEndsTheProcess() throws {
        let exited = expectation(description: "saiu")
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh", "-c", "sleep 30"],
            directory: nil,
            columns: 80,
            rows: 24,
            onOutput: { _ in },
            onExit: { _ in exited.fulfill() }
        )
        pty.terminate()
        wait(for: [exited], timeout: 5)
    }
}

final class TerminalMarkersTests: XCTestCase {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    func testParsesMarkersWithBellAndStringTerminators() {
        let scanner = MarkerScanner()
        let markers = scanner.feed(bytes("\u{1b}]133;A\u{07}ls\u{1b}]133;C\u{1b}\\\u{1b}]133;D;2\u{07}\u{1b}]133;D\u{07}"))
        XCTAssertEqual(markers, [.promptStart, .commandStart, .commandFinished(exitCode: 2), .commandFinished(exitCode: nil)])
    }

    func testMarkersSplitAcrossChunksAreJoined() {
        let scanner = MarkerScanner()
        var markers = scanner.feed(bytes("texto\u{1b}]13"))
        markers += scanner.feed(bytes("3;D;1"))
        markers += scanner.feed(bytes("27\u{07}"))
        XCTAssertEqual(markers, [.commandFinished(exitCode: 127)])
    }

    func testDirectoryIsDecodedAndHostDropped() {
        let scanner = MarkerScanner()
        XCTAssertEqual(scanner.feed(bytes("\u{1b}]7;file://maquina/Users/main/Meu%20Projeto\u{07}")), [.directory("/Users/main/Meu Projeto")])
    }

    func testCommandTextIsUnescaped() {
        let scanner = MarkerScanner()
        let markers = scanner.feed(bytes("\u{1b}]633;E;echo a\\x3b b\\x0aecho \\\\ç\u{07}"))
        XCTAssertEqual(markers, [.commandText("echo a; b\necho \\ç")])
    }

    func testUnknownAndOversizedSequencesAreIgnored() {
        let scanner = MarkerScanner()
        let huge = String(repeating: "x", count: 20000)
        XCTAssertEqual(scanner.feed(bytes("\u{1b}]0;titulo\u{07}\u{1b}]133;\(huge)\u{07}\u{1b}[31m\u{1b}]133;A\u{07}")), [.promptStart])
    }

    func testBlockLifecycleKeepsCommandDirectoryAndDuration() {
        var tracker = BlockTracker()
        let start = Date(timeIntervalSince1970: 1000)
        tracker.apply(.directory("/tmp/a"), at: start)
        tracker.apply(.commandFinished(exitCode: 0), at: start)
        XCTAssertTrue(tracker.blocks.isEmpty)
        tracker.apply(.commandText("make test"), at: start)
        tracker.apply(.commandStart, at: start)
        XCTAssertEqual(tracker.blocks.first?.isRunning, true)
        tracker.apply(.commandFinished(exitCode: 2), at: start.addingTimeInterval(3.5))
        XCTAssertEqual(tracker.blocks.count, 1)
        XCTAssertEqual(tracker.blocks[0].command, "make test")
        XCTAssertEqual(tracker.blocks[0].directory, "/tmp/a")
        XCTAssertEqual(tracker.blocks[0].exitCode, 2)
        XCTAssertEqual(tracker.blocks[0].duration, 3.5)
    }
}

final class StreamRouterTests: XCTestCase {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    func testBeforeTheFirstPromptEverythingIsOutput() {
        let router = StreamRouter()
        XCTAssertEqual(router.feed(bytes("carregando\r\n")), [.output(bytes("carregando\r\n"))])
    }

    func testOnlyBytesBetweenCommandStartAndEndAreOutput() {
        let router = StreamRouter()
        _ = router.feed(bytes("\u{1b}]133;A\u{07}% \u{1b}]133;B\u{07}"))
        let events = router.feed(bytes("ls\r\n\u{1b}]633;E;ls\u{07}\u{1b}]133;C\u{07}a.txt\r\n\u{1b}[31mb\u{1b}[0m\r\n\u{1b}]133;D;0\u{07}\u{1b}]7;file://h/tmp\u{07}\u{1b}]133;A\u{07}% "))
        XCTAssertEqual(events, [
            .metadata(.commandText("ls")),
            .commandBegan,
            .metadata(.commandStart),
            .output(bytes("a.txt\r\n\u{1b}[31mb\u{1b}[0m\r\n")),
            .commandEnded(exitCode: 0),
            .metadata(.commandFinished(exitCode: 0)),
            .metadata(.directory("/tmp")),
            .metadata(.promptStart),
        ])
    }

    func testFirstPromptSignalsReadyOnlyOnce() {
        let router = StreamRouter()
        let first = router.feed(bytes("boas-vindas\u{1b}]133;A\u{07}"))
        XCTAssertEqual(first, [.output(bytes("boas-vindas")), .sessionReady, .metadata(.promptStart)])
        XCTAssertEqual(router.feed(bytes("\u{1b}]133;A\u{07}")), [.metadata(.promptStart)])
    }

    func testOtherEscapeSequencesAndSplitChunksPassThroughIntact() {
        let router = StreamRouter()
        _ = router.feed(bytes("\u{1b}]133;A\u{07}\u{1b}]133;C\u{07}"))
        var output: [UInt8] = []
        for chunk in ["x\u{1b}", "[2Ky\u{1b}]0;tit", "ulo\u{07}z\u{1b}]13", "3;D;1\u{07}"] {
            for case .output(let part) in router.feed(bytes(chunk)) { output += part }
        }
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "x\u{1b}[2Ky\u{1b}]0;titulo\u{07}z")
    }
}

final class ZshIntegrationTests: XCTestCase {
    func testRealZshProducesBlocksWithCommandStatusDirectoryAndDuration() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        let work = lab.root + "/trabalho com espaço"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\nexport TRAMA_TESTE_RC=carregado\n")
        let integration = lab.root + "/zsh"
        try ShellIntegration.install(at: integration)

        let scanner = MarkerScanner()
        let lock = NSLock()
        nonisolated(unsafe) var events: [(TerminalMarker, Date)] = []
        nonisolated(unsafe) var output = ""
        let exited = expectation(description: "saiu")
        let environment = ["TERM=xterm-256color", "HOME=" + home, "USER=teste", "LANG=en_US.UTF-8"]
            + ShellIntegration.environment(directory: integration, home: home)
        let pty = try PTY(
            executable: "/bin/zsh",
            arguments: ["-il"],
            environment: environment,
            directory: work,
            columns: 100,
            rows: 30,
            onOutput: { chunk in
                let markers = scanner.feed(chunk)
                lock.lock()
                output += String(decoding: chunk, as: UTF8.self)
                events += markers.map { ($0, Date()) }
                lock.unlock()
            },
            onExit: { _ in exited.fulfill() }
        )
        pty.write(Array("echo $TRAMA_TESTE_RC\nls /nao/existe\nsleep 0.3\nfor i in 1 2; do\necho $i\ndone\ncd /tmp\nexit\n".utf8))
        wait(for: [exited], timeout: 15)

        var tracker = BlockTracker()
        lock.lock()
        for (marker, date) in events { tracker.apply(marker, at: date) }
        let seenOutput = output
        lock.unlock()

        XCTAssertTrue(seenOutput.contains("carregado"), "o .zshrc do usuário precisa ser carregado")
        XCTAssertEqual(tracker.blocks.map(\.command), ["echo $TRAMA_TESTE_RC", "ls /nao/existe", "sleep 0.3", "for i in 1 2; do\necho $i\ndone", "cd /tmp", "exit"])
        XCTAssertEqual(tracker.blocks.map(\.exitCode).prefix(5), [0, 1, 0, 0, 0])
        XCTAssertEqual(tracker.blocks[0].directory, Paths.real(work))
        XCTAssertEqual(tracker.blocks[4].directory, Paths.real(work))
        XCTAssertGreaterThanOrEqual(tracker.blocks[2].duration ?? 0, 0.25)
        XCTAssertEqual(tracker.directory.map { Paths.real($0) }, Paths.real("/tmp"))
    }
}

@MainActor
final class TerminalEngineTests: XCTestCase {
    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 15, _ message: String = "") async {
        let limit = Date().addingTimeInterval(timeout)
        while !condition(), Date() < limit {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "tempo esgotado: \(message)")
    }

    func testEngineSplitsSessionIntoBlocksWithCapturedOutput() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\necho bem-vindo\n")
        let engine = SwiftTermEngine(homeDirectory: home)
        engine.start(directory: home, command: nil)
        defer { engine.terminate() }

        XCTAssertEqual(engine.mode, .starting)
        await waitUntil(engine.mode == .ready, "primeiro prompt")
        XCTAssertTrue(engine.startupOutput.plain.contains("bem-vindo"))

        let longLine = String(repeating: "x", count: 130)
        engine.submit("printf 'ola\\n\\033[31mvermelho\\033[0m\\n'; echo \(longLine)")
        await waitUntil(engine.blocks.count == 1 && engine.blocks[0].exitCode != nil, "primeiro bloco")
        XCTAssertEqual(engine.mode, .ready)
        let first = try XCTUnwrap(engine.output(for: engine.blocks[0].id))
        XCTAssertEqual(first.plain, "ola\nvermelho\n" + longLine)
        XCTAssertFalse(first.plain.contains("%"), "o prompt não pode vazar para a saída")

        engine.submit("sleep 0.6; echo depois")
        await waitUntil(engine.mode == .running, "modo executando")
        XCTAssertEqual(engine.blocks.count, 2)
        XCTAssertTrue(engine.blocks[1].isRunning)
        await waitUntil(engine.mode == .ready && engine.blocks[1].exitCode != nil, "segundo bloco")
        XCTAssertEqual(engine.output(for: engine.blocks[1].id)?.plain, "depois")

        engine.submit("false")
        await waitUntil(engine.blocks.count == 3 && engine.blocks[2].exitCode != nil, "terceiro bloco")
        XCTAssertEqual(engine.blocks[2].exitCode, 1)
        XCTAssertEqual(engine.output(for: engine.blocks[2].id)?.isEmpty, true)
        XCTAssertEqual(engine.blocks.map(\.command), [
            "printf 'ola\\n\\033[31mvermelho\\033[0m\\n'; echo \(longLine)",
            "sleep 0.6; echo depois",
            "false",
        ])
    }

    func testMultilineCommandIsSubmittedAsOneBlock() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\n")
        let engine = SwiftTermEngine(homeDirectory: home)
        engine.start(directory: home, command: nil)
        defer { engine.terminate() }
        await waitUntil(engine.mode == .ready, "primeiro prompt")
        engine.submit("for i in 1 2 3\ndo\necho item$i\ndone")
        await waitUntil(engine.blocks.count == 1 && engine.blocks[0].exitCode != nil, "bloco multilinha")
        XCTAssertEqual(engine.output(for: engine.blocks[0].id)?.plain, "item1\nitem2\nitem3")
    }

    func testExitingTheShellClosesTheRunningBlockAndReportsExit() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\n")
        let engine = SwiftTermEngine(homeDirectory: home)
        nonisolated(unsafe) var exitCode: Int32??
        engine.onExit = { exitCode = .some($0) }
        engine.start(directory: home, command: nil)
        await waitUntil(engine.mode == .ready, "primeiro prompt")
        engine.submit("exit 4")
        await waitUntil(exitCode != nil, "saída do shell")
        XCTAssertEqual(exitCode, .some(4))
        XCTAssertEqual(engine.blocks.last?.isRunning, false)
        XCTAssertEqual(engine.mode, .ready)
    }

    func testWithoutShellIntegrationTheSessionStaysClassic() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\n")
        let engine = SwiftTermEngine(homeDirectory: home, shellIntegration: false)
        engine.start(directory: home, command: nil)
        defer { engine.terminate() }
        engine.submit("echo classico")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(engine.mode, .starting)
        XCTAssertTrue(engine.blocks.isEmpty)
    }
}
