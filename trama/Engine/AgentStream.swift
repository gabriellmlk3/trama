import Foundation

enum AgentBlock: Equatable {
    case text(String)
    case toolUse(id: String, name: String, summary: String)
}

struct AgentDenial: Equatable, Hashable {
    var tool: String
    var detail: String
    var directory: String?

    init(tool: String, input: [String: Any]) {
        self.tool = tool
        let command = input["command"] as? String
        let file = input["file_path"] as? String
        detail = (command ?? file ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        directory = file.flatMap { $0.hasPrefix("/") ? ($0 as NSString).deletingLastPathComponent : nil }
    }

    var summary: String {
        let line = detail.split(separator: "\n").first.map(String.init) ?? ""
        return line.isEmpty ? tool : "\(tool) `\(line.count > 90 ? String(line.prefix(90)) + "…" : line)`"
    }

    var onceRule: String? {
        if directory != nil { return nil }
        if tool == "Bash", !detail.isEmpty { return "Bash(\(detail))" }
        return tool
    }

    var sessionRule: String? {
        if directory != nil { return nil }
        guard tool == "Bash", !detail.isEmpty else { return tool }
        guard let word = detail.split(whereSeparator: \.isWhitespace).first else { return nil }
        return "Bash(\(word) *)"
    }
}

struct AgentResult: Equatable {
    var isError: Bool
    var message: String?
    var costUSD: Double?
    var durationMS: Int?
    var denials: [AgentDenial]

    var deniedTools: [String] { denials.map(\.summary) }
}

enum AgentCLI {
    static let baseTools = ["Read", "Grep", "Glob", "Bash(trama *)", "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)"]

    static func arguments(role: String, sessionID: String?, extraTools: [String], directories: [String]) -> [String] {
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-mode", "acceptEdits"]
        args += ["--allowedTools"] + baseTools + extraTools
        args += ["--append-system-prompt", role]
        if let sessionID { args += ["--resume", sessionID] }
        args += directories.flatMap { ["--add-dir", $0] }
        return args
    }
}

enum AgentEvent: Equatable {
    case started(sessionID: String, model: String)
    case textDelta(messageID: String, text: String)
    case message(id: String, blocks: [AgentBlock])
    case toolResult(toolUseID: String, text: String, isError: Bool)
    case finished(AgentResult)
}

struct AgentStreamParser {
    private var currentMessageID: String?

    mutating func parse(_ line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        if let parent = object["parent_tool_use_id"] as? String, !parent.isEmpty { return [] }
        switch type {
        case "system":
            guard object["subtype"] as? String == "init", let id = object["session_id"] as? String else { return [] }
            return [.started(sessionID: id, model: object["model"] as? String ?? "")]
        case "stream_event":
            return parseStream(object["event"] as? [String: Any] ?? [:])
        case "assistant":
            return parseAssistant(object["message"] as? [String: Any] ?? [:])
        case "user":
            return parseUser(object["message"] as? [String: Any] ?? [:])
        case "result":
            return [.finished(parseResult(object))]
        default:
            return []
        }
    }

    private mutating func parseStream(_ event: [String: Any]) -> [AgentEvent] {
        switch event["type"] as? String {
        case "message_start":
            currentMessageID = (event["message"] as? [String: Any])?["id"] as? String
            return []
        case "content_block_delta":
            guard let id = currentMessageID,
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            return [.textDelta(messageID: id, text: text)]
        default:
            return []
        }
    }

    private func parseAssistant(_ message: [String: Any]) -> [AgentEvent] {
        guard let id = message["id"] as? String, let content = message["content"] as? [[String: Any]] else { return [] }
        let blocks: [AgentBlock] = content.compactMap { block in
            switch block["type"] as? String {
            case "text":
                guard let text = block["text"] as? String else { return nil }
                return .text(text)
            case "tool_use":
                guard let toolID = block["id"] as? String, let name = block["name"] as? String else { return nil }
                return .toolUse(id: toolID, name: name, summary: Self.summary(of: block["input"] as? [String: Any] ?? [:]))
            default:
                return nil
            }
        }
        return blocks.isEmpty ? [] : [.message(id: id, blocks: blocks)]
    }

