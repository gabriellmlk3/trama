import Foundation

extension Workspace {
    private func remoteBranchTargets(_ slug: String, _ repos: [String]) throws -> (Trama, [(RepoConfig, String)]) {
        let t = try trama(slug)
        let selected = mergeOrdered(t.repos).filter { repos.contains($0.name) }
        let targets = try selected.map { r -> (RepoConfig, String) in
            let wt = worktreePath(t.slug, r.name)
            guard Paths.isDirectory(wt), Git.hasOrigin(wt) else {
                throw TramaError("\(r.name) não tem worktree com remoto origin")
            }
            return (r, wt)
        }
        guard !targets.isEmpty else { throw TramaError("nenhum repositório selecionado") }
        return (t, targets)
    }

    private func validateBranchName(_ name: String, in dir: String) throws {
        guard !name.isEmpty, Git.execute(dir, ["check-ref-format", "--branch", name]).code == 0, !name.hasPrefix("-") else {
            throw TramaError("“\(name)” não é um nome de branch válido")
        }
    }

    private func protectBranch(_ name: String, _ t: Trama, _ pairs: [(RepoConfig, String)]) throws {
        if name == t.branch {
            throw TramaError("“\(name)” é a branch desta trama")
        }
        for (r, _) in pairs where name == base(for: t, r) {
            throw TramaError("“\(name)” é a branch padrão de \(r.name)")
        }
    }

    private func push(_ dir: String, _ refspec: String) throws {
        let r = Git.execute(dir, ["push", "--quiet", "origin", refspec], timeout: 90)
        if r.code != 0 {
            throw TramaError(firstLine(r.error).isEmpty ? "o push para o remoto falhou" : firstLine(r.error))
        }
    }

    public func createRemoteBranch(_ slug: String, name: String, from source: String, repos: [String]) throws {
        let (_, pairs) = try remoteBranchTargets(slug, repos)
        for (r, wt) in pairs {
            try validateBranchName(name, in: wt)
            if Git.ensureRemoteBranch(wt, name) {
                throw TramaError("“\(name)” já existe em \(r.name)")
            }
            guard Git.ensureRemoteBranch(wt, source) else {
                throw TramaError("“\(source)” não existe em \(r.name)")
            }
        }
        for (_, wt) in pairs {
            try push(wt, "refs/remotes/origin/\(source):refs/heads/\(name)")
        }
    }

    public func renameRemoteBranch(_ slug: String, from old: String, to new: String, repos: [String]) throws {
        let (t, pairs) = try remoteBranchTargets(slug, repos)
        try protectBranch(old, t, pairs)
        guard old != new else { return }
        for (r, wt) in pairs {
            try validateBranchName(new, in: wt)
            if Git.ensureRemoteBranch(wt, new) {
                throw TramaError("“\(new)” já existe em \(r.name)")
            }
            guard Git.ensureRemoteBranch(wt, old) else {
                throw TramaError("“\(old)” não existe em \(r.name)")
            }
        }
        for (_, wt) in pairs {
            try push(wt, "refs/remotes/origin/\(old):refs/heads/\(new)")
            try push(wt, ":refs/heads/\(old)")
            _ = Git.execute(wt, ["fetch", "--prune", "--quiet", "origin"], timeout: 60)
        }
    }

    public func deleteRemoteBranch(_ slug: String, name: String, repos: [String]) throws {
        let (t, pairs) = try remoteBranchTargets(slug, repos)
        try protectBranch(name, t, pairs)
        for (_, wt) in pairs {
            try push(wt, ":refs/heads/\(name)")
            _ = Git.execute(wt, ["fetch", "--prune", "--quiet", "origin"], timeout: 60)
        }
    }
}
