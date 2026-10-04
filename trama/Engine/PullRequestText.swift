import Foundation

public struct PullRequestText: Sendable {
    public var title: String
    public var summary: String
}

extension Workspace {
    public func suggestPullRequestText(_ slug: String, only: Set<String>? = nil, targets: [String: String] = [:]) throws -> PullRequestText {
        let t = try trama(slug)
        var sections: [String] = []
        var cwd: String?
        for r in mergeOrdered(t.repos) {
            if let only, !only.contains(r.name) { continue }
            let wt = worktreePath(t.slug, r.name)
            guard Paths.isDirectory(wt) else { continue }
            let ref = Git.baseRef(wt, targets[r.name] ?? base(for: t, r))
            let log = (try? Git.run(wt, ["log", "\(ref)..HEAD", "--format=- %s", "-30"])) ?? ""
            guard !log.isEmpty else { continue }
            let stat = (try? Git.run(wt, ["diff", "--stat", "--no-color", "\(ref)...HEAD"])) ?? ""
            sections.append("Repositório \(r.name):\nCommits:\n\(log)\nArquivos:\n\(String(stat.suffix(1_500)))")
            cwd = cwd ?? wt
        }
        guard let cwd, !sections.isEmpty else { throw TramaError("não há commits à frente do destino para descrever") }
        let capsule = (try? readCapsule(t.slug)) ?? TramaCapsule(trama: t.slug, path: "", exists: false)
        let prompt = Self.pullRequestPrompt(title: t.title, goal: capsule.goal, sections: sections)
        let raw = try CLITool.claude.run(cwd, ["-p", prompt, "--model", "haiku"])
        guard let text = Self.parsePullRequestText(raw) else { throw TramaError("o Claude não devolveu um título") }
        return text
    }

    static func pullRequestPrompt(title: String, goal: String, sections: [String]) -> String {
        """
        Escreva o título e a descrição de um pull request que cobre as mudanças abaixo. Responda só com o texto, sem aspas e sem blocos de código.
        Primeira linha: o título, até 70 caracteres, sem ponto final. Depois uma linha em branco e uma descrição curta em markdown: um parágrafo com o porquê e uma lista de 2 a 5 itens com o que muda. Se houver mais de um repositório, diga o papel de cada um. Escreva em português do Brasil.

        Trama: \(title)
        Objetivo: \(goal.isEmpty ? "(não informado)" : goal)

        \(sections.joined(separator: "\n\n"))
        """
    }

    static func parsePullRequestText(_ raw: String) -> PullRequestText? {
        let cleaned = cleanMessage(raw)
        var lines = cleaned.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }
        var title = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") { title.removeFirst() }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let summary = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return PullRequestText(title: title, summary: summary)
    }
}
