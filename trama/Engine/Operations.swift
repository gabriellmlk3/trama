import Foundation

public struct NewTramaOptions: Sendable {
    public var title: String
    public var repos: [String]
    public var slug: String?
    public var base: String?
    public var task: String?
    public var goal: String?
    public var context: String?
    public var noFetch = false

    public init(title: String, repos: [String], slug: String? = nil, base: String? = nil,
                task: String? = nil, goal: String? = nil, context: String? = nil, noFetch: Bool = false) {
        self.title = title
        self.repos = repos
        self.slug = slug
        self.base = base
        self.task = task
        self.goal = goal
        self.context = context
        self.noFetch = noFetch
    }
}

public struct Warning: Codable, Hashable, Sendable {
    public var repo: String?
    public var message: String
}

public struct ResumeResult: Codable, Hashable, Identifiable, Sendable {
    public var repo: String
    public var situation: String
    public var detail: String?

    public var id: String { repo }
}

private func nilIfEmpty(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

extension Workspace {
    func resolveRepos(_ keys: [String]) throws -> [RepoConfig] {
        var list: [RepoConfig] = []
        for key in keys {
            for part in key.split(separator: ",") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if p.isEmpty { continue }
                let r = try repo(p)
                if !list.contains(where: { $0.name == r.name }) {
                    list.append(r)
                }
            }
        }
        if list.isEmpty {
            throw TramaError("escolha pelo menos um repositório (--repos api,admin)")
        }
        return list
    }

    private func createWorktree(_ t: Trama, _ r: RepoConfig, noFetch: Bool) throws -> (createdBranch: Bool, warning: String?) {
        let destination = worktreePath(t.slug, r.name)
        if Paths.exists(destination) {
            throw TramaError("a pasta \(Paths.abbreviate(destination)) já existe")
        }
        let base = base(for: t, r)
        var warning: String?
        if !noFetch {
            do {
                try Git.fetchBase(r.path, base)
            } catch {
                warning = "não consegui atualizar origin/\(base) · usei o que já estava baixado"
            }
        }
        if Git.branchExists(r.path, t.branch) {
            try Git.run(r.path, "worktree", "add", destination, t.branch)
            return (false, warning)
        }
        let start = Git.baseRef(r.path, base)
        guard Git.refExists(r.path, start) else {
            throw TramaError("\(r.name): a base “\(base)” não existe")
        }
        try Git.run(r.path, "worktree", "add", "--no-track", "-b", t.branch, destination, start)
        return (true, warning)
    }

    private func undoWorktree(_ t: Trama, _ r: RepoConfig, deleteBranch: Bool) {
        _ = Git.execute(r.path, ["worktree", "remove", "--force", worktreePath(t.slug, r.name)])
        if deleteBranch {
            _ = Git.execute(r.path, ["branch", "-D", t.branch])
        }
    }

    public func newTrama(_ o: NewTramaOptions) throws -> (trama: Trama, warnings: [Warning]) {
        let title = o.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TramaError("dê um nome para a trama") }
        let slug = slugify(nilIfEmpty(o.slug) ?? title)
        guard !slug.isEmpty else {
            throw TramaError("não consegui gerar um identificador para esse nome · use --slug")
        }
        let repos = try resolveRepos(o.repos)
        let context = try nilIfEmpty(o.context).map(validContext)
        if let t = try tramas().first(where: { $0.slug == slug }) {
            throw TramaError("já existe uma trama “\(slug)” (\(t.state)) · escolha outro nome ou use --slug")
        }
        var t = Trama(
            slug: slug,
            title: title,
            branch: config.branchPrefix + slug,
            base: nilIfEmpty(o.base),
            repos: [],
            state: TramaState.active,
            task: nilIfEmpty(o.task),
            createdAt: nowUnix()
        )
        t.context = context
        t.portIndex = Workspace.nextPortIndex(try tramas())
        try FileManager.default.createDirectory(atPath: tramaPath(slug), withIntermediateDirectories: true)
        var warnings: [Warning] = []
        var created: [(RepoConfig, Bool)] = []
        func undoAll() {
            for (r, branch) in created {
                undoWorktree(t, r, deleteBranch: branch)
            }
            try? FileManager.default.removeItem(atPath: tramaPath(slug))
        }
        for r in repos {
            do {
                let (didCreate, warning) = try createWorktree(t, r, noFetch: o.noFetch)
                if let warning { warnings.append(Warning(repo: r.name, message: warning)) }
                if !didCreate { warnings.append(Warning(repo: r.name, message: "a branch \(t.branch) já existia e foi reaproveitada")) }
                created.append((r, didCreate))
                t.repos.append(r.name)
            } catch {
                undoAll()
                throw TramaError("\(r.name): \(errorMessage(error))")
            }
        }
        do {
            let final = t
            try withLock {
                var ts = try tramas()
                if ts.contains(where: { $0.slug == slug }) {
                    throw TramaError("já existe uma trama “\(slug)”")
                }
                ts.append(final)
                try saveTramas(ts)
            }
        } catch {
            undoAll()
            throw error
        }
        do {
            try prepareCapsule(t, goal: o.goal ?? "")
        } catch {
            warnings.append(Warning(message: "não consegui criar a cápsula: \(errorMessage(error))"))
        }
        do {
            try writeInstructions(t)
        } catch {
            warnings.append(Warning(message: "não consegui escrever o CLAUDE.md da trama: \(errorMessage(error))"))
        }
        for r in repos {
            warnings += startPreparation(t, r)
        }
        return (t, warnings)
    }

    private func prepareCapsule(_ t: Trama, goal: String) throws {
        let path = capsulePath(t.slug)
        if !Paths.exists(path) {
            try File.write(CapsuleDoc.new(t, goal: goal), to: path)
        } else if !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try setGoal(t.slug, goal)
        }
        try addJournal(t.slug, "trama criada com \(t.repos.joined(separator: ", "))")
    }

    func validContext(_ path: String) throws -> String {
        let c = Paths.absolute(path)
        guard Paths.isDirectory(c) else {
            throw TramaError("pasta de contexto não encontrada: \(c)")
        }
        return c
    }

    public func setTramaContext(_ slug: String, _ path: String?) throws -> Trama {
        let current = try trama(slug)
        guard !current.isArchived else { throw TramaError("essa trama está arquivada") }
        let newContext = try nilIfEmpty(path).map(validContext)
        let from = capsulePath(current.slug)
        let link = Paths.join(tramaPath(current.slug), "CAPSULA.md")
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil {
            try? FileManager.default.removeItem(atPath: link)
        }
        let updated = try updateTrama(current.slug) { $0.context = newContext }
        let to = capsulePath(updated.slug)
        if from != to, Paths.exists(from), !Paths.exists(to) {
            try FileManager.default.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try FileManager.default.moveItem(atPath: from, toPath: to)
        }
        try? writeInstructions(updated)
        let destination = newContext.map { Paths.abbreviate($0) } ?? "o padrão global"
        try? addJournal(updated.slug, "repositório de contexto: \(destination)")
        return updated
    }

    public func writeInstructions(_ t: Trama) throws {
        var b = "# Trama: \(t.title)\n\n"
        b += "Você está dentro de uma **trama**: uma frente de trabalho que atravessa vários repositórios ao mesmo tempo. "
        b += "Cada repositório tem seu próprio worktree, todos na branch `\(t.branch)`.\n\n"
        b += "## Repositórios desta trama\n\n"
        for name in t.repos {
            guard let r = try? repo(name) else { continue }
            let label = (r.label?.isEmpty == false) ? " · \(r.label!)" : ""
            b += "- `\(r.name)` → `\(worktreePath(t.slug, r.name))`\(label)\n"
        }
        b += "\n## Contexto compartilhado (cápsula)\n\n"
        b += "A cápsula fica em `\(capsulePath(t.slug))`. Leia antes de começar: ela tem o objetivo, as decisões já tomadas "
        b += "e os handoffs entre repositórios. Rode `trama capsula` para ver a versão atual.\n\n"
        b += "## Como registrar o que você faz\n\n"
        b += "Use o comando `trama` (em `\(executable)`) a partir da pasta do seu repositório:\n\n"
        b += "- `trama decisao \"texto\"` · decisão que afeta a trama ou outros repositórios\n"
        b += "- `trama handoff <repositório> \"texto\"` · passa trabalho para o agente de outro repositório\n"
        b += "- `trama sugerir <repositório|pasta> \"motivo\"` · pede ao usuário para incluir outro repositório na trama\n"
        b += "- `trama recebido` · marca como lidos os handoffs endereçados ao seu repositório\n"
        b += "- `trama pendencia \"texto\"` e `trama feito <n>` · pendências da trama\n"
        b += "- `trama status` · situação de todos os repositórios da trama\n\n"
        b += "## Regras\n\n"
        b += "- Trabalhe só no worktree do seu repositório e não troque de branch.\n"
        b += "- Mudou um contrato (endpoint, payload, evento, schema)? Registre com `trama decisao` e, se outro repositório precisar agir, com `trama handoff`.\n"
        b += "- Ao terminar uma etapa, deixe na cápsula o que o próximo agente precisa saber.\n"
        let dir = tramaPath(t.slug)
        try File.write(b, to: Paths.join(dir, "CLAUDE.md"))
        if contextPath(t.slug) != nil {
            let link = Paths.join(dir, "CAPSULA.md")
            if (try? FileManager.default.attributesOfItem(atPath: link)) == nil,
               (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == nil {
                try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: capsulePath(t.slug))
            }
        }
    }

    public func pullRepos(_ slug: String, _ keys: [String], noFetch: Bool = false) throws -> (trama: Trama, warnings: [Warning]) {
        var t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let repos = try resolveRepos(keys)
        var warnings: [Warning] = []
        var added: [String] = []
        for r in repos {
            if t.repos.contains(r.name) {
                warnings.append(Warning(repo: r.name, message: "já fazia parte da trama"))
                continue
            }
            do {
                let (didCreate, warning) = try createWorktree(t, r, noFetch: noFetch)
                if let warning { warnings.append(Warning(repo: r.name, message: warning)) }
                if !didCreate { warnings.append(Warning(repo: r.name, message: "a branch já existia e foi reaproveitada")) }
                added.append(r.name)
            } catch {
                throw TramaError("\(r.name): \(errorMessage(error))")
            }
        }
        guard !added.isEmpty else { return (t, warnings) }
        t = try updateTrama(t.slug) { x in
            for n in added where !x.repos.contains(n) {
                x.repos.append(n)
            }
        }
        try? writeInstructions(t)
        try? addJournal(t.slug, "puxou \(added.joined(separator: ", ")) para a trama")
        for r in repos where added.contains(r.name) {
            warnings += startPreparation(t, r)
        }
        return (t, warnings)
    }

    public func dropRepo(_ slug: String, _ key: String, force: Bool = false) throws -> Trama {
        let t = try trama(slug)
        let r = try repo(key)
        guard t.repos.contains(r.name) else {
            throw TramaError("\(r.name) não faz parte da trama")
        }
        let wt = worktreePath(t.slug, r.name)
        if Paths.exists(wt) {
            if !force {
                let lines = try Git.statusLines(wt)
                if !lines.isEmpty {
                    throw TramaError("\(r.name) tem \(lines.count) \(plural(lines.count, "arquivo", "arquivos")) não commitado(s) · commite ou use --forcar")
                }
            }
            try Git.run(r.path, ["worktree", "remove"] + (force ? ["--force"] : []) + [wt])
        }
        stopServices(t.slug, repo: r.name)
        clearServiceLogs(t.slug, [r.name])
        clearPreparation(t.slug, [r.name])
        let updated = try updateTrama(t.slug) { x in
            x.repos.removeAll { $0 == r.name }
        }
        try? writeInstructions(updated)
        try? addJournal(updated.slug, "soltou \(r.name) da trama (a branch \(updated.branch) continua existindo)")
        return updated
    }

    public func park(_ slug: String) throws -> (trama: Trama, status: [RepoStatus]) {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let status = tramaStatus(t, predictConflict: false)
        stopServices(t.slug)
        let updated = try updateTrama(t.slug) { x in
            x.state = TramaState.parked
            x.parkedAt = nowUnix()
        }
        let dirty = status.filter { $0.changed > 0 }.map { "\($0.repo) com \($0.changed) alterado(s)" }
        try? addJournal(updated.slug, "estacionada" + (dirty.isEmpty ? "" : " · " + dirty.joined(separator: ", ")))
        return (updated, status)
    }

    public func resume(_ slug: String, rebase: Bool, noFetch: Bool = false) throws -> (trama: Trama, results: [ResumeResult]) {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        var results: [ResumeResult] = []
        if rebase {
            for name in t.repos {
                do {
                    let r = try repo(name)
                    results.append(rebaseWorktree(t, r, noFetch: noFetch))
                } catch {
                    results.append(ResumeResult(repo: name, situation: "erro", detail: errorMessage(error)))
                }
            }
        }
        let updated = try updateTrama(t.slug) { x in
            x.state = TramaState.active
            x.parkedAt = nil
        }
        var msg = "retomada"
        if rebase {
            msg += " com rebase (" + results.map { "\($0.repo): \($0.situation)" }.joined(separator: ", ") + ")"
        }
        try? addJournal(updated.slug, msg)
        return (updated, results)
    }

    private func rebaseWorktree(_ t: Trama, _ r: RepoConfig, noFetch: Bool) -> ResumeResult {
        let wt = worktreePath(t.slug, r.name)
        do {
            let lines = try Git.statusLines(wt)
            if !lines.isEmpty {
                return ResumeResult(repo: r.name, situation: "pulado", detail: "\(lines.count) arquivo(s) não commitado(s)")
            }
            let b = base(for: t, r)
            if !noFetch { try? Git.fetchBase(r.path, b) }
            let ref = Git.baseRef(wt, b)
            let behind = try Git.aheadBehind(wt, ref).behind
            if behind == 0 {
                return ResumeResult(repo: r.name, situation: "atualizado", detail: nil)
            }
            if Git.execute(wt, ["rebase", "--quiet", ref]).code != 0 {
                _ = Git.execute(wt, ["rebase", "--abort"])
                return ResumeResult(repo: r.name, situation: "conflito", detail: "o rebase em \(ref) teve conflito e foi desfeito · resolva à mão")
            }
            return ResumeResult(repo: r.name, situation: "rebase", detail: "\(behind) commit(s) de \(ref) incorporados")
        } catch {
            return ResumeResult(repo: r.name, situation: "erro", detail: errorMessage(error))
        }
    }

    public func archive(_ slug: String, force: Bool = false) throws -> Trama {
        let t = try trama(slug)
        if !force {
            let dirty = t.repos.compactMap { name -> String? in
                let wt = worktreePath(t.slug, name)
                guard Paths.exists(wt), let lines = try? Git.statusLines(wt), !lines.isEmpty else { return nil }
                return "\(name) (\(lines.count))"
            }
            if !dirty.isEmpty {
                throw TramaError("há mudanças não commitadas em \(dirty.joined(separator: ", ")) · commite ou use --forcar")
            }
        }
        for name in t.repos {
            guard let r = try? repo(name) else { continue }
            let wt = worktreePath(t.slug, name)
            guard Paths.exists(wt) else { continue }
            try Git.run(r.path, ["worktree", "remove"] + (force ? ["--force"] : []) + [wt])
        }
        stopServices(t.slug)
        clearServiceLogs(t.slug, t.repos)
        clearPreparation(t.slug, t.repos)
        let dir = tramaPath(t.slug)
        let fm = FileManager.default
        try? fm.removeItem(atPath: Paths.join(dir, "CLAUDE.md"))
        try? fm.removeItem(atPath: codeWorkspacePath(t.slug))
        if contextPath(t.slug) != nil {
            try? fm.removeItem(atPath: Paths.join(dir, "CAPSULA.md"))
            if (try? fm.contentsOfDirectory(atPath: dir))?.filter({ $0 != ".DS_Store" }).isEmpty == true {
                try? fm.removeItem(atPath: dir)
            }
        }
        let updated = try updateTrama(t.slug) { $0.state = TramaState.archived }
        try? addJournal(updated.slug, "arquivada · worktrees removidos, branch \(updated.branch) mantida")
        return updated
    }

    public func remove(_ slug: String, force: Bool = false, deleteBranches: Bool = false) throws -> Trama {
        var t = try trama(slug)
        if !t.isArchived { t = try archive(t.slug, force: force) }
        if deleteBranches {
            for name in t.repos {
                guard let r = try? repo(name), Git.branchExists(r.path, t.branch) else { continue }
                _ = Git.execute(r.path, ["branch", "-D", t.branch])
            }
        }
        try withLock {
            try saveTramas(try tramas().filter { $0.slug != t.slug })
        }
        return t
    }

    public func locate(_ folder: String) throws -> (trama: Trama, repo: RepoConfig?) {
        let notInside = TramaError("esta pasta não está dentro de uma trama")
        guard let rel = Paths.relative(Paths.real(Paths.absolute(folder)), within: Paths.real(root)), !rel.isEmpty else {
            throw notInside
        }
        let parts = rel.split(separator: "/").map(String.init)
        guard let first = parts.first, !first.hasPrefix(".") else { throw notInside }
        guard let t = try tramas().last(where: { $0.slug == first && !$0.isArchived }) else { throw notInside }
        if parts.count > 1, t.repos.contains(parts[1]), let r = try? repo(parts[1]) {
            return (t, r)
        }
        return (t, nil)
    }
}

