import Foundation
import XCTest
@testable import trama

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