    private func parseUser(_ message: [String: Any]) -> [AgentEvent] {
        guard let content = message["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { block in
            guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
            return .toolResult(toolUseID: id, text: Self.text(of: block["content"]), isError: block["is_error"] as? Bool ?? false)
        }
    }

    private func parseResult(_ object: [String: Any]) -> AgentResult {
        let denials = (object["permission_denials"] as? [[String: Any]] ?? []).compactMap { denial -> AgentDenial? in
            guard let name = denial["tool_name"] as? String else { return nil }
            return AgentDenial(tool: name, input: denial["tool_input"] as? [String: Any] ?? [:])
        }
        return AgentResult(
            isError: object["is_error"] as? Bool ?? false,
            message: object["result"] as? String,
            costUSD: object["total_cost_usd"] as? Double,
            durationMS: object["duration_ms"] as? Int,
            denials: denials
        )
    }

    private static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private static func summary(of input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return input.keys.sorted().compactMap { input[$0] as? String }.first ?? ""
    }
}

struct AgentItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case assistant
        case tool
        case notice
        case error
    }

    var id: Int
    var kind: Kind
    var text: String
    var messageID: String?
    var toolUseID: String?
    var toolName: String?
    var result: String?
    var resultIsError = false
    var isLive = false
    var attachments: [String] = []
}

struct AgentConversation: Equatable {
    private(set) var items: [AgentItem] = []
    private(set) var sessionID: String?
    private(set) var model: String?
    private(set) var costUSD: Double = 0
    private var nextID = 0

    mutating func addUser(_ text: String, attachments: [String] = []) {
        append(.user, text)
        items[items.count - 1].attachments = attachments
    }

    mutating func addHistory(_ turns: [(isUser: Bool, text: String)]) {
        for turn in turns { append(turn.isUser ? .user : .assistant, turn.text) }
    }

    mutating func addNotice(_ text: String) {
        append(.notice, text)
    }

    mutating func addError(_ text: String) {
        append(.error, text)
    }

    mutating func closeLiveText() {
        for index in items.indices where items[index].isLive { items[index].isLive = false }
    }

    mutating func apply(_ event: AgentEvent) {
        switch event {
        case .started(let id, let model):
            sessionID = id
            if !model.isEmpty { self.model = model }
        case .textDelta(let messageID, let text):
            if let index = liveIndex(messageID) {
                items[index].text += text
            } else {
                append(.assistant, text, messageID: messageID, live: true)
            }
        case .message(let messageID, let blocks):
            for block in blocks { apply(block, messageID: messageID) }
        case .toolResult(let toolUseID, let text, let isError):
            guard let index = items.firstIndex(where: { $0.toolUseID == toolUseID }) else { return }
            items[index].result = text
            items[index].resultIsError = isError
        case .finished(let result):
            closeLiveText()
            costUSD += result.costUSD ?? 0
            if result.isError { addError(result.message ?? "O Claude terminou com erro.") }
            if !result.deniedTools.isEmpty {
                let names = Array(Set(result.deniedTools)).sorted().joined(separator: ", ")
                addNotice("Sem permissão no modo visual: \(names).")
            }
        }
    }

    private mutating func apply(_ block: AgentBlock, messageID: String) {
        switch block {
        case .text(let text):
            if let index = liveIndex(messageID) {
                items[index].text = text
                items[index].isLive = false
            } else if !items.contains(where: { $0.messageID == messageID && $0.kind == .assistant && $0.text == text }) {
                append(.assistant, text, messageID: messageID)
            }
        case .toolUse(let id, let name, let summary):
            if let index = items.firstIndex(where: { $0.toolUseID == id }) {
                items[index].text = summary
            } else {
                append(.tool, summary, messageID: messageID, toolUseID: id, toolName: name)
            }
        }
    }

    private func liveIndex(_ messageID: String) -> Int? {
        items.lastIndex { $0.isLive && $0.messageID == messageID }
    }

    private mutating func append(_ kind: AgentItem.Kind, _ text: String, messageID: String? = nil, toolUseID: String? = nil, toolName: String? = nil, live: Bool = false) {
        items.append(AgentItem(id: nextID, kind: kind, text: text, messageID: messageID, toolUseID: toolUseID, toolName: toolName, isLive: live))
        nextID += 1
    }
}
