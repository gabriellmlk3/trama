import Foundation

extension Workspace {
    public func sharedRepos(_ source: Trama, _ target: Trama) -> [String] {
        mergeOrdered(target.repos.filter { source.repos.contains($0) }).map(\.name)
    }

    public func mergeTrama(from sourceSlug: String, into targetSlug: String, repos keys: [String] = [], allowConflicts: Bool = false) throws -> [ResumeResult] {
        let source = try trama(sourceSlug)
        let target = try trama(targetSlug)
        guard source.slug != target.slug else { throw TramaError("escolha duas tramas diferentes") }
        guard !source.isArchived, !target.isArchived else { throw TramaError("uma das tramas está arquivada") }
        var shared = sharedRepos(source, target)
        if !keys.isEmpty {
            let wanted = try keys.map { try repo($0).name }
            shared = shared.filter { wanted.contains($0) }
        }
        guard !shared.isEmpty else {
            throw TramaError("“\(source.title)” e “\(target.title)” não têm repositório em comum" + (keys.isEmpty ? "" : " entre os escolhidos"))
        }
        var problems: [String] = []
        for name in shared {
            let r = try repo(name)
            let wt = worktreePath(target.slug, name)
            guard Paths.isDirectory(wt) else {
                problems.append("\(name): worktree de destino não encontrado")
                continue
            }
            guard Git.branchExists(r.path, source.branch) else {
                problems.append("\(name): a branch \(source.branch) não existe")
                continue
            }
            let dirty = try Git.statusLines(wt).count
            if dirty > 0 {
                problems.append("\(name): \(dirty) \(plural(dirty, "arquivo", "arquivos")) não commitado(s) no destino · commite antes")
            } else if !allowConflicts, Git.predictedConflict(wt, source.branch) == "conflito" {
                problems.append("\(name): o merge teria conflito · use --permitir-conflito para resolver no worktree")
            }
        }
        guard problems.isEmpty else {
            throw TramaError("nada foi mesclado:\n" + problems.joined(separator: "\n"))
        }
        var results: [ResumeResult] = []
        for name in shared {
            results.append(performMerge(repo: name, into: worktreePath(target.slug, name), branch: source.branch, allowConflicts: allowConflicts))
        }
        let done = results.filter { $0.situation == "mesclado" || $0.situation == "conflito" }.map(\.repo)
        if !done.isEmpty {
            try? addJournal(target.slug, "merge de “\(source.title)” (\(source.branch)) em \(done.joined(separator: ", "))")
        }
        return results
    }

    func performMerge(repo name: String, into wt: String, branch: String, allowConflicts: Bool) -> ResumeResult {
        do {
            let incoming = try Git.aheadBehind(wt, branch).behind
            if incoming == 0 {
                return ResumeResult(repo: name, situation: "atualizado", detail: "já tinha tudo de \(branch)")
            }
            let merge = Git.execute(wt, ["merge", "--no-edit", branch])
            if merge.code == 0 {
                return ResumeResult(repo: name, situation: "mesclado", detail: "\(incoming) \(plural(incoming, "commit", "commits")) de \(branch)")
            }
            let unmerged = (try? Git.run(wt, "diff", "--name-only", "--diff-filter=U")) ?? ""
            if allowConflicts, !unmerged.isEmpty {
                let count = unmerged.split(separator: "\n").count
                return ResumeResult(repo: name, situation: "conflito", detail: "\(count) \(plural(count, "arquivo", "arquivos")) em conflito · merge em andamento, resolva em \(Paths.abbreviate(wt))")
            }
            _ = Git.execute(wt, ["merge", "--abort"])
            let message = merge.error.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResumeResult(repo: name, situation: "erro", detail: message.isEmpty ? "o merge falhou e foi desfeito" : message)
        } catch {
            return ResumeResult(repo: name, situation: "erro", detail: errorMessage(error))
        }
    }

    public func mergeWorktrees(repo key: String, from source: String, into target: String, allowConflicts: Bool = false) throws -> ResumeResult {
        let r = try repo(key)
        let list = Git.listWorktrees(r.path).filter { !$0.bare && !$0.prunable }
        guard let from = list.first(where: { Paths.real($0.path) == Paths.real(source) }),
              let to = list.first(where: { Paths.real($0.path) == Paths.real(target) }) else {
            throw TramaError("não achei esses worktrees em \(r.name)")
        }
        guard from.path != to.path else { throw TramaError("escolha dois worktrees diferentes") }
        guard !from.branch.isEmpty else { throw TramaError("o worktree de origem está com HEAD solto · não há branch para mesclar") }
        guard !to.branch.isEmpty else { throw TramaError("o worktree de destino está com HEAD solto") }
        if !allowConflicts, Git.predictedConflict(to.path, from.branch) == "conflito" {
            throw TramaError("o merge de \(from.branch) em \(to.branch) teria conflito · nada foi mesclado")
        }
        let result = performMerge(repo: r.name, into: to.path, branch: from.branch, allowConflicts: allowConflicts)
        if result.situation == "mesclado" || result.situation == "conflito",
           let t = try? tramas().first(where: { !$0.isArchived && to.path.hasPrefix(tramaPath($0.slug) + "/") }) {
            try? addJournal(t.slug, "merge de \(from.branch) em \(r.name)")
        }
        return result
    }
}
