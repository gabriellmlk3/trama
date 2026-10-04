import Foundation

enum EditorDetection {
    static func isInstalled(_ app: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/Applications/\(app).app") || fm.fileExists(atPath: Paths.join(Paths.home, "Applications", "\(app).app"))
    }

    private static func entries(_ dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }

    static func xcodeTarget(_ dir: String) -> String? {
        let skip: Set<String> = ["Pods", "node_modules", "build", "DerivedData"]
        var projects: [String] = []
        var workspaces: [String] = []
        for level in [dir] + entries(dir).filter({ !$0.hasPrefix(".") && !skip.contains($0) }).map({ Paths.join(dir, $0) }) {
            guard Paths.isDirectory(level) else { continue }
            for name in entries(level).sorted() {
                let full = Paths.join(level, name)
                if name.hasSuffix(".xcworkspace"), level == dir || !full.contains(".xcodeproj/") { workspaces.append(full) }
                if name.hasSuffix(".xcodeproj") { projects.append(full) }
            }
        }
        return workspaces.first ?? projects.first
    }

    static func detect(_ dir: String) -> String? {
        let top = entries(dir)
        if xcodeTarget(dir) != nil || top.contains("Package.swift") { return "Xcode" }
        if top.contains(where: { $0.hasPrefix("build.gradle") || $0.hasPrefix("settings.gradle") }) {
            return isInstalled("Android Studio") ? "Android Studio" : nil
        }
        if top.contains("package.json") {
            return ["Cursor", "Visual Studio Code"].first(where: isInstalled)
        }
        return ["Cursor", "Visual Studio Code"].first(where: isInstalled)
    }

    static let codeApps = ["Visual Studio Code", "Cursor"]

    static func detectCode() -> String? {
        codeApps.first(where: isInstalled)
    }

    static func launch(_ path: String, app: String) throws {
        let result = ProcessRunner.run("/usr/bin/open", ["-a", app, path])
        if result.code != 0 {
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TramaError(message.isEmpty ? "não consegui abrir \(app)" : "não consegui abrir \(app): \(message)")
        }
    }

    static func target(_ dir: String, editor: String) -> String {
        if editor == "Xcode", let t = xcodeTarget(dir) { return t }
        if editor == "Xcode", Paths.exists(Paths.join(dir, "Package.swift")) { return Paths.join(dir, "Package.swift") }
        return dir
    }
}

extension Workspace {
    public func editorLaunch(_ slug: String, repo key: String) throws -> (app: String, path: String) {
        let t = try trama(slug)
        let r = try repo(key)
        let wt = worktreePath(t.slug, r.name)
        guard Paths.isDirectory(wt) else { throw TramaError("worktree de \(r.name) não encontrado") }
        guard let app = (r.editor?.isEmpty == false ? r.editor : nil) ?? EditorDetection.detect(wt) else {
            throw TramaError("não achei um editor para \(r.name) · escolha um em Ajustes ▸ Repositórios ▸ Preparo…")
        }
        return (app, EditorDetection.target(wt, editor: app))
    }

    @discardableResult
    public func setEditor(_ key: String, _ editor: String?) throws -> RepoConfig {
        var r = try repo(key)
        let value = editor?.trimmingCharacters(in: .whitespaces)
        r.editor = value?.isEmpty == false ? value : nil
        try replaceRepo(r)
        return r
    }
}

extension Workspace {
    public func codeWorkspacePath(_ slug: String) -> String {
        Paths.join(tramaPath(slug), slug + ".code-workspace")
    }

    @discardableResult
    public func writeCodeWorkspace(_ slug: String) throws -> String {
        let t = try trama(slug)
        var folders: [[String: String]] = []
        for key in t.repos {
            guard let r = try? repo(key), Paths.isDirectory(worktreePath(t.slug, r.name)) else { continue }
            folders.append(["name": r.alias, "path": r.name])
        }
        guard !folders.isEmpty else { throw TramaError("nenhum worktree de \(t.title) encontrado") }
        let document: [String: Any] = [
            "folders": folders,
            "settings": ["window.title": "\(t.title) · ${rootName}${separator}${activeEditorShort}"],
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        let path = codeWorkspacePath(t.slug)
        try File.write(data, to: path)
        return path
    }

    public func codeWorkspaceLaunch(_ slug: String) throws -> (app: String, path: String) {
        guard let app = EditorDetection.detectCode() else {
            throw TramaError("não achei o Visual Studio Code nem o Cursor em /Applications")
        }
        return (app, try writeCodeWorkspace(slug))
    }
}
