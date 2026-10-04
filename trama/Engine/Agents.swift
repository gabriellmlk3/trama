import Foundation

public enum AgentState {
    public static let open = "aberto"
    public static let working = "trabalhando"
    public static let waiting = "aguardando"
    public static let done = "concluiu"
}

public struct Agent: Codable, Hashable, Identifiable, Sendable {
    public var session: String
    public var trama: String
    public var repo: String
    public var cwd: String
    public var state: String
    public var message: String?
    public var startedAt: Int64
    public var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case session = "sessao", trama, repo, cwd, state = "estado", message = "mensagem"
        case startedAt = "iniciadoEm", updatedAt = "atualizadoEm"
    }

    public var id: String { session }
    public var isRoot: Bool { repo.isEmpty }
    public var isWorking: Bool { state == AgentState.working }
    public var isWaiting: Bool { state == AgentState.waiting }
    public var isDone: Bool { state == AgentState.done }
}

public struct HookInput: Decodable, Sendable {
    public var sessionID: String?
    public var hookEventName: String?
    public var cwd: String?
    public var source: String?
    public var message: String?
    public var notificationType: String?
    public var lastAssistantMessage: String?
    public var userPrompt: String?
    public var prompt: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hookEventName = "hook_event_name"
        case cwd, source, message
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case userPrompt = "user_prompt"
        case prompt
    }

    public init(session: String, event: String, cwd: String, source: String? = nil, message: String? = nil,
                notificationType: String? = nil, lastAssistantMessage: String? = nil, userPrompt: String? = nil) {
        self.sessionID = session
        self.hookEventName = event
        self.cwd = cwd
        self.source = source
        self.message = message
        self.notificationType = notificationType
        self.lastAssistantMessage = lastAssistantMessage
        self.userPrompt = userPrompt
    }
}

private struct SessionStartOutput: Encodable {
    struct Specific: Encodable {
        var hookEventName = "SessionStart"
        var additionalContext: String
    }

    var hookSpecificOutput: Specific
}

private let agentInvisibleAfter: TimeInterval = 12 * 3600
private let agentDeleteAfter: TimeInterval = 48 * 3600

extension Workspace {
    private func agentPath(_ session: String) -> String {
        let clean = String(session.unicodeScalars.filter { s in
            CharacterSet.alphanumerics.contains(s) && s.isASCII || s == "-" || s == "_"
        }.map(Character.init))
        return Paths.join(agentsDir, (clean.isEmpty ? "sem-id" : clean) + ".json")
    }

    private func readAgent(_ session: String) -> Agent? {
        guard let text = try? File.read(agentPath(session)) else { return nil }
        return try? JSONDecoder().decode(Agent.self, from: Data(text.utf8))
    }

    private func saveAgent(_ a: Agent) throws {
        let data = try JSON.encoder().encode(a)
        try File.write(data, to: agentPath(a.session))
    }

