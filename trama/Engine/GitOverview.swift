import Foundation

public struct FileChange: Hashable, Identifiable, Sendable {
    public var path: String
    public var code: String
    public var added: Int
    public var removed: Int
    public var untracked = false

    public var id: String { path }

    public var directory: String {
        let d = Paths.parent(path)
        return d == "." || d == "/" || d.isEmpty ? "" : d + "/"
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct WorktreeSummary: Hashable, Identifiable, Sendable {
    public var path: String
    public var branch: String
    public var changed: Int
    public var ahead: Int
    public var isPrimary: Bool
    public var conflicts = 0
    public var behindRemote = 0

    public var id: String { path }
}

public struct GitOverview: Sendable {
    public var branch: String
    public var head: Commit?
    public var base: String
    public var baseLabel: String
    public var baseTip: Commit?
    public var mergeBase: Commit?
    public var changes: [FileChange]
    public var ahead: [Commit]
    public var behind: [Commit]
    public var aheadCount: Int
    public var behindCount: Int
    public var pushed: Bool
    public var hasOrigin: Bool
    public var worktrees: [WorktreeSummary]
    public var merging = false
    public var conflicts = 0
    public var localBaseBehind = 0
    public var loadedAt: Int64

    public var added: Int { changes.reduce(0) { $0 + $1.added } }
    public var removed: Int { changes.reduce(0) { $0 + $1.removed } }
}

public enum DiffKind: Sendable {
    case hunk, context, added, removed
}

public struct DiffLine: Hashable, Identifiable, Sendable {
    public var id: Int
    public var kind: DiffKind
    public var oldNumber: Int?
    public var newNumber: Int?
    public var text: String
}

enum DiffParser {
    static func parse(_ raw: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var old = 0
        var new = 0
        var inHunk = false
        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                inHunk = true
                let numbers = hunkStart(line)
                old = numbers.old
                new = numbers.new
                lines.append(DiffLine(id: lines.count, kind: .hunk, oldNumber: nil, newNumber: nil, text: line))
                continue
            }
            guard inHunk else { continue }
            if line.hasPrefix("+") {
                lines.append(DiffLine(id: lines.count, kind: .added, oldNumber: nil, newNumber: new, text: String(line.dropFirst())))
                new += 1
            } else if line.hasPrefix("-") {
                lines.append(DiffLine(id: lines.count, kind: .removed, oldNumber: old, newNumber: nil, text: String(line.dropFirst())))
                old += 1
            } else if line.hasPrefix("\\") {
                continue
            } else {
                lines.append(DiffLine(id: lines.count, kind: .context, oldNumber: old, newNumber: new, text: line.isEmpty ? "" : String(line.dropFirst())))
                old += 1
                new += 1
            }
        }
        while let last = lines.last, last.kind == .context, last.text.isEmpty { lines.removeLast() }
        return lines
    }

    static func hunkStart(_ header: String) -> (old: Int, new: Int) {
        var old = 1
        var new = 1
        for token in header.split(separator: " ") {
            if token.hasPrefix("-"), let n = Int(token.dropFirst().split(separator: ",").first ?? "") {
                old = n
            } else if token.hasPrefix("+"), let n = Int(token.dropFirst().split(separator: ",").first ?? "") {
                new = n
            }
        }
        return (old, new)
    }
}

