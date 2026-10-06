import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PathReferences {
    private static let delimiters: Set<Character> = ["\"", "'", "`", ",", ";", "(", ")", "[", "]", "{", "}", "<", ">", "=", ":", "|"]

    private static func isDelimiter(_ c: Character) -> Bool {
        c.isWhitespace || delimiters.contains(c)
    }

    static func ranges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard !isDelimiter(text[i]) else {
                i = text.index(after: i)
                continue
            }
            var j = i
            while j < text.endIndex, !isDelimiter(text[j]) { j = text.index(after: j) }
            let token = text[i..<j]
            if token.hasPrefix("/") || token.hasPrefix("./") || token.hasPrefix("../") || token.hasPrefix("~/") {
                result.append(i..<j)
            }
            i = j
        }
        return result
    }
}

struct PathRewriter {
    let root: String
    let repos: [RepoConfig]
    let worktree: (String, String) -> String

    init(root: String, repos: [RepoConfig], worktree: @escaping (String, String) -> String) {
        self.root = Paths.clean(root)
        self.repos = repos.sorted { $0.path.count > $1.path.count }
        self.worktree = worktree
    }

    func locate(_ absolute: String) -> (repo: RepoConfig, suffix: String)? {
        for r in repos {
            let base = Paths.clean(r.path)
            if absolute == base || absolute.hasPrefix(base + "/") {
                return (r, String(absolute.dropFirst(base.count)))
            }
        }
        guard let inside = Paths.relative(absolute, within: root) else { return nil }
        let parts = inside.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].hasPrefix("."), let r = repos.first(where: { $0.name == parts[1] }) else { return nil }
        return (r, String(absolute.dropFirst(Paths.join(root, parts[0], parts[1]).count)))
    }

    func rewrite(_ text: String, fileDir: String, repoDir: String, own: String, trama: Trama?) -> String {
        var out = ""
        var cursor = text.startIndex
        for range in PathReferences.ranges(in: text) {
            out += text[cursor..<range.lowerBound]
            let raw = String(text[range])
            out += replacement(raw, fileDir: fileDir, repoDir: repoDir, own: own, trama: trama) ?? raw
            cursor = range.upperBound
        }
        out += text[cursor...]
        return out
    }

    private func replacement(_ raw: String, fileDir: String, repoDir: String, own: String, trama: Trama?) -> String? {
        let absolute = raw.hasPrefix("/") || raw.hasPrefix("~/") ? Paths.clean(Paths.expand(raw)) : Paths.join(fileDir, raw)
        guard let (r, suffix) = locate(absolute), r.name != own else { return nil }
        let base = trama.flatMap { $0.repos.contains(r.name) ? worktree($0.slug, r.name) : nil } ?? Paths.clean(r.path)
        let target = base + suffix
        guard target != absolute else { return nil }
        var formatted = target
        let siblings = Paths.parent(Paths.clean(repoDir))
        if Paths.parent(base) == siblings, let inside = Paths.relative(Paths.clean(fileDir), within: siblings) {
            let depth = inside.split(separator: "/").count
            formatted = String(repeating: "../", count: depth) + Paths.name(base) + suffix
        }
        if raw.count > 1 && raw.hasSuffix("/") { formatted += "/" }
        return formatted
    }
}

extension Workspace {
    var pathRewriter: PathRewriter {
        PathRewriter(root: root, repos: config.repos) { [root] slug, repo in Paths.join(root, slug, repo) }
    }

    private var pathRules: [Automation] {
        config.automations.filter { $0.enabled && $0.kind == .paths }
    }

    private func isTracked(_ dir: String, _ relative: String) -> Bool {
        Git.execute(dir, ["ls-files", "--error-unmatch", "--", relative]).code == 0
    }

    private func ensureIgnored(_ dir: String, _ relative: String) {
        guard Git.execute(dir, ["check-ignore", "-q", "--", relative]).code != 0 else { return }
        guard let common = try? Git.run(dir, "rev-parse", "--git-common-dir"), !common.isEmpty else { return }
        let commonDir = common.hasPrefix("/") ? common : Paths.join(dir, common)
        let exclude = Paths.join(commonDir, "info", "exclude")
        var text = (try? File.read(exclude)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        try? File.write(text + "/" + relative + "\n", to: exclude)
    }

    private func matchingFiles(_ patterns: [String], in dir: String) -> [String] {
        var found: [String] = []
        let base = Paths.clean(dir)
        for pattern in patterns {
            var g = glob_t()
            defer { globfree(&g) }
            guard glob(Paths.join(base, pattern), GLOB_BRACE, nil, &g) == 0 else { continue }
            for i in 0..<Int(g.gl_pathc) {
                guard let c = g.gl_pathv[i] else { continue }
                let path = Paths.clean(String(cString: c))
                guard !Paths.isDirectory(path), let relative = Paths.relative(path, within: base), !relative.isEmpty else { continue }
                if relative == ".git" || relative.hasPrefix(".git/") || found.contains(relative) { continue }
                found.append(relative)
            }
        }
        return found
    }

    func rewritePaths(_ patterns: [String], in dir: String, repo own: String, trama: Trama?) -> [Warning] {
        let rewriter = pathRewriter
        var warnings: [Warning] = []
        for relative in matchingFiles(patterns, in: dir) {
            let file = Paths.join(dir, relative)
            do {
                let warning: Warning? = try withLock {
                    guard let data = FileManager.default.contents(atPath: file),
                          let text = String(data: data, encoding: .utf8) else { return nil }
                    let rewritten = rewriter.rewrite(text, fileDir: Paths.parent(file), repoDir: dir, own: own, trama: trama)
                    guard rewritten != text else { return nil }
                    if isTracked(dir, relative) {
                        return Warning(repo: own, message: "\(relative) é versionado · o Trama só aponta caminhos em arquivos fora do git")
                    }
                    ensureIgnored(dir, relative)
                    try Data(rewritten.utf8).write(to: URL(fileURLWithPath: file))
                    return nil
                }
                if let warning { warnings.append(warning) }
            } catch {
                warnings.append(Warning(repo: own, message: "não consegui ajustar \(relative): \(errorMessage(error))"))
            }
        }
        return warnings
    }

    @discardableResult
    func applyWorktreePathRules(_ t: Trama, rules: [Automation]? = nil) -> [Warning] {
        guard !t.isArchived else { return [] }
        var warnings: [Warning] = []
        for rule in (rules ?? pathRules) where rule.kind == .paths && rule.scope == .worktrees {
            for name in t.repos where rule.repos.isEmpty || rule.repos.contains(name) {
                let wt = worktreePath(t.slug, name)
                guard Paths.isDirectory(wt) else { continue }
                warnings += rewritePaths(rule.files, in: wt, repo: name, trama: t)
            }
        }
        return warnings
    }

    @discardableResult
    func applyFocusPathRules(_ focused: Trama?, rules: [Automation]? = nil) -> [Warning] {
        var warnings: [Warning] = []
        for rule in (rules ?? pathRules) where rule.followsFocus {
            for name in rule.repos {
                guard let r = try? repo(name) else {
                    warnings.append(Warning(repo: name, message: "“\(rule.name)” age neste repositório, mas ele não está mais cadastrado"))
                    continue
                }
                warnings += rewritePaths(rule.files, in: r.path, repo: r.name, trama: focused)
            }
        }
        return warnings
    }

    func applyAllPathRules() -> [Warning] {
        var warnings: [Warning] = []
        for t in (try? tramas()) ?? [] where !t.isArchived {
            warnings += applyWorktreePathRules(t)
        }
        return warnings + applyFocusPathRules(focusedTrama())
    }
}
