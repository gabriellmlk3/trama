import Foundation

public enum CIState {
    public static let success = "sucesso"
    public static let failure = "falhou"
    public static let pending = "rodando"
    public static let none = "sem checks"
}

public struct PullRequestInfo: Codable, Hashable, Identifiable, Sendable {
    public var repo: String
    public var url: String
    public var number: Int
    public var state: String
    public var draft: Bool
    public var ci: String

    public var id: String { repo }
}

func ciState(_ rollup: [[String: Any]]) -> String {
    guard !rollup.isEmpty else { return CIState.none }
    let bad: Set<String> = ["FAILURE", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED", "ERROR"]
    let waiting: Set<String> = ["PENDING", "EXPECTED", "IN_PROGRESS", "QUEUED", "WAITING", "REQUESTED"]
    var pending = false
    for check in rollup {
        let conclusion = (check["conclusion"] as? String ?? "").uppercased()
        let status = (check["status"] as? String ?? "").uppercased()
        let state = (check["state"] as? String ?? "").uppercased()
        if bad.contains(conclusion) || bad.contains(state) { return CIState.failure }
        if waiting.contains(status) || waiting.contains(state) { pending = true }
    }
    return pending ? CIState.pending : CIState.success
}

public struct ManualPullRequest: Codable, Hashable, Identifiable, Sendable {
    public var repo: String
    public var provider: ProviderKind
    public var target: String
    public var url: String?

    public var id: String { repo }
}

private struct OpenedPullRequest {
    let repo: RepoConfig
    let url: String
    let dir: String
    let target: String
    let retargetedFrom: String?
    let provider: any PullRequestProvider
}

extension Workspace {
    public func mergeOrdered(_ names: [String]) -> [RepoConfig] {
        names.compactMap { try? repo($0) }.sorted { ($0.mergeRank, $0.name) < ($1.mergeRank, $1.name) }
    }

    @discardableResult
    public func setMergeRank(_ key: String, _ rank: Int) throws -> RepoConfig {
        var r = try repo(key)
        r.mergeRank = rank
        try replaceRepo(r)
        return r
    }

    func pullRequestBody(_ t: Trama, capsule: TramaCapsule, links: [(repo: String, url: String)], current: String, limit: Int = Int.max, title: String? = nil, summary: String = "") -> String {
        var head = ""
        let goal = capsule.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        head += "## \(title ?? t.title)\n\n"
        if !summary.isEmpty { head += "\(summary)\n\n" }
        if !goal.isEmpty { head += "**Objetivo.** \(goal)\n\n" }
        if let task = t.task, !task.isEmpty { head += "**Tarefa.** \(task)\n\n" }
        if !capsule.decisions.isEmpty {
            head += "### Decisões\n\n"
            for d in capsule.decisions { head += "- \(d.text)\n" }
            head += "\n"
        }
        var tail = ""
        if links.count > 1 {
            tail += "---\n\n### PRs desta trama\n\nMerge nesta ordem:\n\n"
            for (i, l) in links.enumerated() {
                tail += "\(i + 1). \(l.url)" + (l.repo == current ? " ← este PR" : "") + "\n"
            }
        }
        guard head.count + tail.count > limit else { return head + tail }
        let room = max(limit - tail.count - 3, 0)
        return String(head.prefix(room)).trimmingCharacters(in: .whitespacesAndNewlines) + "…\n\n" + tail
    }

    @discardableResult
    public func openPullRequests(_ slug: String, draft: Bool = false, targets: [String: String] = [:], only: Set<String>? = nil, title: String? = nil, summary: String = "") throws -> (trama: Trama, prs: [PullRequestInfo], warnings: [Warning], manual: [ManualPullRequest], opened: [String]) {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let capsule = (try? readCapsule(t.slug)) ?? TramaCapsule(trama: t.slug, path: "", exists: false)
        var warnings: [Warning] = []
        var opened: [OpenedPullRequest] = []
        var manual: [ManualPullRequest] = []
        var chosen: [(repo: RepoConfig, target: String)] = []
        var linked: [(repo: String, url: String)] = []
        var known = t.prs
        for r in mergeOrdered(t.repos) {
            if let only, !only.contains(r.name) { continue }
            let wt = worktreePath(t.slug, r.name)
            guard Paths.isDirectory(wt) else {
                warnings.append(Warning(repo: r.name, message: "worktree não encontrado"))
                continue
            }
            guard Git.hasOrigin(wt) else {
                warnings.append(Warning(repo: r.name, message: "não tem remoto origin"))
                continue
            }
            let target = targets[r.name] ?? prTarget(for: t, r)
            guard Git.ensureRemoteBranch(wt, target) else {
                warnings.append(Warning(repo: r.name, message: "o destino \(target) não existe no remoto · não abri PR"))
                continue
            }
            let ahead = (try? Git.aheadBehind(wt, Git.baseRef(wt, target)).ahead) ?? 0
            guard ahead > 0 else {
                warnings.append(Warning(repo: r.name, message: "sem commits à frente de \(target) · não abri PR"))
                continue
            }
            if let lines = try? Git.statusLines(wt), !lines.isEmpty {
                warnings.append(Warning(repo: r.name, message: "\(lines.count) \(plural(lines.count, "arquivo", "arquivos")) não commitado(s) ficaram de fora do PR"))
            }
            let host = self.host(for: r, dir: wt)
            do {
                guard let provider = host.automatic else {
                    try Git.run(wt, "push", "-u", "origin", t.branch)
                    if let tool = host.missingTool {
                        warnings.append(Warning(repo: r.name, message: "\(tool.missingMessage) · abra o PR pelo link"))
                    }
                    manual.append(ManualPullRequest(repo: r.name, provider: host.kind, target: target, url: host.newPullRequestURL(branch: t.branch, target: target)))
                    chosen.append((r, target))
                    continue
                }
                let knownURL = known[r.name]
                let current = provider.existing(wt, knownURL ?? t.branch)
                if let current, current.state != "open" {
                    known[r.name] = current.url
                    linked.append((r.name, current.url))
                    let reason = current.state == "merged" ? "já foi mesclado" : "está fechado"
                    warnings.append(Warning(repo: r.name, message: "o PR #\(current.number) \(reason) · não mexi nele"))
                    continue
                }
                try Git.run(wt, "push", "-u", "origin", t.branch)
                var retargetedFrom: String?
                if let current, !current.base.isEmpty, current.base != target {
                    try provider.retarget(wt, url: current.url, base: target)
                    retargetedFrom = current.base
                }
                let url: String
                if let existingURL = knownURL ?? current?.url {
                    url = existingURL
                } else {
                    let body = pullRequestBody(t, capsule: capsule, links: [], current: r.name, limit: provider.bodyLimit, title: title, summary: summary)
                    url = try provider.create(wt, head: t.branch, base: target, title: title ?? t.title, body: body, draft: draft)
                }
                known[r.name] = url
                linked.append((r.name, url))
                opened.append(OpenedPullRequest(repo: r, url: url, dir: wt, target: target, retargetedFrom: retargetedFrom, provider: provider))
                chosen.append((r, target))
            } catch {
                warnings.append(Warning(repo: r.name, message: errorMessage(error)))
            }
        }
        guard !opened.isEmpty || !manual.isEmpty else {
            throw TramaError(warnings.isEmpty ? "nenhum repositório com PR para abrir" : warnings.map { ($0.repo.map { "\($0): " } ?? "") + $0.message }.joined(separator: "\n"))
        }
        let links = linked
        for o in opened {
            let body = pullRequestBody(t, capsule: capsule, links: links, current: o.repo.name, limit: o.provider.bodyLimit, title: title, summary: summary)
            do {
                try o.provider.updateBody(o.dir, url: o.url, body: body)
            } catch {
                warnings.append(Warning(repo: o.repo.name, message: "não consegui ligar os PRs: \(errorMessage(error))"))
            }
        }
        var bases = t.prBases
        for c in chosen {
            if c.target == base(for: t, c.repo) {
                bases.removeValue(forKey: c.repo.name)
            } else {
                bases[c.repo.name] = c.target
            }
        }
        let savedPRs = known
        let savedBases = bases
        let updated = try updateTrama(t.slug) {
            $0.prs = savedPRs
            $0.prBases = savedBases
        }
        var lines = opened.map { o -> String in
            var line = "\(o.repo.name) \(o.url) → \(o.target)"
            if let from = o.retargetedFrom { line += " (antes \(from))" }
            return line
        }
        lines += manual.map { "\($0.repo) → \($0.target) (\($0.provider.title), pelo navegador)" }
        try? addJournal(updated.slug, "PRs: " + lines.joined(separator: " · "))
        return (updated, pullRequestInfos(updated), warnings, manual, opened.map { $0.repo.name })
    }

    @discardableResult
    public func forgetPullRequests(_ slug: String, repos: [String]) throws -> Trama {
        let updated = try updateTrama(slug) { t in
            for name in repos { t.prs.removeValue(forKey: name) }
        }
        try? addJournal(updated.slug, "PRs descartados da trama: " + repos.joined(separator: ", "))
        return updated
    }

    public func pullRequestInfos(_ t: Trama) -> [PullRequestInfo] {
        let entries = mergeOrdered(t.repos).compactMap { r in t.prs[r.name].map { (r, $0) } }
        var out = [PullRequestInfo?](repeating: nil, count: entries.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let (r, url) = entries[i]
            var info = PullRequestInfo(repo: r.name, url: url, number: 0, state: "?", draft: false, ci: CIState.none)
            let dir = Paths.isDirectory(r.path) ? r.path : root
            if let provider = host(for: r, dir: dir).automatic, let status = provider.status(dir, url: url) {
                info.number = status.number
                info.state = status.state
                info.draft = status.draft
                info.ci = status.ci
            }
            lock.lock()
            out[i] = info
            lock.unlock()
        }
        return out.compactMap { $0 }
    }
}
