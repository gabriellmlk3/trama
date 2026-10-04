import Foundation
import XCTest
@testable import trama

final class Lab {
    let root: String
    var repos: [String: String] = [:]

    init() throws {
        root = Paths.real(NSTemporaryDirectory()) + "/trama-teste-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        setenv("GIT_AUTHOR_NAME", "Teste", 1)
        setenv("GIT_AUTHOR_EMAIL", "teste@example.com", 1)
        setenv("GIT_COMMITTER_NAME", "Teste", 1)
        setenv("GIT_COMMITTER_EMAIL", "teste@example.com", 1)
        setenv("GIT_CONFIG_GLOBAL", root + "/gitconfig", 1)
        setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
        try write(root + "/gitconfig", "[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n[commit]\n\tgpgsign = false\n")
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    func git(_ dir: String, _ args: String...) throws -> String {
        try Git.run(dir, args)
    }

    func write(_ path: String, _ content: String) throws {
        try File.write(content, to: path)
    }

    func commit(_ dir: String, _ file: String, _ content: String, _ msg: String) throws {
        try write(dir + "/" + file, content)
        try git(dir, "add", "-A")
        try git(dir, "commit", "-q", "-m", msg)
    }

    @discardableResult
    func newRepo(_ name: String) throws -> String {
        let remote = "\(root)/remotos/\(name).git"
        let dir = "\(root)/github/\(name)"
        try FileManager.default.createDirectory(atPath: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try git(remote, "init", "-q", "--bare", "-b", "main")
        try git(dir, "init", "-q", "-b", "main")
        try commit(dir, "README.md", "# \(name)\n", "inicial")
        try commit(dir, "src/app.txt", "linha 1\nlinha 2\nlinha 3\n", "app")
        try git(dir, "remote", "add", "origin", remote)
        try git(dir, "push", "-q", "-u", "origin", "main")
        repos[name] = dir
        return dir
    }

    func pushToMain(_ name: String, _ file: String, _ content: String, _ msg: String) throws {
        let peer = "\(root)/colega/\(name)"
        if Paths.exists(peer) {
            try git(peer, "pull", "-q")
        } else {
            try FileManager.default.createDirectory(atPath: "\(root)/colega", withIntermediateDirectories: true)
            try git(root, "clone", "-q", "\(root)/remotos/\(name).git", peer)
        }
        try commit(peer, file, content, msg)
        try git(peer, "push", "-q", "origin", "main")
    }

    func workspace(withContext: Bool = true) throws -> Workspace {
        for n in ["rebocs_api", "rebocs-admin", "rebocs-android", "rebocs-context"] {
            try newRepo(n)
        }
        let w = try Workspace.configure(root: root + "/Tramas", context: withContext ? repos["rebocs-context"] : nil)
        w.executable = "/Applications/Trama.app/Contents/MacOS/trama"
        for n in ["rebocs_api", "rebocs-admin", "rebocs-android"] {
            try w.addRepo(repos[n]!)
            try w.setProvider(n, .github)
        }
        return w
    }
}
