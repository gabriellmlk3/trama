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
