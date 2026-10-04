import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PrepState {
    public static let running = "preparando"
    public static let ready = "pronto"
    public static let failed = "falhou"
}

public struct Recipe: Equatable, Sendable {
    public var copy: [String]
    public var run: [String]

    public var isEmpty: Bool { copy.isEmpty && run.isEmpty }
}

extension RepoConfig {
    public var recipe: Recipe { Recipe(copy: copy, run: run) }
}

enum RecipeSuggestion {
    private static let templates: Set<String> = [".env.example", ".env.sample", ".env.template", ".env.dist"]

    static func forRepo(_ path: String) -> Recipe {
        var copy: [String] = []
        var run: [String] = []
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        if entries.contains(where: { $0.hasPrefix(".env") && !templates.contains($0) }) {
            copy.append(".env*")
        }
        if entries.contains("local.properties") {
            copy.append("local.properties")
        }
        if entries.contains("pnpm-lock.yaml") {
            run.append("pnpm install --frozen-lockfile")
        } else if entries.contains("yarn.lock") {
            run.append("yarn install --frozen-lockfile")
        } else if entries.contains("package-lock.json") {
            run.append("npm ci")
        }
        if entries.contains("Podfile") {
            run.append("pod install")
        }
        return Recipe(copy: copy, run: run)
    }
}

extension Workspace {
    var logsDir: String { Paths.join(stateDir, "logs") }

    public func prepLogPath(_ slug: String, _ repo: String) -> String {
        Paths.join(logsDir, "\(slug)-\(repo).log")
    }

    private func prepStatePath(_ slug: String, _ repo: String) -> String {
        Paths.join(logsDir, "\(slug)-\(repo).estado")
    }

    public func prepState(_ slug: String, _ repo: String) -> String? {
        guard let text = try? File.read(prepStatePath(slug, repo)) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func clearPreparation(_ slug: String, _ repos: [String]) {
        for name in repos {
            try? FileManager.default.removeItem(atPath: prepLogPath(slug, name))
            try? FileManager.default.removeItem(atPath: prepStatePath(slug, name))
        }
    }

    @discardableResult
    public func setRecipe(_ key: String, copy: [String], run: [String]) throws -> RepoConfig {
        var r = try repo(key)
        let patterns = copy.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for p in patterns where p.hasPrefix("/") || p.hasPrefix("~") || p.split(separator: "/").contains("..") {
            throw TramaError("o padrão “\(p)” precisa ser relativo à pasta do repositório")
        }
        r.copy = patterns
        r.run = run.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try replaceRepo(r)
        return r
    }

    func copyIgnoredFiles(_ r: RepoConfig, into destination: String) -> (copied: [String], failures: [String]) {
        var copied: [String] = []
        var failures: [String] = []
        let fm = FileManager.default
        let source = Paths.real(r.path)
        for pattern in r.copy {
            var g = glob_t()
            defer { globfree(&g) }
            guard glob(Paths.join(source, pattern), GLOB_BRACE, nil, &g) == 0 else { continue }
            for i in 0..<Int(g.gl_pathc) {
                guard let c = g.gl_pathv[i] else { continue }
                let match = Paths.real(String(cString: c))
                guard let relative = Paths.relative(match, within: source), !relative.isEmpty else { continue }
                if relative == ".git" || relative.hasPrefix(".git/") { continue }
                let target = Paths.join(destination, relative)
                if Paths.exists(target) { continue }
                do {
                    try fm.createDirectory(atPath: Paths.parent(target), withIntermediateDirectories: true)
                    try fm.copyItem(atPath: match, toPath: target)
                    copied.append(relative)
                } catch {
                    failures.append("\(relative): \(error.localizedDescription)")
                }
            }
        }
        return (copied, failures)
    }

    @discardableResult
    public func prepare(_ slug: String, _ key: String) throws -> [Warning] {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let r = try repo(key)
        guard t.repos.contains(r.name) else { throw TramaError("\(r.name) não faz parte da trama") }
        guard !r.recipe.isEmpty else { throw TramaError("\(r.name) não tem receita de preparo · veja `trama repo preparo`") }
        let wt = worktreePath(t.slug, r.name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree de \(r.name) não encontrado") }
        return startPreparation(t, r)
    }

    func startPreparation(_ t: Trama, _ r: RepoConfig) -> [Warning] {
        guard !r.recipe.isEmpty else { return [] }
        let wt = worktreePath(t.slug, r.name)
        let log = prepLogPath(t.slug, r.name)
        let statePath = prepStatePath(t.slug, r.name)
        var warnings: [Warning] = []
        do {
            try File.write("", to: log)
            try File.write(PrepState.running + "\n", to: statePath)
        } catch {
            return [Warning(repo: r.name, message: "não consegui preparar o worktree: \(errorMessage(error))")]
        }
        var header = "# preparo de \(r.name) · \(Timestamp.string())\n"
        let (copied, failures) = copyIgnoredFiles(r, into: wt)
        for file in copied { header += "copiado: \(file)\n" }
        for failure in failures {
            header += "não copiado: \(failure)\n"
            warnings.append(Warning(repo: r.name, message: "não copiei \(failure)"))
        }
        try? File.write(header, to: log)
        guard !r.run.isEmpty else {
            try? File.write(PrepState.ready + "\n", to: statePath)
            return warnings
        }
        let script = """
        cd "$TRAMA_WT" && /bin/zsh -ilc "$TRAMA_RECIPE" >> "$TRAMA_LOG" 2>&1
        if [ $? -eq 0 ]; then echo \(PrepState.ready) > "$TRAMA_STATE"; else echo \(PrepState.failed) > "$TRAMA_STATE"; fi
        """
        var env = ProcessInfo.processInfo.environment
        env["TRAMA_WT"] = wt
        env["TRAMA_LOG"] = log
        env["TRAMA_STATE"] = statePath
        env["TRAMA_RECIPE"] = r.run.joined(separator: " && ")
        do {
            try ProcessRunner.spawnDetached("/bin/sh", ["-c", script], environment: env)
        } catch {
            try? File.write(PrepState.failed + "\n", to: statePath)
            warnings.append(Warning(repo: r.name, message: "não consegui rodar o preparo: \(error.localizedDescription)"))
        }
        return warnings
    }
}
