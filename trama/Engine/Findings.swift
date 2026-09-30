import Foundation

public enum FindingType {
    public static let editOnBase = "edicao_na_base"
    public static let forgottenChange = "mudanca_esquecida"
    public static let pendingHandoff = "handoff_pendente"
    public static let unpushed = "nao_enviado"
    public static let noRemote = "sem_remoto"
    public static let looseWorktree = "worktree_solto"
    public static let staleParked = "estacionada_parada"
    public static let merged = "integradas"

    static let priority: [String: Int] = [
        editOnBase: 0, forgottenChange: 1, pendingHandoff: 2, unpushed: 3,
        noRemote: 4, looseWorktree: 5, staleParked: 6, merged: 7,
    ]
}

public struct Finding: Codable, Hashable, Identifiable, Sendable {
    public var type: String
    public var repo: String?
    public var trama: String?
    public var title: String
    public var detail: String
    public var branch: String?
    public var path: String?
    public var count: Int?
    public var timestamp: Int64?
    public var items: [String]?
    public var suggestion: String?
    public var suggestedTrama: String?
    public var command: String?

    public var id: String {
        [type, repo ?? "", trama ?? "", branch ?? "", path ?? "", title].joined(separator: "|")
    }

    init(type: String, repo: String? = nil, trama: String? = nil, title: String, detail: String) {
        self.type = type
        self.repo = repo
        self.trama = trama
        self.title = title
        self.detail = detail
    }
}

