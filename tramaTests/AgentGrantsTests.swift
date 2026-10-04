import Foundation
import XCTest
@testable import trama

final class AgentGrantsTests: XCTestCase {
    func testGrantsPersistPerTramaAndCanBeRevoked() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()

        try w.grantAgent("melhorias", rule: "Bash(make test)", directory: nil)
        try w.grantAgent("melhorias", rule: "Bash(make test)", directory: "/tmp/x")
        try w.grantAgent("outra", rule: "Edit", directory: nil)

        let reopened = try Workspace.open(root: w.root)
        XCTAssertEqual(reopened.agentGrants("melhorias"), AgentGrants(rules: ["Bash(make test)"], directories: ["/tmp/x"]))
        XCTAssertEqual(reopened.agentGrants("outra").rules, ["Edit"])
        XCTAssertTrue(reopened.agentGrants("nenhuma").isEmpty)

        try reopened.revokeAgent("melhorias", rule: "Bash(make test)", directory: nil)
        try reopened.revokeAgent("melhorias", rule: nil, directory: "/tmp/x")
        XCTAssertTrue(try Workspace.open(root: w.root).agentGrants("melhorias").isEmpty)
        XCTAssertNil(try Workspace.open(root: w.root).config.agentGrants["melhorias"])
    }

    func testResultCarriesTokenUsageAndLabelFormatsIt() {
        var parser = AgentStreamParser()
        let line = #"{"type":"result","is_error":false,"total_cost_usd":0.1234,"permission_denials":[],"usage":{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":985,"output_tokens":2500}}"#
        var conversation = AgentConversation()
        for event in parser.parse(line) { conversation.apply(event) }
        XCTAssertEqual(conversation.inputTokens, 1000)
        XCTAssertEqual(conversation.outputTokens, 2500)
        XCTAssertEqual(conversation.usageLabel, "US$ 0,12 · 3,5 mil tokens")
        XCTAssertNil(AgentConversation().usageLabel)
    }

    func testTrashedConversationCanBeRestored() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let folder = Paths.join(lab.root, "trama-z")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let dir = ClaudeSessions.projectDirectory(for: folder, home: lab.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try (#"{"type":"user","message":{"role":"user","content":"oi"}}"# + "\n").write(toFile: Paths.join(dir, "a.jsonl"), atomically: true, encoding: .utf8)

        let trashed = ClaudeSessions.trash(id: "a", at: folder, home: lab.root)
        XCTAssertEqual(trashed.count, 1)
        XCTAssertTrue(ClaudeSessions.conversations(at: folder, home: lab.root).isEmpty)
        XCTAssertTrue(ClaudeSessions.restore(trashed))
        XCTAssertEqual(ClaudeSessions.conversations(at: folder, home: lab.root).map(\.id), ["a"])
    }
}
