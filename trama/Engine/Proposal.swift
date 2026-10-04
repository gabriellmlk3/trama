import Foundation

public struct Proposal: Codable, Hashable, Sendable {
    public static let new = "nova"
    public static let existing = "existente"

    public var kind: String
    public var title: String
    public var trama: String?
    public var repos: [String]
    public var goal: String
    public var base: String?
    public var task: String?
    public var handoffRepo: String?
    public var handoffText: String?
    public var reason: String
    public var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case kind = "tipo", title = "titulo", trama, repos, goal = "objetivo", base, task = "tarefa"
        case handoffRepo = "handoffPara", handoffText = "handoffTexto", reason = "motivo", createdAt = "criadaEm"
    }

    public var isNew: Bool { kind == Proposal.new }
}

extension Workspace {
    private var proposalPath: String { Paths.join(stateDir, "proposta.json") }

    public func saveProposal(_ proposal: Proposal) throws {
        try File.write(try JSON.encoder().encode(proposal), to: proposalPath)
    }

    public func currentProposal() -> Proposal? {
        guard let text = (try? File.read(proposalPath)) ?? nil else { return nil }
        return try? JSONDecoder().decode(Proposal.self, from: Data(text.utf8))
    }

    public func clearProposal() {
        try? FileManager.default.removeItem(atPath: proposalPath)
    }

    public func proposeNew(title: String, repos: [String], goal: String, base: String?, task: String?, reason: String) throws -> Proposal {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TramaError("uso: trama propor nova \"Título\" --repos a,b --objetivo \"...\"") }
        let names = try canonicalRepos(repos)
        guard !names.isEmpty else { throw TramaError("a proposta precisa de ao menos um repositório (--repos a,b)") }
        let p = Proposal(kind: Proposal.new, title: name, trama: nil, repos: names, goal: goal, base: base, task: task,
                         handoffRepo: nil, handoffText: nil, reason: reason, createdAt: Int64(Date().timeIntervalSince1970))
        try saveProposal(p)
        return p
    }

    public func proposeExisting(slug: String, extraRepos: [String], handoffRepo: String?, handoffText: String?, reason: String) throws -> Proposal {
        let t = try trama(slug)
        let extra = try canonicalRepos(extraRepos).filter { !t.repos.contains($0) }
        var target: String?
        if let handoffRepo, !handoffRepo.isEmpty {
            target = try repo(handoffRepo).name
        }
        let text = handoffText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty, target == nil {
            throw TramaError("o handoff precisa de um repositório de destino (--para repo)")
        }
        let p = Proposal(kind: Proposal.existing, title: t.title, trama: t.slug, repos: extra, goal: "", base: nil, task: nil,
                         handoffRepo: target, handoffText: (text?.isEmpty ?? true) ? nil : text, reason: reason,
                         createdAt: Int64(Date().timeIntervalSince1970))
        try saveProposal(p)
        return p
    }

    public func approveExisting(_ p: Proposal) throws {
        guard let slug = p.trama else { throw TramaError("proposta sem trama de destino") }
        var t = try trama(slug)
        if t.isParked {
            t = try resume(slug, rebase: false).trama
        }
        let missing = p.repos.filter { !t.repos.contains($0) }
        if !missing.isEmpty {
            _ = try pullRepos(slug, missing)
        }
        if let to = p.handoffRepo, let text = p.handoffText {
            try addHandoff(slug, from: "", to: to, author: "agente geral", text)
        }
    }

    private func canonicalRepos(_ keys: [String]) throws -> [String] {
        var seen = Set<String>()
        return try keys.flatMap { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
            .map { try repo($0).name }
            .filter { seen.insert($0).inserted }
    }
}
