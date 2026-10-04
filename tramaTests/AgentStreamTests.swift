import Foundation
import XCTest
@testable import trama

final class AgentStreamTests: XCTestCase {
    private let started = #"{"type":"system","subtype":"init","cwd":"/x","session_id":"s1","model":"claude-sonnet-5-5","permissionMode":"default"}"#
    private let messageStart = #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"m1","role":"assistant","content":[]}},"parent_tool_use_id":null}"#
    private let toolUse = #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x/ROADMAP.md","limit":5}}]},"parent_tool_use_id":null}"#
    private let toolResult = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t1","type":"tool_result","content":"1\t# Roadmap"}]},"parent_tool_use_id":null}"#
    private let secondMessage = #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"m2","role":"assistant","content":[]}},"parent_tool_use_id":null}"#
    private let delta1 = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"O backlog"}},"parent_tool_use_id":null}"#
    private let delta2 = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" do Trama."}},"parent_tool_use_id":null}"#
    private let finalText = #"{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"O backlog do Trama."}]},"parent_tool_use_id":null}"#
    private let result = #"{"type":"result","subtype":"success","is_error":false,"duration_ms":4437,"result":"O backlog do Trama.","total_cost_usd":0.1,"permission_denials":[]}"#

    private func conversation(_ lines: [String]) -> AgentConversation {
        var parser = AgentStreamParser()
        var conversation = AgentConversation()
        for line in lines { for event in parser.parse(line) { conversation.apply(event) } }
        return conversation
    }

    func testParsesInitToolAndResultEvents() {
        var parser = AgentStreamParser()
        XCTAssertEqual(parser.parse(started), [.started(sessionID: "s1", model: "claude-sonnet-5-5")])
        XCTAssertEqual(parser.parse(toolUse), [.message(id: "m1", blocks: [.toolUse(id: "t1", name: "Read", summary: "/x/ROADMAP.md")])])
        XCTAssertEqual(parser.parse(toolResult), [.toolResult(toolUseID: "t1", text: "1\t# Roadmap", isError: false)])
    }

    func testTextDeltasNeedTheMessageStartThatPrecedesThem() {
        var parser = AgentStreamParser()
        XCTAssertEqual(parser.parse(delta1), [])
        _ = parser.parse(secondMessage)
        XCTAssertEqual(parser.parse(delta1), [.textDelta(messageID: "m2", text: "O backlog")])
    }

    func testIgnoresSubagentGarbageAndUnknownLines() {
        var parser = AgentStreamParser()
        XCTAssertEqual(parser.parse("não é json"), [])
        XCTAssertEqual(parser.parse(#"{"type":"rate_limit_event"}"#), [])
        XCTAssertEqual(parser.parse(#"{"type":"assistant","parent_tool_use_id":"t9","message":{"id":"m","content":[{"type":"text","text":"x"}]}}"#), [])
    }

    func testStreamedTextAndFinalMessageBecomeASingleItem() {
        let c = conversation([started, messageStart, toolUse, toolResult, secondMessage, delta1, delta2, finalText, result])
        XCTAssertEqual(c.items.map(\.kind), [.tool, .assistant])
        XCTAssertEqual(c.items[0].result, "1\t# Roadmap")
        XCTAssertEqual(c.items[1].text, "O backlog do Trama.")
        XCTAssertFalse(c.items[1].isLive)
        XCTAssertEqual(c.sessionID, "s1")
    }

    func testCompactBoundaryResetsContextAndLeavesANotice() {
        let withUsage = #"{"type":"assistant","message":{"id":"m3","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":150000,"output_tokens":10}}}"#
        let boundary = #"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":150010,"post_tokens":9000}}"#
        let c = conversation([withUsage, boundary])
        XCTAssertEqual(c.contextTokens, 9_000)
        XCTAssertEqual(c.items.last?.kind, .notice)
    }

    func testContextUsageComesFromTheLastAssistantMessageAndModelWindow() {
        let withUsage = #"{"type":"assistant","message":{"id":"m3","role":"assistant","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":84985,"output_tokens":100}}}"#
        let done = #"{"type":"result","is_error":false,"result":"ok","permission_denials":[],"modelUsage":{"claude-opus":{"contextWindow":1000000}}}"#
        var c = conversation([withUsage])
        XCTAssertEqual(c.contextTokens, 85_100)
        XCTAssertEqual(c.usageLabel, "Contexto 43% · 85,1 mil de 200 mil")
        c = conversation([withUsage, done])
        XCTAssertEqual(c.usageLabel, "Contexto 9% · 85,1 mil de 1 mi")
        XCTAssertNil(AgentConversation().usageLabel)
    }

    func testPartialTextStaysLiveUntilTheFinalMessage() {
        let c = conversation([secondMessage, delta1, delta2])
        XCTAssertEqual(c.items.map(\.text), ["O backlog do Trama."])
        XCTAssertTrue(c.items[0].isLive)
    }

    func testFinalMessageWithoutPartialsStillAppears() {
        let c = conversation([finalText, finalText])
        XCTAssertEqual(c.items.count, 1)
    }

    func testDeniedToolsAndErrorsBecomeNotices() {
        let denied = #"{"type":"result","is_error":true,"result":"falhou","permission_denials":[{"tool_name":"Bash"},{"tool_name":"Bash"}]}"#
        let c = conversation([denied])
        XCTAssertEqual(c.items.map(\.kind), [.error, .notice])
        XCTAssertTrue(c.items[1].text.contains("Bash"))
    }

    func testDeniedNoticeShowsTheCommand() {
        let denied = #"{"type":"result","is_error":false,"result":"ok","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"cd /x && trama ls\nsegunda linha"}}]}"#
        let c = conversation([denied])
        XCTAssertTrue(c.items.last?.text.contains("Bash `cd /x && trama ls`") ?? false)
    }

    func testStreamDeliversLinesInOrderAndTheExitCode() throws {
        let done = expectation(description: "exit")
        let box = LineBox()
        _ = try ProcessRunner.stream(
            "/bin/sh", ["-c", "cat; printf 'sem-quebra'; echo erro >&2; exit 3"],
            input: "um\ndois\n",
            onLine: { box.append($0) },
            onExit: { code, error in
                box.finish(code: code, error: error)
                done.fulfill()
            }
        )
        wait(for: [done], timeout: 10)
        XCTAssertEqual(box.lines, ["um", "dois", "sem-quebra"])
        XCTAssertEqual(box.code, 3)
        XCTAssertEqual(box.error.trimmingCharacters(in: .whitespacesAndNewlines), "erro")
    }
}

private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lines: [String] = []
    private(set) var code: Int32 = -99
    private(set) var error = ""

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    func finish(code: Int32, error: String) {
        lock.lock(); defer { lock.unlock() }
        self.code = code
        self.error = error
    }
}
