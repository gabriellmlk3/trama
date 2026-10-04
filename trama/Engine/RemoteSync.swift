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

extension Git {
    static func behindUpstream(_ dir: String) -> Int {
        (try? countCommits(dir, "HEAD..@{u}")) ?? 0
    }
}
