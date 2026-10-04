import Foundation

public enum ConflictSide: String, Sendable {
    case ours, theirs
}

public struct ConflictFile: Hashable, Identifiable, Sendable {
    public var path: String
    public var code: String

    public var id: String { path }
    public var canMerge: Bool { code == "UU" || code == "AA" }

    public var summary: String {
        switch code {
        case "AA": return "adicionado nos dois lados"
        case "DU": return "removido aqui, alterado lá"
        case "UD": return "alterado aqui, removido lá"
        case "AU": return "adicionado aqui"
        case "UA": return "adicionado lá"
        case "DD": return "removido nos dois lados"
        default: return "alterado nos dois lados"
        }
    }
}

public struct ConflictState: Sendable {
    public var merging: Bool
    public var current: String
    public var incoming: String
    public var files: [ConflictFile]
}

public struct ConflictHunk: Identifiable, Hashable, Sendable {
    public var id: Int
    public var ours: [String]
    public var theirs: [String]
    public var base: [String]?

    public var commonLines: Set<String> { Set(ours).intersection(theirs) }

    public func composed(ours pickedOurs: Set<Int>, theirs pickedTheirs: Set<Int>) -> [String] {
        let fromOurs = ours.enumerated().filter { pickedOurs.contains($0.offset) }.map(\.element)
        var seen = Set(fromOurs)
        var out = fromOurs
        for (i, line) in theirs.enumerated() where pickedTheirs.contains(i) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty || !seen.contains(line) {
                out.append(line)
                seen.insert(line)
            }
        }
        return out
    }
}

public struct ConflictPicks: Hashable, Sendable {
    public var ours: Set<Int> = []
    public var theirs: Set<Int> = []

    public var isEmpty: Bool { ours.isEmpty && theirs.isEmpty }

    public init(ours: Set<Int> = [], theirs: Set<Int> = []) {
        self.ours = ours
        self.theirs = theirs
    }

    public static func all(_ hunk: ConflictHunk, ours: Bool, theirs: Bool) -> ConflictPicks {
        ConflictPicks(ours: ours ? Set(hunk.ours.indices) : [], theirs: theirs ? Set(hunk.theirs.indices) : [])
    }

    public func resolution(for hunk: ConflictHunk) -> ConflictResolution? {
        if isEmpty { return nil }
        if self == .all(hunk, ours: true, theirs: false) { return .ours }
        if self == .all(hunk, ours: false, theirs: true) { return .theirs }
        return .custom(hunk.composed(ours: ours, theirs: theirs))
    }
}

public enum ConflictSegment: Identifiable, Hashable, Sendable {
    case context(id: Int, lines: [String])
    case hunk(ConflictHunk)

    public var id: Int {
        switch self {
        case .context(let id, _): return id
        case .hunk(let h): return h.id
        }
    }
}

public enum ConflictResolution: Hashable, Sendable {
    case ours, theirs, both, bothReversed
    case custom([String])

    public func lines(for hunk: ConflictHunk) -> [String] {
        switch self {
        case .ours: return hunk.ours
        case .theirs: return hunk.theirs
        case .both: return hunk.ours + hunk.theirs
        case .bothReversed: return hunk.theirs + hunk.ours
        case .custom(let lines): return lines
        }
    }
}

public struct ConflictDocument: Sendable {
    public var path: String
    public var segments: [ConflictSegment]
    public var oursLabel: String
    public var theirsLabel: String
    public var endsWithNewline: Bool

    public var hunks: [ConflictHunk] {
        segments.compactMap { if case .hunk(let h) = $0 { return h } else { return nil } }
    }

    public func render(_ resolutions: [Int: ConflictResolution]) throws -> String {
        var lines: [String] = []
        for segment in segments {
            switch segment {
            case .context(_, let l):
                lines += l
            case .hunk(let h):
                guard let r = resolutions[h.id] else { throw TramaError("ainda há trechos em conflito sem resolver") }
                lines += r.lines(for: h)
            }
        }
        return lines.joined(separator: "\n") + (endsWithNewline && !lines.isEmpty ? "\n" : "")
    }
}