extension Workspace {
    public func baseCandidates(repos names: [String], excluding branch: String? = nil) throws -> [String] {
        let repos = try resolveRepos(names)
        let lists = repos.map { r -> Set<String> in
            let local = (try? Git.run(r.path, "for-each-ref", "--format=%(refname:short)", "refs/heads")).map {
                $0.split(separator: "\n").map(String.init)
            } ?? []
            return Set(Git.remoteBranches(r.path) + local)
        }
        guard var common = lists.first else { return [] }
        for l in lists.dropFirst() { common.formIntersection(l) }
        if let branch { common.remove(branch) }
        let preferred = Set(repos.compactMap(\.base) + [config.defaultBranch])
        return common.sorted { a, b in
            let pa = preferred.contains(a), pb = preferred.contains(b)
            return pa != pb ? pa : a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    public func setPinned(_ slug: String, _ pinned: Bool) throws {
        try withLock {
            var ts = try tramas()
            guard let i = ts.firstIndex(where: { $0.slug == slug }) else {
                throw TramaError("trama “\(slug)” não encontrada")
            }
            ts[i].pinned = pinned
            try saveTramas(ts)
        }
    }

    public func reorderTramas(_ slugs: [String]) throws {
        try withLock {
            var ts = try tramas()
            for (position, slug) in slugs.enumerated() {
                guard let i = ts.firstIndex(where: { $0.slug == slug }) else { continue }
                ts[i].order = position
            }
            try saveTramas(ts)
        }
    }

    public func setBase(_ slug: String, base: String) throws -> Trama {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let name = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TramaError("escolha uma branch de base") }
        guard name != t.branch else { throw TramaError("“\(name)” é a branch desta trama") }
        for r in mergeOrdered(t.repos) {
            guard Git.ensureRemoteBranch(r.path, name) || Git.branchExists(r.path, name) else {
                throw TramaError("\(r.name): a base “\(name)” não existe")
            }
        }
        let updated = try updateTrama(slug) { $0.base = name }
        try? addJournal(slug, "base trocada para \(name)")
        return updated
    }
}