private let reAhead = regex(#"ahead (\d+)"#)

extension Workspace {
    public func findings(now: Date = Date()) throws -> [Finding] {
        let ts = try tramas()
        let repos = config.repos
        var all: [Finding] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let list = findingsForRepo(repos[i], ts, now: now)
            lock.lock()
            all += list
            lock.unlock()
        }
        all += findingsForTramas(ts, now: now)
        return all.sorted { a, b in
            let pa = FindingType.priority[a.type] ?? 99
            let pb = FindingType.priority[b.type] ?? 99
            if pa != pb { return pa < pb }
            if (a.timestamp ?? 0) != (b.timestamp ?? 0) { return (a.timestamp ?? 0) > (b.timestamp ?? 0) }
            return a.id < b.id
        }
    }

    private func mostRecent(_ dir: String, _ lines: [String]) -> Int64 {
        var max: Int64 = 0
        for l in lines where l.count > 3 {
            var p = String(l.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let arrow = p.range(of: " -> ") { p = String(p[arrow.upperBound...]) }
            p = p.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let m = File.modificationDate(Paths.join(dir, p)), m > max { max = m }
        }
        return max
    }

    func findingsForRepo(_ r: RepoConfig, _ ts: [Trama], now: Date) -> [Finding] {
        var out: [Finding] = []
        let base = r.base ?? config.defaultBranch
        let ref = Git.baseRef(r.path, base)
        let current = Git.currentBranch(r.path)

        if let lines = try? Git.statusLines(r.path), !lines.isEmpty {
            let n = lines.count
            var a = Finding(
                type: current == base ? FindingType.editOnBase : FindingType.forgottenChange,
                repo: r.name,
                title: current == base ? "Edição feita direto na \(base)" : "\(n) \(plural(n, "arquivo não commitado", "arquivos não commitados"))",
                detail: "\(r.name) · \(current)"
            )
            a.branch = current
            a.path = r.path
            a.count = n
            a.timestamp = mostRecent(r.path, lines)
            let candidates = ts.filter { $0.isActive && $0.repos.contains(r.name) }
            if candidates.count == 1 {
                a.suggestion = "Pode ser da trama “\(candidates[0].title)”"
                a.suggestedTrama = candidates[0].slug
                a.command = "trama adotar \(r.alias) --para \(candidates[0].slug)"
            } else if candidates.count > 1 {
                a.suggestion = "Pode ser de uma destas tramas: " + candidates.map(\.title).joined(separator: ", ")
            } else {
                a.suggestion = "Nenhuma trama ativa cobre este repositório"
            }
            out.append(a)
        }

        let tramaBranches = Set(ts.filter { !$0.isArchived }.map(\.branch))
        let worktrees = Git.listWorktrees(r.path)
        var inUse: Set<String> = [current]
        for wt in worktrees where !wt.branch.isEmpty {
            inUse.insert(wt.branch)
        }

        var merged: [String] = []
        var lastMerged: Int64 = 0
        let format = "%(refname:short)%09%(upstream:short)%09%(upstream:track)%09%(committerdate:unix)"
        if let out2 = try? Git.run(r.path, "for-each-ref", "--format=" + format, "refs/heads") {
            for line in out2.components(separatedBy: "\n") {
                let p = line.components(separatedBy: "\t")
                guard p.count == 4, !p[0].isEmpty else { continue }
                let (name, upstream, track) = (p[0], p[1], p[2])
                let timestamp = Int64(p[3]) ?? 0
                if name == base || tramaBranches.contains(name) { continue }
                if !upstream.isEmpty && track.contains("ahead") && !track.contains("gone") {
                    let n = matchGroups(reAhead, track).flatMap { Int($0[1]) } ?? 0
                    var a = Finding(type: FindingType.unpushed, repo: r.name,
                                     title: "\(n) \(plural(n, "commit", "commits")) só na sua máquina",
                                     detail: "\(r.name) · \(name)")
                    a.branch = name
                    a.count = n
                    a.timestamp = timestamp
                    a.path = r.path
                    a.command = "git -C \(r.path) push origin \(name)"
                    out.append(a)
                    continue
                }
                if inUse.contains(name) { continue }
                if !upstream.isEmpty && !track.contains("gone") { continue }
                guard let unique = try? Git.countCommits(r.path, ref + ".." + name) else { continue }
                if unique == 0 {
                    merged.append(name)
                    lastMerged = max(lastMerged, timestamp)
                    continue
                }
                let days = Int(now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(timestamp))) / 86400)
                var a = Finding(type: FindingType.noRemote, repo: r.name,
                                 title: days >= 1 ? "Branch sem remoto há \(days) \(plural(days, "dia", "dias"))" : "Branch sem remoto",
                                 detail: "\(r.name) · \(name)")
                a.branch = name
                a.count = unique
                a.timestamp = timestamp
                a.path = r.path
                a.suggestion = "Tem \(unique) \(plural(unique, "commit que não existe", "commits que não existem")) em nenhum outro lugar"
                out.append(a)
            }
        }
        if !merged.isEmpty {
            merged.sort()
            let n = merged.count
            var a = Finding(type: FindingType.merged, repo: r.name,
                             title: "\(n) \(plural(n, "branch já integrada", "branches já integradas"))",
                             detail: "\(r.name) · já \(plural(n, "está", "estão")) na \(base)")
            a.count = n
            a.timestamp = lastMerged
            a.items = merged
            a.suggestion = "Nenhum commit exclusivo · dá para apagar sem perder nada"
            a.command = "trama limpar \(r.alias)"
            out.append(a)
        }

        let realRoot = Paths.real(root)
        for wt in worktrees where !wt.bare && Paths.real(wt.path) != Paths.real(r.path) {
            if let rel = Paths.relative(Paths.real(wt.path), within: realRoot),
               let slug = rel.split(separator: "/").first.map(String.init),
               ts.contains(where: { $0.slug == slug && !$0.isArchived }) {
                continue
            }
            var a = Finding(type: FindingType.looseWorktree, repo: r.name,
                             title: wt.prunable ? "Worktree quebrado (a pasta sumiu)" : "Worktree fora das tramas",
                             detail: "\(r.name) · \(Paths.abbreviate(wt.path))")
            a.branch = wt.branch.isEmpty ? nil : wt.branch
            a.path = wt.path
            if wt.prunable {
                a.command = "git -C \(r.path) worktree prune"
            } else {
                a.timestamp = File.modificationDate(wt.path)
            }
            out.append(a)
        }
        return out
    }

    func findingsForTramas(_ ts: [Trama], now: Date) -> [Finding] {
        var out: [Finding] = []
        for t in ts where !t.isArchived {
            if t.isParked, let at = t.parkedAt {
                let days = Int(now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(at))) / 86400)
                if days >= 7 {
                    let behind = tramaStatus(t, predictConflict: false).reduce(0) { $0 + $1.behind }
                    var a = Finding(type: FindingType.staleParked, trama: t.slug,
                                     title: "Trama estacionada há \(days) dias",
                                     detail: "\(t.title) · \(behind) \(plural(behind, "commit", "commits")) atrás da base")
                    a.timestamp = at
                    a.count = behind
                    a.command = "trama retomar \(t.slug) --rebase"
                    out.append(a)
                }
            }
            guard let c = try? readCapsule(t.slug), c.exists else { continue }
            for h in c.handoffs where !h.done {
                guard let q = h.timestamp, now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(q))) >= 86400 else { continue }
                var a = Finding(type: FindingType.pendingHandoff, repo: h.to, trama: t.slug,
                                 title: "Handoff sem resposta",
                                 detail: "\(h.from ?? "?") → \(h.to ?? "?") · \(t.title)")
                a.timestamp = q
                a.suggestion = truncate(h.text, 140)
                out.append(a)
            }
        }
        return out
    }

    public func adoptChanges(_ repoKey: String, into slug: String) throws {
        let r = try repo(repoKey)
        let t = try trama(slug)
        guard t.repos.contains(r.name) else {
            throw TramaError("\(r.name) não faz parte da trama “\(t.slug)” · use `trama puxar \(t.slug) \(r.alias)` antes")
        }
        let lines = try Git.statusLines(r.path)
        guard !lines.isEmpty else { throw TramaError("não há mudanças para adotar") }
        let wt = worktreePath(t.slug, r.name)
        guard Paths.exists(wt) else {
            throw TramaError("o worktree \(Paths.abbreviate(wt)) não existe")
        }
        let msg = "trama: adotado para \(t.slug)"
        try Git.run(r.path, "stash", "push", "--include-untracked", "-m", msg)
        do {
            try Git.run(wt, "stash", "pop")
        } catch {
            throw TramaError("guardei as mudanças no stash (“\(msg)”), mas não consegui aplicá-las na trama: \(errorMessage(error))")
        }
        try? addJournal(t.slug, "adotou \(lines.count) arquivo(s) esquecido(s) de \(r.name)")
    }

    public func cleanMerged(_ repoKey: String) throws -> [String] {
        let r = try repo(repoKey)
        let target = findingsForRepo(r, try tramas(), now: Date()).first(where: { $0.type == FindingType.merged })?.items ?? []
        let ref = Git.baseRef(r.path, r.base ?? config.defaultBranch)
        var deleted: [String] = []
        for b in target {
            guard let n = try? Git.countCommits(r.path, ref + ".." + b), n == 0 else { continue }
            if Git.execute(r.path, ["branch", "-D", b]).code == 0 {
                deleted.append(b)
            }
        }
        return deleted
    }
}
