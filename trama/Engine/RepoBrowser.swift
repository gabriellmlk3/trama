import Foundation

public struct CheckoutStatus: Hashable, Sendable {
    public var branch = ""
    public var head = ""
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var changed = 0
    public var conflicts = 0

    public var detached: Bool { branch.isEmpty }
}

public struct RepoSnapshot: Hashable, Identifiable, Sendable {
    public var name: String
    public var alias: String
    public var path: String
    public var status: CheckoutStatus
    public var stashes: Int
    public var worktrees: Int
    public var error: String?

    public var id: String { name }
}

public struct CheckoutInfo: Hashable, Identifiable, Sendable {
    public var path: String
    public var branch: String
    public var isPrimary: Bool

    public var id: String { path }
}

public struct BranchInfo: Hashable, Identifiable, Sendable {
    public var name: String
    public var remote: Bool
    public var tip: String
    public var subject: String
    public var timestamp: Int64
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var upstreamGone = false
    public var current = false
    public var openAt: String?

    public var id: String { (remote ? "remote/" : "local/") + name }

    public var localName: String {
        guard remote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

public struct StashEntry: Hashable, Identifiable, Sendable {
    public var ref: String
    public var hash: String
    public var timestamp: Int64
    public var message: String

    public var id: String { hash }
}

public struct CommitDetail: Hashable, Sendable {
    public var hash: String
    public var short: String
    public var parents: [String]
    public var author: String
    public var email: String
    public var timestamp: Int64
    public var subject: String
    public var body: String
    public var changes: [FileChange]
}

public struct RepoBrowserState: Equatable, Sendable {
    public var repo: String
    public var checkout: String
    public var status: CheckoutStatus
    public var checkouts: [CheckoutInfo]
    public var commits: [GraphCommit]
    public var graph: [GraphRow]
    public var branches: [BranchInfo]
    public var stashes: [StashEntry]
    public var changes: [FileChange]
    public var merging: Bool
    public var hasRemote: Bool
    public var truncated: Bool
    public var loadedAt: Int64

    public var localBranches: [BranchInfo] { branches.filter { !$0.remote } }
    public var remoteBranches: [BranchInfo] { branches.filter(\.remote) }

    public func sameContent(as other: RepoBrowserState?) -> Bool {
        guard var other else { return false }
        other.loadedAt = loadedAt
        return self == other
    }
}

struct HistorySnapshot {
    var commits: [GraphCommit]
    var graph: [GraphRow]
}

final class HistoryCache: @unchecked Sendable {
    static let shared = HistoryCache()
    private let lock = NSLock()
    private var entries: [String: (signature: Int, snapshot: HistorySnapshot)] = [:]

    func snapshot(path: String, limit: Int, signature: Int, load: () -> [GraphCommit]) -> HistorySnapshot {
        let key = path + "\u{0}" + String(limit)
        lock.lock()
        let hit = entries[key]
        lock.unlock()
        if let hit, hit.signature == signature { return hit.snapshot }
        let commits = load()
        let fresh = HistorySnapshot(commits: commits, graph: CommitGraph.layout(commits))
        lock.lock()
        if entries.count >= 24, entries[key] == nil { entries.removeAll(keepingCapacity: true) }
        entries[key] = (signature, fresh)
        lock.unlock()
        return fresh
    }
}

private final class SnapshotSlots: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [RepoSnapshot?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ snapshot: RepoSnapshot) {
        lock.lock()
        slots[index] = snapshot
        lock.unlock()
    }

    var values: [RepoSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

extension Git {
    static func checkoutStatus(_ dir: String) -> CheckoutStatus {
        parseStatus(execute(dir, ["status", "--porcelain=v2", "--branch"]).output)
    }

    static func parseStatus(_ raw: String) -> CheckoutStatus {
        var s = CheckoutStatus()
        for line in raw.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let name = String(line.dropFirst(14))
                s.branch = name == "(detached)" ? "" : name
            } else if line.hasPrefix("# branch.oid ") {
                let oid = String(line.dropFirst(13))
                s.head = oid == "(initial)" ? "" : String(oid.prefix(7))
            } else if line.hasPrefix("# branch.upstream ") {
                s.upstream = String(line.dropFirst(18))
            } else if line.hasPrefix("# branch.ab ") {
                for token in line.dropFirst(12).split(separator: " ") {
                    if token.hasPrefix("+") { s.ahead = Int(token.dropFirst()) ?? 0 }
                    if token.hasPrefix("-") { s.behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("u ") {
                s.changed += 1
                s.conflicts += 1
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("? ") {
                s.changed += 1
            }
        }
        return s
    }

    static func refSignature(_ dir: String) -> Int {
        let r = execute(dir, ["for-each-ref", "--format=%(objectname) %(refname)", "refs/heads", "refs/remotes", "refs/tags"])
        return r.code == 0 ? r.output.hashValue : Int.random(in: Int.min...Int.max)
    }

    static func stashes(_ dir: String) -> [StashEntry] {
        let r = execute(dir, ["stash", "list", "--format=%gd%x1f%H%x1f%ct%x1f%gs"])
        guard r.code == 0 else { return [] }
        return r.output.split(separator: "\n").compactMap { line in
            let p = line.components(separatedBy: fieldSeparator)
            guard p.count >= 4 else { return nil }
            return StashEntry(ref: p[0], hash: p[1], timestamp: Int64(p[2]) ?? 0, message: p[3...].joined(separator: fieldSeparator))
        }
    }

    static func branches(_ dir: String, current: String, worktrees: [WorktreeInfo], checkout: String) -> [BranchInfo] {
        let format = ["%(refname)", "%(objectname:short)", "%(upstream:short)", "%(upstream:track,nobracket)", "%(committerdate:unix)", "%(contents:subject)"].joined(separator: "%1f")
        guard let out = try? run(dir, "for-each-ref", "--format=" + format, "refs/heads", "refs/remotes") else { return [] }
        var openAt: [String: String] = [:]
        for w in worktrees where !w.branch.isEmpty && !w.prunable && Paths.real(w.path) != Paths.real(checkout) {
            openAt[w.branch] = w.path
        }
        let list = out.split(separator: "\n").compactMap { line -> BranchInfo? in
            let p = line.components(separatedBy: fieldSeparator)
            guard p.count >= 6, !p[0].hasSuffix("/HEAD") else { return nil }
            let remote = p[0].hasPrefix("refs/remotes/")
            let name = shortRefName(p[0])
            var info = BranchInfo(name: name, remote: remote, tip: p[1], subject: p[5...].joined(separator: fieldSeparator), timestamp: Int64(p[4]) ?? 0)
            if !remote {
                info.upstream = p[2].isEmpty ? nil : p[2]
                let track = parseTrack(p[3])
                info.ahead = track.ahead
                info.behind = track.behind
                info.upstreamGone = track.gone
                info.current = name == current
                info.openAt = openAt[name]
            }
            return info
        }
        return list.sorted { a, b in
            if a.current != b.current { return a.current }
            return a.timestamp > b.timestamp
        }
    }

    static func parseTrack(_ raw: String) -> (ahead: Int, behind: Int, gone: Bool) {
        if raw == "gone" { return (0, 0, true) }
        var ahead = 0
        var behind = 0
        for part in raw.components(separatedBy: ", ") {
            let words = part.split(separator: " ")
            guard words.count == 2, let n = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = n }
            if words[0] == "behind" { behind = n }
        }
        return (ahead, behind, false)
    }

    static func emptyTree(_ dir: String) -> String {
        let r = execute(dir, ["hash-object", "-t", "tree", "/dev/null"])
        let hash = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.code == 0 && !hash.isEmpty ? hash : "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    }

    static func isValidBranchName(_ dir: String, _ name: String) -> Bool {
        !name.hasPrefix("-") && execute(dir, ["check-ref-format", "--branch", name]).code == 0
    }

    static func isCommitHash(_ value: String) -> Bool {
        value.count >= 4 && value.count <= 64 && value.allSatisfy { $0.isHexDigit }
    }
}

extension Workspace {
    public func repoSnapshots() -> [RepoSnapshot] {
        let repos = config.repos
        let results = SnapshotSlots(count: repos.count)
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            results.set(i, Self.snapshot(repos[i]))
        }
        return results.values
    }

    static func snapshot(_ r: RepoConfig) -> RepoSnapshot {
        guard Paths.isDirectory(r.path) else {
            return RepoSnapshot(name: r.name, alias: r.alias, path: r.path, status: CheckoutStatus(), stashes: 0, worktrees: 0, error: "pasta não encontrada")
        }
        var status = CheckoutStatus()
        var stashes = 0
        var worktrees = 0
        runConcurrently([
            { status = Git.checkoutStatus(r.path) },
            { stashes = Git.stashes(r.path).count },
            { worktrees = Git.listWorktrees(r.path).filter { !$0.bare && !$0.prunable }.count }
        ])
        return RepoSnapshot(name: r.name, alias: r.alias, path: r.path, status: status, stashes: stashes, worktrees: worktrees)
    }

    func browserCheckout(_ key: String, _ checkout: String?) throws -> (repo: RepoConfig, path: String) {
        let r = try repo(key)
        guard Paths.isDirectory(r.path) else { throw TramaError("\(r.name): pasta não encontrada em \(Paths.abbreviate(r.path))") }
        guard let checkout, !checkout.isEmpty, Paths.real(checkout) != Paths.real(r.path) else { return (r, r.path) }
        return (r, try matchingCheckout(r, checkout, Git.listWorktrees(r.path)))
    }

    private func matchingCheckout(_ r: RepoConfig, _ checkout: String, _ worktrees: [Git.WorktreeInfo]) throws -> String {
        guard let match = worktrees.first(where: { !$0.prunable && !$0.bare && Paths.real($0.path) == Paths.real(checkout) }) else {
            throw TramaError("\(Paths.abbreviate(checkout)) não é um checkout de \(r.name)")
        }
        return match.path
    }

    public func repoBrowser(_ key: String, checkout: String? = nil, limit: Int = 400) throws -> RepoBrowserState {
        let r = try repo(key)
        guard Paths.isDirectory(r.path) else { throw TramaError("\(r.name): pasta não encontrada em \(Paths.abbreviate(r.path))") }
        let worktrees = Git.listWorktrees(r.path).filter { !$0.bare && !$0.prunable }
        var path = r.path
        if let checkout, !checkout.isEmpty, Paths.real(checkout) != Paths.real(r.path) {
            path = try matchingCheckout(r, checkout, worktrees)
        }

        var status = CheckoutStatus()
        var signature = 0
        var stashes: [StashEntry] = []
        var changes: [FileChange] = []
        var merging = false
        var hasRemote = false
        runConcurrently([
            { status = Git.checkoutStatus(path) },
            { signature = Git.refSignature(path) },
            { stashes = Git.stashes(path) },
            { changes = Git.fileChanges(path) },
            { merging = Git.isMerging(path) },
            { hasRemote = !((try? Git.run(path, "remote")) ?? "").isEmpty }
        ])

        var history = HistorySnapshot(commits: [], graph: [])
        var branches: [BranchInfo] = []
        runConcurrently([
            { history = HistoryCache.shared.snapshot(path: path, limit: limit, signature: Self.historySignature(status, signature)) {
                Git.history(path, limit: limit, hasHead: !status.head.isEmpty)
            } },
            { branches = Git.branches(path, current: status.branch, worktrees: worktrees, checkout: path) }
        ])

        let checkouts = worktrees.map { CheckoutInfo(path: $0.path, branch: $0.branch, isPrimary: Paths.real($0.path) == Paths.real(r.path)) }
        return RepoBrowserState(
            repo: r.name,
            checkout: checkouts.first { Paths.real($0.path) == Paths.real(path) }?.path ?? path,
            status: status,
            checkouts: checkouts,
            commits: history.commits,
            graph: history.graph,
            branches: branches,
            stashes: stashes,
            changes: changes,
            merging: merging,
            hasRemote: hasRemote,
            truncated: history.commits.count >= limit,
            loadedAt: nowUnix()
        )
    }

    private static func historySignature(_ status: CheckoutStatus, _ refs: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(status.branch)
        hasher.combine(status.head)
        hasher.combine(refs)
        return hasher.finalize()
    }

    public func commitDetail(_ key: String, hash: String) throws -> CommitDetail {
        let r = try repo(key)
        guard Git.isCommitHash(hash), Git.refExists(r.path, hash) else { throw TramaError("commit \(hash) não encontrado em \(r.name)") }
        let format = ["%H", "%h", "%P", "%an", "%ae", "%ct", "%s", "%b"].joined(separator: "%x1f")
        let out = try Git.run(r.path, "show", "-s", "--format=" + format, hash)
        let p = out.components(separatedBy: Git.fieldSeparator)
        guard p.count >= 8 else { throw TramaError("não consegui ler o commit \(hash)") }
        let parents = p[2].split(separator: " ").map(String.init)
        let base = parents.first ?? Git.emptyTree(r.path)
        return CommitDetail(
            hash: p[0],
            short: p[1],
            parents: parents,
            author: p[3],
            email: p[4],
            timestamp: Int64(p[5]) ?? 0,
            subject: p[6],
            body: p[7...].joined(separator: Git.fieldSeparator).trimmingCharacters(in: .whitespacesAndNewlines),
            changes: Git.diffChanges(r.path, [base, p[0]])
        )
    }

    public func commitFileDiff(_ key: String, detail: CommitDetail, path: String) throws -> [DiffLine] {
        let r = try repo(key)
        let base = detail.parents.first ?? Git.emptyTree(r.path)
        return Git.revisionDiff(r.path, [base, detail.hash], path: path)
    }

    public func checkoutFileDiff(_ key: String, checkout: String, change: FileChange) throws -> [DiffLine] {
        let path = try browserCheckout(key, checkout).path
        return Git.fileDiff(path, change.path, untracked: change.untracked)
    }

    public func fetchRepo(_ key: String) throws -> String {
        let r = try repo(key)
        guard !((try? Git.run(r.path, "remote")) ?? "").isEmpty else { throw TramaError("\(r.name) não tem remoto") }
        let fetched = Git.execute(r.path, ["fetch", "--all", "--prune", "--quiet"], timeout: 120)
        guard fetched.code == 0 else { throw GitError(args: ["fetch", "--all", "--prune"], code: fetched.code, stderr: fetched.error) }
        return "remotos atualizados"
    }

    public func pullCheckout(_ key: String, checkout: String) throws -> String {
        let (r, path) = try browserCheckout(key, checkout)
        let status = Git.checkoutStatus(path)
        guard !status.detached else { throw TramaError("HEAD solto · troque para uma branch antes de puxar") }
        guard status.upstream != nil else { throw TramaError("\(status.branch) não acompanha nenhuma branch remota · use Enviar para publicá-la") }
        return try syncWorktree(repo: r.name, worktree: path, pull: true)
    }

    public func pushCheckout(_ key: String, checkout: String) throws -> String {
        let path = try browserCheckout(key, checkout).path
        let status = Git.checkoutStatus(path)
        guard !status.detached else { throw TramaError("HEAD solto · troque para uma branch antes de enviar") }
        guard Git.hasOrigin(path) else { throw TramaError("sem remoto origin para enviar") }
        if status.upstream == nil {
            let pushed = Git.execute(path, ["push", "--quiet", "-u", "origin", status.branch], timeout: 120)
            guard pushed.code == 0 else { throw GitError(args: ["push", "-u", "origin", status.branch], code: pushed.code, stderr: pushed.error) }
            return "\(status.branch) publicada em origin"
        }
        guard status.ahead > 0 else { return "\(status.branch) não tem commits para enviar" }
        let pushed = Git.execute(path, ["push", "--quiet"], timeout: 120)
        guard pushed.code == 0 else { throw GitError(args: ["push"], code: pushed.code, stderr: pushed.error) }
        return "\(status.ahead) \(plural(status.ahead, "commit enviado", "commits enviados")) de \(status.branch)"
    }

    public func switchBranch(_ key: String, checkout: String, branch: String, remote: Bool) throws -> String {
        let (r, path) = try browserCheckout(key, checkout)
        guard !branch.hasPrefix("-"), !branch.isEmpty else { throw TramaError("nome de branch inválido") }
        if Git.isMerging(path) { throw TramaError("há um merge em andamento · conclua ou aborte antes de trocar de branch") }
        var local = branch
        var args = ["switch", "--quiet", branch]
        if remote {
            guard Git.refExists(path, "refs/remotes/" + branch), let slash = branch.firstIndex(of: "/") else {
                throw TramaError("\(branch) não existe no remoto")
            }
            local = String(branch[branch.index(after: slash)...])
            args = Git.branchExists(path, local) ? ["switch", "--quiet", local] : ["switch", "--quiet", "-c", local, "--track", branch]
        } else if !Git.branchExists(path, branch) {
            throw TramaError("a branch \(branch) não existe")
        }
        if let other = Git.listWorktrees(r.path).first(where: { $0.branch == local && !$0.prunable && Paths.real($0.path) != Paths.real(path) }) {
            throw TramaError("\(local) já está aberta em \(Paths.abbreviate(other.path)) · o git não deixa a mesma branch em dois checkouts")
        }
        let switched = Git.execute(path, args)
        guard switched.code == 0 else {
            if switched.error.contains("would be overwritten") {
                throw TramaError("as mudanças não commitadas conflitam com \(local) · guarde no stash ou commite antes de trocar")
            }
            throw GitError(args: args, code: switched.code, stderr: switched.error)
        }
        return "agora em \(local)"
    }

    public func createBranch(_ key: String, checkout: String, name: String, from start: String?, switchTo: Bool) throws -> String {
        let path = try browserCheckout(key, checkout).path
        let branch = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Git.isValidBranchName(path, branch) else { throw TramaError("“\(branch)” não é um nome de branch válido") }
        guard !Git.branchExists(path, branch) else { throw TramaError("a branch \(branch) já existe") }
        let origin = start.flatMap { $0.isEmpty ? nil : $0 }
        if let origin, origin.hasPrefix("-") || !Git.refExists(path, origin) { throw TramaError("\(origin) não existe") }
        if switchTo, Git.isMerging(path) { throw TramaError("há um merge em andamento · conclua ou aborte antes de trocar de branch") }
        let args = switchTo ? ["switch", "--quiet", "--no-track", "-c", branch] + (origin.map { [$0] } ?? []) : ["branch", "--no-track", branch, origin ?? "HEAD"]
        let made = Git.execute(path, args)
        guard made.code == 0 else {
            if made.error.contains("would be overwritten") {
                throw TramaError("as mudanças não commitadas conflitam com o ponto de partida · guarde no stash ou commite antes")
            }
            throw GitError(args: args, code: made.code, stderr: made.error)
        }
        return switchTo ? "branch \(branch) criada · agora em \(branch)" : "branch \(branch) criada"
    }

    public func deleteBranch(_ key: String, name: String) throws -> String {
        let r = try repo(key)
        guard !name.hasPrefix("-"), Git.branchExists(r.path, name) else { throw TramaError("a branch \(name) não existe") }
        if let open = Git.listWorktrees(r.path).first(where: { $0.branch == name && !$0.prunable }) {
            throw TramaError("\(name) está aberta em \(Paths.abbreviate(open.path)) · troque de branch lá antes de apagar")
        }
        if let owner = try tramas().first(where: { $0.branch == name && !$0.isArchived && $0.repos.contains(r.name) }) {
            throw TramaError("\(name) é a branch da trama “\(owner.title)” · arquive a trama em vez de apagar a branch")
        }
        let deleted = Git.execute(r.path, ["branch", "-d", name])
        guard deleted.code == 0 else {
            if deleted.error.contains("not fully merged") {
                throw TramaError("\(name) tem commits que não estão em nenhuma outra branch · o Trama não apaga para não perder trabalho")
            }
            throw GitError(args: ["branch", "-d", name], code: deleted.code, stderr: deleted.error)
        }
        return "branch \(name) apagada"
    }

    public func saveStash(_ key: String, checkout: String, message: String) throws -> String {
        let path = try browserCheckout(key, checkout).path
        guard Git.checkoutStatus(path).changed > 0 else { throw TramaError("não há mudanças para guardar") }
        if Git.isMerging(path) { throw TramaError("há um merge em andamento · conclua ou aborte antes de guardar no stash") }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = ["stash", "push", "--quiet", "--include-untracked"] + (text.isEmpty ? [] : ["-m", text])
        try Git.run(path, args)
        return "mudanças guardadas no stash"
    }

    func stashRef(_ dir: String, hash: String) throws -> String {
        guard let entry = Git.stashes(dir).first(where: { $0.hash == hash }) else {
            throw TramaError("esse stash não existe mais · recarregue e tente de novo")
        }
        return entry.ref
    }

    public func applyStash(_ key: String, checkout: String, hash: String, drop: Bool) throws -> String {
        let path = try browserCheckout(key, checkout).path
        let ref = try stashRef(path, hash: hash)
        let args = ["stash", drop ? "pop" : "apply", "--quiet", ref]
        let applied = Git.execute(path, args)
        guard applied.code == 0 else {
            if !Git.conflictFiles(path).isEmpty {
                throw TramaError("o stash entrou com conflitos · resolva os arquivos marcados\(drop ? "; o stash foi mantido" : "")")
            }
            throw GitError(args: args, code: applied.code, stderr: applied.error)
        }
        return drop ? "stash aplicado e removido" : "stash aplicado"
    }

    public func dropStash(_ key: String, hash: String) throws -> String {
        let r = try repo(key)
        let ref = try stashRef(r.path, hash: hash)
        try Git.run(r.path, "stash", "drop", "--quiet", ref)
        return "stash apagado"
    }

    @discardableResult
    public func commitCheckout(_ key: String, checkout: String, paths: [String], message: String) throws -> Commit {
        try Git.commitPaths(try browserCheckout(key, checkout).path, paths: paths, message: message)
    }

    public func discardInCheckout(_ key: String, checkout: String, paths: [String]) throws {
        let path = try browserCheckout(key, checkout).path
        if Git.isMerging(path) { throw TramaError("há um merge em andamento · resolva ou aborte o merge antes de descartar") }
        guard !paths.isEmpty else { throw TramaError("escolha ao menos um arquivo para descartar") }
        let chosen = Set(paths)
        let targets = Git.fileChanges(path).filter { chosen.contains($0.path) }
        guard targets.count == chosen.count else { throw TramaError("a lista de arquivos mudou · recarregue e tente de novo") }
        try Git.discardFiles(path, targets)
    }

    public func discardLinesInCheckout(_ key: String, checkout: String, change: FileChange, lines: Set<Int>) throws {
        let path = try browserCheckout(key, checkout).path
        if Git.isMerging(path) { throw TramaError("há um merge em andamento · resolva ou aborte o merge antes de descartar") }
        guard !lines.isEmpty else { throw TramaError("escolha ao menos uma linha para descartar") }
        guard !change.untracked else { throw TramaError("arquivo novo não tem linhas para descartar · descarte o arquivo inteiro") }
        try Git.discardLines(path, path: change.path, lines: lines)
    }

    public func suggestCheckoutCommitMessage(_ key: String, checkout: String, paths: [String]?) throws -> String {
        let (r, path) = try browserCheckout(key, checkout)
        return try Self.suggestCommitMessage(in: path, name: r.name, paths: paths)
    }
}
