import Foundation
import XCTest
@testable import trama

final class PersistenceTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
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

    func testConfigFromNewerVersionIsRefused() throws {
        let w = try lab.workspace()
        var text = try XCTUnwrap(try File.read(w.configPath))
        text = text.replacingOccurrences(of: "\"versao\" : 1", with: "\"versao\" : 99")
        try File.write(text, to: w.configPath)
        XCTAssertThrowsError(try Workspace.open(root: w.root)) { error in
            XCTAssertTrue(errorMessage(error).contains("versão 99"))
        }
    }

    func testTramasFileCarriesVersionAndRefusesNewerOnes() throws {
        let w = try lab.workspace()
        try w.saveTramas([])
        var text = try XCTUnwrap(try File.read(w.tramasPath))
        XCTAssertTrue(text.contains("\"versao\" : 1"))
        XCTAssertEqual(try w.tramas().count, 0)
        text = text.replacingOccurrences(of: "\"versao\" : 1", with: "\"versao\" : 7")
        try File.write(text, to: w.tramasPath)
        XCTAssertThrowsError(try w.tramas()) { error in
            XCTAssertTrue(errorMessage(error).contains("versão 7"))
        }
    }

    func testTramasFileWithoutVersionStillLoads() throws {
        let w = try lab.workspace()
        try File.write("{ \"tramas\" : [] }\n", to: w.tramasPath)
        XCTAssertEqual(try w.tramas().count, 0)
    }

    func testStaleWorkspaceDoesNotOverwriteOtherChanges() throws {
        let first = try lab.workspace()
        let second = try Workspace.open(root: first.root)
        try first.setDefaultBranch("develop")
        try second.setAgentPullPolicy(.approval)
        let reopened = try Workspace.open(root: first.root)
        XCTAssertEqual(reopened.config.defaultBranch, "develop")
        XCTAssertEqual(reopened.config.agentPullPolicy, .approval)
    }

    func testConcurrentConfigUpdatesLoseNothing() throws {
        let seed = try lab.workspace()
        let names = seed.config.repos.map(\.name)
        let workspaces = try names.map { _ in try Workspace.open(root: seed.root) }
        DispatchQueue.concurrentPerform(iterations: names.count * 10) { i in
            let k = i % names.count
            _ = try? workspaces[k].setMergeRank(names[k], i)
        }
        let reopened = try Workspace.open(root: seed.root)
        XCTAssertEqual(reopened.config.repos.count, names.count)
        for (k, name) in names.enumerated() where k > 0 {
            let rank = try XCTUnwrap(reopened.config.repos.first { $0.name == name }?.mergeRank)
            XCTAssertEqual(rank % names.count, k, "\(name) perdeu a gravação")
        }
        XCTAssertNoThrow(try reopened.setProvider(names[0], .github))
    }
}
