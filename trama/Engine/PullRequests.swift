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

enum GH {
    static var executable: String? {
        if let v = ProcessInfo.processInfo.environment["TRAMA_GH"], !v.isEmpty { return v }
        return ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func execute(_ dir: String, _ args: [String], timeout: TimeInterval = 60) -> GitResult {
        guard let exe = executable else {
            return GitResult(output: "", error: "não encontrei o `gh` · instale com `brew install gh` e rode `gh auth login`", code: -1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        process.environment = env
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return GitResult(output: "", error: "não consegui executar o gh: \(error.localizedDescription)", code: -1)
        }
        let item = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        let errorBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.data = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        item.cancel()
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\n") { text.removeLast() }
        return GitResult(output: text, error: String(decoding: errorBox.data, as: UTF8.self), code: process.terminationStatus)
    }

    static func run(_ dir: String, _ args: [String]) throws -> String {
        let r = execute(dir, args)
        guard r.code == 0 else {
            let message = r.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TramaError("gh \(args.prefix(2).joined(separator: " ")): \(message.isEmpty ? "código \(r.code)" : message)")
        }
        return r.output
    }
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

    func pullRequestBody(_ t: Trama, capsule: TramaCapsule, links: [(repo: String, url: String)], current: String) -> String {
        var b = ""
        let goal = capsule.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        b += "## \(t.title)\n\n"
        if !goal.isEmpty { b += "**Objetivo.** \(goal)\n\n" }
        if let task = t.task, !task.isEmpty { b += "**Tarefa.** \(task)\n\n" }
        if !capsule.decisions.isEmpty {
            b += "### Decisões\n\n"
            for d in capsule.decisions { b += "- \(d.text)\n" }
            b += "\n"
        }
        if links.count > 1 {
            b += "---\n\n### PRs desta trama\n\nMerge nesta ordem:\n\n"
            for (i, l) in links.enumerated() {
                b += "\(i + 1). \(l.url)" + (l.repo == current ? " ← este PR" : "") + "\n"
            }
        }
        return b
    }

    @discardableResult
    public func openPullRequests(_ slug: String, draft: Bool = false) throws -> (trama: Trama, prs: [PullRequestInfo], warnings: [Warning]) {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        guard GH.executable != nil else {
            throw TramaError("não encontrei o `gh` · instale com `brew install gh` e rode `gh auth login`")
        }
        let capsule = (try? readCapsule(t.slug)) ?? TramaCapsule(trama: t.slug, path: "", exists: false)
        var warnings: [Warning] = []
        var opened: [(repo: String, url: String, dir: String)] = []
        var known = t.prs
        for r in mergeOrdered(t.repos) {
            let wt = worktreePath(t.slug, r.name)
            guard Paths.isDirectory(wt) else {
                warnings.append(Warning(repo: r.name, message: "worktree não encontrado"))
                continue
            }
            guard Git.hasOrigin(wt) else {
                warnings.append(Warning(repo: r.name, message: "não tem remoto origin"))
                continue
            }
            let base = base(for: t, r)
            let ahead = (try? Git.aheadBehind(wt, Git.baseRef(wt, base)).ahead) ?? 0
            guard ahead > 0 else {
                warnings.append(Warning(repo: r.name, message: "sem commits à frente de \(base) · não abri PR"))
                continue
            }
            if let lines = try? Git.statusLines(wt), !lines.isEmpty {
                warnings.append(Warning(repo: r.name, message: "\(lines.count) \(plural(lines.count, "arquivo", "arquivos")) não commitado(s) ficaram de fora do PR"))
            }
            do {
                try Git.run(wt, "push", "-u", "origin", t.branch)
                var url = known[r.name]
                if url == nil {
                    let r1 = GH.execute(wt, ["pr", "view", t.branch, "--json", "url", "--jq", ".url"])
                    if r1.code == 0, !r1.output.isEmpty { url = r1.output }
                }
                if url == nil {
                    var args = ["pr", "create", "--base", base, "--head", t.branch, "--title", t.title,
                                "--body", pullRequestBody(t, capsule: capsule, links: [], current: r.name)]
                    if draft { args.append("--draft") }
                    let out = try GH.run(wt, args)
                    url = out.split(separator: "\n").map(String.init).last { $0.hasPrefix("http") }
                }
                guard let url else { throw TramaError("o gh não devolveu o endereço do PR") }
                known[r.name] = url
                opened.append((r.name, url, wt))
            } catch {
                warnings.append(Warning(repo: r.name, message: errorMessage(error)))
            }
        }
        guard !opened.isEmpty else {
            throw TramaError(warnings.isEmpty ? "nenhum repositório com PR para abrir" : warnings.map { ($0.repo.map { "\($0): " } ?? "") + $0.message }.joined(separator: "\n"))
        }
        let links = opened.map { (repo: $0.repo, url: $0.url) }
        for o in opened {
            let body = pullRequestBody(t, capsule: capsule, links: links, current: o.repo)
            do {
                try GH.run(o.dir, ["pr", "edit", o.url, "--body", body])
            } catch {
                warnings.append(Warning(repo: o.repo, message: "não consegui ligar os PRs: \(errorMessage(error))"))
            }
        }
        let saved = known
        let updated = try updateTrama(t.slug) { $0.prs = saved }
        try? addJournal(updated.slug, "PRs: " + opened.map { "\($0.repo) \($0.url)" }.joined(separator: " · "))
        return (updated, pullRequestInfos(updated), warnings)
    }

    public func pullRequestInfos(_ t: Trama) -> [PullRequestInfo] {
        let entries = mergeOrdered(t.repos).compactMap { r in t.prs[r.name].map { (r.name, $0) } }
        var out = [PullRequestInfo?](repeating: nil, count: entries.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let (name, url) = entries[i]
            var info = PullRequestInfo(repo: name, url: url, number: 0, state: "?", draft: false, ci: CIState.none)
            let r = GH.execute(root, ["pr", "view", url, "--json", "number,state,isDraft,statusCheckRollup"], timeout: 30)
            if r.code == 0,
               let json = try? JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any] {
                info.number = json["number"] as? Int ?? 0
                info.state = (json["state"] as? String ?? "?").lowercased()
                info.draft = json["isDraft"] as? Bool ?? false
                info.ci = ciState(json["statusCheckRollup"] as? [[String: Any]] ?? [])
            }
            lock.lock()
            out[i] = info
            lock.unlock()
        }
        return out.compactMap { $0 }
    }
}
