import Foundation
import XCTest
@testable import trama

final class AgentPermissionTests: XCTestCase {
    private func denials(_ json: String) -> [AgentDenial] {
        var parser = AgentStreamParser()
        for case .finished(let result) in parser.parse(#"{"type":"result","is_error":false,"result":"ok","permission_denials":\#(json)}"#) {
            return result.denials
        }
        return []
    }

    func testBashDenialOffersExactAndPrefixRules() {
        let found = denials(#"[{"tool_name":"Bash","tool_input":{"command":"npm test -- --watch"}}]"#)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].onceRule, "Bash(npm test -- --watch)")
        XCTAssertEqual(found[0].sessionRule, "Bash(npm *)")
        XCTAssertNil(found[0].directory)
        XCTAssertEqual(found[0].summary, "Bash `npm test -- --watch`")
    }

    func testFileOutsideTheWorkspaceOffersItsDirectory() {
        let found = denials(#"[{"tool_name":"Read","tool_input":{"file_path":"/tmp/outro/a.txt"}}]"#)
        XCTAssertEqual(found[0].directory, "/tmp/outro")
        XCTAssertNil(found[0].onceRule)
        XCTAssertNil(found[0].sessionRule)
    }

    func testOtherToolsAreAllowedByName() {
        let found = denials(#"[{"tool_name":"WebFetch","tool_input":{"url":"https://x.dev"}}]"#)
        XCTAssertEqual(found[0].onceRule, "WebFetch")
        XCTAssertEqual(found[0].sessionRule, "WebFetch")
    }

    func testResultKeepsDeniedToolsSummaries() {
        let found = denials(#"[{"tool_name":"Bash"}]"#)
        XCTAssertEqual(found.map(\.summary), ["Bash"])
    }

    func testArgumentsAppendGrantsAfterTheBaseTools() {
        let args = AgentCLI.arguments(role: "papel", sessionID: "s1", extraTools: ["Bash(npm *)"], directories: ["/a", "/b"])
        let tools = args.firstIndex(of: "--allowedTools").map { Array(args[($0 + 1)...].prefix(AgentCLI.baseTools.count + 1)) }
        XCTAssertEqual(tools, AgentCLI.baseTools + ["Bash(npm *)"])
        XCTAssertEqual(args.firstIndex(of: "--resume").map { args[$0 + 1] }, "s1")
        XCTAssertEqual(args.filter { $0 == "--add-dir" }.count, 2)
        XCTAssertFalse(AgentCLI.arguments(role: "papel", sessionID: nil, extraTools: [], directories: []).contains("--resume"))
    }

    func testRepoInstructionsScopeTheAgentToOneWorktree() {
        let text = TramaAgent.repoInstructions(title: "Melhorias", branch: "trama/melhorias", repo: "api", others: ["admin"])
        XCTAssertTrue(text.contains("“api”"))
        XCTAssertTrue(text.contains("só nele"))
        XCTAssertTrue(text.contains("admin"))
        XCTAssertTrue(text.contains("trama recebido"))
    }

    func testHandoffPromptNamesTheNumberToMarkAsReceived() {
        let text = TramaAgent.handoffPrompt(from: "api", to: "admin", number: 3, text: "usar o novo endpoint")
        XCTAssertTrue(text.contains("#3 de api para admin"))
        XCTAssertTrue(text.contains("trama recebido 3"))
        XCTAssertTrue(text.contains("usar o novo endpoint"))
    }
}
