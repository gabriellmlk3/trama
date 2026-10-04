import Foundation

public struct Commit: Codable, Hashable, Sendable {
    public var hash: String
    public var subject: String
    public var timestamp: Int64
    public var parents = 1

    public var isMerge: Bool { parents > 1 }

    public var mergedName: String? {
        guard isMerge else { return nil }
        if let open = subject.firstIndex(of: "'") {
            let rest = subject[subject.index(after: open)...]
            if let close = rest.firstIndex(of: "'") { return String(rest[..<close]) }
        }
        if let range = subject.range(of: " from ") {
            let name = subject[range.upperBound...].split(separator: " ").first
            return name.map(String.init)
        }
        return nil
    }

    public init(hash: String, subject: String, timestamp: Int64, parents: Int = 1) {
        self.hash = hash
        self.subject = subject
        self.timestamp = timestamp
        self.parents = parents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash)
        subject = try c.decode(String.self, forKey: .subject)
        timestamp = try c.decode(Int64.self, forKey: .timestamp)
        parents = try c.decodeIfPresent(Int.self, forKey: .parents) ?? 1
    }
}

public struct RepoStatus: Codable, Hashable, Identifiable, Sendable {
    public var repo: String
    public var alias: String
    public var label: String?
    public var path: String
    public var exists = false
    public var base: String
    public var branch = ""
    public var ahead = 0
    public var behind = 0
    public var changed = 0
    public var lastCommit: Commit?
    public var conflict: String?
    public var agents: [Agent] = []
    public var prep: String?
    public var prepLog: String?
    public var services: [ServiceStatus] = []
    public var error: String?

    public var id: String { repo }

    public var primaryAgent: Agent? {
        agents.first(where: { $0.isWaiting })
            ?? agents.first(where: { $0.isWorking })
            ?? agents.first
    }
}

@dynamicMemberLookup
public struct LiveTrama: Hashable, Identifiable, Encodable, Sendable {
    public var trama: Trama
    public var path: String
    public var capsule: String
    public var status: [RepoStatus]

    public var id: String { trama.slug }

    public subscript<T>(dynamicMember path: KeyPath<Trama, T>) -> T {
        trama[keyPath: path]
    }

    public func status(for repo: String) -> RepoStatus? {
        status.first(where: { $0.repo == repo })
    }

    public var conflicts: Int {
        status.filter { $0.conflict == "conflito" }.count
    }

    enum CodingKeys: String, CodingKey {
        case slug, title = "titulo", branch, base, repos, state = "estado", task = "tarefa", context = "contexto"
        case createdAt = "criadaEm", parkedAt = "estacionadaEm", updatedAt = "atualizadaEm"
        case path = "caminho", capsule = "capsula", status
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trama.slug, forKey: .slug)
        try c.encode(trama.title, forKey: .title)
        try c.encode(trama.branch, forKey: .branch)
        try c.encodeIfPresent(trama.base, forKey: .base)
        try c.encode(trama.repos, forKey: .repos)
        try c.encode(trama.state, forKey: .state)
        try c.encodeIfPresent(trama.task, forKey: .task)
        try c.encodeIfPresent(trama.context, forKey: .context)
        try c.encode(trama.createdAt, forKey: .createdAt)
        try c.encodeIfPresent(trama.parkedAt, forKey: .parkedAt)
        try c.encode(trama.updatedAt, forKey: .updatedAt)
        try c.encode(path, forKey: .path)
        try c.encode(capsule, forKey: .capsule)
        try c.encode(status, forKey: .status)
    }
}

public struct OverallState: Encodable, Sendable {
    public var root: String
    public var context: String?
    public var repos: [RepoConfig]
    public var tramas: [LiveTrama]
    public var agents: [Agent]
    public var generatedAt: Int64
}

extension Workspace {
    public func repoStatus(_ t: Trama, _ r: RepoConfig, predictConflict: Bool) -> RepoStatus {
        let wt = worktreePath(t.slug, r.name)
        var s = RepoStatus(repo: r.name, alias: r.alias, label: r.label, path: wt, base: base(for: t, r))
        guard Paths.isDirectory(wt) else {
            s.error = "worktree não encontrado"
            return s
        }
        s.exists = true
        s.prep = prepState(t.slug, r.name)
        if s.prep != nil { s.prepLog = prepLogPath(t.slug, r.name) }
        s.services = serviceStatuses(t, r)
        let ref = Git.baseRef(wt, s.base)
        do {
            let ab = try Git.aheadBehind(wt, ref)
            s.ahead = ab.ahead
            s.behind = ab.behind
        } catch {
            s.error = errorMessage(error)
        }
        if let lines = try? Git.statusLines(wt) {
            s.changed = lines.count
        }
        s.lastCommit = Git.lastCommit(wt)
        s.branch = Git.currentBranchName(wt)
        if predictConflict && s.behind > 0 {
            s.conflict = s.ahead == 0 ? "limpo" : Git.predictedConflict(wt, ref)
        }
        return s
    }

    public func tramaStatus(_ t: Trama, predictConflict: Bool) -> [RepoStatus] {
        let repos = t.repos
        var out = [RepoStatus?](repeating: nil, count: repos.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let name = repos[i]
            let s: RepoStatus
            if let r = try? repo(name) {
                s = repoStatus(t, r, predictConflict: predictConflict)
            } else {
                s = RepoStatus(repo: name, alias: name, path: worktreePath(t.slug, name), base: config.defaultBranch, error: "repositório não cadastrado")
            }
            lock.lock()
            out[i] = s
            lock.unlock()
        }
        return out.compactMap { $0 }
    }

    @discardableResult
    public func fetchAll() -> [Warning] {
        let repos = config.repos
        var warnings: [Warning] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let r = repos[i]
            do {
                try Git.fetchBase(r.path, r.base ?? config.defaultBranch)
                Git.fetchUpstream(r.path)
            } catch {
                lock.lock()
                warnings.append(Warning(repo: r.name, message: errorMessage(error)))
                lock.unlock()
            }
        }
        return warnings.sorted { ($0.repo ?? "") < ($1.repo ?? "") }
    }

    public func liveTrama(_ t: Trama, agents: [Agent], predictConflict: Bool = true) -> LiveTrama {
        var v = LiveTrama(trama: t, path: tramaPath(t.slug), capsule: capsulePath(t.slug), status: [])
        guard !t.isArchived else { return v }
        v.status = tramaStatus(t, predictConflict: predictConflict)
        for i in v.status.indices {
            v.status[i].agents = agents.filter { $0.trama == t.slug && $0.repo == v.status[i].repo }
        }
        return v
    }

    public func fullState(includeArchived: Bool = false) throws -> OverallState {
        assignMissingPortIndexes()
        let ts = try tramas().filter { includeArchived || !$0.isArchived }
        let ags = (try? agents()) ?? []
        var live = [LiveTrama?](repeating: nil, count: ts.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: ts.count) { i in
            let v = liveTrama(ts[i], agents: ags)
            lock.lock()
            live[i] = v
            lock.unlock()
        }
        return OverallState(
            root: root,
            context: config.context,
            repos: config.repos,
            tramas: live.compactMap { $0 }.sorted { $0.trama.createdAt < $1.trama.createdAt },
            agents: ags,
            generatedAt: nowUnix()
        )
    }
}
