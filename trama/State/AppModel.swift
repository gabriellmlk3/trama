import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Hashable {
        case trama(String)
        case findings
    }

    enum NoteKind {
        case decision, pending, note, goal
    }

    @Published var state: OverallState?
    @Published var screen: Screen?
    @Published var capsule: TramaCapsule?
    @Published var findings: [Finding] = []
    @Published var findingsAt: Date?
    @Published var pullRequests: [String: [PullRequestInfo]] = [:]
    @Published var error: String?
    @Published var notice: String?
    @Published var needsSetup = false
    @Published var busy = false
    @Published var showingNewTrama = false
    @Published var resuming: LiveTrama?

    let terminals = TerminalStore()

    private var loop: Task<Void, Never>?
    private var refreshing = false
    private var knownAgents: [Agent]?

    var waitingCount: Int { activeAgents.filter { $0.isWaiting }.count }

    func start() {
        guard loop == nil else { return }
        Notifier.shared.onOpen = { [weak self] slug, path in
            guard let self else { return }
            self.select(slug)
            if !self.terminals.focus(path: path) {
                self.terminals.open(path: path, command: "claude", title: "\(Paths.name(path)) · claude")
            }
        }
        Notifier.shared.start()
        loop = Task { [weak self] in
            DispatchQueue.global(qos: .utility).async { Integration.sync() }
            await self?.refresh()
            await self?.fetchRemotes()
            await self?.refreshFindings()
            await self?.refreshPullRequests()
            var cycle = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                cycle += 1
                await self.refresh()
                if cycle % 120 == 0 { await self.fetchRemotes() }
                if cycle % 12 == 0 {
                    await self.refreshFindings()
                    await self.refreshPullRequests()
                }
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let new = try await Core.run { try $0.fullState() }
            state = new
            notifyTransitions(new)
            needsSetup = false
            if screen == nil, let first = new.tramas.first(where: { $0.isActive }) ?? new.tramas.first {
                screen = .trama(first.slug)
            }
            if let t = selectedTrama {
                await loadCapsule(t.slug)
            }
        } catch let e as TramaError where e == .notInitialized {
            needsSetup = true
        } catch {
            showError(errorMessage(error))
        }
    }

    private func notifyTransitions(_ new: OverallState) {
        let waiting = new.agents.filter { $0.isWaiting }.count
        NSApp.dockTile.badgeLabel = waiting > 0 ? String(waiting) : nil
        defer { knownAgents = new.agents }
        guard let previous = knownAgents else { return }
        for transition in agentTransitions(from: previous, to: new.agents) {
            let agent = transition.agent
            let live = new.tramas.first(where: { $0.slug == agent.trama })
            let path = live?.status(for: agent.repo)?.path ?? agent.cwd
            Notifier.shared.post(transition, tramaTitle: live?.title ?? agent.trama, path: path)
        }
    }

    func refreshFindings() async {
        guard !needsSetup else { return }
        do {
            findings = try await Core.run { try $0.findings() }
            findingsAt = Date()
        } catch {
            showError(errorMessage(error))
        }
    }

    func refreshPullRequests() async {
        guard !needsSetup, let tramas = state?.tramas.filter({ !$0.isArchived && !$0.trama.prs.isEmpty }), !tramas.isEmpty else {
            pullRequests = [:]
            return
        }
        let list = tramas.map(\.trama)
        if let result = try? await Core.run({ w in Dictionary(uniqueKeysWithValues: list.map { ($0.slug, w.pullRequestInfos($0)) }) }) {
            pullRequests = result
        }
    }

    func openPullRequests(_ slug: String, draft: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await Core.run { try $0.openPullRequests(slug, draft: draft) }
            showNotice("PRs abertos")
            if !result.warnings.isEmpty {
                showError(result.warnings.map { w in w.repo.map { "\($0): \(w.message)" } ?? w.message }.joined(separator: "\n"))
            }
            await refresh()
            await refreshPullRequests()
        } catch {
            showError(errorMessage(error))
        }
    }

    func fetchRemotes() async {
        guard !needsSetup else { return }
        _ = try? await Core.run { $0.fetchAll() }
        await refresh()
    }

    func loadCapsule(_ slug: String) async {
        if let c = try? await Core.run({ try $0.readCapsule(slug) }) {
            capsule = c
        }
    }

    func showError(_ text: String) {
        if error != text { error = text }
    }

    func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if notice == text { notice = nil }
        }
    }

    var visibleTramas: [LiveTrama] { state?.tramas.filter { !$0.isArchived } ?? [] }
    var active: [LiveTrama] { visibleTramas.filter { $0.isActive } }
    var parked: [LiveTrama] { visibleTramas.filter { $0.isParked } }
    var repos: [RepoConfig] { state?.repos ?? [] }
    var activeAgents: [Agent] { state?.agents ?? [] }

    var selectedTrama: LiveTrama? {
        guard case .trama(let slug)? = screen else { return nil }
        return state?.tramas.first(where: { $0.slug == slug })
    }

    var focusedTrama: LiveTrama? {
        if let t = selectedTrama, t.isActive { return t }
        return active.first
    }

    func agents(for slug: String) -> [Agent] {
        activeAgents.filter { $0.trama == slug }
    }

    func repo(_ name: String) -> RepoConfig? {
        repos.first(where: { $0.name == name })
    }

    func aliases(_ names: [String]) -> [String] {
        names.map { repo($0)?.alias ?? $0 }
    }

    func worktreePath(_ t: LiveTrama, _ repo: String) -> String {
        t.status(for: repo)?.path ?? (t.path + "/" + repo)
    }

    func select(_ slug: String) {
        screen = .trama(slug)
        if capsule?.trama != slug { capsule = nil }
        Task { await loadCapsule(slug) }
    }

    @discardableResult
    func perform(success: String? = nil, _ work: @escaping @Sendable (Workspace) throws -> Void) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await Core.run(work)
            if let success { showNotice(success) }
            await refresh()
            return true
        } catch {
            showError(errorMessage(error))
            return false
        }
    }

    func newTrama(_ options: NewTramaOptions, openAgents: Bool) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let result = try await Core.run { try $0.newTrama(options) }
            await refresh()
            select(result.trama.slug)
            showNotice("Trama “\(result.trama.title)” tecida")
            if !result.warnings.isEmpty {
                let lines = result.warnings.map { warning -> String in
                    guard let r = warning.repo else { return warning.message }
                    return "\(r): \(warning.message)"
                }
                showError(lines.joined(separator: "\n"))
            }
            if openAgents, let live = selectedTrama {
                openClaudeInAll(live)
            }
            return true
        } catch {
            showError(errorMessage(error))
            return false
        }
    }

    func park(_ slug: String) async {
        await perform(success: "Trama estacionada · os worktrees ficaram intactos") { _ = try $0.park(slug) }
    }

    func resume(_ slug: String, rebase: Bool) async -> [ResumeResult]? {
        busy = true
        defer { busy = false }
        do {
            let result = try await Core.run { try $0.resume(slug, rebase: rebase) }
            await refresh()
            select(slug)
            return result.results
        } catch {
            showError(errorMessage(error))
            return nil
        }
    }

    func pull(_ slug: String, _ repo: String) async {
        await perform(success: "\(repo) entrou na trama") { _ = try $0.pullRepos(slug, [repo]) }
    }

    func drop(_ slug: String, _ repo: String) async {
        await perform(success: "\(repo) saiu da trama (a branch continua)") { _ = try $0.dropRepo(slug, repo) }
    }

    func archive(_ slug: String) async {
        if await perform(success: "Trama arquivada", { _ = try $0.archive(slug) }) {
            screen = active.first.map { Screen.trama($0.slug) }
        }
    }

    func annotate(_ kind: NoteKind, _ text: String, trama slug: String) async {
        await perform { w in
            switch kind {
            case .decision: try w.addDecision(slug, author: "você", text)
            case .pending: try w.addPending(slug, text)
            case .note: try w.addJournal(slug, text)
            case .goal: try w.setGoal(slug, text)
            }
        }
        await loadCapsule(slug)
    }

    func replaceGoal(_ text: String, previous: String?, trama slug: String) async {
        await perform { w in
            if let previous, !previous.isEmpty {
                try w.addJournal(slug, "Objetivo atingido: \(previous)")
            }
            try w.setGoal(slug, text)
        }
        await loadCapsule(slug)
    }

    func completePending(_ n: Int, trama slug: String) async {
        await perform { try $0.completePending(slug, n) }
        await loadCapsule(slug)
    }

    func confirmHandoff(_ n: Int, trama slug: String) async {
        await perform { _ = try $0.confirmHandoffs(slug, to: nil, number: n) }
        await loadCapsule(slug)
    }

    func setTramaContext(_ slug: String, _ path: String?) async {
        let ok = await perform(success: path == nil ? "Voltou ao contexto padrão" : "Repositório de contexto da trama atualizado") { _ = try $0.setTramaContext(slug, path) }
        if ok { await loadCapsule(slug) }
    }

    func sync(_ slug: String) async {
        await perform(success: "Cápsula commitada no repositório de contexto") { _ = try $0.syncCapsule(slug) }
    }

    func commit(_ slug: String, repo: String, paths: [String], message: String) async -> Bool {
        await perform(success: "Commit feito em \(repo)") { _ = try $0.commitChanges(slug, repo: repo, paths: paths, message: message) }
    }

    func resolve(_ finding: Finding) async {
        let ok: Bool
        switch finding.type {
        case FindingType.editOnBase, FindingType.forgottenChange:
            guard let repo = finding.repo, let slug = finding.suggestedTrama else { return }
            ok = await perform(success: "Mudanças levadas para a trama") { try $0.adoptChanges(repo, into: slug) }
        case FindingType.merged:
            guard let repo = finding.repo else { return }
            ok = await perform(success: "Branches integradas apagadas") { _ = try $0.cleanMerged(repo) }
        default:
            return
        }
        if ok { await refreshFindings() }
    }

    func openClaudeInAll(_ t: LiveTrama, target: ClaudeTarget = .current, scope: AgentScope = .current) {
        switch scope {
        case .single:
            let extra = t.repos.map { worktreePath(t, $0) }
            openClaude(path: t.path, repo: t.title, target: target, extraDirs: extra)
        case .perRepo:
            for r in t.repos {
                openClaude(path: worktreePath(t, r), repo: r, target: target)
            }
        }
    }

    func openClaude(path: String, repo: String, target: ClaudeTarget = .current, extraDirs: [String] = []) {
        switch target {
        case .cli:
            let command = (["claude"] + extraDirs.flatMap { ["--add-dir", shellQuoted($0)] }).joined(separator: " ")
            terminals.open(path: path, command: command, title: "\(repo) · claude")
        case .desktop:
            guard let url = ClaudeTarget.desktopURL(folder: path), NSWorkspace.shared.open(url) else {
                showError("Não consegui abrir o Claude Desktop. Ele está instalado?")
                return
            }
        }
    }

    func setup(context: String?, repos: [String], hooks: Bool, command: Bool) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await Core.inBackground {
                let w = try Workspace.configure(context: context)
                var failures: [String] = []
                for p in repos {
                    do {
                        try w.addRepo(p)
                    } catch {
                        failures.append(errorMessage(error))
                    }
                }
                if command { try Integration.installCommand() }
                if hooks { try Integration.installHooks() }
                if !failures.isEmpty { throw TramaError(failures.joined(separator: "\n")) }
            }
            await refresh()
            await refreshFindings()
            return true
        } catch {
            showError(errorMessage(error))
            await refresh()
            return false
        }
    }

    func setContext(_ path: String) async {
        busy = true
        defer { busy = false }
        do {
            try await Core.inBackground { _ = try Workspace.configure(context: path) }
            showNotice("Repositório de contexto atualizado")
            await refresh()
        } catch {
            showError(errorMessage(error))
        }
    }

    func setDefaultBranch(_ branch: String) async {
        await perform(success: "Branch padrão atualizada") { w in try w.setDefaultBranch(branch) }
    }

    func addRepos(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        await perform(success: "Repositórios cadastrados") { w in
            var failures: [String] = []
            for p in paths {
                do {
                    try w.addRepo(p)
                } catch {
                    failures.append(errorMessage(error))
                }
            }
            if failures.count == paths.count { throw TramaError(failures.joined(separator: "\n")) }
        }
    }

    func setRecipe(_ name: String, copy: [String], run: [String]) async {
        await perform(success: "Receita de \(name) salva") { _ = try $0.setRecipe(name, copy: copy, run: run) }
    }

    func merge(_ source: LiveTrama, into target: LiveTrama, allowConflicts: Bool = false) async {
        busy = true
        defer { busy = false }
        do {
            let results = try await Core.run { try $0.mergeTrama(from: source.slug, into: target.slug, allowConflicts: allowConflicts) }
            await refresh()
            let lines = results.map { "\($0.repo): \($0.situation)" + ($0.detail.map { " · " + $0 } ?? "") }
            if allowConflicts, results.contains(where: { $0.situation == "conflito" }) {
                showNotice("Merge com conflitos · resolva na aba Git")
            } else if results.allSatisfy({ $0.situation == "mesclado" || $0.situation == "atualizado" }) {
                showNotice("“\(source.title)” entrou em “\(target.title)”")
            } else {
                showError(lines.joined(separator: "\n"))
            }
        } catch {
            showError(errorMessage(error))
        }
    }

    func mergeWorktree(_ repo: String, from source: String, into target: String, label: String, allowConflicts: Bool = false) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await Core.run { try $0.mergeWorktrees(repo: repo, from: source, into: target, allowConflicts: allowConflicts) }
            await refresh()
            if result.situation == "conflito" {
                showNotice("Merge em \(label) com conflitos · resolva abaixo")
            } else if result.situation == "mesclado" || result.situation == "atualizado" {
                showNotice("Merge em \(label): \(result.detail ?? result.situation)")
            } else {
                showError("\(label): \(result.detail ?? result.situation)")
            }
        } catch {
            showError(errorMessage(error))
        }
    }

    func concludeMerge(_ repo: String, worktree: String) async -> Bool {
        await perform(success: "Merge concluído em \(repo)") { _ = try $0.concludeMerge(repo: repo, worktree: worktree) }
    }

    func abortMerge(_ repo: String, worktree: String) async -> Bool {
        await perform(success: "Merge abortado em \(repo)") { try $0.abortMerge(repo: repo, worktree: worktree) }
    }

    func acceptSide(_ repo: String, worktree: String, file: String, side: ConflictSide) async -> Bool {
        await perform { try $0.acceptSide(repo: repo, worktree: worktree, file: file, side: side) }
    }

    func saveResolution(_ repo: String, worktree: String, file: String, content: String) async -> Bool {
        await perform(success: "\(file) resolvido") { try $0.saveResolution(repo: repo, worktree: worktree, file: file, content: content) }
    }

    func setEditor(_ name: String, _ editor: String) async {
        await perform { _ = try $0.setEditor(name, editor) }
    }

    func openInEditor(_ slug: String, repos: [String]) async {
        for name in repos {
            do {
                let launch = try await Core.run { try $0.editorLaunch(slug, repo: name) }
                try Terminal.open(launch.path, withApp: launch.app)
            } catch {
                showError("\(name): \(errorMessage(error))")
            }
        }
    }

    func setServices(_ name: String, _ services: [ServiceConfig]) async {
        await perform(success: "Serviços de \(name) salvos") { _ = try $0.setServices(name, services) }
    }

    func setMergeRank(_ name: String, _ rank: Int) async {
        await perform { _ = try $0.setMergeRank(name, rank) }
    }

    func startServices(_ slug: String, repo: String) async {
        await perform { _ = try $0.startServices(slug, repo: repo) }
    }

    func stopServices(_ slug: String, repo: String) async {
        await perform { $0.stopServices(slug, repo: repo) }
    }

    func prepare(_ slug: String, _ repo: String) async {
        await perform(success: "Preparando \(repo)…") { _ = try $0.prepare(slug, repo) }
    }

    func removeRepo(_ name: String) async {
        await perform(success: "\(name) saiu do cadastro") { _ = try $0.removeRepo(name) }
    }
}
