import Foundation

extension Workspace {
    /// Mescla a branch da trama direto nas branches de destino do remoto, sem PR.
    /// Valida todos os repositórios antes de enviar qualquer coisa.
    public func mergeIntoBranches(_ slug: String, targets: [String: String] = [:], only: Set<String>? = nil) throws -> (trama: Trama, results: [ResumeResult], warnings: [Warning]) {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        var warnings: [Warning] = []
        var problems: [String] = []
        var plan: [(repo: RepoConfig, dir: String, target: String)] = []
        for r in mergeOrdered(t.repos) {
            if let only, !only.contains(r.name) { continue }
            let wt = worktreePath(t.slug, r.name)
            guard Paths.isDirectory(wt) else {
                problems.append("\(r.name): worktree não encontrado")
                continue
            }
            guard Git.hasOrigin(wt) else {
                problems.append("\(r.name): não tem remoto origin")
                continue
            }
            let target = targets[r.name] ?? prTarget(for: t, r)
            guard target != t.branch else {
                problems.append("\(r.name): o destino é a própria branch da trama")
                continue
            }
            guard Git.ensureRemoteBranch(wt, target) else {
                problems.append("\(r.name): o destino \(target) não existe no remoto")
                continue
            }
            let fetched = Git.execute(wt, ["fetch", "--quiet", "origin", target], timeout: 60)
            guard fetched.code == 0 else {
                problems.append("\(r.name): não consegui atualizar \(target): " + firstLine(fetched.error))
                continue
            }
            let ref = "origin/" + target
            let ahead = (try? Git.aheadBehind(wt, ref).ahead) ?? 0
            guard ahead > 0 else {
                warnings.append(Warning(repo: r.name, message: "sem commits à frente de \(target) · nada a mesclar"))
                continue
            }
            if let files = Git.predictedConflictFiles(wt, ref), !files.isEmpty {
                problems.append("\(r.name): mesclar em \(target) teria conflito em \(files.count) \(plural(files.count, "arquivo", "arquivos")) · atualize a trama com \(target) antes")
                continue
            }
            if let lines = try? Git.statusLines(wt), !lines.isEmpty {
                warnings.append(Warning(repo: r.name, message: "\(lines.count) \(plural(lines.count, "arquivo", "arquivos")) não commitado(s) ficaram de fora da mescla"))
            }
            plan.append((r, wt, target))
        }
        guard problems.isEmpty else {
            throw TramaError("nada foi mesclado:\n" + problems.joined(separator: "\n"))
        }
        guard !plan.isEmpty else {
            throw TramaError(warnings.isEmpty ? "nenhum repositório para mesclar" : warnings.map { ($0.repo.map { "\($0): " } ?? "") + $0.message }.joined(separator: "\n"))
        }
        var results: [ResumeResult] = []
        for p in plan {
            results.append(pushMerge(repo: p.repo.name, dir: p.dir, branch: t.branch, target: p.target))
        }
        let done = results.filter { $0.situation == "mesclado" }.map { r in
            "\(r.repo) → \(plan.first(where: { $0.repo.name == r.repo })?.target ?? "")"
        }
        if !done.isEmpty {
            try? addJournal(t.slug, "mescla direta de \(t.branch): " + done.joined(separator: " · "))
        }
        return (t, results, warnings)
    }

    private func pushMerge(repo name: String, dir wt: String, branch: String, target: String) -> ResumeResult {
        do {
            let ref = "origin/" + target
            let counts = try Git.aheadBehind(wt, ref)
            let spec = "refs/heads/" + target
            if counts.behind == 0 {
                try Git.run(wt, "push", "origin", branch + ":" + spec)
                return ResumeResult(repo: name, situation: "mesclado", detail: "\(counts.ahead) \(plural(counts.ahead, "commit", "commits")) em \(target) (avanço direto)")
            }
            let temp = NSTemporaryDirectory() + "trama-merge-" + UUID().uuidString
            try Git.run(wt, "worktree", "add", "--detach", temp, ref)
            defer {
                _ = Git.execute(wt, ["worktree", "remove", "--force", temp])
                try? FileManager.default.removeItem(atPath: temp)
            }
            let merge = Git.execute(temp, ["merge", "--no-ff", "-m", "Merge branch '\(branch)' into \(target)", branch])
            guard merge.code == 0 else {
                let message = firstLine(merge.error.isEmpty ? merge.output : merge.error)
                return ResumeResult(repo: name, situation: "erro", detail: message.isEmpty ? "o merge falhou e nada foi enviado" : message)
            }
            try Git.run(temp, "push", "origin", "HEAD:" + spec)
            return ResumeResult(repo: name, situation: "mesclado", detail: "\(counts.ahead) \(plural(counts.ahead, "commit", "commits")) em \(target) (commit de merge)")
        } catch {
            return ResumeResult(repo: name, situation: "erro", detail: errorMessage(error))
        }
    }
}