extension Git {
    static func commits(_ dir: String, _ range: String, limit: Int = 40) -> [Commit] {
        guard let out = try? run(dir, "log", "-\(limit)", "--format=%h%x1f%s%x1f%ct%x1f%P", range), !out.isEmpty else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let p = line.components(separatedBy: "\u{1f}")
            guard p.count == 4 else { return nil }
            return Commit(hash: p[0], subject: p[1], timestamp: Int64(p[2]) ?? 0, parents: max(1, p[3].split(separator: " ").count))
        }
    }

    static func commit(_ dir: String, _ ref: String) -> Commit? {
        commits(dir, ref, limit: 1).first
    }

    static func fileChanges(_ dir: String) -> [FileChange] {
        guard let raw = try? run(dir, "status", "--porcelain", "-uall") else { return [] }
        var numbers: [String: (Int, Int)] = [:]
        if let stat = try? run(dir, "diff", "HEAD", "--numstat") {
            for line in stat.split(separator: "\n") {
                let p = line.components(separatedBy: "\t")
                guard p.count == 3 else { continue }
                numbers[p[2]] = (Int(p[0]) ?? 0, Int(p[1]) ?? 0)
            }
        }
        var out: [FileChange] = []
        for line in raw.split(separator: "\n") where line.count > 3 {
            let status = String(line.prefix(2))
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            if path.hasPrefix("\""), path.hasSuffix("\"") { path = String(path.dropFirst().dropLast()) }
            var code = "M"
            if status == "??" || status.contains("A") { code = "N" }
            else if status.contains("D") { code = "D" }
            else if status.contains("R") { code = "R" }
            var counts = numbers[path] ?? (0, 0)
            if status == "??" { counts = (untrackedLines(dir + "/" + path), 0) }
            out.append(FileChange(path: path, code: code, added: counts.0, removed: counts.1, untracked: status == "??"))
        }
        return out.sorted { $0.path < $1.path }
    }

    static func untrackedLines(_ path: String) -> Int {
        guard let data = FileManager.default.contents(atPath: path), data.count < 1_000_000 else { return 0 }
        return String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).count - 1
    }

    static func fileDiff(_ dir: String, _ path: String, untracked: Bool) -> [DiffLine] {
        let r: GitResult
        if untracked {
            r = execute(dir, ["diff", "--no-index", "--unified=3", "--", "/dev/null", path])
        } else {
            r = execute(dir, ["diff", "HEAD", "--unified=3", "--", path])
        }
        return DiffParser.parse(r.output)
    }

    static func currentBranchName(_ dir: String) -> String {
        (try? run(dir, "symbolic-ref", "--quiet", "--short", "HEAD")) ?? ""
    }
}

