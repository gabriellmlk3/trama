import Foundation

@MainActor
final class GeneralAgentSession: ObservableObject {
    static let allowedTools = AgentCLI.baseTools

    let path: String
    let extraDirs: [String]
    let role: String
    var onTurnEnd: ((GeneralAgentSession) -> Void)?
    var attachmentsDir: String?
    var onRemember: ((AgentDenial) -> Void)?
    private(set) var grants: AgentGrants
    private var resumeID: String?
    @Published private(set) var conversation = AgentConversation()
    @Published var model = AgentModel.saved {
        didSet { UserDefaults.standard.set(model.id, forKey: AgentModel.storageKey) }
    }
    @Published private(set) var running = false
    @Published private(set) var pendingPermissions: [AgentDenial] = []
    private var parser = AgentStreamParser()
    private var handle: StreamHandle?
    private var turn = 0
    private var stopRequested = false
    private var sessionRules: [String] = []
    private var sessionDirs: [String] = []
    private var onceRules: [String] = []
    private var granted: [String] = []

    init(path: String, extraDirs: [String], role: String = HomeAgent.instructions, resume: String? = nil, grants: AgentGrants = AgentGrants()) {
        self.path = path
        self.extraDirs = extraDirs
        self.role = role
        self.resumeID = resume
        self.grants = grants
        if let resume {
            conversation.addHistory(ClaudeSessions.transcript(id: resume, at: path))
            conversation.addNotice("Conversa retomada · as mensagens acima vêm do histórico.")
        }
    }

    var lastReply: String? {
        conversation.items.last { $0.kind == .assistant }?.text
    }

    func send(_ text: String, attachments: [AgentAttachment] = []) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty || !attachments.isEmpty, !running else { return }
        guard let executable = CLITool.claude.executable else {
            conversation.addError(CLITool.claude.missingMessage)
            return
        }
        let prompt = AgentAttachments.prompt(text: typed, files: attachments)
        conversation.addUser(typed, attachments: attachments.map(\.name))
        pendingPermissions = []
        granted = []
        parser = AgentStreamParser()
        running = true
        stopRequested = false
        turn += 1
        let current = turn
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["PATH"] = Integration.agentPath(root: path, current: environment["PATH"])
        do {
            handle = try ProcessRunner.stream(
                executable,
                arguments(),
                directory: path,
                environment: environment,
                input: prompt,
                onLine: { [weak self] line in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.receive(line, turn: current) }
                    }
                },
                onExit: { [weak self] code, error in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.finish(code: code, error: error, turn: current) }
                    }
                }
            )
        } catch {
            running = false
            conversation.addError("Não consegui iniciar o Claude: \(error.localizedDescription)")
        }
    }

    func stop() {
        stopRequested = true
        handle?.terminate()
    }

    func reset() {
        stop()
        resumeID = nil
        conversation = AgentConversation()
        pendingPermissions = []
        granted = []
        sessionRules = []
        sessionDirs = []
        onceRules = []
    }

    func allow(_ denial: AgentDenial, forSession: Bool) {
        guard pendingPermissions.contains(denial) else { return }
        if let directory = denial.directory {
            if !sessionDirs.contains(directory) { sessionDirs.append(directory) }
        } else if forSession, let rule = denial.sessionRule {
            if !sessionRules.contains(rule) { sessionRules.append(rule) }
        } else if let rule = denial.onceRule {
            onceRules.append(rule)
        }
        granted.append(denial.summary)
        pendingPermissions.removeAll { $0 == denial }
        continueAfterDecision()
    }

    var canCompact: Bool { !running && conversation.sessionID != nil && conversation.contextTokens > 0 }

    func compact() {
        guard canCompact else { return }
        send("/compact")
    }

    var canRemember: Bool { onRemember != nil }

    func allowAlways(_ denial: AgentDenial) {
        guard pendingPermissions.contains(denial), canRemember else { return }
        grants.add(rule: denial.onceRule, directory: denial.directory)
        onRemember?(denial)
        allow(denial, forSession: false)
    }

    func replaceGrants(_ new: AgentGrants) {
        grants = new
    }

    func deny(_ denial: AgentDenial) {
        pendingPermissions.removeAll { $0 == denial }
        continueAfterDecision()
    }

    private func continueAfterDecision() {
        guard pendingPermissions.isEmpty else { return }
        let names = granted.joined(separator: ", ")
        granted = []
        guard !names.isEmpty else { return }
        send("Permissão concedida: \(names). Pode continuar de onde parou.")
    }

    private func arguments() -> [String] {
        AgentCLI.arguments(
            role: role,
            sessionID: conversation.sessionID ?? resumeID,
            extraTools: grants.rules + sessionRules + onceRules,
            directories: extraDirs + grants.directories + sessionDirs + [attachmentsDir].compactMap { $0 },
            model: model.argument
        )
    }

    private func receive(_ line: String, turn: Int) {
        guard turn == self.turn else { return }
        for event in parser.parse(line) {
            conversation.apply(event)
            if case .finished(let result) = event {
                var seen = Set<AgentDenial>()
                pendingPermissions = result.denials.filter { seen.insert($0).inserted }
            }
        }
    }

    private func finish(code: Int32, error: String, turn: Int) {
        guard turn == self.turn else { return }
        running = false
        handle = nil
        onceRules = []
        conversation.closeLiveText()
        if code != 0 {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            conversation.addError(message.isEmpty ? "O Claude terminou com código \(code)." : message)
        }
        if !stopRequested { onTurnEnd?(self) }
    }
}