enum ConflictParser {
    static func parse(path: String, text: String) throws -> ConflictDocument {
        var lines = text.components(separatedBy: "\n")
        let endsWithNewline = text.hasSuffix("\n")
        if endsWithNewline { lines.removeLast() }
        var segments: [ConflictSegment] = []
        var context: [String] = []
        var oursLabel = ""
        var theirsLabel = ""
        var nextId = 0

        func flush() {
            guard !context.isEmpty else { return }
            segments.append(.context(id: nextId, lines: context))
            nextId += 1
            context = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("<<<<<<< ") || line == "<<<<<<<" else {
                context.append(line)
                i += 1
                continue
            }
            var ours: [String] = []
            var base: [String]?
            var theirs: [String] = []
            var stage = 0
            var closed = false
            if oursLabel.isEmpty { oursLabel = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            i += 1
            while i < lines.count {
                let l = lines[i]
                i += 1
                if stage == 0, l.hasPrefix("||||||| ") || l == "|||||||" {
                    stage = 1
                    base = []
                } else if stage < 2, l == "=======" {
                    stage = 2
                } else if stage == 2, l.hasPrefix(">>>>>>> ") || l == ">>>>>>>" {
                    if theirsLabel.isEmpty { theirsLabel = String(l.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                    closed = true
                    break
                } else {
                    switch stage {
                    case 0: ours.append(l)
                    case 1: base?.append(l)
                    default: theirs.append(l)
                    }
                }
            }
            guard closed else { throw TramaError("os marcadores de conflito em \(path) estão incompletos · resolva esse arquivo no editor") }
            flush()
            segments.append(.hunk(ConflictHunk(id: nextId, ours: ours, theirs: theirs, base: base)))
            nextId += 1
        }
        flush()
        return ConflictDocument(path: path, segments: segments, oursLabel: oursLabel, theirsLabel: theirsLabel, endsWithNewline: endsWithNewline)
    }
}

extension Git {
    static func gitPath(_ dir: String, _ name: String) -> String? {
        guard let p = try? run(dir, "rev-parse", "--git-path", name), !p.isEmpty else { return nil }
        return p.hasPrefix("/") ? p : dir + "/" + p
    }

    static func isMerging(_ dir: String) -> Bool {
        guard let p = gitPath(dir, "MERGE_HEAD") else { return false }
        return Paths.exists(p)
    }

    static func incomingLabel(_ dir: String) -> String {
        guard let p = gitPath(dir, "MERGE_MSG"), let text = try? File.read(p) else { return "" }
        let first = text.components(separatedBy: "\n").first ?? ""
        let parts = first.components(separatedBy: "'")
        return parts.count >= 3 ? parts[1] : ""
    }

    static func conflictFiles(_ dir: String) -> [ConflictFile] {
        guard let raw = try? run(dir, "status", "--porcelain") else { return [] }
        let codes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        var out: [ConflictFile] = []
        for line in raw.split(separator: "\n") where line.count > 3 {
            let code = String(line.prefix(2))
            guard codes.contains(code) else { continue }
            var path = String(line.dropFirst(3))
            if path.hasPrefix("\""), path.hasSuffix("\"") { path = String(path.dropFirst().dropLast()) }
            out.append(ConflictFile(path: path, code: code))
        }
        return out.sorted { $0.path < $1.path }
    }

    static func hasStage(_ dir: String, _ path: String, _ stage: Int) -> Bool {
        guard let out = try? run(dir, "ls-files", "-u", "--", path) else { return false }
        return out.split(separator: "\n").contains { line in
            line.split(separator: "\t").first?.split(separator: " ").last == Substring(String(stage))
        }
    }
}

extension Workspace {
    func conflictWorktree(_ key: String, _ worktree: String) throws -> (repo: RepoConfig, path: String) {
        let r = try repo(key)
        guard let info = Git.listWorktrees(r.path).first(where: { !$0.bare && !$0.prunable && Paths.real($0.path) == Paths.real(worktree) }) else {
            throw TramaError("não achei esse worktree em \(r.name)")
        }
        return (r, info.path)
    }

    private func conflictedFile(_ dir: String, _ file: String) throws -> ConflictFile {
        guard let f = Git.conflictFiles(dir).first(where: { $0.path == file }) else {
            throw TramaError("\(file) não está mais em conflito")
        }
        return f
    }

    public func conflictState(repo key: String, worktree: String) throws -> ConflictState {
        let wt = try conflictWorktree(key, worktree).path
        return ConflictState(merging: Git.isMerging(wt), current: Git.currentBranchName(wt), incoming: Git.incomingLabel(wt), files: Git.conflictFiles(wt))
    }

    public func conflictDocument(repo key: String, worktree: String, file: String) throws -> ConflictDocument {
        let wt = try conflictWorktree(key, worktree).path
        let f = try conflictedFile(wt, file)
        guard f.canMerge else { throw TramaError("\(file): \(f.summary) · escolha a versão a manter") }
        guard let text = try File.read(wt + "/" + file) else {
            throw TramaError("não consegui ler \(file) como texto · escolha a versão a manter")
        }
        let document = try ConflictParser.parse(path: file, text: text)
        guard document.hunks.contains(where: { $0.base == nil }) else { return document }
        return fillConflictBase(document, worktree: wt, file: file)
    }

    public func saveResolution(repo key: String, worktree: String, file: String, content: String) throws {
        let wt = try conflictWorktree(key, worktree).path
        _ = try conflictedFile(wt, file)
        try File.write(content, to: wt + "/" + file)
        try Git.run(wt, "add", "--", file)
        clearConflictDraft(worktree: wt, file: file)
    }

    public func acceptSide(repo key: String, worktree: String, file: String, side: ConflictSide) throws {
        let wt = try conflictWorktree(key, worktree).path
        _ = try conflictedFile(wt, file)
        if Git.hasStage(wt, file, side == .ours ? 2 : 3) {
            try Git.run(wt, "checkout", "--\(side.rawValue)", "--", file)
            try Git.run(wt, "add", "--", file)
        } else {
            try Git.run(wt, "rm", "-q", "--", file)
        }
    }

    @discardableResult
    public func concludeMerge(repo key: String, worktree: String) throws -> String {
        let (r, wt) = try conflictWorktree(key, worktree)
        guard Git.isMerging(wt) else { throw TramaError("não há merge em andamento em \(r.name)") }
        let pending = Git.conflictFiles(wt).count
        guard pending == 0 else {
            throw TramaError("\(pending) \(plural(pending, "arquivo ainda está", "arquivos ainda estão")) em conflito")
        }
        let incoming = Git.incomingLabel(wt)
        try Git.run(wt, "commit", "--no-edit")
        journalMerge(wt, "merge de \(incoming.isEmpty ? "outra branch" : incoming) concluído em \(r.name) com conflitos resolvidos")
        return Git.lastCommit(wt)?.hash ?? ""
    }

    public func abortMerge(repo key: String, worktree: String) throws {
        let (r, wt) = try conflictWorktree(key, worktree)
        guard Git.isMerging(wt) else { throw TramaError("não há merge em andamento em \(r.name)") }
        try Git.run(wt, "merge", "--abort")
        journalMerge(wt, "merge abortado em \(r.name)")
    }

    private func journalMerge(_ wt: String, _ text: String) {
        if let t = try? tramas().first(where: { !$0.isArchived && wt.hasPrefix(tramaPath($0.slug) + "/") }) {
            try? addJournal(t.slug, text)
        }
    }
}
