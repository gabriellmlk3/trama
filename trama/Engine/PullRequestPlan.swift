import Foundation

public struct ExistingPullRequest: Codable, Hashable, Sendable {
    public var url: String
    public var number: Int
    public var state: String
    public var base: String
    public var draft: Bool
}

public enum PullRequestAction: String, Codable, Sendable {
    case create
    case retarget
    case update
    case manual
    case blocked
}

public enum PullRequestBlocker: String, Codable, Sendable {
    case noWorktree
    case noRemote
    case missingTarget
    case nothingAhead
    case merged
    case closed
}

public struct PullRequestPlanRow: Codable, Hashable, Identifiable, Sendable {
    public var repo: String
    public var order: Int
    public var target: String
    public var targetExists: Bool
    public var ahead: Int
    public var conflictFiles: [String]?
    public var existing: ExistingPullRequest?
    public var blocker: PullRequestBlocker?
    public var provider: ProviderKind = .github
    public var automatic = true
    public var missingTool: String?

    public var id: String { repo }

    public var action: PullRequestAction {
        if blocker != nil { return .blocked }
        if !automatic { return .manual }
        guard let existing else { return .create }
        return existing.base.isEmpty || existing.base == target ? .update : .retarget
    }

    public var hasConflict: Bool { !(conflictFiles ?? []).isEmpty }

    public var summary: String {
        let number = existing?.number ?? 0
        switch action {
        case .create:
            return "novo PR"
        case .retarget:
            return "redirecionar o PR #\(number): \(existing?.base ?? "") → \(target)"
        case .update:
            return "atualizar o PR #\(number)"
        case .manual:
            return missingTool.map { "sem o \($0) · abrir pelo navegador" } ?? "abrir pelo navegador"
        case .blocked:
            switch blocker {
            case .noWorktree: return "worktree não encontrado"
            case .noRemote: return "não tem remoto origin"
            case .missingTarget: return "\(target) não existe no remoto"
            case .nothingAhead: return "nada a subir"
            case .merged: return "o PR #\(number) já foi mesclado"
            case .closed: return "o PR #\(number) está fechado"
            case nil: return ""
            }
        }
    }
}

public struct RemoteBranchOption: Hashable, Identifiable, Sendable {
    public var name: String
    public var repos: [String]
    public var isTrama: Bool

    public var id: String { name }
}

public struct RemoteBranchCatalog: Sendable {
    public var options: [RemoteBranchOption]
    public var warnings: [Warning]
}

extension Workspace {
    public func prTarget(for trama: Trama, _ r: RepoConfig) -> String {
        if let b = trama.prBases[r.name], !b.isEmpty { return b }
        return base(for: trama, r)
    }

    public func pullRequestTargets(_ slug: String) throws -> (saved: [String: String], defaults: [String: String]) {
        let t = try trama(slug)
        var saved: [String: String] = [:]
        var defaults: [String: String] = [:]
        for r in mergeOrdered(t.repos) {
            saved[r.name] = prTarget(for: t, r)
            defaults[r.name] = base(for: t, r)
        }
        return (saved, defaults)
    }

