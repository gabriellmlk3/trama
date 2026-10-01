import Foundation

extension Git {
    static func discardFiles(_ dir: String, _ changes: [FileChange]) throws {
        let tracked = changes.filter { !$0.untracked && refExists(dir, "HEAD") && execute(dir, ["cat-file", "-e", "HEAD:" + $0.path]).code == 0 }
        let trackedPaths = Set(tracked.map(\.path))
        let removable = changes.filter { !trackedPaths.contains($0.path) }
        if !tracked.isEmpty {
            try run(dir, ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + tracked.map(\.path))
        }
        for change in removable {
            if !change.untracked {
                _ = execute(dir, ["rm", "-r", "-f", "--cached", "--ignore-unmatch", "--", change.path])
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent(change.path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }
    }

    static func discardLines(_ dir: String, path: String, lines selected: Set<Int>) throws {
        let raw = execute(dir, ["diff", "HEAD", "--unified=3", "--", path]).output
        guard let patch = reversiblePatch(raw, selected: selected) else {
            throw TramaError("as linhas escolhidas não existem mais · recarregue e tente de novo")
        }
        let file = NSTemporaryDirectory() + "trama-discard-\(UUID().uuidString).patch"
        try patch.write(toFile: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: file) }
        try run(dir, ["apply", "-R", "--recount", "--whitespace=nowarn", file])
    }

    static func reversiblePatch(_ raw: String, selected: Set<Int>) -> String? {
        var header: [String] = []
        var hunks: [[String]] = []
        var current: [String] = []
        var touched = false
        var touchedHunks: [Bool] = []
        var id = 0
        var inHunk = false
        var keepMarker = false
        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                if inHunk { hunks.append(current); touchedHunks.append(touched) }
                inHunk = true
                touched = false
                current = [line]
                id += 1
                continue
            }
            guard inHunk else { header.append(line); continue }
            if line.hasPrefix("\\") {
                if keepMarker { current.append(line) }
                continue
            }
            let isSelected = selected.contains(id)
            id += 1
            if line.hasPrefix("+") {
                if isSelected {
                    current.append(line)
                    touched = true
                } else {
                    current.append(" " + line.dropFirst())
                }
                keepMarker = true
            } else if line.hasPrefix("-") {
                if isSelected {
                    current.append(line)
                    touched = true
                    keepMarker = true
                } else {
                    keepMarker = false
                }
            } else {
                current.append(line)
                keepMarker = true
            }
        }
        if inHunk { hunks.append(current); touchedHunks.append(touched) }
        let kept = zip(hunks, touchedHunks).filter { $0.1 }.map(\.0)
        guard !kept.isEmpty else { return nil }
        return (header + kept.flatMap { $0 }).joined(separator: "\n") + "\n"
    }
}

extension Workspace {
    private func discardWorktree(_ slug: String, repo name: String) throws -> String {
        let wt = worktreePath(slug, try repo(name).name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree não encontrado em \(Paths.abbreviate(wt))") }
        if Git.isMerging(wt) { throw TramaError("há um merge em andamento · resolva ou aborte o merge antes de descartar") }
        return wt
    }

    public func discardChanges(_ slug: String, repo name: String, paths: [String]) throws {
        let wt = try discardWorktree(slug, repo: name)
        guard !paths.isEmpty else { throw TramaError("escolha ao menos um arquivo para descartar") }
        let current = Git.fileChanges(wt)
        let chosen = Set(paths)
        let targets = current.filter { chosen.contains($0.path) }
        guard targets.count == chosen.count else { throw TramaError("a lista de arquivos mudou · recarregue e tente de novo") }
        try Git.discardFiles(wt, targets)
    }

    public func discardLines(_ slug: String, repo name: String, change: FileChange, lines: Set<Int>) throws {
        let wt = try discardWorktree(slug, repo: name)
        guard !lines.isEmpty else { throw TramaError("escolha ao menos uma linha para descartar") }
        guard !change.untracked else { throw TramaError("arquivo novo não tem linhas para descartar · descarte o arquivo inteiro") }
        try Git.discardLines(wt, path: change.path, lines: lines)
    }
}