extension Workspace {
    public func gitOverview(_ slug: String, repo name: String, compare: String? = nil) throws -> GitOverview {
        let t = try trama(slug)
        let r = try repo(name)
        let wt = worktreePath(slug, r.name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree não encontrado em \(Paths.abbreviate(wt))") }
        let base = base(for: t, r)
        let compare = compare.flatMap { Git.refExists(wt, $0) ? $0 : nil }
        let ref = compare ?? Git.baseRef(wt, base)
        let branch = Git.currentBranchName(wt)
        let ab = (try? Git.aheadBehind(wt, ref)) ?? (ahead: 0, behind: 0)
        let mergeBaseHash = (try? Git.run(wt, "merge-base", ref, "HEAD")) ?? ""
        let origin = Git.hasOrigin(wt)
        let pushed = !branch.isEmpty && Git.refExists(wt, "refs/remotes/origin/" + branch)
        return GitOverview(
            branch: branch,
            head: Git.lastCommit(wt),
            base: compare ?? base,
            baseLabel: ref,
            baseTip: Git.commit(wt, ref),
            mergeBase: mergeBaseHash.isEmpty ? nil : Git.commit(wt, mergeBaseHash),
            changes: Git.fileChanges(wt),
            ahead: Git.commits(wt, "\(ref)..HEAD"),
            behind: Git.commits(wt, "HEAD..\(ref)"),
            aheadCount: ab.ahead,
            behindCount: ab.behind,
            pushed: pushed,
            hasOrigin: origin,
            worktrees: worktreeSummaries(r, base: base),
            merging: Git.isMerging(wt),
            conflicts: Git.conflictFiles(wt).count,
            localBaseBehind: compare == nil ? Git.localBranchBehindOrigin(wt, base) : 0,
            loadedAt: nowUnix()
        )
    }

    public func fileDiff(_ slug: String, repo name: String, change: FileChange) throws -> [DiffLine] {
        let wt = worktreePath(slug, try repo(name).name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree não encontrado em \(Paths.abbreviate(wt))") }
        return Git.fileDiff(wt, change.path, untracked: change.untracked)
    }

    @discardableResult
    public func commitChanges(_ slug: String, repo name: String, paths: [String], message: String) throws -> Commit {
        let wt = worktreePath(slug, try repo(name).name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree não encontrado em \(Paths.abbreviate(wt))") }
        let subject = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { throw TramaError("escreva uma mensagem de commit") }
        guard !paths.isEmpty else { throw TramaError("escolha ao menos um arquivo para commitar") }
        let all = Set(Git.fileChanges(wt).map(\.path))
        let chosen = Set(paths)
        guard chosen.isSubset(of: all) else { throw TramaError("a lista de arquivos mudou · recarregue e tente de novo") }
        if chosen == all {
            try Git.run(wt, "add", "-A")
            try Git.run(wt, "commit", "--quiet", "-m", subject)
        } else {
            if Git.isMerging(wt) { throw TramaError("há um merge em andamento · o commit precisa incluir todos os arquivos") }
            let list = chosen.sorted()
            try Git.run(wt, ["add", "-A", "--"] + list)
            try Git.run(wt, ["commit", "--quiet", "-m", subject, "--"] + list)
        }
        guard let made = Git.lastCommit(wt) else { throw TramaError("o commit não foi criado") }
        return made
    }

    public func commitAll(_ slug: String, messages: [String: String]) -> [String: String] {
        var failures: [String: String] = [:]
        for (name, message) in messages {
            do {
                let wt = worktreePath(slug, try repo(name).name)
                let paths = Git.fileChanges(wt).map(\.path)
                try commitChanges(slug, repo: name, paths: paths, message: message)
            } catch {
                failures[name] = errorMessage(error)
            }
        }
        return failures
    }

    func worktreeSummaries(_ r: RepoConfig, base: String) -> [WorktreeSummary] {
        Git.listWorktrees(r.path).filter { !$0.bare && !$0.prunable }.map { info in
            let ref = Git.baseRef(info.path, base)
            let ahead = (try? Git.aheadBehind(info.path, ref).ahead) ?? 0
            let changed = (try? Git.statusLines(info.path).count) ?? 0
            return WorktreeSummary(
                path: info.path,
                branch: info.branch,
                changed: changed,
                ahead: ahead,
                isPrimary: Paths.real(info.path) == Paths.real(r.path),
                conflicts: Git.conflictFiles(info.path).count,
                behindRemote: Git.behindUpstream(info.path)
            )
        }
    }
}

public struct FindingChanges: Sendable {
    public var changes: [FileChange]
    public var commits: [Commit]
    public var commitCount: Int
    public var reference: String?
}

extension Git {
    static func rangeChanges(_ dir: String, from: String, to: String) -> [FileChange] {
        let range = "\(from)...\(to)"
        var codes: [String: String] = [:]
        if let names = try? run(dir, "diff", "--name-status", "--no-renames", range) {
            for line in names.split(separator: "\n") {
                let p = line.components(separatedBy: "\t")
                guard p.count == 2 else { continue }
                codes[p[1]] = p[0] == "A" ? "N" : (p[0] == "D" ? "D" : "M")
            }
        }
        guard let stat = try? run(dir, "diff", "--numstat", "--no-renames", range) else { return [] }
        var out: [FileChange] = []
        for line in stat.split(separator: "\n") {
            let p = line.components(separatedBy: "\t")
            guard p.count == 3 else { continue }
            out.append(FileChange(path: p[2], code: codes[p[2]] ?? "M", added: Int(p[0]) ?? 0, removed: Int(p[1]) ?? 0))
        }
        return out.sorted { $0.path < $1.path }
    }

    static func rangeDiff(_ dir: String, from: String, to: String, path: String) -> [DiffLine] {
        DiffParser.parse(execute(dir, ["diff", "--no-renames", "--unified=3", "\(from)...\(to)", "--", path]).output)
    }
}

extension Workspace {
    private enum FindingSource {
        case workingTree(String)
        case range(dir: String, from: String, to: String)
    }

    private func diffSource(_ f: Finding) -> FindingSource? {
        guard let dir = f.path, Paths.isDirectory(dir) else { return nil }
        switch f.type {
        case FindingType.editOnBase, FindingType.forgottenChange, FindingType.looseWorktree:
            return .workingTree(dir)
        case FindingType.unpushed:
            guard let b = f.branch else { return nil }
            return .range(dir: dir, from: b + "@{upstream}", to: b)
        case FindingType.noRemote:
            guard let b = f.branch, let name = f.repo, let r = try? repo(name) else { return nil }
            return .range(dir: dir, from: Git.baseRef(dir, r.base ?? config.defaultBranch), to: b)
        default:
            return nil
        }
    }

    public func findingChanges(_ f: Finding) throws -> FindingChanges {
        guard let source = diffSource(f) else { throw TramaError("este achado não tem diferenças para mostrar") }
        switch source {
        case .workingTree(let dir):
            return FindingChanges(changes: Git.fileChanges(dir), commits: [], commitCount: 0, reference: nil)
        case .range(let dir, let from, let to):
            let commits = Git.commits(dir, "\(from)..\(to)")
            let count = (try? Git.countCommits(dir, "\(from)..\(to)")) ?? commits.count
            return FindingChanges(changes: Git.rangeChanges(dir, from: from, to: to), commits: commits, commitCount: count, reference: from)
        }
    }

    public func findingFileDiff(_ f: Finding, change: FileChange) throws -> [DiffLine] {
        guard let source = diffSource(f) else { return [] }
        switch source {
        case .workingTree(let dir):
            return Git.fileDiff(dir, change.path, untracked: change.untracked)
        case .range(let dir, let from, let to):
            return Git.rangeDiff(dir, from: from, to: to, path: change.path)
        }
    }
}