    public func remoteBranchCatalog(_ slug: String, fetch: Bool = false) throws -> RemoteBranchCatalog {
        let t = try trama(slug)
        let repos = mergeOrdered(t.repos)
        var names = [[String]](repeating: [], count: repos.count)
        var warnings: [Warning] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let wt = worktreePath(t.slug, repos[i].name)
            guard Paths.isDirectory(wt), Git.hasOrigin(wt) else { return }
            var failure: Warning?
            if fetch {
                let r = Git.execute(wt, ["fetch", "--prune", "--quiet", "origin"], timeout: 60)
                if r.code != 0 {
                    failure = Warning(repo: repos[i].name, message: "não consegui atualizar o remoto: " + firstLine(r.error))
                }
            }
            let list = Git.remoteBranches(wt)
            lock.lock()
            names[i] = list
            if let failure { warnings.append(failure) }
            lock.unlock()
        }
        var byName: [String: [String]] = [:]
        for (i, list) in names.enumerated() {
            for name in list where name != t.branch {
                byName[name, default: []].append(repos[i].name)
            }
        }
        let prefix = config.branchPrefix
        let options = byName
            .map { RemoteBranchOption(name: $0.key, repos: $0.value, isTrama: !prefix.isEmpty && $0.key.hasPrefix(prefix)) }
            .sorted { $0.repos.count != $1.repos.count ? $0.repos.count > $1.repos.count : $0.name < $1.name }
        return RemoteBranchCatalog(options: options, warnings: warnings)
    }

    public func existingPullRequests(_ slug: String) throws -> [String: ExistingPullRequest] {
        let t = try trama(slug)
        let repos = mergeOrdered(t.repos)
        var found = [ExistingPullRequest?](repeating: nil, count: repos.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let wt = worktreePath(t.slug, repos[i].name)
            guard Paths.isDirectory(wt), let provider = host(for: repos[i], dir: wt).automatic else { return }
            let info = provider.existing(wt, t.prs[repos[i].name] ?? t.branch)
            lock.lock()
            found[i] = info
            lock.unlock()
        }
        var out: [String: ExistingPullRequest] = [:]
        for (i, info) in found.enumerated() {
            if let info { out[repos[i].name] = info }
        }
        return out
    }

    public func pullRequestPlan(_ slug: String, targets: [String: String] = [:], existing: [String: ExistingPullRequest] = [:]) throws -> [PullRequestPlanRow] {
        let t = try trama(slug)
        let repos = mergeOrdered(t.repos)
        var rows = [PullRequestPlanRow?](repeating: nil, count: repos.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let r = repos[i]
            let row = planRow(t, r, order: i + 1, target: targets[r.name] ?? prTarget(for: t, r), existing: existing[r.name])
            lock.lock()
            rows[i] = row
            lock.unlock()
        }
        return rows.compactMap { $0 }
    }

    private func planRow(_ t: Trama, _ r: RepoConfig, order: Int, target: String, existing: ExistingPullRequest?) -> PullRequestPlanRow {
        var row = PullRequestPlanRow(repo: r.name, order: order, target: target, targetExists: false, ahead: 0, conflictFiles: nil, existing: existing, blocker: nil)
        let wt = worktreePath(t.slug, r.name)
        guard Paths.isDirectory(wt) else {
            row.blocker = .noWorktree
            row.provider = r.provider ?? .manual
            row.automatic = false
            return row
        }
        let host = self.host(for: r, dir: wt)
        row.provider = host.kind
        row.automatic = host.automatic != nil
        row.missingTool = host.missingTool?.name
        guard Git.hasOrigin(wt) else {
            row.blocker = .noRemote
            return row
        }
        row.targetExists = Git.refExists(wt, "refs/remotes/origin/" + target)
        guard row.targetExists else {
            row.blocker = .missingTarget
            return row
        }
        let ref = "origin/" + target
        row.ahead = (try? Git.aheadBehind(wt, ref).ahead) ?? 0
        if let existing, existing.state != "open" {
            row.blocker = existing.state == "merged" ? .merged : .closed
            return row
        }
        guard row.ahead > 0 else {
            row.blocker = .nothingAhead
            return row
        }
        row.conflictFiles = Git.predictedConflictFiles(wt, ref)
        return row
    }

    public func parsePullRequestTargets(_ spec: String, for t: Trama) throws -> [String: String] {
        var global: String?
        var overrides: [String: String] = [:]
        let items = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for item in items {
            if let equals = item.firstIndex(of: "=") {
                let key = String(item[..<equals]).trimmingCharacters(in: .whitespaces)
                let branch = String(item[item.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !branch.isEmpty else {
                    throw TramaError("use --base repo=branch (ex.: --base api=staging)")
                }
                let r = try repo(key)
                guard t.repos.contains(r.name) else {
                    throw TramaError("\(r.name) não faz parte da trama “\(t.slug)”")
                }
                overrides[r.name] = branch
            } else {
                global = item
            }
        }
        var targets: [String: String] = [:]
        if let global {
            for name in t.repos { targets[name] = global }
        }
        for (name, branch) in overrides { targets[name] = branch }
        return targets
    }
}
