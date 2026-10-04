import Foundation

public struct DiscoveredRepo: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var path: String

    public var id: String { path }
}

extension Workspace {
    public func suggestRepo(_ slug: String, target: String, author: String, reason: String) throws -> CapsuleItem {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !why.isEmpty else { throw TramaError("diga por que o repositório é necessário") }
        let stored = try suggestionTarget(target)
        if let known = try? repo(stored), t.repos.contains(known.name) {
            throw TramaError("\(known.name) já faz parte desta trama")
        }
        let existing = try readCapsule(slug)
        if existing.openSuggestions.contains(where: { $0.to == stored }) {
            throw TramaError("\(stored) já foi sugerido e espera resposta")
        }
        let line = "- [ ] \(Timestamp.string()) · \(stored) · \(author): \(why)"
        try editCapsule(slug) { CapsuleDoc.insert($0, section: CapsuleSection.suggestions, line: line) }
        guard let item = try readCapsule(slug).suggestions.last(where: { $0.raw == line }) else {
            throw TramaError("não consegui registrar a sugestão")
        }
        return item
    }

    private func suggestionTarget(_ target: String) throws -> String {
        let key = target.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw TramaError("informe o repositório") }
        if let r = try? repo(key) { return r.name }
        let looksLikePath = key.hasPrefix("/") || key.hasPrefix("~") || key.hasPrefix(".") || key.contains("/")
        guard looksLikePath else {
            throw TramaError("não conheço “\(key)” · use o nome de um repositório cadastrado (`trama repo ls`) ou a pasta dele")
        }
        let a = Paths.absolute(key)
        guard let top = try? Git.toplevel(a), !top.isEmpty else {
            throw TramaError("\(Paths.abbreviate(a)) não é um repositório git")
        }
        let clean = Paths.clean(top)
        if let known = config.repos.first(where: { Paths.real($0.path) == Paths.real(clean) }) {
            return known.name
        }
        return Paths.abbreviate(clean)
    }

    public func acceptSuggestion(_ slug: String, number n: Int, noFetch: Bool = false) throws -> (trama: Trama, warnings: [Warning]) {
        let item = try openSuggestion(slug, n)
        let target = item.to ?? ""
        var name = target
        if (try? repo(target)) == nil {
            name = try addRepo(target).name
        }
        let result = try pullRepos(slug, [name], noFetch: noFetch)
        try resolveSuggestion(slug, n, mark: "x")
        try? addJournal(slug, "\(name) incluído a pedido de \(item.author ?? "agente"): \(item.text)")
        return result
    }

    public func dismissSuggestion(_ slug: String, number n: Int) throws {
        _ = try openSuggestion(slug, n)
        try resolveSuggestion(slug, n, mark: "-")
    }

    private func openSuggestion(_ slug: String, _ n: Int) throws -> CapsuleItem {
        guard let item = try readCapsule(slug).openSuggestions.first(where: { $0.index == n }) else {
            throw TramaError("não há sugestão aberta com o número \(n)")
        }
        return item
    }

    private func resolveSuggestion(_ slug: String, _ n: Int, mark: String) throws {
        try editCapsule(slug) { doc in
            var lines = CapsuleDoc.split(doc)
            guard let s = CapsuleDoc.section(lines, CapsuleSection.suggestions) else {
                throw TramaError("não há sugestão aberta com o número \(n)")
            }
            var seen = 0
            for i in (s.start + 1)..<s.end where lines[i].hasPrefix("- ") {
                seen += 1
                if seen == n, lines[i].hasPrefix("- [ ] ") {
                    lines[i] = "- [\(mark)] " + lines[i].dropFirst(6)
                    return CapsuleDoc.join(lines)
                }
            }
            throw TramaError("não há sugestão aberta com o número \(n)")
        }
    }

    public func discoverRepos() -> [DiscoveredRepo] {
        let known = Set(config.repos.map { Paths.real($0.path) })
        let treeRoot = Paths.real(root)
        var found: [String: DiscoveredRepo] = [:]
        let parents = Set(config.repos.map { Paths.parent($0.path) })
        for parent in parents {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = Paths.join(parent, name)
                let real = Paths.real(path)
                guard !known.contains(real), real != treeRoot, !real.hasPrefix(treeRoot + "/"),
                      Paths.isDirectory(Paths.join(path, ".git")) else { continue }
                found[real] = DiscoveredRepo(name: name, path: Paths.abbreviate(path))
            }
        }
        return found.values.sorted { $0.name < $1.name }
    }
}
