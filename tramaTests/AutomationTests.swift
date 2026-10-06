import Foundation
import XCTest
@testable import trama

final class AutomationTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        unsetenv("TRAMA_HOME")
        lab.cleanup()
    }

    func waitAutomations(_ w: Workspace, _ slug: String) {
        let deadline = Date().addingTimeInterval(20)
        while w.automationState(slug) == AutomationRunState.running, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    func read(_ path: String) throws -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func fakeTrama(_ slug: String, _ repos: [String]) -> Trama {
        Trama(slug: slug, title: slug, branch: "trama/" + slug, base: nil, repos: repos, state: TramaState.active, task: nil, createdAt: 0)
    }

    func testPathsInAnyFormatFollowTheTrama() {
        let repos = ["api", "admin"].map { RepoConfig(name: $0, alias: $0, path: "/x/github/" + $0) }
        let rewriter = PathRewriter(root: "/x/Tramas", repos: repos) { "/x/Tramas/\($0)/\($1)" }
        let original = """
        dependency_overrides:
          api:
            path: ../api
        API_DIR=../api/src
        "api": "file:../api",
        includeBuild('../api')
        use ../api/
        remote: https://dev.azure.com/org/_git/api
        own: ../admin/lib
        other: ../desconhecido ../apix

        """
        let main = "/x/github/admin"
        let focused = rewriter.rewrite(original, fileDir: main, repoDir: main, own: "admin", trama: fakeTrama("t", ["api"]))
        XCTAssertEqual(focused, """
        dependency_overrides:
          api:
            path: /x/Tramas/t/api
        API_DIR=/x/Tramas/t/api/src
        "api": "file:/x/Tramas/t/api",
        includeBuild('/x/Tramas/t/api')
        use /x/Tramas/t/api/
        remote: https://dev.azure.com/org/_git/api
        own: ../admin/lib
        other: ../desconhecido ../apix

        """)
        XCTAssertEqual(rewriter.rewrite(focused, fileDir: main, repoDir: main, own: "admin", trama: nil), original)
        XCTAssertEqual(rewriter.rewrite(original, fileDir: main, repoDir: main, own: "admin", trama: fakeTrama("t", ["admin"])), original,
                       "um repositório fora da trama continua na cópia principal")

        let nested = main + "/android"
        let gradle = "includeBuild(\"../../api\")\r\nrootProject.name = 'admin'\r\n"
        let inTrama = rewriter.rewrite(gradle, fileDir: nested, repoDir: main, own: "admin", trama: fakeTrama("t", ["api"]))
        XCTAssertEqual(inTrama, "includeBuild(\"/x/Tramas/t/api\")\r\nrootProject.name = 'admin'\r\n")
        XCTAssertEqual(rewriter.rewrite(inTrama, fileDir: nested, repoDir: main, own: "admin", trama: nil), gradle)

        let worktree = "/x/Tramas/t/admin"
        let copied = "a: ../api\nb: /x/github/api/lib\nc: /x/Tramas/antiga/api\n"
        XCTAssertEqual(rewriter.rewrite(copied, fileDir: worktree, repoDir: worktree, own: "admin", trama: fakeTrama("t", ["api", "admin"])),
                       "a: ../api\nb: ../api/lib\nc: ../api\n")
        XCTAssertEqual(rewriter.rewrite(copied, fileDir: worktree, repoDir: worktree, own: "admin", trama: fakeTrama("t", ["admin"])),
                       "a: /x/github/api\nb: /x/github/api/lib\nc: /x/github/api\n")
    }

    func testWorktreeRuleAcrossTheTramaLifecycle() throws {
        let w = try lab.workspace()
        let main = lab.repos["rebocs_api"]!
        let original = "ADMIN=../rebocs-admin\nANDROID=../rebocs-android/build\nSELF=./src\n"
        try lab.write(main + "/local.env", original)
        try w.setRecipe("api", copy: ["local.env"], run: [])
        try w.saveAutomation(Automation(name: "", kind: .paths, scope: .worktrees, files: ["local.env"]))
        XCTAssertEqual(w.config.automations.first?.name, "Caminhos em local.env")

        let (t, warnings) = try w.newTrama(NewTramaOptions(title: "Caminhos", repos: ["api", "admin"], noFetch: true))
        XCTAssertTrue(warnings.isEmpty, "\(warnings)")
        let wt = w.worktreePath(t.slug, "rebocs_api")
        let android = lab.repos["rebocs-android"]!
        let admin = lab.repos["rebocs-admin"]!
        XCTAssertEqual(try read(wt + "/local.env"), "ADMIN=../rebocs-admin\nANDROID=\(android)/build\nSELF=./src\n",
                       "o preparo copia antes, e o que não está na trama aponta para a cópia principal")
        XCTAssertEqual(try Git.statusLines(wt), [], "o arquivo ajustado não suja o worktree")

        _ = try w.pullRepos(t.slug, ["android"], noFetch: true)
        XCTAssertEqual(try read(wt + "/local.env"), "ADMIN=../rebocs-admin\nANDROID=../rebocs-android/build\nSELF=./src\n")
        _ = try w.dropRepo(t.slug, "admin")
        XCTAssertEqual(try read(wt + "/local.env"), "ADMIN=\(admin)\nANDROID=../rebocs-android/build\nSELF=./src\n")
        XCTAssertEqual(try read(main + "/local.env"), original, "a cópia principal não muda")
    }

    func testFocusRuleFollowsTheFocusedTrama() throws {
        let w = try lab.workspace()
        let main = lab.repos["rebocs-admin"]!
        let original = "deps:\n  api:\n    path: ../rebocs_api\n  android:\n    path: '../rebocs-android'\n  html: 0.15.5+1\nremoto: https://example.com/acme/rebocs_api\n"
        try lab.write(main + "/deps.yaml", original)
        try w.saveAutomation(Automation(name: "deps", kind: .paths, scope: .primaries, repos: ["admin"], files: ["deps.yaml"]))
        XCTAssertEqual(try read(main + "/deps.yaml"), original)

        let (a, _) = try w.newTrama(NewTramaOptions(title: "Foco A", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Foco B", repos: ["api"], noFetch: true))
        XCTAssertEqual(try read(main + "/deps.yaml"), original, "criar não mexe na cópia principal")

        _ = try w.focus(a.slug)
        let apiA = w.worktreePath(a.slug, "rebocs_api")
        XCTAssertEqual(try read(main + "/deps.yaml"), original.replacingOccurrences(of: "path: ../rebocs_api", with: "path: \(apiA)"))
        XCTAssertFalse(try Git.statusLines(main).contains { $0.contains("deps.yaml") })

        _ = try w.focus(b.slug)
        let apiB = w.worktreePath(b.slug, "rebocs_api")
        XCTAssertEqual(try read(main + "/deps.yaml"), original.replacingOccurrences(of: "path: ../rebocs_api", with: "path: \(apiB)"))

        _ = try w.pullRepos(b.slug, ["android"], noFetch: true)
        XCTAssertTrue(try read(main + "/deps.yaml")?.contains("path: '\(w.worktreePath(b.slug, "rebocs-android"))'") == true,
                      "incluir na trama em foco já atualiza a cópia principal")
        _ = try w.dropRepo(b.slug, "android")
        XCTAssertTrue(try read(main + "/deps.yaml")?.contains("path: '../rebocs-android'") == true)

        _ = try w.clearFocus()
        XCTAssertNil(w.focusedSlug())
        XCTAssertEqual(try read(main + "/deps.yaml"), original)

        _ = try w.focus(a.slug)
        _ = try w.archive(a.slug)
        XCTAssertNil(w.focusedSlug(), "arquivar a trama em foco tira o foco")
        XCTAssertEqual(try read(main + "/deps.yaml"), original)
    }

    func testSavingDisablingAndRemovingRulesKeepFilesConsistent() throws {
        let w = try lab.workspace()
        let main = lab.repos["rebocs-admin"]!
        try lab.write(main + "/.env", "API=\(w.root)/trama-antiga/rebocs_api/dist\n")
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Regra", repos: ["api"], noFetch: true))
        _ = try w.focus(t.slug)
        XCTAssertEqual(try read(main + "/.env"), "API=\(w.root)/trama-antiga/rebocs_api/dist\n", "sem regra, nada muda")

        let rule = try w.saveAutomation(Automation(name: "env", kind: .paths, scope: .primaries, repos: ["admin"], files: [".env"])).automation
        let focused = "API=\(w.worktreePath(t.slug, "rebocs_api"))/dist\n"
        XCTAssertEqual(try read(main + "/.env"), focused, "salvar a regra já aplica na trama em foco")

        try w.setAutomationEnabled(rule.id, false)
        XCTAssertEqual(try read(main + "/.env"), "API=../rebocs_api/dist\n", "desligar devolve para a cópia principal")
        try w.setAutomationEnabled(rule.id, true)
        XCTAssertEqual(try read(main + "/.env"), focused)
        try w.removeAutomation(rule.id)
        XCTAssertEqual(try read(main + "/.env"), "API=../rebocs_api/dist\n")
    }

    func testTrackedFilesAreLeftAlone() throws {
        let w = try lab.workspace()
        let main = lab.repos["rebocs-admin"]!
        try lab.commit(main, "settings.gradle", "includeBuild('../rebocs_api')\n", "versionado")
        try w.saveAutomation(Automation(name: "gradle", kind: .paths, scope: .primaries, repos: ["admin"], files: ["settings.gradle"]))
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Versionado", repos: ["api"], noFetch: true))
        let warnings = try w.focus(t.slug).warnings
        XCTAssertTrue(warnings.contains { $0.repo == "rebocs-admin" && $0.message.contains("versionado") }, "\(warnings)")
        XCTAssertEqual(try read(main + "/settings.gradle"), "includeBuild('../rebocs_api')\n")
        XCTAssertEqual(try Git.statusLines(main), [])
    }

    func testInvalidRulesAreRefused() throws {
        let w = try lab.workspace()
        XCTAssertThrowsError(try w.saveAutomation(Automation(name: "x", kind: .paths, scope: .worktrees)))
        XCTAssertThrowsError(try w.saveAutomation(Automation(name: "x", kind: .paths, scope: .worktrees, files: ["../fora.env"])))
        XCTAssertThrowsError(try w.saveAutomation(Automation(name: "x", kind: .paths, scope: .trama, files: [".env"])))
        XCTAssertThrowsError(try w.saveAutomation(Automation(name: "x", kind: .paths, scope: .primaries, files: [".env"])))
        XCTAssertThrowsError(try w.saveAutomation(Automation(name: "sem repo", events: [.focus], scope: .primaries, command: "true")))
        XCTAssertThrowsError(try w.saveAutomation(Automation(name: "sem evento", events: [], scope: .trama, command: "true")))
        let saved = try w.saveAutomation(Automation(name: "", kind: .paths, events: [.park], scope: .worktrees, command: "rm -rf x", files: ["a.env, config/*.env"])).automation
        XCTAssertEqual(saved.files, ["a.env", "config/*.env"])
        XCTAssertEqual(saved.events, [], "caminhos não têm evento")
        XCTAssertEqual(saved.command, "")
    }

    func testEveryTemplateIsAValidAutomation() throws {
        let w = try lab.workspace()
        XCTAssertEqual(Set(AutomationTemplate.all.map(\.id)).count, AutomationTemplate.all.count)
        for template in AutomationTemplate.all {
            var a = template.instantiate()
            XCTAssertNotEqual(a.id, template.automation.id)
            if a.scope == .primaries { a.repos = ["admin"] }
            XCTAssertNoThrow(try w.saveAutomation(a), template.id)
        }
        XCTAssertEqual(try AutomationTemplate.find("2").id, AutomationTemplate.all[1].id)
        XCTAssertThrowsError(try AutomationTemplate.find("nenhum"))
    }

    func testCommandAutomationsRunWithTramaVariables() throws {
        let w = try lab.workspace()
        let out = lab.root + "/saida"
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try w.saveAutomation(Automation(name: "worktree", events: [.focus], scope: .worktrees,
                                        command: "echo \"$TRAMA_EVENTO $TRAMA_SLUG $TRAMA_REPO $PWD\" >> \(out)/worktrees.txt"))
        try w.saveAutomation(Automation(name: "principal", events: [.focus, .unfocus], scope: .primaries, repos: ["admin"],
                                        command: "echo \"$TRAMA_EVENTO $TRAMA_SLUG $TRAMA_CAMINHO_REBOCS_API $TRAMA_CAMINHO_REBOCS_ADMIN $PWD\" >> \(out)/principal.txt"))
        try w.saveAutomation(Automation(name: "estacionar", events: [.park], scope: .primaries, repos: ["admin"],
                                        command: "echo x >> \(out)/park.txt"))
        XCTAssertEqual(try w.automation("2").name, "principal")
        XCTAssertEqual(try w.automation("worktree").repos, [])

        let (a, _) = try w.newTrama(NewTramaOptions(title: "Auto A", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Auto B", repos: ["api"], noFetch: true))
        let adminMain = lab.repos["rebocs-admin"]!
        _ = try w.focus(a.slug)
        waitAutomations(w, a.slug)
        let firstLog = try File.read(w.automationLogPath(a.slug)) ?? ""
        XCTAssertEqual(w.automationState(a.slug), AutomationRunState.done, firstLog)
        let apiA = w.worktreePath(a.slug, "rebocs_api")
        XCTAssertEqual(try File.read(out + "/worktrees.txt"), "focar auto-a rebocs_api \(apiA)\n")
        XCTAssertEqual(try File.read(out + "/principal.txt"), "focar auto-a \(apiA) \(adminMain) \(adminMain)\n")

        _ = try w.focus(b.slug)
        waitAutomations(w, b.slug)
        let apiB = w.worktreePath(b.slug, "rebocs_api")
        XCTAssertEqual(try File.read(out + "/principal.txt"),
                       "focar auto-a \(apiA) \(adminMain) \(adminMain)\n"
                       + "desfocar auto-a \(apiA) \(adminMain) \(adminMain)\n"
                       + "focar auto-b \(apiB) \(adminMain) \(adminMain)\n")
        let live = try w.fullState().tramas.first { $0.slug == b.slug }
        XCTAssertEqual(live?.automation, AutomationRunState.done)
        XCTAssertEqual(live?.automationLog, w.automationLogPath(b.slug))

        _ = try w.park(a.slug)
        XCTAssertFalse(Paths.exists(out + "/park.txt"), "na cópia principal, só a trama em foco dispara")
        XCTAssertThrowsError(try w.runAutomation("estacionar", trama: a.slug))
        _ = try w.runAutomation("estacionar", trama: b.slug)
        waitAutomations(w, b.slug)
        XCTAssertEqual(try File.read(out + "/park.txt"), "x\n")
    }

    func testFailingAutomationIsReported() throws {
        let w = try lab.workspace()
        try w.saveAutomation(Automation(name: "quebra", events: [.create], scope: .trama, command: "echo antes; exit 4"))
        try w.saveAutomation(Automation(name: "segue", events: [.create], scope: .trama, command: "echo depois"))
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Falha", repos: ["api"], noFetch: true))
        waitAutomations(w, t.slug)
        XCTAssertEqual(w.automationState(t.slug), AutomationRunState.failed)
        let log = try File.read(w.automationLogPath(t.slug)) ?? ""
        XCTAssertTrue(log.contains("antes"))
        XCTAssertTrue(log.contains("código 4"))
        XCTAssertTrue(log.contains("depois"), "um passo que falha não impede os seguintes")
    }

    func testAutomationsSurviveUnknownValuesInConfig() throws {
        let json = """
        {"versao": 1, "repos": [], "automacoes": [
          {"id": "a1", "nome": "x", "quando": ["focar", "lua-cheia"], "onde": "worktrees", "repos": [], "comando": "true", "ativa": true},
          {"id": "a2", "nome": "y", "quando": ["focar"], "onde": "nuvem", "repos": [], "comando": "true", "ativa": true},
          {"id": "a3", "nome": "z", "tipo": "teletransporte", "onde": "worktrees", "repos": [], "ativa": true},
          {"id": "a4", "nome": "w", "tipo": "caminhos", "onde": "principais", "repos": ["app"], "arquivos": [".env"], "ativa": true}
        ]}
        """
        let config = try Workspace.decodeConfig(json, path: "config.json")
        XCTAssertEqual(config.automations.map(\.events), [[.focus], [.focus], [], []])
        XCTAssertEqual(config.automations.map(\.enabled), [true, false, false, true])
        XCTAssertEqual(config.automations[3].kind, .paths)
        XCTAssertEqual(config.automations[3].files, [".env"])
        XCTAssertTrue(config.automations[3].followsFocus)
    }

    func testFocusAndAutomationCommands() throws {
        let w = try lab.workspace()
        let root = w.root
        let main = lab.repos["rebocs-admin"]!
        try lab.write(main + "/local.env", "API=../rebocs_api\n")
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Pelo terminal", repos: ["api"], noFetch: true))
        func run(_ args: [String], in folder: String) -> (code: Int32, output: String, error: String) {
            var output = ""
            var error = ""
            let cli = CLI(output: { output += $0 }, error: { error += $0 }, input: { Data() },
                          currentDirectory: { folder }, environment: ["TRAMA_HOME": root])
            setenv("TRAMA_HOME", root, 1)
            return (cli.run(args), output, error)
        }
        var r = run(["focar"], in: lab.root)
        XCTAssertEqual(r.output, "Nenhuma trama em foco. Use: trama focar <trama>\n")

        r = run(["automacao", "add", "Env", "segue", "--caminhos", "local.env", "--onde", "principal", "--repos", "admin"], in: lab.root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertEqual(r.output, "✓ automação 1 · Env segue: enquanto uma trama estiver em foco · na cópia principal de rebocs-admin\n")

        r = run(["focar"], in: w.worktreePath(t.slug, "rebocs_api"))
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertEqual(r.output, "✓ Pelo terminal em foco\n  local.env de rebocs-admin aponta para pelo-terminal\n")
        XCTAssertEqual(try read(main + "/local.env"), "API=\(w.worktreePath(t.slug, "rebocs_api"))\n")
        r = run(["focar"], in: lab.root)
        XCTAssertEqual(r.output, "Pelo terminal (pelo-terminal) está em foco\n")

        r = run(["automacao", "modelos"], in: lab.root)
        XCTAssertTrue(r.output.contains("Flutter/Dart"))
        XCTAssertTrue(r.output.contains("Docker"))
        r = run(["automacao", "add", "--modelo", "flutter-pub-get", "--repos", "admin"], in: lab.root)
        XCTAssertEqual(r.code, 0, r.error)
        XCTAssertEqual(r.output, "✓ automação 2 · flutter pub get ao focar: ao focar · na cópia principal de rebocs-admin\n")
        r = run(["automacao", "add", "x", "--quando", "sempre", "--comando", "true"], in: lab.root)
        XCTAssertNotEqual(r.code, 0)
        XCTAssertTrue(r.error.contains("evento desconhecido"))
        r = run(["automacao", "add", "x", "--comando", "true", "--caminhos", ".env"], in: lab.root)
        XCTAssertTrue(r.error.contains("não os dois"))
        r = run(["automacao", "desligar", "2"], in: lab.root)
        XCTAssertEqual(r.output, "✓ “flutter pub get ao focar” desligada\n")
        r = run(["automacao"], in: lab.root)
        XCTAssertTrue(r.output.contains("Em foco: Pelo terminal (pelo-terminal)"))
        XCTAssertTrue(r.output.contains("segue o foco"))
        XCTAssertTrue(r.output.contains("apontar caminhos em local.env"))
        XCTAssertTrue(r.output.contains("flutter pub get ao focar (desligada)"))
        r = run(["automacao", "rm", "2"], in: lab.root)
        XCTAssertEqual(try Workspace.open(root: root).config.automations.count, 1)

        r = run(["focar", "--limpar"], in: lab.root)
        XCTAssertEqual(r.output, "✓ Pelo terminal saiu do foco · as cópias principais voltaram ao que eram\n")
        XCTAssertNil(w.focusedSlug())
        XCTAssertEqual(try read(main + "/local.env"), "API=../rebocs_api\n")
    }
}
