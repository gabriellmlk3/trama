import Foundation

extension Workspace {
    public func syncWorktree(repo key: String, worktree: String, pull: Bool) throws -> String {
        let r = try repo(key)
        guard let target = Git.listWorktrees(r.path).first(where: { Paths.real($0.path) == Paths.real(worktree) && !$0.prunable }) else {
            throw TramaError("não achei esse worktree em \(r.name)")
        }
        guard !target.branch.isEmpty else { throw TramaError("o worktree está com HEAD solto") }
        guard Git.hasOrigin(target.path) else { throw TramaError("\(r.name) não tem remoto origin") }
        let fetched = Git.execute(target.path, ["fetch", "--prune", "--quiet", "origin"], timeout: 60)
        guard fetched.code == 0 else {
            throw TramaError("fetch falhou em \(r.name): \(fetched.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let behind = Git.behindUpstream(target.path)
        guard pull else {
            return behind > 0 ? "\(behind) \(behind == 1 ? "commit novo" : "commits novos") em \(target.branch)" : "\(target.branch) já está em dia com o remoto"
        }
        guard behind > 0 else { return "\(target.branch) já está em dia com o remoto" }
        let merged = Git.execute(target.path, ["merge", "--ff-only", "--quiet", "@{u}"], timeout: 60)
        guard merged.code == 0 else {
            throw TramaError("não deu para atualizar \(target.branch) sem merge: \(merged.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return "\(target.branch) atualizada · \(behind) \(behind == 1 ? "commit" : "commits")"
    }
}

public struct SyncOutcome: Sendable {
    public var repo: String
    public var message: String
    public var failed: Bool
}

extension Workspace {
    public func syncPrimaries(_ slug: String) throws -> [SyncOutcome] {
        let t = try trama(slug)
        return try t.repos.map { key in
            let r = try repo(key)
            do {
                return SyncOutcome(repo: r.name, message: try syncWorktree(repo: r.name, worktree: r.path, pull: true), failed: false)
            } catch {
                return SyncOutcome(repo: r.name, message: errorMessage(error), failed: true)
            }
        }
    }
}

extension Git {
    static func fetchUpstream(_ dir: String) {
        let upstream = execute(dir, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        let name = upstream.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard upstream.code == 0, name.hasPrefix("origin/") else { return }
        _ = execute(dir, ["fetch", "--quiet", "origin", String(name.dropFirst("origin/".count))], timeout: 45)
    }

    static func behindUpstream(_ dir: String) -> Int {
        (try? countCommits(dir, "HEAD..@{u}")) ?? 0
    }
}

extension Git {
    static func localBranchBehindOrigin(_ dir: String, _ branch: String) -> Int {
        guard refExists(dir, "refs/heads/" + branch), refExists(dir, "refs/remotes/origin/" + branch) else { return 0 }
        return (try? countCommits(dir, "\(branch)..origin/\(branch)")) ?? 0
    }
}

extension Workspace {
    public func updateLocalBase(repo key: String, branch: String) throws -> String {
        let r = try repo(key)
        guard Git.hasOrigin(r.path) else { throw TramaError("\(r.name) não tem remoto origin") }
        let behind = Git.localBranchBehindOrigin(r.path, branch)
        guard behind > 0 else { return "\(branch) já está em dia com o remoto" }
        let updated = Git.execute(r.path, ["fetch", "--quiet", "origin", "\(branch):\(branch)"], timeout: 60)
        guard updated.code == 0 else {
            throw TramaError("não deu para atualizar \(branch) sem merge: \(updated.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return "\(branch) local atualizada · \(behind) \(behind == 1 ? "commit" : "commits")"
    }
}