    public func agents() throws -> [Agent] {
        let fm = FileManager.default
        guard Paths.isDirectory(agentsDir) else { return [] }
        let now = Date()
        var list: [Agent] = []
        for name in try fm.contentsOfDirectory(atPath: agentsDir) where name.hasSuffix(".json") {
            let path = Paths.join(agentsDir, name)
            guard let text = try? File.read(path),
                  let a = try? JSONDecoder().decode(Agent.self, from: Data(text.utf8)) else { continue }
            let age = now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(a.updatedAt)))
            if age > agentDeleteAfter {
                try? fm.removeItem(atPath: path)
                continue
            }
            if age > agentInvisibleAfter { continue }
            list.append(a)
        }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public func handleHook(_ input: HookInput, now: Date = Date()) throws -> String {
        guard let session = input.sessionID, !session.isEmpty,
              let cwd = input.cwd, !cwd.isEmpty,
              let place = try? locate(cwd) else {
            return ""
        }
        let (t, r) = place
        let event = input.hookEventName ?? ""
        if event == "SessionEnd" {
            try? FileManager.default.removeItem(atPath: agentPath(session))
            return ""
        }
        let unix = Int64(now.timeIntervalSince1970)
        var a = readAgent(session) ?? Agent(session: session, trama: t.slug, repo: "", cwd: cwd, state: AgentState.open, startedAt: unix, updatedAt: unix)
        a.trama = t.slug
        a.cwd = cwd
        a.repo = r?.name ?? ""
        a.updatedAt = unix
        var out = ""
        switch event {
        case "SessionStart":
            if a.state.isEmpty { a.state = AgentState.open }
            out = sessionContext(t, r)
        case "UserPromptSubmit":
            a.state = AgentState.working
            a.message = truncate(firstLine(input.userPrompt ?? input.prompt ?? ""), 110)
        case "PostToolUse", "PreToolUse":
            a.state = AgentState.working
        case "Notification":
            if input.notificationType == "idle_prompt" {
                if a.state != AgentState.waiting { a.state = AgentState.done }
            } else {
                a.state = AgentState.waiting
                a.message = truncate(firstLine(input.message ?? ""), 140)
            }
        case "Stop":
            a.state = AgentState.done
            let m = truncate(firstLine(input.lastAssistantMessage ?? ""), 140)
            if !m.isEmpty { a.message = m }
        default:
            return ""
        }
        try saveAgent(a)
        return out
    }

    func sessionContext(_ t: Trama, _ r: RepoConfig?) -> String {
        var b = "[Trama] Você está na trama “\(t.title)” (branch \(t.branch))"
        if let r { b += ", no repositório \(r.name)" }
        b += ".\n"
        let others = t.repos.filter { $0 != r?.name }.map { "\($0) → \(worktreePath(t.slug, $0))" }
        if !others.isEmpty {
            b += "Outros repositórios desta trama: \(others.joined(separator: "; ")).\n"
        }
        b += "Registre decisões com `trama decisao \"...\"` e passe trabalho a outro repositório com `trama handoff <repo> \"...\"`.\n"
        if config.agentPullPolicy == .approval {
            b += "Precisa de um repositório que não está na trama? Peça com `trama sugerir <repo|pasta> \"motivo\"`: o usuário aprova no app antes de entrar. `trama repo descobrir` lista repositórios ainda não cadastrados.\n"
        } else {
            b += "Precisa de um repositório que não está na trama? Inclua com `trama puxar <trama> <repo> --motivo \"...\"`; se ele não estiver cadastrado, `trama repo descobrir` mostra candidatos e `trama repo add <pasta>` cadastra. Para o usuário decidir, use `trama sugerir`.\n"
        }
        if let c = try? readCapsule(t.slug), c.exists {
            if let r {
                let pending = c.handoffs.filter { !$0.done && $0.to == r.name }
                if !pending.isEmpty {
                    b += "\nHandoffs esperando por você (marque com `trama recebido` depois de ler):\n"
                    b += pending.map { "- de \($0.from ?? "?"): \($0.text)" }.joined(separator: "\n") + "\n"
                }
            }
            var md = c.markdown
            if md.count > 12000 {
                md = String(md.prefix(12000)) + "\n…(cápsula cortada · leia o arquivo completo)"
            }
            b += "\nCápsula da trama (\(c.path)):\n\n\(md)"
        }
        let out = SessionStartOutput(hookSpecificOutput: .init(additionalContext: b))
        guard let data = try? JSON.encoder(pretty: false).encode(out) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum AgentAlert: Sendable {
    case waiting, done
}

public struct AgentTransition: Hashable, Sendable {
    public var agent: Agent
    public var alert: AgentAlert

    public static func == (a: AgentTransition, b: AgentTransition) -> Bool {
        a.agent == b.agent
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(agent)
    }
}

public func agentTransitions(from previous: [Agent], to current: [Agent]) -> [AgentTransition] {
    let before = Dictionary(previous.map { ($0.session, $0.state) }, uniquingKeysWith: { _, last in last })
    return current.compactMap { agent in
        let old = before[agent.session]
        if agent.isWaiting, old != AgentState.waiting {
            return AgentTransition(agent: agent, alert: .waiting)
        }
        if agent.isDone, let old, old != AgentState.done {
            return AgentTransition(agent: agent, alert: .done)
        }
        return nil
    }
}
