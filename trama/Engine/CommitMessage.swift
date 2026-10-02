import Foundation

extension CLITool {
    static let claude = CLITool(
        name: "claude",
        environmentKey: "TRAMA_CLAUDE",
        candidates: ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", NSHomeDirectory() + "/.local/bin/claude", NSHomeDirectory() + "/.claude/local/claude"],
        installHint: "instale o Claude Code e entre na sua conta",
        environment: ["NO_COLOR": "1"]
    )
}

extension Workspace {
    public func suggestCommitMessage(_ slug: String, repo name: String) throws -> String {
        let wt = worktreePath(slug, try repo(name).name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree não encontrado em \(Paths.abbreviate(wt))") }
        let changes = Git.fileChanges(wt)
        guard !changes.isEmpty else { throw TramaError("não há mudanças em \(name)") }
        let prompt = Self.commitPrompt(
            files: changes.map { "\($0.code.trimmingCharacters(in: .whitespaces)) \($0.path) (+\($0.added) -\($0.removed))" },
            diff: Self.boundedDiff(wt, untracked: changes.filter(\.untracked).map(\.path)),
            recent: (try? Git.run(wt, "log", "-8", "--format=%s")) ?? ""
        )
        let raw = try CLITool.claude.run(wt, ["-p", prompt, "--model", "haiku"])
        let message = Self.cleanMessage(raw)
        guard !message.isEmpty else { throw TramaError("o Claude não devolveu uma mensagem") }
        return message
    }

    static func boundedDiff(_ wt: String, untracked: [String], limit: Int = 24_000) -> String {
        var diff = (try? Git.run(wt, ["diff", "HEAD", "--no-color", "--unified=2"])) ?? ""
        if diff.count > limit { diff = String(diff.prefix(limit)) + "\n[diff truncado]" }
        if !untracked.isEmpty {
            diff += "\n\nArquivos novos (sem diff): " + untracked.prefix(40).joined(separator: ", ")
        }
        return diff
    }

    static func commitPrompt(files: [String], diff: String, recent: String) -> String {
        """
        Escreva a mensagem de commit para estas mudanças. Responda só com a mensagem, sem aspas, sem markdown e sem explicação.
        Primeira linha: assunto no imperativo, até 72 caracteres, sem ponto final. Se as mudanças pedirem, uma linha em branco e um corpo curto explicando o porquê.
        Siga o idioma e o estilo dos commits recentes. Não acrescente linhas Co-Authored-By.

        Commits recentes:
        \(recent)

        Arquivos:
        \(files.joined(separator: "\n"))

        Diff:
        \(diff)
        """
    }

    static func cleanMessage(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            text = lines.joined(separator: "\n")
        }
        let kept = text.components(separatedBy: "\n").filter { !$0.lowercased().hasPrefix("co-authored-by:") }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
