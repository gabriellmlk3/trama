import Foundation
import XCTest
@testable import trama

final class ClaudeTranscriptTests: XCTestCase {
    func testTranscriptKeepsOnlyVisibleTextTurns() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let folder = Paths.join(lab.root, "trama-x")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let dir = ClaudeSessions.projectDirectory(for: folder, home: lab.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}"#,
            #"{"type":"user","message":{"role":"user","content":"ajuste o login"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Read","input":{}},{"type":"text","text":"feito"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"x"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"lateral"}]}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(toFile: Paths.join(dir, "abc.jsonl"), atomically: true, encoding: .utf8)

        let turns = ClaudeSessions.transcript(id: "abc", at: folder, home: lab.root)
        XCTAssertEqual(turns.map(\.text), ["ajuste o login", "feito"])
        XCTAssertEqual(turns.map(\.isUser), [true, false])
        XCTAssertTrue(ClaudeSessions.transcript(id: "nao-existe", at: folder, home: lab.root).isEmpty)

        var conversation = AgentConversation()
        conversation.addHistory(turns)
        XCTAssertEqual(conversation.items.map(\.kind), [.user, .assistant])
    }

    func testTramaInstructionsNameTheRepositories() {
        let text = TramaAgent.instructions(title: "Melhorias", branch: "trama/melhorias", repos: ["api", "admin"])
        XCTAssertTrue(text.contains("“Melhorias”"))
        XCTAssertTrue(text.contains("api, admin"))
        XCTAssertTrue(text.contains("trama capsula"))
    }

    func testDockedIsTheDefaultTarget() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: ClaudeTarget.storageKey)
        defer { defaults.set(saved, forKey: ClaudeTarget.storageKey) }
        defaults.removeObject(forKey: ClaudeTarget.storageKey)
        XCTAssertEqual(ClaudeTarget.current, .docked)
        defaults.set(ClaudeTarget.cli.rawValue, forKey: ClaudeTarget.storageKey)
        XCTAssertEqual(ClaudeTarget.current, .cli)
    }
}
