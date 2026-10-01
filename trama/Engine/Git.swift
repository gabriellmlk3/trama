import Foundation

public struct GitError: Error, LocalizedError, CustomStringConvertible {
    public let args: [String]
    public let code: Int32
    public let stderr: String

    public var description: String {
        let m = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAuthenticationFailure {
            return "sem acesso ao remoto: entre na conta do provedor em Ajustes › Contas Git (token ou login pela CLI) e tente de novo.\n\(m)"
        }
        return "git \(args.joined(separator: " ")): \(m.isEmpty ? "código \(code)" : m)"
    }

    var isAuthenticationFailure: Bool {
        let text = stderr.lowercased()
        return [
            "could not read username",
            "could not read password",
            "authentication failed",
            "terminal prompts disabled",
            "http basic: access denied",
            "permission denied (publickey",
            "invalid username or token",
            "returned error: 403"
        ].contains { text.contains($0) }
    }

    public var errorDescription: String? { description }
}

struct GitResult {
    var output: String
    var error: String
    var code: Int32
}

final class Box {
    var data = Data()
}

enum Git {
    static var executable: String {
        if let v = ProcessInfo.processInfo.environment["TRAMA_GIT"], !v.isEmpty {
            return v
        }
        return "/usr/bin/git"
    }

    static func execute(_ dir: String, _ args: [String], timeout: TimeInterval = 0) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-C", dir] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        for (key, value) in GitCredentials.gitEnvironment() where env[key] == nil { env[key] = value }
        if env["GIT_SSH_COMMAND"] == nil {
            env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        }
        process.environment = env
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return GitResult(output: "", error: "não consegui executar o git (\(executable)): \(error.localizedDescription)", code: -1)
        }
        let errorBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.data = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        var timer: DispatchWorkItem?
        if timeout > 0 {
            let item = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            timer = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timer?.cancel()
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\n") { text.removeLast() }
        return GitResult(output: text, error: String(decoding: errorBox.data, as: UTF8.self), code: process.terminationStatus)
    }

    @discardableResult
    static func run(_ dir: String, _ args: String...) throws -> String {
        try run(dir, args)
    }

    @discardableResult
    static func run(_ dir: String, _ args: [String]) throws -> String {
        let r = execute(dir, args)
        if r.code != 0 {
            throw GitError(args: args, code: r.code, stderr: r.error)
        }
        return r.output
    }

    static func refExists(_ dir: String, _ ref: String) -> Bool {
        execute(dir, ["rev-parse", "--verify", "--quiet", ref + "^{commit}"]).code == 0
    }

    static func branchExists(_ dir: String, _ branch: String) -> Bool {
        refExists(dir, "refs/heads/" + branch)
    }

    static func hasOrigin(_ dir: String) -> Bool {
        guard let out = try? run(dir, "remote") else { return false }
        return out.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "origin" }
    }

    static func remoteURL(_ dir: String) -> String? {
        let r = execute(dir, ["config", "--get", "remote.origin.url"])
        let url = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.code == 0 && !url.isEmpty ? url : nil
    }

    static func baseRef(_ dir: String, _ base: String) -> String {
        refExists(dir, "refs/remotes/origin/" + base) ? "origin/" + base : base
    }

    static func fetchBase(_ dir: String, _ base: String) throws {
        guard hasOrigin(dir) else { return }
        let r = execute(dir, ["fetch", "--quiet", "origin", base], timeout: 45)
        if r.code != 0 {
            throw GitError(args: ["fetch", "origin", base], code: r.code, stderr: r.error)
        }
    }

    static func toplevel(_ dir: String) throws -> String {
        try run(dir, "rev-parse", "--show-toplevel")
    }

    static func currentBranch(_ dir: String) -> String {
        (try? run(dir, "rev-parse", "--abbrev-ref", "HEAD")) ?? ""
    }

    static func probableBase(_ dir: String) -> String {
        if let out = try? run(dir, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD") {
            let b = out.hasPrefix("origin/") ? String(out.dropFirst(7)) : out
            if !b.isEmpty { return b }
        }
        for b in ["main", "master", "develop"] where branchExists(dir, b) || refExists(dir, "refs/remotes/origin/" + b) {
            return b
        }
        let current = currentBranch(dir)
        if !current.isEmpty && current != "HEAD" { return current }
        return "main"
    }

    static func aheadBehind(_ dir: String, _ ref: String) throws -> (ahead: Int, behind: Int) {
        let out = try run(dir, "rev-list", "--left-right", "--count", ref + "...HEAD")
        let fields = out.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 2, let behind = Int(fields[0]), let ahead = Int(fields[1]) else {
            throw TramaError("saída inesperada do git rev-list: \(out)")
        }
        return (ahead, behind)
    }

    static func countCommits(_ dir: String, _ range: String) throws -> Int {
        let out = try run(dir, "rev-list", "--count", range)
        guard let n = Int(out.trimmingCharacters(in: .whitespaces)) else {
            throw TramaError("saída inesperada do git rev-list: \(out)")
        }
        return n
    }

    static func statusLines(_ dir: String) throws -> [String] {
        let out = try run(dir, "status", "--porcelain")
        return out.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func lastCommit(_ dir: String) -> Commit? {
        guard let out = try? run(dir, "log", "-1", "--format=%h%x1f%s%x1f%ct"), !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "\u{1f}")
        guard p.count == 3 else { return nil }
        return Commit(hash: p[0], subject: p[1], timestamp: Int64(p[2]) ?? 0)
    }

    static func predictedConflict(_ dir: String, _ ref: String) -> String {
        let r = execute(dir, ["merge-tree", "--write-tree", "--name-only", "HEAD", ref], timeout: 20)
        switch r.code {
        case 0: return "limpo"
        case 1: return "conflito"
        default: return "desconhecido"
        }
    }

    static func predictedConflictFiles(_ dir: String, _ ref: String) -> [String]? {
        let r = execute(dir, ["merge-tree", "--write-tree", "--name-only", "HEAD", ref], timeout: 20)
        switch r.code {
        case 0:
            return []
        case 1:
            var files: [String] = []
            for line in r.output.components(separatedBy: "\n").dropFirst() {
                if line.isEmpty { break }
                files.append(line)
            }
            return files.isEmpty ? nil : files
        default:
            return nil
        }
    }

    static func remoteBranches(_ dir: String) -> [String] {
        let prefix = "refs/remotes/origin/"
        guard let out = try? run(dir, "for-each-ref", "--format=%(refname)", "refs/remotes/origin") else { return [] }
        return out.split(separator: "\n").compactMap { line in
            guard line.hasPrefix(prefix) else { return nil }
            let name = String(line.dropFirst(prefix.count))
            return name == "HEAD" ? nil : name
        }
    }

    static func ensureRemoteBranch(_ dir: String, _ branch: String) -> Bool {
        if refExists(dir, "refs/remotes/origin/" + branch) { return true }
        guard execute(dir, ["ls-remote", "--exit-code", "--heads", "origin", "refs/heads/" + branch], timeout: 30).code == 0 else {
            return false
        }
        _ = execute(dir, ["fetch", "--quiet", "origin", branch], timeout: 45)
        return true
    }

    struct WorktreeInfo {
        var path: String
        var branch = ""
        var prunable = false
        var bare = false
    }

    static func listWorktrees(_ dir: String) -> [WorktreeInfo] {
        guard let out = try? run(dir, "worktree", "list", "--porcelain") else { return [] }
        var list: [WorktreeInfo] = []
        var current: WorktreeInfo?
        for line in out.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                if let a = current { list.append(a) }
                current = WorktreeInfo(path: String(line.dropFirst(9)))
            } else if current != nil {
                if line.hasPrefix("branch ") {
                    var b = String(line.dropFirst(7))
                    if b.hasPrefix("refs/heads/") { b = String(b.dropFirst(11)) }
                    current?.branch = b
                } else if line.hasPrefix("prunable") {
                    current?.prunable = true
                } else if line == "bare" {
                    current?.bare = true
                }
            }
        }
        if let a = current { list.append(a) }
        return list
    }
}
