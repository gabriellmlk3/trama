import Foundation

@MainActor
final class GeneralAgentSession: ObservableObject {
    static let allowedTools = ["Read", "Grep", "Glob", "Bash(trama *)", "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)"]

    static let role = HomeAgent.instructions

    let path: String
    let extraDirs: [String]
    @Published private(set) var conversation = AgentConversation()
    @Published private(set) var running = false
    private var parser = AgentStreamParser()
    private var handle: StreamHandle?
    private var turn = 0

    init(path: String, extraDirs: [String]) {
        self.path = path
        self.extraDirs = extraDirs
    }

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !running else { return }
        guard let executable = CLITool.claude.executable else {
            conversation.addError(CLITool.claude.missingMessage)
            return
        }
        conversation.addUser(prompt)
        parser = AgentStreamParser()
        running = true
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
        handle?.terminate()
    }

    func reset() {
        stop()
        conversation = AgentConversation()
    }

    private func arguments() -> [String] {
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--permission-mode", "acceptEdits"]
        args += ["--allowedTools"] + Self.allowedTools
        args += ["--append-system-prompt", Self.role]
        if let id = conversation.sessionID {
            args += ["--resume", id]
        } else if ClaudeSessions.hasHistory(at: path) {
            args.append("--continue")
        }
        args += extraDirs.flatMap { ["--add-dir", $0] }
        return args
    }

    private func receive(_ line: String, turn: Int) {
        guard turn == self.turn else { return }
        for event in parser.parse(line) { conversation.apply(event) }
    }

    private func finish(code: Int32, error: String, turn: Int) {
        guard turn == self.turn else { return }
        running = false
        handle = nil
        conversation.closeLiveText()
        guard code != 0 else { return }
        let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.addError(message.isEmpty ? "O Claude terminou com código \(code)." : message)
    }
}
